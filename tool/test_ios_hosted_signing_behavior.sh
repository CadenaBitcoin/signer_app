#!/usr/bin/env bash
# BEHAVIOUR and MUTATION tests of the hosted iOS signing workflow (Issue #71, docs/IOS_HOSTED_SIGNING.md).
#
#   tool/test_ios_hosted_signing_behavior.sh
#
# tool/test_ios_hosted_signing.sh reads the workflow file for strings. That cannot tell whether the workflow still behaves safely:
# an independent audit showed six dangerous edits that every string check passed. These tests RUN the real steps of the workflow
# (their `run:` scripts, extracted from the YAML) on synthetic input, with stub `git`, `xcodebuild` and `plutil` and SYNTHETIC
# credentials, and they read the parsed YAML structurally. Nothing here signs, contacts Apple or GitHub, or uses a real
# credential. Then, unless HOSTED_SIGNING_NO_MUTATIONS=1, every dangerous edit that the audit found (and more) is applied to a
# COPY of the workflow and the tests must catch it.
#
# HOSTED_SIGNING_WORKFLOW=path runs the tests against another copy of the workflow (that is how the mutations are tried).
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="${HOSTED_SIGNING_WORKFLOW:-$root/.github/workflows/ios-hosted-signing.yml}"
self="${BASH_SOURCE[0]}"
if ! python3 -c 'import yaml' 2>/dev/null; then
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "FAIL PyYAML is required in CI"; exit 1; fi
  echo "skipped: PyYAML is not installed here (the hosted Linux runner has it)"; exit 0
fi
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }
chk() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "${3:-}"; fi; }

SHA=42d358a4e7bcbf85b92aa992ec6439214dbd4405
VER=1.0.4+1000035
BID=com.app.cadenabitcoin
TEAM=D65458CPDP
WFSHA=1111111111111111111111111111111111111111
OLDSHA=2222222222222222222222222222222222222222
REC=docs/release-records/ios-1.0.4-1000035.md
DLC_OK=9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13   # the archive hash of both diagnostics runs (proposed initial value)
RUSTSHA=203dcd7abe4187de0b756638a55f691b2d5c680b17d4fbfa7dda550ed703949b
REAL_GIT="$(command -v git)"

# --- the steps of the workflow, extracted from the YAML into files: <job>.<n>.sh with a name index ---
steps="$tmp/steps"; mkdir -p "$steps"
python3 -I - "$wf" "$steps" <<'PY'
import sys, yaml, json, os
d = yaml.safe_load(open(sys.argv[1]))
out = sys.argv[2]
index = []
for j, v in d["jobs"].items():
    for i, st in enumerate(v["steps"]):
        fn = None
        if "run" in st:
            fn = "%s.%02d.sh" % (j, i)
            open(os.path.join(out, fn), "w").write(st["run"])
        index.append({"job": j, "i": i, "name": st.get("name", ""), "file": fn, "uses": st.get("uses"), "with": st.get("with"), "env": st.get("env"), "if": st.get("if"), "run": st.get("run")})
json.dump({"index": index, "jobs": {j: {k: v[k] for k in v if k != "steps"} for j, v in d["jobs"].items()}, "top_env": d.get("env"), "on": d.get(True, d.get("on"))}, open(os.path.join(out, "index.json"), "w"))
PY
sf() { # JOB NAME_PREFIX -> the extracted script file of the step
  python3 -I - "$steps/index.json" "$1" "$2" "$steps" <<'PY'
import sys, json, os
idx = json.load(open(sys.argv[1]))["index"]
m = [s for s in idx if s["job"] == sys.argv[2] and s["name"].startswith(sys.argv[3]) and s["file"]]
if len(m) != 1:
    sys.exit(1)
print(os.path.join(sys.argv[4], m[0]["file"]))
PY
}
for pair in "authorize|Validate the inputs|vin_a" "build|Validate the inputs|vin_b" "sign|Validate the inputs|vin_s" \
            "authorize|Check the release record|gate" "sign|Re-check the authorization|recheck" \
            "sign|Export and sign|secret" "sign|Seal the evidence|seal" "sign|Check the archive digest|archive" "sign|Enforce the authorized dlc_wallet|dlc"; do
  IFS='|' read -r j n v <<<"$pair"
  f="$(sf "$j" "$n")" && eval "STEP_$v=\"$f\"" || { bad "the workflow has exactly one step '$n' in job $j"; eval "STEP_$v=/nonexistent"; }
done

# ============================================================================================================================
# 1. Structure (parsed YAML, not strings)
# ============================================================================================================================
python3 -I - "$steps/index.json" > "$tmp/structure.txt" <<'PY'
import sys, json, re
data = json.load(open(sys.argv[1]))
idx, jobs = data["index"], data["jobs"]
res = []
def chk(desc, cond, detail=""):
    res.append(("ok  " if cond else "FAIL") + " " + desc + ((" :: " + detail) if (detail and not cond) else ""))

CHECKOUT = "actions/checkout@11d5960a326750d5838078e36cf38b85af677262"
FLUTTER = "subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2"
UP = "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"
DOWN = "actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093"
allowed = {"authorize": {CHECKOUT}, "build": {CHECKOUT, FLUTTER, UP}, "sign": {CHECKOUT, DOWN, UP}}
for j in ("authorize", "build", "sign"):
    used = {s["uses"].split(" ")[0] for s in idx if s["job"] == j and s["uses"]}
    chk("job %s uses only the allowed, SHA-pinned actions (no other third-party action)" % j, used <= allowed[j], str(sorted(used - allowed[j])))
chk("exactly the jobs authorize, build and sign", set(jobs) == {"authorize", "build", "sign"})

sign = [s for s in idx if s["job"] == "sign"]
sec_i = [s["i"] for s in sign if s["env"] and any("secrets." in str(v) for v in s["env"].values())]
chk("exactly one step of the signing job reads secrets", len(sec_i) == 1, str(sec_i))
secret_step = next((s for s in sign if s["i"] in sec_i), None)
if secret_step:
    chk("that step's environment holds exactly the three secrets and nothing else", sorted(secret_step["env"]) == ["APPLE_API_ISSUER_ID", "APPLE_API_KEY_ID", "APPLE_API_KEY_P8"], str(sorted(secret_step["env"])))
    chk("and its name is the documented one", secret_step["name"].startswith("Export and sign with the cloud-managed Distribution certificate"))
others = [s for s in idx if (s["job"], s["i"]) != ("sign", sec_i[0] if sec_i else -1) and ("secrets." in json.dumps({"e": s["env"], "w": s["with"], "r": s["run"], "i": s["if"]}))]
chk("no other step of any job refers to a secret", not others, str([(s["job"], s["name"]) for s in others]))
chk("no job or workflow level environment, secret or variable", not any(jobs[j].get("env") for j in jobs) and "secrets." not in json.dumps(data["top_env"]) and all("secrets." not in json.dumps(jobs[j]) for j in jobs))
chk("only the signing job has an environment, and it is ios-hosted-signing", [j for j in jobs if jobs[j].get("environment")] == ["sign"] and jobs["sign"]["environment"] == "ios-hosted-signing")
chk("the trigger is workflow_dispatch only", list((data["on"] or {}).keys()) == ["workflow_dispatch"])

ar_i = next((s["i"] for s in sign if s["name"].startswith("Check the archive digest")), None)
pre = [s for s in sign if sec_i and s["i"] < sec_i[0]]
post = [s for s in sign if sec_i and s["i"] > sec_i[0]]
# no code of the approved commit, of the archive or of the hand-over is executed anywhere in the signing job
INTERP = re.compile(r"(?:^|[;&|(`]|\$\()\s*(?:sudo\s+)?(bash|/bin/bash|sh|/bin/sh|zsh|source|\.|python3?|perl|ruby|node|osascript|swift|make|xcrun|env)\s+((?:-\S+\s+)*)(\S+)", re.M)
OK_TARGET = re.compile(r'^"?(tools/tool/[A-Za-z_]+\.(py|sh)|\$RUNNER_TEMP/redact\.py|\$\{RUNNER_TEMP\}/redact\.py|-u|-)"?$')
bad_exec = []
for s in sign:
    txt = "\n".join(l for l in (s["run"] or "").splitlines() if not l.strip().startswith("#"))
    for m in INTERP.finditer(txt):
        interp, opts, target = m.group(1), m.group(2), m.group(3)
        if interp in ("env",):
            continue   # `env -u NAME command` is checked through its command below
        if interp == "xcrun":
            bad_exec.append((s["name"], m.group(0).strip())); continue
        if not OK_TARGET.match(target):
            bad_exec.append((s["name"], m.group(0).strip()))
    stripped = txt.replace("approved/pubspec.yaml", "").replace("git -C approved", "")
    if re.search(r"""(^|[\s"'=:/])(\./)?approved/|cd\s+approved""", stripped):
        bad_exec.append((s["name"], "uses a path of the approved checkout beyond its pubspec.yaml / git rev-parse"))
