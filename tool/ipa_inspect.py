#!/usr/bin/env python3
"""Reads the signing facts of an iOS app bundle: the library behind tool/verify_ipa.py.

Pure reading, standard library only (plus the `openssl` command for the one thing the standard
library cannot do, a CMS signature check). No Xcode tools, no macOS: it runs on Linux and on the
macOS runner, so the same code is tested here and used in CI. It never reads, creates or needs a
private key, a certificate with a private key or an Apple credential: it only reads what a signed
app carries publicly (the code signature, the embedded provisioning profile and the certificates in
them).

What it can establish from the files alone:
  - the structure and the hashes of a code signature (CodeDirectory, entitlements, requirements,
    CodeResources, the page hashes of the executable) against the files that are actually present;
  - that the CMS signatures of the code signature and of the provisioning profile are
    cryptographically valid for the certificate they carry (`openssl cms -verify -noverify`);
  - the signer certificate: subject, issuer, validity, SHA-1 and SHA-256 fingerprints.

What it cannot establish without a real signed IPA and the Apple trust anchors, and does not claim:
  - that the certificate chain leads to an Apple root and is not revoked;
  - that App Store Connect, or a device, accepts the app.
"""
import hashlib
import os
import plistlib
import re
import shutil
import struct
import subprocess
import tempfile

# ---- ASN.1 / BER (enough for CMS and X.509; indefinite lengths included) ---------------------


class Asn1Error(Exception):
    pass


class Node(object):
    __slots__ = ("data", "tag", "cls", "constructed", "start", "vstart", "vend", "end", "_kids")

    def __init__(self, data, tag, cls, constructed, start, vstart, vend, end):
        self.data, self.tag, self.cls, self.constructed = data, tag, cls, constructed
        self.start, self.vstart, self.vend, self.end = start, vstart, vend, end
        self._kids = None

    @property
    def raw(self):
        return self.data[self.start:self.end]

    @property
    def value(self):
        return self.data[self.vstart:self.vend]

    @property
    def children(self):
        if self._kids is None:
            self._kids = parse_all(self.data, self.vstart, self.vend) if self.constructed else []
        return self._kids


def parse_node(data, off, limit):
    if off + 2 > limit:
        raise Asn1Error("truncated element at %d" % off)
    first = data[off]
    cls, constructed, tag = first >> 6, bool(first & 0x20), first & 0x1F
    pos = off + 1
    if tag == 0x1F:
        tag = 0
        while True:
            if pos >= limit:
                raise Asn1Error("truncated tag")
            b = data[pos]
            pos += 1
            tag = (tag << 7) | (b & 0x7F)
            if not b & 0x80:
                break
    if pos >= limit:
        raise Asn1Error("truncated length")
    lb = data[pos]
    pos += 1
    if lb == 0x80:  # indefinite: children up to the end-of-contents marker
        if not constructed:
            raise Asn1Error("indefinite length on a primitive element")
        vstart, cur = pos, pos
        while True:
            if cur + 2 > limit:
                raise Asn1Error("unterminated indefinite-length element")
            if data[cur] == 0 and data[cur + 1] == 0:
                return Node(data, tag, cls, constructed, off, vstart, cur, cur + 2)
            cur = parse_node(data, cur, limit).end
    if lb & 0x80:
        n = lb & 0x7F
        if n == 0 or n > 4 or pos + n > limit:
            raise Asn1Error("bad length encoding")
        length = int.from_bytes(data[pos:pos + n], "big")
        pos += n
    else:
        length = lb
    if pos + length > limit:
        raise Asn1Error("element runs past its container")
    return Node(data, tag, cls, constructed, off, pos, pos + length, pos + length)


def parse_all(data, off, limit):
    out = []
    while off < limit:
        node = parse_node(data, off, limit)
        out.append(node)
        off = node.end
    return out


def parse_der(data):
    node = parse_node(data, 0, len(data))
    return node


