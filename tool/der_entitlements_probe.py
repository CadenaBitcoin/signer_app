#!/usr/bin/env python3
"""Shows what the DER entitlements of a signed Mach-O file REALLY look like, assuming no layout.

    tool/der_entitlements_probe.py [--synthetic-identifier IDENTIFIER] [--dump-file] FILE...

For every architecture slice of every FILE that carries a code signature it prints (lines start with `PROBE`):
  - the identity of the file (name, size, SHA-256) and of each CodeDirectory (identifier, hash algorithm, flags, version, page
    size, team), with the special-slot seals of the XML entitlements (slot 5) and of the DER entitlements (slot 7) next to the
    hash of the blobs actually present;
  - the DER blob: whether it is present, its size and SHA-256, its header and an ASN.1 outline that assumes nothing (classes,
    tags, lengths and the small BOOLEAN and INTEGER values);
  - the verdict of the CURRENT parser (tool/ipa_inspect.py parse_der_entitlements) and, if it decoded the blob, whether the
    decoded values equal the XML entitlements. That parser is the SUBJECT of the investigation: it may legitimately refuse
    genuine Apple data, and its verdict NEVER decides whether evidence was obtained.

EVIDENCE STATUS. For every FILE it prints one line
`PROBE-RESULT der_evidence=complete|INCOMPLETE parser=accepted|rejected|n/a fixture_dump=not-requested|complete|INCOMPLETE`,
preceded, when something is missing, by one `PROBE-EVIDENCE-PROBLEM` line per reason for the evidence and one
`PROBE-DUMP-PROBLEM` line per reason for the dump. The two are SEPARATE:
  - der_evidence: whether the DER structure and seals were inspected successfully. It is COMPLETE only if
      1. the file is readable as Mach-O and every slice is signed with at least one CodeDirectory;
      2. every slice carries a DER entitlements blob (slot 7) and an XML entitlements blob (slot 5);
      3. the DER blob's container is valid (magic 0xfade7172, declared length equals the blob's length) and its body is exactly
         ONE well-formed ASN.1 element with nothing after it;
      4. every CodeDirectory's special slot 7 seals the DER blob that is present (the hash matches);
      5. every CodeDirectory's special slot 5 seals the XML entitlements blob that is present.
  - fixture_dump: whether the COMPLETE executable was actually emitted, when --dump-file asked for it. `not-requested` without
    --dump-file; `complete` only if the file was designated synthetic input, is at most 64 KiB, was read in full, and was written
    out in full (a BEGIN-FILE line with its size and SHA-256, PROBE-DATA lines, an END-FILE line); `INCOMPLETE` in every other case,
    for instance because raw output was withheld (the identifier does not match) or the file is too large. A requested dump that
    was not produced is a FAILURE of the probe, however complete the DER evidence is.
Apple's `codesign --verify` is a separate check made by tool/probe_der_entitlements.sh. Exit status: 0 only if, for every FILE,
the evidence is complete AND any requested dump is complete; 1 if either is not (everything that could be shown is still
printed); 2 for a usage error, a FILE that is not a file, or a failure of the probe itself. The existing parser's verdict is
never part of it.

STRUCTURE is always printed. RAW output (the string content of the outline, the DER bytes in hex, the XML entitlements, and
with --dump-file the whole file in base64) is an EXPLICIT, OPERATOR-GIVEN control: it is printed only with
--synthetic-identifier IDENTIFIER, and then only if every signed slice of the file has CodeDirectories whose identifier EQUALS
IDENTIFIER exactly and has no CMS signature (a disposable ad-hoc program has none; every Apple-signed application has one).
THIS DOES NOT PROVE THAT THE FILE WAS MADE BY THE DISPOSABLE PROCEDURE: whoever controls a file can give it that identifier and
leave out the CMS signature, and the identifier is only what the signer wrote into the file. The option is a safeguard against
printing raw bytes of a REAL application by mistake, not an authentication of the input; the caller (the script) is what makes
the input disposable, by building and signing it itself in a fresh directory. Anything that does not match gets the structure
only, with a note that raw output was withheld. --dump-file additionally needs the file to be at most 64 KiB; it is given for
a few chosen test cases only.

It judges nothing about the parser, changes nothing and needs no credential: it reads files. Every line is escaped (no line
break, no control or escape-sequence character, no workflow command can come out of the data). Standard library only; it runs
on Linux and on the macOS runner.
"""
import base64
import hashlib
import os
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ipa_inspect as I  # noqa: E402

