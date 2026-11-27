#!/usr/bin/env python3
"""OFFLINE FIXTURE EXTRACTOR for the DER entitlements experiment (Issue #71, Phase 3 preparation).

    python3 -I tool/extract_probe_fixtures.py --log SAVED_JOB_LOG --out NEW_DIRECTORY

The macOS experiment (tool/probe_der_entitlements.sh) prints the complete signed synthetic executable of its three REQUIRED cases
into the GitHub Actions job log, as base64 between BEGIN-FILE and END-FILE records. Nothing is uploaded, so the log is the only
copy. This tool reconstructs those three files from a job log that YOU saved (for example with `gh run view RUN --log` or the
job-log download of the Actions page), after checking everything the log says about them. It works on a file on this machine,
it needs no network and no credential, and it never runs what it extracts.

WHAT IT ACCEPTS. A log that holds exactly one complete run's three required dumps:
  - one BEGIN-FILE, its PROBE-DATA lines and its END-FILE for each of runner-ios-xcodelike, runner-mac-plain and
    arrays-ios-xcodelike, each INSIDE the log group of that case, with the label "CASE/com.example.disposable" in both records and
    nothing else between them;
  - base64 that decodes strictly (100-character data lines, padding only at the very end), to exactly the size and the SHA-256
    that BEGIN-FILE states (a decimal size field of at most 5 digits, at most 64 KiB);
  - a file that is a structurally valid Mach-O container (one thin 64-bit little-endian image, or a fat container of such images)
    in which EVERY image has exactly one LC_CODE_SIGNATURE, a well-formed embedded signature SuperBlob, and a primary
    CodeDirectory (and any alternate CodeDirectory) whose identifier, read at the offset the CodeDirectory itself declares, is
    exactly com.example.disposable. The file is parsed by bounded structural reading only: an identifier string found anywhere
    else in the file proves nothing and is ignored;
  - for each case exactly one "PROBE-RESULT der_evidence=complete parser=P fixture_dump=complete" line inside the group that holds
    its dump (P is accepted or rejected: a parser REFUSAL does not make complete evidence invalid), the script's own verdict line
    "RESULT CASE: signing=ok verify=ok evidence=ok fixture_dump=ok parser=P => DER evidence obtained" exactly once with the SAME
    parser verdict, the closing "RESULT OK: ..." line exactly once, and no "RESULT FAILED" line.
It REJECTS, and writes nothing, on anything else: a missing, duplicated, interleaved, truncated or extra record; a record in
another group or with another label; bad base64, size or digest; a size field that is not a short plain decimal number; a file
that is not a valid signed Mach-O or whose CodeDirectory identifier is missing, malformed, conflicting or not the expected one; a
missing, repeated, malformed, incomplete or contradicting PROBE-RESULT or verdict; a log larger than 64 MiB.

WHAT IT WRITES. Only into the directory given with --out, which must not exist (it is created, mode 0700) or must be an empty
directory that is not a symbolic link; its parent must exist. The three files have FIXED names chosen by this tool, never taken
from the log (CASE.macho, mode 0600, created with O_EXCL and O_NOFOLLOW, so nothing is overwritten and no link is followed), and
a MANIFEST.txt with their sizes and SHA-256 digests. If anything fails while writing, what this run created is removed again.

WHAT IT NEVER DOES. It does not execute, load or open for execution any extracted file (it imports no process, network or
dynamic-loading module and sets no execute permission), it does not upload or send anything, and it prints no text taken from the
log: its messages name a line number and a fixed reason.

WHAT THE CHECKS ARE NOT. The Mach-O reading is a STRUCTURAL CONSISTENCY check of the container and of where the signature says its
identifier is. It does not hash the code, check the code hashes, the entitlement seals or any CMS signature, and it is no proof of
Apple's signature authenticity or that the file was produced by the experiment.

THE FILES ARE EVIDENCE, NOT TRUSTED CODE. They are signed synthetic test programs. Read them with tool/ipa_inspect.py or
tool/der_entitlements_probe.py (the latter prints; neither runs them), keep them away from anything that executes files, and note
that the log of this public repository is publicly readable, so anyone can produce a log that looks like this one: the checks above
show that a log is CONSISTENT, not that it is genuine. Take the log from the run you started, by its run number.

Exit status: 0 extracted; 1 the log was rejected (nothing written); 2 a usage or file error. Python 3.8+, standard library only.
"""
import argparse
import base64
import binascii
import hashlib
import os
import re
import struct
import sys

