#!/usr/bin/env python3
"""Synthetic builds with REAL build manifests, for the tests of the retained-artifact tools
(tool/test_retained_artifacts.sh, tool/test_resign_android_aab.sh):

  tool/retained_fixtures.py REPO_ROOT OUT_DIR

Writes OUT_DIR/<variant>/ for android-production-apk, android-production-aab, android-staging-apk
and ios-production: the artifact (a small zip or an .xcarchive directory), its text evidence, a
toolchain file and the build manifest made by tool/build_manifest.py create. Test data only: no
credential, no network, nothing that is a real application."""
import hashlib, json, os, plistlib, shutil, subprocess, sys, zipfile
sys.dont_write_bytecode = True
root, out = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, "tool"))
import build_manifest as bm

COMMIT = "7b63c9791fccc8f9711ed853e2294967899be972"
RUN = "39237471969"
Z = "0" * 64
pubspec, name, build = bm.load_pubspec(root)
cfg_sha = {e: bm.sha256_file(os.path.join(root, "config/build/%s.json" % e)) for e in ("staging", "production")}

def sha(b): return hashlib.sha256(b).hexdigest()

def make_zip(path, entries, signer=b"SIGNER-A"):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, data in entries.items():
            z.writestr(n, data)
        z.writestr("META-INF/MANIFEST.MF", b"Manifest-Version: 1.0\n" + signer)
        z.writestr("META-INF/CERT.SF", b"Signature-Version: 1.0\n" + signer)
        z.writestr("META-INF/CERT.RSA", b"\x30\x82" + signer)

def write_ev(d, variant, lines):
    with open(os.path.join(d, variant + ".txt"), "w") as f:
        f.write("".join("%s=%s\n" % kv for kv in lines))

def common(variant, env, app_id, bname, kind_cmd):
    return [
        ("variant", variant),
        ("build_command", "flutter build %s --release --flavor %s --dart-define-from-file=config/build/%s.json" % (kind_cmd, env, env)),
        ("config_file", "config/build/%s.json" % env),
        ("config_file_sha256", cfg_sha[env]),
        ("commit", COMMIT), ("ref", env),
        ("run", "https://github.com/CadenaBitcoin/signer_app/actions/runs/%s (attempt 1)" % RUN),
    ]

def tail(env, app_id, dname):
    return [("environment", env), ("application_id", app_id), ("display_name", dname),
            ("version_name", name), ("version_code", str(build)), ("distributable", "no"),
            ("environment_check", "%s-url-present-other-absent" % env), ("environment_check_snapshots", "3")]

def create_manifest(d, variant, toolchain):
    with open(os.path.join(d, variant + ".toolchain"), "w") as f:
        f.write(toolchain)
    env = dict(os.environ, GITHUB_RUN_ID=RUN, GITHUB_RUN_ATTEMPT="1", GITHUB_SERVER_URL="https://github.com",
               GITHUB_REPOSITORY="CadenaBitcoin/signer_app", GITHUB_SHA=COMMIT, GITHUB_REF_NAME=("staging" if "staging" in variant else "production"),
               GITHUB_REF_TYPE="branch", GITHUB_EVENT_NAME="push", GITHUB_WORKFLOW="Build variants (compile validation)")
    subprocess.run([sys.executable, "-I", os.path.join(root, "tool", "build_manifest.py"), "create", "--evidence", os.path.join(d, variant + ".txt"),
                    "--toolchain", os.path.join(d, variant + ".toolchain"), "--out", os.path.join(d, variant + ".manifest.json")],
                   check=True, stdout=subprocess.DEVNULL, env=env)

ANDROID_TC = "flutter=Flutter 3.35.3 • channel stable\ndart=3.9.2\njava=openjdk version \"17.0.10\"\nrunner_image=ubuntu24 20260101.1\nandroid_build_tools=36.0.0\n"
IOS_TC = "runner_image=macos15 20260101.1\nrunner_arch=arm64\nxcode=26.3 (17C529)\niphoneos_sdk=26.2\nflutter=3.35.3 (revision a402d9a437)\ndart=3.9.2\ncocoapods=1.17.0\n"

