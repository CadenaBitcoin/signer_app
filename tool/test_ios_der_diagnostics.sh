#!/usr/bin/env bash
# Static tests of the DER entitlements diagnostics of Issue #71 (Phase 2 of the verifier repair): the workflow TEMPLATE
# docs/workflow-templates/ios-der-entitlements-diagnostics.yml.template (it is NOT a workflow: GitHub does not read it),
# tool/probe_der_entitlements.sh and tool/der_entitlements_probe.py.
# They read the files and run the script's own flow against STUB macOS commands; they run nothing on macOS and start
# nothing on GitHub.
#
#   tool/test_ios_der_diagnostics.sh
#
# What they protect: the experiment must be INACTIVE (no executable workflow can start it), and, if it is ever activated,
# stay manual, input-free, credential-free, upload-free, without contact to Apple services, limited to a disposable program,
# bounded in what it prints, and say that success does not prove Apple distribution compatibility.
# (No `grep -q` at the end of a pipeline: under pipefail an early-closed pipe is a SIGPIPE failure.)
# Exit 0 only if every check passes.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/docs/workflow-templates/ios-der-entitlements-diagnostics.yml.template"
script="$root/tool/probe_der_entitlements.sh"
probe="$root/tool/der_entitlements_probe.py"
pass=0
failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }
chk() { # DESCRIPTION CONDITION(0 = good)
  if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi
}

# the experiment is inactive: no file that GitHub reads refers to it
[ ! -e "$root/.github/workflows/ios-der-entitlements-diagnostics.yml" ]; chk "inactive: there is no workflow of that name under .github/workflows/" $?
[ -z "$(grep -rlE 'probe_der_entitlements|der_entitlements_probe|ios-der-entitlements-diagnostics' "$root/.github" 2>/dev/null || true)" ]; chk "inactive: nothing under .github/ (workflows, actions, templates) refers to the probe or to the template" $?
[ -z "$(grep -rl -- 'generate-entitlement-der' "$root/.github" 2>/dev/null || true)" ]; chk "inactive: nothing under .github/ asks Apple's codesign for DER entitlements" $?
case "$wf" in *.yml|*.yaml) false ;; */docs/workflow-templates/*.template) true ;; *) false ;; esac; chk "inactive: the template is under docs/workflow-templates/ and its name is not .yml or .yaml" $?
grep -F "THIS FILE IS A TEMPLATE, NOT A WORKFLOW" "$wf" >/dev/null && grep -F "a separate, explicit authorization" "$wf" >/dev/null; chk "template: says it is not a workflow and what activating it needs" $?
wfcode="$(grep -vE '^[[:space:]]*#' "$wf")"
on_block="$(echo "$wfcode" | sed -n '/^on:/,/^permissions:/p')"
triggers="$(grep -E '^  [a-z_]+:' <<<"$on_block" | tr -d ' :' | tr '\n' ' ')"
[ "$triggers" = "workflow_dispatch " ]; chk "template (if activated): starts only by hand (workflow_dispatch), not on push, pull request or schedule (found: $triggers)" $?
! grep -E 'inputs:' >/dev/null <<<"$on_block"; chk "template (if activated): has no inputs (nothing is chosen by whoever starts it)" $?
perm="$(echo "$wfcode" | sed -n '/^permissions:/,/^concurrency:/p' | grep -E '^  [a-z-]+:' | tr -d ' ' | tr '\n' ' ')"
[ "$perm" = "contents:read " ]; chk "template (if activated): permissions are exactly contents: read (found: $perm)" $?
! grep -E 'secrets\.|environment:|upload-artifact|download-artifact|id-token|workflow_run|pull_request|github\.token|GH_TOKEN' >/dev/null <<<"$wfcode"; chk "template (if activated): no secret, environment, artifact upload/download, OIDC or API token, or pull-request trigger" $?
! grep -iE 'altool|notarytool|testflight|appstoreconnect|app-store-connect|developer\.apple|exportArchive|\.p8|AuthKey|\.mobileprovision|provisioning|keychain|p12|security import' >/dev/null <<<"$wfcode"; chk "template (if activated): no Apple service, export, API-key, provisioning-profile, keychain or certificate reference" $?
! grep -E '\$\{\{' >/dev/null <<<"$wfcode"; chk "template (if activated): no expression reaches a shell (no input, no script injection)" $?
bad_uses="$(grep -E '^[[:space:]]*-?[[:space:]]*uses:' <<<"$wfcode" | grep -vE '@[0-9a-f]{40}( |$)' || true)"
[ -z "$bad_uses" ]; chk "template (if activated): every action is pinned to a full commit SHA" $?
grep -F "runs-on: macos-15" >/dev/null <<<"$wfcode"; chk "template (if activated): runs on macos-15" $?
for key in XCODE_APP EXPECTED_XCODE; do
  a="$(grep -E "^  $key:" "$wf" | head -1 | sed 's/[[:space:]]*#.*//')"
  b="$(grep -E "^  $key:" "$root/.github/workflows/ios-ci-validation.yml" | head -1 | sed 's/[[:space:]]*#.*//')"
  [ -n "$a" ] && [ "$a" = "$b" ]; chk "template (if activated): $key equals the pin of the iOS validation workflow" $?
done
grep -E '^    timeout-minutes: [0-9]+' >/dev/null <<<"$wfcode"; chk "template (if activated): the job has a timeout" $?
[ "$(grep -c 'bash tool/probe_der_entitlements.sh' <<<"$wfcode")" -eq 1 ]; chk "template (if activated): runs the probe script exactly once and nothing else of substance" $?
grep -F "SUCCESS HERE DOES NOT PROVE APPLE DISTRIBUTION COMPATIBILITY" "$wf" >/dev/null && grep -F "does not prove Apple distribution compatibility" "$wf" >/dev/null; chk "template (if activated): states that success does not prove Apple distribution compatibility (header and report)" $?
grep -F "WITHOUT A SEPARATE, EXPLICIT AUTHORIZATION" "$wf" >/dev/null; chk "template (if activated): says it is not to be started without a separate authorization" $?