MAX_DUMP = 64 * 1024


def line(text):
    print("PROBE " + I.escape_text(text, limit=I.MAX_LINE_CHARS))


def token_line(token, text):
    """A machine-readable line: TOKEN first (fixed text), then escaped text. Scripts match on the token."""
    print(token + " " + I.escape_text(text, limit=I.MAX_LINE_CHARS))


def show_xml(ents):
    def render(v, ind):
        pad = "  " * ind
        if isinstance(v, dict):
            return "{\n" + "".join("%s  %r: %s,\n" % (pad, k, render(v[k], ind + 1)) for k in sorted(v)) + pad + "}"
        if isinstance(v, list):
            return "[" + ", ".join(render(x, ind + 1) for x in v) + "]"
        return repr(v)
    return render(ents, 0)


def label(path):
    return "%s/%s" % (os.path.basename(os.path.dirname(path)), os.path.basename(path))


def file_sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def der_structure_problem(blob):
    """Why a DER entitlements blob is not a valid container holding ONE well-formed ASN.1 element, or None. It assumes
    nothing about the element's layout (that is what is being investigated)."""
    if len(blob) < 8:
        return "shorter than the 8-byte blob header"
    magic, length = struct.unpack(">II", blob[:8])
    if magic != I.CSMAGIC_DER_ENTITLEMENTS:
        return "magic is 0x%08x, not 0x%08x" % (magic, I.CSMAGIC_DER_ENTITLEMENTS)
    if length != len(blob):
        return "declared length %d differs from the blob's length %d" % (length, len(blob))
    body = blob[8:]
    try:
        node = I.parse_node(body, 0, len(body))
    except (I.Asn1Error, IndexError, ValueError, RecursionError, struct.error) as e:
        return "the body is not well-formed ASN.1: %s" % e
    if node.end != len(body):
        return "the body is not ONE ASN.1 element: %d byte(s) follow it" % (len(body) - node.end)
    return None


def seal_problem(cd, slot, blob):
    sealed = I.slot_hash(cd, slot)
    if sealed is None:
        return "does not seal special slot %d" % slot
    if hashlib.new(cd["hash_name"], blob).digest()[:len(sealed)] != sealed:
        return "special slot %d does not match the blob's hash" % slot
    return None


def assess(sig):
    """(reasons evidence is incomplete, parser status). The existing parser is run for the report ONLY."""
    if sig["error"]:
        return ["not readable as Mach-O: %s" % sig["error"]], "n/a"
    reasons, parsers = [], []
    if not sig["slices"]:
        reasons.append("the file has no architecture slice")
    for si, s in enumerate(sig["slices"]):
        tag = "slice %d" % si
        if not s["signed"]:
            reasons.append("%s is not signed" % tag)
            continue
        if not s["cds"]:
            reasons.append("%s has no CodeDirectory" % tag)
            continue
        xml_blob, der_blob = s["entitlements_blob"], s.get("der_entitlements_blob")
        if xml_blob is None:
            reasons.append("%s has no XML entitlements blob (slot 5)" % tag)
        if der_blob is None:
            reasons.append("%s has no DER entitlements blob (slot 7)" % tag)
        else:
            why = der_structure_problem(der_blob)
            if why:
                reasons.append("%s: DER entitlements blob: %s" % (tag, why))
            try:
                I.parse_der_entitlements(der_blob)
                parsers.append("accepted")
            except Exception:  # the parser may refuse genuine data; whatever it does is only reported
                parsers.append("rejected")
        for key, cd in s["cds"]:
            for slot, blob in ((I.SLOT_DER_ENTITLEMENTS, der_blob), (I.SLOT_ENTITLEMENTS, xml_blob)):
                if blob is not None:
                    why = seal_problem(cd, slot, blob)
                    if why:
                        reasons.append("%s CodeDirectory 0x%x %s" % (tag, key, why))
    parser = "n/a" if not parsers else ("rejected" if "rejected" in parsers else "accepted")
    return reasons, parser