chk("the signing job executes no script of the approved commit, of the archive or of the hand-over (interpreter targets are tools/tool/*, redact.py)", not bad_exec, str(bad_exec))
cmd_exec = []
for s in sign:
    for ln in (s["run"] or "").splitlines():
        t = ln.strip()
        if re.match(r'^(\./|"?\$\{?(APP|ARCHIVE|BASELINE_APP|IPA|X|ARCHIVE_PATH|ARCHIVE_APP)\b[^ ]*"?\s*($|\s))', t):
            cmd_exec.append((s["name"], t))
chk("no command of the signing job is a file of the archive, the app or the IPA", not cmd_exec, str(cmd_exec))
envwrites = []
for s in pre:
    for ln in (s["run"] or "").splitlines():
        m = re.search(r'>>\s*"?\$\{?(GITHUB_ENV|GITHUB_PATH)\}?"?', ln)
        if m:
            envwrites.append(ln.strip())
names = set(re.match(r'\s*echo "([A-Z_a-z0-9]+)=', l).group(1) for l in envwrites if re.match(r'\s*echo "([A-Z_a-z0-9]+)=', l))
chk("steps before the secret step write only ARCHIVE, BASELINE_APP, RUST_LIB_SHA256, VERIFIER_REPO to GITHUB_ENV, never PATH", len(names) == len(envwrites) and names <= {"ARCHIVE", "BASELINE_APP", "RUST_LIB_SHA256", "VERIFIER_REPO"} and not any("GITHUB_PATH" in l for l in envwrites), str(envwrites))
dlcs = [s for s in sign if s["name"].startswith("Enforce the authorized dlc_wallet")]
chk("the signing job has exactly one dlc_wallet hash step", len(dlcs) == 1)
if dlcs and secret_step and ar_i is not None:
    d = dlcs[0]
    chk("the dlc_wallet hash step runs after the archive is extracted and BEFORE the secret step", ar_i < d["i"] < secret_step["i"], "%s %s %s" % (ar_i, d["i"], secret_step["i"]))
    chk("it holds no secret and reads the authorized hash through the gate script (--print-field G2S-DLC-WALLET-SHA256)", not d["env"] or all("secrets." not in str(v) for v in d["env"].values()))
    chk("and it compares strictly (a mismatch exits non-zero)", "--print-field G2S-DLC-WALLET-SHA256" in d["run"] and re.search(r'\[ "\$actual" != "\$authorized" \]', d["run"]) is not None and "exit 1" in d["run"])
dl = [s for s in sign if s["uses"] and s["uses"].startswith("actions/download-artifact@")]
chk("the hand-over is downloaded from THIS run only (no run-id, no token, no pattern)", len(dl) == 1 and set((dl[0]["with"] or {}).keys()) == {"name", "path"} and "github.run_id" in dl[0]["with"]["name"])
ar = next((s for s in sign if s["name"].startswith("Check the archive digest")), None)
if ar:
    t = ar["run"]
    a, b, c = t.find("validate_handover_archive.py list"), t.find("tar -xf"), t.find("validate_handover_archive.py tree")
    chk("the archive's member list is validated BEFORE tar extracts it, and its tree AFTER", 0 <= a < b < c, "%d %d %d" % (a, b, c))
    chk("the archive is extracted exactly once, and the digest is compared before anything is read", t.count("tar -xf") == 1 and t.find("shasum") < a)
chk("tar -x appears nowhere else in the signing job", sum((s["run"] or "").count("tar -x") for s in sign) == 1)
chk("the key never reaches an artifact: the only artifact paths are evidence/ and the unsigned tar", all((s["with"] or {}).get("path") in ("evidence/", "handover/Runner.xcarchive.tar") for s in idx if s["uses"] and s["uses"].startswith("actions/upload-artifact@")))
print("\n".join(res))
PY
while IFS= read -r line; do
  case "$line" in "ok  "*) ok "structure: ${line#ok   }" ;; FAIL*) bad "structure: ${line#FAIL }" ;; esac
done < "$tmp/structure.txt"

# ============================================================================================================================
# 2. Input validation: whole-string match (a value with a second line must not pass)
# ============================================================================================================================
good_env=(APPROVED_SHA="$SHA" CONTENT_REF=862831e0b3a0f30c4155d2e086c69fc28bdab286 EXPECTED_VERSION="$VER" EXPECTED_CERT_SHA256="" GITHUB_REF=refs/heads/development)
for v in vin_a vin_b vin_s; do
  f="$(eval echo \$STEP_$v)"
  env -i PATH="$PATH" "${good_env[@]}" bash -e "$f" >/dev/null 2>&1; chk "validation ($v): good inputs pass" $?
  for var in APPROVED_SHA CONTENT_REF EXPECTED_VERSION; do
    case "$v|$var" in "vin_s|CONTENT_REF") continue ;; esac
    case "$var" in EXPECTED_VERSION) val="1.0.4+1000035"; ;; *) val="$SHA" ;; esac
    env -i PATH="$PATH" "${good_env[@]}" "$var=$(printf '%s\nzz' "$val")" bash -e "$f" >/dev/null 2>&1; [ $? -ne 0 ]; chk "validation ($v): a two-line $var is refused (first line valid, second line junk)" $?
    env -i PATH="$PATH" "${good_env[@]}" "$var=$(printf 'zz\n%s' "$val")" bash -e "$f" >/dev/null 2>&1; [ $? -ne 0 ]; chk "validation ($v): a two-line $var is refused (junk first, valid second line)" $?
  done
  cert64=$(printf 'a%.0s' $(seq 1 64))
  case "$v" in vin_a|vin_s)
    env -i PATH="$PATH" "${good_env[@]}" EXPECTED_CERT_SHA256="$cert64" bash -e "$f" >/dev/null 2>&1; chk "validation ($v): a 64-hex pin passes" $?
    env -i PATH="$PATH" "${good_env[@]}" EXPECTED_CERT_SHA256="$(printf 'zz\n%s' "$cert64")" bash -e "$f" >/dev/null 2>&1; [ $? -ne 0 ]; chk "validation ($v): a pin with a junk first line is refused" $?
    env -i PATH="$PATH" "${good_env[@]}" EXPECTED_CERT_SHA256=$'\n' bash -e "$f" >/dev/null 2>&1; [ $? -ne 0 ]; chk "validation ($v): a pin that is only a line break is refused" $? ;;
  esac
done

# ============================================================================================================================
# 3. The authorization gate AS WIRED in the workflow: the authorize step and the re-check in the signing job
# ============================================================================================================================
stubdir="$tmp/stub"; mkdir -p "$stubdir"
cat > "$stubdir/git" <<'EOF'
#!/bin/bash
# STUB: answers `git ls-remote` with the tip in STUB_TIP (nothing when empty); every other command is the real git.
if [ "${1:-}" = ls-remote ]; then [ -n "${STUB_TIP:-}" ] && printf '%s\trefs/heads/development\n' "$STUB_TIP"; exit 0; fi
exec "$REAL_GIT" "$@"
EOF
chmod +x "$stubdir/git"

