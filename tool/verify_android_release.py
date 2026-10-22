#!/usr/bin/env python3
"""Independent verification of Android release artifacts, and the release report (Issue #72).

  tool/verify_android_release.py apk  ENV FILE.apk --expect-cert-sha256 FP        [options]
  tool/verify_android_release.py apk  ENV FILE.apk --signing play                 [options]
  tool/verify_android_release.py aab  ENV FILE.aab --expect-cert-sha256 FP        [options]
  tool/verify_android_release.py pair ENV FILE.apk FILE.aab --expect-cert-sha256 FP [options]
  tool/verify_android_release.py release ENV --apk FILE.apk --aab FILE.aab --expect-cert-sha256 FP
                                 --identity-label TEXT --out DIR                  [options]

It reads the artifact as a stranger would and trusts nothing the build says about it:

  identity      application ID, display name, versionName and versionCode are the ones ENV and
                pubspec.yaml require (tool/verify_artifact.sh matrix is the single copy of the IDs);
                every content-provider authority starts with the application ID; the app is not
                debuggable, forbids cleartext traffic and does not allow backups; targetSdk meets
                Google Play's requirement (--min-target-sdk, default 36);
  signature     APK: apksigner verifies it, with APK Signature Scheme v2 and v3, one signer; AAB:
                jarsigner verifies every entry and there is one signer. The signer's certificate
                SHA-256 fingerprint must equal the one that was expected. Debug certificates and the
                fingerprints in config/release/android_signing.json "do_not_use" are always refused;
  class         the signer is classified: `release-local` (the expected, Cadena-controlled upload
                identity), `play-signed` (the Google Play app-signing certificate of the ledger),
                `debug` or `unknown`. A locally signed APK is NOT a Google Play-signed APK: it carries
                another certificate and therefore cannot update an installation that came from Play;
  native        the Rust libraries (libdlcplazacryptlib.so and the libsecp256k1_zkp it loads) of every
                ABI are present and byte-identical to config/release/native_libs.json, libflutter.so
                and libapp.so exist, no other ABI is shipped, and every 64-bit library is 16 KB
                page aligned (ELF segments); an APK is also zip-aligned for 16 KB pages (zipalign);
  provenance    `release`: SHA-256 and size of each artifact, the commit, a clean tracked tree, the
                configuration, the ledgers, the toolchain and the production gate, written to
                release-report.json, release-report.md and SHA256SUMS.

A verified artifact is NOT authorization to publish. The report always says `distributable: false`:
delivery to the website or upload to Google Play is a separate, explicitly authorized step.

Nothing here reads a private key or a password. Exit 0: every check passed (and, for `release`, the
release is ready). Exit 1: a check failed. Exit 2: usage error or unreadable input.

WHAT THIS CANNOT PROVE: that Google Play accepts the upload (only an upload shows that), what Google
signs the delivered APKs with (only Play Console says so), or anything about a device.
"""
import argparse
import datetime
import hashlib
import json
import os
import platform
import re
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

sys.dont_write_bytecode = True  # importing the tool/ modules must not leave __pycache__ in the repository
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_manifest as BM  # noqa: E402

SCHEMA = "cadena-android-release-report/1"
PAGE_16K = 16384
GOOGLE_VALIDITY_END = datetime.date(2033, 10, 22)  # Play requires signing certificates to be valid beyond this day
ABI_64 = ("arm64-v8a", "x86_64")
EXPECTED_ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")
ALWAYS_PRESENT = ("libflutter.so", "libapp.so")
A = "{http://schemas.android.com/apk/res/android}"


class Usage(Exception):
    pass


class Report:
    def __init__(self, title):
        self.title = title
        self.lines = []      # (status, text)
        self.evidence = {}
        self.failures = 0

    def ok(self, text):
        self.lines.append(("PASS", text))

    def fail(self, text):
        self.lines.append(("FAIL", text))
        self.failures += 1

    def check(self, cond, ok_text, fail_text):
        (self.ok if cond else self.fail)(ok_text if cond else fail_text)
        return bool(cond)

    def note(self, text):
        self.lines.append(("NOTE", text))

    def ev(self, key, value):
        self.evidence[key] = value

    def print(self):
        print(self.title)
        for status, text in self.lines:
            print("  %-4s  %s" % (status, text))


