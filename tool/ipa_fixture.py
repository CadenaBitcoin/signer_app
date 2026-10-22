#!/usr/bin/env python3
"""SYNTHETIC iOS app and IPA fixtures for testing tool/verify_ipa.py. TEST TOOLING ONLY.

  tool/ipa_fixture.py certs  DIR
  tool/ipa_fixture.py unsigned DIR --env staging|production [--executable-seed N]
  tool/ipa_fixture.py sign   UNSIGNED_APP_DIR OUT.ipa --certs DIR --team TEAMID [--mutate KIND]...
  tool/ipa_fixture.py manifest UNSIGNED_APP_DIR OUT.json --env staging|production

Everything is made up: a throwaway root/intermediate/leaf certificate chain with names that say
"Synthetic" (they do not imitate Apple), a fake provisioning profile signed by a throwaway
signer, tiny fake Mach-O files, and a signer that writes the same structures Apple's codesign
writes (LC_CODE_SIGNATURE, SuperBlob, CodeDirectory, entitlements, CodeResources, a CMS signature
with the cdhashes attribute). No Apple credential, certificate or profile is read or needed, and
nothing here is a signature Apple or a device would accept. It exists so that the verifier can be
tested without a real signed IPA, including on real unsigned build output (`sign` accepts any
unsigned Runner.app directory, even one that already carries ad-hoc signatures).

The key material is generated into the directory you give and is meant to be deleted with it.
"""
import argparse
import copy
import datetime
import hashlib
import json
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import zipfile

sys.dont_write_bytecode = True  # importing the tool/ modules must not leave __pycache__ in the repository
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ipa_inspect as I  # noqa: E402
import build_manifest as BM  # noqa: E402

ISSUER_CN = "Synthetic Test Intermediate CA"
MUT = set()  # mutations of the sign command, read by the signing helpers
MUT_VICTIM = [None]  # path of the certificate that "spoof-signer" pretends to be
LEAF_CN_PREFIX = "Synthetic Distribution:"


def die(text):
    print("ipa_fixture: %s" % text, file=sys.stderr)
    sys.exit(2)


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, **kw)
    if r.returncode != 0:
        die("%s failed: %s" % (" ".join(cmd[:3]), r.stderr.decode("utf-8", "replace").strip()))
    return r.stdout


def openssl():
    exe = I.openssl_path()
    if not exe:
        die("openssl not found")
    return exe


# ---- DER writing (the little that CMS needs) ----------------------------------------------------