# The record as it was BEFORE any G2S authorization: no G2S line, no D14 row, the nine G2S rows back to "Proposed". The tests build their
# fixtures from this, so they hold whether or not the committed record already carries the authorization (and stay valid after it is withdrawn).
neutral_record() { # IN OUT
  awk '/^G2S-/ { next } /^\| D14 \| / { next } { print }' "$1" | awk '
    BEGIN { n = split("D3 D6 D7 D8 D9 D10 D11 D12", a, " "); for (i = 1; i <= n; i++) want[i] = "| " a[i] " | " }
    { for (i = 1; i <= n; i++) if (index($0, want[i]) == 1) sub(/\| Decided \| [^|]*\| [0-9-]+ \|[ ]*$/, "| Proposed, not decided | TBD | TBD |"); print }' > "$2"
}
mkws() { # DIR : the files the gate reads, with the WORKFLOW UNDER TEST, and the record before any authorization
  rm -rf "$1"; mkdir -p "$1/.github/workflows" "$1/docs/release-records"
  mkdir -p "$1/tool"; cp "$root"/tool/{check_signing_authorization.sh,build_manifest.py,ipa_inspect.py,validate_handover_archive.py,verify_artifact.sh,verify_ipa.py} "$1/tool/"
  cp "$wf" "$1/.github/workflows/ios-hosted-signing.yml"
  neutral_record "$root/docs/release-records/ios-1.0.4-1000035.md" "$1/$REC"
}
decide_rows() { # RECORD ROWS... : the rows become Decided (what the CTO's record pull request would do)
  local rec="$1" id; shift
  for id in "$@"; do
    awk -v id="$id" 'index($0, "| " id " | ") == 1 { sub(/\| [^|]*\| TBD \| TBD \|[ ]*$/, "| Decided | CTO | 2026-11-21 |") } { print }' "$rec" > "$rec.n" && mv "$rec.n" "$rec"
  done
}
authorize_ws() { # DIR : decided rows, the D14 row and the G2S lines that match DIR's own files
  local ws="$1" rec="$1/$REC"
  decide_rows "$rec" D3 D6 D7 D8 D9 D10 D11 D12
  awk '{ print } index($0, "| D13 | ") == 1 { print "| D14 | **Credential decision (test fixture)** | Decided | CTO | 2026-11-21 |" }' "$rec" > "$rec.n" && mv "$rec.n" "$rec"
  { echo
    echo "G2S-STATUS: AUTHORIZED"; echo "G2S-OPERATION: sign-and-verify-only"; echo "G2S-APPROVED-SHA: $SHA"; echo "G2S-VERSION: $VER"
    echo "G2S-BUNDLE-ID: $BID"; echo "G2S-TEAM-ID: $TEAM"
    bash "$ws/tool/check_signing_authorization.sh" --print-expected --tools-root "$ws"
    echo "G2S-DLC-WALLET-SHA256: $DLC_OK"
    echo "G2S-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-1234567890"
  } >> "$rec"
}
GATE_RC=0; GATE_AUTH=""
run_authorize() { # WS TIP [VAR=value ...]   (the authorize job's gate step, in WS as the workspace)
  local ws="$1" tip="$2" t; shift 2; t="$(mktemp -d -p "$tmp")"; : > "$t/out"; : > "$t/sum"
  ( cd "$ws" && env -i PATH="$stubdir:$PATH" HOME="$HOME" REAL_GIT="$REAL_GIT" STUB_TIP="$tip" GITHUB_REF=refs/heads/development GITHUB_EVENT_NAME=workflow_dispatch \
      GITHUB_SHA="$WFSHA" GITHUB_SERVER_URL=https://example.invalid GITHUB_REPOSITORY=example/repo RUNNER_TEMP="$t" GITHUB_STEP_SUMMARY="$t/sum" GITHUB_OUTPUT="$t/out" \
      APPROVED_SHA="$SHA" EXPECTED_VERSION="$VER" BUNDLE_ID="$BID" TEAM_ID="$TEAM" "$@" bash -e "$STEP_gate" > "$t/stdout" 2>&1 ); GATE_RC=$?
  GATE_AUTH="$(sed -n 's/^authorized=//p' "$t/out")"
}
RECHECK_RC=0
run_recheck() { # WS TIP [VAR=value ...]   (the signing job's re-check; WS is copied to tools/)
  local ws="$1" tip="$2" w; shift 2; w="$(mktemp -d -p "$tmp")"; cp -r "$ws" "$w/tools"
  ( cd "$w" && env -i PATH="$stubdir:$PATH" HOME="$HOME" REAL_GIT="$REAL_GIT" STUB_TIP="$tip" GITHUB_SHA="$WFSHA" GITHUB_SERVER_URL=https://example.invalid GITHUB_REPOSITORY=example/repo \
      APPROVED_SHA="$SHA" EXPECTED_VERSION="$VER" BUNDLE_ID="$BID" TEAM_ID="$TEAM" "$@" bash -e "$STEP_recheck" > "$w/stdout" 2>&1 ); RECHECK_RC=$?
}
# Both: expect(not authorized) / (authorized)
refused() { # NAME WS TIP [env]
  local name="$1" ws="$2" tip="$3"; shift 3
  run_authorize "$ws" "$tip" "$@"; [ "$GATE_RC" -eq 0 ] && [ "$GATE_AUTH" = false ]; chk "authorize job: $name -> authorized=false" $? "rc=$GATE_RC auth='$GATE_AUTH'"
  run_recheck "$ws" "$tip" ; [ "$RECHECK_RC" -ne 0 ]; chk "signing job re-check: $name -> stops before any secret" $? "rc=$RECHECK_RC"
}
base="$tmp/ws_real"; mkws "$base"
refused "G1 alone: the committed record has no G2S line (tip == revision)" "$base" "$WFSHA"
good="$tmp/ws_good"; mkws "$good"; authorize_ws "$good"
run_authorize "$good" "$WFSHA"; [ "$GATE_RC" -eq 0 ] && [ "$GATE_AUTH" = true ]; chk "authorize job: a complete, matching, current authorization -> authorized=true" $? "rc=$GATE_RC auth='$GATE_AUTH'"
run_recheck "$good" "$WFSHA"; chk "signing job re-check: the same authorization passes" $RECHECK_RC
refused "a historical revision (the tip moved on; a re-run of an old run)" "$good" "$OLDSHA"
refused "the tip of development cannot be read" "$good" ""
run_authorize "$good" "$WFSHA" GITHUB_REF=refs/heads/issue/x; [ "$GATE_AUTH" = false ]; chk "authorize job: a branch other than development -> authorized=false" $?
run_authorize "$good" "$WFSHA" GITHUB_REF=refs/tags/development; [ "$GATE_AUTH" = false ]; chk "authorize job: a tag named development -> authorized=false" $?
run_authorize "$good" "$WFSHA" GITHUB_EVENT_NAME=push; [ "$GATE_AUTH" = false ]; chk "authorize job: an event other than workflow_dispatch -> authorized=false" $?
# the implementation is bound: any change invalidates the authorization
for f in .github/workflows/ios-hosted-signing.yml tool/check_signing_authorization.sh tool/verify_ipa.py tool/ipa_inspect.py tool/build_manifest.py tool/verify_artifact.sh tool/validate_handover_archive.py; do
  w="$tmp/ws_mod"; rm -rf "$w"; cp -r "$good" "$w"; printf '\n# changed after the authorization\n' >> "$w/$f"
  refused "$f changed after the authorization (authorization is bound to the implementation)" "$w" "$WFSHA"
done
# the record (the gate script's own cases; they do not depend on the workflow, so the nested mutation runs skip them)
if [ "${HOSTED_SIGNING_QUICK:-0}" != 1 ]; then
mutrec() { # NAME awk/sed-style python replacement via sed -E expression
  local name="$1" expr="$2" w="$tmp/ws_rec"; rm -rf "$w"; cp -r "$good" "$w"; sed -E "$expr" "$w/$REC" > "$w/$REC.n" && mv "$w/$REC.n" "$w/$REC"; refused "$name" "$w" "$WFSHA"
}
for key in G2S-STATUS G2S-OPERATION G2S-APPROVED-SHA G2S-VERSION G2S-BUNDLE-ID G2S-TEAM-ID G2S-WORKFLOW-BLOB G2S-GATE-BLOB G2S-TOOL-BLOBS G2S-DLC-WALLET-SHA256 G2S-AUTHORIZATION; do
  mutrec "the record lacks $key" "/^$key: /d"
done
mutrec "status NOT AUTHORIZED" 's/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: NOT AUTHORIZED/'
mutrec "a contradicting second status line" 's/^(G2S-STATUS: AUTHORIZED)$/\1\nG2S-STATUS: WITHDRAWN/'
mutrec "an operation that includes upload" 's/^G2S-OPERATION: .*/G2S-OPERATION: sign-and-upload/'
mutrec "another approved SHA" "s/^G2S-APPROVED-SHA: .*/G2S-APPROVED-SHA: $OLDSHA/"
mutrec "another version" 's/^G2S-VERSION: .*/G2S-VERSION: 1.0.5+1000036/'
mutrec "another bundle ID" 's/^G2S-BUNDLE-ID: .*/G2S-BUNDLE-ID: com.app.cadenabitcoin.staging/'
mutrec "another team" 's/^G2S-TEAM-ID: .*/G2S-TEAM-ID: ABCDE12345/'
mutrec "a stale tool blob" 's/(tool\/verify_ipa\.py=)[0-9a-f]{40}/\10000000000000000000000000000000000000000/'
mutrec "an authorization on another issue" 's#issues/71#issues/72#'
mutrec "a withdrawn record (status line)" 's/`G1 AUTHORIZED`/`WITHDRAWN`/'
mutrec "a draft record" 's/`G1 AUTHORIZED`/`DRAFT`/'
mutrec "CRLF line endings" 's/$/\r/'
mutrec "G2S lines inside a fenced code block" 's/^(G2S-STATUS: AUTHORIZED)$/```\n\1/; $a ```'
mutrec "G2S lines inside an HTML comment" 's/^(G2S-STATUS: AUTHORIZED)$/<!--\n\1/; $a -->'
mutrec "an APPROVED_SHA row that names another commit" "s/\*\*\`$SHA\`\*\*/**\`$OLDSHA\`**/"
for id in D3 D6 D7 D8 D9 D10 D11 D12; do
  w="$tmp/ws_rec"; rm -rf "$w"; cp -r "$good" "$w"
  awk -v id="$id" 'index($0, "| " id " | ") == 1 { sub(/\| Decided \| CTO \| 2026-11-21 \|[ ]*$/, "| Proposed, not decided | TBD | TBD |") } { print }' "$w/$REC" > "$w/$REC.n" && mv "$w/$REC.n" "$w/$REC"
  refused "decision $id is still Proposed" "$w" "$WFSHA"