scode="$(grep -vE '^[[:space:]]*#' "$script")"
! grep -iE 'security |keychain|identity|p12|p8|mobileprovision|provisioning|altool|notarytool|curl|wget|gh |git |ssh|upload|exportArchive|xcodebuild (-exportArchive|-archive)|Runner\.app|\.ipa|xcarchive' >/dev/null <<<"$scode"; chk "script: no keychain, identity, profile, Apple service, network, upload, application, archive or IPA reference" $?
grep -E 'codesign .*-s - ' >/dev/null <<<"$scode" && ! grep -E 'codesign .*-s [^- ]|codesign .*--sign [^-]' >/dev/null <<<"$scode"; chk "script: codesign is only ever called with the ad-hoc identity (-s -)" $?
[ "$(grep -c -- '--timestamp=none' <<<"$scode")" -ge 3 ] && ! grep -E -- '--timestamp([^=]|$)' >/dev/null <<<"$scode"; chk "script: codesign never contacts a timestamp server (--timestamp=none)" $?
[ "$(grep -c 'generate-entitlement-der' <<<"$scode")" -ge 3 ]; chk "script: all three codesign variants ask for the DER entitlements" $?
grep -F 'trap '"'"'rm -rf "$work"'"'"' EXIT' >/dev/null <<<"$scode"; chk "script: removes its work directory on exit" $?
grep -F '[ -e "$work" ]' >/dev/null <<<"$scode"; chk "script: refuses a work directory that already exists (it never reuses or overwrites files)" $?
grep -F "SUCCESS HERE DOES NOT PROVE APPLE DISTRIBUTION COMPATIBILITY" "$script" >/dev/null; chk "script: states that success does not prove Apple distribution compatibility" $?
[ "$(grep -E '^dump_cases=' "$script" | tr -d '"' | sed 's/^dump_cases=//' | wc -w | tr -d ' ')" -eq 3 ]; chk "script: the whole signed file is dumped for exactly three chosen cases" $?
[ "$(grep -c -- '--dump-file' <<<"$scode")" -eq 1 ] && grep -F -- '--synthetic-identifier "$IDENT"' >/dev/null <<<"$scode"; chk "script: --dump-file is given in one place only (the chosen cases) and the probe is always told the synthetic identifier" $?
bash -n "$script"; chk "script: is syntactically valid" $?

# ---- Task A: the three variants of the codesign call (plain; xcodelike = a CONTROLLED variant; logref = the Packaging.log reference) ----
variant_code() { awk -v v="$1" '{ s = $0; gsub(/^[ \t]+|[ \t]+$/, "", s) } s == v ")" {on = 1; next} on && s == ";;" {exit} on {print}' <<<"$scode"; }
has() { grep -F -e "$2" >/dev/null <<<"$1"; }
vp="$(variant_code plain)"; vx="$(variant_code xcodelike)"; vl="$(variant_code logref)"
[ -n "$vp" ] && [ -n "$vx" ] && [ -n "$vl" ]; chk "script: the three variants (plain, xcodelike, logref) are separate, named codesign calls" $?
ok_common=0
for v in "$vp" "$vx" "$vl"; do
  has "$v" "codesign -f -s - " && has "$v" "--timestamp=none" && has "$v" "--generate-entitlement-der" && has "$v" '--entitlements "$work/ents/$case.plist"' || ok_common=1
done
[ "$ok_common" -eq 0 ]; chk "script: every variant is ad hoc (-s -), takes no timestamp, asks for the DER entitlements and signs the explicit entitlements file" $?
has "$vx" '-i "$IDENT"'; chk "script: the controlled xcodelike variant sets the expected CodeDirectory identifier explicitly (-i)" $?
! has "$vx" "--requirements" && ! has "$vx" "anchor apple" && ! has "$vx" "certificate"; chk "script: the controlled xcodelike variant has NO designated requirement and no certificate reference (an ad-hoc signature cannot satisfy one)" $?
has "$vx" "--preserve-metadata=identifier,flags,runtime,launch-constraints,library-constraints" && has "$vx" "--omit-adhoc-flag" && has "$vx" "--signature-size 16000" && has "$vx" "--strip-disallowed-xattrs"; chk "script: the xcodelike variant keeps the other flags of the Packaging.log call" $?
has "$vp" '-i "$IDENT"' && ! has "$vp" "--requirements"; chk "script: the plain variant sets the identifier and has no requirement" $?
has "$vl" "--requirements" && has "$vl" "anchor apple generic" && ! has "$vl" '-i "$IDENT"'; chk "script: the logref reference keeps the Packaging.log call as it is: its certificate-dependent requirement, and no -i" $?
[ "$(grep -c -- '--requirements' <<<"$scode")" -eq 1 ]; chk "script: --requirements occurs once in the whole script, in the exploratory logref call only" $?
dc="$(grep -E '^dump_cases=' "$script")"
! has "$dc" "logref" && has "$dc" "runner-ios-xcodelike" && has "$dc" "arrays-ios-xcodelike" && has "$dc" "runner-mac-plain"; chk "script: the three required cases are the xcodelike and plain ones; the exploratory logref reference is never a required case" $?
grep -F "NOT the command Xcode ran" "$script" >/dev/null && grep -F "EXPLORATORY" "$script" >/dev/null && grep -F "not claimed to reproduce Xcode's Distribution process" "$script" >/dev/null; chk "script: documents that xcodelike is NOT the command Xcode ran, is not claimed to reproduce Xcode's process, and that logref is exploratory" $?

# ---- Task A and C documentation: the variants, the narrow logging exception, the public log, the recovery tool ----
doc="$root/docs/IOS_SIGNING.md"
docx="$(sed -n '/^### 3.1b /,/^### 3.2 /p' "$doc")"
[ -n "$docx" ]; chk "docs: IOS_SIGNING.md has the Phase 3 section 3.1b" $?
for needle in "NOT the command Xcode ran" "not claimed to reproduce Xcode's Distribution process" "**Mandatory** for \`runner-ios-xcodelike\` and \`arrays-ios-xcodelike\`" "**Exploratory**" "never a required case" "without** the certificate-dependent designated requirement" "not an observation"; do
  grep -F -e "$needle" >/dev/null <<<"$docx"; chk "docs 3.1b: says: $needle" $?
done
grep -F "runner-ios-xcodelike" >/dev/null <<<"$docx" && grep -F "runner-mac-plain" >/dev/null <<<"$docx" && grep -F "arrays-ios-xcodelike" >/dev/null <<<"$docx"; chk "docs 3.1b: names the three mandatory cases" $?
grep -F "separate from the exhausted Apple Distribution Authorizations A, B and C" >/dev/null <<<"$docx"; chk "docs 3.1b: says the experiment is separate from the exhausted Authorizations A, B and C" $?
for needle in "narrow exception" "disposable executable generated specifically for this experiment" "explicitly designated synthetic input" "the three approved fixture-capture cases" "a production or staging application" "a real IPA or archive" "a signing credential or certificate" "a provisioning profile" "a secret or any authentication material" "any arbitrary binary given to the probe" "publicly accessible" "There is no general-purpose exception"; do
  grep -F -e "$needle" >/dev/null <<<"$docx"; chk "docs 3.1b (logging exception): says: $needle" $?
done
grep -F "No IPA, profile, certificate or key in an artifact, Release, comment or log." "$doc" >/dev/null && grep -F "Derived values (a decoded profile, a base64 string) are never printed" "$doc" >/dev/null; chk "docs section 7: the original prohibition on printing base64 and signing material is still in place, word for word" $?
grep -F "The only exception is the narrow one for the disposable synthetic fixtures of the DER experiment, section 3.1b; it is not a general exception." "$doc" >/dev/null; chk "docs section 7: points to the one narrow exception and says it is not general" $?
grep -F "tool/extract_probe_fixtures.py" >/dev/null <<<"$docx" && grep -F "Never execute an extracted file" >/dev/null <<<"$docx" && grep -F "default branch" >/dev/null <<<"$docx"; chk "docs 3.1b: gives the evidence-recovery procedure, says never to execute the files, and the default-branch fact for activation" $?
grep -F "NOT the command Xcode ran" "$wf" >/dev/null && grep -F "EXPLORATORY" "$wf" >/dev/null && grep -F "publicly readable" "$wf" >/dev/null && grep -F "tool/extract_probe_fixtures.py" "$wf" >/dev/null; chk "template: names the controlled and the exploratory variants, the public log and the extractor" $?
grep -F "test_extract_probe_fixtures.sh" "$root/.github/workflows/android-release-tests.yml" >/dev/null; chk "CI: the extractor tests run in the iOS signing security job" $?
python3 -I -c "import ast,sys;ast.parse(open(sys.argv[1]).read())" "$probe"; chk "probe: der_entitlements_probe.py is valid Python" $?
! grep -E '^\s*(import|from)\s+(socket|urllib|http|requests|ssl|ftplib|smtplib)' "$probe" >/dev/null; chk "probe: imports nothing that could reach a network" $?

# ---- the script's own flow, against STUB macOS commands ----
# Nothing is signed by Apple's tools. The stub `clang` writes a small, structurally valid Mach-O (tool/ipa_fixture.py) and the
# stub `codesign` signs it ad hoc with the fixture signer, so the probe reads REAL structure; STUB_MODE then makes the stub
# misbehave in the ways that matter: succeed but leave the file unreadable or unsigned, drop the DER blob, write a malformed or
# mis-sealed one, fail verification, or crash the probe. The script must call each of those a failure, and must never call the
# current parser's refusal one.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
real_py="$(python3 -c 'import sys; print(sys.executable)')"  # the interpreter itself, not a version-manager shim
mkdir -p "$tmp/stub"
cat > "$tmp/stubmacho.py" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import ipa_fixture as F
open(sys.argv[2], "wb").write(F.make_macho("stub"))
PY
cat > "$tmp/stubcodesign.py" <<'PY'
import os, struct, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import ipa_fixture as F
import ipa_inspect as I
args = sys.argv[2:]
exe = args[-1]
case = os.path.basename(os.path.dirname(exe))
# STUB_FAULTS="case=mode case=mode": a fault for named cases (the default is a faithful stub); STUB_FAIL_CASES: codesign exits 1
faults = dict(x.split("=", 1) for x in os.environ.get("STUB_FAULTS", "").split() if "=" in x)
mode = faults.get(case, "real")
if case in os.environ.get("STUB_FAIL_CASES", "").split():
    print("stub codesign: refusing %s" % case)
    sys.exit(1)
ents = args[args.index("--entitlements") + 1]
# A MODEL, not Apple's behaviour (which has not been observed): a file signed with a designated requirement anchored in Apple's
# certificate chain fails `codesign --verify` because an ad-hoc signature cannot satisfy it. The shell wrapper reads this marker.
if "--requirements" in args:
    open(exe + ".req", "w").write("requirement")
ident = args[args.index("-i") + 1] if "-i" in args else os.path.basename(exe)
if mode == "other-ident":   # a valid, sealed executable whose CodeDirectory identifier is not the disposable program's
    ident = "com.example.other"
orig_value = F.d_value
def d_value(v):
    if isinstance(v, (bytes, float)) or hasattr(v, "year"):
        return F.der(0x0C, repr(v).encode())
    return orig_value(v)
F.d_value = d_value
if mode == "garbage":      # codesign "succeeds" and leaves a file that is not a Mach-O
    open(exe, "wb").write(b"stubbed")
    sys.exit(0)
if mode == "unsigned":     # codesign "succeeds" and leaves the Mach-O without a signature
    sys.exit(0)
if mode == "no-der":
    F.MUT.add("no-der")
if mode == "parser-rejects":
    F.MUT.add("der-version2")   # a valid ASN.1 blob, sealed, that the CURRENT parser refuses
good = F.der_entitlements_blob
if mode == "bad-asn1":
    F.der_entitlements_blob = lambda e, version=b"\x01": struct.pack(">II", I.CSMAGIC_DER_ENTITLEMENTS, 8 + 6) + b"\x70\x84\xff\xff\xff\xff"
if mode == "trailing-asn1":
    def trailing(e, version=b"\x01"):
        body = good(e)[8:] + b"\x00"
        return struct.pack(">II", I.CSMAGIC_DER_ENTITLEMENTS, 8 + len(body)) + body
    F.der_entitlements_blob = trailing
if mode == "two-elements":
    def two(e, version=b"\x01"):
        body = good(e)[8:] * 2
        return struct.pack(">II", I.CSMAGIC_DER_ENTITLEMENTS, 8 + len(body)) + body
    F.der_entitlements_blob = two
if mode == "bad-length":
    def badlen(e, version=b"\x01"):
        blob = good(e)
        return struct.pack(">II", I.CSMAGIC_DER_ENTITLEMENTS, len(blob) + 1) + blob[8:]
    F.der_entitlements_blob = badlen
if mode == "bad-magic":
    def badmagic(e, version=b"\x01"):
        blob = good(e)
        return struct.pack(">II", 0xfade7171, len(blob)) + blob[8:]
    F.der_entitlements_blob = badmagic
if mode == "empty-der":
    F.der_entitlements_blob = lambda e, version=b"\x01": struct.pack(">II", I.CSMAGIC_DER_ENTITLEMENTS, 8)
try:
    F.sign_macho_file(exe, ident, "TESTTEAM00", {}, open(ents, "rb").read(), False, True, None, True)
except SystemExit:
    sys.exit(1)
except Exception as e:
    print("stub codesign: %s" % type(e).__name__)
    sys.exit(1)
if mode == "oversized":     # a valid, sealed executable larger than the 64 KiB dump limit
    with open(exe, "ab") as f:
        f.write(b"\0" * 70000)
if mode in ("der-seal-mismatch", "xml-seal-mismatch"):
    data = open(exe, "rb").read()
    sl = I.read_signature(exe)["slices"][0]
    blob = sl["der_entitlements_blob"] if mode == "der-seal-mismatch" else sl["entitlements_blob"]
    tampered = blob[:-1] + bytes([blob[-1] ^ 1])
    assert data.count(blob) == 1
    open(exe, "wb").write(data.replace(blob, tampered))
PY
printf '#!/bin/sh\necho Darwin\n' > "$tmp/stub/uname"
printf '#!/bin/sh\nif [ "$3" = "--show-sdk-path" ]; then echo /stub/sdk; exit 0; fi\nout=""\nwhile [ "$#" -gt 0 ]; do if [ "$1" = "-o" ]; then out="$2"; fi; shift; done\n"%s" -I "%s" "%s/tool" "$out"\n' "$real_py" "$tmp/stubmacho.py" "$root" > "$tmp/stub/xcrun"
printf '#!/bin/sh\nout=""\nwhile [ "$#" -gt 0 ]; do if [ "$1" = "-o" ]; then out="$2"; fi; shift; done\n"%s" -I "%s" "%s/tool" "$out"\n' "$real_py" "$tmp/stubmacho.py" "$root" > "$tmp/stub/clang"
# verification and display are answered by the shell itself (fast); only signing runs Python. A fault is looked up by the name
# of the case, which is the name of the directory that holds the executable (the last argument).
printf '#!/bin/sh\necho "stub codesign $*" >> "$STUB_LOG"\nfor last in "$@"; do :; done\ncase "$(basename "$(dirname "$last")")" in *) c="$(basename "$(dirname "$last")")" ;; esac\ncase "$1" in\n  -v) [ -n "${STUB_REQ_FAILS:-}" ] && [ -e "$last.req" ] && { echo "stub (a MODEL of the suspected behaviour, not the real tool): code failed to satisfy its designated requirement"; exit 3; }; case " ${STUB_FAULTS:-} " in *" $c=verify-fails "*) echo "stub: a verification failure"; exit 1 ;; esac; echo "valid on disk"; exit 0 ;;\n  -d) echo "Identifier=stub"; exit 0 ;;\nesac\nexec "%s" -I "%s" "%s/tool" "$@"\n' "$real_py" "$tmp/stubcodesign.py" "$root" > "$tmp/stub/codesign"
printf '#!/bin/sh\necho "Xcode 26.3"\necho "Build version stub"\n' > "$tmp/stub/xcodebuild"
# python3: the real one, except for the PROBE on a case that carries a fault: probe-crash makes it crash; dump-no-end, dump-no-begin,
# dump-short and dump-badsha let it run and then damage its file dump (the probe itself reports a complete dump; only a script that
# checks the dump it received can tell)
cat > "$tmp/stub/python3" <<'STUBPY'
#!/bin/sh
probe=""
for a in "$@"; do case "$a" in *der_entitlements_probe.py) probe=1 ;; esac; done
if [ -n "$probe" ]; then
  for last in "$@"; do :; done
  c="$(basename "$(dirname "$last")")"
  fault=""
  for f in ${STUB_FAULTS:-}; do case "$f" in "$c="*) fault="${f#*=}" ;; esac; done
  case "$fault" in
    probe-crash) echo "Traceback (most recent call last): stub crash" >&2; exit 1 ;;
    dump-no-end|dump-no-begin|dump-short|dump-badsha)
      o="$(@REAL_PY@ "$@")"; r=$?
      case "$fault" in
        dump-no-end) printf '%s\n' "$o" | grep -v '^PROBE END-FILE ' ;;
        dump-no-begin) printf '%s\n' "$o" | grep -v '^PROBE BEGIN-FILE ' ;;
        dump-short) printf '%s\n' "$o" | awk '/^PROBE-DATA /{n++; if (n == 2) next} {print}' ;;
        dump-badsha) printf '%s\n' "$o" | sed '/BEGIN-FILE/s/ sha256 [0-9a-f]\{64\}$/ sha256 0000000000000000000000000000000000000000000000000000000000000000/' ;;
      esac
      exit $r ;;
  esac
