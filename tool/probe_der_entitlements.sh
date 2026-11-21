#!/usr/bin/env bash
# DER ENTITLEMENTS PROBE (Issue #71, Phase 2 of the verifier repair). macOS only. Credential-free.
#
#   tool/probe_der_entitlements.sh WORK_DIR        (WORK_DIR must not exist yet)
#
# Question: what does a DER entitlements blob written by APPLE'S OWN `codesign --generate-entitlement-der` really look
# like? tool/ipa_inspect.py parse_der_entitlements assumes a layout (the dictionary as a SET) that was taken from public
# descriptions and never checked against Apple's output; on the first Apple-signed IPA (Authorization C, run
# 44834801248) it refused the real blob with "unsupported DER entitlements version or layout", and that blob was not
# kept. This script produces new ones, from scratch, with nothing of the application in them:
#
#   1. it compiles a tiny DISPOSABLE executable (a C program that does nothing), once for iOS arm64 and once for macOS;
#   2. for each of a set of explicit XML entitlements (the keys of the real app, then every value type) it makes a copy
#      and signs it AD HOC (`codesign -s -`, no identity, no keychain, no timestamp server) with --generate-entitlement-der,
#      in up to three variants (see section 3): PLAIN, XCODELIKE (a controlled variant: the flags Xcode used for the real app
#      with the certificate-dependent requirement removed and the identifier set; it is NOT the command Xcode ran) and LOGREF
#      (the Packaging.log call itself with substituted team and certificate-name values; exploratory, never blocking);
#   3. it asks Apple's own `codesign` to verify and display the result, and prints, with tool/der_entitlements_probe.py, the file
#      identity, the CodeDirectory facts, the special-slot seals, the DER blob (size, digest, bytes in hex), an ASN.1 outline that
#      assumes no layout, and, for THREE chosen cases only, the whole signed file (base64) for use as a test fixture. Raw output
#      is printed because this script itself built and signed the disposable program in a fresh directory. The probe is given
#      the program's exact CodeDirectory identifier as an explicit raw-output control and withholds raw output from a file whose
#      identifier differs or that carries a CMS signature; that is a safeguard against printing a real application by mistake,
#      NOT proof of where a file came from (see tool/der_entitlements_probe.py).
#
# A case is DER evidence only if signing, Apple's verification AND the probe's evidence checks all succeed (see section 3);
# the current parser's verdict is reported and never required. The exit status is 0 only if every required case produced
# evidence, so a run in which codesign "succeeded" but wrote nothing usable fails.
#
# What it must never do (tool/test_ios_der_diagnostics.sh checks this statically):
#   - use a certificate, identity, keychain, provisioning profile, App Store Connect key, password or any secret;
#   - touch the application, the archive or any file of the repository other than this checkout's own tools;
#   - contact Apple or any other service; upload or keep anything: it prints text and removes WORK_DIR.
#
# WHAT IT PROVES AND WHAT IT DOES NOT. An ad-hoc signature written by Apple's tool is genuine evidence of the FORMAT Apple's
# codesign writes for DER entitlements. The Packaging.log of run 44834801248 shows that Xcode's own local call for every
# item, the main app included, is an ad-hoc call (`codesign -f -s - ... --generate-entitlement-der`), that the cloud service
# is sent only the CodeDirectory digest, and that its CMS signature is attached afterwards (`codesign -e --edit-cms`). So the
# blob in a cloud-signed IPA was written by a call of the kind made here, which makes this strong evidence of its layout; it
# is still not a proof about that IPA (its entitlements and exact flags differ).
# SUCCESS HERE DOES NOT PROVE APPLE DISTRIBUTION COMPATIBILITY.
set -uo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "probe_der_entitlements: macOS only (it needs Apple's codesign and clang)." >&2
  exit 2
fi
if [ "$#" -ne 1 ]; then
  echo "usage: tool/probe_der_entitlements.sh WORK_DIR" >&2
  exit 2
fi
work="$1"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
probe="$here/der_entitlements_probe.py"
[ -r "$probe" ] || { echo "probe_der_entitlements: $probe is missing." >&2; exit 2; }
if [ -e "$work" ]; then
  echo "probe_der_entitlements: $work already exists; it must be a fresh, empty location." >&2
  exit 2
fi
mkdir -p "$work/ents" "$work/bin/ios" "$work/bin/mac" "$work/out" || exit 2
trap 'rm -rf "$work"' EXIT

TEAM="TESTTEAM00"
IDENT="com.example.disposable"

