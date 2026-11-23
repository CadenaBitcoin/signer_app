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
            "sign|Export and sign|secret" "sign|Seal the evidence|seal" "sign|Check the archive digest|archive" "sign|Enforce the authorized dlc_wallet|dlc" "sign|Report (job summary)|report" "sign|Native library identity|v9" "sign|Capture the Info.plist|capture"; do
  IFS='|' read -r j n v <<<"$pair"
  f="$(sf "$j" "$n")" && eval "STEP_$v=\"$f\"" || { bad "the workflow has exactly one step '$n' in job $j"; eval "STEP_$v=/nonexistent"; }
done

for pair in "sign|Probe Apple|uprobe" "sign|Re-check the upload authorization|upre" "sign|Validate and upload the verified IPA|uup" "sign|Check again that no key file remains|ukey"; do
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
chk("exactly two steps of the signing job read secrets: the export and the upload", len(sec_i) == 2, str(sec_i))
secret_step = next((s for s in sign if s["i"] in sec_i), None)
upload_step = next((s for s in sign if s["i"] in sec_i and s["name"].startswith("Validate and upload the verified IPA")), None)
if secret_step:
    chk("the first of them is the export step, with exactly the three secrets and nothing else", sorted(secret_step["env"]) == ["APPLE_API_ISSUER_ID", "APPLE_API_KEY_ID", "APPLE_API_KEY_P8"] and secret_step["name"].startswith("Export and sign with the cloud-managed Distribution certificate"), str(sorted(secret_step["env"])))
chk("the second is the upload step, with exactly the three secrets and nothing else", upload_step is not None and sorted(upload_step["env"]) == ["APPLE_API_ISSUER_ID", "APPLE_API_KEY_ID", "APPLE_API_KEY_P8"] and sec_i and upload_step["i"] == sec_i[-1] and upload_step["i"] != sec_i[0])
others = [s for s in idx if (s["job"], s["i"]) not in {("sign", i) for i in sec_i} and ("secrets." in json.dumps({"e": s["env"], "w": s["with"], "r": s["run"], "i": s["if"]}))]
chk("no job or workflow level environment, secret or variable", not any(jobs[j].get("env") for j in jobs) and "secrets." not in json.dumps(data["top_env"]) and all("secrets." not in json.dumps(jobs[j]) for j in jobs))
chk("only the signing job has an environment, and it is ios-hosted-signing", [j for j in jobs if jobs[j].get("environment")] == ["sign"] and jobs["sign"]["environment"] == "ios-hosted-signing")
chk("the trigger is workflow_dispatch only", list((data["on"] or {}).keys()) == ["workflow_dispatch"])

ar_i = next((s["i"] for s in sign if s["name"].startswith("Check the archive digest")), None)
pre = [s for s in sign if sec_i and s["i"] < sec_i[0]]
post = [s for s in sign if sec_i and s["i"] > sec_i[0]]
UPLOAD_STEPS = ("Probe Apple", "Re-check the upload authorization", "Validate and upload the verified IPA")
# no code of the approved commit, of the archive or of the hand-over is executed anywhere in the signing job
INTERP = re.compile(r"(?:^|[;&|(`]|\$\()\s*(?:sudo\s+)?(bash|/bin/bash|sh|/bin/sh|zsh|source|\.|python3?|perl|ruby|node|osascript|swift|make|xcrun|env)\s+((?:-\S+\s+)*)(\S+)", re.M)
OK_TARGET = re.compile(r'^"?(tools/tool/[A-Za-z_]+\.(py|sh)|\$RUNNER_TEMP/(redact|findlog)\.py|\$\{RUNNER_TEMP\}/(redact|findlog)\.py|-u|-)"?$')   # redact.py and findlog.py are written by the secret step itself (heredocs), never read from a checkout
bad_exec = []
for s in sign:
    txt = "\n".join(l for l in (s["run"] or "").splitlines() if not l.strip().startswith("#"))
    for m in INTERP.finditer(txt):
        interp, opts, target = m.group(1), m.group(2), m.group(3)
        if interp in ("env",):
            continue   # `env -u NAME command` is checked through its command below
        if interp == "xcrun":
            if s["name"].startswith("Probe Apple") and target == "altool":   # the one probe of Apple's upload tool, before any secret exists
                continue
            bad_exec.append((s["name"], m.group(0).strip())); continue
        if not OK_TARGET.match(target):
            bad_exec.append((s["name"], m.group(0).strip()))
    stripped = txt.replace("approved/pubspec.yaml", "").replace("git -C approved", "")
    if re.search(r"""(^|[\s"'=:/])(\./)?approved/|cd\s+approved""", stripped):
        bad_exec.append((s["name"], "uses a path of the approved checkout beyond its pubspec.yaml / git rev-parse"))
chk("the signing job executes no script of the approved commit, of the archive or of the hand-over (interpreter targets are tools/tool/*, redact.py, findlog.py)", not bad_exec, str(bad_exec))
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
# ---- the upload is gated, and a failed verification (or any failed step) means no upload ------------------------------------------------
# GitHub gives a step whose `if` has no status function the condition `success() && (expression)`: it runs only if every earlier step of the job
# succeeded. That rule is SIMULATED here on the real steps and conditions of the signing job: whichever step fails, the upload steps do not run;
# when the dispatch is not authorized for upload they never run; when everything succeeds and it is authorized, exactly they do.
chk("the authorize job exposes upload_authorized from its gate step", jobs["authorize"].get("outputs", {}).get("upload_authorized") == "${{ steps.gate.outputs.upload_authorized }}")
chk("the signing job itself runs only when the dispatch is authorized to sign", jobs["sign"].get("if") == "needs.authorize.outputs.authorized == 'true'")
UP_PREFIX = ("Probe Apple", "Re-check the upload authorization", "Validate and upload the verified IPA")
def step_runs(st, failed, upload_ok):
    expr = (st["if"] or "").strip() if st["if"] is not None else ""
    if not expr:
        return not failed
    if "always()" in expr:
        return True
    if "failure()" in expr:
        return failed
    if expr == "needs.authorize.outputs.upload_authorized == 'true'":
        return (not failed) and upload_ok
    raise ValueError("a condition this simulation does not know: %r" % expr)
def simulate(fail_name, upload_ok):
    failed, ran = False, []
    for st in sign:
        if step_runs(st, failed, upload_ok):
            ran.append(st["name"])
            if st["name"] == fail_name:
                failed = True
    return ran
try:
    all_ok = simulate(None, True)
    ups_ran = [n for n in all_ok if n.startswith(UP_PREFIX)]
    chk("simulation: when every step succeeds and the upload is authorized, the probe, the pre-check and the upload all run", len(ups_ran) == 3, str(ups_ran))
    not_authorized = simulate(None, False)
    chk("simulation: when the dispatch is NOT authorized for upload (the record names the signing-only operation, or nothing), none of the three runs, whatever else happens", not [n for n in not_authorized if n.startswith(UP_PREFIX)])
    chk("simulation: ...and the verification and the evidence steps still run in that case (an unauthorized upload changes nothing else)", len(not_authorized) == len(all_ok) - 3)
    leaks_ = []
    for st in sign:
        if st["name"] in all_ok and not st["name"].startswith(UP_PREFIX[0]):
            ran = simulate(st["name"], True)
            late = [n for n in ran if n.startswith(UP_PREFIX[1:])]
            # a step that fails AFTER the probe and BEFORE the pre-check/upload must stop both; a step that comes after the upload cannot matter
            pos = [s["name"] for s in sign].index(st["name"]); pos_pre = [s["name"] for s in sign].index(next(n for n in all_ok if n.startswith(UP_PREFIX[1])))
            if pos < pos_pre and late:
                leaks_.append(st["name"])
    chk("simulation: a failure of ANY earlier step of the signing job (the export, V1 to V9, the digest check, the archive and hash checks, the key-file check) stops the pre-check and the upload", not leaks_, str(leaks_))
    verif = [n for n in all_ok if re.match(r"(Unpack the exported IPA|Signature seals|Embedded profile|Environment inside|Repository IPA verifier|Native library identity|Fix the IPA digest)", n)]
    chk("simulation: the seven steps that carry V1 to V9 and the digest check are all among the steps whose failure was simulated", len(verif) == 7, str(verif))
    evid = simulate("Repository IPA verifier, pinned on the certificate, and \"signatures only\" comparison (V7, V8)", True)
    chk("simulation: after a failed V7/V8 the evidence steps still run (capture, seal, report, upload of the text evidence) and no upload step does", any(n.startswith("Capture the Info.plist") for n in evid) and any(n.startswith("Upload the text evidence") for n in evid) and not [n for n in evid if n.startswith(UP_PREFIX[1:])], str(evid[-6:]))