fi
exec @REAL_PY@ "$@"
STUBPY
sed -i.bak "s|@REAL_PY@|$real_py|g" "$tmp/stub/python3" && rm -f "$tmp/stub/python3.bak"
chmod +x "$tmp/stub"/*
export STUB_LOG="$tmp/calls.log"
n_run=0
# runmode FAULTS [FAIL_CASES]: runs the whole script against the stubs; sets out and rc
runmode() {
  n_run=$((n_run + 1))
  : > "$STUB_LOG"
  out="$(STUB_FAULTS="${1:-}" STUB_FAIL_CASES="${2:-}" STUB_REQ_FAILS="${STUB_REQ_FAILS:-}" PATH="$tmp/stub:$PATH" bash "$script" "$tmp/work$n_run" 2>&1)"; rc=$?
}
count() { grep -c -- "$1" <<<"$out"; }
# Here-strings, not pipes: under "pipefail" a reader that stops early (grep, awk exit) would make the writing side fail with EPIPE.
block() { awk -v n="::group::$1" '$0 == n {on=1} on {print} $0 == "::endgroup::" && on {exit}' <<<"$out"; }
all_cases=""
for t in ios mac; do
  for c in runner booleans strings integers arrays dicts unsorted many duplicate real data date; do all_cases="$all_cases $c-$t-plain"; done
  all_cases="$all_cases runner-$t-xcodelike arrays-$t-xcodelike runner-$t-logref arrays-$t-logref"
done
required="runner-ios-xcodelike runner-mac-plain arrays-ios-xcodelike"
others=""
for c in $all_cases; do case " $required " in *" $c "*) ;; *) others="$others $c" ;; esac; done
without() { local r="" c; for c in $others; do [ "$c" = "$1" ] || r="$r $c"; done; echo "$r"; }

runmode ""
[ "$rc" -eq 0 ]; chk "script (stub run): exits 0 when every case yields DER evidence" $?
[ "$(count '=> DER evidence obtained')" -eq 32 ]; chk "script (stub run): 32 cases (2 targets x (12 plain + 2 xcodelike + 2 logref)) each count as DER evidence (found $(count '=> DER evidence obtained'))" $?
grep -F "RESULT summary: signing succeeded for 32 case(s); Apple's codesign verified 32; DER evidence obtained for 32" >/dev/null <<<"$out"; chk "script (stub run): the summary tells signing, verification and DER evidence apart" $?
grep -F "RESULT OK: DER evidence and the fixture dump were obtained for every required case" >/dev/null <<<"$out"; chk "script (stub run): says so when every required case produced evidence" $?
[ ! -e "$tmp/work1" ]; chk "script (stub run): the work directory is removed" $?
[ "$(grep -c -- '--generate-entitlement-der' "$STUB_LOG")" -eq 32 ] && [ "$(grep -c -- ' -s - ' "$STUB_LOG")" -eq 32 ]; chk "script (stub run): every codesign call is ad hoc and asks for the DER entitlements" $?
! grep -E -- '--keychain|--sign [^-]|-s [^- ]' "$STUB_LOG" >/dev/null; chk "script (stub run): no codesign call names an identity or a keychain" $?
grep -F "PROBE file " >/dev/null <<<"$out" && grep -F "PROBE-RESULT der_evidence=complete parser=accepted" >/dev/null <<<"$out"; chk "script (stub run): the probe is run on what was signed and reports its evidence status" $?
[ "$(count 'BEGIN-FILE')" -eq 3 ]; chk "script (stub run): the whole signed file is printed for exactly three cases (found $(count 'BEGIN-FILE'))" $?
[ "$(count 'fixture_dump=ok parser=accepted => DER evidence obtained')" -eq 3 ] && [ "$(count '^RESULT .* fixture_dump=not-requested ')" -eq 29 ]; chk "script (stub run): exactly the three required cases report fixture_dump=ok; the other 29 report not-requested" $?
grep -F "requested fixture dumps complete for 3 of 3" >/dev/null <<<"$out"; chk "script (stub run): the summary says the requested fixture dumps are complete (3 of 3)" $?

# (only the SIGNING calls: the log also holds the verify and display calls on the same paths)
xl="$(grep -E ' -f -s - .*/[a-z]+-(ios|mac)-xcodelike/' "$STUB_LOG")"; ll="$(grep -E ' -f -s - .*/[a-z]+-(ios|mac)-logref/' "$STUB_LOG")"
[ "$(grep -c . <<<"$xl")" -eq 4 ] && [ "$(grep -c -- ' -i com.example.disposable ' <<<"$xl")" -eq 4 ] && ! grep -F -- '--requirements' >/dev/null <<<"$xl"; chk "script (stub run): the four xcodelike calls set -i to the disposable identifier and carry no --requirements" $?
[ "$(grep -c . <<<"$ll")" -eq 4 ] && [ "$(grep -c -- '--requirements' <<<"$ll")" -eq 4 ] && ! grep -F -- ' -i ' >/dev/null <<<"$ll"; chk "script (stub run): the four logref calls carry the Packaging.log requirement and no -i" $?
blk="$(block runner-ios-xcodelike)"; grep -F -e "--- role: REQUIRED" <<<"$blk" >/dev/null && grep -F -e "NOT the command Xcode ran" <<<"$blk" >/dev/null; chk "script (stub run): a required xcodelike case says it is REQUIRED and that it is not the command Xcode ran" $?
blk="$(block runner-ios-logref)"; grep -F -e "--- role: EXPLORATORY" <<<"$blk" >/dev/null && grep -F -e "exploratory, never required" <<<"$blk" >/dev/null; chk "script (stub run): a logref case says it is EXPLORATORY and never required" $?
blk="$(block strings-mac-plain)"; grep -F -e "--- role: supporting" <<<"$blk" >/dev/null; chk "script (stub run): a supporting case says it never blocks the run" $?