sys.dont_write_bytecode = True

IDENT = "com.example.disposable"
# the three REQUIRED cases of tool/probe_der_entitlements.sh (its dump_cases) and the fixed file name chosen for each
REQUIRED = ("runner-ios-xcodelike", "runner-mac-plain", "arrays-ios-xcodelike")
MAX_DUMP = 64 * 1024            # the probe's own limit for a dump
MAX_LOG = 64 * 1024 * 1024      # the largest log this tool will read
CHUNK = 100                     # the probe writes the base64 in lines of 100 characters
MAX_SIZE_DIGITS = len(str(MAX_DUMP))        # the BEGIN-FILE size field: at most this many plain decimal digits
MAX_DATA_LINES = (MAX_DUMP * 4 // 3 + 8) // CHUNK + 2   # the most 100-character lines a 64 KiB file can need
# Mach-O and code-signature structure (constants of the file formats), read with explicit bounds
MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC, FAT_MAGIC_64 = 0xCAFEBABE, 0xCAFEBABF
LC_SEGMENT_64, LC_CODE_SIGNATURE = 0x19, 0x1D
CSMAGIC_EMBEDDED_SIGNATURE, CSMAGIC_CODEDIRECTORY = 0xFADE0CC0, 0xFADE0C02
SLOT_CODEDIRECTORY = 0
SLOT_ALT_CODEDIRECTORIES = range(0x1000, 0x1005)
MAX_ARCHS, MAX_COMMANDS, MAX_BLOBS, MAX_SPECIAL_SLOTS = 8, 256, 64, 64
CD_MIN_HEADER = 44                          # the CodeDirectory fields up to and including the spare word
CD_HASH_SIZES = (20, 32, 48)

# what a log line looks like: optionally "JOB<TAB>STEP<TAB>" (gh run view --log), optionally a timestamp (every download form)
_PREFIX = re.compile(r"^(?:[^\t]*\t[^\t]*\t)?(?:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z )?")
_GROUP = re.compile(r"^(?:::group::|##\[group\])(.*)$")
_ENDGROUP = ("::endgroup::", "##[endgroup]")
_BEGIN = re.compile(r"^PROBE BEGIN-FILE (\S+) ([0-9]+) byte\(s\) sha256 ([0-9a-f]{64})$")
_END = re.compile(r"^PROBE END-FILE (\S+)$")
_DATA = re.compile(r"^PROBE-DATA ([A-Za-z0-9+/=]+)$")
_RESULT = re.compile(r"^RESULT (\S+): signing=ok verify=ok evidence=ok fixture_dump=ok parser=(accepted|rejected) => DER evidence obtained$")
_PROBE_RESULT = re.compile(r"^PROBE-RESULT der_evidence=(\S+) parser=(\S+) fixture_dump=(\S+)$")


class Rejected(Exception):
    """The log is not acceptable. The text is a FIXED reason; it never contains text from the log."""


def fail(lineno, reason):
    raise Rejected("line %d: %s" % (lineno, reason) if lineno else reason)


def normalize(raw):
    return _PREFIX.sub("", raw.rstrip("\r\n"), count=1)


def check_codedirectory(cd, lineno):
    """One CodeDirectory blob: well-formed header and layout, and the identifier AT THE OFFSET IT DECLARES is exactly IDENT."""
    if len(cd) < CD_MIN_HEADER:
        fail(lineno, "a CodeDirectory too small to have a header")
    (magic, _length, version, _flags, hash_off, ident_off, n_special, n_code, _limit, hash_size, _htype, _plat, _page) = \
        struct.unpack(">IIIIIIIIIBBBB", cd[:40])
    if magic != CSMAGIC_CODEDIRECTORY:
        fail(lineno, "a CodeDirectory blob with the wrong magic")
    if not 0x20001 <= version <= 0x2FFFF:
        fail(lineno, "a CodeDirectory with an implausible version")
    if hash_size not in CD_HASH_SIZES:
        fail(lineno, "a CodeDirectory with an unsupported hash size")
    if n_special > MAX_SPECIAL_SLOTS or hash_off > len(cd) or n_code * hash_size > len(cd) - hash_off:
        fail(lineno, "a CodeDirectory whose hash arrays do not lie inside it")
    want = IDENT.encode("ascii") + b"\0"
    if ident_off < CD_MIN_HEADER or ident_off + len(want) > len(cd):
        fail(lineno, "a CodeDirectory whose identifier offset is outside the blob or inside its header")
    if cd[ident_off:ident_off + len(want)] != want:
        fail(lineno, "a CodeDirectory identifier that is missing, unterminated or not exactly the disposable identifier")
    if ident_off + len(want) > hash_off - n_special * hash_size:
        fail(lineno, "a CodeDirectory whose identifier overlaps its hash arrays")


def check_signature(sl, lineno):
    """One 64-bit little-endian image: load commands, exactly one LC_CODE_SIGNATURE, a SuperBlob, and every CodeDirectory in it."""
    if len(sl) < 32 or struct.unpack("<I", sl[:4])[0] != MH_MAGIC_64:
        fail(lineno, "an image that is not a 64-bit little-endian Mach-O")
    ncmds, sizeofcmds = struct.unpack("<II", sl[16:24])
    end = 32 + sizeofcmds
    if not 1 <= ncmds <= MAX_COMMANDS or sizeofcmds < 8 * ncmds or end > len(sl):
        fail(lineno, "a Mach-O whose load commands are missing, too many or outside the image")
    pos, sig = 32, None
    for _ in range(ncmds):
        if pos + 8 > end:
            fail(lineno, "a load command header outside the load-command area")
        cmd, csize = struct.unpack("<II", sl[pos:pos + 8])
        if csize < 8 or csize % 8 or pos + csize > end:
            fail(lineno, "a load command with a bad size")
        if cmd == LC_SEGMENT_64:
            if csize < 72 or csize != 72 + 80 * struct.unpack("<I", sl[pos + 64:pos + 68])[0]:
                fail(lineno, "a segment command whose size does not fit its sections")
        elif cmd == LC_CODE_SIGNATURE:
            if csize != 16 or sig is not None:
                fail(lineno, "a code-signature load command of the wrong size, or a second one")
            sig = struct.unpack("<II", sl[pos + 8:pos + 16])
        pos += csize
    if pos != end:
        fail(lineno, "load commands that do not add up to the declared size")
    if sig is None:
        fail(lineno, "an image without a code signature")
    off, size = sig
    if size < 12 or off < end or off > len(sl) or size > len(sl) - off:
        fail(lineno, "a code signature that lies outside the image or over its headers")
    sb = sl[off:off + size]
    magic, length, count = struct.unpack(">III", sb[:12])
    if magic != CSMAGIC_EMBEDDED_SIGNATURE:
        fail(lineno, "a code signature that is not an embedded-signature SuperBlob")
    if not 1 <= count <= MAX_BLOBS or length > size or length < 12 + 8 * count:
        fail(lineno, "a SuperBlob with a bad length or blob count")
    first, seen, spans = 12 + 8 * count, set(), []
    for i in range(count):
        kind, o = struct.unpack(">II", sb[12 + 8 * i:20 + 8 * i])
        if kind in seen:
            fail(lineno, "a SuperBlob that lists a blob type twice")
        seen.add(kind)
        if o < first or o + 8 > length:
            fail(lineno, "a SuperBlob blob offset outside the SuperBlob")
        blen = struct.unpack(">I", sb[o + 4:o + 8])[0]
        if blen < 8 or blen > length - o:
            fail(lineno, "a SuperBlob blob that runs past the SuperBlob")
        spans.append((o, o + blen, kind))
    spans.sort()
    for a, b in zip(spans, spans[1:]):
        if a[1] > b[0]:
            fail(lineno, "SuperBlob blobs that overlap")
    if SLOT_CODEDIRECTORY not in seen:
        fail(lineno, "a SuperBlob without a primary CodeDirectory")
    for start, stop, kind in spans:
        if kind == SLOT_CODEDIRECTORY or kind in SLOT_ALT_CODEDIRECTORIES:
            check_codedirectory(sb[start:stop], lineno)


def check_macho(data, lineno):
    """Bounded structural check of a (thin or fat) Mach-O: every image must be signed with the expected identifier. Raises Rejected."""
    if len(data) < 32:
        fail(lineno, "a file too small to be a Mach-O")
    if struct.unpack("<I", data[:4])[0] == MH_MAGIC_64:
        check_signature(data, lineno)
        return
    magic = struct.unpack(">I", data[:4])[0]
    if magic not in (FAT_MAGIC, FAT_MAGIC_64):
        fail(lineno, "the data is neither a 64-bit little-endian Mach-O nor a fat container")
    n = struct.unpack(">I", data[4:8])[0]
    each = 20 if magic == FAT_MAGIC else 32
    if not 1 <= n <= MAX_ARCHS or 8 + n * each > len(data):
        fail(lineno, "a fat container with no, too many or truncated architecture records")
    table_end, images = 8 + n * each, []
    for i in range(n):
        rec = data[8 + i * each:8 + (i + 1) * each]
        off, size = struct.unpack(">II", rec[8:16]) if magic == FAT_MAGIC else struct.unpack(">QQ", rec[8:24])
        if size < 32 or off < table_end or off > len(data) or size > len(data) - off:
            fail(lineno, "a fat image that lies outside the file or over the header")
        images.append((off, size))
    images.sort()
    for a, b in zip(images, images[1:]):
        if a[0] + a[1] > b[0]:
            fail(lineno, "fat images that overlap")
    for off, size in images:
        check_signature(data[off:off + size], lineno)


def parse(text):
    """-> {case: bytes}. Raises Rejected."""
    lines = text.split("\n")
    group = None
    seq = 0                 # which group occurrence we are in (a group name can occur more than once)
    dump_seq = {}           # case -> the group occurrence that held its dump
    records = {}            # case -> bytes
    verdicts = {}           # case -> parser verdict of its RESULT line
    probe_results = {}      # case -> [(der_evidence, parser, fixture_dump)] of the PROBE-RESULT lines in its group
    ok_lines = 0
    i = 0
    n = len(lines)
    while i < n:
        lineno = i + 1
        first = lines[i]
        if i == 0 and first.startswith("\ufeff"):   # a byte order mark before the first timestamp
            first = first[1:]
        s = normalize(first)
        g = _GROUP.match(s)
        if g:
            group = g.group(1)
            seq += 1
        elif s in _ENDGROUP:
            group = None
        elif s.startswith("PROBE BEGIN-FILE") or s.startswith("PROBE-DATA") or s.startswith("PROBE END-FILE"):
            if not s.startswith("PROBE BEGIN-FILE"):
                fail(lineno, "a data or end record outside a BEGIN-FILE record")
            m = _BEGIN.match(s)
            if not m:
                fail(lineno, "malformed BEGIN-FILE record")
            label, size_text, sha = m.group(1), m.group(2), m.group(3)
            # the size field is checked as TEXT before it is ever converted: a short plain decimal number without a leading zero
            if len(size_text) > MAX_SIZE_DIGITS or (len(size_text) > 1 and size_text[0] == "0"):
                fail(lineno, "the stated size is not a short plain decimal number")
            size = int(size_text)
            if not (0 < size <= MAX_DUMP):
                fail(lineno, "the stated size is zero or above the 64 KiB limit")
            if group is None:
                fail(lineno, "a dump outside the log group of a case")
            if group not in REQUIRED:
                fail(lineno, "a dump in a group that is not one of the three required cases")
            if label != "%s/%s" % (group, IDENT):
                fail(lineno, "the label of the dump does not match its group and the disposable identifier")
            if group in records:
                fail(lineno, "a second dump for a case that already has one")
            data = []
            i += 1
            while True:
                if i >= n:
                    fail(0, "the log ends inside a dump (truncated)")
                lineno = i + 1
                t = normalize(lines[i])
                d = _DATA.match(t)
                if d:
                    data.append((lineno, d.group(1)))
                    if len(data) > MAX_DATA_LINES:
                        fail(lineno, "more data lines than a 64 KiB file can need")
                    i += 1
                    continue
                e = _END.match(t)
                if e:
                    if e.group(1) != label:
                        fail(lineno, "END-FILE does not carry the label of its BEGIN-FILE")
                    break
                fail(lineno, "something other than data or END-FILE inside a dump")
            if not data:
                fail(lineno, "a dump without data")
            for k, (ln, chunk) in enumerate(data):
                last = k == len(data) - 1
                if (not last and len(chunk) != CHUNK) or len(chunk) > CHUNK or len(chunk) % 4 != 0:
                    fail(ln, "a data line of the wrong length")
                if "=" in chunk.rstrip("=") or (not last and chunk.endswith("=")):
                    fail(ln, "base64 padding in the wrong place")
            try:
                raw = base64.b64decode("".join(c for _, c in data).encode("ascii"), validate=True)
            except (binascii.Error, ValueError):
                fail(lineno, "the data is not strictly valid base64")
            if len(raw) != size:
                fail(lineno, "the decoded size is not the stated size")
            if hashlib.sha256(raw).hexdigest() != sha:
                fail(lineno, "the SHA-256 of the decoded data is not the stated digest")
            check_macho(raw, lineno)
            records[group] = raw
            dump_seq[group] = seq
        elif s.startswith("PROBE-RESULT"):
            # the probe's own line for ONE file, printed after its dump. Other cases' lines are not ours; ours must be exactly one.
            if group is None:
                fail(lineno, "a PROBE-RESULT line outside the log group of a case")
            if group in REQUIRED:
                pr = _PROBE_RESULT.match(s)
                if not pr:
                    fail(lineno, "a malformed PROBE-RESULT line in a required case")
                if dump_seq.get(group) != seq:
                    fail(lineno, "a PROBE-RESULT line in a required case before (or without) the dump of that group")
                probe_results.setdefault(group, []).append(pr.groups())
        else:
            r = _RESULT.match(s)
            if r and r.group(1) in REQUIRED:
                if r.group(1) in verdicts:
                    fail(lineno, "a second verdict line for a required case (more than one run in the log?)")
                verdicts[r.group(1)] = r.group(2)
            elif s.startswith("RESULT FAILED"):
                fail(lineno, "the run reports RESULT FAILED")
            elif s.startswith("RESULT OK: DER evidence and the fixture dump were obtained for every required case"):
                ok_lines += 1
                if ok_lines > 1:
                    fail(lineno, "a second closing RESULT OK line (more than one run in the log?)")
            elif re.match(r"^RESULT (?:%s): " % "|".join(map(re.escape, REQUIRED)), s):
                fail(lineno, "a verdict line for a required case that is not a complete success")
        i += 1
    missing = [c for c in REQUIRED if c not in records]
    if missing:
        fail(0, "no dump for %d of the 3 required cases" % len(missing))
    if sorted(verdicts) != sorted(REQUIRED):
        fail(0, "a required case has no success verdict line")
    for case in REQUIRED:
        found = probe_results.get(case, [])
        if len(found) != 1:
            fail(0, "a required case has %d PROBE-RESULT line(s) instead of exactly one" % len(found))
        evidence, parser, fixture = found[0]
        if evidence != "complete" or fixture != "complete":
            fail(0, "a PROBE-RESULT of a required case does not report complete evidence and a complete fixture dump")
        if parser not in ("accepted", "rejected"):
            fail(0, "a PROBE-RESULT of a required case has no parser verdict")
        if parser != verdicts[case]:
            fail(0, "the parser verdict of a PROBE-RESULT contradicts the RESULT line of its case")
    if ok_lines != 1:
        fail(0, "the closing RESULT OK line is missing")
    return records


def write_all(records, out):
    """Creates OUT (or fills an empty one) and writes the files; on any failure removes what this call created."""
    created_dir = False
    created = []
    try:
        if os.path.lexists(out):
            if os.path.islink(out) or not os.path.isdir(out):
                raise Rejected("the destination exists and is not a plain directory")
            if os.listdir(out):
                raise Rejected("the destination directory is not empty (nothing is overwritten)")
        else:
            parent = os.path.dirname(os.path.abspath(out))
            if not os.path.isdir(parent):
                raise Rejected("the parent of the destination does not exist")
            os.mkdir(out, 0o700)
            created_dir = True
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
        manifest = ["# fixtures extracted from a saved job log by tool/extract_probe_fixtures.py (synthetic test programs; never execute them)"]
        for case in REQUIRED:
            data = records[case]
            path = os.path.join(out, case + ".macho")
            fd = os.open(path, flags, 0o600)
            created.append(path)
            with os.fdopen(fd, "wb") as f:
                f.write(data)
            manifest.append("%s.macho  %d byte(s)  sha256 %s" % (case, len(data), hashlib.sha256(data).hexdigest()))
        path = os.path.join(out, "MANIFEST.txt")
        fd = os.open(path, flags, 0o600)
        created.append(path)
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(manifest) + "\n")
    except BaseException:
        for p in created:
            try:
                os.remove(p)
            except OSError:
                pass
        if created_dir:
            try:
                os.rmdir(out)
            except OSError:
                pass
        raise