except ValueError as e:
    chk("simulation: every condition of the signing job is one the simulation understands", False, str(e))
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
GATE_RC=0; GATE_AUTH=""; GATE_UP=""
run_authorize() { # WS TIP [VAR=value ...]   (the authorize job's gate step, in WS as the workspace)
  local ws="$1" tip="$2" t; shift 2; t="$(mktemp -d -p "$tmp")"; : > "$t/out"; : > "$t/sum"
  ( cd "$ws" && env -i PATH="$stubdir:$PATH" HOME="$HOME" REAL_GIT="$REAL_GIT" STUB_TIP="$tip" GITHUB_REF=refs/heads/development GITHUB_EVENT_NAME=workflow_dispatch \
      GITHUB_SHA="$WFSHA" GITHUB_SERVER_URL=https://example.invalid GITHUB_REPOSITORY=example/repo RUNNER_TEMP="$t" GITHUB_STEP_SUMMARY="$t/sum" GITHUB_OUTPUT="$t/out" \
      APPROVED_SHA="$SHA" EXPECTED_VERSION="$VER" BUNDLE_ID="$BID" TEAM_ID="$TEAM" "$@" bash -e "$STEP_gate" > "$t/stdout" 2>&1 ); GATE_RC=$?
  GATE_AUTH="$(sed -n 's/^authorized=//p' "$t/out")"; GATE_UP="$(sed -n 's/^upload_authorized=//p' "$t/out")"
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
# ---- 3a. The UPLOAD authorization as wired: upload_authorized is true ONLY for the operation sign-verify-and-upload, on top of a passing gate
up="$tmp/ws_up"; mkws "$up"; authorize_ws "$up"
sed -i -E 's/`G1 AUTHORIZED`/`G2 AUTHORIZED`/; s/^G2S-OPERATION: .*/G2S-OPERATION: sign-verify-and-upload/' "$up/$REC"; decide_rows "$up/$REC" D1 D2 D4 D5
upcase() { # NAME WS TIP WANT_AUTH WANT_UP [VAR=value ...]
  local name="$1" ws="$2" tip="$3" wa="$4" wu="$5"; shift 5
  run_authorize "$ws" "$tip" "$@"; [ "$GATE_RC" -eq 0 ] && [ "$GATE_AUTH" = "$wa" ] && [ "$GATE_UP" = "$wu" ]; chk "authorize job: $name -> authorized=$wa, upload_authorized=$wu" $? "rc=$GATE_RC auth='$GATE_AUTH' up='$GATE_UP'"
}
upcase "a complete upload authorization (operation sign-verify-and-upload, G2, D1 D2 D4 D5, everything G2S needs)" "$up" "$WFSHA" true true
upcase "a complete SIGN-ONLY authorization (sign-and-verify-only): it can sign and can never upload" "$good" "$WFSHA" true false
upcase "the record before any authorization" "$base" "$WFSHA" false false
upcase "an upload authorization read from a historical revision (the tip moved on)" "$up" "$OLDSHA" false false
upcase "an upload authorization when the tip cannot be read" "$up" "" false false
upcase "an upload authorization dispatched from a branch other than development" "$up" "$WFSHA" false false GITHUB_REF=refs/heads/issue/x
upcase "an upload authorization started by an event other than workflow_dispatch" "$up" "$WFSHA" false false GITHUB_EVENT_NAME=push
for spec in 'a record status of G1 (an upload needs G2)|s/`G2 AUTHORIZED`/`G1 AUTHORIZED`/' 'a withdrawn authorization|s/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: WITHDRAWN/' 'an operation with a trailing space|s/^G2S-OPERATION: .*/G2S-OPERATION: sign-verify-and-upload /' 'an operation that merely contains upload|s/^G2S-OPERATION: .*/G2S-OPERATION: sign-and-upload/' 'another approved SHA|s/^G2S-APPROVED-SHA: .*/G2S-APPROVED-SHA: '"$OLDSHA"'/' 'a stale tool blob|s/(tool\/verify_ipa\.py=)[0-9a-f]{40}/\10000000000000000000000000000000000000000/'; do
  w="$tmp/ws_upx"; rm -rf "$w"; cp -r "$up" "$w"; sed -i -E "${spec#*|}" "$w/$REC"; upcase "an upload authorization with ${spec%%|*}" "$w" "$WFSHA" false false
done
for id in D1 D2 D4 D5; do
  w="$tmp/ws_upx"; rm -rf "$w"; cp -r "$up" "$w"; awk -v id="$id" 'index($0, "| " id " | ") == 1 { sub(/\| Decided \| CTO \| 2026-11-21 \|[ ]*$/, "| Proposed, not decided | TBD | TBD |") } { print }' "$w/$REC" > "$w/$REC.n" && mv "$w/$REC.n" "$w/$REC"
  upcase "an upload authorization while decision $id is still Proposed" "$w" "$WFSHA" false false
done
for f in .github/workflows/ios-hosted-signing.yml tool/check_signing_authorization.sh tool/verify_ipa.py tool/ipa_inspect.py; do
  w="$tmp/ws_upx"; rm -rf "$w"; cp -r "$up" "$w"; printf '\n# changed after the authorization\n' >> "$w/$f"; upcase "an upload authorization with $f changed after it was given" "$w" "$WFSHA" false false
done
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
# 4b. The UPLOAD: the probe, the pre-check and the upload step, run with SYNTHETIC input, a stub `xcrun altool` and synthetic credentials
# ============================================================================================================================
FAKEKEYID=FAKEKEY123
FAKEISSUER=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
IPAC="synthetic ipa bytes for the upload tests"
IPAH="$(printf '%s' "$IPAC" | shasum -a 256 | awk '{print $1}')"

# ---- the probe: which interface does the runner's altool offer? (decided BEFORE any credential exists)
run_probe() { # VARIANT: package | legacy | none | partial | missing
  PRB="$(mktemp -d -p "$tmp")"; mkdir -p "$PRB/evidence" "$PRB/tmp" "$PRB/stub"
  cat > "$PRB/stub/xcrun" <<'EOF'
#!/bin/bash
case "$1" in
  --find) [ "${STUB_VARIANT:-}" = missing ] && exit 1; echo /Applications/Xcode_26.3.app/Contents/Developer/usr/bin/altool; exit 0 ;;
  altool) [ "${2:-}" = "--help" ] || exit 2; cat "$STUB_HELP_FILE"; exit 0 ;;
esac
exit 2
EOF
  printf '#!/bin/bash\necho "Xcode 26.3"\necho "Build version 17C529"\n' > "$PRB/stub/xcodebuild"; chmod +x "$PRB/stub/xcrun" "$PRB/stub/xcodebuild"
  case "$1" in
    package) cat > "$PRB/help.txt" <<'EOF'
OVERVIEW: altool - Command-line tool for interacting with the App Store Connect API.
USAGE: xcrun altool [--upload-package | --upload-app -f] <file> --platform <platform> --apple-id <id> --bundle-id <id> --bundle-version <string> --bundle-short-version-string <string> [--wait]
       xcrun altool --validate-app <file> --platform <platform> --apple-id <id> --bundle-id <id> --bundle-version <string> --bundle-short-version-string <string>
OPTIONS:
  --api-key <string>      Required for JWT authentication.
  --api-issuer <uuid>     Required if --api-key is specified.
EOF
    ;;
    legacy) cat > "$PRB/help.txt" <<'EOF'
USAGE: altool --validate-app -f <file> -t <type> [--apiKey <key> --apiIssuer <issuer>]
       altool --upload-app -f <file> -t <type> [--apiKey <key> --apiIssuer <issuer>]
EOF
    ;;
    partial) cat > "$PRB/help.txt" <<'EOF'
USAGE: xcrun altool --upload-package <file> --validate-app <file> --platform <p> --apple-id <id> --bundle-version <v> --bundle-short-version-string <s> --api-key <k>
EOF
    ;;
    *) printf 'USAGE: altool --notarize-app <file> --primary-bundle-id <id>\n' > "$PRB/help.txt" ;;
  esac
  ( cd "$PRB" && env -i PATH="$PRB/stub:$PATH" HOME="$HOME" RUNNER_TEMP="$PRB/tmp" STUB_VARIANT="$1" STUB_HELP_FILE="$PRB/help.txt" bash -e "$STEP_uprobe" > "$PRB/stdout" 2>&1 ); PRB_RC=$?
}
run_probe package; [ "$PRB_RC" -eq 0 ] && [ "$(cat "$PRB/tmp/upload-syntax")" = package ] && grep -qx 'syntax=package' "$PRB/evidence/upload-tool-probe.txt" && [ -s "$PRB/evidence/upload-tool-help.txt" ]; chk "probe: an altool with --upload-package, --api-key and --api-issuer is the 'package' interface (evidence kept)" $? "rc=$PRB_RC"
run_probe legacy; [ "$PRB_RC" -eq 0 ] && [ "$(cat "$PRB/tmp/upload-syntax")" = legacy ] && grep -qx 'syntax=legacy' "$PRB/evidence/upload-tool-probe.txt"; chk "probe: an altool with --upload-app, --apiKey and --apiIssuer is the 'legacy' interface" $? "rc=$PRB_RC"
for v in none partial missing; do
  run_probe "$v"; [ "$PRB_RC" -ne 0 ] && [ ! -e "$PRB/tmp/upload-syntax" ] && grep -q 'Stopping before any credential is used' "$PRB/stdout"; chk "probe: a tool that offers no complete interface ($v) stops the run BEFORE any credential is used, and no syntax is recorded" $? "rc=$PRB_RC"
done
run_probe none; grep -qx 'syntax=none' "$PRB/evidence/upload-tool-probe.txt"; chk "probe: the refusal is kept as evidence (syntax=none)" $?