# Faults in SUPPORTING cases, one fault per case, in one run: each is named, none is counted, and none fails the script.
# The current parser's refusal (parser-rejects) is NOT a fault: it is still DER evidence.
matrix="booleans-ios-plain=garbage strings-ios-plain=unsigned integers-ios-plain=no-der dicts-ios-plain=empty-der unsorted-ios-plain=bad-asn1 many-ios-plain=trailing-asn1 duplicate-ios-plain=two-elements real-ios-plain=bad-length data-ios-plain=bad-magic date-ios-plain=der-seal-mismatch booleans-mac-plain=xml-seal-mismatch strings-mac-plain=verify-fails integers-mac-plain=probe-crash dicts-mac-plain=parser-rejects"
runmode "$matrix"
[ "$rc" -eq 0 ] && [ "$(count '=> DER evidence obtained')" -eq 19 ] && [ "$(count 'NOT DER evidence')" -eq 13 ]; chk "script (stub run): 13 faulty supporting cases are reported and NOT counted (19 evidence), and the script still exits 0 (exit $rc)" $?
grep -F "RESULT summary: signing succeeded for 32 case(s); Apple's codesign verified 31; DER evidence obtained for 19 (the current parser accepted 18 and rejected 1 of those)" >/dev/null <<<"$out"; chk "script (stub run): the summary counts 32 signed, 31 verified, 19 evidence, parser accepted 18 / rejected 1" $?
expect() { # CASE FRAGMENT-OF-ITS-OUTPUT DESCRIPTION
  blk="$(block "$1")"; grep -F -e "$2" <<<"$blk" >/dev/null; chk "script (stub run): $1 $3" $?
}
expect booleans-ios-plain "PROBE-EVIDENCE-PROBLEM not readable as Mach-O" "(codesign succeeded, file unreadable): reported as not readable"
grep -F "RESULT booleans-ios-plain: signing=ok verify=ok evidence=NONE(probe exit 1) fixture_dump=not-requested parser=n/a => NOT DER evidence" >/dev/null <<<"$out"; chk "script (stub run): booleans-ios-plain: signing ok, verify ok, evidence NONE, not counted" $?
expect strings-ios-plain "PROBE-EVIDENCE-PROBLEM slice 0 is not signed" "(codesign succeeded, nothing signed): reported as not signed"
expect integers-ios-plain "PROBE-EVIDENCE-PROBLEM slice 0 has no DER entitlements blob (slot 7)" "(no DER blob): named"
expect dicts-ios-plain "PROBE-EVIDENCE-PROBLEM slice 0: DER entitlements blob: the body is not well-formed ASN.1" "(empty DER body): not well-formed"
expect unsorted-ios-plain "PROBE-EVIDENCE-PROBLEM slice 0: DER entitlements blob: the body is not well-formed ASN.1" "(malformed ASN.1): not well-formed"
expect many-ios-plain "ONE ASN.1 element: 1 byte(s) follow it" "(byte after the element): not ONE element"
expect duplicate-ios-plain "ONE ASN.1 element" "(two elements): not ONE element"
expect real-ios-plain "declared length" "(wrong declared length): reported"
expect data-ios-plain "magic is 0xfade7171" "(wrong magic): reported"
expect date-ios-plain "special slot 7 does not match the blob's hash" "(DER blob not sealed by the CodeDirectory): reported"
expect booleans-mac-plain "special slot 5 does not match the blob's hash" "(XML blob not sealed by the CodeDirectory): reported"
grep -F "RESULT strings-mac-plain: signing=ok verify=FAILED(exit 1) evidence=ok fixture_dump=not-requested parser=accepted => NOT DER evidence" >/dev/null <<<"$out"; chk "script (stub run): strings-mac-plain: Apple's verification failed although the evidence was complete: not counted" $?
grep -F "RESULT integers-mac-plain: signing=ok verify=ok evidence=NONE(probe exit 1) fixture_dump=not-requested parser=n/a => NOT DER evidence" >/dev/null <<<"$out"; chk "script (stub run): integers-mac-plain: the probe crashed: not counted" $?
grep -F "RESULT dicts-mac-plain: signing=ok verify=ok evidence=ok fixture_dump=not-requested parser=rejected => DER evidence obtained" >/dev/null <<<"$out"; chk "script (stub run): dicts-mac-plain: the current parser refuses a valid, sealed blob: STILL DER evidence, refusal reported apart" $?

