#!/usr/bin/env python3
"""Build manifest: ties one built artifact to its source, version, build run and signing status.

  tool/build_manifest.py create  --evidence F.txt --toolchain T.txt --out M.json [--repo ROOT] [--release-id ID]
  tool/build_manifest.py verify  M.json [--repo ROOT] [--evidence F.txt]
  tool/build_manifest.py verify-dir DIR --variants "v1 v2 ..." [--repo ROOT]
  tool/build_manifest.py name    M.json [--classification internal-evaluation]
  tool/build_manifest.py check-file M.json FILE_OR_APP_DIR
  tool/build_manifest.py gate    --channel staging|production [--repo ROOT]

A manifest is written next to the existing text evidence of tool/verify_artifact.sh and the
workflow's run metadata (<variant>.txt). It adds no new fact about the artifact: it takes every
artifact fact from that evidence, the run metadata from the GitHub environment, and structures
them so that they can be checked by a machine. `verify` rejects missing, malformed,
inconsistent or contradictory metadata; with --repo it also recomputes what the repository at
that commit says (pubspec version, configuration file digest, published-version ledger).

Identifiers (docs/RELEASE_VERSIONING.md):
  application version   pubspec.yaml X.Y.Z+BUILD   changes only by a reviewed commit
  CI build identifier   <run id>.<attempt>:<variant>   unique per execution, never a version
  release identifier    vX.Y.Z[-rc.N]   null for a compile-validation build

This tool needs only python3 (standard library). It never reads or prints key material.
Exit status: 0 ok, 1 a check failed, 2 usage or unreadable input.
"""
import json
import os
import re
import subprocess
import sys

SCHEMA = "cadena-build-manifest/1"
LEDGER_SCHEMA = "cadena-published-versions/1"
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.dirname(HERE)

# variant -> (platform, kind, environment). The catalogue lives in tool/plan_build_variants.sh;
# test_build_manifest.sh fails if the two disagree.
VARIANTS = {
    "android-staging-apk": ("android", "apk", "staging"),
    "ios-staging": ("ios", "ios-app", "staging"),
    "android-production-apk": ("android", "apk", "production"),
    "android-production-aab": ("android", "aab", "production"),
    "ios-production": ("ios", "ios-app", "production"),
}
SIGNING = ("unsigned", "debug", "release")
CLASSIFICATIONS = ("compile-validation", "internal-evaluation", "release-candidate", "release")
KNOWN_ISSUES = (
    "application-id-differs-from-published-app",
    "version-code-not-above-published-floor",
)
GATE_STATUS = ("blocked-not-above-floor", "above-floor", "no-published-record", "not-applicable")
DIGEST_KINDS = ("file", "directory-manifest")
REQUIRED_TOOLCHAIN = {
    "android": ("flutter", "dart", "java", "runner_image", "android_build_tools"),
    "ios": ("flutter", "dart", "xcode", "iphoneos_sdk", "cocoapods", "runner_image"),
}
EXTENSION = {"apk": ".apk", "aab": ".aab", "ios-app": ".app"}
INTERNAL_PREFIX = "NON-DISTRIBUTABLE_INTERNAL-EVALUATION_"
MAX_ANDROID_VERSION_CODE = 2100000000  # Google Play's upper bound

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
NUM = r"(0|[1-9][0-9]*)"
PRODUCT = re.compile(r"^%s\.%s\.%s$" % (NUM, NUM, NUM))
PUBSPEC = re.compile(r"^(%s\.%s\.%s)\+([1-9][0-9]*)$" % (NUM, NUM, NUM))
RELEASE_ID = re.compile(r"^v(%s\.%s\.%s)(-rc\.[1-9][0-9]*)?$" % (NUM, NUM, NUM))
DIGITS = re.compile(r"^[1-9][0-9]*$")


class Problems:
    def __init__(self):
        self.items = []

    def add(self, text):
        self.items.append(text)

    def __bool__(self):
        return bool(self.items)


def die(text, code=2):
    print("build_manifest: %s" % text, file=sys.stderr)
    sys.exit(code)


# ---- inputs ---------------------------------------------------------------------------
def read_kv(path):
    """key=value lines; a repeated key is an error (ambiguous evidence)."""
    out = {}
    try:
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                line = line.rstrip("\n")
                if not line.strip():
                    continue
                if "=" not in line:
                    die("%s:%d is not key=value" % (path, n))
                k, v = line.split("=", 1)
                if k in out:
                    die("%s:%d repeats the key '%s'" % (path, n, k))
                out[k] = v
    except OSError as e:
        die("cannot read %s: %s" % (path, e))
    return out


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        die("cannot read %s: %s" % (path, e))