# ---- the pre-check: the authorization and the exact IPA, read again right before the upload (no secret)
run_pre() { # WS TIP [SETUP-snippet evaluated with $d] [VAR=value ...]
  local ws="$1" tip="$2" setup="${3:-}"; shift 3 2>/dev/null || shift $#
  PRE_DIR="$(mktemp -d -p "$tmp")"; local d="$PRE_DIR"
  mkdir -p "$d/evidence" "$d/tmp"; cp -r "$ws" "$d/tools"
  printf '%s' "$IPAC" > "$d/tmp/Runner.ipa"
  printf 'xcodebuild_exportArchive_exit=0\nipa_sha256_after_export=%s\nipa_size=1\n' "$IPAH" > "$d/evidence/export-result.txt"
  printf 'ipa_sha256_after_export=%s\nipa_sha256_after_verification=%s\nipa_size=1\n' "$IPAH" "$IPAH" > "$d/evidence/ipa-digest.txt"
  printf 'CFBundleIdentifier=%s\nCFBundleShortVersionString=1.0.4\nCFBundleVersion=1000035\nCFBundleDisplayName=Cadena Bitcoin\n' "$BID" > "$d/evidence/v1-identity.txt"
  printf 'package\n' > "$d/tmp/upload-syntax"; : > "$d/env"
  [ -z "$setup" ] || eval "$setup"
  ( cd "$d" && env -i PATH="$stubdir:$PATH" HOME="$HOME" REAL_GIT="$REAL_GIT" STUB_TIP="$tip" RUNNER_TEMP="$d/tmp" GITHUB_ENV="$d/env" IPA="$d/tmp/Runner.ipa" GITHUB_SHA="$WFSHA" \
      GITHUB_SERVER_URL=https://example.invalid GITHUB_REPOSITORY=example/repo APPROVED_SHA="$SHA" EXPECTED_VERSION="$VER" BUNDLE_ID="$BID" TEAM_ID="$TEAM" "$@" bash -e "$STEP_upre" > "$d/stdout" 2>&1 ); PRE_RC=$?
}
pre_refused() { # NAME WS TIP [SETUP]
  run_pre "$2" "$3" "${4:-}"; [ "$PRE_RC" -ne 0 ] && [ ! -s "$PRE_DIR/env" ] && [ ! -e "$PRE_DIR/tmp/asc-private-keys" ]; chk "pre-check: $1 -> refused; nothing is handed to the upload step" $? "rc=$PRE_RC env=$(cat "$PRE_DIR/env" | tr '\n' ' ')"
}
run_pre "$up" "$WFSHA"
[ "$PRE_RC" -eq 0 ] && grep -qx 'UPLOAD_SYNTAX=package' "$PRE_DIR/env" && grep -qx "UPLOAD_BUNDLE_ID=$BID" "$PRE_DIR/env" && grep -qx 'UPLOAD_SHORT_VERSION=1.0.4' "$PRE_DIR/env" && grep -qx 'UPLOAD_BUILD=1000035' "$PRE_DIR/env" && grep -qx "UPLOAD_IPA_SHA256=$IPAH" "$PRE_DIR/env" && [ "$(stat -c %a "$PRE_DIR/tmp/asc-private-keys")" = 700 ] && [ -z "$(ls -A "$PRE_DIR/tmp/asc-private-keys")" ] && grep -qx 'operation=sign-verify-and-upload' "$PRE_DIR/evidence/upload-precheck.txt"; chk "pre-check: a complete upload authorization and the exact IPA pass; the identity, the digest and the syntax are handed on, and an empty mode-700 key directory exists" $? "rc=$PRE_RC $(tail -n 3 "$PRE_DIR/stdout")"
[ "$(wc -l < "$PRE_DIR/env" | tr -d ' ')" -eq 5 ]; chk "pre-check: exactly five non-secret values are written to GITHUB_ENV" $?
pre_refused "the signing-only authorization (sign-and-verify-only) can never give an upload" "$good" "$WFSHA"
pre_refused "the tip of development moved on (for example a withdrawal was merged while the run was going)" "$up" "$OLDSHA"
pre_refused "the tip of development cannot be read" "$up" ""
w="$tmp/ws_upx"; rm -rf "$w"; cp -r "$up" "$w"; sed -i 's/`G2 AUTHORIZED`/`G1 AUTHORIZED`/' "$w/$REC"; pre_refused "the record status is G1 (an upload needs G2 AUTHORIZED)" "$w" "$WFSHA"
for id in D1 D2 D4 D5; do
  w="$tmp/ws_upx"; rm -rf "$w"; cp -r "$up" "$w"; awk -v id="$id" 'index($0, "| " id " | ") == 1 { sub(/\| Decided \| CTO \| 2026-11-21 \|[ ]*$/, "| Proposed, not decided | TBD | TBD |") } { print }' "$w/$REC" > "$w/$REC.n" && mv "$w/$REC.n" "$w/$REC"
  pre_refused "decision $id is not decided" "$w" "$WFSHA"
done
w="$tmp/ws_upx"; rm -rf "$w"; cp -r "$up" "$w"; sed -i 's/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: WITHDRAWN/' "$w/$REC"; pre_refused "the authorization was withdrawn" "$w" "$WFSHA"
w="$tmp/ws_upx"; rm -rf "$w"; cp -r "$up" "$w"; sed -i 's/^G2S-OPERATION: .*/G2S-OPERATION: sign-verify-and-upload /' "$w/$REC"; pre_refused "an operation line with a trailing space" "$w" "$WFSHA"
w="$tmp/ws_upx"; rm -rf "$w"; cp -r "$up" "$w"; sed -i 's/^G2S-GATE-BLOB: .*/G2S-GATE-BLOB: 0000000000000000000000000000000000000000/' "$w/$REC"; pre_refused "the record names another gate" "$w" "$WFSHA"
w="$tmp/ws_upx"; rm -rf "$w"; cp -r "$up" "$w"; printf '\n# changed after the authorization\n' >> "$w/.github/workflows/ios-hosted-signing.yml"; pre_refused "the workflow changed after the authorization" "$w" "$WFSHA"
pre_refused "the IPA changed after it was exported and verified (the same size, other bytes)" "$up" "$WFSHA" 'printf "%s" "SYNTHETIC ipa bytes for the upload tests" > "$d/tmp/Runner.ipa"'
pre_refused "the digest recorded at the export is another one" "$up" "$WFSHA" 'printf "ipa_sha256_after_export=%s\n" "$(printf x | shasum -a 256 | cut -d" " -f1)" > "$d/evidence/export-result.txt"'
pre_refused "the digest recorded after the verification is another one" "$up" "$WFSHA" 'printf "ipa_sha256_after_verification=%s\n" "$(printf x | shasum -a 256 | cut -d" " -f1)" > "$d/evidence/ipa-digest.txt"'
pre_refused "the digests are missing" "$up" "$WFSHA" ': > "$d/evidence/ipa-digest.txt"'
pre_refused "the verified bundle identifier is another one" "$up" "$WFSHA" 'sed -i "s/^CFBundleIdentifier=.*/CFBundleIdentifier=com.example.other/" "$d/evidence/v1-identity.txt"'
pre_refused "the verified version is another one" "$up" "$WFSHA" 'sed -i "s/^CFBundleShortVersionString=.*/CFBundleShortVersionString=1.0.5/" "$d/evidence/v1-identity.txt"'
pre_refused "the verified build number is another one" "$up" "$WFSHA" 'sed -i "s/^CFBundleVersion=.*/CFBundleVersion=1000036/" "$d/evidence/v1-identity.txt"'
pre_refused "no upload-tool syntax was probed" "$up" "$WFSHA" 'rm "$d/tmp/upload-syntax"'
pre_refused "the probed syntax is something else" "$up" "$WFSHA" 'printf "evil; rm -rf /\n" > "$d/tmp/upload-syntax"'
pre_refused "the IPA is missing" "$up" "$WFSHA" 'rm "$d/tmp/Runner.ipa"'
pre_refused "the IPA is a symbolic link" "$up" "$WFSHA" 'mv "$d/tmp/Runner.ipa" "$d/tmp/real.ipa"; ln -s real.ipa "$d/tmp/Runner.ipa"'
run_pre "$up" "$WFSHA"; ! grep -q 'secrets\.\|APPLE_API' "$STEP_upre"; chk "pre-check: the step refers to no secret and no APPLE_API variable" $?

# ---- the upload step itself
UPSEC=""
run_upload() { # VALIDATE_RC UPLOAD_RC SYNTAX [SETUP-snippet evaluated with $UP] [VAR=value ...]
  local vrc="$1" urc="$2" syn="$3" setup="${4:-}"; shift 4 2>/dev/null || shift $#
  UP="$(mktemp -d -p "$tmp")"; mkdir -p "$UP/evidence" "$UP/tmp/asc-private-keys" "$UP/stub"; chmod 700 "$UP/tmp/asc-private-keys"
  printf '%s' "$IPAC" > "$UP/tmp/Runner.ipa"
  cat > "$UP/stub/xcrun" <<'EOF'
#!/bin/bash
# STUB xcrun altool: records the call, reports what a child of the upload step can see (names and counts, never values), and plays altool at its worst:
# it prints the key ID, the issuer ID, a key line, a JWT-shaped token and a bearer token into its own output.
[ "${1:-}" = altool ] || exit 2
shift
echo "CALL: $*" >> "$STUB_CALLS"
{
  echo "env var names with APPLE_API: $(env | cut -d= -f1 | grep -c APPLE_API)"
  echo "env values containing the key text: $(env | grep -c TESTONLYFAKEKEY)"
  echo "env values containing the key id other than KEYFILE: $(env | grep -v "^KEYFILE=" | grep -c FAKEKEY123)"
  echo "env values containing the issuer id: $(env | grep -c aaaaaaaa-bbbb)"
  echo "key file readable: $([ -r "$KEYFILE" ] && echo yes || echo no) mode: $(stat -c %a "$KEYFILE" 2>/dev/null)"
  echo "key directory is the one altool is told: $([ "${API_PRIVATE_KEYS_DIR:-}" = "$(dirname "$KEYFILE")" ] && echo yes || echo no)"
} >> "$STUB_REPORT"
echo "key id FAKEKEY123 issuer aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee path $KEYFILE"
sed -n '2p' "$KEYFILE"
echo "token $STUB_JWT end; Authorization: Bearer abcdefgh12345678"
echo "-----BEGIN PRIVATE KEY-----"
case " $* " in
  *" --validate-app "*) exit "${STUB_VALIDATE_RC:-0}" ;;
  *" --upload-package "*|*" --upload-app "*) echo "Delivery UUID: 12345678-1234-1234-1234-123456789012"; exit "${STUB_UPLOAD_RC:-0}" ;;