# A fault in a REQUIRED case fails the script, whatever else succeeded. (All supporting cases are made to fail fast, to keep the run short.)
for pair in garbage unsigned no-der empty-der bad-asn1 trailing-asn1 bad-length der-seal-mismatch xml-seal-mismatch verify-fails probe-crash; do
  runmode "runner-ios-xcodelike=$pair" "$others"
  [ "$rc" -eq 1 ] && grep -F "RESULT FAILED: no suitable DER evidence and fixture dump for the required case(s): runner-ios-xcodelike" >/dev/null <<<"$out" && [ "$(count '=> DER evidence obtained')" -eq 2 ]
  chk "script (stub run): the required case runner-ios-xcodelike with fault '$pair' fails the script although codesign succeeded (exit $rc)" $?
done

# Task A: the EXPLORATORY logref reference may fail in every way (signing, verification, garbage, no DER blob) without failing the run
runmode "runner-ios-logref=garbage arrays-ios-logref=no-der runner-mac-logref=verify-fails" "arrays-mac-logref"
[ "$rc" -eq 0 ] && [ "$(count 'signing=FAILED')" -eq 1 ] && [ "$(count 'NOT DER evidence')" -eq 3 ] && [ "$(count '=> DER evidence obtained')" -eq 28 ] \
  && grep -F "requested fixture dumps complete for 3 of 3" >/dev/null <<<"$out" && grep -F "RESULT OK: DER evidence and the fixture dump were obtained for every required case" >/dev/null <<<"$out"