def der(tag, content):
    n = len(content)
    if n < 0x80:
        head = bytes([tag, n])
    else:
        b = n.to_bytes((n.bit_length() + 7) // 8, "big")
        head = bytes([tag, 0x80 | len(b)]) + b
    return head + content


def d_seq(*items):
    return der(0x30, b"".join(items))


def d_set(*items):
    return der(0x31, b"".join(items))


def d_oid(text):
    p = [int(x) for x in text.split(".")]
    out = bytes([p[0] * 40 + p[1]])
    for v in p[2:]:
        chunk = [v & 0x7F]
        v >>= 7
        while v:
            chunk.append(0x80 | (v & 0x7F))
            v >>= 7
        out += bytes(reversed(chunk))
    return der(0x06, out)


def d_octet(b):
    return der(0x04, b)


def d_int(value_bytes):
    return der(0x02, value_bytes)


def d_value(v):
    if isinstance(v, bool):
        return der(0x01, b"\xff" if v else b"\x00")
    if isinstance(v, int):
        return der(0x02, v.to_bytes(max(1, (v.bit_length() + 8) // 8), "big", signed=True))
    if isinstance(v, str):
        return der(0x0C, v.encode())
    if isinstance(v, list):
        return d_seq(*[d_value(x) for x in v])
    if isinstance(v, dict):
        return d_dict(v)
    raise TypeError(type(v))


def d_dict(d):
    return d_set(*[d_seq(der(0x0C, k.encode()), d_value(v)) for k, v in sorted(d.items())])


def der_entitlements_blob(ents):
    body = der(0x70, d_int(b"\x01") + d_dict(ents))
    return struct.pack(">II", I.CSMAGIC_DER_ENTITLEMENTS, 8 + len(body)) + body


OID_SHA256 = "2.16.840.1.101.3.4.2.1"
OID_RSA = "1.2.840.113549.1.1.1"
OID_DATA = "1.2.840.113549.1.7.1"


def alg(oid, null=True):
    return d_seq(d_oid(oid), der(0x05, b"") if null else b"")


def rsa_sign(key, data):
    return run([openssl(), "dgst", "-sha256", "-sign", key], input=data)


def spki_hash(cert_der):
    """SHA-1 of the subject public key bit string (a subjectKeyIdentifier by method 1)."""
    tbs = I.parse_der(cert_der).children[0]
    kids = tbs.children
    i = 1 if kids[0].cls == 2 else 0
    spki = kids[i + 5]
    return hashlib.sha1(spki.children[1].value[1:]).digest()


def cms_for_codedirectory(cd0, cdhashes, leaf_pem, key, chain_pems):
    """A CMS SignedData over CodeDirectory `cd0` with Apple's cdhashes attribute, signed with `key`."""
    leaf = pem_to_der(leaf_pem)
    cert = I.parse_certificate(leaf)
    plist = plistlib.dumps({"cdhashes": list(cdhashes)}, fmt=plistlib.FMT_XML)
    attrs = [
        d_seq(d_oid("1.2.840.113549.1.9.3"), d_set(d_oid(OID_DATA))),
        d_seq(d_oid("1.2.840.113549.1.9.4"), d_set(d_octet(hashlib.sha256(cd0).digest()))),
        d_seq(d_oid(I.OID_APPLE_CDHASHES), d_set(d_octet(plist))),
    ]
    attrs.sort()
    attr_body = b"".join(attrs)
    signature = rsa_sign(key, d_set(*attrs))
    sid = d_seq(cert["issuer_der"], d_int(bytes.fromhex(cert["serial"])))
    if "spoof-signer" in MUT:
        sid = der(0x80, spki_hash(leaf))  # [0] SubjectKeyIdentifier instead of issuer and serial
    signer_info = d_seq(
        d_int(b"\x01"),
        sid,
        alg(OID_SHA256, null=False),
        der(0xA0, attr_body),
        alg(OID_RSA),
        d_octet(signature),
    )
    certs = b"".join([leaf] + [pem_to_der(c) for c in chain_pems])
    if "spoof-signer" in MUT:  # the certificate of the pinned identity comes first, the real signer after it
        certs = pem_to_der(MUT_VICTIM[0]) + certs
    signed = d_seq(d_int(b"\x01"), d_set(alg(OID_SHA256, null=False)), d_seq(d_oid(OID_DATA)),
                   der(0xA0, certs), d_set(signer_info))
    return d_seq(d_oid(I.OID_SIGNED_DATA), der(0xA0, signed))


def pem_to_der(path):
    return run([openssl(), "x509", "-in", path, "-outform", "DER"])


# ---- certificates -------------------------------------------------------------------------------


def make_certs(directory, team="SYNTH12345"):
    os.makedirs(directory, exist_ok=True)
    ssl = openssl()

    def key(name):
        run([ssl, "genrsa", "-out", os.path.join(directory, name + ".key"), "2048"])

    def ca(name, cn, issuer=None):
        key(name)
        csr = os.path.join(directory, name + ".csr")
        run([ssl, "req", "-new", "-key", os.path.join(directory, name + ".key"), "-subj", "/CN=%s/O=Synthetic Test/C=XX" % cn, "-out", csr])
        ext = os.path.join(directory, name + ".ext")
        with open(ext, "w") as f:
            f.write("basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n")
        sign_with = ["-signkey", os.path.join(directory, name + ".key")] if issuer is None else [
            "-CA", os.path.join(directory, issuer + ".crt"), "-CAkey", os.path.join(directory, issuer + ".key"), "-CAcreateserial"]
        run([ssl, "x509", "-req", "-in", csr, "-days", "3650", "-extfile", ext, "-out", os.path.join(directory, name + ".crt")] + sign_with)

    def leaf(name, cn, ou, issuer="intermediate"):
        key(name)
        csr = os.path.join(directory, name + ".csr")
        run([ssl, "req", "-new", "-key", os.path.join(directory, name + ".key"), "-subj", "/CN=%s/OU=%s/O=Synthetic Test/C=XX" % (cn, ou), "-out", csr])
        ext = os.path.join(directory, name + ".ext")
        with open(ext, "w") as f:
            f.write("basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=codeSigning\nsubjectKeyIdentifier=hash\n")
        run([ssl, "x509", "-req", "-in", csr, "-days", "825", "-extfile", ext, "-CA", os.path.join(directory, issuer + ".crt"),
             "-CAkey", os.path.join(directory, issuer + ".key"), "-CAcreateserial", "-out", os.path.join(directory, name + ".crt")])

    ca("root", "Synthetic Test Root CA")
    ca("intermediate", ISSUER_CN, issuer="root")
    leaf("leaf", "%s Test Org (%s)" % (LEAF_CN_PREFIX, team), team)
    leaf("leaf2", "%s Other Org (OTHER12345)" % LEAF_CN_PREFIX, "OTHER12345")
    leaf("profile_signer", "Synthetic Profile Signer", "none")
    print("certs written to %s" % directory)


def fingerprint(path):
    return I.parse_certificate(pem_to_der(path))["sha256"]


# ---- synthetic Mach-O ---------------------------------------------------------------------------


def pseudo(seed, n):
    out, i = b"", 0
    while len(out) < n:
        out += hashlib.sha256(("%s:%d" % (seed, i)).encode()).digest()
        i += 1
    return out[:n]


def make_macho(seed, filetype=2, text_len=0x3C00, minos=14 << 16, cpu=0x0100000C):
    """A tiny but structurally valid arm64 Mach-O with __TEXT, __LINKEDIT and a build version."""
    sect = (b"__text".ljust(16, b"\0") + b"__TEXT".ljust(16, b"\0") + struct.pack("<QQIIIIIIII", 0x100000400, text_len, 0x400, 2, 0, 0, 0x80000400, 0, 0, 0))
    text = struct.pack("<II16sQQQQiiII", 0x19, 72 + 80, b"__TEXT".ljust(16, b"\0"), 0x100000000, 0x4000, 0, 0x4000, 5, 5, 1, 0) + sect
    link = struct.pack("<II16sQQQQiiII", 0x19, 72, b"__LINKEDIT".ljust(16, b"\0"), 0x100004000, 0x4000, 0x4000, 0x100, 1, 1, 0, 0)
    build = struct.pack("<IIIIII", 0x32, 24, 2, minos, 26 << 16 | 2 << 8, 0)
    cmds = text + link + build
    header = struct.pack("<IIIIIIII", 0xFEEDFACF, cpu, 0, filetype, 3, len(cmds), 0x200085, 0)
    body = header + cmds
    body = body.ljust(0x400, b"\0") + pseudo(seed + "t", text_len)
    body = body.ljust(0x4000, b"\0") + pseudo(seed + "l", 0x100)
    return body


def macho_free_space(sl, m):
    offs = []
    for cmd, pos, size in m["cmds"]:
        if cmd == I.LC_SEGMENT_64:
            nsects = struct.unpack("<I", sl[pos + 64:pos + 68])[0]
            for i in range(nsects):
                base = pos + 72 + i * 80
                off = struct.unpack("<I", sl[base + 48:base + 52])[0]
                if off:
                    offs.append(off)
    return (min(offs) if offs else len(sl)) - m["cmds_end"]


def strip_slice(sl, m):
    if m["codesig"] is None:
        return sl
    dataoff, datasize, pos = m["codesig"]
    csize = [c for c in m["cmds"] if c[1] == pos][0][2]
    body = bytearray(sl[:dataoff])
    rest = bytearray()
    for cmd, p, size in m["cmds"]:
        if p != pos:
            rest += sl[p:p + size]
    start = 32
    body[start:start + len(rest) + csize] = bytes(rest) + b"\0" * csize
    ncmds, sizeofcmds = struct.unpack("<II", sl[16:24])
    struct.pack_into("<II", body, 16, ncmds - 1, sizeofcmds - csize)
    m2 = I.parse_macho_slice(bytes(body), 0, len(body))
    if m2["linkedit"] is not None:
        le = m2["linkedit"]
        fileoff = struct.unpack("<Q", body[le + 40:le + 48])[0]
        struct.pack_into("<Q", body, le + 48, len(body) - fileoff)
    return bytes(body)


def codedirectory(ident, team, hash_name, code, text_limit, specials, flags, main):
    htype = {"sha1": 1, "sha256": 2}[hash_name]
    hs = 20 if htype == 1 else 32
    n_special = 7
    hashed = code[:4096] if "short-codelimit" in MUT else code
    ident_b = ident.encode() + b"\0"
    team_b = (team.encode() + b"\0") if team else b""
    ident_off = 88
    team_off = ident_off + len(ident_b) if team else 0
    hash_off = ident_off + len(ident_b) + len(team_b) + n_special * hs
    page = 4096
    n_code = (len(hashed) + page - 1) // page
    entries = b""
    for slot in range(n_special, 0, -1):
        h = specials.get(slot)
        entries += (hashlib.new(hash_name, h).digest() if h is not None else b"\0" * hs)
    codes = b"".join(hashlib.new(hash_name, hashed[i * page:(i + 1) * page]).digest() for i in range(n_code))
    length = hash_off + len(codes)
    head = struct.pack(">IIIIIIIIIBBBB", I.CSMAGIC_CODEDIRECTORY, length, 0x20400, flags, hash_off, ident_off, n_special,
                       n_code, len(hashed), hs, htype, 0, 12)
    head += struct.pack(">IIIIQQQQ", 0, 0, team_off, 0, 0, 0, text_limit, 1 if main else 0)
    assert len(head) == 88, len(head)
    return head + ident_b + team_b + entries + codes


def sign_slice(sl, ident, team, specials, ents_xml, dual, adhoc, certs, main):
    m = I.parse_macho_slice(sl, 0, len(sl))
    if m["codesig"]:
        sl = strip_slice(sl, m)
        m = I.parse_macho_slice(sl, 0, len(sl))
    if macho_free_space(sl, m) < 16:
        die("no room for an LC_CODE_SIGNATURE command in %s" % ident)
    sig_off = (len(sl) + 15) & ~15
    sig_size = ((((sig_off + 4095) // 4096) * 52 + 16384) + 15) & ~15  # room for both hash types
    buf = bytearray(sl.ljust(sig_off, b"\0"))
    ncmds, sizeofcmds = struct.unpack("<II", buf[16:24])
    struct.pack_into("<II", buf, 16, ncmds + 1, sizeofcmds + 16)
    struct.pack_into("<IIII", buf, m["cmds_end"], I.LC_CODE_SIGNATURE, 16, sig_off, sig_size)
    le = m["linkedit"]
    fileoff = struct.unpack("<Q", buf[le + 40:le + 48])[0]
    filesize = sig_off + sig_size - fileoff
    struct.pack_into("<Q", buf, le + 32, (filesize + 0x3FFF) & ~0x3FFF)
    struct.pack_into("<Q", buf, le + 48, filesize)
    code = bytes(buf)
    text_limit = 0x4000
    flags = I.CS_ADHOC if adhoc else 0
    sp = dict(specials)
    req = struct.pack(">III", I.CSMAGIC_REQUIREMENTS, 12, 0)
    sp[2] = req
    ents_blob = der_blob = None
    if ents_xml is not None:
        ents_blob = struct.pack(">II", I.CSMAGIC_ENTITLEMENTS, 8 + len(ents_xml)) + ents_xml
        sp[5] = ents_blob
        if "no-der" not in MUT:
            ents = plistlib.loads(ents_xml)
            if "der-differs" in MUT:
                ents = dict(ents, **{"get-task-allow": True})
            der_blob = der_entitlements_blob(ents)
            sp[7] = der_blob
    blobs = {}
    algs = ["sha1", "sha256"] if dual else ["sha256"]
    cds = []
    for i, name in enumerate(algs):
        cd = codedirectory(ident, team, name, code, text_limit, sp, flags, main)
        cds.append((name, cd))
    blobs[0] = cds[0][1]
    for i, (name, cd) in enumerate(cds[1:]):
        blobs[0x1000 + i] = cd
    blobs[2] = req
    if ents_blob is not None:
        blobs[5] = ents_blob
    if der_blob is not None:
        blobs[7] = der_blob
    if adhoc:
        blobs[0x10000] = struct.pack(">II", I.CSMAGIC_BLOBWRAPPER, 8)
    else:
        cdhashes = [hashlib.new(n, cd).digest()[:20] for n, cd in cds]
        cms = cms_for_codedirectory(cds[0][1], cdhashes, certs["leaf"], certs["key"], [certs["intermediate"]])
        blobs[0x10000] = struct.pack(">II", I.CSMAGIC_BLOBWRAPPER, 8 + len(cms)) + cms
    order = sorted(blobs)
    index_len = 12 + 8 * len(order)
    pos, index, payload = index_len, b"", b""
    for t in order:
        index += struct.pack(">II", t, pos)
        payload += blobs[t]
        pos += len(blobs[t])
    superblob = struct.pack(">III", I.CSMAGIC_EMBEDDED_SIGNATURE, pos, len(order)) + index + payload
    if len(superblob) > sig_size:
        die("signature larger than the reserved %d bytes" % sig_size)
    out = code + superblob.ljust(sig_size, b"\0")
    if "padding-nonzero" in MUT:
        out = out[:-8] + b"\x01" + out[-7:]
    if "trailing-data" in MUT:
        out += b"\x01"
    return out


def sign_macho_file(path, ident, team, specials, ents_xml, dual, adhoc, certs, main):
    with open(path, "rb") as f:
        data = f.read()
    sls = I.macho_slices(data)
    signed = [sign_slice(data[o:o + s], ident, team, specials, ents_xml, dual, adhoc, certs, main) for _c, o, s in sls]
    if struct.unpack(">I", data[:4])[0] in (I.FAT_MAGIC, I.FAT_MAGIC_64):
        off, recs, placed = 0x4000, b"", []
        for (cpu, _o, _s), sl in zip(sls, signed):
            recs += struct.pack(">iIIII", cpu, 0, off, len(sl), 14)
            placed.append((off, sl))
            off = (off + len(sl) + 0x3FFF) & ~0x3FFF
        out = bytearray(struct.pack(">II", I.FAT_MAGIC, len(sls)) + recs)
        for o, sl in placed:
            out = out.ljust(o, b"\0")
            out += sl
        new = bytes(out)
    else:
        new = signed[0]
    with open(path, "wb") as f:
        f.write(new)


# ---- bundle --------------------------------------------------------------------------------------

RULES2 = {
    "^.*": True,
    "^.*\\.lproj/": {"optional": True, "weight": 1000.0},
    "^.*\\.lproj/locversion.plist$": {"omit": True, "weight": 1100.0},
    "^Base\\.lproj/": {"weight": 1010.0},
    "^Info\\.plist$": {"omit": True, "weight": 20.0},
    "^PkgInfo$": {"omit": True, "weight": 20.0},
    "^embedded\\.provisionprofile$": {"weight": 20.0},
    "^version\\.plist$": {"weight": 20.0},
    "^(.*/)?\\.DS_Store$": {"omit": True, "weight": 2000.0},
}


def write_code_resources(bundle, exe_name):
    import re
    files, files2 = {}, {}
    omit = [re.compile(p) for p, r in RULES2.items() if isinstance(r, dict) and r.get("omit")]
    for rel in I.bundle_files(bundle):
        if rel == exe_name or rel.startswith("_CodeSignature/") or any(rx.search(rel) for rx in omit):
            continue
        full = os.path.join(bundle, rel)
        if os.path.islink(full):
            files2[rel] = {"symlink": os.readlink(full)}
            continue
        with open(full, "rb") as f:
            data = f.read()
        files[rel] = hashlib.sha1(data).digest()
        files2[rel] = {"hash": hashlib.sha1(data).digest(), "hash2": hashlib.sha256(data).digest()}
    os.makedirs(os.path.join(bundle, "_CodeSignature"), exist_ok=True)
    with open(os.path.join(bundle, "_CodeSignature", "CodeResources"), "wb") as f:
        plistlib.dump({"files": files, "files2": files2, "rules": {"^.*": True}, "rules2": copy.deepcopy(RULES2)}, f)


def make_unsigned_app(directory, env, seed="1", version=None):
    ids = BM.identities(os.path.dirname(HERE), "ios")
    app_id, name = ids[env]
    _raw, vname, vbuild = BM.load_pubspec(os.path.dirname(HERE))
    app = os.path.join(directory, "Runner.app")
    os.makedirs(os.path.join(app, "Frameworks", "Flut.framework"), exist_ok=True)
    os.makedirs(os.path.join(app, "Frameworks", "App.framework", "flutter_assets"), exist_ok=True)
    os.makedirs(os.path.join(app, "Base.lproj"), exist_ok=True)
    info = {"CFBundleIdentifier": app_id, "CFBundleDisplayName": name, "CFBundleName": "signer", "CFBundleExecutable": "Runner",
            "CFBundleShortVersionString": version or vname, "CFBundleVersion": str(vbuild), "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "DTPlatformName": "iphoneos", "DTSDKName": "iphoneos26.2", "MinimumOSVersion": "14.0", "UIDeviceFamily": [1],
            "UIBackgroundModes": ["fetch"], "CFBundlePackageType": "APPL"}
    with open(os.path.join(app, "Info.plist"), "wb") as f:
        plistlib.dump(info, f, fmt=plistlib.FMT_BINARY)
    with open(os.path.join(app, "PkgInfo"), "wb") as f:
        f.write(b"APPL????")
    with open(os.path.join(app, "Runner"), "wb") as f:
        f.write(make_macho("runner" + seed))
    for fw, ident in (("Flut", "org.example.flut"), ("App", "org.example.app")):
        d = os.path.join(app, "Frameworks", fw + ".framework")
        with open(os.path.join(d, "Info.plist"), "wb") as f:
            plistlib.dump({"CFBundleIdentifier": ident, "CFBundleExecutable": fw, "CFBundlePackageType": "FMWK",
                           "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"}, f)
        with open(os.path.join(d, fw), "wb") as f:
            f.write(make_macho(fw + seed, filetype=6))
    with open(os.path.join(app, "Frameworks", "App.framework", "flutter_assets", "AssetManifest.json"), "w") as f:
        f.write('{"assets": []}\n')
    with open(os.path.join(app, "Frameworks", "libswift_Synthetic.dylib"), "wb") as f:
        f.write(make_macho("dylib" + seed, filetype=6))
    with open(os.path.join(app, "Base.lproj", "Main.storyboardc"), "wb") as f:
        f.write(b"compiled-storyboard-placeholder")
    print("synthetic unsigned app: %s (%s, %s)" % (app, env, app_id))
    return app


def make_profile(path, certs, team, bundle_id, kind, expires, ents, platform=("iOS",)):
    data = {"Name": "Synthetic profile", "UUID": "00000000-0000-4000-8000-000000000001", "TeamIdentifier": [team],
            "TeamName": "Synthetic Test Org", "ApplicationIdentifierPrefix": [team], "Platform": list(platform),
            "CreationDate": expires - datetime.timedelta(days=365), "ExpirationDate": expires, "Version": 1,
            "DeveloperCertificates": [pem_to_der(certs["leaf_for_profile"])], "Entitlements": ents}
    if kind == "ad-hoc":
        data["ProvisionedDevices"] = ["00000000-0000000000000000"]
    plist = plistlib.dumps(data, fmt=plistlib.FMT_XML)
    tmp = path + ".plist"
    with open(tmp, "wb") as f:
        f.write(plist)
    out = run([openssl(), "cms", "-sign", "-nodetach", "-binary", "-outform", "DER", "-signer", certs["profile_signer_crt"],
               "-inkey", certs["profile_signer_key"], "-certfile", certs["intermediate"], "-in", tmp])
    os.remove(tmp)
    with open(path, "wb") as f:
        f.write(out)


def sign_app(app_in, out_ipa, certdir, team, mutations):
    mut = set(mutations)
    MUT.clear()
    MUT.update(mut)
    tmp = out_ipa + ".work"
    if os.path.exists(tmp):
        shutil.rmtree(tmp)
    app = os.path.join(tmp, "Payload", "Runner.app")
    shutil.copytree(app_in, app, symlinks=True)
    with open(os.path.join(app, "Info.plist"), "rb") as f:
        info = plistlib.load(f)
    bundle_id = info["CFBundleIdentifier"]
    if "wrong-bundle" in mut:
        info["CFBundleIdentifier"] = bundle_id = bundle_id + ".x"
        with open(os.path.join(app, "Info.plist"), "wb") as f:
            plistlib.dump(info, f)
    if "wrong-version" in mut:
        info["CFBundleShortVersionString"] = "9.9.9"
        with open(os.path.join(app, "Info.plist"), "wb") as f:
            plistlib.dump(info, f)
    c = lambda n: os.path.join(certdir, n)
    MUT_VICTIM[0] = c("leaf.crt")
    leaf_name = "leaf2" if ("other-team-cert" in mut or "spoof-signer" in mut) else "leaf"
    if "x86-main" in mut:
        with open(os.path.join(app, "Runner"), "wb") as f:
            f.write(make_macho("x86", cpu=0x01000007))
    if "plugin" in mut:
        os.makedirs(os.path.join(app, "PlugIns", "Share.appex"))
        with open(os.path.join(app, "PlugIns", "Share.appex", "Info.plist"), "wb") as f:
            plistlib.dump({"CFBundleIdentifier": bundle_id + ".share"}, f)
    if "exe-traversal" in mut:
        info["CFBundleExecutable"] = "../Runner"
        with open(os.path.join(app, "Info.plist"), "wb") as f:
            plistlib.dump(info, f)
    certs = {"leaf": c(leaf_name + ".crt"), "key": c(leaf_name + ".key"), "intermediate": c("intermediate.crt"),
             "profile_signer_crt": c("profile_signer.crt"), "profile_signer_key": c("profile_signer.key"),
             "leaf_for_profile": c("leaf2.crt" if "profile-without-cert" in mut else "leaf.crt")}
    if "spoof-signer" in mut:
        certs["leaf_for_profile"] = c("leaf.crt")
    adhoc_main = "adhoc-main" in mut
    dual = "dual" in mut
    # nested bundles and standalone dylibs first
    fw_dir = os.path.join(app, "Frameworks")
    for fw in sorted(os.listdir(fw_dir)):
        full = os.path.join(fw_dir, fw)
        if os.path.isdir(full) and fw.endswith(".framework"):
            exe = fw[:-len(".framework")]
            shutil.rmtree(os.path.join(full, "_CodeSignature"), ignore_errors=True)
            nested_certs = dict(certs)
            if "framework-other-signer" in mut and exe == "Flut":
                nested_certs.update({"leaf": c("leaf2.crt"), "key": c("leaf2.key")})
            if "framework-unsigned" in mut and exe == "Flut":
                write_code_resources(full, exe)
                continue
            write_code_resources(full, exe)
            with open(os.path.join(full, "Info.plist"), "rb") as f:
                info_b = f.read()
            with open(os.path.join(full, "_CodeSignature", "CodeResources"), "rb") as f:
                res_b = f.read()
            nteam = "OTHER12345" if ("framework-other-signer" in mut and exe == "Flut") else team
            sign_macho_file(os.path.join(full, exe), "org.example." + exe.lower(), nteam, {1: info_b, 3: res_b}, None, dual,
                            False, nested_certs, False)
        elif fw.endswith(".dylib"):
            sign_macho_file(full, fw[:-len(".dylib")], team, {}, None, dual, False, certs, False)
    # the profile
    exp = datetime.datetime(2027, 6, 1)
    if "expired-profile" in mut:
        exp = datetime.datetime(2020, 1, 1)
    if "near-expiry-profile" in mut:
        exp = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(days=5)
    pents = {"application-identifier": "%s.%s" % (team, bundle_id), "com.apple.developer.team-identifier": team,
             "get-task-allow": False, "keychain-access-groups": ["%s.*" % team], "beta-reports-active": True,
             "aps-environment": "production"}
    platform = ["tvOS"] if "profile-platform-tvos" in mut else ["iOS"]
    if "wildcard-profile" in mut:
        pents["application-identifier"] = "%s.*" % team
    if "dev-profile" in mut:
        pents["get-task-allow"] = True
    if "wrong-team-profile" in mut:
        pents["application-identifier"] = "OTHER12345.%s" % bundle_id
    kind = "ad-hoc" if "adhoc-profile" in mut else "app-store"
    if "no-profile" not in mut:
        make_profile(os.path.join(app, "embedded.mobileprovision"), certs, "OTHER12345" if "wrong-team-profile" in mut else team,
                     bundle_id, kind, exp, pents, platform)
    # the app's seal, then the executable
    if "unsigned-macho32" in mut:
        with open(os.path.join(app, "Frameworks", "old32.dylib"), "wb") as f:
            f.write(b"\xce\xfa\xed\xfe" + b"\0" * 4096)
    write_code_resources(app, "Runner")
    extra_entries = {}
    flut_exe = os.path.join(app, "Frameworks", "Flut.framework", "Flut")
    if "cr-dotdot-key" in mut:
        with open(os.path.join(app, "PkgInfo"), "rb") as f:
            extra_entries["Frameworks/../PkgInfo"] = {"hash2": hashlib.sha256(f.read()).digest()}
    if "cr-cdhash-ok" in mut or "cr-cdhash-bad" in mut:
        sl = I.read_signature(flut_exe)["slices"][0]
        good = I.cd_hash(sl["cds"][0][1], sl["cds"][0][1]["hash_name"])
        extra_entries["Frameworks/Flut.framework/"] = {"cdhash": good if "cr-cdhash-ok" in mut else b"\0" * 20}
    if extra_entries:
        crp = os.path.join(app, "_CodeSignature", "CodeResources")
        with open(crp, "rb") as f:
            cr = plistlib.load(f)
        cr["files2"].update(extra_entries)
        with open(crp, "wb") as f:
            plistlib.dump(cr, f)
    if "stale-seal" in mut:  # a nested binary is signed again after the app was sealed
        fw = os.path.dirname(flut_exe)
        with open(os.path.join(fw, "Info.plist"), "rb") as f:
            fi = f.read()
        with open(os.path.join(fw, "_CodeSignature", "CodeResources"), "rb") as f:
            fr = f.read()
        sign_macho_file(flut_exe, "org.example.flut-again", team, {1: fi, 3: fr}, None, dual, False, certs, False)
    ents = {"application-identifier": "%s.%s" % (team, bundle_id), "com.apple.developer.team-identifier": team,
            "get-task-allow": "get-task-allow" in mut, "keychain-access-groups": ["%s.%s" % (team, bundle_id)],
            "beta-reports-active": True, "aps-environment": "production"}
    if "ent-not-in-profile" in mut:
        ents["com.apple.developer.associated-domains"] = ["applinks:example.org"]
    if "aps-development" in mut:
        ents["aps-environment"] = "development"
    ents_xml = plistlib.dumps(ents, fmt=plistlib.FMT_XML)
    with open(os.path.join(app, "Info.plist"), "rb") as f:
        info_b = f.read()
    with open(os.path.join(app, "_CodeSignature", "CodeResources"), "rb") as f:
        res_b = f.read()
    sign_macho_file(os.path.join(app, "Runner"), bundle_id, team if "wrong-cd-team" not in mut else "OTHER12345",
                    {1: info_b, 3: res_b}, None if "no-entitlements" in mut else ents_xml, dual, adhoc_main, certs, True)
    # tampering AFTER signing
    if "tamper-exe" in mut:
        p = os.path.join(app, "Runner")
        with open(p, "r+b") as f:
            f.seek(0x1000)
            b = f.read(1)
            f.seek(0x1000)
            f.write(bytes([b[0] ^ 0xFF]))
    if "tamper-resource" in mut:
        with open(os.path.join(app, "Frameworks", "App.framework", "flutter_assets", "AssetManifest.json"), "a") as f:
            f.write("tampered\n")
    if "tamper-info" in mut:
        info["CFBundleDisplayName"] = info["CFBundleDisplayName"] + " X"
        with open(os.path.join(app, "Info.plist"), "wb") as f:
            plistlib.dump(info, f)
    if "add-file" in mut:
        with open(os.path.join(app, "injected.dylib"), "wb") as f:
            f.write(b"payload")
    if "tamper-cms" in mut:
        p = os.path.join(app, "Runner")
        with open(p, "rb") as f:
            data = bytearray(f.read())
        sig = I.read_signature(p)["slices"][0]
        cms = sig["cms"]
        off = bytes(data).find(cms[-40:])
        data[off + 10] ^= 0x01
        with open(p, "wb") as f:
            f.write(bytes(data))
    if "tamper-altcd" in mut:
        p = os.path.join(app, "Runner")
        with open(p, "rb") as f:
            data = bytearray(f.read())
        sig = I.read_signature(p)["slices"][0]
        alt = sig["slots"][0x1000]
        off = bytes(data).find(alt[:40])
        data[off + 12] ^= 0x01  # flags field of the alternate CodeDirectory
        with open(p, "wb") as f:
            f.write(bytes(data))
    if "cs-extra-file" in mut:
        for d in (app, os.path.join(app, "Frameworks", "Flut.framework")):
            with open(os.path.join(d, "_CodeSignature", "evil.bin"), "wb") as f:
                f.write(b"payload")
    if "garbage-info-plist" in mut:
        with open(os.path.join(app, "Info.plist"), "wb") as f:
            f.write(b"\x00garbage, not a plist\xff")
    if "truncated-profile" in mut:
        pp = os.path.join(app, "embedded.mobileprovision")
        with open(pp, "r+b") as f:
            f.truncate(100)
    if "tamper-profile" in mut:
        pp = os.path.join(app, "embedded.mobileprovision")
        with open(pp, "rb") as f:
            data = f.read()
        data = data.replace(b"Synthetic profile", b"Synthetic PROFILE")
        with open(pp, "wb") as f:
            f.write(data)
    if "tamper-der" in mut:
        p = os.path.join(app, "Runner")
        with open(p, "rb") as f:
            data = f.read()
        off = data.find(b"\xfa\xde\x71\x72")
        data = bytearray(data)
        i = data.find(b"production", off)
        data[i] = ord("P")
        with open(p, "wb") as f:
            f.write(bytes(data))
    if "tamper-late-byte" in mut:
        p = os.path.join(app, "Runner")
        with open(p, "r+b") as f:
            f.seek(0x2000)
            b = f.read(1)
            f.seek(0x2000)
            f.write(bytes([b[0] ^ 0xFF]))
    # the archive
    if os.path.exists(out_ipa):
        os.remove(out_ipa)
    with zipfile.ZipFile(out_ipa, "w", zipfile.ZIP_DEFLATED) as z:
        for base, dirs, files in os.walk(os.path.join(tmp, "Payload")):
            for fn in sorted(files):
                full = os.path.join(base, fn)
                z.write(full, os.path.relpath(full, tmp))
        if "two-apps" in mut:
            z.writestr("Payload/Other.app/Info.plist", b"x")
        if "traversal" in mut:
            z.writestr("Payload/Runner.app/../../evil.txt", b"x")
    shutil.rmtree(tmp)
    print("synthetic IPA: %s (mutations: %s)" % (out_ipa, ",".join(sorted(mut)) or "none"))


def make_manifest(app_dir, out, env):
    ids = BM.identities(os.path.dirname(HERE), "ios")
    with open(os.path.join(app_dir, "Info.plist"), "rb") as f:
        info = plistlib.load(f)
    m = {"schema": BM.SCHEMA, "environment": env, "platform": "ios", "kind": "ios-app",
         "application": {"id": ids[env][0], "display_name": ids[env][1]},
         "version": {"platform_version_name": info["CFBundleShortVersionString"], "platform_build_number": int(info["CFBundleVersion"])},
         "signing": {"status": "unsigned"}, "source": {"commit": "0123456789abcdef0123456789abcdef01234567"},
         "ci": {"build_id": "1.1:synthetic"},
         "artifact": {"digest_kind": "directory-manifest", "sha256": BM.tree_digest(app_dir)}}
    with open(out, "w") as f:
        json.dump(m, f, indent=2)
    print("synthetic manifest: %s" % out)


def main(argv):
    ap = argparse.ArgumentParser(prog="ipa_fixture.py", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd")
    a = sub.add_parser("certs")
    a.add_argument("dir")
    a.add_argument("--team", default="SYNTH12345")
    b = sub.add_parser("unsigned")
    b.add_argument("dir")
    b.add_argument("--env", required=True, choices=["staging", "production"])
    b.add_argument("--seed", default="1")
    c = sub.add_parser("sign")
    c.add_argument("app")
    c.add_argument("out")
    c.add_argument("--certs", required=True)
    c.add_argument("--team", required=True)
    c.add_argument("--mutate", action="append", default=[])
    d = sub.add_parser("manifest")
    d.add_argument("app")
    d.add_argument("out")
    d.add_argument("--env", required=True, choices=["staging", "production"])
    e = sub.add_parser("fingerprint")
    e.add_argument("pem")
    args = ap.parse_args(argv[1:])
    if args.cmd == "certs":
        make_certs(args.dir, args.team)
    elif args.cmd == "unsigned":
        make_unsigned_app(args.dir, args.env, args.seed)
    elif args.cmd == "sign":
        sign_app(args.app, args.out, args.certs, args.team, args.mutate)
    elif args.cmd == "manifest":
        make_manifest(args.app, args.out, args.env)
    elif args.cmd == "fingerprint":
        print(fingerprint(args.pem))
    else:
        ap.print_help()
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