done
w="$tmp/ws_rec"; rm -rf "$w"; cp -r "$good" "$w"; sed -i '/^| D14 | /d' "$w/$REC"; refused "decision row D14 (the credential decision) is missing" "$w" "$WFSHA"
w="$tmp/ws_rec"; rm -rf "$w"; cp -r "$good" "$w"; sed -i 's/^| D14 | \(.*\)| Decided | CTO | 2026-11-21 |$/| D14 | \1| Decided | TBD | 2026-11-21 |/' "$w/$REC"; refused "decision D14 Decided but without a name (By TBD)" "$w" "$WFSHA"
fi
# G2S needs less than G2: the upload-time rows are NOT needed (and X1, X2 stay open) -- but they are not decided here either
run_authorize "$good" "$WFSHA"; [ "$GATE_AUTH" = true ] && grep -q '^| X2 | .*| Open |' "$good/$REC"; chk "G2S does not require X1, X2, D1, D2, D4 or D5 (they stay open for the upload gate G2)" $?
# a gate usage error stops the job (never "authorized")
w="$tmp/ws_rec"; rm -rf "$w"; cp -r "$good" "$w"; rm "$w/tool/ipa_inspect.py"; run_authorize "$w" "$WFSHA"; [ "$GATE_RC" -ne 0 ]; chk "authorize job: a gate that cannot run fails the job (exit $GATE_RC)" $?

# ============================================================================================================================
# 3b. The dlc_wallet hash gate: the real step, with a fixture archive and the authorized fixture record
# ============================================================================================================================
sha_of() { printf '%s' "$1" | shasum -a 256 | awk '{print $1}'; }
DLC_RC=0; DLC_DIR=""
run_dlc() { # CONTENT_OF_THE_BINARY RECORD_HASH [record sed -E expression] [VAR=value ...]
  local content="$1" rh="$2" sedx="${3:-}" d; shift 3 2>/dev/null || shift 2
  d="$(mktemp -d -p "$tmp")"; mkdir -p "$d/archive/Products/Applications/Runner.app/Frameworks/dlc_wallet.framework"
  printf '%s' "$content" > "$d/archive/Products/Applications/Runner.app/Frameworks/dlc_wallet.framework/dlc_wallet"
  cp -r "$good" "$d/tools"
  sed -E -i "s/^(G2S-DLC-WALLET-SHA256: ).*/\1$rh/" "$d/tools/$REC"
  [ -z "$sedx" ] || sed -E -i "$sedx" "$d/tools/$REC"
  ( cd "$d" && env -i PATH="$PATH" HOME="$HOME" ARCHIVE="$d/archive" EXPECTED_VERSION="$VER" RUST_LIB_SHA256="$RUSTSHA" "$@" bash -e "$STEP_dlc" > "$d/stdout" 2>&1 ); DLC_RC=$?; DLC_DIR="$d"
}
run_dlc "native-binary-v1" "$(sha_of native-binary-v1)" ""
[ "$DLC_RC" -eq 0 ] && grep -q "^dlc_wallet_archive_binary_sha256=$(sha_of native-binary-v1)$" "$DLC_DIR/evidence/dlc-wallet-hash.txt"; chk "dlc_wallet step: the authorized binary passes and both hashes are recorded" $? "rc=$DLC_RC"
run_dlc "native-binary-v2" "$(sha_of native-binary-v1)" ""
[ "$DLC_RC" -ne 0 ] && grep -q 'not the one the CTO authorized' "$DLC_DIR/stdout" && grep -q "authorized_sha256=$(sha_of native-binary-v1)" "$DLC_DIR/evidence/dlc-wallet-hash.txt"; chk "dlc_wallet step: a different binary stops the run, and the evidence shows actual and authorized hashes" $? "rc=$DLC_RC"
run_dlc "native-binary-v1" "$(sha_of native-binary-v1)" ""; ok_hash="$(sha_of native-binary-v1)"
run_dlc "native-binary-V1" "$ok_hash" ""; [ "$DLC_RC" -ne 0 ]; chk "dlc_wallet step: a one-character difference in the binary is refused" $?
run_dlc "native-binary-v1" "$DLC_OK" ""; [ "$DLC_RC" -ne 0 ]; chk "dlc_wallet step: the proposed real value does not accept some other binary" $?
run_dlc "native-binary-v1" "$ok_hash" "/^G2S-DLC-WALLET-SHA256: /d"; [ "$DLC_RC" -ne 0 ]; chk "dlc_wallet step: a record without the line stops the run (no authorized value, no signing)" $?
run_dlc "native-binary-v1" "$ok_hash" 's/^(G2S-DLC-WALLET-SHA256: .*)$/\1\n\1/'; [ "$DLC_RC" -ne 0 ]; chk "dlc_wallet step: a repeated line stops the run" $?
run_dlc "native-binary-v1" "${ok_hash^^}" ""; [ "$DLC_RC" -ne 0 ]; chk "dlc_wallet step: an upper-case hash stops the run" $?
run_dlc "native-binary-v1" "abc123" ""; [ "$DLC_RC" -ne 0 ]; chk "dlc_wallet step: a malformed hash stops the run" $?
run_dlc "native-binary-v1" "$ok_hash" 's/^(G2S-DLC-WALLET-SHA256: .*)$/```\n\1\n```/'; [ "$DLC_RC" -ne 0 ]; chk "dlc_wallet step: a hash line inside a code block is not an authorization" $?
run_dlc "native-binary-v2" "$ok_hash" "" EXPECTED_DLC_WALLET_SHA256="$(sha_of native-binary-v2)" DLC_WALLET_SHA256="$(sha_of native-binary-v2)" dlc_wallet_sha256="$(sha_of native-binary-v2)"; [ "$DLC_RC" -ne 0 ]; chk "dlc_wallet step: no environment variable or input can substitute the authorized value" $?
run_dlc "native-binary-v1" "$ok_hash" ""; rm "$DLC_DIR/archive/Products/Applications/Runner.app/Frameworks/dlc_wallet.framework/dlc_wallet"; ( cd "$DLC_DIR" && env -i PATH="$PATH" HOME="$HOME" ARCHIVE="$DLC_DIR/archive" EXPECTED_VERSION="$VER" RUST_LIB_SHA256="$RUSTSHA" bash -e "$STEP_dlc" >/dev/null 2>&1 ); [ $? -ne 0 ]; chk "dlc_wallet step: a missing binary stops the run" $?
run_dlc "native-binary-v1" "$ok_hash" ""; f="$DLC_DIR/archive/Products/Applications/Runner.app/Frameworks/dlc_wallet.framework/dlc_wallet"; mv "$f" "$f.real"; ln -s "$f.real" "$f"; ( cd "$DLC_DIR" && env -i PATH="$PATH" HOME="$HOME" ARCHIVE="$DLC_DIR/archive" EXPECTED_VERSION="$VER" RUST_LIB_SHA256="$RUSTSHA" bash -e "$STEP_dlc" >/dev/null 2>&1 ); [ $? -ne 0 ]; chk "dlc_wallet step: a symbolic link instead of the binary stops the run" $?
run_dlc "native-binary-v1" "$ok_hash" ""; grep -q 'secrets\.\|APPLE_API' "$STEP_dlc"; [ $? -ne 0 ]; chk "dlc_wallet step: it touches no secret (no secrets reference, no APPLE_API variable)" $?