# ---- small helpers ------------------------------------------------------------------------
def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha256_path(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def norm_fp(text):
    """A SHA-256 fingerprint as 64 lower-case hex digits, or None (colons and case are accepted)."""
    if not isinstance(text, str):
        return None
    t = text.strip().replace(":", "").lower()
    return t if re.fullmatch(r"[0-9a-f]{64}", t) else None


def colon(fp):
    return ":".join(fp[i:i + 2] for i in range(0, 64, 2)).upper()


def run(cmd, timeout=600):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, errors="replace")
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, "%s: %s" % (cmd[0], e)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def sdk_roots(repo):
    roots = [os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT")]
    lp = os.path.join(repo, "android", "local.properties")
    if os.path.isfile(lp):
        with open(lp, errors="replace") as f:
            for line in f:
                if line.startswith("sdk.dir="):
                    roots.append(line.split("=", 1)[1].strip())
    return [r for r in roots if r and os.path.isdir(r)]


def find_tool(name, repo):
    """A build-tools program: PATH first, then the newest build-tools directory of the SDK."""
    for d in os.environ.get("PATH", "").split(os.pathsep):
        p = os.path.join(d, name)
        if d and os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    best = None
    for root in sdk_roots(repo):
        bt = os.path.join(root, "build-tools")
        if not os.path.isdir(bt):
            continue
        for v in os.listdir(bt):
            p = os.path.join(bt, v, name)
            if os.path.isfile(p) and os.access(p, os.X_OK):
                key = tuple(int(x) if x.isdigit() else 0 for x in re.split(r"[.\-]", v))
                if best is None or key > best[0]:
                    best = (key, p)
    return best[1] if best else None


def bundletool_cmd():
    jar = os.environ.get("BUNDLETOOL_JAR")
    if jar and os.path.isfile(jar):
        return ["java", "-jar", jar]
    return None


def load_ledgers(repo):
    signing = BM.read_json(os.path.join(repo, "config", "release", "android_signing.json"))
    native = BM.read_json(os.path.join(repo, "config", "release", "native_libs.json"))
    if signing.get("schema") != "cadena-android-signing/1":
        raise Usage("android_signing.json: unexpected schema %r" % signing.get("schema"))
    if native.get("schema") != "cadena-native-libs/1":
        raise Usage("native_libs.json: unexpected schema %r" % native.get("schema"))
    return signing, native


# ---- ELF: 16 KB page alignment --------------------------------------------------------------
def elf_info(data):
    """(bits, minimum PT_LOAD alignment) of an ELF shared object, or None when it is not a well-formed ELF."""
    if len(data) < 64 or data[:4] != b"\x7fELF" or data[5] not in (1, 2):
        return None
    bits = 32 if data[4] == 1 else 64 if data[4] == 2 else None
    if bits is None:
        return None
    e = "<" if data[5] == 1 else ">"
    try:
        if bits == 64:
            phoff, = struct.unpack_from(e + "Q", data, 32)
            phentsize, phnum = struct.unpack_from(e + "HH", data, 54)
            align_off, fmt = 48, "Q"
        else:
            phoff, = struct.unpack_from(e + "I", data, 28)
            phentsize, phnum = struct.unpack_from(e + "HH", data, 42)
            align_off, fmt = 28, "I"
        aligns = []
        for i in range(phnum):
            base = phoff + i * phentsize
            if base + phentsize > len(data):
                return None
            ptype, = struct.unpack_from(e + "I", data, base)
            if ptype == 1:  # PT_LOAD
                aligns.append(struct.unpack_from(e + fmt, data, base + align_off)[0])
        return bits, (min(aligns) if aligns else 0)
    except struct.error:
        return None


# ---- native libraries -------------------------------------------------------------------------
def native_entries(zf, prefix):
    """{abi: {file name: bytes}} for the .so files under PREFIX/<abi>/ of an archive."""
    libs = {}
    for info in zf.infolist():
        n = info.filename
        if not n.startswith(prefix) or info.is_dir():
            continue
        parts = n[len(prefix):].split("/")
        if len(parts) == 2 and parts[1].endswith(".so"):
            libs.setdefault(parts[0], {})[parts[1]] = zf.read(info)
    return libs


def check_native(rep, libs, native_ledger, kind):
    expected = native_ledger["abis"]
    found_abis = tuple(sorted(libs))
    rep.check(found_abis == tuple(sorted(EXPECTED_ABIS)),
              "%s ships exactly the ABIs %s" % (kind, ", ".join(sorted(EXPECTED_ABIS))),
              "%s ships the ABIs [%s], expected exactly [%s]" % (kind, ", ".join(found_abis), ", ".join(sorted(EXPECTED_ABIS))))
    hashes = {}
    for abi in EXPECTED_ABIS:
        have = libs.get(abi, {})
        for name in ALWAYS_PRESENT:
            rep.check(name in have, "%s/%s is present" % (abi, name), "%s/%s is MISSING" % (abi, name))
        for name, want in sorted(expected.get(abi, {}).items()):
            data = have.get(name)
            if data is None:
                rep.fail("%s/%s (Rust cryptographic library input) is MISSING" % (abi, name))
                continue
            got = sha256_bytes(data)
            hashes["%s/%s" % (abi, name)] = got
            rep.check(got == want, "%s/%s is byte-identical to config/release/native_libs.json (%s...)" % (abi, name, got[:12]),
                      "%s/%s differs from config/release/native_libs.json: %s, ledger %s" % (abi, name, got, want))
        for name in sorted(have):
            if name not in ALWAYS_PRESENT and name not in expected.get(abi, {}):
                pass  # third-party libraries are not pinned here; they are alignment-checked below
    # 16 KB page alignment of every shared library of the 64-bit ABIs (Google Play requirement)
    misaligned = []
    unreadable = []
    for abi in ABI_64:
        for name, data in sorted(libs.get(abi, {}).items()):
            info = elf_info(data)
            if info is None:
                unreadable.append("%s/%s" % (abi, name))
            elif info[1] < PAGE_16K:
                misaligned.append("%s/%s (p_align %d)" % (abi, name, info[1]))
    rep.check(not unreadable, "every 64-bit library is a well-formed ELF", "not a well-formed ELF: %s" % ", ".join(unreadable))
    rep.check(not misaligned, "every 64-bit library (arm64-v8a, x86_64) is 16 KB page aligned (ELF segments)",
              "NOT 16 KB aligned: %s" % ", ".join(misaligned))
    n32 = sum(len(v) for k, v in libs.items() if k not in ABI_64)
    rep.note("32-bit libraries (%d) are not subject to the 16 KB requirement and are not checked" % n32)
    return hashes


# ---- identity from the repository ------------------------------------------------------------
def expected_identity(repo, env):
    ids = BM.identities(repo, "android")
    _raw, name, build = BM.load_pubspec(repo)
    return ids[env][0], ids[env][1], name, str(build)


def check_identity(rep, repo, env, app_id, label, vname, vcode, debuggable, min_target, target_sdk, kind):
    want_id, want_label, want_name, want_code = expected_identity(repo, env)
    rep.check(app_id == want_id, "application ID is %s" % app_id, "application ID is '%s', the %s ID is %s" % (app_id, env, want_id))
    rep.check(label == want_label, "display name is '%s'" % label, "display name is '%s', expected '%s'" % (label, want_label))
    rep.check(vname == want_name, "versionName %s matches pubspec.yaml" % vname, "versionName '%s' != pubspec %s" % (vname, want_name))
    rep.check(vcode == want_code, "versionCode %s matches pubspec.yaml" % vcode, "versionCode '%s' != pubspec %s" % (vcode, want_code))
    rep.check(not debuggable, "the application is not debuggable", "the application is marked debuggable")
    if target_sdk is not None:
        rep.check(target_sdk >= min_target, "targetSdk %d meets Google Play's requirement (>= %d)" % (target_sdk, min_target),
                  "targetSdk %d is below %d, which Google Play requires" % (target_sdk, min_target))
    rep.ev("application_id", app_id)
    rep.ev("display_name", label)
    rep.ev("version_name", vname)
    rep.ev("version_code", vcode)


def classify(fp, signing_ledger, expected_fp, dn):
    if dn and "CN=Android Debug" in dn:
        return "debug"
    if expected_fp and fp == expected_fp:
        return "release-local"
    if fp == norm_fp(signing_ledger["play_app_signing"]["sha256"]):
        return "play-signed"
    return "unknown"


def check_signer(rep, signer_fp, dn, mode, expected_fp, signing_ledger, repo_has_ledger_upload):
    """The signer's identity against what was expected. mode: release | play."""
    play_fp = norm_fp(signing_ledger["play_app_signing"]["sha256"])
    banned = {norm_fp(x["sha256"]): x for x in signing_ledger["upload"].get("do_not_use", [])}
    cls = classify(signer_fp, signing_ledger, expected_fp if mode == "release" else None, dn)
    rep.ev("signer_sha256", colon(signer_fp))
    rep.ev("signer_dn", dn or "")
    rep.ev("signing_class", cls)
    rep.check(cls != "debug", "the signer is not a debug certificate", "the artifact is signed with a DEBUG certificate: it is not a release")
    rep.check(signer_fp not in banned, "the signer is not an identity the ledger forbids",
              "the signer %s is an identity the ledger forbids (%s)" % (colon(signer_fp), banned.get(signer_fp, {}).get("reason", "")))
    if mode == "play":
        rep.check(signer_fp == play_fp, "Google Play-signed: the signer is the Play app-signing certificate of the ledger (%s...)" % colon(signer_fp)[:23],
                  "NOT Google Play-signed: the signer is %s, the ledger's Play app-signing certificate is %s" % (colon(signer_fp), colon(play_fp)))
    else:
        rep.check(signer_fp == expected_fp, "locally signed with the expected upload identity (%s...)" % colon(signer_fp)[:23],
                  "the signer is %s, the expected certificate is %s" % (colon(signer_fp), colon(expected_fp)))
        rep.check(signer_fp != play_fp, "the signer is not the Google Play app-signing certificate (a local build cannot have that key)",
                  "the signer equals the Google Play app-signing certificate, which no local build can hold: refusing")
        rep.note("a locally signed artifact carries the upload identity, NOT the Google Play app-signing identity: "
                 "an APK of it cannot update an installation that came from Google Play")
    return cls


# ---- APK ---------------------------------------------------------------------------------------
def parse_badging(text):
    def one(pattern):
        m = re.search(pattern, text, re.M)
        return m.group(1) if m else None
    return {
        "id": one(r"^package: name='([^']*)'"),
        "code": one(r"^package:.* versionCode='([^']*)'"),
        "name": one(r"^package:.* versionName='([^']*)'"),
        "label": one(r"^application-label:'(.*)'$"),
        "min": one(r"^sdkVersion:'(\d+)'"),
        "target": one(r"^targetSdkVersion:'(\d+)'"),
        "debuggable": bool(re.search(r"^application-debuggable", text, re.M)),
    }


def check_manifest_xml(rep, tree_text, app_id):
    auths = re.findall(r'authorities\(0x[0-9a-f]+\)="([^"]*)"', tree_text)
    bad = [a for a in auths for part in a.split(";") if not part.startswith(app_id + ".")]
    rep.check(not bad, "all %d content-provider authorities start with the application ID" % len(auths),
              "authorities that do not start with %s.: %s" % (app_id, ", ".join(bad)))
    rep.check(re.search(r"usesCleartextTraffic\(0x[0-9a-f]+\)=(false|\(type 0x12\)0x0)", tree_text) is not None,
              "cleartext traffic is forbidden (usesCleartextTraffic=false)", "usesCleartextTraffic is not false")
    rep.check(re.search(r"allowBackup\(0x[0-9a-f]+\)=(false|\(type 0x12\)0x0)", tree_text) is not None,
              "backups are not allowed (allowBackup=false)", "allowBackup is not false")


def parse_apksigner(text):
    def flag(label):
        m = re.search(r"Verified using %s: (true|false)" % re.escape(label), text)
        return m.group(1) == "true" if m else None
    sha = re.findall(r"Signer #(\d+) certificate SHA-256 digest: ([0-9a-f]{64})", text)
    dn = re.findall(r"Signer #\d+ certificate DN: (.*)", text)
    n = re.search(r"Number of signers: (\d+)", text)
    return {"verifies": text.lstrip().startswith("Verifies") or "\nVerifies" in text,
            "v1": flag("v1 scheme (JAR signing)"), "v2": flag("v2 scheme (APK Signature Scheme v2)"),
            "v3": flag("v3 scheme (APK Signature Scheme v3)"), "v31": flag("v3.1 scheme (APK Signature Scheme v3.1)"),
            "signers": int(n.group(1)) if n else None, "sha256": [s[1] for s in sha], "dn": dn}


def verify_apk(repo, env, path, mode, expected_fp, min_target, signing_ledger, native_ledger):
    rep = Report("verify_android_release apk: %s (%s, %s)" % (os.path.basename(path), env, mode))
    rep.ev("kind", "apk")
    rep.ev("file", os.path.basename(path))
    rep.ev("sha256", sha256_path(path))
    rep.ev("bytes", os.path.getsize(path))
    aapt2, apksigner, zipalign = (find_tool(t, repo) for t in ("aapt2", "apksigner", "zipalign"))
    if not aapt2 or not apksigner:
        raise Usage("aapt2 and apksigner are needed (set ANDROID_HOME, or sdk.dir in android/local.properties)")
    rc, out = run([aapt2, "dump", "badging", path])
    if rc != 0:
        raise Usage("aapt2 cannot read %s" % path)
    b = parse_badging(out)
    check_identity(rep, repo, env, b["id"], b["label"], b["name"], b["code"], b["debuggable"], min_target,
                   int(b["target"]) if b["target"] else None, "apk")
    rep.ev("min_sdk", b["min"] or "")
    rep.ev("target_sdk", b["target"] or "")
    rc, tree = run([aapt2, "dump", "xmltree", "--file", "AndroidManifest.xml", path])
    if rc == 0:
        check_manifest_xml(rep, tree, b["id"] or "")
    else:
        rep.fail("aapt2 cannot dump the manifest")
    # signature
    rc, sig = run([apksigner, "verify", "--verbose", "--print-certs", path])
    s = parse_apksigner(sig)
    rep.check(rc == 0 and s["verifies"], "apksigner verifies the signature", "apksigner REJECTS the signature: %s" % sig.strip().splitlines()[0:1])
    rep.check(s["v2"] is True, "APK Signature Scheme v2 is present", "APK Signature Scheme v2 is missing")
    rep.check(s["v3"] is True, "APK Signature Scheme v3 is present (needed for a later key rotation)", "APK Signature Scheme v3 is missing")
    rep.ev("schemes", "v1=%s v2=%s v3=%s v3.1=%s" % (s["v1"], s["v2"], s["v3"], s["v31"]))
    if s["signers"] == 1 and len(s["sha256"]) == 1:
        rep.ok("exactly one signer")
        check_signer(rep, s["sha256"][0], s["dn"][0] if s["dn"] else "", mode, expected_fp, signing_ledger, True)
    else:
        rep.fail("expected exactly one signer, apksigner reports %s" % s["signers"])
        rep.ev("signing_class", "unknown")
    # native libraries
    with zipfile.ZipFile(path) as zf:
        libs = native_entries(zf, "lib/")
    rep.ev("native_lib_sha256", check_native(rep, libs, native_ledger, "the APK"))
    if zipalign:
        rc, za = run([zipalign, "-c", "-P", "16", "-v", "4", path])
        if rc == 0:
            rep.ok("the APK is zip-aligned for 16 KB pages (zipalign -P 16)")
        elif "Verification FAILED" in za:
            rep.fail("the APK is NOT zip-aligned for 16 KB pages: " + "; ".join(l.strip() for l in za.splitlines() if "BAD" in l)[:300])
        else:
            rep.note("zipalign does not support -P 16 here; the zip alignment for 16 KB pages was not verified")
    else:
        rep.note("zipalign was not found; the zip alignment for 16 KB pages was not verified")
    return rep


# ---- AAB ---------------------------------------------------------------------------------------
def parse_keytool_jar(text):
    signers = re.findall(r"^Signer #(\d+):", text, re.M)
    sha = re.findall(r"SHA256: ([0-9A-F:]{95})", text)
    owner = re.findall(r"^Owner: (.*)$", text, re.M)
    until = re.findall(r"until: (.*)$", text, re.M)
    return signers, sha, owner, until


def until_date(text):
    m = re.search(r"([A-Z][a-z]{2}) ([A-Z][a-z]{2}) (\d{1,2}) \d\d:\d\d:\d\d \S+ (\d{4})", text)
    if not m:
        return None
    try:
        return datetime.datetime.strptime("%s %s %s" % (m.group(2), m.group(3), m.group(4)), "%b %d %Y").date()
    except ValueError:
        return None


def verify_aab(repo, env, path, expected_fp, min_target, signing_ledger, native_ledger):
    rep = Report("verify_android_release aab: %s (%s, release)" % (os.path.basename(path), env))
    rep.ev("kind", "aab")
    rep.ev("file", os.path.basename(path))
    rep.ev("sha256", sha256_path(path))
    rep.ev("bytes", os.path.getsize(path))
    bt = bundletool_cmd()
    if not bt:
        raise Usage("bundletool is needed (set BUNDLETOOL_JAR to a pinned bundletool jar)")
    rc, man = run(bt + ["dump", "manifest", "--bundle=" + path])
    if rc != 0:
        raise Usage("bundletool cannot read %s" % path)
    root = ET.fromstring(man)
    app = root.find("application")
    uses_sdk = root.find("uses-sdk")
    target = uses_sdk.get(A + "targetSdkVersion") if uses_sdk is not None else None
    check_identity(rep, repo, env, root.get("package", ""), app.get(A + "label", "") if app is not None else "",
                   root.get(A + "versionName", ""), root.get(A + "versionCode", ""),
                   (app.get(A + "debuggable", "") == "true") if app is not None else False,
                   min_target, int(target) if target and target.isdigit() else None, "aab")
    rep.check(app is not None and app.get(A + "usesCleartextTraffic") == "false", "cleartext traffic is forbidden (usesCleartextTraffic=false)",
              "usesCleartextTraffic is not false")
    rep.check(app is not None and app.get(A + "allowBackup") == "false", "backups are not allowed (allowBackup=false)", "allowBackup is not false")
    auths = [p.get(A + "authorities", "") for p in root.iter("provider")]
    pkg = root.get("package", "")
    bad = [a for a in auths for part in a.split(";") if part and not part.startswith(pkg + ".")]
    rep.check(not bad, "all %d content-provider authorities start with the application ID" % len(auths),
              "authorities that do not start with %s.: %s" % (pkg, ", ".join(bad)))
    # signature
    jarsigner = "jarsigner"
    rc, js = run([jarsigner, "-verify", path])
    rep.check(rc == 0 and "jar verified" in js, "jarsigner verifies the bundle signature (every entry is covered)",
              "jarsigner REJECTS the bundle: %s" % (js.strip().splitlines()[0:1],))
    rep.check("unsigned entries" not in js, "no entry of the bundle is outside the signature",
              "the bundle contains unsigned entries that were not integrity-checked")
    rc, kt = run(["keytool", "-printcert", "-jarfile", path])
    signers, sha, owner, until = parse_keytool_jar(kt)
    if rc == 0 and len(signers) == 1 and len(sha) >= 1:
        rep.ok("exactly one signer")
        fp = norm_fp(sha[0])
        check_signer(rep, fp, owner[0] if owner else "", "release", expected_fp, signing_ledger, True)
        d = until_date(until[0]) if until else None
        rep.ev("signer_valid_until", d.isoformat() if d else "")
        rep.check(d is not None and d > GOOGLE_VALIDITY_END, "the signing certificate is valid beyond %s (Google Play's requirement)" % GOOGLE_VALIDITY_END,
                  "the signing certificate's validity ends %s, Google Play requires it beyond %s" % (d, GOOGLE_VALIDITY_END))
    else:
        rep.fail("expected exactly one signer, keytool reports %d" % len(signers))
        rep.ev("signing_class", "unknown")
    with zipfile.ZipFile(path) as zf:
        libs = native_entries(zf, "base/lib/")
    rep.ev("native_lib_sha256", check_native(rep, libs, native_ledger, "the bundle"))
    return rep


# ---- APK <-> AAB ------------------------------------------------------------------------------
def verify_pair(apk_rep, aab_rep):
    rep = Report("verify_android_release pair: the APK and the AAB are one release")
    for key, label in (("application_id", "application ID"), ("display_name", "display name"),
                       ("version_name", "versionName"), ("version_code", "versionCode"),
                       ("signer_sha256", "signing certificate")):
        a, b = apk_rep.evidence.get(key), aab_rep.evidence.get(key)
        rep.check(bool(a) and a == b, "%s is identical: %s" % (label, a), "%s differs or is missing: '%s' vs '%s'" % (label, a, b))
    na, nb = apk_rep.evidence.get("native_lib_sha256", {}), aab_rep.evidence.get("native_lib_sha256", {})
    rep.check(bool(na) and na == nb, "the Rust libraries of every ABI are byte-identical in both artifacts (%d files)" % len(na),
              "the Rust libraries differ between the APK and the AAB")
    return rep


# ---- provenance --------------------------------------------------------------------------------
def git(repo, *args):
    rc, out = run(["git", "-C", repo] + list(args))
    return out.strip() if rc == 0 else None


def first_line(cmd):
    rc, out = run(cmd, timeout=120)
    return out.strip().splitlines()[0] if rc == 0 and out.strip() else "unknown"


def provenance(repo, env, bundletool_jar):
    commit = git(repo, "rev-parse", "HEAD")
    dirty = git(repo, "status", "--porcelain", "--untracked-files=no")
    cfg = os.path.join(repo, "config", "build", "%s.json" % env)
    gate_rc, gate_out = run([sys.executable, "-I", os.path.join(HERE, "build_manifest.py"), "gate", "--channel", env, "--repo", repo])
    sdk = None
    for p in ("aapt2", "apksigner"):
        t = find_tool(p, repo)
        if t:
            sdk = os.path.basename(os.path.dirname(t))
            break
    gradle_props = os.path.join(repo, "android", "gradle", "wrapper", "gradle-wrapper.properties")
    gradle = ""
    if os.path.isfile(gradle_props):
        m = re.search(r"gradle-([\d.]+)-", open(gradle_props).read())
        gradle = m.group(1) if m else ""
    agp = ""
    sg = os.path.join(repo, "android", "settings.gradle.kts")
    if os.path.isfile(sg):
        m = re.search(r'com\.android\.application"\) version "([\d.]+)"', open(sg).read())
        agp = m.group(1) if m else ""
    _raw, vname, vbuild = BM.load_pubspec(repo)
    return {
        "commit": commit, "branch": git(repo, "symbolic-ref", "--short", "-q", "HEAD") or "(detached)",
        "tracked_tree_clean": dirty == "" if dirty is not None else False,
        "pubspec_version": "%s+%s" % (vname, vbuild),
        "configuration": {"file": "config/build/%s.json" % env, "sha256": sha256_path(cfg) if os.path.isfile(cfg) else None},
        "ledgers": {n: sha256_path(os.path.join(repo, "config", "release", n))
                    for n in ("android_signing.json", "native_libs.json", "published_versions.json")
                    if os.path.isfile(os.path.join(repo, "config", "release", n))},
        "toolchain": {
            "flutter": first_line(["flutter", "--version"]), "java": first_line(["java", "-version"]),
            "gradle": gradle, "android_gradle_plugin": agp, "android_build_tools": sdk or "unknown",
            "bundletool": (os.path.basename(bundletool_jar) + " sha256 " + sha256_path(bundletool_jar)) if bundletool_jar and os.path.isfile(bundletool_jar) else "unknown",
            "python": platform.python_version(),
        },
        "builder": {"host": platform.platform(), "time_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
        "production_gate": {"command": "tool/build_manifest.py gate --channel %s" % env, "exit_status": gate_rc, "output": gate_out.strip().splitlines()},
    }


def markdown(report):
    r = report
    lines = ["# Android release report", "",
             "**%s** - environment `%s`, %s" % ("RELEASE READY (verified, NOT published)" if r["release_ready"] else "NOT READY", r["environment"], r["provenance"]["pubspec_version"]), "",
             "> Verification is not authorization to publish. `distributable: false` until the release authority decides, "
             "per channel, to deliver this artifact (website) or upload it (Google Play).", ""]
    if r["not_ready_reasons"]:
        lines += ["## Why it is not ready", ""] + ["- " + x for x in r["not_ready_reasons"]] + [""]
    p = r["provenance"]
    lines += ["## Provenance", "",
              "| | |", "|---|---|",
              "| Commit | `%s` (%s), tracked tree clean: %s |" % (p["commit"], p["branch"], p["tracked_tree_clean"]),
              "| Version | %s |" % p["pubspec_version"],
              "| Signing identity label | %s |" % r["signing_identity_label"],
              "| Expected certificate (SHA-256) | `%s` |" % r["expected_certificate_sha256"],
              "| Configuration | `%s` `%s` |" % (p["configuration"]["file"], p["configuration"]["sha256"]),
              "| Built/verified | %s on %s |" % (p["builder"]["time_utc"], p["builder"]["host"]),
              "| Flutter | %s |" % p["toolchain"]["flutter"],
              "| Java | %s |" % p["toolchain"]["java"],
              "| Gradle / AGP / build-tools | %s / %s / %s |" % (p["toolchain"]["gradle"], p["toolchain"]["android_gradle_plugin"], p["toolchain"]["android_build_tools"]),
              "| bundletool | %s |" % p["toolchain"]["bundletool"], ""]
    lines += ["## Ledgers (SHA-256)", ""] + ["- `%s` `%s`" % (k, v) for k, v in sorted(p["ledgers"].items())] + [""]
    lines += ["## Artifacts", "", "| File | SHA-256 | Bytes | Signer (SHA-256) | Class | Schemes |", "|---|---|---|---|---|---|"]
    for a in r["artifacts"]:
        lines.append("| %s | `%s` | %s | `%s` | %s | %s |" % (a["file"], a["sha256"], a["bytes"], a["signer_sha256"], a["signing_class"], a.get("schemes", "jar signature")))
    lines += ["", "## Production gate", "", "```"] + p["production_gate"]["output"] + ["```", "", "## Checks", ""]
    for name, res in r["verification"].items():
        lines += ["### %s - %s" % (name, "all passed" if res["failures"] == 0 else "%d FAILED" % res["failures"]), "", "```"]
        lines += ["%-4s  %s" % (s, t) for s, t in res["checks"]]
        lines += ["```", ""]
    lines += ["## Not verified by this report", "",
              "- that Google Play accepts the upload (only an upload shows that) or what it signs delivered APKs with (Play Console);",
              "- anything about a device;",
              "- the identity of the person who holds the key (see docs/ANDROID_RELEASE.md and the custody register).", ""]
    return "\n".join(lines)


def cmd_release(args):
    repo = os.path.abspath(args.repo)
    signing_ledger, native_ledger = load_ledgers(repo)
    expected = require_expected(args, signing_ledger)
    for f in (args.apk, args.aab):
        if not os.path.isfile(f):
            raise Usage("%s is not a file" % f)
    apk_rep = verify_apk(repo, args.env, args.apk, "release", expected, args.min_target_sdk, signing_ledger, native_ledger)
    aab_rep = verify_aab(repo, args.env, args.aab, expected, args.min_target_sdk, signing_ledger, native_ledger)
    pair_rep = verify_pair(apk_rep, aab_rep)
    prov = provenance(repo, args.env, os.environ.get("BUNDLETOOL_JAR"))
    reasons = []
    for r in (apk_rep, aab_rep, pair_rep):
        if r.failures:
            reasons.append("%d verification check(s) failed: %s" % (r.failures, r.title))
    if not prov["tracked_tree_clean"] and not args.allow_dirty:
        reasons.append("the tracked working tree is not clean (a release is built from a committed state)")
    if prov["production_gate"]["exit_status"] != 0:
        reasons.append("the %s release gate fails (build number or application ID; see Production gate)" % args.env)
    report = {
        "schema": SCHEMA, "environment": args.env, "release_ready": not reasons, "not_ready_reasons": reasons,
        "distributable": False,
        "distributable_note": "Never set by this tool. Delivery to the website or an upload to Google Play is a separate, explicitly authorized step.",
        "signing_identity_label": args.identity_label, "expected_certificate_sha256": colon(expected),
        "provenance": prov,
        "artifacts": [dict(r.evidence, native_lib_sha256=None) for r in (apk_rep, aab_rep)],
        "native_libraries": apk_rep.evidence.get("native_lib_sha256", {}),
        "verification": {r.title.split(":")[0].replace("verify_android_release ", ""): {"failures": r.failures, "checks": r.lines}
                         for r in (apk_rep, aab_rep, pair_rep)},
    }
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "release-report.json"), "w") as f:
        json.dump(report, f, indent=2, sort_keys=True)
        f.write("\n")
    with open(os.path.join(args.out, "release-report.md"), "w") as f:
        f.write(markdown(report))
    with open(os.path.join(args.out, "SHA256SUMS"), "w") as f:
        for r in (apk_rep, aab_rep):
            f.write("%s  %s\n" % (r.evidence["sha256"], r.evidence["file"]))
    for r in (apk_rep, aab_rep, pair_rep):
        r.print()
    print("release report: %s" % os.path.join(args.out, "release-report.md"))
    if reasons:
        print("RESULT: NOT READY (%s)" % "; ".join(reasons))
        return 1
    print("RESULT: OK (release ready, verified, not published)")
    return 0