chk "script (stub run): four failing exploratory logref cases are reported as results (1 signing failure, 3 not evidence) and the run still succeeds (exit $rc)" $?
# a MODEL (not Apple's behaviour, which has not been observed) of the suspected problem: a file signed with a certificate-anchored
# requirement fails Apple's verification. The controlled variants (no requirement) pass; the logref reference fails; the run succeeds.
STUB_REQ_FAILS=1 runmode ""
[ "$rc" -eq 0 ] && [ "$(count 'verify=FAILED(exit 3)')" -eq 4 ] && [ "$(count '^RESULT .*-logref: signing=ok verify=FAILED(exit 3) evidence=ok .* => NOT DER evidence')" -eq 4 ] \
  && grep -F "RESULT summary: signing succeeded for 32 case(s); Apple's codesign verified 28; DER evidence obtained for 28" >/dev/null <<<"$out" \
  && grep -F "requested fixture dumps complete for 3 of 3" >/dev/null <<<"$out"
chk "script (stub run): if a certificate-anchored requirement breaks verification (modelled), the four logref cases are NOT evidence, the controlled variants still are, and the run succeeds (exit $rc)" $?
# the other required cases fail the run when their verification fails
for c in arrays-ios-xcodelike runner-mac-plain; do
  runmode "$c=verify-fails" "$others"
  [ "$rc" -eq 1 ] && grep -F "RESULT FAILED: no suitable DER evidence and fixture dump for the required case(s): $c" >/dev/null <<<"$out" && [ "$(count '=> DER evidence obtained')" -eq 2 ]
  chk "script (stub run): the required case $c with a failing verification fails the run although codesign signed it (exit $rc)" $?
done
# R3: complete DER evidence WITHOUT its requested fixture dump is not a success for a required case
r3() { # DESCRIPTION FAULT EXPECTED-FRAGMENT-OF-THE-CASE-BLOCK
  runmode "runner-ios-xcodelike=$2" "$others"
  [ "$rc" -eq 1 ] && [ "$(count 'RESULT runner-ios-xcodelike: signing=ok verify=ok evidence=ok fixture_dump=INCOMPLETE parser=accepted => NOT a success: DER evidence obtained, but the requested fixture dump is INCOMPLETE')" -eq 1 ] \
    && grep -F "RESULT FAILED: no suitable DER evidence and fixture dump for the required case(s): runner-ios-xcodelike" >/dev/null <<<"$out" \
    && [ "$(count '=> DER evidence obtained')" -eq 2 ] && grep -F "requested fixture dumps complete for 2 of 3" >/dev/null <<<"$out"
  chk "script (stub run): $1: the DER evidence is complete but the requested dump is not, so the required case FAILS the script (exit $rc)" $?
  if [ -n "${3:-}" ]; then blk="$(block runner-ios-xcodelike)"; grep -F -e "$3" <<<"$blk" >/dev/null; chk "script (stub run): ...and the output says why: $3" $?; fi
}
r3 "a valid sealed executable with an unexpected CodeDirectory identifier" other-ident "the requested file dump was not produced: not designated synthetic input"
r3 "a valid sealed executable larger than 64 KiB" oversized "larger than the 65536-byte limit"
r3 "a dump whose END-FILE line is missing (truncated output)" dump-no-end
r3 "a dump whose BEGIN-FILE line is missing" dump-no-begin
r3 "a dump with a data line missing" dump-short
r3 "a dump whose digest does not match its data" dump-badsha
# the same faults in a SUPPORTING case (no dump requested there) change nothing: its evidence is complete and it is not a failure
for fault in other-ident oversized; do
  runmode "strings-mac-plain=$fault" "$(without strings-mac-plain)"
  [ "$rc" -eq 0 ] && grep -F "RESULT strings-mac-plain: signing=ok verify=ok evidence=ok fixture_dump=not-requested parser=accepted => DER evidence obtained" >/dev/null <<<"$out" && grep -F "requested fixture dumps complete for 3 of 3" >/dev/null <<<"$out"
  chk "script (stub run): a supporting case with fault '$fault' has complete evidence and no dump is requested for it (exit $rc)" $?