# ============================================================================================================================
# 4. The credential-bearing step, run with SYNTHETIC credentials and a stub xcodebuild
# ============================================================================================================================
FAKEKEY=$'-----BEGIN PRIVATE KEY-----\nTESTONLYFAKEKEYLINE1abcdef\nTESTONLYFAKEKEYLINE2ghijkl\n-----END PRIVATE KEY-----'
FAKEJWT='eyJhbGciOiJFUzI1NiIsImtpZCI6IkZBS0UifQ.eyJpc3MiOiJGQUtFIn0.c2lnbmF0dXJlLWZha2UtMTIzNDU2'
SEC=""
run_secret() { # FAILMODE(0|1)
  SEC="$(mktemp -d -p "$tmp")"; mkdir -p "$SEC/evidence" "$SEC/tmp" "$SEC/stub"
  cat > "$SEC/stub/xcodebuild" <<'EOF'
#!/bin/bash
# STUB xcodebuild: reports what a child of the credential step can see (names and counts, never values) and plays Xcode
# at its worst: it prints the key ID, the issuer ID, a key line and a JWT-shaped token into its own output.
{
  echo "env var names with APPLE_API: $(env | cut -d= -f1 | grep -c APPLE_API)"
  echo "env values containing the key text: $(env | grep -c TESTONLYFAKEKEY)"
  echo "env values containing the key id: $(env | grep -c FAKEKEYID99)"
  echo "env values containing the issuer id: $(env | grep -c fake-issuer-0000)"
  echo "key file readable: $([ -r "$KEYFILE" ] && echo yes || echo no) mode: $(stat -c %a "$KEYFILE" 2>/dev/null)"
  echo "key file argument matches: $(case " $* " in *" -authenticationKeyPath $KEYFILE "*) echo yes ;; *) echo no ;; esac)"
  echo "argument names: $(printf '%s\n' "$@" | grep -E '^-(exportArchive|allowProvisioningUpdates|authenticationKey[A-Za-z]*)$' | tr '\n' ' ')"
} >> "$STUB_REPORT"
echo "key id FAKEKEYID99 issuer fake-issuer-0000-aaaa path $KEYFILE"
sed -n '2p' "$KEYFILE"
echo "token $STUB_JWT end; Authorization: Bearer abcdefgh12345678"
echo "-----BEGIN PRIVATE KEY-----"
[ "${STUB_FAIL:-0}" = 1 ] && exit 70
exp=""; while [ $# -gt 0 ]; do [ "$1" = "-exportPath" ] && exp="$2"; shift; done; : > "$exp/Runner.ipa"; exit 0
EOF
  printf '#!/bin/bash\nexit 0\n' > "$SEC/stub/plutil"; chmod +x "$SEC/stub/xcodebuild" "$SEC/stub/plutil"
  # Every other program the step starts is wrapped: it logs its name when the key text is in ITS environment, then runs the real one.
  ENVBIN="$(type -P env)"; GREPBIN="$(type -P grep)"   # type -P: a path, never a shell function or alias
  # (python3 is not wrapped: on some machines it is itself a launcher script that finds `python3` on PATH again and would loop; it starts only after the key text is gone.)
  for tool in chmod head rm cat mkdir tail grep find wc shasum stat awk ls env; do
    real="$(type -P "$tool" 2>/dev/null)" && [ -x "$real" ] || continue
    printf '#!/bin/bash\necho %s >> "$LEAKLOG.calls"\nif %s | %s -q TESTONLYFAKEKEY; then echo %s >> "$LEAKLOG"; fi\nexec %s "$@"\n' "$tool" "$ENVBIN" "$GREPBIN" "$tool" "$real" > "$SEC/stub/$tool"; chmod +x "$SEC/stub/$tool"
  done
  : > "$SEC/report.txt"
  ( cd "$SEC" && env -i PATH="$SEC/stub:$PATH" HOME="$HOME" RUNNER_TEMP="$SEC/tmp" GITHUB_ENV="$SEC/env" TEAM_ID="$TEAM" ARCHIVE="$SEC/tmp/a.xcarchive" \
      LEAKLOG="$SEC/leak.log" STUB_REPORT="$SEC/report.txt" STUB_FAIL="$1" STUB_JWT="$FAKEJWT" APPLE_API_KEY_P8="$FAKEKEY" APPLE_API_KEY_ID=FAKEKEYID99 APPLE_API_ISSUER_ID=fake-issuer-0000-aaaa \
      bash -e "$STEP_secret" > "$SEC/stdout" 2>&1 ); SEC_RC=$?
}
leaks() { # counts of synthetic secret material in everything the step kept or printed
  grep -rE 'FAKEKEYID99|fake-issuer-0000|TESTONLYFAKEKEY|eyJhbGciOi|abcdefgh12345678' "$SEC/stdout" "$SEC/evidence" 2>/dev/null | wc -l | tr -d ' '
}
for mode in 0 1; do
  label=$([ "$mode" = 0 ] && echo success || echo "xcodebuild failure")
  run_secret "$mode"
  if [ "$mode" = 0 ]; then [ "$SEC_RC" -eq 0 ]; else [ "$SEC_RC" -ne 0 ]; fi; chk "credential step ($label): exit status $SEC_RC is the expected one" $?
  grep -q '^env values containing the key text: 0$' "$SEC/report.txt" && ! grep -q 'env var names with APPLE_API: [1-9]' "$SEC/report.txt"; chk "credential step ($label): the child process has NO APPLE_API_* variable and no key text in its environment" $? "$(cat "$SEC/report.txt" | head -n 4 | tr '\n' '|')"
  grep -q '^env values containing the key id: 0$' "$SEC/report.txt" && grep -q '^env values containing the issuer id: 0$' "$SEC/report.txt"; chk "credential step ($label): the child's environment holds neither key ID nor issuer ID" $?
  grep -q 'key file readable: yes mode: 600' "$SEC/report.txt"; chk "credential step ($label): the key file is readable by xcodebuild and mode 600 while it runs" $?
  grep -q 'key file argument matches: yes' "$SEC/report.txt" && grep -q -- '-exportArchive' "$SEC/report.txt" && grep -q -- '-allowProvisioningUpdates' "$SEC/report.txt" && grep -q -- '-authenticationKeyID' "$SEC/report.txt"; chk "credential step ($label): xcodebuild still gets the key by path with -authenticationKey* arguments (Apple authentication preserved)" $?
  [ -z "$(find "$SEC/tmp" -maxdepth 1 -name '*.p8')" ]; chk "credential step ($label): the key file is removed afterwards" $?
  [ -f "$SEC/leak.log" ] || : > "$SEC/leak.log"; [ ! -s "$SEC/leak.log" ]; chk "credential step ($label): no program the step starts (chmod, rm, head, cat, env, ...) ever has the key text in its environment" $? "saw it: $(sort -u "$SEC/leak.log" | tr '\n' ' ')"
  grep -qx chmod "$SEC/leak.log.calls" && grep -qx rm "$SEC/leak.log.calls" && grep -qx head "$SEC/leak.log.calls"; chk "credential step ($label): the wrappers saw chmod, rm and head run (the check above is not vacuous)" $?
  [ "$(leaks)" = 0 ]; chk "credential step ($label): no key ID, issuer ID, key line, JWT or bearer token in the job log or the kept evidence" $? "$(grep -rhE 'FAKEKEYID99|fake-issuer-0000|TESTONLYFAKEKEY|eyJhbGciOi|abcdefgh12345678' "$SEC/stdout" "$SEC/evidence" 2>/dev/null | head -n 3 | cut -c1-120 | tr '\n' '|')"
  grep -q 'REDACTED' "$SEC/evidence/export.log"; chk "credential step ($label): the evidence shows where material was redacted" $?
  if [ "$mode" = 1 ]; then [ -f "$SEC/evidence/export-diagnosis.txt" ]; chk "credential step (failure): the diagnosis evidence is written" $?; fi
done
# ============================================================================================================================
# 5. The evidence seal: tokens and key markers never reach an artifact
# ============================================================================================================================
run_seal() { # CONTENT -> SEAL_RC, evidence dir left in $SEAL
  SEAL="$(mktemp -d -p "$tmp")"; mkdir -p "$SEAL/evidence"; printf '%s\n' "$1" > "$SEAL/evidence/note.txt"
  ( cd "$SEAL" && env -i PATH="$PATH" HOME="$HOME" bash -e "$STEP_seal" > "$SEAL/stdout" 2>&1 ); SEAL_RC=$?
}
run_seal "plain text evidence"; [ "$SEAL_RC" -eq 0 ] && [ -f "$SEAL/evidence/SHA256SUMS.txt" ]; chk "seal: clean text evidence is kept and checksummed" $?
run_seal "leak $FAKEJWT"; [ "$SEAL_RC" -ne 0 ] && [ ! -e "$SEAL/evidence/note.txt" ]; chk "seal: a JWT-shaped token anywhere in the evidence refuses and removes the evidence" $?
run_seal "-----BEGIN PRIVATE KEY-----"; [ "$SEAL_RC" -ne 0 ] && [ ! -e "$SEAL/evidence/note.txt" ]; chk "seal: a private-key marker refuses and removes the evidence" $?

# ============================================================================================================================
# 6. The archive validator (F4): behaviour on crafted archives, before and after extraction
# ============================================================================================================================
V="$root/tool/validate_handover_archive.py"
if [ "${HOSTED_SIGNING_QUICK:-0}" != 1 ]; then
av="$tmp/archives"; mkdir -p "$av"
python3 -I - "$av" <<'PY'
import io, os, sys, tarfile, gzip
d = sys.argv[1]
TOP = "Runner.xcarchive"
def mk(name, members, fmt=tarfile.PAX_FORMAT):
    with tarfile.open(os.path.join(d, name + ".tar"), "w", format=fmt) as t:
        for m in members:
            ti, data = m
            t.addfile(ti, io.BytesIO(data) if data is not None else None)
def reg(n, data=b"x", mode=0o644):
    ti = tarfile.TarInfo(n); ti.size = len(data); ti.mode = mode; return (ti, data)
def dir_(n):
    ti = tarfile.TarInfo(n); ti.type = tarfile.DIRTYPE; ti.mode = 0o755; return (ti, None)
def sym(n, target):
    ti = tarfile.TarInfo(n); ti.type = tarfile.SYMTYPE; ti.linkname = target; ti.mode = 0o755; return (ti, None)
def hard(n, target):
    ti = tarfile.TarInfo(n); ti.type = tarfile.LNKTYPE; ti.linkname = target; ti.mode = 0o644; return (ti, None)
def special(n, typ):
    ti = tarfile.TarInfo(n); ti.type = typ; ti.mode = 0o644; return (ti, None)
base = [dir_(TOP), dir_(TOP + "/Products"), reg(TOP + "/Info.plist"), reg(TOP + "/Products/a.bin")]
mk("good", base + [sym(TOP + "/Products/link", "a.bin"), sym(TOP + "/Products/up", "../Info.plist"), hard(TOP + "/Products/hl", TOP + "/Products/a.bin")])
mk("abs_name", base + [reg("/etc/evil")])
mk("dotdot_name", base + [reg(TOP + "/../evil")])
mk("dotdot_middle", base + [reg(TOP + "/Products/../../evil")])
mk("other_top", base + [reg("Other/x")])
mk("two_tops", base + [dir_("Second"), reg("Second/x")])
mk("sym_abs", base + [sym(TOP + "/Products/key", "/Users/runner/work/_temp/apple-api-key.p8")])
mk("sym_dotdot", base + [sym(TOP + "/Products/out", "../../outside")])
mk("sym_deep_escape", base + [sym(TOP + "/Products/a/b", "../../../../etc")])
mk("through_symlink", base + [sym(TOP + "/Products/d", "."), reg(TOP + "/Products/d/x")])
mk("through_symlink_dir", base + [sym(TOP + "/Products/inner", "."), dir_(TOP + "/Products/inner/sub")])
mk("hard_abs", base + [hard(TOP + "/hl", "/etc/passwd")])
mk("hard_dotdot", base + [hard(TOP + "/hl", TOP + "/../x")])
mk("hard_to_later", base + [hard(TOP + "/hl", TOP + "/later"), reg(TOP + "/later")])
mk("hard_to_symlink", base + [sym(TOP + "/s", "Info.plist"), hard(TOP + "/hl", TOP + "/s")])
mk("duplicate", base + [reg(TOP + "/Info.plist", b"second")])
mk("fifo", base + [special(TOP + "/pipe", tarfile.FIFOTYPE)])
mk("chardev", base + [special(TOP + "/dev", tarfile.CHRTYPE)])
mk("setuid", base + [reg(TOP + "/su", mode=0o4755)])
mk("sticky_dir", base + [(lambda t: (t.__setattr__("mode", 0o1777) or (t, None)))(dir_(TOP + "/tmpdir")[0])])
mk("control_char", base + [reg(TOP + "/bad\nname")])
mk("backslash", base + [reg(TOP + "/bad\\name")])
mk("empty_component", base + [reg(TOP + "//x")])
mk("dot_component", base + [reg(TOP + "/./x")])
open(os.path.join(d, "empty.tar"), "wb").write(b"\0" * 10240)
open(os.path.join(d, "garbage.tar"), "wb").write(b"this is not a tar file" * 100)
with open(os.path.join(d, "good.tar"), "rb") as f, gzip.open(os.path.join(d, "gz.tar"), "wb") as g:
    g.write(f.read())
PY
vl() { python3 -I "$V" list "$av/$1.tar" "${@:2}" >"$tmp/v.out" 2>&1; }
vl good; chk "validator: a legitimate archive (safe relative links, a hard link to an earlier file) passes" $? "$(head -n 3 "$tmp/v.out")"
mkdir -p "$tmp/x_good"; tar -xf "$av/good.tar" -C "$tmp/x_good" && python3 -I "$V" tree "$tmp/x_good/Runner.xcarchive" >"$tmp/v.out" 2>&1; chk "validator: its extracted tree passes the post-extraction check" $? "$(head -n 3 "$tmp/v.out")"
for n in abs_name dotdot_name dotdot_middle other_top two_tops sym_abs sym_dotdot sym_deep_escape through_symlink through_symlink_dir hard_abs hard_dotdot hard_to_later hard_to_symlink duplicate fifo chardev setuid sticky_dir control_char backslash empty_component dot_component empty garbage gz; do
  vl "$n"; [ $? -eq 1 ] && grep -q REFUSED "$tmp/v.out"; chk "validator (before extraction): $n is refused" $? "$(head -n 2 "$tmp/v.out")"
done
vl good --max-members 2; [ $? -eq 1 ]; chk "validator: the member limit is enforced" $?
vl good --max-bytes 1; [ $? -eq 1 ]; chk "validator: the size limit is enforced" $?
python3 -I "$V" list "$av/missing.tar" >/dev/null 2>&1; [ $? -eq 1 ]; chk "validator: a missing file is a refusal, never a pass" $?
# after extraction: what GNU/BSD tar would really create
mkdir -p "$tmp/xt"
for n in sym_abs sym_dotdot sym_deep_escape fifo setuid; do
  rm -rf "$tmp/xt/$n"; mkdir -p "$tmp/xt/$n"; tar -xpf "$av/$n.tar" -C "$tmp/xt/$n" 2>/dev/null
  python3 -I "$V" tree "$tmp/xt/$n/Runner.xcarchive" >"$tmp/v.out" 2>&1; [ $? -eq 1 ]; chk "validator (after extraction): $n tree is refused" $? "$(head -n 2 "$tmp/v.out")"
done
mkdir -p "$tmp/xt/chain/Runner.xcarchive"; ln -s ../one "$tmp/xt/chain/Runner.xcarchive/two"; ln -s ../outside "$tmp/xt/chain/one"; ln -s /etc "$tmp/xt/chain/outside"
python3 -I "$V" tree "$tmp/xt/chain/Runner.xcarchive" >"$tmp/v.out" 2>&1; [ $? -eq 1 ]; chk "validator (after extraction): a link chain that resolves outside is refused" $?
before="$(find "$av" -type f | sort | xargs shasum | shasum)"; python3 -I "$V" list "$av/good.tar" >/dev/null; after="$(find "$av" -type f | sort | xargs shasum | shasum)"; [ "$before" = "$after" ]; chk "validator: reads only (extracts and writes nothing)" $?

# --- the reviewer's exact attacks, case-insensitive and Unicode aliases, link chains in the FINAL state ---
python3 -I - "$av" <<'PYX'
import io, os, sys, tarfile
d = sys.argv[1]
T = "Runner.xcarchive"
def mk(name, members, fmt=tarfile.PAX_FORMAT):
    with tarfile.open(os.path.join(d, name + ".tar"), "w", format=fmt) as t:
        for ti, data in members:
            t.addfile(ti, io.BytesIO(data) if data is not None else None)
def reg(n, data=b"x", mode=0o644):
    ti = tarfile.TarInfo(n); ti.size = len(data); ti.mode = mode; return (ti, data)
def dir_(n):
    ti = tarfile.TarInfo(n); ti.type = tarfile.DIRTYPE; ti.mode = 0o755; return (ti, None)
def sym(n, target):
    ti = tarfile.TarInfo(n); ti.type = tarfile.SYMTYPE; ti.linkname = target; ti.mode = 0o755; return (ti, None)
def hard(n, target):
    ti = tarfile.TarInfo(n); ti.type = tarfile.LNKTYPE; ti.linkname = target; ti.mode = 0o644; return (ti, None)
base = [dir_(T), dir_(T + "/Products"), dir_(T + "/Products/Frameworks"), reg(T + "/Info.plist"), reg(T + "/Products/Frameworks/x")]
# 1. the reviewer's chain: each link looks contained, but E is physically the PARENT of the archive and G two levels up
mk("rv_chain", base + [sym(T + "/d", "."), sym(T + "/E", "d/.."), sym(T + "/G", "E/..")])
# 2. the same, with a member that differs from the link E only by case (one directory on macOS' default APFS)
mk("rv_chain_case_payload", base + [sym(T + "/d", "."), sym(T + "/E", "d/.."), reg(T + "/e/payload")])
# 3. other aliases and orders
mk("case_alias_through_link", base + [sym(T + "/Products/A", "Frameworks"), reg(T + "/Products/a/evil")])
mk("case_alias_dir_link", base + [sym(T + "/Products/Frameworks2", "Frameworks"), reg(T + "/Products/frameworks2/evil")])
mk("case_dup_file", base + [reg(T + "/info.plist", b"second")])
mk("case_dup_dir_vs_file", base + [reg(T + "/PRODUCTS", b"second")])
mk("unicode_dup", base + [reg(T + "/Café"), reg(T + "/Café")])
mk("unicode_alias_through_link", base + [sym(T + "/Café", "Products"), reg(T + "/Café/evil")])
mk("forward_ref_escape", base + [sym(T + "/a", "b/.."), sym(T + "/b", ".")])        # `a` looked harmless when it was read
mk("link_loop", base + [sym(T + "/a", "b"), sym(T + "/b", "a")])
mk("link_self", base + [sym(T + "/a", "a")])
mk("link_to_parent_of_top", base + [sym(T + "/up", "..")])
mk("link_dotdot_via_dir", base + [sym(T + "/Products/up", "../../x")])
def cont(n):
    ti = tarfile.TarInfo(n); ti.type = tarfile.CONTTYPE; ti.size = 1; ti.mode = 0o644; return (ti, b"x")
mk("contiguous_member", base + [cont(T + "/c")])
# 4. a hard link whose target is only an alias of a link
mk("hard_to_link_alias", base + [sym(T + "/Products/L", "Frameworks"), hard(T + "/hl", T + "/products/l/x")])
# 5. legitimate archives: the structure the diagnostics of run 44625655320 recorded (names from its tree and Mach-O list)
fws = ["App", "dlc_wallet", "FingerprintPro", "Flutter", "flutter_idensic_mobile_sdk_plugin", "flutter_local_notifications", "flutter_secure_storage",
       "fluttertoast", "IdensicMobileSDK_Fisherman", "IdensicMobileSDK", "mobile_scanner", "path_provider_foundation", "shared_preferences_foundation", "workmanager_apple"]
def genuine(links=False):
    m = [dir_(T), reg(T + "/Info.plist", b"<plist/>"), dir_(T + "/Products"), dir_(T + "/Products/Applications"), dir_(T + "/Products/Applications/Runner.app")]
    app = T + "/Products/Applications/Runner.app"
    m += [reg(app + "/Runner", b"\xcf\xfa\xed\xfe", 0o755), reg(app + "/Info.plist", b"<plist/>"), reg(app + "/PkgInfo", b"APPL????"), dir_(app + "/Frameworks"), dir_(app + "/flutter_assets"), reg(app + "/flutter_assets/AssetManifest.json", b"{}")]
    for f in fws:
        m += [dir_(app + "/Frameworks/%s.framework" % f), reg(app + "/Frameworks/%s.framework/%s" % (f, f), b"\xcf\xfa\xed\xfe", 0o755), reg(app + "/Frameworks/%s.framework/Info.plist" % f, b"<plist/>")]
        m += [dir_(T + "/dSYMs/%s.framework.dSYM/Contents" % f), reg(T + "/dSYMs/%s.framework.dSYM/Contents/Info.plist" % f)]
    m += [dir_(app + "/Frameworks/flutter_local_notifications.framework/flutter_local_notifications_privacy.bundle"), reg(app + "/Frameworks/flutter_local_notifications.framework/flutter_local_notifications_privacy.bundle/PrivacyInfo.xcprivacy", b"<plist/>")]
    m += [dir_(T + "/SwiftSupport"), dir_(T + "/SwiftSupport/iphoneos"), reg(T + "/SwiftSupport/iphoneos/libswift_Concurrency.dylib", b"\xcf\xfa\xed\xfe", 0o755)]
    if links:   # contained links of the kind a macOS-style bundle has: they must stay acceptable
        fw = app + "/Frameworks/Flutter.framework"
        m += [dir_(fw + "/Versions"), dir_(fw + "/Versions/A"), reg(fw + "/Versions/A/Flutter", b"\xcf\xfa\xed\xfe", 0o755), sym(fw + "/Versions/Current", "A"), sym(fw + "/Resources", "Versions/Current/Resources"), sym(fw + "/Flutter2", "Versions/Current/Flutter")]
    return m
mk("genuine_pax", genuine(), tarfile.PAX_FORMAT)
mk("genuine_gnu", genuine(), tarfile.GNU_FORMAT)
mk("genuine_ustar_links", [x for x in genuine(True) if len(x[0].name) < 100], tarfile.USTAR_FORMAT)
mk("genuine_pax_links", genuine(True), tarfile.PAX_FORMAT)
PYX
for n in rv_chain rv_chain_case_payload case_alias_through_link case_alias_dir_link case_dup_file case_dup_dir_vs_file unicode_dup unicode_alias_through_link forward_ref_escape link_loop link_self link_to_parent_of_top link_dotdot_via_dir hard_to_link_alias contiguous_member; do
  vl "$n"; [ $? -eq 1 ] && grep -q REFUSED "$tmp/v.out"; chk "validator (before extraction): $n is refused" $? "$(head -n 2 "$tmp/v.out")"
done
vl rv_chain; grep -q "leaves the top-level directory" "$tmp/v.out"; chk "validator: the reviewer's symlink chain is refused for the right reason (E and G leave the archive physically)" $? "$(head -n 3 "$tmp/v.out")"
vl rv_chain_case_payload; grep -q "runs through the symbolic link" "$tmp/v.out"; chk "validator: a member that differs from a link only by case is recognized as running through it" $? "$(head -n 3 "$tmp/v.out")"
vl unicode_dup; grep -q "Unicode normalization" "$tmp/v.out"; chk "validator: NFC and NFD spellings of one name are one name" $? "$(head -n 3 "$tmp/v.out")"
for n in genuine_pax genuine_gnu genuine_ustar_links genuine_pax_links; do
  vl "$n"; chk "validator: a genuine iOS archive (structure of run 44625655320) stays acceptable: $n" $? "$(head -n 3 "$tmp/v.out")"
  rm -rf "$tmp/xg"; mkdir -p "$tmp/xg"; tar -xf "$av/$n.tar" -C "$tmp/xg" && python3 -I "$V" tree "$tmp/xg/Runner.xcarchive" >"$tmp/v.out" 2>&1; chk "validator: and its extracted tree passes: $n" $? "$(head -n 3 "$tmp/v.out")"
done
vl genuine_pax_links; grep -q '3 symbolic links' "$tmp/v.out"; chk "validator: contained symbolic links (Versions/Current style, a chain through Current) are accepted and counted" $?
# the reviewer's chain as the filesystem makes it: the post-extraction check refuses it as well
rm -rf "$tmp/xr"; mkdir -p "$tmp/xr"; tar -xf "$av/rv_chain.tar" -C "$tmp/xr" 2>/dev/null; python3 -I "$V" tree "$tmp/xr/Runner.xcarchive" >"$tmp/v.out" 2>&1; [ $? -eq 1 ]; chk "validator (after extraction): the reviewer's chain is refused by the real filesystem's resolution too" $?

fi

# ============================================================================================================================
# 7. Mutations: the dangerous edits of the independent audit (F5) and more, applied to a COPY of the workflow
# ============================================================================================================================
echo
echo "test_ios_hosted_signing_behavior (without mutations): $pass passed, $failed failed"
if [ "${HOSTED_SIGNING_NO_MUTATIONS:-0}" = 1 ]; then [ "$failed" -eq 0 ]; exit $?; fi
mut="$tmp/mut"; mkdir -p "$mut"
python3 -I - "$wf" "$mut" <<'PY'
import sys, os, json
src = open(sys.argv[1]).read()
out = sys.argv[2]
CHK = "        uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4\n"
M = []
def m(mid, desc, old, new, which=0):
    M.append((mid, desc, old, new, which))
m("A_authorize_forced_true", "authorization forcibly set to true", 'if [ "$rc" -eq 0 ]; then authorized=true', 'authorized=true; if [ "$rc" -eq 0 ]; then :')
m("B_recheck_bypassed", "signing authorization re-check bypassed", '|| { echo "::error::Signing is not authorized by the release record. Stopping before any secret is used."; exit 1; }', '|| true')
m("B2_recheck_gate_not_run", "re-check never runs the gate", '          bash tools/tool/check_signing_authorization.sh --record "$record" --approved-sha', '          true tools/tool/check_signing_authorization.sh --record "$record" --approved-sha')
m("C_third_party_action", "a pinned third-party action before the secret step", '      - name: Select Xcode 26.3\n        run: |\n          sudo xcode-select -s "$XCODE_APP/Contents/Developer"\n          actual="$(xcodebuild -version | sed -n \'1s/^Xcode //p\')"\n          echo "xcode=$actual', '      - name: harmless\n        uses: evil/action@0123456789abcdef0123456789abcdef01234567\n      - name: Select Xcode 26.3\n        run: |\n          sudo xcode-select -s "$XCODE_APP/Contents/Developer"\n          actual="$(xcodebuild -version | sed -n \'1s/^Xcode //p\')"\n          echo "xcode=$actual')
m("D_approved_script_executed", "the signing job executes a script of the approved commit", 'cp tools/tool/verify_artifact.sh "$RUNNER_TEMP/verifier-repo/tool/verify_artifact.sh"', 'cp approved/tool/verify_artifact.sh "$RUNNER_TEMP/verifier-repo/tool/verify_artifact.sh"; bash approved/tool/verify_artifact.sh matrix')
m("D2_archive_script_executed", "the signing job executes a script from the extracted archive", '          ARCHIVE="$RUNNER_TEMP/archive/Runner.xcarchive"\n', '          ARCHIVE="$RUNNER_TEMP/archive/Runner.xcarchive"\n          bash "$ARCHIVE/run.sh"\n')
m("E_key_text_in_environment", "the key text stays in the environment of xcodebuild", '          unset APPLE_API_KEY_P8\n', '          :\n')
m("E2_env_not_stripped", "secrets are not removed from xcodebuild's environment", '          env -u APPLE_API_KEY_P8 -u APPLE_API_KEY_ID -u APPLE_API_ISSUER_ID \\\n            xcodebuild', '          xcodebuild')
m("F_raw_log_printed", "the raw xcodebuild log is printed", '          echo "---- xcodebuild -exportArchive (redacted), last 60 lines ----"', '          tail -n 5 "$RUNNER_TEMP/export.raw.log"\n          echo "---- xcodebuild -exportArchive (redacted), last 60 lines ----"')
m("G_jwt_not_redacted", "JWT-shaped tokens are not redacted", 'data = re.sub(r"eyJ[A-Za-z0-9_-]{4,}\\.[A-Za-z0-9_-]{4,}(\\.[A-Za-z0-9_-]*)?", "[REDACTED]", data)', 'pass')
m("G2_bearer_not_redacted", "bearer tokens are not redacted", 'data = re.sub(r"(?i)(bearer|authorization:?)\\s+[A-Za-z0-9._~+/=-]{8,}", r"\\1 [REDACTED]", data)', 'pass')
m("G3_seal_ignores_jwt", "the seal step ignores JWT-shaped tokens", "PRIVATE KEY|BEGIN PKCS7|eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}", "PRIVATE KEY|BEGIN PKCS7")
m("E3_chmod_before_unset", "chmod runs while the key text is still in the environment", '          unset APPLE_API_KEY_P8\n          chmod 600 "$KEYFILE"\n', '          chmod 600 "$KEYFILE"\n          unset APPLE_API_KEY_P8\n')
m("H_key_file_open_mode", "the key file is not mode 600", '          chmod 600 "$KEYFILE"\n', '          chmod 644 "$KEYFILE"\n')
m("H2_no_umask", "no umask before the key file", '          umask 077\n          unset BASH_ENV', '          unset BASH_ENV')
m("I2_no_trap", "no trap and no cleanup", "          trap cleanup EXIT\n", "")
m("J_secret_in_build", "a secret in the build job", '      - name: Resolve dependencies exactly as the lockfiles say\n        run: |', '      - name: Resolve dependencies exactly as the lockfiles say\n        env:\n          X: ${{ secrets.APPLE_API_KEY_ID }}\n        run: |')
m("K_validation_line_based", "line-based input validation again (sign job)", 'isexact "$APPROVED_SHA" "$re_sha" || { echo "::error::approved_sha must be 40 lower-case hex characters."; fail=1; }\n          isexact "$EXPECTED_VERSION"', 'printf \'%s\' "$APPROVED_SHA" | grep -Eq \'^[0-9a-f]{40}$\' || { echo "::error::approved_sha must be 40 lower-case hex characters."; fail=1; }\n          isexact "$EXPECTED_VERSION"')
m("L_stale_tip_authorize", "the stale-run check compares the revision with itself (authorize job)", '--workflow-sha "$GITHUB_SHA" --development-tip "$tip" > "$RUNNER_TEMP/gate.txt"', '--workflow-sha "$GITHUB_SHA" --development-tip "$GITHUB_SHA" > "$RUNNER_TEMP/gate.txt"')
m("L2_stale_tip_recheck", "the stale-run check compares the revision with itself (signing job)", '--tools-root tools --workflow-sha "$GITHUB_SHA" --development-tip "$tip"', '--tools-root tools --workflow-sha "$GITHUB_SHA" --development-tip "$GITHUB_SHA"')
m("M_extract_before_validate", "the archive is extracted without the member-list check", 'python3 -I tools/tool/validate_handover_archive.py list handover/Runner.xcarchive.tar --top Runner.xcarchive | tee evidence/archive-validate-list.txt\n          [ "${PIPESTATUS[0]}" -eq 0 ] ||', 'true | tee evidence/archive-validate-list.txt\n          [ "${PIPESTATUS[0]}" -eq 0 ] ||')
m("M2_no_tree_check", "no check of the extracted tree", 'python3 -I tools/tool/validate_handover_archive.py tree "$RUNNER_TEMP/archive" | tee', 'true | tee')
m("N_download_other_run", "the hand-over is taken from another run", '          name: ios-hosted-unsigned-archive_${{ github.run_id }}-${{ github.run_attempt }}\n          path: handover', '          name: ios-hosted-unsigned-archive_${{ github.run_id }}-${{ github.run_attempt }}\n          run-id: 1\n          github-token: ${{ github.token }}\n          path: handover')
m("U_dlc_hash_ignored", "the dlc_wallet hash comparison never fails", 'if [ "$actual" != "$authorized" ]; then', 'if false; then')
m("U2_dlc_actual_from_record", "the dlc_wallet hash is read from the record on both sides", 'actual="$(shasum -a 256 "$fw" | awk \'{print $1}\')"', 'actual="$authorized"')
m("U4_dlc_env_override", "an environment variable may substitute the authorized hash", 'authorized="$(bash tools/tool/check_signing_authorization.sh --print-field G2S-DLC-WALLET-SHA256 --record "$record" --tools-root tools)"; rc=$?', 'authorized="${DLC_WALLET_SHA256:-$(bash tools/tool/check_signing_authorization.sh --print-field G2S-DLC-WALLET-SHA256 --record "$record" --tools-root tools)}"; rc=$?')
m("U5_dlc_step_exits_early", "the dlc_wallet step exits successfully before comparing", '          fw="$ARCHIVE/Products/Applications/Runner.app/Frameworks/dlc_wallet.framework/dlc_wallet"\n', '          fw="$ARCHIVE/Products/Applications/Runner.app/Frameworks/dlc_wallet.framework/dlc_wallet"\n          exit 0\n')
m("O_upload_added", "an upload step in the signing job", '      - name: Fix the IPA digest again (integrity of the file that was verified)', '      - name: upload\n        run: xcrun altool --upload-app -f "$IPA" --apiKey x\n      - name: Fix the IPA digest again (integrity of the file that was verified)')
m("O2_destination_upload", "the export destination is upload", '<key>destination</key><string>export</string>', '<key>destination</key><string>upload</string>')
m("P_build_number_managed", "Xcode may manage the build number", '<key>manageAppVersionAndBuildNumber</key><false/>', '<key>manageAppVersionAndBuildNumber</key><true/>')
m("Q_ref_not_checked", "the signing job no longer insists on development", '[ "$GITHUB_REF" = "refs/heads/development" ] || { echo "::error::Hosted signing runs only from refs/heads/development."; fail=1; }', ':')
m("R_secret_wholesale", "the whole secret context is passed", 'APPLE_API_ISSUER_ID: ${{ secrets.APPLE_API_ISSUER_ID }}', 'APPLE_API_ISSUER_ID: ${{ secrets.APPLE_API_ISSUER_ID }}\n          ALL: ${{ toJSON(secrets) }}')
m("S_verifier_repo_is_approved", "the verifier is pointed at the approved checkout again", '--repo "$VERIFIER_REPO"', '--repo approved')
m("T_environment_dropped", "the protected environment is dropped", '    environment: ios-hosted-signing\n', '')
res = []
for mid, desc, old, new, which in M:
    cnt = src.count(old)
    if cnt == 0:
        res.append((mid, desc, None)); continue
    idx = -1
    for _ in range(which + 1):
        idx = src.index(old, idx + 1)
    mutated = src[:idx] + new + src[idx + len(old):]
    open(os.path.join(out, mid + ".yml"), "w").write(mutated)
    res.append((mid, desc, True))
json.dump(res, open(os.path.join(out, "list.json"), "w"))
PY
caught=0; missed=0
run_mutation() { # ID -> writes $mut/ID.result
  local mid="$1" r1 r2
  HOSTED_SIGNING_WORKFLOW="$mut/$mid.yml" HOSTED_SIGNING_NO_MUTATIONS=1 HOSTED_SIGNING_QUICK=1 bash "$self" >"$mut/$mid.out" 2>&1; r1=$?
  HOSTED_SIGNING_WORKFLOW="$mut/$mid.yml" bash "$root/tool/test_ios_hosted_signing.sh" >"$mut/$mid.static.out" 2>&1; r2=$?
  echo "$r1 $r2" > "$mut/$mid.result"
}
jobs_n=0
while IFS=$'\t' read -r mid desc status; do
  [ "$status" = "true" ] || continue
  run_mutation "$mid" &
  jobs_n=$((jobs_n + 1)); [ $((jobs_n % 4)) -eq 0 ] && wait
done < <(python3 -I -c "
import json
for mid,desc,st in json.load(open('$mut/list.json')): print('%s\t%s\t%s' % (mid, desc, 'true' if st else 'false'))")
wait
while IFS=$'\t' read -r mid desc status; do
  if [ "$status" != "true" ]; then bad "mutation $mid could not be applied (the workflow no longer contains the text it mutates): $desc"; continue; fi
  read -r r1 r2 < "$mut/$mid.result"
  if [ "$r1" -ne 0 ] || [ "$r2" -ne 0 ]; then caught=$((caught + 1)); ok "mutation $mid is caught ($desc) [behaviour=$r1 static=$r2]"; else missed=$((missed + 1)); bad "mutation $mid ESCAPED every test: $desc"; fi
done < <(python3 -I -c "
import json
for mid,desc,st in json.load(open('$mut/list.json')): print('%s\t%s\t%s' % (mid, desc, 'true' if st else 'false'))")
echo
echo "test_ios_hosted_signing_behavior: $pass passed, $failed failed ($caught mutations caught, $missed escaped)"
[ "$failed" -eq 0 ]