# ---- 1. the disposable executables ------------------------------------------------------------------------------------
cat > "$work/disposable.c" <<'EOF'
/* A disposable test program. It does nothing and belongs to nobody. */
int main(void) { return 0; }
EOF
sdk_ios="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
targets=""
if [ -n "$sdk_ios" ] && xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=14.0 -isysroot "$sdk_ios" -o "$work/bin/ios/$IDENT" "$work/disposable.c" 2>"$work/clang-ios.txt"; then
  targets="ios"
else
  echo "RESULT build ios FAILED: $(tr '\n' ' ' < "$work/clang-ios.txt" 2>/dev/null | cut -c1-200)"
fi
if clang -arch arm64 -o "$work/bin/mac/$IDENT" "$work/disposable.c" 2>"$work/clang-mac.txt"; then
  targets="$targets mac"
else
  echo "RESULT build mac FAILED: $(tr '\n' ' ' < "$work/clang-mac.txt" 2>/dev/null | cut -c1-200)"
fi
[ -n "$targets" ] || { echo "RESULT no disposable executable could be built"; exit 1; }
echo "RESULT built disposable executables for:$targets"
echo "tools: $(xcodebuild -version | tr '\n' ' ')| $(codesign --version 2>&1 | head -1) | $(python3 --version 2>&1)"

# ---- 2. the XML entitlements, written out explicitly --------------------------------------------------------------------
# ent NAME 'BODY' writes $work/ents/NAME.plist with BODY (the dictionary's content) inside <dict>.
ent() {
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n%s\n</dict>\n</plist>\n' "$2" > "$work/ents/$1.plist"
}
long200="$(printf 'a%.0s' $(seq 1 200))"
manykeys=""
i=1
while [ "$i" -le 60 ]; do
  manykeys="$manykeys<key>com.example.key$(printf '%02d' "$i")</key><string>value$i</string>"
  i=$((i + 1))
done

# the four keys of the real application's entitlements (Authorization C, evidence v5-entitlements.txt), with a fake team
ent runner "<key>application-identifier</key><string>$TEAM.$IDENT</string>
<key>beta-reports-active</key><true/>
<key>com.apple.developer.team-identifier</key><string>$TEAM</string>
<key>get-task-allow</key><false/>"
ent booleans '<key>com.example.yes</key><true/><key>com.example.no</key><false/>'
ent strings "<key>com.example.empty</key><string></string><key>com.example.ascii</key><string>hello world</string><key>com.example.unicode</key><string>caf&#233; &#26085;&#26412;</string><key>com.example.long</key><string>$long200</string>"
ent integers '<key>com.example.i0</key><integer>0</integer><key>com.example.i1</key><integer>1</integer><key>com.example.i127</key><integer>127</integer><key>com.example.i128</key><integer>128</integer><key>com.example.i255</key><integer>255</integer><key>com.example.i256</key><integer>256</integer><key>com.example.i65535</key><integer>65535</integer><key>com.example.neg1</key><integer>-1</integer><key>com.example.neg128</key><integer>-128</integer><key>com.example.neg129</key><integer>-129</integer><key>com.example.i32max</key><integer>2147483647</integer>'
ent arrays '<key>com.example.empty</key><array/><key>com.example.strings</key><array><string>a</string><string>b</string></array><key>com.example.nested</key><array><array><string>x</string></array></array><key>com.example.dicts</key><array><dict><key>k</key><string>v</string></dict></array><key>com.example.mixed</key><array><string>s</string><true/><integer>7</integer></array>'
ent dicts '<key>com.example.empty</key><dict/><key>com.example.nested</key><dict><key>b</key><string>2</string><key>a</key><dict><key>z</key><true/><key>y</key><false/></dict></dict>'
ent unsorted '<key>zzz</key><string>last-in-order-first-in-file</string><key>aaa</key><string>first-in-order-last-in-file</string><key>mmm</key><string>middle</string><key>AAA</key><string>upper</string><key>aa</key><string>prefix</string>'
ent many "$manykeys"
# exploratory: what does Apple's tool do with these? (a failure is a result, not an error of this script)
ent duplicate '<key>com.example.dup</key><string>first</string><key>com.example.dup</key><string>second</string>'
ent real '<key>com.example.real</key><real>1.5</real>'
ent data '<key>com.example.data</key><data>AAECAw==</data>'
ent date '<key>com.example.date</key><date>2026-01-02T03:04:05Z</date>'
cases="runner booleans strings integers arrays dicts unsorted many duplicate real data date"
# The signed file is printed in full (base64, at most 64 KiB) for these three cases only (the REQUIRED cases): the XCODELIKE call on
# the real app's four entitlements for iOS, the PLAIN call on them for macOS, and the XCODELIKE call on the richest value case for iOS.
# Every case still gets its file identity, CodeDirectory facts, special-slot seals, DER size, digest and ASN.1 structure, and its DER hex.
# No LOGREF case is ever a required case: it is the exploratory reference call (see below) and its result never fails the script.
dump_cases="runner-ios-xcodelike runner-mac-plain arrays-ios-xcodelike"