done
# a required case whose dump is fine and whose evidence is not (the existing distinction), and a parser refusal with a good dump
runmode "runner-ios-xcodelike=parser-rejects" "$others"
[ "$rc" -eq 0 ] && grep -F "evidence=ok fixture_dump=ok parser=rejected => DER evidence obtained" >/dev/null <<<"$out"; chk "script (stub run): a required case the current parser refuses still succeeds when its evidence and dump are complete (exit $rc)" $?

runmode "" "$required $others"
[ "$rc" -eq 1 ] && [ "$(count 'signing=FAILED')" -eq 32 ] && grep -F "RESULT summary: signing succeeded for 0 case(s)" >/dev/null <<<"$out" && grep -F "codesign" >/dev/null <<<"$out"; chk "script (stub run): a codesign that fails everywhere is reported case by case and the script fails (exit $rc)" $?
runmode "" "$others"
[ "$rc" -eq 0 ] && [ "$(count 'signing=FAILED')" -eq 29 ] && [ "$(count '=> DER evidence obtained')" -eq 3 ]; chk "script (stub run): when only the 3 required cases are signed (29 exploratory and supporting cases fail) the script exits 0 (exit $rc)" $?
runmode "" "runner-ios-xcodelike runner-mac-plain $others"
[ "$rc" -eq 1 ] && grep -F "required case(s): runner-ios-xcodelike runner-mac-plain" >/dev/null <<<"$out"; chk "script (stub run): every missing required case is named (exit $rc)" $?

out="$(PATH="$tmp/stub:$PATH" bash "$script" "$tmp" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && grep -F "already exists" >/dev/null <<<"$out"; chk "script (stub run): an existing work directory is refused (and not removed)" $?
[ -d "$tmp" ]; chk "script (stub run): the refused work directory is untouched" $?

# ---- the probe on its own ----
mkdir "$tmp/pf"
STUB_MODE=real STUB_LOG="$tmp/pf.log" "$real_py" -I "$tmp/stubmacho.py" "$root/tool" "$tmp/pf/com.example.disposable"
printf '<?xml version="1.0"?><plist version="1.0"><dict><key>k</key><string>v</string></dict></plist>' > "$tmp/pf/ents.plist"
STUB_MODE=real STUB_LOG="$tmp/pf.log" "$real_py" -I "$tmp/stubcodesign.py" "$root/tool" -f -s - -i com.example.disposable --entitlements "$tmp/pf/ents.plist" "$tmp/pf/com.example.disposable"
pout="$("$real_py" -I "$probe" "$tmp/pf/com.example.disposable" 2>&1)"; prc=$?
[ "$prc" -eq 0 ] && grep -F "PROBE-RESULT der_evidence=complete parser=accepted" >/dev/null <<<"$pout"; chk "probe: complete evidence exits 0 and prints PROBE-RESULT (exit $prc)" $?
! grep -E "DER hex|BEGIN-FILE|'k'" >/dev/null <<<"$pout" && grep -F "raw output is off" >/dev/null <<<"$pout"; chk "probe: without --synthetic-identifier no raw output is printed" $?
pout="$("$real_py" -I "$probe" --synthetic-identifier com.example.disposable "$tmp/pf/com.example.disposable" 2>&1)"; prc=$?
grep -F "DER hex" >/dev/null <<<"$pout" && grep -F "'k'" >/dev/null <<<"$pout"; chk "probe: with the exact identifier raw output is printed" $?
pout="$("$real_py" -I "$probe" --synthetic-identifier com.example.disposable.other "$tmp/pf/com.example.disposable" 2>&1)"
! grep -E "DER hex|'k'" >/dev/null <<<"$pout" && grep -F "RAW OUTPUT WITHHELD" >/dev/null <<<"$pout"; chk "probe: an identifier that only STARTS with the given one (or a longer one) gets no raw output (exact match)" $?
pout="$("$real_py" -I "$probe" --synthetic-identifier com.example "$tmp/pf/com.example.disposable" 2>&1)"
! grep -F "DER hex" >/dev/null <<<"$pout"; chk "probe: a prefix of the identifier is not enough either" $?
printf 'not a mach-o' > "$tmp/pf/garbage"
# fixture_dump: reported apart from the evidence, and a requested dump that was not produced fails the probe
pout="$("$real_py" -I "$probe" --synthetic-identifier com.example.disposable --dump-file "$tmp/pf/com.example.disposable" 2>&1)"; prc=$?
[ "$prc" -eq 0 ] && grep -F "PROBE-RESULT der_evidence=complete parser=accepted fixture_dump=complete" >/dev/null <<<"$pout" && grep -E "^PROBE BEGIN-FILE .* [0-9]+ byte\(s\) sha256 [0-9a-f]{64}$" >/dev/null <<<"$pout" && grep -F "PROBE END-FILE" >/dev/null <<<"$pout"; chk "probe: a requested dump of a designated file is complete: exit 0, fixture_dump=complete, BEGIN-FILE with size and digest, END-FILE (exit $prc)" $?
echo "$pout" | "$real_py" -I -c '
import base64, hashlib, re, sys
t = sys.stdin.read().splitlines()
m = [re.match(r"^PROBE BEGIN-FILE \S+ (\d+) byte\(s\) sha256 ([0-9a-f]{64})$", l) for l in t]
b = next(x for x in m if x)
raw = base64.b64decode("".join(l[11:] for l in t if l.startswith("PROBE-DATA ")))
orig = open(sys.argv[1], "rb").read()
sys.exit(0 if raw == orig and int(b.group(1)) == len(orig) and hashlib.sha256(orig).hexdigest() == b.group(2) else 1)' "$tmp/pf/com.example.disposable"; chk "probe: the emitted dump decodes to exactly the executable (bytes, size and SHA-256)" $?
pout="$("$real_py" -I "$probe" --synthetic-identifier com.example.disposable "$tmp/pf/com.example.disposable" 2>&1)"; prc=$?
[ "$prc" -eq 0 ] && grep -F "fixture_dump=not-requested" >/dev/null <<<"$pout" && ! grep -F "BEGIN-FILE" >/dev/null <<<"$pout"; chk "probe: without --dump-file, fixture_dump=not-requested and nothing is dumped (exit $prc)" $?
pout="$("$real_py" -I "$probe" --synthetic-identifier com.example.other --dump-file "$tmp/pf/com.example.disposable" 2>&1)"; prc=$?
[ "$prc" -eq 1 ] && grep -F "PROBE-RESULT der_evidence=complete parser=accepted fixture_dump=INCOMPLETE" >/dev/null <<<"$pout" && grep -F "PROBE-DUMP-PROBLEM the requested file dump was not produced: not designated synthetic input" >/dev/null <<<"$pout" && ! grep -E "BEGIN-FILE|PROBE-DATA" >/dev/null <<<"$pout"; chk "probe: a requested dump of a file with another identifier is withheld: evidence complete, fixture_dump=INCOMPLETE, exit 1 (exit $prc)" $?
pout="$("$real_py" -I "$probe" --dump-file "$tmp/pf/com.example.disposable" 2>&1)"; prc=$?
[ "$prc" -eq 1 ] && grep -F "fixture_dump=INCOMPLETE" >/dev/null <<<"$pout" && ! grep -E "BEGIN-FILE|PROBE-DATA" >/dev/null <<<"$pout"; chk "probe: --dump-file without --synthetic-identifier produces no dump and exits 1 (exit $prc)" $?
cp "$tmp/pf/com.example.disposable" "$tmp/pf/big"
"$real_py" -I -c 'import sys; open(sys.argv[1], "ab").write(b"\0" * 70000)' "$tmp/pf/big"
pout="$("$real_py" -I "$probe" --synthetic-identifier com.example.disposable --dump-file "$tmp/pf/big" 2>&1)"; prc=$?
[ "$prc" -eq 1 ] && grep -F "PROBE-RESULT der_evidence=complete parser=accepted fixture_dump=INCOMPLETE" >/dev/null <<<"$pout" && grep -F "larger than the 65536-byte limit" >/dev/null <<<"$pout" && ! grep -E "BEGIN-FILE|PROBE-DATA" >/dev/null <<<"$pout"; chk "probe: a valid sealed file larger than 64 KiB has complete evidence but its requested dump is refused: exit 1 (exit $prc)" $?
pout="$("$real_py" -I "$probe" --synthetic-identifier com.example.disposable "$tmp/pf/big" 2>&1)"; prc=$?
[ "$prc" -eq 0 ]; chk "probe: the same large file WITHOUT a requested dump is fine (exit $prc): the dump limit concerns only the dump" $?
pout="$("$real_py" -I "$probe" --synthetic-identifier com.example.disposable --dump-file "$tmp/pf/garbage" 2>&1)"; prc=$?
[ "$prc" -eq 1 ] && grep -F "der_evidence=INCOMPLETE parser=n/a fixture_dump=INCOMPLETE" >/dev/null <<<"$pout"; chk "probe: an unreadable file with a requested dump is INCOMPLETE in both respects (exit $prc)" $?
pout="$("$real_py" -I "$probe" --synthetic-identifier com.example.disposable --dump-file "$tmp/pf/missing" 2>&1)"; prc=$?
[ "$prc" -eq 2 ] && grep -F "fixture_dump=INCOMPLETE" >/dev/null <<<"$pout"; chk "probe: a missing file with a requested dump is INCOMPLETE and exits 2 (exit $prc)" $?