esac
exit 9
EOF
  chmod +x "$UP/stub/xcrun"
  ENVBIN="$(type -P env)"; GREPBIN="$(type -P grep)"
  for tool in chmod head rm cat mkdir tail grep wc shasum stat awk date env ls; do
    real="$(type -P "$tool" 2>/dev/null)" && [ -x "$real" ] || continue
    printf '#!/bin/bash\necho %s >> "$LEAKLOG.calls"\nif %s | %s -q TESTONLYFAKEKEY; then echo %s >> "$LEAKLOG"; fi\nexec %s "$@"\n' "$tool" "$ENVBIN" "$GREPBIN" "$tool" "$real" > "$UP/stub/$tool"; chmod +x "$UP/stub/$tool"
  done
  : > "$UP/report.txt"; : > "$UP/calls.txt"
  [ -z "$setup" ] || eval "$setup"
  ( cd "$UP" && env -i PATH="$UP/stub:$PATH" HOME="$HOME" RUNNER_TEMP="$UP/tmp" IPA="$UP/tmp/Runner.ipa" UPLOAD_SYNTAX="$syn" UPLOAD_BUNDLE_ID="$BID" UPLOAD_SHORT_VERSION=1.0.4 UPLOAD_BUILD=1000035 \
      UPLOAD_IPA_SHA256="$IPAH" APP_APPLE_ID=6753348211 LEAKLOG="$UP/leak.log" STUB_REPORT="$UP/report.txt" STUB_CALLS="$UP/calls.txt" STUB_VALIDATE_RC="$vrc" STUB_UPLOAD_RC="$urc" STUB_JWT="$FAKEJWT" \
      APPLE_API_KEY_P8="${UPKEY-$FAKEKEY}" APPLE_API_KEY_ID="${UPKEYID-$FAKEKEYID}" APPLE_API_ISSUER_ID="${UPISSUER-$FAKEISSUER}" "$@" bash -e "$STEP_uup" > "$UP/stdout" 2>&1 ); UP_RC=$?
}
up_leaks() { grep -rE 'FAKEKEY123|aaaaaaaa-bbbb|TESTONLYFAKEKEY|eyJhbGciOi|abcdefgh12345678' "$UP/stdout" "$UP/evidence" 2>/dev/null | wc -l | tr -d ' '; }
up_clean() { # NAME : the key is gone, nothing leaked, no process saw the key text
  [ -z "$(find "$UP" -name '*.p8')" ]; chk "upload step ($1): the key file is removed afterwards" $?
  [ "$(up_leaks)" = 0 ]; chk "upload step ($1): no key ID, issuer ID, key line, JWT or bearer token in the job log or the kept evidence" $? "$(grep -rhE 'FAKEKEY123|aaaaaaaa-bbbb|TESTONLYFAKEKEY|eyJhbGciOi|abcdefgh12345678' "$UP/stdout" "$UP/evidence" 2>/dev/null | head -3)"
  [ -f "$UP/leak.log" ] || : > "$UP/leak.log"; [ ! -s "$UP/leak.log" ]; chk "upload step ($1): no program the step starts has the key text in its environment" $? "saw it: $(sort -u "$UP/leak.log" | tr '\n' ' ')"
}
# --- success, current interface
run_upload 0 0 package
[ "$UP_RC" -eq 0 ]; chk "upload step (success): exit status $UP_RC is 0" $? "$(tail -n 4 "$UP/stdout")"
[ "$(wc -l < "$UP/calls.txt" | tr -d ' ')" -eq 2 ] && sed -n 1p "$UP/calls.txt" | grep -q -- '--validate-app' && sed -n 2p "$UP/calls.txt" | grep -q -- '--upload-package'; chk "upload step (success): Apple's validation runs first, then exactly ONE upload" $? "$(cat "$UP/calls.txt")"
for n in 1 2; do
  c="$(sed -n ${n}p "$UP/calls.txt")"
  case "$c" in *"$UP/tmp/Runner.ipa"*"--platform ios"*"--apple-id 6753348211"*"--bundle-id $BID"*"--bundle-version 1000035"*"--bundle-short-version-string 1.0.4"*"--api-key $FAKEKEYID"*"--api-issuer $FAKEISSUER"*) r=0 ;; *) r=1 ;; esac
  chk "upload step (success): call $n names THE verified IPA, the production record, the exact identity and the key" $r "$c"
done
grep -q '^env values containing the key text: 0$' "$UP/report.txt" && ! grep -q 'env var names with APPLE_API: [1-9]' "$UP/report.txt" && grep -q '^env values containing the key id other than KEYFILE: 0$' "$UP/report.txt" && grep -q '^env values containing the issuer id: 0$' "$UP/report.txt"; chk "upload step (success): altool's environment holds no APPLE_API_* variable, no key text and no issuer ID, and the key ID only inside the key file's name (KEYFILE), which altool needs" $?
[ "$(grep -c 'key file readable: yes mode: 600' "$UP/report.txt")" -eq 2 ] && [ "$(grep -c 'key directory is the one altool is told: yes' "$UP/report.txt")" -eq 2 ]; chk "upload step (success): while altool runs the key file is readable, mode 600, in the directory altool is told (API_PRIVATE_KEYS_DIR)" $?
grep -qx 'uploaded=yes' "$UP/evidence/upload-result.txt" && grep -qx 'validate_exit=0' "$UP/evidence/upload-result.txt" && grep -qx 'upload_exit=0' "$UP/evidence/upload-result.txt" && grep -qx "ipa_sha256=$IPAH" "$UP/evidence/upload-result.txt"; chk "upload step (success): the result is recorded (uploaded=yes, both exit codes, the digest of the uploaded file)" $?
grep -q 'REDACTED' "$UP/evidence/upload.log" && grep -q 'REDACTED' "$UP/evidence/upload-validate.log" && grep -q 'Delivery UUID' "$UP/evidence/upload.log"; chk "upload step (success): the redacted logs show where material was redacted and keep Apple's delivery message" $?
up_clean "success"
[ -f "$UP/leak.log.calls" ] && grep -qx chmod "$UP/leak.log.calls" && grep -qx rm "$UP/leak.log.calls" && grep -qx head "$UP/leak.log.calls"; chk "upload step: the wrappers saw chmod, rm and head run (the environment check above is not vacuous)" $?
# the redacted evidence must pass the seal
( cd "$UP" && env -i PATH="$PATH" HOME="$HOME" bash -e "$STEP_seal" > "$UP/seal.out" 2>&1 ); [ $? -eq 0 ] && [ -f "$UP/evidence/SHA256SUMS.txt" ] && [ -f "$UP/evidence/upload-result.txt" ]; chk "upload step (success): the evidence it kept passes the evidence seal (nothing token- or key-shaped is left in it)" $? "$(tail -n 3 "$UP/seal.out")"
# --- success, legacy interface
run_upload 0 0 legacy
[ "$UP_RC" -eq 0 ] && sed -n 1p "$UP/calls.txt" | grep -q -- "--validate-app -f $UP/tmp/Runner.ipa -t ios --apiKey $FAKEKEYID --apiIssuer $FAKEISSUER" && sed -n 2p "$UP/calls.txt" | grep -q -- "--upload-app -f $UP/tmp/Runner.ipa -t ios --apiKey $FAKEKEYID --apiIssuer $FAKEISSUER"; chk "upload step (legacy interface): validate-app then upload-app, the same file, -t ios and the camel-case key options" $? "$(cat "$UP/calls.txt")"
up_clean "legacy interface"
# --- the validation fails: NO upload
run_upload 5 0 package
[ "$UP_RC" -ne 0 ] && [ "$(wc -l < "$UP/calls.txt" | tr -d ' ')" -eq 1 ] && ! grep -q -- '--upload' "$UP/calls.txt" && grep -qx 'uploaded=no' "$UP/evidence/upload-result.txt" && grep -qx 'validate_exit=5' "$UP/evidence/upload-result.txt" && grep -q 'upload_exit=not attempted' "$UP/evidence/upload-result.txt"; chk "upload step (the validation fails): the step fails and NO upload command is ever run" $? "rc=$UP_RC $(cat "$UP/calls.txt")"
[ -s "$UP/evidence/upload-validate.log" ] && [ ! -e "$UP/evidence/upload.log" ]; chk "upload step (the validation fails): the validation log is kept (redacted), there is no upload log" $?
up_clean "the validation fails"
# --- the upload fails: reported, never repeated
run_upload 0 7 package
[ "$UP_RC" -ne 0 ] && [ "$(wc -l < "$UP/calls.txt" | tr -d ' ')" -eq 2 ] && grep -qx 'uploaded=no' "$UP/evidence/upload-result.txt" && grep -qx 'upload_exit=7' "$UP/evidence/upload-result.txt" && grep -q 'BEFORE any new run' "$UP/stdout"; chk "upload step (the upload fails): the step fails, the upload ran exactly once (no retry), the result says uploaded=no, and the message says to look in App Store Connect before a new run" $? "rc=$UP_RC"
up_clean "the upload fails"
# --- inputs that must stop the step before any file or process exists
nocall() { # NAME  (a refusal: no altool call, no key file, a non-zero status)
  [ "$UP_RC" -ne 0 ] && [ ! -s "$UP/calls.txt" ]; chk "upload step ($1): the step stops and altool is never run" $? "rc=$UP_RC"
  [ -z "$(find "$UP" -name '*.p8')" ]; chk "upload step ($1): no key file exists afterwards" $?
  [ "$(up_leaks)" = 0 ]; chk "upload step ($1): nothing of the credentials is printed or kept" $?
}
run_upload 0 0 package 'chmod 600 "$UP/tmp/Runner.ipa"; printf "%s" "changed after the re-check" > "$UP/tmp/Runner.ipa"'; nocall "the IPA changed since the pre-check"
for badid in "../../evil" "short" "fakekey123" "FAKEKEY1234" $'FAKEKEY123\nX' "FAKE KEY12" '$(touch pwned)' ; do
  UPKEYID="$badid" run_upload 0 0 package; nocall "a key ID of the wrong shape: $(printf '%s' "$badid" | head -c 14 | tr '\n' '_')"; [ ! -e "$UP/pwned" ] && [ ! -e "$UP/evil" ] && [ ! -e "$UP/tmp/evil.p8" ]; chk "upload step (bad key ID): no file was created from it anywhere" $?