# ---- 3. sign ad hoc with Apple's codesign, verify with it, and print what was written ------------------------------------
# Four DIFFERENT things are told apart for every case, and only the last two decide whether DER evidence was obtained:
#   signing   = Apple's codesign exited 0 (it says nothing about what is in the file);
#   verify    = Apple's `codesign --verify --strict` accepts the result;
#   evidence  = tool/der_entitlements_probe.py exited 0: the file reads as Mach-O, every slice is signed and has a CodeDirectory,
#               the DER blob (slot 7) and the XML blob (slot 5) are present, the DER container and ONE ASN.1 element are well formed,
#               and the CodeDirectories seal both blobs with matching hashes;
#   parser    = whether the CURRENT parser (tool/ipa_inspect.py) accepts the DER. This is the SUBJECT of the investigation: it is
#               reported and NEVER required, because it may legitimately refuse genuine Apple data.
#   fixture   = for the three dump_cases only: the COMPLETE signed executable was actually emitted (BEGIN-FILE with its size and
#               SHA-256, the base64 data, END-FILE) and this script decoded it and found the size and digest to agree. Complete DER
#               evidence without its requested dump is NOT a success: the dump is the fixture the investigation needs.
# THE THREE VARIANTS (the name of a case is CASE-TARGET-VARIANT):
#   plain      codesign -f -s - -i IDENT --timestamp=none --entitlements E --generate-entitlement-der   (every case; REQUIRED for
#              runner-mac-plain, supporting otherwise);
#   xcodelike  a CONTROLLED variant of the flags Xcode used for the real app: the same ad-hoc call with --signature-size,
#              --preserve-metadata, --omit-adhoc-flag, --team-identifier, --strip-disallowed-xattrs and -vvv, but with the identifier
#              set explicitly (-i IDENT) and WITHOUT the certificate-dependent designated requirement (only for the cases runner and
#              arrays; REQUIRED for runner-ios and arrays-ios, supporting otherwise). It is NOT the command Xcode ran,
#              and it is not claimed to reproduce Xcode's Distribution process. The requirement is removed because an ad-hoc
#              signature cannot satisfy a requirement anchored in Apple's certificate chain, which would make Apple's own
#              `codesign --verify` (a condition of DER evidence) fail for a reason unrelated to the DER entitlements;
#   logref     the call as the Packaging.log of run 44834801248 shows it, with a made-up team and a made-up certificate name and
#              WITHOUT -i, INCLUDING its certificate-dependent designated requirement (only for runner and arrays; EXPLORATORY:
#              kept as reference evidence of what Apple's tool does with that call on an ad-hoc signature; whether it signs, whether
#              it verifies and what it writes is a result, and a failure of it never fails the script).
# A case counts as DER evidence only if signing, verify and evidence all succeeded. A REQUIRED case (the three dump_cases) is a
# SUCCESS only if, in addition, its fixture dump is complete; the script exits 0 only if every required case succeeded. The other
# cases are supporting or exploratory: their results and diagnostics are printed in full, but a failure of one does not fail the
# script.
# Reads the probe's output on stdin and succeeds only if it holds ONE complete, self-consistent file dump: BEGIN-FILE with a size and
# a SHA-256, the PROBE-DATA lines, then END-FILE, and the decoded bytes have exactly that size and digest. (Python 3, standard library.)
check_dump='
import base64, hashlib, re, sys
begin = end = None
data = []
lines = sys.stdin.read().splitlines()
for i, ln in enumerate(lines):
    m = re.match(r"^PROBE BEGIN-FILE \S+ (\d+) byte\(s\) sha256 ([0-9a-f]{64})$", ln)
    if m:
        if begin is not None:
            sys.exit(1)
        begin = (i, int(m.group(1)), m.group(2))
    elif ln.startswith("PROBE END-FILE "):
        if end is not None:
            sys.exit(1)
        end = i
    elif ln.startswith("PROBE-DATA ") and begin is not None and end is None:
        data.append(ln[len("PROBE-DATA "):])