pout="$("$real_py" -I "$probe" "$tmp/pf/garbage" 2>&1)"; prc=$?
[ "$prc" -eq 1 ] && grep -F "PROBE-RESULT der_evidence=INCOMPLETE parser=n/a" >/dev/null <<<"$pout"; chk "probe: an unreadable file exits 1 with der_evidence=INCOMPLETE (exit $prc)" $?
pout="$("$real_py" -I "$probe" "$tmp/pf/missing" 2>&1)"; prc=$?
[ "$prc" -eq 2 ] && grep -F "der_evidence=INCOMPLETE" >/dev/null <<<"$pout"; chk "probe: a file that does not exist exits 2 and is INCOMPLETE (exit $prc)" $?
pout="$("$real_py" -I "$probe" "$tmp/pf/com.example.disposable" "$tmp/pf/garbage" 2>&1)"; prc=$?
[ "$prc" -eq 1 ] && [ "$(grep -c 'der_evidence=complete' <<<"$pout")" -eq 1 ] && [ "$(grep -c 'der_evidence=INCOMPLETE' <<<"$pout")" -eq 1 ]; chk "probe: with several files one incomplete result makes the exit status nonzero and each file has its own result" $?
# a CMS-signed file never gets raw output even with the right identifier (checked on the fixture's real signer)
cms_ok=0
if "$real_py" -I - "$root" "$tmp/pf" >/dev/null <<'PY'
import os, sys, subprocess
sys.dont_write_bytecode = True
root, d = sys.argv[1:3]
sys.path.insert(0, os.path.join(root, "tool"))
import ipa_fixture as F, ipa_inspect as I
cd = os.path.join(d, "certs")
F.make_certs(cd)
certs = {"leaf": os.path.join(cd, "leaf.crt"), "key": os.path.join(cd, "leaf.key"), "intermediate": os.path.join(cd, "intermediate.crt")}
open(os.path.join(d, "cms.bin"), "wb").write(F.make_macho("cms"))
F.sign_macho_file(os.path.join(d, "cms.bin"), "com.example.disposable", "SYNTH12345", {}, open(os.path.join(d, "ents.plist"), "rb").read(), False, False, certs, True)
PY
then
  pout="$("$real_py" -I "$probe" --synthetic-identifier com.example.disposable "$tmp/pf/cms.bin" 2>&1)"
  if ! grep -F "DER hex" >/dev/null <<<"$pout" && grep -F "RAW OUTPUT WITHHELD" >/dev/null <<<"$pout"; then cms_ok=1; fi
fi
[ "$cms_ok" -eq 1 ]; chk "probe: a file with a CMS signature gets no raw output even with the exact identifier" $?

echo
echo "test_ios_der_diagnostics: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