def main(argv):
    ap = argparse.ArgumentParser(prog="extract_probe_fixtures.py", allow_abbrev=False, add_help=True,
                                 description="Reconstruct the three signed synthetic fixtures from a saved GitHub Actions job log.")
    ap.add_argument("--log", required=True, help="the saved job log (a file; there is no default and no standard input)")
    ap.add_argument("--out", required=True, help="the destination: a directory that does not exist yet, or an empty one")
    try:
        args = ap.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code not in (0, None) else 0
    log = args.log
    if not os.path.isfile(log):
        print("extract_probe_fixtures: the log is not a file", file=sys.stderr)
        return 2
    try:
        size = os.path.getsize(log)
        if size > MAX_LOG:
            print("extract_probe_fixtures: REJECTED: the log is larger than %d MiB" % (MAX_LOG // (1024 * 1024)), file=sys.stderr)
            return 1
        with open(log, "rb") as f:
            raw = f.read(MAX_LOG + 1)
    except OSError:
        print("extract_probe_fixtures: the log cannot be read", file=sys.stderr)
        return 2
    if len(raw) > MAX_LOG:
        print("extract_probe_fixtures: REJECTED: the log is larger than %d MiB" % (MAX_LOG // (1024 * 1024)), file=sys.stderr)
        return 1
    try:
        records = parse(raw.decode("utf-8", errors="replace"))
    except Rejected as e:
        print("extract_probe_fixtures: REJECTED (nothing written): %s" % e, file=sys.stderr)
        return 1
    except RecursionError:  # pragma: no cover - the parser is iterative; this is a last resort
        print("extract_probe_fixtures: REJECTED (nothing written): the log could not be processed", file=sys.stderr)
        return 1
    try:
        write_all(records, args.out)
    except Rejected as e:
        print("extract_probe_fixtures: REFUSED (nothing written): %s" % e, file=sys.stderr)
        return 2
    except OSError:
        print("extract_probe_fixtures: the files could not be written (what this run created was removed)", file=sys.stderr)
        return 2
    print("extract_probe_fixtures: OK: extracted the 3 required fixtures into the destination (files are evidence: never execute them)")
    for case in REQUIRED:
        print("  %s.macho  %d byte(s)  sha256 %s" % (case, len(records[case]), hashlib.sha256(records[case]).hexdigest()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