# ---- CLI --------------------------------------------------------------------------------------
def require_expected(args, signing_ledger):
    expected = norm_fp(args.expect_cert_sha256) if args.expect_cert_sha256 else None
    if args.expect_cert_sha256 and not expected:
        raise Usage("--expect-cert-sha256 must be a SHA-256 fingerprint (64 hex digits, colons optional)")
    if getattr(args, "signing", "release") == "release":
        if not expected:
            raise Usage("a release verification needs --expect-cert-sha256 (the upload certificate the artifact must carry)")
        active = signing_ledger["upload"].get("active_sha256")
        if active and norm_fp(active) != expected:
            raise Usage("--expect-cert-sha256 differs from the active upload fingerprint recorded in config/release/android_signing.json")
        if not active:
            print("NOTE  config/release/android_signing.json records no active upload fingerprint yet: the expected "
                  "fingerprint %s is not cross-checked against the repository" % colon(expected))
    return expected


def main(argv):
    ap = argparse.ArgumentParser(prog="verify_android_release.py", description="Android release verification (Issue #72)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p):
        p.add_argument("env", choices=("staging", "production"))
        p.add_argument("--repo", default=BM.DEFAULT_ROOT)
        p.add_argument("--expect-cert-sha256", default=None)
        p.add_argument("--min-target-sdk", type=int, default=36)
    p = sub.add_parser("apk")
    common(p)
    p.add_argument("file")
    p.add_argument("--signing", choices=("release", "play"), default="release")
    p = sub.add_parser("aab")
    common(p)
    p.add_argument("file")
    p = sub.add_parser("pair")
    common(p)
    p.add_argument("apk")
    p.add_argument("aab")
    p = sub.add_parser("release")
    common(p)
    p.set_defaults(env_only="production")
    p.add_argument("--apk", required=True)
    p.add_argument("--aab", required=True)
    p.add_argument("--identity-label", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--allow-dirty", action="store_true")
    args = ap.parse_args(argv)
    try:
        repo = os.path.abspath(args.repo)
        if args.cmd == "release":
            if args.env != "production":
                raise Usage("`release` is for the production APK and AAB; a staging signing identity does not exist yet (Issue #72)")
            return cmd_release(args)
        signing_ledger, native_ledger = load_ledgers(repo)
        expected = require_expected(args, signing_ledger)
        if args.cmd == "apk":
            rep = verify_apk(repo, args.env, args.file, args.signing, expected, args.min_target_sdk, signing_ledger, native_ledger)
        elif args.cmd == "aab":
            rep = verify_aab(repo, args.env, args.file, expected, args.min_target_sdk, signing_ledger, native_ledger)
        else:
            a = verify_apk(repo, args.env, args.apk, "release", expected, args.min_target_sdk, signing_ledger, native_ledger)
            b = verify_aab(repo, args.env, args.aab, expected, args.min_target_sdk, signing_ledger, native_ledger)
            rep = verify_pair(a, b)
            a.print()
            b.print()
            if a.failures or b.failures:
                rep.fail("an individual artifact failed (see above)")
        rep.print()
        for k, v in sorted(rep.evidence.items()):
            if not isinstance(v, dict):
                print("evidence %s=%s" % (k, v))
        print("RESULT: %s" % ("OK" if rep.failures == 0 else "FAILED (%d)" % rep.failures))
        return 0 if rep.failures == 0 else 1
    except Usage as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 2
    except (zipfile.BadZipFile, OSError, ET.ParseError, KeyError, ValueError) as e:
        # An unreadable or malformed artifact is a failure, never a pass.
        print("ERROR: the input could not be read as an Android artifact (%s: %s)" % (type(e).__name__, e), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