done
UPISSUER="not-a-uuid" run_upload 0 0 package; nocall "an issuer ID that is not a UUID"
UPISSUER=$'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n--extra-option' run_upload 0 0 package; nocall "an issuer ID with a second line (an extra option)"
UPKEY="" run_upload 0 0 package; nocall "an empty key text"
UPKEY="not a pem file" run_upload 0 0 package; nocall "a stored key that is not a PEM file"
run_upload 0 0 weird; nocall "an unknown upload-tool syntax"
run_upload 0 0 package 'rm -rf "$UP/tmp/asc-private-keys"'; nocall "the key directory is missing (the pre-check did not run)"
unset UPKEY UPKEYID UPISSUER
# --- the key-file check after the upload
KC="$(mktemp -d -p "$tmp")"; mkdir -p "$KC/evidence" "$KC/tmp/asc-private-keys" "$KC/home"; : > "$KC/tmp/asc-private-keys/AuthKey_LEFTOVER12.p8"
( cd "$KC" && env -i PATH="$PATH" HOME="$KC/home" RUNNER_TEMP="$KC/tmp" bash -e "$STEP_ukey" > "$KC/out" 2>&1 ); [ $? -ne 0 ] && [ ! -e "$KC/tmp/asc-private-keys" ] && grep -q 'A key file remains' "$KC/out"; chk "key check after the upload: a leftover key file is reported (the step fails), removed, and the directory is removed" $?
KC="$(mktemp -d -p "$tmp")"; mkdir -p "$KC/evidence" "$KC/tmp" "$KC/home"
( cd "$KC" && env -i PATH="$PATH" HOME="$KC/home" RUNNER_TEMP="$KC/tmp" bash -e "$STEP_ukey" > "$KC/out" 2>&1 ); [ $? -eq 0 ] && grep -qx 'key_file_removed_after_upload_step=yes' "$KC/evidence/key-removed-after-upload.txt"; chk "key check after the upload: with no key file the evidence says so (key_file_removed_after_upload_step=yes)" $?

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
# 5b. Phase 7C: the evidence capture step and the failed-export distribution log
# ============================================================================================================================
P7="$tmp/p7c"; mkdir -p "$P7/st"
FX="$root/tool/ipa_fixture.py"
python3 -I "$FX" certs "$P7/certs" >/dev/null 2>&1 && python3 -I "$FX" unsigned "$P7/st" --env staging >/dev/null 2>&1
python3 -I "$FX" sign "$P7/st/Runner.app" "$P7/same.ipa" --certs "$P7/certs" --team SYNTH12345 >/dev/null 2>&1
python3 -I "$FX" sign "$P7/st/Runner.app" "$P7/reorder.ipa" --certs "$P7/certs" --team SYNTH12345 --mutate info-reorder >/dev/null 2>&1
python3 -I "$FX" sign "$P7/st/Runner.app" "$P7/secret.ipa" --certs "$P7/certs" --team SYNTH12345 --mutate info-secret >/dev/null 2>&1
[ -s "$P7/same.ipa" ] && [ -s "$P7/reorder.ipa" ] && [ -s "$P7/secret.ipa" ]; chk "capture step: the synthetic IPAs for the tests exist" $?
printf 'garbage' > "$P7/corrupt.ipa"
CAP=""
run_capture() { # EXPORT_EXIT(0|70|none) IPA_ENV(path|none) [FIND_IPA(path)]
  CAP="$(mktemp -d -p "$tmp")"; mkdir -p "$CAP/evidence" "$CAP/tmp/export" "$CAP/tools"; ln -s "$root/tool" "$CAP/tools/tool"
  [ "$1" = none ] || printf 'xcodebuild_exportArchive_exit=%s\n' "$1" > "$CAP/evidence/export-result.txt"
  printf 'earlier evidence of an earlier step\n' > "$CAP/evidence/v7-ipa-verify-output.txt"
  [ -z "${3:-}" ] || cp "$3" "$CAP/tmp/export/signer.ipa"
  local ipa_env=(); [ "$2" = none ] || ipa_env=(IPA="$2")
  ( cd "$CAP" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="$CAP/tmp" RUNNER_TEMP="$CAP/tmp" GITHUB_RUN_ID=4242 GITHUB_RUN_ATTEMPT=1 GITHUB_SHA="$WFSHA" \
      BASELINE_APP="$P7/st/Runner.app" "${ipa_env[@]}" bash -e "$STEP_capture" > "$CAP/stdout" 2>&1 ); CAP_RC=$?
}
cap_status() { sed -n "s/^$1=//p" "$CAP/evidence/v8-capture/status.txt" 2>/dev/null | head -1; }
grep -q 'secrets\.\|APPLE_API' "$STEP_capture"; [ $? -ne 0 ]; chk "capture step: it touches no secret (no secrets reference, no APPLE_API variable)" $?
run_capture 0 "$P7/same.ipa"
[ "$CAP_RC" -eq 0 ] && [ "$(cap_status state)" = export-succeeded ] && [ "$(cap_status infoplist_ipa)" = kept ] && [ "$(cap_status der)" = kept ] && [ -s "$CAP/evidence/v8-capture/ipa-Info.plist.b64" ]; chk "capture step: a successful export gives the evidence files (exit 0)" $? "rc=$CAP_RC $(cat "$CAP/stdout" | head -3)"
run_capture 0 "$P7/reorder.ipa"
[ "$CAP_RC" -eq 0 ] && grep -q 'serialization_only=yes' "$CAP/evidence/v8-capture/infoplist-summary.txt" && grep -q 'bytes_identical=NO' "$CAP/evidence/v8-capture/infoplist-summary.txt"; chk "capture step: an exported Info.plist that V8 would refuse still yields the evidence, and the capture itself is not a failure (it decides nothing)" $?
run_capture 70 none
[ "$CAP_RC" -eq 0 ] && [ "$(cap_status state)" = export-failed ] && [ ! -e "$CAP/evidence/v8-capture/ipa-Info.plist.b64" ] && [ -z "$(ls "$CAP/evidence/v8-capture" | grep '\.hex$')" ]; chk "capture step: after a failed export nothing is invented, and the step does not add a failure of its own" $? "rc=$CAP_RC"
run_capture 0 "$CAP/missing.ipa"
[ "$CAP_RC" -ne 0 ] && [ "$(cap_status state)" = ipa-missing-after-export ]; chk "capture step: an IPA missing after an export that succeeded FAILS the step (a diagnostic failure, not a silent skip)" $?
run_capture none none
[ "$CAP_RC" -eq 0 ] && [ "$(cap_status state)" = export-not-reached ]; chk "capture step: when the export step never ran, that is said, and the step does not fail" $?
run_capture 0 "$P7/corrupt.ipa"
[ "$CAP_RC" -ne 0 ] && grep -q 'the IPA cannot be read' "$CAP/evidence/v8-capture/status.txt"; chk "capture step: an unreadable IPA after a successful export FAILS the step (evidence collection failure is never silent)" $?
run_capture 0 none "$P7/same.ipa"
[ "$CAP_RC" -eq 0 ] && [ "$(cap_status infoplist_ipa)" = kept ]; chk "capture step: without IPA in the environment the exported IPA is found in the export directory" $?
run_capture 0 "$P7/same.ipa"
[ "$(cat "$CAP/evidence/v7-ipa-verify-output.txt")" = "earlier evidence of an earlier step" ]; chk "capture step: the evidence of earlier steps is not touched" $?
( cd "$CAP" && find . -type f | sort ) > "$CAP/after.list"
[ -z "$(grep -vE '^\./(evidence/(v8-capture/.*|export-result\.txt|v7-ipa-verify-output\.txt)|stdout|after\.list)$' "$CAP/after.list" | grep -v '^./tools/')" ]; chk "capture step: it writes nothing outside evidence/v8-capture (and keeps no IPA)" $?
[ -z "$(find "$CAP/tmp" -maxdepth 1 -name 'verify_ipa_cap_*')" ] && [ ! -e "$CAP/evidence/v8-capture/signer.ipa" ] && [ -z "$(find "$CAP/evidence" -name '*.ipa')" ]; chk "capture step: no temporary copy of the executable and no IPA is left behind" $?
grep -qE 'PlistBuddy|CFBundle|NSCamera' "$CAP/stdout"; [ $? -ne 0 ]; chk "capture step: the job log shows no property list key or value" $?
SEAL="$(mktemp -d -p "$tmp")"; cp -R "$CAP/evidence" "$SEAL/evidence"
( cd "$SEAL" && env -i PATH="$PATH" HOME="$HOME" bash -e "$STEP_seal" > "$SEAL/stdout" 2>&1 ); SEAL_RC=$?
[ "$SEAL_RC" -eq 0 ] && [ -s "$SEAL/evidence/v8-capture/ipa-Info.plist.b64" ] && [ -s "$SEAL/evidence/v8-capture/der-summary.txt" ] && grep -q 'v8-capture/ipa-Info.plist.b64' "$SEAL/evidence/SHA256SUMS.txt"; chk "capture step: the evidence seal keeps the captured files and checksums them" $?
run_capture 0 "$P7/secret.ipa"
SEAL="$(mktemp -d -p "$tmp")"; cp -R "$CAP/evidence" "$SEAL/evidence"
( cd "$SEAL" && env -i PATH="$PATH" HOME="$HOME" bash -e "$STEP_seal" > "$SEAL/stdout" 2>&1 ); SEAL_RC=$?
[ "$CAP_RC" -eq 0 ] && [ "$(cap_status infoplist_ipa)" = "withheld: a JWT-shaped token" ] && [ "$SEAL_RC" -eq 0 ] && [ -s "$SEAL/evidence/v7-ipa-verify-output.txt" ] && ! grep -rq 'eyJhbGciOiJFUzI1NiJ9' "$CAP/evidence" "$CAP/stdout"; chk "capture step: an Info.plist carrying a token-shaped string is withheld, nothing of it is kept, and the evidence seal does NOT wipe the other evidence" $?

# ---- the distribution log of a FAILED export, through the redaction (the credential step, synthetic key, stub xcodebuild)
PK=""
run_pkg() { # MODE: normal | nobundle | outside | linkdir | linklog | old | decoy | big | success
  PK="$(mktemp -d -p "$tmp")"; mkdir -p "$PK/evidence" "$PK/tmp" "$PK/stub" "$PK/T" "$PK/elsewhere"
  cat > "$PK/stub/xcodebuild" <<'XEOF'
#!/bin/bash
# STUB xcodebuild: fails like a real failed export and leaves a distribution log bundle named on its first output line.
mode="$STUB_PKG"
bundle="$TMPDIR/production_2026-11-22_10-00-00.000.xcdistributionlogs"
[ "$mode" = outside ] && bundle="$STUB_ELSEWHERE/production_x.xcdistributionlogs"
write_log() { printf 'Processing step: IDEDistributionCodesignStep\nkey id FAKEKEYID99 issuer fake-issuer-0000-aaaa\ntoken %s end\n-----BEGIN PRIVATE KEY-----\nplain line kept\n' "$STUB_JWT" > "$1"; }
case "$mode" in
  linkdir) mkdir -p "$STUB_ELSEWHERE/real.xcdistributionlogs"; write_log "$STUB_ELSEWHERE/real.xcdistributionlogs/Packaging.log"; ln -s "$STUB_ELSEWHERE/real.xcdistributionlogs" "$bundle" ;;
  linklog) mkdir -p "$bundle"; write_log "$STUB_ELSEWHERE/target.log"; ln -s "$STUB_ELSEWHERE/target.log" "$bundle/Packaging.log" ;;
  nobundle) ;;
  *) mkdir -p "$bundle"; write_log "$bundle/Packaging.log"
     [ "$mode" = old ] && touch -d '2000-01-01' "$bundle/Packaging.log"
     [ "$mode" = unreadable ] && chmod 000 "$bundle/Packaging.log"
     [ "$mode" = big ] && head -c 4500000 /dev/zero | tr '\0' 'a' >> "$bundle/Packaging.log" ;;
