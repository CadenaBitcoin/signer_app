#!/usr/bin/env bash
# Tests of the OFFLINE FIXTURE EXTRACTOR tool/extract_probe_fixtures.py (Issue #71, Phase 3 preparation).
#
#   tool/test_extract_probe_fixtures.sh
#
# The logs are built here from the REAL probe's output (tool/der_entitlements_probe.py run on synthetic Mach-O files signed with
# the fixture signer of tool/ipa_fixture.py), wrapped the way a GitHub Actions job log wraps a step: timestamp prefixes and
# ##[group] lines, the "job<TAB>step<TAB>" form of `gh run view --log`, and the bare form of the script's own output. Nothing is
# signed by Apple's tools, nothing runs on macOS, nothing is downloaded and nothing is started on GitHub.
# What they protect: the extractor rebuilds the three required files exactly, and REJECTS (writing nothing) a log that is
# incomplete, duplicated, malformed, inconsistent, in another group or identifier, or hostile; it writes only into a new or empty
# directory under names it chooses, never overwrites, never follows a link, never executes, never uploads, never echoes the log.
# Exit 0 only if every check passes.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool="$root/tool/extract_probe_fixtures.py"
real_py="$(python3 -c 'import sys; print(sys.executable)')"  # the interpreter itself, not a version-manager shim
pass=0
failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }
chk() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

# ---- static rules of the tool ----
"$real_py" -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read(), feature_version=(3, 8))" "$tool"; chk "tool: valid Python 3.8 grammar" $?
static="$("$real_py" -I -c "
import ast, re, sys
src = open(sys.argv[1]).read()
tree = ast.parse(src)
mods, names, consts = set(), set(), set()
for n in ast.walk(tree):
    if isinstance(n, ast.Import):
        mods.update(a.name.split('.')[0] for a in n.names)
    elif isinstance(n, ast.ImportFrom):
        mods.add((n.module or '').split('.')[0])
    elif isinstance(n, ast.Constant) and isinstance(n.value, str):
        consts.add(n.value)
    elif isinstance(n, ast.Name):
        names.add(n.id)
    elif isinstance(n, ast.Attribute) and not (n.attr == 'compile' and isinstance(n.value, ast.Name) and n.value.id == 're'):
        names.add(n.attr)
forbidden = {'subprocess', 'system', 'popen', 'execv', 'execve', 'execl', 'execlp', 'execvp', 'spawnv', 'spawnl', 'fork', 'ctypes', 'importlib',
             '__import__', 'eval', 'exec', 'compile', 'runpy', 'socket', 'urllib', 'http', 'requests', 'ssl', 'shutil', 'tempfile', 'chmod',
             'fchmod', 'umask', 'chown', 'startfile', 'webbrowser'}
code_lines = [l for l in src.splitlines() if not l.lstrip().startswith('#')]
modes = sorted(set(re.findall(r'0o[0-7]+', chr(10).join(code_lines))))
print('MODS=' + ' '.join(sorted(mods)))
print('FORBIDDEN=' + ' '.join(sorted(names & forbidden)))
print('MODES=' + ' '.join(modes))
print('EXCL=' + ('yes' if 'O_EXCL' in names else 'no'))
print('NOFOLLOW=' + ('yes' if 'O_NOFOLLOW' in names or 'O_NOFOLLOW' in consts else 'no'))" "$tool")"
mods="$(sed -n 's/^MODS=//p' <<<"$static")"; forb="$(sed -n 's/^FORBIDDEN=//p' <<<"$static")"; modes="$(sed -n 's/^MODES=//p' <<<"$static")"
[ "$mods" = "argparse base64 binascii hashlib os re struct sys" ]; chk "tool: imports only argparse base64 binascii hashlib os re struct sys (standard library; found: $mods)" $?
[ -z "$forb" ]; chk "tool: no process, network, dynamic-loading, evaluation or permission-changing name is used in its code (found: ${forb:-none})" $?
[ "$modes" = "0o600 0o700" ]; chk "tool: the only file modes it uses are 0600 (files) and 0700 (the new directory): never an execute bit (found: $modes)" $?
[ "$(sed -n 's/^EXCL=//p' <<<"$static")" = "yes" ] && [ "$(sed -n 's/^NOFOLLOW=//p' <<<"$static")" = "yes" ]; chk "tool: its CODE (not a comment) creates files with os.O_EXCL and O_NOFOLLOW (no overwrite, no followed link)" $?
grep -F "never run" "$tool" >/dev/null && grep -F "NEVER DOES" "$tool" >/dev/null && grep -F "publicly readable" "$tool" >/dev/null; chk "tool: documents that it never executes or uploads and that the public log can be forged" $?

# ---- the rest runs in Python, in a scratch directory; it prints one ok/FAIL line per check ----
out="$("$real_py" -I - "$root" "$real_py" <<'PY'
import base64, hashlib, os, re, shutil, stat, struct, subprocess, sys, tempfile
sys.dont_write_bytecode = True
root, py = sys.argv[1:3]
tool = os.path.join(root, "tool", "extract_probe_fixtures.py")
sys.path.insert(0, os.path.join(root, "tool"))
import ipa_fixture as F

IDENT = "com.example.disposable"
CASES = ["runner-ios-xcodelike", "runner-mac-plain", "arrays-ios-xcodelike"]
tmp = tempfile.mkdtemp()
results = []


def check(desc, cond, detail=""):
    print(("ok   " if cond else "FAIL ") + desc, flush=True)   # printed at once, so a crash later cannot hide what already ran
    if not cond and detail:
        print("     " + detail, flush=True)


ents = os.path.join(tmp, "ents.plist")
open(ents, "w").write('<?xml version="1.0"?><plist version="1.0"><dict><key>k</key><string>v</string></dict></plist>')


def run(args, cwd=None):
    p = subprocess.run([py, "-I", tool] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=cwd)
    return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")


def make_file(case, ident=IDENT, extra=b"", magic_fix=None):
    d = os.path.join(tmp, "src", case)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, ident)
    open(p, "wb").write(F.make_macho(case))
    F.sign_macho_file(p, ident, "TESTTEAM00", {}, open(ents, "rb").read(), False, True, None, True)
    if extra:
        open(p, "ab").write(extra)
    return p