def load_pubspec(root):
    path = os.path.join(root, "pubspec.yaml")
    try:
        with open(path, encoding="utf-8") as f:
            lines = [ln for ln in f.read().split("\n") if ln.startswith("version:")]
    except OSError as e:
        die("cannot read %s: %s" % (path, e))
    if len(lines) != 1:
        die("pubspec.yaml must have exactly one top-level version: line (found %d)" % len(lines))
    raw = re.sub(r"\s*#.*$", "", lines[0][len("version:"):]).strip()
    m = PUBSPEC.match(raw)
    if not m:
        die("pubspec.yaml version '%s' is not X.Y.Z+BUILD" % raw)
    return raw, m.group(1), int(m.group(5))


def load_ledger(root):
    data = read_json(os.path.join(root, "config", "release", "published_versions.json"))
    if data.get("schema") != LEDGER_SCHEMA:
        die("published_versions.json: unexpected schema '%s'" % data.get("schema"))
    entries = data.get("entries")
    if not isinstance(entries, list):
        die("published_versions.json: 'entries' must be a list")
    for e in entries:
        for key in ("platform", "channel", "package", "version_name", "version_code"):
            if key not in e:
                die("published_versions.json: an entry lacks '%s'" % key)
        if not isinstance(e["version_code"], int) or e["version_code"] < 1:
            die("published_versions.json: version_code must be a positive integer")
    return entries


def floor_for(entries, platform):
    codes = [e["version_code"] for e in entries if e["platform"] == platform]
    return max(codes) if codes else None


def identity_differs(entries, platform, app_id):
    """True when the platform has a published package and app_id is not one of them: a release
    with this identity would not be an update of the published app."""
    packages = {e["package"] for e in entries if e["platform"] == platform}
    return bool(packages) and app_id not in packages