def android(variant, kind, env):
    d = os.path.join(out, variant); os.makedirs(d)
    fname = "app-%s-release.%s" % (env, kind)
    path = os.path.join(d, fname)
    make_zip(path, {"AndroidManifest.xml": b"<manifest/>", "classes.dex": b"dex-" + variant.encode(), "resources.arsc": b"res",
                    "META-INF/services/x": b"service"})
    data = open(path, "rb").read()
    app_id = "com.cadenabitcoin.mobile.signer" + (".staging" if env == "staging" else "")
    lines = common(variant, env, app_id, "", "apk" if kind == "apk" else "appbundle")
    lines += [("artifact_kind", kind), ("artifact_file", fname), ("artifact_sha256", sha(data)), ("artifact_bytes", str(len(data))),
              ("signing", "debug"), ("signer_dn", "C=US, O=Android, CN=Android Debug"), ("signer_cert_sha256", Z),
              ("native_lib_sha256.arm64-v8a", Z)]
    lines += tail(env, app_id, "Cadena Signer STAGING" if env == "staging" else "Cadena Bitcoin")
    write_ev(d, variant, lines)
    create_manifest(d, variant, ANDROID_TC)

def ios_app(app, version, build_no, bundle_id, exe=b"MACHO-EXE", extra=None):
    os.makedirs(os.path.join(app, "Frameworks", "App.framework"))
    with open(os.path.join(app, "Info.plist"), "wb") as f:
        plistlib.dump({"CFBundleIdentifier": bundle_id, "CFBundleShortVersionString": version, "CFBundleVersion": str(build_no)}, f)
    with open(os.path.join(app, "Runner"), "wb") as f: f.write(exe)
    os.chmod(os.path.join(app, "Runner"), 0o755)
    with open(os.path.join(app, "Frameworks", "App.framework", "App"), "wb") as f: f.write(b"AOT-SNAPSHOT" + (extra or b""))

def ios_evidence(app):
    snap = sha(open(os.path.join(app, "Frameworks", "App.framework", "App"), "rb").read())
    exe = sha(open(os.path.join(app, "Runner"), "rb").read())
    return [("artifact_sha256", bm.tree_digest(app)), ("app_snapshot_sha256", snap), ("executable_sha256", exe),
            ("minimum_os_version", "14.0"), ("executable_archs", "arm64"), ("signing", "unsigned")]

def ios(variant, env):
    d = os.path.join(out, variant); os.makedirs(d)
    bundle = "com.app.cadenabitcoin" + (".staging" if env == "staging" else "")
    dname = "Cadena Signer STAGING" if env == "staging" else "Cadena Bitcoin"
    # an iOS run that retains verifies the application INSIDE the unsigned archive
    # (flutter build ipa --no-codesign), and its evidence describes that application
    arch = os.path.join(d, "Runner.xcarchive")
    app = os.path.join(arch, "Products", "Applications", "Runner.app")
    ios_app(app, name, build, bundle)
    os.makedirs(os.path.join(arch, "dSYMs", "Runner.app.dSYM"))
    with open(os.path.join(arch, "dSYMs", "Runner.app.dSYM", "sym"), "wb") as f: f.write(b"dsym")
    with open(os.path.join(arch, "Info.plist"), "wb") as f:
        plistlib.dump({"ApplicationProperties": {"ApplicationPath": "Applications/Runner.app"}}, f)
    ev = common(variant, env, bundle, "", "ios")
    ev[1] = ("build_command", "flutter build ipa --release --no-codesign --flavor %s --dart-define-from-file=config/build/%s.json" % (env, env))
    ev += [("podfile_lock_drift", "no"), ("rust_lib_sha256", Z), ("artifact_kind", "ios-app"), ("artifact_file", "Runner.app"),
           ("artifact_sha256_basis", "sha256 of the sorted per-file sha256 manifest of the .app directory"), ("artifact_bytes", "12KiB")]
    ev += ios_evidence(app)
    ev += tail(env, bundle, dname)
    write_ev(d, variant, ev)
    create_manifest(d, variant, IOS_TC)

android("android-production-apk", "apk", "production")
android("android-production-aab", "aab", "production")
android("android-staging-apk", "apk", "staging")
ios("ios-production", "production")
print("fixtures ready")