def emit_dump(path, size):
    """Writes the whole file as base64 between BEGIN-FILE and END-FILE. -> (True, None) or (False, reason)."""
    with open(path, "rb") as f:
        data = f.read(MAX_DUMP + 1)
    if len(data) != size:
        return False, "the file changed while it was read (%d byte(s) read, %d expected)" % (len(data), size)
    line("BEGIN-FILE %s %d byte(s) sha256 %s" % (label(path), len(data), hashlib.sha256(data).hexdigest()))
    b64 = base64.b64encode(data).decode("ascii")
    for i in range(0, len(b64), 100):
        print("PROBE-DATA " + b64[i:i + 100])
    line("END-FILE %s" % label(path))
    return True, None


def result_line(reasons, parser, dump_status):
    token_line("PROBE-RESULT", "der_evidence=%s parser=%s fixture_dump=%s" % ("INCOMPLETE" if reasons else "complete", parser, dump_status))


def probe(path, ident, dump):
    """-> True if the DER evidence of this file is complete AND, when a dump was requested, the dump is complete."""
    size = os.path.getsize(path)
    sig = I.read_signature(path)
    line("file %s: %d byte(s), sha256 %s" % (label(path), size, file_sha256(path)))
    reasons, parser = assess(sig)
    for why in reasons:
        token_line("PROBE-EVIDENCE-PROBLEM", why)
    dump_status = "INCOMPLETE" if dump else "not-requested"
    if sig["error"]:
        line("  unreadable as Mach-O: %s" % sig["error"])
        if dump:
            token_line("PROBE-DUMP-PROBLEM", "the file is not readable as Mach-O, so no dump was produced")
        result_line(reasons, parser, dump_status)
        return False
    signed = [s for s in sig["slices"] if s["signed"]]
    idents = [cd["identifier"] for s in signed for _k, cd in s["cds"]]
    with_cms = [s for s in signed if s["cms"]]
    synthetic = bool(ident) and bool(signed) and bool(idents) and all(i == ident for i in idents) and not with_cms
    if ident and not synthetic:
        line("  RAW OUTPUT WITHHELD: the CodeDirectory identifier(s) are not exactly the designated %r, or a CMS signature is present (identifiers: %s)" % (ident, ", ".join(sorted(set(idents))) or "none"))
    elif not ident:
        line("  raw output is off (no --synthetic-identifier given): structure only")
    for si, s in enumerate(sig["slices"]):
        line("  slice %d: cpu 0x%x, %s" % (si, s["cpu"], "signed" if s["signed"] else "NOT signed"))
        for p in s["problems"]:
            line("    verifier finding (reported only; it does not decide the evidence status): %s" % p)
        if not s["signed"]:
            continue
        xml_blob, der_blob = s["entitlements_blob"], s.get("der_entitlements_blob")
        for key, cd in s["cds"]:
            line("    CodeDirectory 0x%x: identifier %r, %s, version 0x%x, flags 0x%x, page size %d, team %r, %d special slot(s), %d code slot(s)"
                 % (key, cd["identifier"], cd["hash_name"], cd["version"], cd["flags"], cd["page_size"], cd["team_id"], cd["n_special"], cd["n_code"]))
            sealed5, sealed7 = I.slot_hash(cd, I.SLOT_ENTITLEMENTS), I.slot_hash(cd, I.SLOT_DER_ENTITLEMENTS)
            hn = cd["hash_name"]

            def agree(sealed, blob):
                if sealed is None:
                    return "not sealed" + ("" if blob is None else " (but a blob is present)")
                if blob is None:
                    return "sealed %s but no blob is present" % sealed.hex()
                got = hashlib.new(hn, blob).digest()[:len(sealed)]
                return "sealed %s, %s" % (sealed.hex(), "equals the blob's hash" if got == sealed else "DIFFERS from the blob's hash %s" % got.hex())
            line("    CodeDirectory 0x%x: XML entitlements slot 5: %s" % (key, agree(sealed5, xml_blob)))
            line("    CodeDirectory 0x%x: DER entitlements slot 7: %s" % (key, agree(sealed7, der_blob)))
        if s["entitlements"] is not None:
            line("    XML entitlements: %d key(s)" % len(s["entitlements"]))
            if synthetic:
                for ln in show_xml(s["entitlements"]).splitlines():
                    line("      " + ln)
        else:
            line("    no XML entitlements")
        if der_blob is None:
            line("    no DER entitlements blob")
        else:
            d = I.der_blob_diagnostic(der_blob, raw=synthetic)
            line("    DER entitlements blob: present, %d byte(s), sha256 %s" % (d["length"], d["sha256"]))
            line("    DER header: %s" % d["header"])
            for ln in d["outline"]:
                line("    DER outline: " + ln)
            if d["hex"] is not None:
                line("    DER hex%s: %s" % (" (first %d bytes)" % I.DER_DIAG_MAX_BYTES if d["hex_truncated"] else "", d["hex"]))
            try:
                decoded = I.parse_der_entitlements(der_blob)
            except Exception as e:  # the parser may refuse genuine data; that is a finding, not an error of the probe
                line("    current parser: REFUSES the blob: %s" % e)
            else:
                same = s["entitlements"] is not None and decoded == s["entitlements"]
                line("    current parser: decodes the blob; equal to the XML entitlements: %s" % ("yes" if same else "NO"))
    if dump:
        why = None
        if not synthetic:
            why = "not designated synthetic input (raw output was withheld)"
        elif size > MAX_DUMP:
            why = "the file is %d byte(s), larger than the %d-byte limit" % (size, MAX_DUMP)
        else:
            done, why = emit_dump(path, size)
            if done:
                dump_status = "complete"
        if dump_status != "complete":
            token_line("PROBE-DUMP-PROBLEM", "the requested file dump was not produced: %s" % why)
    result_line(reasons, parser, dump_status)
    return not reasons and dump_status in ("complete", "not-requested")


def main(argv):
    ident, dump, files = None, False, []
    it = iter(argv)
    for a in it:
        if a == "--dump-file":
            dump = True
        elif a == "--synthetic-identifier":
            ident = next(it, None)
            if not ident:
                print("--synthetic-identifier needs a value", file=sys.stderr)
                return 2
        elif a.startswith("--"):
            print("unknown option %s" % I.escape_text(a), file=sys.stderr)
            return 2
        else:
            files.append(a)
    if not files:
        print(__doc__)
        return 2
    rc = 0
    for f in files:
        if not os.path.isfile(f):
            line("%s: not a file" % f)
            token_line("PROBE-RESULT", "der_evidence=INCOMPLETE parser=n/a fixture_dump=%s" % ("INCOMPLETE" if dump else "not-requested"))
            rc = 2
            continue
        try:
            complete = probe(f, ident, dump)
        except Exception as e:  # a failure on one file must not hide the others, and is never read as success
            line("%s: the probe failed on this file (%s)" % (label(f), type(e).__name__))
            token_line("PROBE-RESULT", "der_evidence=INCOMPLETE parser=n/a fixture_dump=%s" % ("INCOMPLETE" if dump else "not-requested"))
            rc = 2
            continue
        if not complete and rc == 0:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