esac
[ "$mode" = decoy ] && { mkdir -p "$TMPDIR/stale_2020.xcdistributionlogs"; printf 'DECOYSECRET99\n' > "$TMPDIR/stale_2020.xcdistributionlogs/Packaging.log"; }
[ "$mode" != nobundle ] && [ "$mode" != success ] && echo "2026-11-22 10:00:00.000 xcodebuild[1:2] [MT] IDEDistribution: Created bundle at path \"$bundle\"."
echo "token $STUB_JWT"
[ "$mode" = success ] && { exp=""; while [ $# -gt 0 ]; do [ "$1" = "-exportPath" ] && exp="$2"; shift; done; : > "$exp/Runner.ipa"; exit 0; }
exit 70
XEOF
  printf '#!/bin/bash\nexit 0\n' > "$PK/stub/plutil"; chmod +x "$PK/stub/xcodebuild" "$PK/stub/plutil"
  ( cd "$PK" && env -i PATH="$PK/stub:$PATH" HOME="$HOME" TMPDIR="$PK/T" RUNNER_TEMP="$PK/tmp" GITHUB_ENV="$PK/env" TEAM_ID="$TEAM" ARCHIVE="$PK/tmp/a.xcarchive" \
      STUB_PKG="$1" STUB_ELSEWHERE="$PK/elsewhere" STUB_JWT="$FAKEJWT" APPLE_API_KEY_P8="$FAKEKEY" APPLE_API_KEY_ID=FAKEKEYID99 APPLE_API_ISSUER_ID=fake-issuer-0000-aaaa \
      bash -e "$STEP_secret" > "$PK/stdout" 2>&1 ); PK_RC=$?
}
pk_leaks() { grep -rE 'FAKEKEYID99|fake-issuer-0000|TESTONLYFAKEKEY|eyJhbGciOi|DECOYSECRET99|BEGIN PRIVATE' "$PK/stdout" "$PK/evidence" 2>/dev/null | wc -l | tr -d ' '; }
pk_src() { sed -n "s/^$1=//p" "$PK/evidence/packaging-log-source.txt" 2>/dev/null | head -1; }
run_pkg normal
[ "$PK_RC" -ne 0 ] && [ -s "$PK/evidence/Packaging.log" ] && grep -q 'REDACTED' "$PK/evidence/Packaging.log" && grep -q 'plain line kept' "$PK/evidence/Packaging.log" && [ "$(pk_src packaging_log | cut -c1-9)" = collected ]; chk "packaging log: a failed export's distribution log is collected and the step still fails" $? "rc=$PK_RC"
[ "$(pk_leaks)" = 0 ]; chk "packaging log: no key ID, issuer ID, key line, JWT or private-key marker survives in the collected log, the job log or any evidence" $? "$(grep -rhE 'FAKEKEYID99|fake-issuer-0000|eyJhbGciOi|BEGIN PRIVATE' "$PK/evidence" "$PK/stdout" | head -3)"
[ -z "$(find "$PK/tmp" -maxdepth 1 -name '*.p8')" ]; chk "packaging log: the key file is still removed afterwards" $?
for mode in nobundle outside linkdir linklog old big; do
  run_pkg "$mode"
  case "$mode" in nobundle) why="names no distribution log bundle" ;; outside) why="not a plain bundle directly inside" ;; linkdir) why="a link or not a directory" ;; linklog) why="holds no plain Packaging.log" ;; old) why="older than this export run" ;; big) why="larger than the redaction reads" ;; esac
  [ ! -e "$PK/evidence/Packaging.log" ] && [ "$(pk_src packaging_log)" = "not collected" ] && grep -q "$why" "$PK/evidence/packaging-log-source.txt" && [ "$(pk_leaks)" = 0 ] && [ "$PK_RC" -ne 0 ]; chk "packaging log ($mode): it is NOT collected, a one-line reason is kept ($why), nothing leaks, the failure stays" $? "$(cat "$PK/evidence/packaging-log-source.txt" 2>/dev/null | tr '\n' '|')"
done
# a log that cannot be redacted is withheld, and the step says so (it does not go on as if the evidence were complete)
if [ "$(id -u)" -ne 0 ]; then
  run_pkg unreadable
  [ "$PK_RC" -ne 0 ] && [ ! -e "$PK/evidence/Packaging.log" ] && [ "$(pk_src packaging_log)" = "withheld: the redaction failed" ] && grep -q 'A redaction failed. Evidence of this step is withheld' "$PK/stdout" && ! grep -q -- '---- xcodebuild -exportArchive (redacted)' "$PK/stdout" && [ "$(pk_leaks)" = 0 ]; chk "packaging log: a log that cannot be redacted is withheld, the step reports the failed redaction and prints no evidence tail" $? "$(cat "$PK/evidence/packaging-log-source.txt" 2>/dev/null | tr '\n' '|')"
else
  ok "packaging log: (the unreadable-log case is skipped: this runs as root, which can read any file)"
fi
run_pkg decoy
[ "$(pk_leaks)" = 0 ] && ! grep -q DECOYSECRET99 "$PK/evidence/Packaging.log"; chk "packaging log: another bundle in the temporary directory, not named by this run, is never read" $?
run_pkg success
[ "$PK_RC" -eq 0 ] && [ ! -e "$PK/evidence/packaging-log-source.txt" ] && [ ! -e "$PK/evidence/Packaging.log" ]; chk "packaging log: after a SUCCESSFUL export nothing of this kind is collected (the export directory's own copy is the source then)" $? "rc=$PK_RC"
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
# 6b. Exit-status constructs of steps that only run on macOS (the first real run stopped at one): the REAL lines of the steps,
#     extracted from the YAML and run on Linux with a stand-in `codesign`, under the step's own shell options (bash -e, pipefail)
# ============================================================================================================================
python3 -I - "$STEP_archive" "$STEP_v9" "$tmp" <<'PYX'
import sys, re
archive, v9, out = open(sys.argv[1]).read().split("\n"), open(sys.argv[2]).read().split("\n"), sys.argv[3]
a = next(i for i, l in enumerate(archive) if 'codesign_state="$(codesign -dv' in l)
b = next(i for i, l in enumerate(archive) if "codesign shows a signature on the archived app" in l)
open(out + "/snip_unsigned.sh", "w").write("\n".join(archive[a:b + 1]) + "\n")
c = next(i for i, l in enumerate(v9) if "The native library inspection failed" in l)
open(out + "/snip_v9_tail.sh", "w").write("\n".join(v9[c:]) + "\n")
PYX
[ -s "$tmp/snip_unsigned.sh" ] && [ -s "$tmp/snip_v9_tail.sh" ]; chk "the unsigned-state lines and the V9 tail can be extracted from the workflow" $?
run_unsigned() { # CASE -> UNS_RC ; the evidence file stays in $UNS_DIR
  UNS_DIR="$(mktemp -d -p "$tmp")"; mkdir -p "$UNS_DIR/evidence" "$UNS_DIR/bin" "$UNS_DIR/x/Runner.app"
  cat > "$UNS_DIR/bin/codesign" <<'EOF'
#!/bin/bash
# STAND-IN for codesign -dv. An unsigned bundle: the line the build job captured on the real archive, exit 1 (as `codesign -d` does).
a="$STUB_APP"
case "$STUB_CASE" in
  unsigned)        echo "$a: code object is not signed at all"; exit 1 ;;
  unsigned_note)   echo "$a: code object is not signed at all"; echo "warning: something else"; exit 1 ;;
  adhoc)           printf 'Executable=%s/Runner\nIdentifier=com.app.cadenabitcoin\nFormat=app bundle with Mach-O thin (arm64)\nSignature=adhoc\n' "$a"; exit 0 ;;
  signed)          printf 'Executable=%s/Runner\nIdentifier=com.app.cadenabitcoin\nFormat=app bundle with Mach-O thin (arm64)\nAuthority=Apple Distribution: X\nTeamIdentifier=D65458CPDP\n' "$a"; exit 0 ;;
  phrase_then_sig) echo "$a: code object is not signed at all"; echo "Authority=Apple Distribution: X"; exit 1 ;;
  phrase_not_last) echo "$a: code object is not signed at all yet"; exit 1 ;;
  error)           echo "$a: No such file or directory"; exit 1 ;;
  empty)           exit 0 ;;
esac
EOF
  chmod +x "$UNS_DIR/bin/codesign"
  ( cd "$UNS_DIR" && env -i PATH="$UNS_DIR/bin:$PATH" HOME="$HOME" APP="$UNS_DIR/x/Runner.app" STUB_APP="$UNS_DIR/x/Runner.app" STUB_CASE="$1" bash -e -c "set -uo pipefail
$(cat "$tmp/snip_unsigned.sh")" > "$UNS_DIR/out.txt" 2>&1 ); UNS_RC=$?
}
run_unsigned unsigned; [ "$UNS_RC" -eq 0 ]; chk "unsigned-state: a genuinely unsigned app (codesign prints the phrase and exits 1) is ACCEPTED under pipefail" $? "rc=$UNS_RC $(head -n 2 "$UNS_DIR/out.txt")"
grep -q 'code object is not signed at all' "$UNS_DIR/evidence/archive-codesign-state.txt"; chk "unsigned-state: the codesign answer is kept as evidence" $?
run_unsigned unsigned_note; [ "$UNS_RC" -eq 0 ]; chk "unsigned-state: an unsigned answer with an extra harmless line is accepted" $?
for c in adhoc signed phrase_then_sig phrase_not_last error empty; do
  run_unsigned "$c"; [ "$UNS_RC" -ne 0 ]; chk "unsigned-state: case '$c' is REFUSED" $? "rc=$UNS_RC"