def identities(root):
    """Expected application ID and display name per environment: the single copy lives in
    tool/verify_artifact.sh; it is asked, not duplicated."""
    script = os.path.join(root, "tool", "verify_artifact.sh")
    try:
        out = subprocess.run(["bash", script, "matrix"], capture_output=True, text=True,
                             cwd=root, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as e:
        die("cannot read the identity matrix from %s: %s" % (script, e))
    result = {}
    for line in out.splitlines():
        m = re.match(r"^(staging|production)\s+(\S+)\s+'(.*)'$", line)
        if m:
            result[m.group(1)] = (m.group(2), m.group(3))
    if set(result) != {"staging", "production"}:
        die("the identity matrix of %s is unreadable: %r" % (script, out))
    return result


def sha256_file(path):
    import hashlib
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
    except OSError as e:
        die("cannot read %s: %s" % (path, e))
    return h.hexdigest()


# ---- derived facts (shared by create and verify, so they cannot drift apart) ----------------
def derive_gate(platform, environment, build, app_id, entries):
    """(release_gate, known_issues) as they follow from the repository's ledger."""
    issues = []
    if environment != "production":
        return {"status": "not-applicable", "published_floor": None}, issues
    floor = floor_for(entries, platform)
    if floor is None:
        return {"status": "no-published-record", "published_floor": None}, issues
    if build <= floor:
        status = "blocked-not-above-floor"
        if platform == "android":
            issues.append("version-code-not-above-published-floor")
    else:
        status = "above-floor"
    if platform == "android" and identity_differs(entries, platform, app_id):
        issues.append("application-id-differs-from-published-app")
    return {"status": status, "published_floor": floor}, sorted(issues)


def canonical_name(m, classification=None):
    v = m["version"]
    base = "cadena-signer-%s-%s+%s-%s-%s-%s-run%s.%s%s" % (
        m["environment"], v["name"], v["platform_build_number"], m["platform"], m["kind"],
        m["source"]["commit"][:7], m["ci"]["run_id"], m["ci"]["run_attempt"], EXTENSION[m["kind"]])
    if classification == "internal-evaluation":
        return INTERNAL_PREFIX + base
    if classification not in (None, "compile-validation"):
        die("no file name is defined for the classification '%s'" % classification)
    return base


# ---- create -----------------------------------------------------------------------------
def need(kv, key):
    if not kv.get(key):
        die("the evidence lacks '%s'" % key)
    return kv[key]


def cmd_create(args):
    opts = parse_opts(args, {"--evidence": 1, "--toolchain": 1, "--out": 1, "--repo": 1, "--release-id": 1})
    root = opts.get("--repo", DEFAULT_ROOT)
    ev = read_kv(need_opt(opts, "--evidence"))
    tc = read_kv(need_opt(opts, "--toolchain"))
    env = os.environ

    variant = need(ev, "variant")
    if variant not in VARIANTS:
        die("unknown variant '%s'" % variant)
    platform, kind, environment = VARIANTS[variant]
    run_id = env.get("GITHUB_RUN_ID", "")
    attempt = env.get("GITHUB_RUN_ATTEMPT", "")
    if not DIGITS.match(run_id) or not DIGITS.match(attempt):
        die("GITHUB_RUN_ID / GITHUB_RUN_ATTEMPT are missing or not positive integers")
    server = env.get("GITHUB_SERVER_URL", "")
    repo = env.get("GITHUB_REPOSITORY", "")
    commit = env.get("GITHUB_SHA", "")
    if not (server and repo and HEX40.match(commit)):
        die("GITHUB_SERVER_URL, GITHUB_REPOSITORY or GITHUB_SHA is missing or malformed")
    if commit != need(ev, "commit"):
        die("GITHUB_SHA differs from the evidence commit")

    pubspec, name, pub_build = load_pubspec(root)
    entries = load_ledger(root)
    build = need(ev, "version_code")
    if not DIGITS.match(build):
        die("version_code '%s' is not a positive integer" % build)
    app_id = need(ev, "application_id")
    gate, issues = derive_gate(platform, environment, int(build), app_id, entries)

    signing = need(ev, "signing")
    if signing not in ("unsigned", "debug"):
        die("signing '%s' cannot be recorded by a compile-validation build" % signing)
    basis = ev.get("artifact_sha256_basis")
    digest_kind = "directory-manifest" if kind == "ios-app" else "file"
    if kind == "ios-app" and not basis:
        die("the iOS evidence lacks artifact_sha256_basis")

    native = {}
    for k, v in sorted(ev.items()):
        if k.startswith("native_lib_sha256."):
            native["libdlcplazacryptlib.so/" + k.split(".", 1)[1]] = v
    if "rust_lib_sha256" in ev:
        native["libdlcplazacryptlib.a/ios"] = ev["rust_lib_sha256"]

    toolchain = {k: v for k, v in sorted(tc.items())}
    verification = {"environment_check": need(ev, "environment_check"),
                    "environment_check_snapshots": need(ev, "environment_check_snapshots")}
    if "podfile_lock_drift" in ev:
        verification["podfile_lock_drift"] = ev["podfile_lock_drift"]

    m = {
        "schema": SCHEMA,
        "variant": variant,
        "platform": platform,
        "kind": kind,
        "environment": environment,
        "classification": "compile-validation",
        "source": {
            "commit": commit,
            "ref": env.get("GITHUB_REF_NAME", ""),
            "ref_type": env.get("GITHUB_REF_TYPE", ""),
            "event": env.get("GITHUB_EVENT_NAME", ""),
            "release_id": opts.get("--release-id"),
        },
        "ci": {
            "repository": repo,
            "workflow": env.get("GITHUB_WORKFLOW", ""),
            "run_id": run_id,
            "run_attempt": int(attempt),
            "run_url": "%s/%s/actions/runs/%s" % (server, repo, run_id),
            "build_id": "%s.%s:%s" % (run_id, attempt, variant),
        },
        "version": {
            "pubspec": pubspec,
            "name": name,
            "pubspec_build": pub_build,
            "platform_version_name": need(ev, "version_name"),
            "platform_build_number": int(build),
        },
        "application": {"id": app_id, "display_name": need(ev, "display_name")},
        "configuration": {
            "file": need(ev, "config_file"),
            "sha256": need(ev, "config_file_sha256"),
            "build_command": need(ev, "build_command"),
        },
        "toolchain": toolchain,
        "native_libs": native,
        "artifact": {
            "file": need(ev, "artifact_file"),
            "canonical_name": "",
            "sha256": need(ev, "artifact_sha256"),
            "digest_kind": digest_kind,
            "digest_basis": basis or "sha256 of the raw file",
            "size": need(ev, "artifact_bytes"),
        },
        "signing": {
            "status": signing,
            "signer_dn": ev.get("signer_dn", ""),
            "signer_cert_sha256": ev.get("signer_cert_sha256", ""),
        },
        "distribution": {"distributable": False, "binary_retained": False},
        "verification": verification,
        "release_gate": gate,
        "known_issues": issues,
    }
    m["artifact"]["canonical_name"] = canonical_name(m)
    out = need_opt(opts, "--out")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(m, f, indent=2, sort_keys=False)
        f.write("\n")
    print("manifest written to %s (%s, %s)" % (out, variant, m["ci"]["build_id"]))


# ---- verify -----------------------------------------------------------------------------
def is_str(x):
    return isinstance(x, str) and x != ""


def check_shape(m, p):
    """Exactly the documented keys, with the documented types."""
    top = ("schema", "variant", "platform", "kind", "environment", "classification", "source", "ci",
           "version", "application", "configuration", "toolchain", "native_libs", "artifact",
           "signing", "distribution", "verification", "release_gate", "known_issues")
    sections = {
        "source": ("commit", "ref", "ref_type", "event", "release_id"),
        "ci": ("repository", "workflow", "run_id", "run_attempt", "run_url", "build_id"),
        "version": ("pubspec", "name", "pubspec_build", "platform_version_name", "platform_build_number"),
        "application": ("id", "display_name"),
        "configuration": ("file", "sha256", "build_command"),
        "artifact": ("file", "canonical_name", "sha256", "digest_kind", "digest_basis", "size"),
        "signing": ("status", "signer_dn", "signer_cert_sha256"),
        "distribution": ("distributable", "binary_retained"),
        "release_gate": ("status", "published_floor"),
    }
    for key in top:
        if key not in m:
            p.add("missing key '%s'" % key)
    for key in m:
        if key not in top:
            p.add("unknown key '%s'" % key)
    for name, keys in sections.items():
        sec = m.get(name)
        if not isinstance(sec, dict):
            if name in m:
                p.add("'%s' must be an object" % name)
            continue
        for key in keys:
            if key not in sec:
                p.add("missing key '%s.%s'" % (name, key))
        for key in sec:
            if key not in keys:
                p.add("unknown key '%s.%s'" % (name, key))
    return not p


def verify_manifest(m, root, evidence=None):
    p = Problems()
    if m.get("schema") != SCHEMA:
        p.add("schema is %r, expected %r" % (m.get("schema"), SCHEMA))
        return p
    if not check_shape(m, p):
        return p

    variant = m["variant"]
    if variant not in VARIANTS:
        p.add("unknown variant '%s'" % variant)
        return p
    platform, kind, environment = VARIANTS[variant]
    for key, want in (("platform", platform), ("kind", kind), ("environment", environment)):
        if m[key] != want:
            p.add("%s is '%s' but the variant %s is %s" % (key, m[key], variant, want))

    src, ci, ver, app = m["source"], m["ci"], m["version"], m["application"]
    cfg, art, sig = m["configuration"], m["artifact"], m["signing"]
    dist, gate = m["distribution"], m["release_gate"]

    # -- source ---------------------------------------------------------------------------
    if not (is_str(src["commit"]) and HEX40.match(src["commit"])):
        p.add("source.commit must be a full 40-character lowercase SHA")
    if not is_str(src["ref"]):
        p.add("source.ref is missing")
    if src["ref_type"] not in ("branch", "tag"):
        p.add("source.ref_type must be 'branch' or 'tag'")
    if src["event"] not in ("push", "workflow_dispatch"):
        p.add("source.event must be 'push' or 'workflow_dispatch'")
    if src["event"] == "push":
        # A promotion push builds only the variants of its own branch's environment.
        if src["ref_type"] != "branch" or src["ref"] != environment:
            p.add("a push to '%s' (%s) cannot build the %s environment" % (src["ref"], src["ref_type"], environment))
    rid = src["release_id"]
    if rid is not None:
        mm = RELEASE_ID.match(rid) if is_str(rid) else None
        if not mm:
            p.add("source.release_id '%s' is not vX.Y.Z or vX.Y.Z-rc.N" % rid)
        else:
            if mm.group(1) != ver["name"]:
                p.add("release_id %s does not match the product version %s" % (rid, ver["name"]))
            if environment == "staging" and not mm.group(5):
                p.add("a staging release identifier must be vX.Y.Z-rc.N, got %s" % rid)
            if environment == "production" and mm.group(5):
                p.add("a production release identifier must not carry -rc.N, got %s" % rid)

    # -- CI build identity -------------------------------------------------------------------
    rid_s, attempt = ci["run_id"], ci["run_attempt"]
    if not (is_str(rid_s) and DIGITS.match(rid_s)):
        p.add("ci.run_id must be a positive integer string")
    if not (isinstance(attempt, int) and not isinstance(attempt, bool) and attempt >= 1):
        p.add("ci.run_attempt must be an integer >= 1")
    if is_str(ci["repository"]) and is_str(rid_s):
        if not re.match(r"^https://[^/]+/%s/actions/runs/%s$" % (re.escape(ci["repository"]), re.escape(rid_s)), str(ci["run_url"])):
            p.add("ci.run_url does not name run %s of %s" % (rid_s, ci["repository"]))
    if ci["build_id"] != "%s.%s:%s" % (rid_s, attempt, variant):
        p.add("ci.build_id '%s' is not <run>.<attempt>:<variant>" % ci["build_id"])

    # -- version -------------------------------------------------------------------------
    pm = PUBSPEC.match(ver["pubspec"]) if is_str(ver["pubspec"]) else None
    if not pm:
        p.add("version.pubspec '%s' is not X.Y.Z+BUILD" % ver["pubspec"])
    else:
        if pm.group(1) != ver["name"]:
            p.add("version.name %s differs from pubspec %s" % (ver["name"], ver["pubspec"]))
        if int(pm.group(5)) != ver["pubspec_build"]:
            p.add("version.pubspec_build %s differs from pubspec %s" % (ver["pubspec_build"], ver["pubspec"]))
    if not (is_str(ver["name"]) and PRODUCT.match(ver["name"])):
        p.add("version.name '%s' is not X.Y.Z" % ver["name"])
    if ver["platform_version_name"] != ver["name"]:
        # Policy 7.2 will allow X.Y.Z-rc.N on Android staging; the checker is then changed
        # together with that wiring, not loosened ahead of time.
        p.add("the %s version name '%s' differs from the product version %s" % (platform, ver["platform_version_name"], ver["name"]))
    pb = ver["platform_build_number"]
    if not (isinstance(pb, int) and not isinstance(pb, bool) and pb >= 1):
        p.add("version.platform_build_number must be a positive integer")
    else:
        if pb != ver["pubspec_build"]:
            p.add("the %s build number %s differs from the pubspec build %s (no platform override is defined)" % (platform, pb, ver["pubspec_build"]))
        if platform == "android" and pb > MAX_ANDROID_VERSION_CODE:
            p.add("versionCode %s exceeds Google Play's limit %s" % (pb, MAX_ANDROID_VERSION_CODE))

    # -- application identity and configuration -------------------------------------------------
    ident = identities(root or DEFAULT_ROOT)
    want_id, want_name = ident[environment]
    if app["id"] != want_id:
        p.add("application.id '%s' is not the %s identity %s" % (app["id"], environment, want_id))
    if app["display_name"] != want_name:
        p.add("application.display_name '%s' is not '%s'" % (app["display_name"], want_name))
    if cfg["file"] != "config/build/%s.json" % environment:
        p.add("configuration.file '%s' is not the %s configuration" % (cfg["file"], environment))
    if not (is_str(cfg["sha256"]) and HEX64.match(cfg["sha256"])):
        p.add("configuration.sha256 must be 64 lowercase hex digits")
    if is_str(cfg["build_command"]):
        if "--flavor %s" % environment not in cfg["build_command"] or "--dart-define-from-file=%s" % cfg["file"] not in cfg["build_command"]:
            p.add("configuration.build_command does not use the %s flavor and configuration file" % environment)
        if "--build-name" in cfg["build_command"] or "--build-number" in cfg["build_command"]:
            p.add("configuration.build_command overrides the version")
    else:
        p.add("configuration.build_command is missing")

    # -- toolchain and native libraries ----------------------------------------------------------
    tc = m["toolchain"]
    if not isinstance(tc, dict):
        p.add("toolchain must be an object")
    else:
        for key in REQUIRED_TOOLCHAIN.get(platform, ()):
            if not is_str(tc.get(key)) or "unknown" in tc.get(key):
                p.add("toolchain.%s is missing or unknown" % key)
    nl = m["native_libs"]
    if not isinstance(nl, dict) or not nl:
        p.add("native_libs is empty: the provenance of the committed Rust library is not recorded")
    else:
        for key, val in nl.items():
            if not (is_str(val) and HEX64.match(val)):
                p.add("native_libs['%s'] is not a SHA-256" % key)

    # -- artifact ----------------------------------------------------------------------------
    if not (is_str(art["sha256"]) and HEX64.match(art["sha256"])):
        p.add("artifact.sha256 must be 64 lowercase hex digits")
    want_digest = "directory-manifest" if kind == "ios-app" else "file"
    if art["digest_kind"] != want_digest:
        p.add("artifact.digest_kind is '%s'; a %s artifact has a %s digest" % (art["digest_kind"], kind, want_digest))
    if art["digest_kind"] not in DIGEST_KINDS:
        p.add("artifact.digest_kind '%s' is unknown" % art["digest_kind"])
    for key in ("file", "digest_basis", "size"):
        if not is_str(art[key]):
            p.add("artifact.%s is missing" % key)
    try:
        if art["canonical_name"] != canonical_name(m):
            p.add("artifact.canonical_name '%s' is not the canonical name %s" % (art["canonical_name"], canonical_name(m)))
    except (KeyError, TypeError):
        p.add("artifact.canonical_name cannot be recomputed")

    # -- signing, classification, distribution: no contradiction --------------------------------
    status = sig["status"]
    if status not in SIGNING:
        p.add("signing.status '%s' is not one of %s" % (status, ", ".join(SIGNING)))
    if platform == "ios" and status != "unsigned":
        p.add("an iOS compile-validation artifact must be unsigned, not '%s'" % status)
    if status == "debug":
        if not (is_str(sig["signer_dn"]) and "CN=Android Debug" in sig["signer_dn"]):
            p.add("signing.status is 'debug' but the signer is not the Android debug certificate")
        if not (is_str(sig["signer_cert_sha256"]) and HEX64.match(sig["signer_cert_sha256"])):
            p.add("a debug-signed artifact must record the signer certificate SHA-256")
    if status == "unsigned" and (sig["signer_dn"] or sig["signer_cert_sha256"]):
        p.add("signing.status is 'unsigned' but a signer is recorded")
    if status == "release":
        if not (is_str(sig["signer_cert_sha256"]) and HEX64.match(sig["signer_cert_sha256"])):
            p.add("a release-signed artifact must record the signing certificate SHA-256")
        if not src["release_id"]:
            p.add("a release-signed artifact needs a release identifier")
    cls = m["classification"]
    if cls not in CLASSIFICATIONS:
        p.add("classification '%s' is unknown" % cls)
    if status in ("unsigned", "debug") and cls not in ("compile-validation", "internal-evaluation"):
        p.add("a %s artifact cannot be classified '%s'" % (status, cls))
    if dist["distributable"] is not False and status != "release":
        p.add("distribution.distributable must be false unless the artifact is release-signed")
    if dist["distributable"] is True and cls != "release":
        p.add("only a 'release' classified artifact can be distributable")
    if dist["binary_retained"] is True and cls not in ("internal-evaluation", "release-candidate", "release"):
        p.add("a retained binary needs the classification internal-evaluation, release-candidate or release")
    for key in ("distributable", "binary_retained"):
        if not isinstance(dist[key], bool):
            p.add("distribution.%s must be true or false" % key)

    # -- release gate and known issues ------------------------------------------------------------
    if gate["status"] not in GATE_STATUS:
        p.add("release_gate.status '%s' is unknown" % gate["status"])
    for issue in m["known_issues"] if isinstance(m["known_issues"], list) else [None]:
        if issue not in KNOWN_ISSUES:
            p.add("known_issues contains '%s'" % issue)
    if not isinstance(m["known_issues"], list):
        p.add("known_issues must be a list")

    # -- a release cannot be claimed while the published-version protections are open -----------------
    # (the gate and the known issues are recomputed from the ledger when --repo is given; a
    # manifest that is trusted without --repo only has its own word for them)
    claims_release = cls in ("release-candidate", "release") or status == "release" or dist["distributable"] is True
    if claims_release:
        if gate["status"] == "blocked-not-above-floor":
            p.add("a release is claimed but the build number is not above the published floor %s" % gate["published_floor"])
        if isinstance(m["known_issues"], list) and m["known_issues"]:
            p.add("a release is claimed while known issues are open: %s" % ", ".join(str(i) for i in m["known_issues"]))

    # -- what the repository at this commit says -----------------------------------------------------
    if root is not None and not p:
        ppub, pname, pbuild = load_pubspec(root)
        if ppub != ver["pubspec"]:
            p.add("the manifest says pubspec %s, the repository says %s" % (ver["pubspec"], ppub))
        cfile = os.path.join(root, cfg["file"])
        if not os.path.isfile(cfile):
            p.add("configuration file %s does not exist in the repository" % cfg["file"])
        elif sha256_file(cfile) != cfg["sha256"]:
            p.add("configuration file %s changed since the manifest was written" % cfg["file"])
        want_gate, want_issues = derive_gate(platform, environment, pb, app["id"], load_ledger(root))
        if gate != want_gate:
            p.add("release_gate %s differs from the ledger-derived %s" % (gate, want_gate))
        if m["known_issues"] != want_issues:
            p.add("known_issues %s differ from the ledger-derived %s (an issue cannot be dropped)" % (m["known_issues"], want_issues))

    # -- the text evidence says the same ----------------------------------------------------------
    if evidence is not None and not p:
        pairs = (("variant", variant), ("commit", src["commit"]), ("config_file_sha256", cfg["sha256"]),
                 ("artifact_sha256", art["sha256"]), ("artifact_file", art["file"]),
                 ("application_id", app["id"]), ("display_name", app["display_name"]),
                 ("version_name", ver["platform_version_name"]), ("version_code", str(pb)),
                 ("signing", status), ("environment", environment))
        for key, got in pairs:
            if evidence.get(key) != got:
                p.add("the text evidence says %s=%r, the manifest %r" % (key, evidence.get(key), got))
        run_line = evidence.get("run", "")
        if run_line != "%s (attempt %s)" % (ci["run_url"], attempt):
            p.add("the text evidence run line %r differs from the manifest" % run_line)
    return p


def crosscheck(manifests):
    """Consistency of the manifests of ONE run: one release identity, unique build identifiers."""
    p = Problems()
    if not manifests:
        p.add("no manifest")
        return p
    for key in (("source", "commit"), ("source", "ref"), ("source", "event"), ("ci", "run_id"),
                ("ci", "run_attempt"), ("ci", "repository"), ("version", "pubspec"),
                ("source", "release_id")):
        values = {json.dumps(m[key[0]][key[1]]) for m in manifests}
        if len(values) != 1:
            p.add("the manifests of one run disagree on %s.%s: %s" % (key[0], key[1], ", ".join(sorted(values))))
    for label, getter in (("variant", lambda m: m["variant"]), ("ci.build_id", lambda m: m["ci"]["build_id"]),
                          ("canonical file name", lambda m: m["artifact"]["canonical_name"]),
                          ("artifact SHA-256", lambda m: m["artifact"]["sha256"])):
        seen = {}
        for m in manifests:
            v = getter(m)
            if v in seen:
                p.add("%s '%s' is not unique (%s and %s)" % (label, v, seen[v], m["variant"]))
            seen[v] = m["variant"]
    # One update family: the production APK and AAB are the same application release.
    by = {m["variant"]: m for m in manifests}
    a, b = by.get("android-production-apk"), by.get("android-production-aab")
    if a and b:
        for sec, key in (("application", "id"), ("application", "display_name"), ("version", "platform_version_name"),
                         ("version", "platform_build_number"), ("signing", "status")):
            if a[sec][key] != b[sec][key]:
                p.add("the production APK and AAB differ in %s.%s (%s vs %s)" % (sec, key, a[sec][key], b[sec][key]))
    # Staging and production are different applications on each platform.
    for platform in ("android", "ios"):
        ids = {}
        for m in manifests:
            if m["platform"] == platform:
                ids.setdefault(m["environment"], set()).add(m["application"]["id"])
        if set(ids) == {"staging", "production"} and ids["staging"] & ids["production"]:
            p.add("staging and production share an application identity on %s" % platform)
    return p


def cmd_verify(args):
    opts = parse_opts(args, {"--repo": 1, "--evidence": 1}, positional=1)
    m = read_json(opts["_"][0])
    ev = read_kv(opts["--evidence"]) if "--evidence" in opts else None
    # Without --repo nothing is recomputed from the repository (the identity matrix still comes
    # from the repository that holds this tool).
    return report(opts["_"][0], verify_manifest(m, opts.get("--repo"), ev))


def parse_opts(args, spec, positional=0):
    """spec: option -> 1 (takes a value). Returns the options plus the positional arguments in '_'."""
    opts = {"_": []}
    i = 0
    while i < len(args):
        a = args[i]
        if a in spec:
            if i + 1 >= len(args):
                die("%s needs a value" % a)
            opts[a] = args[i + 1]
            i += 2
        elif a.startswith("--"):
            die("unknown option '%s'" % a)
        else:
            opts["_"].append(a)
            i += 1
    if len(opts["_"]) != positional:
        die("expected %d positional argument(s), got %d" % (positional, len(opts["_"])))
    return opts


def need_opt(opts, name):
    if name not in opts:
        die("%s is required" % name)
    return opts[name]


def report(label, problems):
    if problems:
        for text in problems.items:
            print("  FAIL  %s" % text)
        print("RESULT: FAILED (%d) %s" % (len(problems.items), label))
        return 1
    print("RESULT: OK %s" % label)
    return 0


def cmd_verify_dir(args):
    opts = parse_opts(args, {"--variants": 1, "--repo": 1}, positional=1)
    directory = opts["_"][0]
    variants = need_opt(opts, "--variants").split()
    root = opts.get("--repo")
    manifests, rc = [], 0
    for v in variants:
        mpath = os.path.join(directory, v + ".manifest.json")
        tpath = os.path.join(directory, v + ".txt")
        if not os.path.isfile(mpath) or not os.path.isfile(tpath):
            print("  FAIL  %s: manifest or text evidence is missing" % v)
            rc = 1
            continue
        m = read_json(mpath)
        p = verify_manifest(m, root, read_kv(tpath))
        if m.get("variant") != v:
            p.add("the file %s.manifest.json describes variant %r" % (v, m.get("variant")))
        rc |= report(v, p)
        if not p:
            manifests.append(m)
    if rc == 0:
        rc |= report("cross-checks of %d manifest(s)" % len(manifests), crosscheck(manifests))
    return rc


def tree_digest(directory):
    """SHA-256 of the sorted "<sha256>  ./<relative path>" manifest of every regular file, exactly
    as tool/verify_artifact.sh computes it for a Runner.app (symlinks are not followed)."""
    import hashlib
    paths = []
    for base, dirs, files in os.walk(directory, followlinks=False):
        for name in files:
            full = os.path.join(base, name)
            if os.path.isfile(full) and not os.path.islink(full):
                paths.append("./" + os.path.relpath(full, directory).replace(os.sep, "/"))
    lines = "".join("%s  %s\n" % (sha256_file(os.path.join(directory, rel[2:])), rel)
                    for rel in sorted(paths, key=lambda r: r.encode("utf-8")))
    return hashlib.sha256(lines.encode("utf-8")).hexdigest()


def cmd_check_file(args):
    """Does this file match its manifest? Recomputes the digest and size of the file you hold and
    prints what the manifest CLAIMS about it. A match proves the file is the one the manifest
    describes; it does not prove who wrote the manifest or that the claims are true."""
    opts = parse_opts(args, {}, positional=2)
    manifest, target = opts["_"]
    m = read_json(manifest)
    p = Problems()
    if m.get("schema") != SCHEMA or not isinstance(m.get("artifact"), dict):
        die("%s is not a %s manifest" % (manifest, SCHEMA))
    art = m["artifact"]
    if art.get("digest_kind") == "directory-manifest":
        if not os.path.isdir(target):
            p.add("the manifest describes a directory (%s); %s is not one" % (art.get("digest_basis"), target))
            got = None
        else:
            got = tree_digest(target)
    else:
        if not os.path.isfile(target):
            p.add("%s is not a file" % target)
            got = None
        else:
            got = sha256_file(target)
            if str(os.path.getsize(target)) != str(art.get("size")):
                p.add("the file is %d bytes, the manifest says %s" % (os.path.getsize(target), art.get("size")))
    if got is not None and got != art.get("sha256"):
        p.add("SHA-256 mismatch: the file is %s, the manifest says %s" % (got, art.get("sha256")))
    base = os.path.basename(target.rstrip("/"))
    names = (art.get("file"), art.get("canonical_name"), INTERNAL_PREFIX + str(art.get("canonical_name")))
    if base not in names:
        print("  NOTE  the file name '%s' is none of the recorded names (a renamed file is still decided by its digest)" % base)
    if not p:
        v, a, s_, c, ci = m["version"], m["application"], m["signing"], m["configuration"], m["ci"]
        print("  PASS  SHA-256 %s (%s)" % (got, art["digest_kind"]))
        print("CLAIMED by the manifest (recorded build provenance, not authenticated):")
        print("  variant        %s  (%s, %s)" % (m["variant"], m["platform"], m["environment"]))
        print("  application    %s \"%s\"" % (a["id"], a["display_name"]))
        print("  version        %s  build %s  (pubspec %s)" % (v["name"], v["platform_build_number"], v["pubspec"]))
        print("  source commit  %s  (ref %s, %s)" % (m["source"]["commit"], m["source"]["ref"], m["source"]["event"]))
        print("  CI execution   %s" % ci["run_url"])
        print("  CI build id    %s  (attempt %s)" % (ci["build_id"], ci["run_attempt"]))
        print("  configuration  %s  sha256 %s" % (c["file"], c["sha256"]))
        print("  signing        %s%s" % (s_["status"], ("  cert " + s_["signer_cert_sha256"]) if s_["signer_cert_sha256"] else ""))
        print("  classification %s  distributable=%s" % (m["classification"], m["distribution"]["distributable"]))
        if m.get("known_issues"):
            print("  known issues   %s" % ", ".join(m["known_issues"]))
    return report(target, p)


def cmd_name(args):
    opts = parse_opts(args, {"--classification": 1}, positional=1)
    m = read_json(opts["_"][0])
    print(canonical_name(m, opts.get("--classification")))
    return 0


def cmd_gate(args):
    """The production release gate has two independent rules: a release build must have a build
    number above every published one, and its Android application ID must be the published
    package (otherwise the build is not an update of the published app; #72). Either rule fails
    the gate, whatever the other says. Not part of a compile-validation build (which may equal the
    published number); the signed release pipeline (#72) must run it and fail on a non-zero status."""
    opts = parse_opts(args, {"--channel": 1, "--repo": 1})
    channel = need_opt(opts, "--channel")
    if channel not in ("staging", "production"):
        die("--channel must be staging or production")
    root = opts.get("--repo", DEFAULT_ROOT)
    pub, _name, build = load_pubspec(root)
    if channel == "staging":
        print("PASS  staging: no published record applies (staging is a separate application)")
        return 0
    entries = load_ledger(root)
    app_id = identities(root)["production"][0]
    bad = 0
    for platform in ("android", "ios"):
        floor = floor_for(entries, platform)
        if floor is None:
            print("PASS  %s: no published build number is recorded, no floor is enforced" % platform)
        elif build > floor:
            print("PASS  %s: build %d is above the published floor %d" % (platform, build, floor))
        else:
            print("FAIL  %s: build %d is not above the published build number %d (pubspec %s)" % (platform, build, floor, pub))
            bad += 1
    if identity_differs(entries, "android", app_id):
        published = ", ".join(sorted({e["package"] for e in entries if e["platform"] == "android"}))
        print("FAIL  android: the production application ID %s is not the published package %s" % (app_id, published))
        bad += 1
    else:
        print("PASS  android: the production application ID matches the published package (or none is recorded)")
    print("RESULT: %s" % ("FAILED (%d)" % bad if bad else "OK"))
    return 1 if bad else 0


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 2
    cmd, args = argv[1], argv[2:]
    table = {"create": cmd_create, "verify": cmd_verify, "verify-dir": cmd_verify_dir,
             "name": cmd_name, "gate": cmd_gate, "check-file": cmd_check_file}
    if cmd not in table:
        die("unknown command '%s'" % cmd)
    return table[cmd](args) or 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