if begin is None or end is None or end < begin[0] or not data:
    sys.exit(1)
try:
    raw = base64.b64decode("".join(data), validate=True)
except Exception:
    sys.exit(1)
sys.exit(0 if len(raw) == begin[1] and begin[1] > 0 and hashlib.sha256(raw).hexdigest() == begin[2] else 1)
'
n_signed=0; n_verified=0; n_evidence=0; n_accept=0; n_reject=0; n_fixture=0
ok_cases=" "
n_dump_cases="$(echo $dump_cases | wc -w | tr -d ' ')"
for target in $targets; do
  for case in $cases; do
    for variant in plain xcodelike logref; do
      # the Xcode-derived variants are only needed for the real application's own entitlements and one rich case
      if [ "$variant" != "plain" ] && [ "$case" != "runner" ] && [ "$case" != "arrays" ]; then continue; fi
      name="$case-$target-$variant"
      mkdir "$work/out/$name"
      exe="$work/out/$name/$IDENT"
      cp "$work/bin/$target/$IDENT" "$exe"
      case "$variant" in
        plain)
          codesign -f -s - -i "$IDENT" --timestamp=none --entitlements "$work/ents/$case.plist" --generate-entitlement-der "$exe" > "$work/out/$name.codesign.txt" 2>&1
          ;;
        xcodelike)
          # CONTROLLED variant (not the command Xcode ran): the flags of the Packaging.log call, with the identifier set explicitly
          # (-i) and with no designated requirement (no --requirements): an ad-hoc signature cannot satisfy a requirement anchored in
          # Apple's certificate chain, and Apple's own `codesign --verify` is a condition of DER evidence
          codesign -f -s - -i "$IDENT" --timestamp=none --signature-size 16000 --entitlements "$work/ents/$case.plist" \
            --preserve-metadata=identifier,flags,runtime,launch-constraints,library-constraints --omit-adhoc-flag \
            --team-identifier "$TEAM" --generate-entitlement-der --strip-disallowed-xattrs -vvv "$exe" > "$work/out/$name.codesign.txt" 2>&1
          ;;
        logref)
          # EXPLORATORY reference: the arguments of the codesign call Xcode made for the real app (Packaging.log, run 44834801248),
          # with a made-up team and a made-up certificate name in the requirement text, and no -i, as in the log. Its designated
          # requirement is anchored in Apple's certificate chain, which an ad-hoc signature cannot satisfy: whether Apple's tool signs
          # and verifies it is exactly what this case records. It is never a required case.
          codesign -f -s - --timestamp=none --signature-size 16000 --entitlements "$work/ents/$case.plist" \
            --requirements "=designated => anchor apple generic and identifier \"$IDENT\" and certificate leaf[subject.CN] = \"Disposable Test Signer ($TEAM)\" and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */" \
            --preserve-metadata=identifier,flags,runtime,launch-constraints,library-constraints --omit-adhoc-flag \
            --team-identifier "$TEAM" --generate-entitlement-der --strip-disallowed-xattrs -vvv "$exe" > "$work/out/$name.codesign.txt" 2>&1
          ;;
      esac
      rc=$?
      if [ "$rc" -ne 0 ]; then
        echo "RESULT $name: signing=FAILED (exit $rc) verify=not-run evidence=NONE fixture_dump=not-run parser=n/a: $(tr '\n' ' ' < "$work/out/$name.codesign.txt" | cut -c1-240)"
        continue
      fi
      n_signed=$((n_signed + 1))
      echo "::group::$name"
      role="supporting (reported in full, never blocks the run)"
      for c in $dump_cases; do [ "$c" = "$name" ] && role="REQUIRED (the run fails unless it has DER evidence and its fixture dump)"; done
      case "$variant" in
        plain) vnote="plain ad-hoc call with the identifier set" ;;
        xcodelike) vnote="CONTROLLED Xcode-like variant: the Packaging.log flags with -i and WITHOUT the certificate-dependent designated requirement; NOT the command Xcode ran" ;;
        logref) vnote="REFERENCE: the Packaging.log call with substituted team and certificate name, INCLUDING its certificate-dependent designated requirement; exploratory, never required" ;;
      esac
      [ "$variant" = "logref" ] && role="EXPLORATORY (a failure here is a result, never an error of the run)"
      echo "--- role: $role"
      echo "--- variant: $vnote"
      echo "--- codesign -v --strict -vvv"
      vout="$(codesign -v --strict -vvv "$exe" 2>&1)"; vrc=$?
      printf '%s\n' "$vout" | sed 's/^/  /'
      echo "--- codesign -d -vvv (the signature as Apple's tool shows it)"
      codesign -d -vvv "$exe" 2>&1 | sed 's/^/  /'
      echo "--- codesign -d --entitlements :- (the XML entitlements as Apple's tool shows them)"
      codesign -d --entitlements :- "$exe" 2>&1 | sed 's/^/  /'
      echo "--- tool/der_entitlements_probe.py"
      # raw output (strings, DER bytes, XML entitlements) only because this is a DISPOSABLE program: the probe is told its exact
      # identifier IDENT and withholds raw output from anything else; the whole signed file is printed for the chosen cases only
      dump=""
      for c in $dump_cases; do [ "$c" = "$name" ] && dump="--dump-file"; done
      pout="$(python3 -I "$probe" --synthetic-identifier "$IDENT" $dump "$exe" 2>&1)"; prc=$?
      printf '%s\n' "$pout"
      echo "::endgroup::"
      verify="ok"; [ "$vrc" -eq 0 ] && n_verified=$((n_verified + 1)) || verify="FAILED(exit $vrc)"
      parser="n/a"
      case "$(grep -E '^PROBE-RESULT ' <<<"$pout" | head -1)" in
        *"parser=accepted"*) parser="accepted" ;;
        *"parser=rejected"*) parser="rejected" ;;
      esac
      # The probe's own verdict on the evidence. Its exit status is 0 when evidence AND any requested dump are complete, 1 when one of
      # them is not, 2 when it failed itself; so exit 1 still means complete evidence if, and only if, the result line says the
      # evidence is complete and the dump is the incomplete part.
      if { [ "$prc" -eq 0 ] || { [ "$prc" -eq 1 ] && grep -F "fixture_dump=INCOMPLETE" >/dev/null <<<"$pout"; }; } \
         && grep -F "PROBE-RESULT der_evidence=complete" >/dev/null <<<"$pout" \
         && ! grep -F "der_evidence=INCOMPLETE" >/dev/null <<<"$pout"; then evidence="ok"; else evidence="NONE(probe exit $prc)"; fi
      fixture="not-requested"
      if [ -n "$dump" ]; then
        if [ "$prc" -eq 0 ] && grep -F "fixture_dump=complete" >/dev/null <<<"$pout" \
           && ! grep -F "fixture_dump=INCOMPLETE" >/dev/null <<<"$pout" \
           && printf '%s\n' "$pout" | python3 -I -c "$check_dump"; then
          fixture="ok"; n_fixture=$((n_fixture + 1))
        else
          fixture="INCOMPLETE"
        fi
      fi
      if [ "$vrc" -eq 0 ] && [ "$evidence" = "ok" ]; then
        n_evidence=$((n_evidence + 1))
        [ "$parser" = "accepted" ] && n_accept=$((n_accept + 1))
        [ "$parser" = "rejected" ] && n_reject=$((n_reject + 1))
        if [ "$fixture" = "INCOMPLETE" ]; then
          echo "RESULT $name: signing=ok verify=$verify evidence=$evidence fixture_dump=$fixture parser=$parser => NOT a success: DER evidence obtained, but the requested fixture dump is INCOMPLETE"
        else
          ok_cases="$ok_cases$name "
          echo "RESULT $name: signing=ok verify=$verify evidence=$evidence fixture_dump=$fixture parser=$parser => DER evidence obtained"
        fi
      else
        echo "RESULT $name: signing=ok verify=$verify evidence=$evidence fixture_dump=$fixture parser=$parser => NOT DER evidence"
      fi
    done
  done
done
echo "RESULT summary: signing succeeded for $n_signed case(s); Apple's codesign verified $n_verified; DER evidence obtained for $n_evidence (the current parser accepted $n_accept and rejected $n_reject of those); requested fixture dumps complete for $n_fixture of $n_dump_cases; WORK_DIR is removed on exit"
missing=""
for c in $dump_cases; do
  case "$ok_cases" in *" $c "*) ;; *) missing="$missing $c" ;; esac
done
if [ -n "$missing" ]; then
  echo "RESULT FAILED: no suitable DER evidence and fixture dump for the required case(s):$missing"
  exit 1
fi
echo "RESULT OK: DER evidence and the fixture dump were obtained for every required case"
exit 0