def oid_str(node):
    v = node.value
    if not v:
        raise Asn1Error("empty OID")
    parts = [v[0] // 40, v[0] % 40]
    acc = 0
    for b in v[1:]:
        acc = (acc << 7) | (b & 0x7F)
        if not b & 0x80:
            parts.append(acc)
            acc = 0
    return ".".join(str(p) for p in parts)


def octets(node):
    """Content of an OCTET STRING, including the constructed (BER segmented) form."""
    if not node.constructed:
        return node.value
    return b"".join(octets(c) for c in node.children)


def asn_text(node):
    try:
        return node.value.decode("utf-8")
    except UnicodeDecodeError:
        return node.value.decode("latin-1")


def asn_time(node):
    t = asn_text(node)
    m = re.match(r"^(\d{2}|\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?Z$", t)
    if not m:
        raise Asn1Error("unreadable time '%s'" % t)
    y = m.group(1)
    year = int(y) + (2000 if int(y) < 50 else 1900) if len(y) == 2 else int(y)
    return "%04d-%s-%sT%s:%s:%sZ" % (year, m.group(2), m.group(3), m.group(4), m.group(5), m.group(6) or "00")


ATTR_NAMES = {"2.5.4.3": "CN", "2.5.4.11": "OU", "2.5.4.10": "O", "2.5.4.6": "C",
              "0.9.2342.19200300.100.1.1": "UID", "2.5.4.5": "serialNumber"}


def name_dict(node):
    """Distinguished name -> {attr: [values]} (a Name is SEQUENCE OF SET OF SEQUENCE{oid, value})."""
    out = {}
    for rdn in node.children:
        for atv in rdn.children:
            kids = atv.children
            key = ATTR_NAMES.get(oid_str(kids[0]), oid_str(kids[0]))
            out.setdefault(key, []).append(asn_text(kids[1]))
    return out


def parse_certificate(der):
    cert = parse_der(der)
    tbs = cert.children[0]
    kids = tbs.children
    i = 1 if kids[0].cls == 2 else 0  # skip [0] version
    info = {
        "der": der,
        "serial": kids[i].value.hex(),
        "issuer_der": kids[i + 2].raw,
        "issuer": name_dict(kids[i + 2]),
        "not_before": asn_time(kids[i + 3].children[0]),
        "not_after": asn_time(kids[i + 3].children[1]),
        "subject": name_dict(kids[i + 4]),
        "sha1": hashlib.sha1(der).hexdigest(),
        "sha256": hashlib.sha256(der).hexdigest(),
    }
    return info


OID_SIGNED_DATA = "1.2.840.113549.1.7.2"


OID_SHA256_FAMILY = {"2.16.840.1.101.3.4.2.1": "sha256", "2.16.840.1.101.3.4.2.2": "sha384",
                     "2.16.840.1.101.3.4.2.3": "sha512"}


def parse_cms(blob):
    """CMS SignedData -> {content, certs[], signer, digest_oid} (BER/DER). Fail closed: exactly one
    SignerInfo, identified by issuer and serial number, matching exactly one certificate of the set,
    and no bytes after the structure. Signature validity is checked separately, by openssl."""
    root = parse_der(blob)
    if root.end != len(blob):
        raise Asn1Error("%d unexpected byte(s) after the CMS structure" % (len(blob) - root.end))
    kids = root.children
    if len(kids) < 2 or oid_str(kids[0]) != OID_SIGNED_DATA:
        raise Asn1Error("not a CMS SignedData")
    sd = kids[1].children[0]
    parts = sd.children
    encap = parts[2]
    content = None
    if len(encap.children) > 1:
        content = octets(encap.children[1].children[0])
    certs, signer_infos = [], None
    for p in parts[3:]:
        if p.cls == 2 and p.tag == 0:  # [0] IMPLICIT certificates
            certs = [parse_certificate(c.raw) for c in p.children if c.tag == 16 and c.cls == 0]
        elif p.cls == 0 and p.tag == 17:  # SET OF SignerInfo
            signer_infos = p
    if signer_infos is None or len(signer_infos.children) != 1:
        raise Asn1Error("the CMS structure must have exactly one signer")
    si = signer_infos.children[0].children
    sid = si[1]
    if not (sid.cls == 0 and sid.tag == 16):
        raise Asn1Error("the signer is not identified by issuer and serial number")
    issuer_der, serial = sid.children[0].raw, sid.children[1].value.hex()
    matches = [c for c in certs if c["serial"] == serial and c["issuer_der"] == issuer_der]
    if len(matches) != 1:
        raise Asn1Error("the signer matches %d certificate(s) of the set (exactly one required)" % len(matches))
    return {"content": content, "certs": certs, "signer": matches[0], "digest_oid": oid_str(si[2].children[0])}


OID_APPLE_CDHASHES = "1.2.840.113635.100.9.1"


def cms_cdhashes(blob):
    """The cdhashes that the CMS signature of a code signature binds (Apple signed attribute
    1.2.840.113635.100.9.1, a plist with a `cdhashes` array), as a list of bytes; None if absent.
    This is what ties the alternate CodeDirectories to the signature: the CMS message digest only
    covers the primary one."""
    root = parse_der(blob)
    sd = root.children[1].children[0]
    sets = [p for p in sd.children if p.cls == 0 and p.tag == 17]
    if not sets or not sets[-1].children:
        return None
    found = []
    for k in sets[-1].children[0].children:
        if k.cls == 2 and k.tag == 0:  # [0] IMPLICIT signedAttrs
            for attr in k.children:
                if oid_str(attr.children[0]) == OID_APPLE_CDHASHES:
                    plist = plistlib.loads(octets(attr.children[1].children[0]))
                    found.append([bytes(h) for h in plist.get("cdhashes", [])])
    if len(found) > 1:
        raise Asn1Error("the cdhashes attribute appears more than once")
    return found[0] if found else None


# ---- openssl (the one external dependency: CMS signature validity) -----------------------------


def openssl_path():
    for cand in (os.environ.get("OPENSSL"), shutil.which("openssl"), "/opt/homebrew/opt/openssl@3/bin/openssl",
                 "/usr/local/opt/openssl@3/bin/openssl"):
        if cand and os.path.exists(cand):
            return cand
    return None


def pem_certs_to_der(text):
    import base64
    out = []
    for m in re.finditer(r"-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----", text, re.S):
        out.append(base64.b64decode("".join(m.group(1).split())))
    return out


def cms_verify(cms_der, detached=None):
    """Check the CMS signature with openssl. -> {"ok", "why", "signer_sha256", "content"}.

    It verifies the signature of the signer certificate over the content (embedded, or `detached`).
    The chain to a trust anchor is NOT checked here (see chain_problems). The certificate openssl
    actually used and the content it actually verified are returned, so that callers never rely on
    their own, possibly different, reading of the structure."""
    res = {"ok": False, "why": "", "signer_sha256": None, "content": None}
    exe = openssl_path()
    if not exe:
        res["why"] = "openssl not found (set OPENSSL=/path/to/openssl)"
        return res
    with tempfile.TemporaryDirectory() as td:
        sig, signer_pem, out_file = (os.path.join(td, n) for n in ("sig.der", "signer.pem", "content.out"))
        with open(sig, "wb") as f:
            f.write(cms_der)
        cmd = [exe, "cms", "-verify", "-inform", "DER", "-in", sig, "-noverify", "-signer", signer_pem, "-out", out_file]
        if detached is not None:
            content = os.path.join(td, "content.bin")
            with open(content, "wb") as f:
                f.write(detached)
            cmd += ["-content", content, "-binary"]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        except (OSError, subprocess.TimeoutExpired) as e:
            res["why"] = "openssl could not run: %s" % e
            return res
        if r.returncode != 0:
            res["why"] = (r.stderr.strip().splitlines() or ["openssl cms -verify failed"])[-1]
            return res
        try:
            with open(signer_pem, "r") as f:
                ders = pem_certs_to_der(f.read())
            if len(ders) != 1:
                res["why"] = "openssl reported %d signer certificates (exactly one required)" % len(ders)
                return res
            res["signer_sha256"] = hashlib.sha256(ders[0]).hexdigest()
            if detached is None:
                with open(out_file, "rb") as f:
                    res["content"] = f.read()
        except OSError as e:
            res["why"] = "openssl output unreadable: %s" % e
            return res
    res["ok"] = True
    return res


def cms_signature_valid(cms_der, detached=None):
    """(True, '') / (False, reason); see cms_verify."""
    r = cms_verify(cms_der, detached)
    return r["ok"], r["why"]


def chain_problems(leaf_der, extra_der, anchors_pem_path, at_epoch):
    """[] when `leaf_der` chains to a certificate in the trust-anchor file (a signature chain with
    the extra certificates as intermediates, judged at `at_epoch`); otherwise the reason. The
    anchor file is supplied by the operator: nothing here knows or ships an Apple root."""
    exe = openssl_path()
    if not exe:
        return ["openssl not found"]
    with tempfile.TemporaryDirectory() as td:
        leaf, untrusted = os.path.join(td, "leaf.der"), os.path.join(td, "untrusted.pem")
        with open(leaf, "wb") as f:
            f.write(leaf_der)
        pem = subprocess.run([exe, "x509", "-inform", "DER", "-in", leaf, "-outform", "PEM"], capture_output=True)
        leaf_pem = os.path.join(td, "leaf.pem")
        with open(leaf_pem, "wb") as f:
            f.write(pem.stdout)
        with open(untrusted, "wb") as f:
            for i, der_bytes in enumerate(extra_der):
                p = os.path.join(td, "x%d.der" % i)
                with open(p, "wb") as g:
                    g.write(der_bytes)
                f.write(subprocess.run([exe, "x509", "-inform", "DER", "-in", p, "-outform", "PEM"], capture_output=True).stdout)
        empty = os.path.join(td, "no-system-roots")
        os.makedirs(empty)  # an empty -CApath keeps the system's default roots out of the decision
        cmd = [exe, "verify", "-CAfile", anchors_pem_path, "-CApath", empty, "-attime", str(at_epoch)]
        if os.path.getsize(untrusted):
            cmd += ["-untrusted", untrusted]
        r = subprocess.run(cmd + [leaf_pem], capture_output=True, text=True)
        if r.returncode == 0 and "OK" in r.stdout:
            return []
        return [(r.stdout + r.stderr).strip().replace("\n", "; ")[:300] or "openssl verify failed"]


# ---- Mach-O and the code signature --------------------------------------------------------------

FAT_MAGIC, FAT_MAGIC_64 = 0xCAFEBABE, 0xCAFEBABF
MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64, LC_CODE_SIGNATURE = 0x19, 0x1D
CPU_ARM64 = 0x0100000C
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CSMAGIC_REQUIREMENTS = 0xFADE0C01
CSMAGIC_ENTITLEMENTS = 0xFADE7171
CSMAGIC_DER_ENTITLEMENTS = 0xFADE7172
CSMAGIC_BLOBWRAPPER = 0xFADE0B01
CS_ADHOC, CS_LINKER_SIGNED = 0x2, 0x20000
HASH_TYPES = {1: ("sha1", 20), 2: ("sha256", 32), 3: ("sha256", 20), 4: ("sha384", 48)}
SLOT_INFO, SLOT_REQUIREMENTS, SLOT_RESOURCES, SLOT_ENTITLEMENTS, SLOT_DER_ENTITLEMENTS = 1, 2, 3, 5, 7
SLOT_CODEDIRECTORY, SLOT_CMS = 0, 0x10000
SLOT_ALT_CODEDIRECTORIES = tuple(range(0x1000, 0x1005))


class MachOError(Exception):
    pass


def macho_slices(data):
    """[(cputype, offset, size)] for a thin or fat (32/64-bit fat header) Mach-O."""
    if len(data) < 8:
        raise MachOError("too small to be a Mach-O file")
    magic_be = struct.unpack(">I", data[:4])[0]
    if magic_be in (FAT_MAGIC, FAT_MAGIC_64):
        n = struct.unpack(">I", data[4:8])[0]
        size_each = 20 if magic_be == FAT_MAGIC else 32
        out = []
        for i in range(n):
            rec = data[8 + i * size_each:8 + (i + 1) * size_each]
            if len(rec) < size_each:
                raise MachOError("truncated fat header")
            if magic_be == FAT_MAGIC:
                cpu, _sub, off, size, _al = struct.unpack(">iIIII", rec)
            else:
                cpu, _sub, off, size, _al, _res = struct.unpack(">iIQQII", rec)
            if off + size > len(data) or size < 32:
                raise MachOError("fat slice lies outside the file")
            out.append((cpu & 0xFFFFFFFF, off, size))
        if not out:
            raise MachOError("fat file without any architecture")
        return out
    if struct.unpack("<I", data[:4])[0] == MH_MAGIC_64:
        cpu = struct.unpack("<I", data[4:8])[0]
        return [(cpu, 0, len(data))]
    raise MachOError("not a 64-bit Mach-O or fat file")


def is_macho(path):
    try:
        with open(path, "rb") as f:
            head = f.read(4)
    except OSError:
        return False
    if len(head) < 4:
        return False
    # Any Mach-O or fat header, 32 or 64 bit, either byte order: code that this tool cannot read must
    # be reported as unreadable, never skipped as "not code".
    return head in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf", b"\xbe\xba\xfe\xca", b"\xbf\xba\xfe\xca",
                    b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe")


def parse_macho_slice(data, off, size):
    """Load commands of a 64-bit little-endian slice. Offsets are relative to the slice."""
    sl = data[off:off + size]
    if len(sl) < 32 or struct.unpack("<I", sl[:4])[0] != MH_MAGIC_64:
        raise MachOError("slice is not a 64-bit Mach-O")
    cpu, _sub, filetype, ncmds, sizeofcmds, flags = struct.unpack("<IIIIII", sl[4:28])
    cmds, pos, codesig, linkedit = [], 32, None, None
    for _ in range(ncmds):
        if pos + 8 > len(sl):
            raise MachOError("load commands run past the file")
        cmd, csize = struct.unpack("<II", sl[pos:pos + 8])
        if csize < 8 or pos + csize > len(sl):
            raise MachOError("bad load command size")
        cmds.append((cmd, pos, csize))
        if cmd == LC_CODE_SIGNATURE and csize >= 16:
            codesig = struct.unpack("<II", sl[pos + 8:pos + 16]) + (pos,)
        elif cmd == LC_SEGMENT_64 and sl[pos + 8:pos + 24].rstrip(b"\0") == b"__LINKEDIT":
            linkedit = pos
        pos += csize
    return {"cpu": cpu, "filetype": filetype, "ncmds": ncmds, "sizeofcmds": sizeofcmds, "cmds": cmds,
            "codesig": codesig, "linkedit": linkedit, "cmds_end": 32 + sizeofcmds, "size": len(sl)}


def parse_superblob(blob):
    """-> {slot: bytes}; checks the magic and that every blob lies inside the SuperBlob."""
    if len(blob) < 12:
        raise MachOError("code signature too small")
    magic, length, count = struct.unpack(">III", blob[:12])
    if magic != CSMAGIC_EMBEDDED_SIGNATURE:
        raise MachOError("code signature magic is 0x%08x" % magic)
    if length > len(blob) or 12 + count * 8 > length:
        raise MachOError("code signature SuperBlob is truncated")
    slots = {}
    entries = [struct.unpack(">II", blob[12 + i * 8:20 + i * 8]) for i in range(count)]
    offsets = sorted(o for _, o in entries) + [length]
    if len({t for t, _o in entries}) != len(entries):
        raise MachOError("the code signature lists a blob type twice")
    for t, o in entries:
        if o + 8 > length:
            raise MachOError("blob offset outside the SuperBlob")
        _m, blen = struct.unpack(">II", blob[o:o + 8])
        if o + blen > length:
            raise MachOError("blob 0x%x runs past the SuperBlob" % t)
        slots[t] = blob[o:o + blen]
    return slots


def parse_codedirectory(cd):
    if len(cd) < 44:
        raise MachOError("CodeDirectory too small")
    (magic, length, version, flags, hash_off, ident_off, n_special, n_code, code_limit, hash_size,
     hash_type, platform, page_size) = struct.unpack(">IIIIIIIIIBBBB", cd[:40])
    if magic != CSMAGIC_CODEDIRECTORY:
        raise MachOError("CodeDirectory magic is 0x%08x" % magic)
    team_off = struct.unpack(">I", cd[48:52])[0] if version >= 0x20200 and len(cd) >= 52 else 0
    if version >= 0x20300 and len(cd) >= 64:
        code_limit64 = struct.unpack(">Q", cd[56:64])[0]
        if code_limit == 0 and code_limit64:
            code_limit = code_limit64
    hname, hlen = HASH_TYPES.get(hash_type, (None, hash_size))
    if length != len(cd):
        raise MachOError("CodeDirectory length field (%d) differs from its size (%d)" % (length, len(cd)))
    if hname is None or hash_size != hlen:
        raise MachOError("CodeDirectory hash type %d with hash size %d is not supported" % (hash_type, hash_size))

    def cstr(o):
        if not o or o >= len(cd):
            return ""
        e = cd.find(b"\0", o)
        return cd[o:e if e >= 0 else len(cd)].decode("utf-8", "replace")

    return {"version": version, "flags": flags, "hash_off": hash_off, "n_special": n_special, "n_code": n_code,
            "code_limit": code_limit, "hash_size": hash_size, "hash_type": hash_type, "hash_name": hname,
            "page_size": (1 << page_size) if page_size else 0, "identifier": cstr(ident_off),
            "team_id": cstr(team_off), "raw": cd, "hash_len": hlen}


def cd_hash(cd, name):
    """The cdhash: the CodeDirectory hashed with its own algorithm, truncated to 20 bytes."""
    h = hashlib.new(name)
    h.update(cd["raw"])
    return h.digest()[:20]


def slot_hash(cd, slot):
    """Special slots count back from hash_off (slot 1 is the entry just before code slot 0)."""
    o = cd["hash_off"] - slot * cd["hash_size"]
    if slot > cd["n_special"] or o < 0:
        return None
    h = cd["raw"][o:o + cd["hash_size"]]
    return None if h == b"\0" * len(h) else h


def code_slot_problems(cd, slice_data, signature_offset=None):
    """Re-hash every page of the executable up to code_limit and compare with the CodeDirectory.
    The hashed range must be exactly everything before the signature: a shorter range would leave
    the rest of the file unprotected."""
    out = []
    if signature_offset is not None and cd["code_limit"] != signature_offset:
        return ["CodeDirectory covers %d bytes but the signature starts at %d (part of the file is not protected)"
                % (cd["code_limit"], signature_offset)]
    if not cd["hash_name"] or not cd["page_size"]:
        return ["CodeDirectory hash type %s / page size %s is not supported" % (cd["hash_type"], cd["page_size"])]
    limit = cd["code_limit"]
    if limit > len(slice_data):
        return ["CodeDirectory code limit %d is beyond the file (%d bytes)" % (limit, len(slice_data))]
    expected_slots = (limit + cd["page_size"] - 1) // cd["page_size"]
    if expected_slots != cd["n_code"]:
        out.append("CodeDirectory has %d code slots, %d pages are needed" % (cd["n_code"], expected_slots))
        return out
    bad = 0
    for i in range(cd["n_code"]):
        page = slice_data[i * cd["page_size"]:min((i + 1) * cd["page_size"], limit)]
        want = cd["raw"][cd["hash_off"] + i * cd["hash_size"]:cd["hash_off"] + (i + 1) * cd["hash_size"]]
        got = hashlib.new(cd["hash_name"], page).digest()[:cd["hash_size"]]
        if got != want:
            bad += 1
    if bad:
        out.append("%d of %d code pages do not match their CodeDirectory hash (the binary was changed after signing)"
                   % (bad, cd["n_code"]))
    return out


def _der_entitlement_value(node):
    if node.cls != 0:
        raise Asn1Error("unexpected tag class in DER entitlements")
    if node.tag == 1:
        return node.value == b"\xff"
    if node.tag == 2:
        return int.from_bytes(node.value, "big", signed=True)
    if node.tag == 12:
        return node.value.decode("utf-8")
    if node.tag == 16:
        return [_der_entitlement_value(c) for c in node.children]
    if node.tag == 17:
        return _der_entitlement_dict(node)
    raise Asn1Error("unsupported value type %d in DER entitlements" % node.tag)


def _der_entitlement_dict(node):
    out = {}
    for pair in node.children:
        kv = pair.children
        if pair.tag != 16 or len(kv) != 2 or kv[0].tag != 12:
            raise Asn1Error("malformed entry in DER entitlements")
        key = kv[0].value.decode("utf-8")
        if key in out:
            raise Asn1Error("duplicate key %r in DER entitlements" % key)
        out[key] = _der_entitlement_value(kv[1])
    return out


def parse_der_entitlements(blob):
    """Decode the DER entitlements blob (magic 0xfade7172): [APPLICATION 16] { INTEGER 1, SET OF
    SEQUENCE { UTF8String key, value } }. The kernel enforces THESE where present, so they must be
    reconciled with the XML entitlements. The layout is from public descriptions and has not been
    checked against a real Apple-signed app (docs/IOS_SIGNING.md); anything else is an error."""
    magic, length = struct.unpack(">II", blob[:8])
    if magic != CSMAGIC_DER_ENTITLEMENTS or length != len(blob):
        raise Asn1Error("DER entitlements blob header is wrong")
    root = parse_der(blob[8:])
    if root.end != len(blob) - 8 or root.cls != 1 or root.tag != 16:
        raise Asn1Error("DER entitlements are not a single [APPLICATION 16] element")
    ver, body = root.children[0], root.children[1]
    if ver.tag != 2 or ver.value != b"\x01" or body.tag != 17:
        raise Asn1Error("unsupported DER entitlements version or layout")
    return _der_entitlement_dict(body)


def read_signature(path):
    """Everything the signature of one Mach-O file (every architecture slice) says.

    -> {"slices": [ {cpu, signed, codedirectories, entitlements, ...} ], "error": str|None}"""
    with open(path, "rb") as f:
        data = f.read()
    result = {"path": path, "slices": [], "error": None}
    try:
        sl_list = macho_slices(data)
    except MachOError as e:
        result["error"] = str(e)
        return result
    for cpu, off, size in sl_list:
        item = {"cpu": cpu, "signed": False, "problems": [], "cds": [], "entitlements": None,
                "entitlements_blob": None, "requirements_blob": None, "cms": None, "slots": {}}
        result["slices"].append(item)
        try:
            m = parse_macho_slice(data, off, size)
        except MachOError as e:
            item["problems"].append(str(e))
            continue
        item["macho"] = m
        item["data"] = data[off:off + size]
        if m["codesig"] is None:
            continue
        dataoff, datasize, _pos = m["codesig"]
        item["signed"] = True
        if dataoff + datasize > size:
            item["problems"].append("code signature lies outside the file")
            continue
        try:
            slots = parse_superblob(item["data"][dataoff:dataoff + datasize])
        except MachOError as e:
            item["problems"].append(str(e))
            continue
        item["slots"] = slots
        item["signature_offset"] = dataoff
        # Bytes between the end of the SuperBlob and the end of its reserved area are not checked: real
        # Apple and Flutter signatures leave stale non-zero data there (seen in the accepted CI artifact).
        # They are neither executed nor hashed. Bytes AFTER the reserved area would be unprotected code
        # space, and are refused.
        if any(item["data"][dataoff + datasize:]):
            item["problems"].append("non-zero bytes follow the code signature at the end of the file")
        for key in (SLOT_CODEDIRECTORY,) + SLOT_ALT_CODEDIRECTORIES:
            if key in slots:
                try:
                    item["cds"].append((key, parse_codedirectory(slots[key])))
                except MachOError as e:
                    item["problems"].append(str(e))
        if SLOT_ENTITLEMENTS in slots:
            item["entitlements_blob"] = slots[SLOT_ENTITLEMENTS]
            blob = slots[SLOT_ENTITLEMENTS]
            try:
                if struct.unpack(">I", blob[:4])[0] != CSMAGIC_ENTITLEMENTS:
                    raise ValueError("entitlements blob magic")
                item["entitlements"] = plistlib.loads(blob[8:])
            except Exception as e:  # unreadable plist is a finding, not a crash
                item["problems"].append("entitlements blob is unreadable: %s" % e)
        item["der_entitlements_blob"] = slots.get(SLOT_DER_ENTITLEMENTS)
        item["der_entitlements"] = None
        if item["der_entitlements_blob"] is not None:
            try:
                item["der_entitlements"] = parse_der_entitlements(item["der_entitlements_blob"])
            except (Asn1Error, IndexError, ValueError, struct.error) as e:
                item["problems"].append("DER entitlements are unreadable: %s" % e)
        if SLOT_REQUIREMENTS in slots:
            item["requirements_blob"] = slots[SLOT_REQUIREMENTS]
        if SLOT_CMS in slots:
            blob = slots[SLOT_CMS]
            if struct.unpack(">I", blob[:4])[0] != CSMAGIC_BLOBWRAPPER:
                item["problems"].append("signature blob magic is not a CMS wrapper")
            else:
                item["cms"] = blob[8:]
    return result


def strip_view(slice_data, m):
    """The part of a slice that signing does not change: used to prove that two binaries are the
    same code, one of them signed. Returns (normalised header+commands, body offset, body bytes).

    Signing (a) adds an LC_CODE_SIGNATURE command into the padding after the load commands,
    (b) appends the signature to __LINKEDIT and (c) grows the __LINKEDIT sizes. Everything else
    (all other commands, all section and symbol bytes) stays identical."""
    hdr = bytearray(slice_data[:32])
    struct.pack_into("<II", hdr, 16, 0, 0)  # ncmds / sizeofcmds differ by exactly the added command
    parts = [bytes(hdr)]
    for cmd, pos, csize in m["cmds"]:
        if cmd == LC_CODE_SIGNATURE:
            continue
        body = bytearray(slice_data[pos:pos + csize])
        if cmd == LC_SEGMENT_64 and m["linkedit"] == pos:
            struct.pack_into("<Q", body, 32, 0)  # vmsize
            struct.pack_into("<Q", body, 48, 0)  # filesize
        parts.append(bytes(body))
    end = m["codesig"][0] if m["codesig"] else len(slice_data)
    return b"".join(parts), m["cmds_end"], slice_data[m["cmds_end"]:end]


def same_code(unsigned, signed):
    """(True, '') when `signed` is `unsigned` plus a signature; otherwise (False, why). Both are
    paths to Mach-O files; every architecture slice is compared."""
    with open(unsigned, "rb") as f:
        da = f.read()
    with open(signed, "rb") as f:
        db = f.read()
    try:
        sa, sb = macho_slices(da), macho_slices(db)
    except MachOError as e:
        return False, str(e)
    if [s[0] for s in sa] != [s[0] for s in sb]:
        return False, "the architectures differ"
    for (cpu, oa, za), (_c, ob, zb) in zip(sa, sb):
        try:
            ma, mb = parse_macho_slice(da, oa, za), parse_macho_slice(db, ob, zb)
        except MachOError as e:
            return False, str(e)
        ca, _ea, _ba = strip_view(da[oa:oa + za], ma)
        cb, _eb, _bb = strip_view(db[ob:ob + zb], mb)
        if ca != cb:
            return False, "the load commands differ beyond the code signature"
        a_slice, b_slice = da[oa:oa + za], db[ob:ob + zb]
        a_end = ma["codesig"][0] if ma["codesig"] else len(a_slice)
        b_end = mb["codesig"][0] if mb["codesig"] else len(b_slice)
        start = max(ma["cmds_end"], mb["cmds_end"])
        if any(a_slice[ma["cmds_end"]:start]) or any(b_slice[mb["cmds_end"]:start]):
            return False, "bytes after the load commands differ"
        common = min(a_end, b_end)
        if a_slice[start:common] != b_slice[start:common]:
            return False, "the executable content differs (it was recompiled or modified, not only signed)"
        if any(a_slice[common:a_end]) or any(b_slice[common:b_end]):
            return False, "the content before the signature differs in length"
        if mb["codesig"] and any(b_slice[mb["codesig"][0] + mb["codesig"][1]:]):
            return False, "data follows the signature"
    return True, ""


# ---- bundle resources: CodeResources ---------------------------------------------------------


def read_code_resources(app_dir):
    path = os.path.join(app_dir, "_CodeSignature", "CodeResources")
    if not os.path.isfile(path):
        return None
    with open(path, "rb") as f:
        return plistlib.loads(f.read())


def file_hash(path, name):
    h = hashlib.new(name)
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.digest()


def bundle_files(app_dir):
    """Relative paths of every regular file and symlink in a bundle (nested bundles included)."""
    out = []
    for base, dirs, files in os.walk(app_dir, followlinks=False):
        for name in files:
            out.append(os.path.relpath(os.path.join(base, name), app_dir).replace(os.sep, "/"))
        for name in list(dirs):
            full = os.path.join(base, name)
            if os.path.islink(full):
                out.append(os.path.relpath(full, app_dir).replace(os.sep, "/"))
                dirs.remove(name)
    return sorted(out)


def code_resources_problems(app_dir, exe_name, nested_prefixes=()):
    """Every file listed in CodeResources exists and has the listed hash, and every file of the
    bundle is either listed, omitted by a rule, the signed executable, or inside a nested bundle."""
    res = read_code_resources(app_dir)
    if res is None:
        return ["no _CodeSignature/CodeResources"], 0
    problems, checked = [], 0
    files2 = res.get("files2") or {}
    rules2 = res.get("rules2") or {}
    for rel in sorted(files2):
        parts = rel.split("/")
        if not rel or rel.startswith("/") or "\\" in rel or "\0" in rel or ".." in parts:
            problems.append("CodeResources lists the unsafe path %r" % rel)
    if problems:
        return problems, 0
    for rel, entry in sorted(files2.items()):
        if isinstance(entry, dict) and entry.get("symlink") is not None:
            full = os.path.join(app_dir, rel)
            if not os.path.islink(full) or os.readlink(full) != entry["symlink"]:
                problems.append("symlink %s differs from CodeResources" % rel)
            continue
        if isinstance(entry, dict) and "cdhash" in entry:
            continue  # a nested bundle: its cdhash is compared by the caller (code_resources_cdhashes)
        want = entry.get("hash2") if isinstance(entry, dict) else None
        full = os.path.join(app_dir, rel)
        if not os.path.isfile(full):
            if isinstance(entry, dict) and entry.get("optional"):
                continue
            problems.append("%s is listed in CodeResources but missing" % rel)
            continue
        checked += 1
        if want is None:
            problems.append("%s has no SHA-256 entry in CodeResources" % rel)
        elif file_hash(full, "sha256") != bytes(want):
            problems.append("%s was modified after signing" % rel)
    compiled = []
    for pattern, rule in rules2.items():
        omit = bool(isinstance(rule, dict) and rule.get("omit"))
        weight = rule.get("weight", 1.0) if isinstance(rule, dict) else 1.0
        optional = bool(isinstance(rule, dict) and rule.get("optional"))
        try:
            compiled.append((re.compile(re.sub(r"^\(\?i\)", "", pattern), re.I if pattern.startswith("(?i)") else 0),
                             omit, float(weight), optional))
        except re.error:
            continue
    for rel in bundle_files(app_dir):
        if rel == "_CodeSignature/CodeResources" or rel == exe_name or rel in files2:
            continue
        if rel.startswith("_CodeSignature/"):
            problems.append("%s is an unexpected file in _CodeSignature" % rel)
            continue
        if any(rel.startswith(p) for p in nested_prefixes):
            continue
        best = None
        for rx, omit, weight, optional in compiled:
            if rx.search(rel) and (best is None or weight > best[1]):
                best = (omit, weight, optional)
        if best is not None and best[0]:
            continue
        problems.append("%s is in the bundle but not covered by CodeResources (added after signing)" % rel)
    return problems, checked


def code_resources_cdhashes(app_dir):
    """[(path, cdhash bytes)] for the nested-bundle entries of CodeResources."""
    res = read_code_resources(app_dir) or {}
    return [(k, bytes(v["cdhash"])) for k, v in sorted((res.get("files2") or {}).items())
            if isinstance(v, dict) and "cdhash" in v]


# ---- provisioning profile -------------------------------------------------------------------


def read_profile(path):
    """-> {plist, signer, certs, signature_valid, signature_error}. The profile is a CMS SignedData
    whose content is an XML plist. The plist is the content that openssl VERIFIED, and the signer is
    required to be the certificate openssl used, so a structure read differently by this parser and
    by openssl cannot make the result look better than it is."""
    with open(path, "rb") as f:
        blob = f.read()
    cms = parse_cms(blob)
    v = cms_verify(blob)
    err = v["why"]
    if v["ok"] and v["signer_sha256"] != cms["signer"]["sha256"]:
        v["ok"], err = False, "the signer certificate read from the structure is not the one openssl verified"
    if v["content"] is None:
        raise Asn1Error(err or "the provisioning profile carries no verified content")
    plist = plistlib.loads(v["content"])
    return {"plist": plist, "signer": cms["signer"], "certs": cms["certs"], "signature_valid": v["ok"],
            "signature_error": err}


def profile_type(plist):
    """'development' | 'ad-hoc' | 'enterprise' | 'app-store' from the profile's own fields."""
    ent = plist.get("Entitlements") or {}
    if plist.get("ProvisionsAllDevices"):
        return "enterprise"
    if plist.get("ProvisionedDevices"):
        return "ad-hoc" if not ent.get("get-task-allow") else "development"
    return "development" if ent.get("get-task-allow") else "app-store"


def team_from_application_identifier(app_id):
    return app_id.split(".", 1)[0] if app_id and "." in app_id else ""