def probe_output(path, ident=IDENT):
    """The REAL probe's output for one file with a dump requested."""
    p = subprocess.run([py, "-I", os.path.join(root, "tool", "der_entitlements_probe.py"), "--synthetic-identifier", ident,
                        "--dump-file", path], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert p.returncode == 0, p.stdout.decode()[-300:]
    return p.stdout.decode().splitlines()


files = {c: make_file(c) for c in CASES}
originals = {c: open(files[c], "rb").read() for c in CASES}
probe_lines = {c: probe_output(files[c]) for c in CASES}
check("setup: the real probe produced a BEGIN-FILE, data and END-FILE record for each of the three cases",
      all(any(l.startswith("PROBE BEGIN-FILE ") for l in probe_lines[c]) and any(l.startswith("PROBE END-FILE ") for l in probe_lines[c]) for c in CASES))


def parser_of(ls):
    """The parser verdict the real probe printed in its (first) PROBE-RESULT line."""
    for l in ls:
        m = re.match(r"^PROBE-RESULT der_evidence=\S+ parser=(\S+) ", l)
        if m:
            return m.group(1)
    return "rejected"


def build(cases=None, ts=True, ghform=False, grp="##[group]%s", endgrp="##[endgroup]", result=True, final=True,
          lines_for=None, extra_lines=(), crlf=False, results_override=None, bom=False):
    """-> the text of a job log. lines_for: case -> list of probe lines (default: the real ones)."""
    cases = CASES if cases is None else cases
    lines_for = lines_for or {}
    out = ["Run bash tool/probe_der_entitlements.sh \"$RUNNER_TEMP/der-probe\"",
           "RESULT built disposable executables for: ios mac",
           "tools: Xcode 26.3 Build version stub | Apple codesign | Python 3.12"]
    for c in cases:
        out.append(grp % c)
        out.append("--- role: REQUIRED (the run fails unless it has DER evidence and its fixture dump)")
        out.extend(lines_for.get(c, probe_lines[c]))
        out.append(endgrp)
        if result:
            out.append((results_override or {}).get(c, "RESULT %s: signing=ok verify=ok evidence=ok fixture_dump=ok parser=%s => DER evidence obtained" % (c, parser_of(lines_for.get(c, probe_lines[c])))))
    out.extend(extra_lines)
    out.append("RESULT summary: signing succeeded for 32 case(s); Apple's codesign verified 32; DER evidence obtained for 32 (the current parser accepted 0 and rejected 32 of those); requested fixture dumps complete for 3 of 3; WORK_DIR is removed on exit")
    if final:
        out.append("RESULT OK: DER evidence and the fixture dump were obtained for every required case")
    wrapped = []
    for n, l in enumerate(out):
        if ghform:
            l = "probe\tSign the disposable program ad hoc and print the DER entitlements\t2026-11-21T17:%02d:%02d.1234567Z %s" % (n // 60 % 60, n % 60, l)
        elif ts:
            l = "2026-11-21T17:%02d:%02d.1234567Z %s" % (n // 60 % 60, n % 60, l)
        wrapped.append(l)
    return ("\ufeff" if bom else "") + ("\r\n" if crlf else "\n").join(wrapped) + ("\r\n" if crlf else "\n")


counter = [0]


def attempt(text, desc, expect_rc, dest=None, precreate=False, must=None, mustnot=None, binary=False, prefilled=False):
    """Runs the extractor on `text`; checks rc, that nothing is written on a rejection, and fragments of the messages."""
    counter[0] += 1
    d = os.path.join(tmp, "case%d" % counter[0])
    os.makedirs(d)
    log = os.path.join(d, "job.log")
    if binary:
        open(log, "wb").write(text)
    else:
        open(log, "w", newline="").write(text)
    dest = dest or os.path.join(d, "out")
    if precreate:
        os.makedirs(dest, exist_ok=True)
    rc, so, se = run(["--log", log, "--out", dest])
    wrote = os.path.isdir(dest) and bool(os.listdir(dest))
    good = rc == expect_rc and "Traceback" not in se       # an uncaught exception is never an acceptable way to reject
    if expect_rc != 0:
        good = good and (prefilled or not wrote) and so == ""   # a destination the user pre-filled is checked by its own test
    if must:
        good = good and must in (so + se)
    detail = "rc=%d, wrote=%s, out=%r err=%r" % (rc, wrote, so[:120], se[:200])
    check(desc, good, detail)
    return rc, so, se, dest


# ---------------------------------------------------------------- successful extraction
for label, kw in (("timestamped raw job log with ##[group] lines", dict()),
                  ("`gh run view --log` form (job<TAB>step<TAB>timestamp text)", dict(ghform=True)),
                  ("bare script output with ::group:: lines and no timestamps", dict(ts=False, grp="::group::%s", endgrp="::endgroup::")),
                  ("log saved with CRLF line endings", dict(crlf=True)),
                  ("log saved with a UTF-8 byte order mark before the first timestamp", dict(bom=True))):
    rc, so, se, dest = attempt(build(**kw), "success: %s" % label, 0)
    names = sorted(os.listdir(dest)) if os.path.isdir(dest) else []
    check("success (%s): exactly the three fixed file names and a manifest are written" % label,
          names == sorted([c + ".macho" for c in CASES] + ["MANIFEST.txt"]), str(names))
    same = all(os.path.exists(os.path.join(dest, c + ".macho")) and open(os.path.join(dest, c + ".macho"), "rb").read() == originals[c] for c in CASES)
    check("success (%s): every extracted file equals the original byte for byte (size and SHA-256)" % label, same)
    if label.startswith("timestamped"):
        modes = [stat.S_IMODE(os.stat(os.path.join(dest, n)).st_mode) for n in names]
        check("success: files are mode 0600 (no execute bit anywhere) and the new directory is 0700",
              all(m == 0o600 for m in modes) and stat.S_IMODE(os.stat(dest).st_mode) == 0o700, str([oct(m) for m in modes]))
        man = open(os.path.join(dest, "MANIFEST.txt")).read()
        check("success: the manifest lists each file with its size and SHA-256",
              all(("%s.macho  %d byte(s)  sha256 %s" % (c, len(originals[c]), hashlib.sha256(originals[c]).hexdigest())) in man for c in CASES))
        check("success: the tool prints each digest and says the files are evidence that must never be executed",
              all(hashlib.sha256(originals[c]).hexdigest() in so for c in CASES) and "never execute them" in so)
        # the extracted file is readable evidence: the probe (which only reads) accepts it
        p = subprocess.run([py, "-I", os.path.join(root, "tool", "der_entitlements_probe.py"), "--synthetic-identifier", IDENT,
                            os.path.join(dest, CASES[0] + ".macho")], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        check("success: an extracted file passes the probe's evidence checks (the next step of the procedure)",
              p.returncode == 0 and b"der_evidence=complete" in p.stdout, p.stdout.decode()[-200:])

d = os.path.join(tmp, "emptydest")
os.makedirs(d)
attempt(build(), "success: an existing EMPTY destination directory is accepted", 0, dest=d)
attempt(build(extra_lines=["\x00\x01 binary noise \xff", "PROBE something else", "RESULT strings-mac-plain: signing=ok verify=ok evidence=ok fixture_dump=not-requested parser=accepted => DER evidence obtained"]),
        "success: unrelated lines (noise, other RESULT lines of supporting cases) are ignored", 0)

# ---------------------------------------------------------------- rejection: incomplete, duplicated, malformed, inconsistent
def mutate(case, fn):
    ls = list(probe_lines[case])
    return {case: fn(ls)}


def idx(ls, prefix):
    return next(i for i, l in enumerate(ls) if l.startswith(prefix))


R = "REJECTED"
c0 = CASES[0]
attempt(build(lines_for=mutate(c0, lambda ls: [l for l in ls if not l.startswith("PROBE END-FILE")])), "reject: a dump without END-FILE", 1, must=R)
attempt(build(lines_for=mutate(c0, lambda ls: [l for l in ls if not l.startswith("PROBE BEGIN-FILE")])), "reject: data and END-FILE without a BEGIN-FILE", 1, must=R)
attempt(build(lines_for=mutate(c0, lambda ls: [l for i, l in enumerate(ls) if i != idx(ls, "PROBE-DATA ") + 1])), "reject: one data line missing (size and digest no longer fit)", 1, must=R)
attempt(build(lines_for=mutate(c0, lambda ls: [l for l in ls if not l.startswith("PROBE-DATA ")])), "reject: a dump without any data line", 1, must=R)
attempt(build(lines_for=mutate(c0, lambda ls: [re.sub(r"sha256 [0-9a-f]{64}", "sha256 " + "0" * 64, l) if l.startswith("PROBE BEGIN-FILE") else l for l in ls])), "reject: the stated SHA-256 is not the digest of the data", 1, must=R)
attempt(build(lines_for=mutate(c0, lambda ls: [re.sub(r" (\d+) byte\(s\)", lambda m: " %d byte(s)" % (int(m.group(1)) + 1), l) if l.startswith("PROBE BEGIN-FILE") else l for l in ls])), "reject: the stated size is not the decoded size", 1, must=R)
attempt(build(lines_for=mutate(c0, lambda ls: [re.sub(r" (\d+) byte\(s\)", " 0 byte(s)", l) if l.startswith("PROBE BEGIN-FILE") else l for l in ls])), "reject: a stated size of zero", 1, must=R)
attempt(build(lines_for=mutate(c0, lambda ls: [l.replace("PROBE-DATA ", "PROBE-DATA !", 1) if i == idx(ls, "PROBE-DATA ") else l for i, l in enumerate(ls)])), "reject: a character outside the base64 alphabet", 1, must=R)
attempt(build(lines_for=mutate(c0, lambda ls: [l[:-4] + "=AAA" if i == idx(ls, "PROBE-DATA ") else l for i, l in enumerate(ls)])), "reject: base64 padding in the middle of the data", 1, must=R)


def rechunk(ls, width):
    data = "".join(l[len("PROBE-DATA "):] for l in ls if l.startswith("PROBE-DATA "))
    first = idx(ls, "PROBE-DATA ")
    rest = [l for l in ls if not l.startswith("PROBE-DATA ")]
    new = ["PROBE-DATA " + data[i:i + width] for i in range(0, len(data), width)]
    return rest[:first] + new + rest[first:]


attempt(build(lines_for=mutate(c0, lambda ls: rechunk(ls, 96))), "reject: data lines of a different length than the probe writes (not 100 characters)", 1, must=R)
attempt(build(lines_for=mutate(c0, lambda ls: [l for l in ls if not l.startswith("PROBE-DATA ")][:idx(ls, "PROBE-DATA ")] + ["PROBE-DATA " + ls[idx(ls, "PROBE-DATA ")][11:][:50]] + [l for l in ls if l.startswith("PROBE-DATA ")][1:] + [l for l in ls if not l.startswith("PROBE-DATA ")][idx(ls, "PROBE-DATA "):])),
        "reject: a short data line before the last one", 1, must=R)
full = build()
cut = full[:full.index("PROBE END-FILE") + 20]
attempt(cut, "reject: a log that ends in the middle of a dump (truncated)", 1, must=R)
attempt(full.replace("RESULT OK: DER evidence and the fixture dump were obtained for every required case\n", ""), "reject: the closing RESULT OK line is missing", 1, must=R)
attempt(build(cases=CASES[:2]), "reject: only two of the three required dumps", 1, must=R)
attempt(build(cases=CASES[:1]), "reject: only one of the three required dumps", 1, must=R)
attempt(build(extra_lines=[]) + build(), "reject: two runs in one log (duplicate dumps and verdicts)", 1, must=R)
dup = build(lines_for={c0: probe_lines[c0] + probe_lines[c0]})
attempt(dup, "reject: the same case dumped twice inside one group", 1, must=R)
attempt(build(result=False), "reject: no verdict (RESULT ... DER evidence obtained) line for the required cases", 1, must=R)
attempt(build(results_override={c0: "RESULT %s: signing=ok verify=FAILED(exit 1) evidence=ok fixture_dump=ok parser=accepted => NOT DER evidence" % c0}), "reject: the verdict of a required case is not a success", 1, must=R)
attempt(build(results_override={c0: "RESULT %s: signing=ok verify=ok evidence=ok fixture_dump=INCOMPLETE parser=accepted => NOT a success: DER evidence obtained, but the requested fixture dump is INCOMPLETE" % c0}), "reject: the verdict says the requested fixture dump is INCOMPLETE", 1, must=R)
attempt(build(extra_lines=["RESULT FAILED: no suitable DER evidence and fixture dump for the required case(s): runner-mac-plain"]), "reject: the log contains RESULT FAILED", 1, must=R)
attempt(build(results_override={c0: "RESULT %s: signing=ok verify=ok evidence=ok fixture_dump=ok parser=rejected => DER evidence obtained\nRESULT %s: signing=ok verify=ok evidence=ok fixture_dump=ok parser=accepted => DER evidence obtained" % (c0, c0)}), "reject: a repeated verdict for a required case", 1, must=R)

# wrong group / label / identifier
attempt(build(grp="##[group]x-%s"), "reject: a dump inside a group that is not one of the three required cases", 1, must=R)
swap = build()
swap = swap.replace("##[group]%s\n" % CASES[0], "##[group]TMP\n").replace("##[group]%s\n" % CASES[1], "##[group]%s\n" % CASES[0]).replace("##[group]TMP\n", "##[group]%s\n" % CASES[1])
attempt(swap, "reject: dumps whose labels do not match the group they are in (cases swapped)", 1, must=R)
attempt(build(lines_for=mutate(c0, lambda ls: [l.replace("/" + IDENT, "/com.example.other") for l in ls])), "reject: a label that names another identifier", 1, must=R)
attempt(build(lines_for=mutate(c0, lambda ls: [l.replace("PROBE END-FILE %s/" % c0, "PROBE END-FILE other/") for l in ls])), "reject: END-FILE with another label than its BEGIN-FILE", 1, must=R)
other = make_file("other-ident-case", ident="com.example.other")
ol = probe_output(other, ident="com.example.other")
ol = [l.replace("other-ident-case/com.example.other", "%s/%s" % (c0, IDENT)) for l in ol]
attempt(build(lines_for={c0: ol}), "reject: a file whose own CodeDirectory identifier is not the disposable one, even with a matching label", 1, must=R)


def fake_dump(case, raw):
    b = base64.b64encode(raw).decode()
    ls = ["PROBE BEGIN-FILE %s/%s %d byte(s) sha256 %s" % (case, IDENT, len(raw), hashlib.sha256(raw).hexdigest())]
    ls += ["PROBE-DATA " + b[i:i + 100] for i in range(0, len(b), 100)]
    ls.append("PROBE END-FILE %s/%s" % (case, IDENT))
    ls.append("PROBE-RESULT der_evidence=complete parser=rejected fixture_dump=complete")
    return ls


attempt(build(lines_for={c0: fake_dump(c0, (IDENT + "\0").encode() + b"x" * 400)}), "reject: consistent size and digest but not a Mach-O", 1, must=R)
attempt(build(lines_for={c0: fake_dump(c0, b"\xcf\xfa\xed\xfe" + b"x" * 400)}), "reject: a Mach-O magic without the disposable identifier", 1, must=R)
big = make_file("big-case", extra=b"\0" * 70000)
attempt(build(lines_for={c0: fake_dump(c0, open(big, "rb").read())}), "reject: a consistent dump larger than the 64 KiB limit", 1, must=R)
attempt(build(lines_for=mutate(c0, lambda ls: ls[:idx(ls, "PROBE-DATA ") + 1] + ["an interleaved line"] + ls[idx(ls, "PROBE-DATA ") + 1:])), "reject: another line between the records of one dump (interleaved output)", 1, must=R)
attempt(build(extra_lines=["PROBE-DATA AAAA"]), "reject: a data record outside any dump", 1, must=R)
attempt(build(extra_lines=["PROBE END-FILE %s/%s" % (c0, IDENT)]), "reject: an END-FILE outside any dump", 1, must=R)
attempt(build(extra_lines=["PROBE BEGIN-FILE not a valid record"]), "reject: a malformed BEGIN-FILE record anywhere", 1, must=R)
outside = build().replace("##[group]%s\n" % c0, "").replace("##[endgroup]\n", "", 1)
attempt(outside, "reject: a dump that is not inside any log group", 1, must=R)

# ---------------------------------------------------------------- P3-R1: the identifier must come from the CodeDirectory, by structure
good_bin = originals[c0]


def sig_loc(b):
    """-> (position of the LC_CODE_SIGNATURE command, dataoff, datasize)."""
    pos = 32
    for _ in range(struct.unpack("<I", b[16:20])[0]):
        cmd, sz = struct.unpack("<II", b[pos:pos + 8])
        if cmd == 0x1D:
            return (pos,) + struct.unpack("<II", b[pos + 8:pos + 16])
        pos += sz
    raise AssertionError("no signature command")


def blobs(b):
    _pos, off, size = sig_loc(b)
    count = struct.unpack(">I", b[off + 8:off + 12])[0]
    out = []
    for i in range(count):
        t, o = struct.unpack(">II", b[off + 12 + 8 * i:off + 20 + 8 * i])
        out.append((t, off + o, struct.unpack(">I", b[off + o + 4:off + o + 8])[0]))
    return off, size, out


def entries_of(b):
    _off, _size, bl = blobs(b)
    return [(t, b[o:o + n]) for t, o, n in bl]


def rebuild(b, entries):
    """The same image with its SuperBlob rebuilt from (type, blob) entries (duplicates allowed), padded to the old reserved size."""
    off, size, _ = blobs(b)
    first = 12 + 8 * len(entries)
    index, body = b"", b""
    for t, blob in entries:
        index += struct.pack(">II", t, first + len(body))
        body += blob
    sb = struct.pack(">III", 0xFADE0CC0, first + len(body), len(entries)) + index + body
    assert len(sb) <= size
    return b[:off] + sb.ljust(size, b"\0") + b[off + size:]


def patch(b, off, fmt, *v):
    return b[:off] + struct.pack(fmt, *v) + b[off + struct.calcsize(fmt):]


def cd_at(b, kind=0):
    return next(o for t, o, n in blobs(b)[2] if t == kind)


def shrink(b):
    """The same image with the unused reserved signature space cut off (so that two fit in a 64 KiB fat file)."""
    pos, off, size = sig_loc(b)
    return patch(b, pos + 12, "<I", 1024)[:off + 1024]


def fat(images, wide=False):
    each = 32 if wide else 20
    table = 8 + each * len(images)
    out = struct.pack(">II", 0xCAFEBABF if wide else 0xCAFEBABE, len(images))
    placed, off = [], (table + 0xFFF) & ~0xFFF
    for im in images:
        out += struct.pack(">iIQQII", 0x0100000C, 0, off, len(im), 12, 0) if wide else struct.pack(">iIIII", 0x0100000C, 0, off, len(im), 12)
        placed.append((off, im))
        off = (off + len(im) + 0xFFF) & ~0xFFF
    out = bytearray(out)
    for o, im in placed:
        out = out.ljust(o, b"\0") + im
    return bytes(out)


def rej(desc, data, must):
    attempt(build(lines_for={c0: fake_dump(c0, data)}), "P3-R1 reject: " + desc, 1, must=must)


def acc(desc, data):
    rc, so, se, dest = attempt(build(lines_for={c0: fake_dump(c0, data)}), "P3-R1 accept: " + desc, 0)
    check("P3-R1 accept: %s - the file is written byte for byte" % desc, os.path.exists(os.path.join(dest, c0 + ".macho")) and open(os.path.join(dest, c0 + ".macho"), "rb").read() == data)


ID = IDENT.encode()
# the reviewer's pseudo-Mach-O files: the magic and the identifier string, and nothing structural
rej("a Mach-O magic followed by the identifier string only (the reviewer's pseudo file)", b"\xcf\xfa\xed\xfe" + b"\0" * 28 + ID + b"\0", "load commands are missing")
rej("a Mach-O magic, garbage and the identifier string", b"\xcf\xfa\xed\xfe" + b"x" * 28 + ID + b"\0" + b"y" * 300, "load commands are missing")
rej("the magic, a plausible header and the identifier string but no valid commands", b"\xcf\xfa\xed\xfe" + struct.pack("<7I", 0x0100000C, 0, 2, 3, 400, 0, 0) + ID + b"\0" * 400, "load command with a bad size")
rej("a valid unsigned Mach-O that merely contains the identifier string", F.make_macho(c0) + ID + b"\0", "without a code signature")
decoy = make_file("decoy", ident="com.example.other", extra=ID + b"\0junk")
check("P3-R1 setup: the decoy file really contains the expected identifier string (old substring check would have accepted it)", (ID + b"\0") in open(decoy, "rb").read())
rej("a file signed with ANOTHER identifier that contains the expected string elsewhere in the file", open(decoy, "rb").read(), "identifier that is missing, unterminated or not exactly")
d2 = os.path.join(tmp, "src", "teamdecoy")
os.makedirs(d2, exist_ok=True)
p2 = os.path.join(d2, "x")
open(p2, "wb").write(F.make_macho("teamdecoy"))
F.sign_macho_file(p2, "com.example.other", IDENT, {}, open(ents, "rb").read(), False, True, None, True)
rej("another identifier with the expected string used as the team identifier inside the CodeDirectory", open(p2, "rb").read(), "identifier that is missing, unterminated or not exactly")
for bad_ident in (IDENT + ".x", "x" + IDENT, IDENT[:-1], IDENT.upper(), IDENT + "\u00e9"):
    p3 = os.path.join(tmp, "src", "badident")
    os.makedirs(p3, exist_ok=True)
    fp = os.path.join(p3, "y")
    open(fp, "wb").write(F.make_macho("badident"))
    F.sign_macho_file(fp, bad_ident, "TESTTEAM00", {}, open(ents, "rb").read(), False, True, None, True)
    rej("a CodeDirectory identifier that only resembles the expected one (%r)" % bad_ident, open(fp, "rb").read(), "identifier that is missing, unterminated or not exactly")

pos0, sigoff, sigsize = sig_loc(good_bin)
cd0 = cd_at(good_bin)
rej("CodeDirectory identifier offset inside its own header", patch(good_bin, cd0 + 20, ">I", 8), "identifier offset is outside the blob or inside its header")
rej("CodeDirectory identifier offset beyond the blob", patch(good_bin, cd0 + 20, ">I", 0xFFFFFFF0), "identifier offset is outside the blob or inside its header")
rej("CodeDirectory identifier offset redirected to other bytes", patch(good_bin, cd0 + 20, ">I", struct.unpack(">I", good_bin[cd0 + 20:cd0 + 24])[0] + 1), "identifier that is missing, unterminated or not exactly")
cdb = entries_of(good_bin)[0][1]
ioff = struct.unpack(">I", cdb[20:24])[0]
cut = bytearray(cdb[:ioff + len(ID)])        # the identifier string is the last thing in the blob and has NO terminating NUL
cut[4:8] = struct.pack(">I", len(cut))
cut[16:20] = struct.pack(">I", len(cut))
cut[24:32] = struct.pack(">II", 0, 0)
rej("CodeDirectory whose identifier string is the last thing in the blob, with no terminating NUL", rebuild(good_bin, [(0, bytes(cut))] + entries_of(good_bin)[1:]), "identifier offset is outside the blob or inside its header")
rej("CodeDirectory magic wrong", patch(good_bin, cd0, ">I", 0xFADE0C01), "wrong magic")
rej("CodeDirectory shortened through its own length field (which is also the SuperBlob's blob length)", patch(good_bin, cd0 + 4, ">I", 100), "hash arrays do not lie inside")
rej("CodeDirectory hash offset beyond the blob", patch(good_bin, cd0 + 16, ">I", 0xFFFFFF00), "hash arrays do not lie inside")
rej("CodeDirectory with an enormous number of code slots", patch(good_bin, cd0 + 28, ">I", 0xFFFFFFFF), "hash arrays do not lie inside")
rej("CodeDirectory with an enormous number of special slots", patch(good_bin, cd0 + 24, ">I", 0xFFFFFFFF), "hash arrays do not lie inside")
rej("CodeDirectory whose identifier overlaps the hash arrays", patch(good_bin, cd0 + 24, ">I", 50), "overlaps its hash arrays")
rej("CodeDirectory with an unsupported hash size", patch(good_bin, cd0 + 36, ">B", 7), "unsupported hash size")
rej("CodeDirectory with an implausible version", patch(good_bin, cd0 + 8, ">I", 0x10000), "implausible version")
ents0 = entries_of(good_bin)
alt = ents0[0][1].replace(ID + b"\0", b"com.example.disposablX\0", 1)
acc("an extra alternate CodeDirectory (slot 0x1000) with the SAME identifier", rebuild(good_bin, ents0 + [(0x1000, ents0[0][1])]))
rej("a CONFLICTING alternate CodeDirectory (slot 0x1000) with another identifier", rebuild(good_bin, ents0 + [(0x1000, alt)]), "identifier that is missing, unterminated or not exactly")
rej("the primary CodeDirectory is missing (only an alternate one)", rebuild(good_bin, [(0x1000, ents0[0][1])] + ents0[1:]), "without a primary CodeDirectory")
rej("a SuperBlob that lists the primary CodeDirectory type twice", rebuild(good_bin, ents0 + [(0, ents0[0][1])]), "lists a blob type twice")
acc("the signature as the fixture signer wrote it, rebuilt unchanged (the helper itself is sound)", rebuild(good_bin, ents0))
rej("SuperBlob magic wrong", patch(good_bin, sigoff, ">I", 0xFADE0C02), "not an embedded-signature SuperBlob")
rej("SuperBlob length beyond the reserved area", patch(good_bin, sigoff + 4, ">I", sigsize + 1), "bad length or blob count")
rej("SuperBlob length shorter than its index", patch(good_bin, sigoff + 4, ">I", 14), "bad length or blob count")
rej("SuperBlob with zero blobs", patch(good_bin, sigoff + 8, ">I", 0), "bad length or blob count")
rej("SuperBlob with an enormous blob count", patch(good_bin, sigoff + 8, ">I", 0xFFFFFFFF), "bad length or blob count")
rej("SuperBlob blob offset beyond the SuperBlob", patch(good_bin, sigoff + 16, ">I", 0x7FFFFFFF), "blob offset outside the SuperBlob")
rej("SuperBlob blob offset inside the index", patch(good_bin, sigoff + 16, ">I", 4), "blob offset outside the SuperBlob")
rej("SuperBlob blob whose length runs past the SuperBlob", patch(good_bin, cd0 + 4, ">I", 0x7FFFFFFF), "runs past the SuperBlob")
rej("SuperBlob blobs that overlap", patch(good_bin, sigoff + 24, ">I", struct.unpack(">I", good_bin[sigoff + 16:sigoff + 20])[0]), "overlap")
rej("code signature offset inside the Mach-O header and load commands", patch(good_bin, pos0 + 8, "<I", 40), "outside the image or over its headers")
rej("code signature offset beyond the file", patch(good_bin, pos0 + 8, "<I", len(good_bin) + 10), "outside the image or over its headers")
rej("code signature size beyond the file", patch(good_bin, pos0 + 12, "<I", 0x7FFFFFFF), "outside the image or over its headers")
rej("code signature size too small to hold a SuperBlob header", patch(good_bin, pos0 + 12, "<I", 8), "outside the image or over its headers")
rej("an enormous number of load commands", patch(good_bin, 16, "<I", 0xFFFFFFFF), "load commands are missing, too many")
rej("no load commands", patch(good_bin, 16, "<I", 0), "load commands are missing, too many")
rej("a load-command area larger than the image", patch(good_bin, 20, "<I", 0x7FFFFFFF), "load commands are missing, too many")
rej("a load command of size 0", patch(good_bin, 36, "<I", 0), "load command with a bad size")
rej("a load command whose size is not a multiple of 8", patch(good_bin, 36, "<I", 153), "load command with a bad size")
rej("a load command that runs past the load-command area", patch(good_bin, 36, "<I", 0xFFFFFF), "load command with a bad size")
rej("a segment command whose section count does not fit its size", patch(good_bin, 32 + 64, "<I", 5), "segment command whose size does not fit")
rej("fewer load commands than the declared area (sizes do not add up)", patch(good_bin, 16, "<I", 3), "do not add up")
twice = patch(patch(good_bin, 16, "<I", 5), 20, "<I", struct.unpack("<I", good_bin[20:24])[0] + 16)
twice = twice[:32 + struct.unpack("<I", good_bin[20:24])[0]] + good_bin[pos0:pos0 + 16] + twice[32 + struct.unpack("<I", good_bin[20:24])[0] + 16:]
rej("a second LC_CODE_SIGNATURE command", twice, "second one")
rej("a code-signature command of the wrong size", patch(good_bin, pos0 + 4, "<I", 24), "load command with a bad size")
rej("a 32-bit Mach-O magic", b"\xce\xfa\xed\xfe" + good_bin[4:], "neither a 64-bit little-endian Mach-O nor a fat container")
rej("a big-endian 64-bit Mach-O magic", b"\xfe\xed\xfa\xcf" + good_bin[4:], "neither a 64-bit little-endian Mach-O nor a fat container")
rej("a file too small to be a Mach-O", b"\xcf\xfa\xed\xfe" + ID, "too small")

small = shrink(good_bin)
acc("a thin image shrunk to its signature (the helper for the fat tests is sound)", small)
acc("a fat container with ONE valid signed image", fat([small]))
acc("a fat container with TWO valid signed images carrying the same identifier", fat([small, small]))
acc("a 64-bit fat container (CAFEBABF) with one valid signed image", fat([small], wide=True))
unsigned_small = F.make_macho("u")[:0x4100]
rej("a fat container whose second image has another identifier", fat([small, shrink(open(decoy, "rb").read()[:])]), "identifier that is missing, unterminated or not exactly")
rej("a fat container whose second image is only a magic and the identifier string", fat([small, b"\xcf\xfa\xed\xfe" + b"\0" * 28 + ID + b"\0" * 20]), "load commands are missing")
rej("a fat container whose second image is not signed", fat([small, unsigned_small]), "without a code signature")
rej("a fat container with no images", struct.pack(">II", 0xCAFEBABE, 0) + b"\0" * 64, "no, too many or truncated architecture records")
rej("a fat container with an enormous image count", struct.pack(">II", 0xCAFEBABE, 0xFFFFFFFF) + b"\0" * 64, "no, too many or truncated architecture records")
rej("a fat container with more images than the limit", struct.pack(">II", 0xCAFEBABE, 9) + b"\0" * 400, "no, too many or truncated architecture records")
f1 = fat([small])
rej("a fat image that starts inside the fat header", patch(f1, 16, ">I", 4), "lies outside the file or over the header")
rej("a fat image that extends beyond the file", patch(f1, 20, ">I", 0x7FFFFFFF), "lies outside the file or over the header")
f2 = fat([small, small])
rej("two fat images that overlap", patch(f2, 36, ">I", struct.unpack(">I", f2[16:20])[0] + 8), "fat images that overlap")

# ---------------------------------------------------------------- P3-R2: the probe's own result lines must agree
RC = "PROBE-RESULT der_evidence=complete parser=%s fixture_dump=complete"
real_pr = probe_lines[c0][idx(probe_lines[c0], "PROBE-RESULT ")]
real_parser = parser_of(probe_lines[c0])
other_parser = "accepted" if real_parser == "rejected" else "rejected"
check("P3-R2 setup: the real probe printed exactly one PROBE-RESULT line with a parser verdict for the case", sum(l.startswith("PROBE-RESULT ") for l in probe_lines[c0]) == 1 and real_parser in ("accepted", "rejected"), real_pr)


def swap_pr(new):
    return mutate(c0, lambda ls: [new if l.startswith("PROBE-RESULT ") else l for l in ls])


def result_for(parser):
    return {c0: "RESULT %s: signing=ok verify=ok evidence=ok fixture_dump=ok parser=%s => DER evidence obtained" % (c0, parser)}


attempt(build(lines_for=mutate(c0, lambda ls: [l for l in ls if not l.startswith("PROBE-RESULT ")])), "P3-R2 reject: a required case with NO PROBE-RESULT line", 1, must="has 0 PROBE-RESULT")
attempt(build(lines_for=mutate(c0, lambda ls: ls + [real_pr])), "P3-R2 reject: a DUPLICATED identical PROBE-RESULT line (reproduces the reviewer's case)", 1, must="has 2 PROBE-RESULT")
attempt(build(lines_for=mutate(c0, lambda ls: ls + ["PROBE-RESULT der_evidence=INCOMPLETE parser=n/a fixture_dump=INCOMPLETE"])), "P3-R2 reject: a CONTRADICTORY second PROBE-RESULT after a successful final RESULT (reviewer's case)", 1, must="has 2 PROBE-RESULT")
attempt(build(lines_for=mutate(c0, lambda ls: ["PROBE-RESULT der_evidence=INCOMPLETE parser=n/a fixture_dump=INCOMPLETE"] + ls)), "P3-R2 reject: a contradictory PROBE-RESULT line placed BEFORE the dump", 1, must="before (or without) the dump")
attempt(build(lines_for=swap_pr("PROBE-RESULT der_evidence=INCOMPLETE parser=%s fixture_dump=complete" % real_parser), results_override=result_for(real_parser)), "P3-R2 reject: the only PROBE-RESULT reports INCOMPLETE evidence", 1, must="does not report complete evidence")
for fx in ("INCOMPLETE", "not-requested", "complete-ish"):
    attempt(build(lines_for=swap_pr("PROBE-RESULT der_evidence=complete parser=%s fixture_dump=%s" % (real_parser, fx)), results_override=result_for(real_parser)), "P3-R2 reject: the only PROBE-RESULT reports fixture_dump=%s" % fx, 1, must="does not report complete evidence")
for pv in ("n/a", "bogus", ""):
    attempt(build(lines_for=swap_pr("PROBE-RESULT der_evidence=complete parser=%s fixture_dump=complete" % pv), results_override=result_for(real_parser)), "P3-R2 reject: a PROBE-RESULT with parser verdict %r" % pv, 1, must="malformed PROBE-RESULT" if pv == "" else "no parser verdict")
attempt(build(lines_for=swap_pr(RC % other_parser), results_override=result_for(real_parser)), "P3-R2 reject: PROBE-RESULT says parser=%s but the RESULT line says parser=%s (contradiction)" % (other_parser, real_parser), 1,
        must="contradicts", )
attempt(build(lines_for=swap_pr(RC % real_parser), results_override=result_for(other_parser)), "P3-R2 reject: RESULT line says parser=%s but the PROBE-RESULT says parser=%s (contradiction)" % (other_parser, real_parser), 1, must="contradicts")
for bad in ("PROBE-RESULT der_evidence=complete parser=accepted", "PROBE-RESULT der_evidence=complete parser=accepted fixture_dump=complete extra=1",
            "PROBE-RESULT  der_evidence=complete parser=accepted fixture_dump=complete", "PROBE-RESULT der_evidence=complete parser=accepted fixture_dump=complete ", "PROBE-RESULTS der_evidence=complete parser=accepted fixture_dump=complete"):
    attempt(build(lines_for=swap_pr(bad), results_override=result_for("accepted")), "P3-R2 reject: a malformed PROBE-RESULT line (%r)" % bad, 1, must="malformed PROBE-RESULT")
attempt(build(extra_lines=[real_pr]), "P3-R2 reject: a PROBE-RESULT line outside any log group", 1, must="outside the log group")
attempt(build(lines_for=mutate(c0, lambda ls: ls + ["##[endgroup]", "##[group]%s" % c0, real_pr])), "P3-R2 reject: the case's group occurs twice and the second holds another PROBE-RESULT", 1, must="before (or without) the dump")
attempt(build(lines_for=mutate(c0, lambda ls: [real_pr] + ls[:idx(ls, "PROBE-RESULT ")] + ls[idx(ls, "PROBE-RESULT ") + 1:])), "P3-R2 reject: the PROBE-RESULT line comes before its dump", 1, must="before (or without) the dump")
for pv in ("accepted", "rejected"):
    attempt(build(lines_for=swap_pr(RC % pv), results_override=result_for(pv)), "P3-R2 accept: a parser verdict of %s agreeing in both lines (a parser REFUSAL never invalidates complete evidence)" % pv, 0)
attempt(build(extra_lines=["##[group]strings-mac-plain", "PROBE-RESULT der_evidence=INCOMPLETE parser=n/a fixture_dump=not-requested", "PROBE-RESULT whatever", "##[endgroup]"]),
        "P3-R2 accept: PROBE-RESULT lines of other (supporting) cases are not ours and are ignored", 0)

# ---------------------------------------------------------------- P3-R3: the size field is bounded text, never an unbounded number
def with_size(text):
    return mutate(c0, lambda ls: [re.sub(r" [0-9]+ byte\(s\)", " %s byte(s)" % text, l) if l.startswith("PROBE BEGIN-FILE") else l for l in ls])


for desc, size_text, frag in (("5000 digits", "9" * 5000, "short plain decimal number"), ("4301 digits (above Python's own conversion limit)", "1" * 4301, "short plain decimal number"),
                              ("4300 digits", "1" * 4300, "short plain decimal number"), ("1 million digits", "7" * 1000000, "short plain decimal number"),
                              ("6 digits", "100000", "short plain decimal number"), ("a leading zero", "0%d" % len(originals[c0]), "short plain decimal number"), ("leading zeros on a short number", "00123", "short plain decimal number"),
                              ("a leading zero within five digits", "03329", "short plain decimal number"),
                              ("65537 (one above the limit)", "65537", "zero or above"), ("99999", "99999", "zero or above"), ("zero", "0", "zero or above"),
                              ("fullwidth decimal digits", "\uff11\uff12\uff13", "malformed BEGIN-FILE"), ("Arabic-Indic digits", "\u0663\u0664", "malformed BEGIN-FILE"),
                              ("a sign", "+123", "malformed BEGIN-FILE"), ("a minus sign", "-5", "malformed BEGIN-FILE"), ("a decimal point", "1.5", "malformed BEGIN-FILE"),
                              ("hexadecimal", "0x400", "malformed BEGIN-FILE"), ("a thousands separator", "33,296", "malformed BEGIN-FILE"), ("an empty field", "", "malformed BEGIN-FILE")):
    rc, so, se, _ = attempt(build(lines_for=with_size(size_text)), "P3-R3 reject: a BEGIN-FILE size field of %s" % desc, 1, must=frag)
    check("P3-R3 (%s): a controlled message, no traceback, and none of the log's text in it" % desc, "Traceback" not in se and "ValueError" not in se and "9999" not in se and "1111" not in se, se[:160])
okmax = "%d" % len(originals[c0])
attempt(build(lines_for=with_size(okmax)), "P3-R3 accept: the real size as plain decimal digits still works", 0)
many = ["PROBE-DATA " + "A" * 100] * 900
attempt(build(lines_for=mutate(c0, lambda ls: ls[:idx(ls, "PROBE-DATA ")] + many + [l for l in ls if l.startswith("PROBE END-FILE")] + [l for l in ls if l.startswith("PROBE-RESULT")])), "P3-R3 reject: more data lines than a 64 KiB file can need (bounded before decoding)", 1, must="more data lines")

# hostile input
for hostile in ("../evil", "/etc/passwd", "..\\..\\evil", "x/../../y", "runner-ios-xcodelike/../../escape"):
    parent_before = sorted(os.listdir(tmp))
    attempt(build(grp="##[group]" + hostile.replace("%", "%%") + "%s", lines_for=None), "reject: a hostile group name %r (path traversal attempt)" % hostile, 1, must=R)
    hl = [l.replace("%s/" % c0, hostile + "/") for l in probe_lines[c0]]
    attempt(build(lines_for={c0: hl}), "reject: a hostile label %r" % hostile, 1, must=R)
check("hostile input: nothing was created outside the per-test directories",
      not os.path.exists(os.path.join(tmp, "evil")) and not os.path.exists("/etc/passwd.macho") and not os.path.exists(os.path.join(tmp, "escape")))
marker = "EVIL-MARKER-<<<\x1b[31m$(touch /tmp/pwned)>>>"
rc, so, se, _ = attempt(build(extra_lines=["PROBE BEGIN-FILE " + marker]), "reject: a hostile malformed record", 1, must=R)
check("the tool echoes nothing from the log (a marker in a rejected record does not appear in its messages)", marker not in so + se and "EVIL-MARKER" not in so + se, se[:200])
check("hostile input: a command-like string in the log is only text (it was not run)", not os.path.exists("/tmp/pwned"))
huge = os.path.join(tmp, "huge.log")
with open(huge, "wb") as f:
    f.truncate(64 * 1024 * 1024 + 1)
rc, so, se = run(["--log", huge, "--out", os.path.join(tmp, "huge-out")])
check("reject: a log larger than 64 MiB (nothing written)", rc == 1 and not os.path.exists(os.path.join(tmp, "huge-out")) and "larger than 64 MiB" in se, se[:150])
os.remove(huge)

# ---------------------------------------------------------------- destinations and arguments
good = build()
d = os.path.join(tmp, "dest1")
os.makedirs(d)
open(os.path.join(d, "keep.txt"), "w").write("mine")
rc, so, se, _ = attempt(good, "destination: a NON-EMPTY existing directory is refused (exit 2) and its content untouched", 2, dest=d, must="REFUSED", prefilled=True)
check("destination: the refused directory still holds only the user's file", os.listdir(d) == ["keep.txt"] and open(os.path.join(d, "keep.txt")).read() == "mine")
f = os.path.join(tmp, "afile")
open(f, "w").write("x")
attempt(good, "destination: an existing regular file is refused (exit 2)", 2, dest=f, must="REFUSED")
check("destination: the refused file is untouched", open(f).read() == "x")
real = os.path.join(tmp, "realdir")
os.makedirs(real)
link = os.path.join(tmp, "linkdir")
os.symlink(real, link)
attempt(good, "destination: a symbolic link to an empty directory is refused (exit 2)", 2, dest=link, must="REFUSED")
check("destination: nothing was written through the link", os.listdir(real) == [])
attempt(good, "destination: a missing parent directory is refused (exit 2); parents are not created", 2, dest=os.path.join(tmp, "no", "such", "parent", "out"), must="REFUSED")
check("destination: no parent directory was created", not os.path.exists(os.path.join(tmp, "no")))
if hasattr(os, "geteuid") and os.geteuid() != 0:
    ro = os.path.join(tmp, "readonly")
    os.makedirs(ro)
    os.chmod(ro, 0o500)
    attempt(good, "destination: an empty directory that cannot be written is reported (exit 2) and left as it was", 2, dest=ro, must="could not be written")
    check("destination: the unwritable directory still exists and is empty", os.path.isdir(ro) and os.listdir(ro) == [])
    os.chmod(ro, 0o700)
rc, so, se = run(["--out", os.path.join(tmp, "x")])
check("arguments: --log is required (exit 2); there is no default log", rc == 2 and not os.path.exists(os.path.join(tmp, "x")))
rc, so, se = run(["--log", os.path.join(tmp, "case1", "job.log")])
check("arguments: --out is required (exit 2); there is no default destination", rc == 2)
rc, so, se = run(["--log", os.path.join(tmp, "nope.log"), "--out", os.path.join(tmp, "x")])
check("arguments: a log that does not exist is an error (exit 2) and nothing is created", rc == 2 and not os.path.exists(os.path.join(tmp, "x")))
rc, so, se = run(["--log", "-", "--out", os.path.join(tmp, "x")])
check("arguments: standard input is not accepted as the log (exit 2)", rc == 2 and not os.path.exists(os.path.join(tmp, "x")))
rc, so, se = run(["--lo", os.path.join(tmp, "case1", "job.log"), "--out", os.path.join(tmp, "x")])
check("arguments: option abbreviations are not accepted (exit 2)", rc == 2 and not os.path.exists(os.path.join(tmp, "x")))
rc, so, se = run(["--log", tmp, "--out", os.path.join(tmp, "x")])
check("arguments: a directory is not a log (exit 2)", rc == 2)
# the tool leaves no bytecode and runs from any working directory
rc, so, se = run(["--log", os.path.join(tmp, "case1", "job.log"), "--out", os.path.join(tmp, "elsewhere-out")], cwd="/")
check("the tool works from any working directory", rc == 0 and os.path.isdir(os.path.join(tmp, "elsewhere-out")))
check("the tool leaves no __pycache__ beside itself", not os.path.exists(os.path.join(root, "tool", "__pycache__", "extract_probe_fixtures.cpython-%d%d.pyc" % sys.version_info[:2])))

shutil.rmtree(tmp, ignore_errors=True)
PY
)"
echo "$out"
n_ok="$(grep -c '^ok   ' <<<"$out")"
n_bad="$(grep -c '^FAIL ' <<<"$out")"
pass=$((pass + n_ok))
failed=$((failed + n_bad))
[ -n "$out" ] || bad "the Python part of the tests produced no output"
echo
echo "test_extract_probe_fixtures: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