done
run_unsigned adhoc; grep -q '::error::The archived app is not unsigned' "$UNS_DIR/out.txt"; chk "unsigned-state: the refusal of an ad-hoc-signed app says why" $? "$(head -n 2 "$UNS_DIR/out.txt")"
run_unsigned adhoc; [ -s "$UNS_DIR/evidence/archive-codesign-state.txt" ] && grep -q 'Signature=adhoc' "$UNS_DIR/evidence/archive-codesign-state.txt"; chk "unsigned-state: a refused answer is kept as evidence too" $?

# the Report step: an optional file that is absent is not a failure; a summary that cannot be written is
run_report() { # SETUP-COMMANDS [SUMMARY_PATH] -> REP_RC, REP_DIR
  REP_DIR="$(mktemp -d -p "$tmp")"; mkdir -p "$REP_DIR/evidence"; ( cd "$REP_DIR" && eval "$1" )
  ( cd "$REP_DIR" && env -i PATH="$PATH" HOME="$HOME" GITHUB_STEP_SUMMARY="${2:-$REP_DIR/summary.md}" bash -e "$STEP_report" > "$REP_DIR/out.txt" 2>&1 ); REP_RC=$?
}
run_report ':'; [ "$REP_RC" -eq 0 ] && grep -q '^## iOS hosted signing' "$REP_DIR/summary.md"; chk "report: with no optional evidence file at all (a failed early run) the step succeeds and writes the header" $? "rc=$REP_RC"
run_report 'echo x > evidence/v9-native.txt'; [ "$REP_RC" -eq 0 ] && grep -q '### v9-native.txt' "$REP_DIR/summary.md"; chk "report: with some optional files and the last one (export-diagnosis.txt) absent -- a SUCCESSFUL run -- the step succeeds" $? "rc=$REP_RC"
run_report 'for f in export-result ipa-digest v1-identity v4-profile-summary v6-environment v9-native export-diagnosis; do echo "$f" > evidence/$f.txt; done; echo abc > evidence/certificate-sha256.txt'; [ "$REP_RC" -eq 0 ] && grep -q '### export-diagnosis.txt' "$REP_DIR/summary.md" && grep -q 'Signing certificate SHA-256' "$REP_DIR/summary.md"; chk "report: with every optional file present all are reported and the step succeeds" $? "rc=$REP_RC"
run_report ':' "$REP_DIR/no-such-dir/summary.md"; [ "$REP_RC" -ne 0 ]; chk "report: a summary that cannot be written is still a failure (a meaningful reporting failure is not hidden)" $? "rc=$REP_RC"

# V9: the manifest line is informational; the gate lines still fail the step
run_v9() { # EXPORTS_LINE FORBIDDEN STRINGS_FORBIDDEN MANIFEST(yes|no) -> V9_RC, V9_DIR
  V9_DIR="$(mktemp -d -p "$tmp")"; mkdir -p "$V9_DIR/evidence" "$V9_DIR/app/Frameworks/dlc_wallet.framework"; : > "$V9_DIR/app/Frameworks/dlc_wallet.framework/dlc_wallet"
  [ "$4" = yes ] && : > "$V9_DIR/app/Frameworks/dlc_wallet.framework/PrivacyInfo.xcprivacy"
  echo "$1" > "$V9_DIR/evidence/v9-native.txt"
  ( cd "$V9_DIR" && env -i PATH="$PATH" HOME="$HOME" APP="$V9_DIR/app" forbidden="$2" strings_forbidden="$3" bash -e -c "set -uo pipefail
$(cat "$tmp/snip_v9_tail.sh")" > "$V9_DIR/out.txt" 2>&1 ); V9_RC=$?
}
OKX='exports=exactly the nine expected'
run_v9 "$OKX" 0 0 no;  [ "$V9_RC" -eq 0 ] && grep -q 'privacy_manifest=none' "$V9_DIR/evidence/v9-native.txt"; chk "V9: no manifest: the step succeeds and says 'none'" $? "rc=$V9_RC"
run_v9 "$OKX" 0 0 yes; [ "$V9_RC" -eq 0 ] && grep -q 'privacy_manifest=present' "$V9_DIR/evidence/v9-native.txt"; chk "V9: a privacy manifest present (X2 resolved later) does NOT fail the step; it is reported as 'present'" $? "rc=$V9_RC $(head -n 2 "$V9_DIR/out.txt")"
run_v9 'exports=DIFFER' 0 0 no;  [ "$V9_RC" -ne 0 ] && grep -q 'The native library inspection failed' "$V9_DIR/out.txt"; chk "V9 gate: exports other than the nine expected still FAIL the step" $? "rc=$V9_RC"
run_v9 "$OKX" 1 0 no;  [ "$V9_RC" -ne 0 ]; chk "V9 gate: a forbidden name among the exports still FAILS the step" $? "rc=$V9_RC"
run_v9 "$OKX" 0 2 yes; [ "$V9_RC" -ne 0 ]; chk "V9 gate: a forbidden name in the strings still FAILS the step (with a manifest present)" $? "rc=$V9_RC"

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
def block(mid, desc, start, end, new):
    global src
    a = src.index(start); b = src.index(end, a) + len(end)
    M.append((mid, desc, src[a:b], new, 0))
block("W1_unsigned_pipefail_regression", "the unsigned-state check is the old pipeline again (false failure under pipefail)", '          codesign_state="$(codesign -dv', 'on the archived app."; exit 1; fi\n', '          codesign -dv "$APP" 2>&1 | head -n 3 | grep -q \'not signed at all\' || { echo "::error::The archived app is not unsigned."; exit 1; }\n')
m("W2_unsigned_accepts_anything", "the unsigned-state check accepts any codesign answer", "            *': code object is not signed at all') ;;\n            *) echo", "            *) ;;\n            *) echo")
m("W3_unsigned_ignores_signature_lines", "signature lines after the phrase are ignored", "if grep -qE '^(Signature|Authority|TeamIdentifier)=' <<<\"$codesign_state\"; then", "if false; then")
m("W4_report_old_form", "the Report step ends with the && form again (fails when export-diagnosis.txt is absent)", '              [ -f "$f" ] || continue   # an optional file that does not exist is not an error (a successful run has no export-diagnosis.txt)\n              echo "### ${f#evidence/}"; echo \'```\'; cat "$f"; echo \'```\'\n', '              [ -f "$f" ] && { echo "### ${f#evidence/}"; echo \'```\'; cat "$f"; echo \'```\'; }\n')
m("W5_report_hides_summary_failure", "the Report step hides a summary that cannot be written", '          } >> "$GITHUB_STEP_SUMMARY"\n\n      - name: Upload the text evidence', '          } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true\n\n      - name: Upload the text evidence')
block("W6_v9_old_form", "the V9 manifest line is the && form again (fails when a manifest exists)", "          # Informational only (X2 is open)", "          fi\n", '          [ "$(ls "$APP/Frameworks/dlc_wallet.framework" | grep -c PrivacyInfo || true)" = "0" ] && echo "dlc_wallet_privacy_manifest=none (decision X2 is open; not decided here)" | tee -a evidence/v9-native.txt\n')
m("W7_v9_gate_suppressed", "a blanket || true suppresses the V9 security verdict", '|| { echo "::error::The native library inspection failed."; exit 1; }', '|| true')
m("O_upload_added", "an upload step in the signing job", '      - name: Fix the IPA digest again (integrity of the file that was verified)', '      - name: upload\n        run: xcrun altool --upload-app -f "$IPA" --apiKey x\n      - name: Fix the IPA digest again (integrity of the file that was verified)')
m("O2_destination_upload", "the export destination is upload", '<key>destination</key><string>export</string>', '<key>destination</key><string>upload</string>')
m("P_build_number_managed", "Xcode may manage the build number", '<key>manageAppVersionAndBuildNumber</key><false/>', '<key>manageAppVersionAndBuildNumber</key><true/>')
m("Q_ref_not_checked", "the signing job no longer insists on development", '[ "$GITHUB_REF" = "refs/heads/development" ] || { echo "::error::Hosted signing runs only from refs/heads/development."; fail=1; }', ':')
m("R_secret_wholesale", "the whole secret context is passed", 'APPLE_API_ISSUER_ID: ${{ secrets.APPLE_API_ISSUER_ID }}', 'APPLE_API_ISSUER_ID: ${{ secrets.APPLE_API_ISSUER_ID }}\n          ALL: ${{ toJSON(secrets) }}')
m("S_verifier_repo_is_approved", "the verifier is pointed at the approved checkout again", '--repo "$VERIFIER_REPO"', '--repo approved')
m("T_environment_dropped", "the protected environment is dropped", '    environment: ios-hosted-signing\n', '')
# Phase 7C: the evidence capture and the failed-export distribution log
m("X1_capture_not_always", "the capture step no longer runs after a failed step", '        if: always()\n        run: |\n          set -uo pipefail\n          set +e\n          mkdir -p evidence/v8-capture', '        run: |\n          set -uo pipefail\n          set +e\n          mkdir -p evidence/v8-capture')
m("X2_capture_continue_on_error", "the capture step is continue-on-error", '      - name: Capture the Info.plist and DER entitlements evidence (V8 diagnostics; read-only, decides nothing)\n        if: always()\n', '      - name: Capture the Info.plist and DER entitlements evidence (V8 diagnostics; read-only, decides nothing)\n        if: always()\n        continue-on-error: true\n')
m("X3_capture_never_fails", "the capture step always exits 0 (a missing IPA is silent)", '          exit $?\n\n      - name: Seal the evidence', '          exit 0\n\n      - name: Seal the evidence')
m("X4_capture_has_secret", "the capture step is given a secret", '      - name: Capture the Info.plist and DER entitlements evidence (V8 diagnostics; read-only, decides nothing)\n        if: always()\n', '      - name: Capture the Info.plist and DER entitlements evidence (V8 diagnostics; read-only, decides nothing)\n        if: always()\n        env:\n          K: ${{ secrets.APPLE_API_KEY_ID }}\n')
m("X5_log_stale_accepted", "a distribution log older than this export run is accepted", 'if os.stat(log).st_mtime < os.stat(marker).st_mtime:', 'if False:')
m("X6_log_dir_link_accepted", "a distribution log bundle that is a link is accepted", 'if os.path.islink(path) or not os.path.isdir(path):', 'if not os.path.isdir(path):')
m("X7_log_file_link_accepted", "a Packaging.log that is a link is accepted", 'if os.path.islink(log) or not os.path.isfile(log):', 'if not os.path.isfile(log):')
m("X8_log_outside_tmpdir", "a bundle outside the step's temporary directory is accepted", ' or os.path.realpath(os.path.dirname(path)) != tmpdir:', ':')
m("X9_log_not_redacted", "the distribution log is copied without redaction", 'if redact "$logdir/Packaging.log" evidence/Packaging.log; then', 'if cp "$logdir/Packaging.log" evidence/Packaging.log; then')
m("X10_log_after_success", "the distribution log is also collected after a successful export", 'if [ "$rc" -ne 0 ] && [ ! -f evidence/Packaging.log ]; then\n            cat > "$RUNNER_TEMP/findlog.py"', 'if true; then\n            cat > "$RUNNER_TEMP/findlog.py"')
m("X11_no_start_marker", "the export start marker is not written", '          : > "$RUNNER_TEMP/.export-start"\n', '')
m("X12_capture_no_ipa_search", "the capture step does not look for the IPA in the export directory", "          [ -n \"$ipa\" ] || ipa=\"$(find \"$RUNNER_TEMP/export\" -maxdepth 1 -name '*.ipa' 2>/dev/null | head -n 1)\"\n", '')
m("X13_capture_no_baseline", "the capture step is not given the archive's app", '--archive-app "${BASELINE_APP:-}"', '--archive-app ""')
m("X14_capture_out_elsewhere", "the capture writes into the evidence root instead of its own folder", '--out evidence/v8-capture --evidence-dir evidence', '--out evidence --evidence-dir evidence')
m("X15_log_failure_hidden", "a failed redaction of the distribution log is hidden", 'red=1; { echo "packaging_log=withheld: the redaction failed"', ':; { echo "packaging_log=withheld: the redaction failed"')
# The upload: each edit that would let a failed verification, an unauthorized dispatch, another file or a leaked credential through
m('UP1_precheck_not_gated', 'the pre-check step runs whether or not the upload is authorized', "      - name: Re-check the upload authorization and the exact IPA to upload (no secret yet)\n        if: needs.authorize.outputs.upload_authorized == 'true'\n", '      - name: Re-check the upload authorization and the exact IPA to upload (no secret yet)\n')
m('UP2_upload_runs_after_failure', 'the upload step runs even after a failed step (always())', "      - name: Validate and upload the verified IPA (the second and last step with secrets)\n        if: needs.authorize.outputs.upload_authorized == 'true'\n", "      - name: Validate and upload the verified IPA (the second and last step with secrets)\n        if: always() && needs.authorize.outputs.upload_authorized == 'true'\n")
m('UP2b_upload_only_after_failure', 'the upload step runs after a failed step (failure())', "      - name: Validate and upload the verified IPA (the second and last step with secrets)\n        if: needs.authorize.outputs.upload_authorized == 'true'\n", "      - name: Validate and upload the verified IPA (the second and last step with secrets)\n        if: failure() && needs.authorize.outputs.upload_authorized == 'true'\n")
m('UP3_operation_not_required', 'any passing authorization grants the upload (the operation is not read)', '            [ "$op" = "sign-verify-and-upload" ] && upload_authorized=true\n', '            upload_authorized=true\n')
m('UP4_output_missing', 'the authorize job no longer exposes upload_authorized', '      upload_authorized: ${{ steps.gate.outputs.upload_authorized }}\n', '')
m('UP5_validation_failure_ignored', 'an upload is attempted after a failed validation', '          if [ "$vrc" -eq 0 ]; then\n            # 2. Upload THE SAME file, once.', '          if true; then\n            # 2. Upload THE SAME file, once.')
m('UP6_digest_not_compared', 'the pre-check no longer compares the IPA with the verified digests', '[[ "$now" =~ $re_hex64 ]] && [ "$now" = "$exported" ] && [ "$now" = "$verified" ] || fail', 'true || fail')
m('UP7_gate_verdict_ignored', "the pre-check ignores the gate's verdict", '|| { cat "$RUNNER_TEMP/upload-gate.txt"; fail "The release record no longer authorizes this run."; }', '|| true')
m('UP8_operation_not_rechecked', "the pre-check does not re-read the record's operation", '[ "$op" = "sign-verify-and-upload" ] || fail "The release record\'s operation is \'$op\', not sign-verify-and-upload."', 'true')
m('UP9_stale_tip_precheck', 'the pre-check compares the revision with itself instead of the live tip', '--workflow-sha "$GITHUB_SHA" --development-tip "$tip" > "$RUNNER_TEMP/upload-gate.txt"', '--workflow-sha "$GITHUB_SHA" --development-tip "$GITHUB_SHA" > "$RUNNER_TEMP/upload-gate.txt"')
m('UP10_key_text_stays_in_env', "the key text stays in the environment of the upload step's processes", '          unset APPLE_API_KEY_P8\n          chmod 600 "$KEYFILE" 2>/dev/null\n', '          :\n          chmod 600 "$KEYFILE" 2>/dev/null\n')
m('UP11_upload_env_not_stripped', "altool's upload runs with the secrets in its environment", '            env -u APPLE_API_KEY_P8 -u APPLE_API_KEY_ID -u APPLE_API_ISSUER_ID xcrun altool "${UPLOAD[@]}"', '            xcrun altool "${UPLOAD[@]}"')
m('UP12_validate_env_not_stripped', "altool's validation runs with the secrets in its environment", '          env -u APPLE_API_KEY_P8 -u APPLE_API_KEY_ID -u APPLE_API_ISSUER_ID xcrun altool "${VALIDATE[@]}"', '          xcrun altool "${VALIDATE[@]}"')
m('UP13_upload_log_not_redacted', 'the upload log is kept without redaction', '            redact "$RUNNER_TEMP/upload.raw.log" evidence/upload.log || red=1', '            cp "$RUNNER_TEMP/upload.raw.log" evidence/upload.log')
m('UP14_validate_log_not_redacted', 'the validation log is kept without redaction', '          redact "$RUNNER_TEMP/validate.raw.log" evidence/upload-validate.log || red=1', '          cp "$RUNNER_TEMP/validate.raw.log" evidence/upload-validate.log')
m('UP15_no_trap', 'the upload step has no trap that removes the key file', '          trap cleanup EXIT\n          # (Errors of these three commands', '          # (Errors of these three commands')
m('UP16_shape_check_removed', 'the key ID and issuer ID shape check is removed', '[[ "$APPLE_API_KEY_ID" =~ $re_key ]] && [[ "$APPLE_API_ISSUER_ID" =~ $re_issuer ]] ||', 'true ||')
m('UP17_second_upload', 'a second upload attempt', '            urc=$?\n            redact "$RUNNER_TEMP/upload.raw.log"', '            urc=$?\n            env -u APPLE_API_KEY_P8 -u APPLE_API_KEY_ID -u APPLE_API_ISSUER_ID xcrun altool "${UPLOAD[@]}" > "$RUNNER_TEMP/upload2.raw.log" 2>&1\n            redact "$RUNNER_TEMP/upload.raw.log"')
m('UP18_upload_in_report_step', 'an upload command in another step', '      - name: Report (job summary)\n        if: always()\n        run: |\n          set +e\n', '      - name: Report (job summary)\n        if: always()\n        run: |\n          set +e\n          xcrun altool --upload-package "$IPA" --api-key x --api-issuer y\n')
m('UP19_upload_continue_on_error', 'the upload step is continue-on-error', "      - name: Validate and upload the verified IPA (the second and last step with secrets)\n        if: needs.authorize.outputs.upload_authorized == 'true'\n", "      - name: Validate and upload the verified IPA (the second and last step with secrets)\n        if: needs.authorize.outputs.upload_authorized == 'true'\n        continue-on-error: true\n")
m('UP20_probe_never_stops', 'the probe never stops the run', '          if [ -z "$altool_path" ] || [ "$syntax" = none ]; then', '          if false; then')
m('UP21_ipa_not_rechecked_before_upload', "the IPA's digest is not compared again right before the upload", '[ "$(shasum -a 256 "$IPA" | awk \'{print $1}\')" = "$UPLOAD_IPA_SHA256" ] || { echo "::error::The IPA changed since it was re-checked. Nothing was uploaded."; exit 1; }', ':')
m('UP22_probe_not_gated', 'the probe runs (and can fail) for every dispatch, authorized or not', "      - name: Probe Apple's upload tool (no secret; stops here, before any credential, if it cannot be used)\n        if: needs.authorize.outputs.upload_authorized == 'true'\n", "      - name: Probe Apple's upload tool (no secret; stops here, before any credential, if it cannot be used)\n")
m('UP23_legacy_validate_skipped', 'the legacy interface uploads without validating', '              VALIDATE=(--validate-app -f "$IPA" "${COMMON[@]}")', '              VALIDATE=(--version)')
m('UP24_upload_flag_changed', 'the upload command names another operation', 'UPLOAD=(--upload-package "$IPA" "${COMMON[@]}")', 'UPLOAD=(--validate-app "$IPA" "${COMMON[@]}")')
m('UP25_wrong_ipa_uploaded', 'another file than the verified IPA is uploaded', 'UPLOAD=(--upload-package "$IPA" "${COMMON[@]}")', 'UPLOAD=(--upload-package "$RUNNER_TEMP/other.ipa" "${COMMON[@]}")')
m('UP26_apple_id_dropped', 'the App Store Connect record is not named', 'COMMON=(--platform ios --apple-id "$APP_APPLE_ID" --bundle-id', 'COMMON=(--platform ios --bundle-id')
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
