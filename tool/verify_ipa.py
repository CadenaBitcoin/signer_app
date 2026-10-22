#!/usr/bin/env python3
"""Independent verification of a signed iOS IPA, before anything is uploaded.

  tool/verify_ipa.py verify ENV IPA --team-id TEAM [options]
  tool/verify_ipa.py structure RUNNER_APP_OR_IPA
  tool/verify_ipa.py compare UNSIGNED_RUNNER_APP SIGNED_RUNNER_APP_OR_IPA
  tool/verify_ipa.py analyze-unsigned RUNNER_APP_DIR

`verify` reads the IPA as a stranger would: it trusts nothing the signing job says about it. It
checks, from the files alone, that

  identity      the bundle identifier, display name, version and build number are the ones ENV and
                pubspec.yaml require (staging and production never mix);
  signature     every executable is signed (not ad hoc), by ONE certificate, for the expected Team ID;
                the CodeDirectory page hashes, special slots (Info.plist, requirements,
                CodeResources, entitlements) and the bundle's CodeResources match the files, so
                nothing was changed after signing; the CMS signature is valid; the cdhashes bound by
                it cover every CodeDirectory;
  certificate   subject (Team ID, "Apple Distribution"), issuer, validity, SHA-256 fingerprint
                (pinned by --expect-cert-sha256; required for production);
  profile       embedded.mobileprovision is an App Store profile (no device list, get-task-allow
                false), for the right Team ID and the exact App ID, not expired, containing the
                signing certificate, with a valid CMS signature;
  entitlements  application-identifier, team identifier, get-task-allow absent, aps-environment
                production when present, and every entitlement granted by the profile;
  provenance    with --manifest and --unsigned-app: the unsigned bundle is the one the build manifest
                describes, and the IPA is that bundle plus signatures only (same code, no recompile,
                no file added or changed).

Nothing here needs a credential: it reads public data. Exit 0: every check passed. Exit 1: at least
one failed. Exit 2: usage or an unreadable input.

WHAT THIS CANNOT PROVE (printed with every run; docs/IOS_SIGNING.md lists them as well): that the
certificate chain leads to an Apple root and is not revoked, and that App Store Connect or a device
accepts the app. Those need a real Apple-signed IPA, Apple's trust anchors and Apple itself.
"""
import argparse
import datetime
import hashlib
import os
import plistlib
import re
import stat
import struct
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True  # importing the tool/ modules must not leave __pycache__ in the repository
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ipa_inspect as I  # noqa: E402
import build_manifest as BM  # noqa: E402

DEFAULT_ISSUER_CN = "Apple Worldwide Developer Relations Certification Authority"
LEAF_PREFIXES = ("Apple Distribution:", "iPhone Distribution:")
MAX_FILES, MAX_BYTES = 50000, 3 * 1024 ** 3
# Test and throwaway identities say so in their names; they must never be taken for a genuine one.
SYNTHETIC_MARKERS = ("Synthetic", "Throwaway")
UNSUPPORTED_NESTED = ("PlugIns", "Watch", "AppClips", "Extensions", "SystemExtensions")
NOT_VERIFIED = [
    "the certificate chain to an Apple root, and revocation (no Apple trust anchors are used here)",
    "that App Store Connect accepts the build (its own validation, ITMS checks, processing)",
    "that the app installs and runs on a device (runtime compatibility is a separate release requirement)",
    "the exact layout of CodeResources for nested bundles as produced by Apple's codesign "
    "(each nested bundle is verified on its own; the outer linkage is not)",
]


class Report(object):
    def __init__(self):
        self.failed = 0
        self.passed = 0
        self.warned = 0
        self.evidence = []

    def ok(self, text):
        self.passed += 1
        print("  PASS  " + text)

    def fail(self, text):
        self.failed += 1
        print("  FAIL  " + text)

    def warn(self, text):
        self.warned += 1
        print("  WARN  " + text)

    def info(self, text):
        print("  INFO  " + text)

    def check(self, cond, ok_text, bad_text):
        (self.ok if cond else self.fail)(ok_text if cond else bad_text)
        return bool(cond)

    def ev(self, key, value):
        self.evidence.append((key, "" if value is None else str(value)))


def die(text, code=2):
    print("verify_ipa: %s" % text, file=sys.stderr)
    sys.exit(code)


def parse_now(text):
    if not text:
        return datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None, microsecond=0)
    try:
        return datetime.datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        die("--now must look like 2026-10-22T12:00:00Z")


def iso_to_dt(text):
    return datetime.datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ")


def sha256_path(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ---- the container ---------------------------------------------------------------------------


def extract_ipa(ipa, dest):
    """Extract with every member checked first. -> (app_dir, problems). Nothing is trusted:
    absolute paths, '..', backslashes, symlinks leaving the bundle and size bombs are refused."""
    problems = []
    try:
        zf = zipfile.ZipFile(ipa)
    except (zipfile.BadZipFile, OSError) as e:
        return None, ["not a readable zip archive: %s" % e]
    with zf:
        infos = zf.infolist()
        if len(infos) > MAX_FILES:
            return None, ["archive has %d entries (limit %d)" % (len(infos), MAX_FILES)]
        if sum(i.file_size for i in infos) > MAX_BYTES:
            return None, ["archive expands beyond %d bytes" % MAX_BYTES]
        names = [i.filename for i in infos]
        folded = [n.lower().rstrip("/") for n in names]
        if len(set(folded)) != len(folded):
            return None, ["the archive has duplicate member names (ambiguous content)"]
        if any(i.flag_bits & 0x1 for i in infos):
            return None, ["the archive has encrypted members"]
        try:
            bad = zf.testzip()
        except (RuntimeError, zipfile.BadZipFile, NotImplementedError) as e:
            return None, ["the archive cannot be read: %s" % e]
        if bad:
            return None, ["archive member %s is corrupt (CRC)" % bad]
        apps = set()
        for i in infos:
            n = i.filename
            parts = n.split("/")
            if n.startswith("/") or "\\" in n or "\0" in n or ".." in parts:
                problems.append("unsafe member name %r" % n)
                continue
            if parts[0] == "Payload" and len(parts) > 1 and parts[1].endswith(".app"):
                apps.add(parts[1])
        if problems:
            return None, problems
        if len(apps) != 1:
            return None, ["the archive must contain exactly one Payload/<name>.app (found %d)" % len(apps)]
        app_name = sorted(apps)[0]
        root = os.path.realpath(dest)
        for i in infos:
            target = os.path.realpath(os.path.join(root, i.filename))
            if not (target == root or target.startswith(root + os.sep)):
                problems.append("member %r would be written outside the target" % i.filename)
                continue
            mode = (i.external_attr >> 16) & 0xFFFF
            if i.is_dir() or i.filename.endswith("/"):
                os.makedirs(target, exist_ok=True)
            elif stat.S_ISLNK(mode):
                link = zf.read(i).decode("utf-8", "replace")
                resolved = os.path.realpath(os.path.join(os.path.dirname(target), link))
                if os.path.isabs(link) or not resolved.startswith(os.path.join(root, "Payload", app_name)):
                    problems.append("symlink %s -> %s leaves the bundle" % (i.filename, link))
                    continue
                os.makedirs(os.path.dirname(target), exist_ok=True)
                os.symlink(link, target)
            else:
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with zf.open(i) as src, open(target, "wb") as out:
                    while True:
                        chunk = src.read(1 << 20)
                        if not chunk:
                            break
                        out.write(chunk)
                os.chmod(target, 0o755 if mode & 0o111 else 0o644)
        top = sorted({i.filename.split("/")[0] for i in infos})
    if problems:
        return None, problems
    return os.path.join(root, "Payload", app_name), {"top": top}


# ---- helpers ------------------------------------------------------------------------------------


def hash_with(cd, data):
    return hashlib.new(cd["hash_name"], data).digest()[:cd["hash_size"]]


def entitlement_allowed(key, value, granted):
    """Is `value` for `key` covered by the profile's entitlements?"""
    if key not in granted:
        return False
    have = granted[key]
    if isinstance(value, list):
        pats = have if isinstance(have, list) else [have]
        for item in value:
            if not any(p == item or (isinstance(p, str) and p.endswith("*") and str(item).startswith(p[:-1]))
                       for p in pats):
                return False
        return True
    if isinstance(have, str) and have.endswith("*") and isinstance(value, str):
        return value.startswith(have[:-1])
    return have == value


def check_code_signature(rep, label, path, bundle_dir, bundle_id, team_id, expect_identifier, is_main):
    """Verify one Mach-O file's signature. Returns {"signer": cert|None, "ents": dict|None, "ok": bool}."""
    result = {"signer": None, "ents": None, "ok": True, "cdhash": None, "cms_certs": None}
    sig = I.read_signature(path)
    if sig["error"]:
        rep.fail("%s: %s" % (label, sig["error"]))
        result["ok"] = False
        return result
    first_signer = None
    if not sig["slices"]:
        rep.fail("%s has no architecture slice" % label)
        result["ok"] = False
        return result
    for si, s in enumerate(sig["slices"]):
        tag = "%s [arch %s]" % (label, hex(s["cpu"])) if len(sig["slices"]) > 1 else label
        for p in s["problems"]:
            rep.fail("%s: %s" % (tag, p))
            result["ok"] = False
        if s["cpu"] != I.CPU_ARM64:
            rep.fail("%s is not built for arm64 (cpu type 0x%x)" % (tag, s["cpu"]))
            result["ok"] = False
        if not s["signed"]:
            rep.fail("%s is not signed" % tag)
            result["ok"] = False
            continue
        if not s["cds"]:
            result["ok"] = False
            rep.fail("%s has no readable CodeDirectory" % tag)
            continue
        names = [cd["hash_name"] for _k, cd in s["cds"]]
        if "sha256" not in names:
            result["ok"] = False
            rep.fail("%s has no SHA-256 CodeDirectory (hashes: %s)" % (tag, ", ".join(map(str, names))))
        for key, cd in s["cds"]:
            if cd["flags"] & I.CS_ADHOC:
                result["ok"] = False
                rep.fail("%s is ad-hoc signed (no identity)" % tag)
            if cd["flags"] & I.CS_LINKER_SIGNED:
                result["ok"] = False
                rep.fail("%s only carries the linker's signature" % tag)
            if expect_identifier is not None and cd["identifier"] != expect_identifier:
                result["ok"] = False
                rep.fail("%s CodeDirectory identifier is '%s', expected '%s'" % (tag, cd["identifier"], expect_identifier))
            if team_id is not None and cd["team_id"] != team_id:
                result["ok"] = False
                rep.fail("%s CodeDirectory team ID is '%s', expected '%s'" % (tag, cd["team_id"], team_id))
            probs = I.code_slot_problems(cd, s["data"], s.get("signature_offset"))
            for p in probs:
                result["ok"] = False
                rep.fail("%s: %s" % (tag, p))
            # special slots against the files that are present
            def slot_check(slot, blob_or_path, what):
                want = I.slot_hash(cd, slot)
                if blob_or_path is None:
                    if want is not None:
                        result["ok"] = False
                        rep.fail("%s: the CodeDirectory seals %s, which is absent" % (tag, what))
                    return
                data = blob_or_path
                if isinstance(blob_or_path, str):
                    with open(blob_or_path, "rb") as f:
                        data = f.read()
                if want is None:
                    result["ok"] = False
                    rep.fail("%s: the CodeDirectory does not seal %s" % (tag, what))
                elif want != hash_with(cd, data):
                    result["ok"] = False
                    rep.fail("%s: %s was changed after signing" % (tag, what))
            info = os.path.join(bundle_dir, "Info.plist") if bundle_dir else None
            slot_check(I.SLOT_INFO, info if info and os.path.isfile(info) else None, "Info.plist")
            res = os.path.join(bundle_dir, "_CodeSignature", "CodeResources") if bundle_dir else None
            slot_check(I.SLOT_RESOURCES, res if res and os.path.isfile(res) else None, "CodeResources")
            slot_check(I.SLOT_REQUIREMENTS, s["requirements_blob"], "the code requirements")
            slot_check(I.SLOT_ENTITLEMENTS, s["entitlements_blob"], "the entitlements")
            slot_check(I.SLOT_DER_ENTITLEMENTS, s["der_entitlements_blob"], "the DER entitlements")
        if s["cms"] is None:
            result["ok"] = False
            rep.fail("%s has no CMS signature (no signing identity)" % tag)
            continue
        verified = I.cms_verify(s["cms"], detached=s["slots"].get(I.SLOT_CODEDIRECTORY))
        if not verified["ok"]:
            result["ok"] = False
            rep.fail("%s CMS signature is not valid: %s" % (tag, verified["why"]))
        try:
            cms = I.parse_cms(s["cms"])
            bound = I.cms_cdhashes(s["cms"])
        except (I.Asn1Error, IndexError, ValueError, KeyError) as e:
            result["ok"] = False
            rep.fail("%s CMS signature is unreadable: %s" % (tag, e))
            continue
        if verified["ok"] and verified["signer_sha256"] != cms["signer"]["sha256"]:
            result["ok"] = False
            rep.fail("%s: the signer certificate read from the signature is not the one that verified it" % tag)
        if cms["digest_oid"] not in I.OID_SHA256_FAMILY:
            result["ok"] = False
            rep.fail("%s CMS signature uses a digest weaker than SHA-256 (%s)" % (tag, cms["digest_oid"]))
        if bound is None:
            result["ok"] = False
            rep.fail("%s CMS signature does not bind the cdhashes" % tag)
        else:
            for key, cd in s["cds"]:
                if I.cd_hash(cd, cd["hash_name"]) not in bound:
                    result["ok"] = False
                    rep.fail("%s CodeDirectory 0x%x is not bound by the signature (it was replaced)" % (tag, key))
        signer = cms["signer"]
        if result["cms_certs"] is None:
            result["cms_certs"] = cms["certs"]
        if signer is None:
            result["ok"] = False
            rep.fail("%s signature carries no signer certificate" % tag)
            continue
        if first_signer is None:
            first_signer = signer
        elif signer["sha256"] != first_signer["sha256"]:
            result["ok"] = False
            rep.fail("%s is signed by a different certificate than the other architecture slice" % tag)
        if s["entitlements"] is not None:
            if s["der_entitlements"] is not None and s["der_entitlements"] != s["entitlements"]:
                result["ok"] = False
                rep.fail("%s: the DER entitlements (enforced by the kernel) differ from the XML entitlements" % tag)
            if result["ents"] is None:
                result["ents"] = s["entitlements"]
            elif result["ents"] != s["entitlements"]:
                result["ok"] = False
                rep.fail("%s: the entitlements differ between architecture slices" % tag)
        elif s["der_entitlements"] is not None:
            result["ok"] = False
            rep.fail("%s has DER entitlements but no XML entitlements" % tag)
        if result["cdhash"] is None and s["cds"]:
            result["cdhash"] = I.cd_hash(s["cds"][0][1], s["cds"][0][1]["hash_name"]).hex()
    result["signer"] = first_signer
    if result["ok"]:
        rep.ok("%s: signature intact (page hashes, special slots, CMS, bound cdhashes)" % label)
    return result


def all_macho(app_dir):
    out = []
    for rel in I.bundle_files(app_dir):
        full = os.path.join(app_dir, rel)
        if not os.path.islink(full) and I.is_macho(full):
            out.append(rel)
    return out


def dn_text(d):
    return ", ".join("%s=%s" % (k, "/".join(v)) for k, v in sorted(d.items()))


# ---- verify ------------------------------------------------------------------------------------


def verify(args):
    rep = Report()
    repo = os.path.abspath(args.repo)
    now = parse_now(args.now)
    env = args.env
    ids = BM.identities(repo, "ios")
    want_id, want_name = ids[env]
    _raw, want_version, want_build = BM.load_pubspec(repo)
    team = args.team_id

    print("verify_ipa: %s (%s)" % (os.path.basename(args.ipa), env))
    if not os.path.isfile(args.ipa):
        die("%s is not a file" % args.ipa)
    ipa_sha = sha256_path(args.ipa)
    rep.ev("ipa_sha256", ipa_sha)
    rep.ev("ipa_bytes", os.path.getsize(args.ipa))
    rep.info("IPA SHA-256 %s" % ipa_sha)
    if args.expect_sha256:
        rep.check(ipa_sha == args.expect_sha256.lower(), "IPA digest equals the digest handed over by the signing job",
                  "IPA digest %s differs from the expected %s (the file was altered in transfer)" % (ipa_sha, args.expect_sha256))

    with tempfile.TemporaryDirectory(prefix="verify_ipa_") as tmp:
        app_dir, extra = extract_ipa(args.ipa, tmp)
        if app_dir is None:
            for p in extra:
                rep.fail("container: %s" % p)
            return finish(rep, args)
        rep.ok("container: a single %s, safe member names, no unsafe links" % os.path.basename(app_dir))
        unexpected = [t for t in extra["top"] if t not in ("Payload", "SwiftSupport", "Symbols", "BCSymbolMaps")]
        if unexpected:
            rep.warn("container: unexpected top-level entries: %s" % ", ".join(unexpected))

        plist_path = os.path.join(app_dir, "Info.plist")
        if not os.path.isfile(plist_path):
            rep.fail("Info.plist is missing")
            return finish(rep, args)
        try:
            with open(plist_path, "rb") as f:
                info = plistlib.load(f)
            if not isinstance(info, dict):
                raise ValueError("not a dictionary")
        except Exception as e:  # any malformed plist is a failure, never a crash and never a pass
            rep.fail("Info.plist is unreadable: %s" % e)
            return finish(rep, args)
        bundle_id = info.get("CFBundleIdentifier", "")
        exe_name = info.get("CFBundleExecutable", "")
        if not isinstance(exe_name, str) or not exe_name or "/" in exe_name or exe_name.startswith("."):
            rep.fail("CFBundleExecutable %r is not a plain file name" % (exe_name,))
            return finish(rep, args)
        nested_apps = [d for d in UNSUPPORTED_NESTED if os.path.exists(os.path.join(app_dir, d))]
        nested_apps += sorted(r for r in I.bundle_files(app_dir) if r.endswith(".appex/Info.plist") or r.endswith(".app/Info.plist"))
        if nested_apps:
            rep.fail("the app contains nested apps or extensions (%s): each needs its own profile and entitlement check, "
                     "which this tool does not do" % ", ".join(nested_apps[:4]))
        rep.ev("environment", env)
        rep.ev("bundle_id", bundle_id)
        rep.ev("display_name", info.get("CFBundleDisplayName", ""))
        rep.ev("version_name", info.get("CFBundleShortVersionString", ""))
        rep.ev("version_code", info.get("CFBundleVersion", ""))
        rep.ev("team_id", team)

        # ---- identity ----
        rep.check(bundle_id == want_id, "bundle identifier is %s" % bundle_id,
                  "bundle identifier is '%s', %s requires '%s'" % (bundle_id, env, want_id))
        rep.check(info.get("CFBundleDisplayName") == want_name, "display name is '%s'" % want_name,
                  "display name is '%s', %s requires '%s'" % (info.get("CFBundleDisplayName"), env, want_name))
        rep.check(info.get("CFBundleShortVersionString") == want_version,
                  "version %s matches pubspec.yaml" % want_version,
                  "version '%s' differs from pubspec.yaml %s" % (info.get("CFBundleShortVersionString"), want_version))
        rep.check(str(info.get("CFBundleVersion")) == str(want_build), "build number %s matches pubspec.yaml" % want_build,
                  "build number '%s' differs from pubspec.yaml %s" % (info.get("CFBundleVersion"), want_build))
        rep.check(info.get("DTPlatformName") == "iphoneos", "built for iphoneos (a device build)",
                  "DTPlatformName is '%s', expected iphoneos" % info.get("DTPlatformName"))
        if args.min_sdk is not None:
            sdk = str(info.get("DTSDKName", ""))
            m = re.match(r"^iphoneos(\d+)", sdk)
            rep.check(bool(m) and int(m.group(1)) >= args.min_sdk, "SDK %s meets the minimum (iOS %d SDK)" % (sdk, args.min_sdk),
                      "SDK '%s' is below the required iOS %d SDK" % (sdk, args.min_sdk))
        rep.ev("minimum_os_version", info.get("MinimumOSVersion", ""))
        rep.ev("sdk_name", info.get("DTSDKName", ""))
        if "ITSAppUsesNonExemptEncryption" not in info:
            rep.warn("Info.plist has no ITSAppUsesNonExemptEncryption: App Store Connect will ask the export-compliance question")

        exe_path = os.path.join(app_dir, exe_name)
        if not exe_name or not os.path.isfile(exe_path):
            rep.fail("executable '%s' is missing" % exe_name)
            return finish(rep, args)

        # ---- profile ----
        prof_path = os.path.join(app_dir, "embedded.mobileprovision")
        prof = None
        if not os.path.isfile(prof_path):
            rep.fail("embedded.mobileprovision is missing (no provisioning profile)")
        else:
            try:
                prof = I.read_profile(prof_path)
            except Exception as e:  # malformed profile: a failure, never a pass
                rep.fail("embedded.mobileprovision is unreadable: %s" % e)
        profile_ents = {}
        if prof is not None:
            pl = prof["plist"]
            profile_ents = pl.get("Entitlements") or {}
            rep.check(prof["signature_valid"], "profile CMS signature is valid",
                      "profile CMS signature is not valid: %s" % prof["signature_error"])
            rep.check("iOS" in (pl.get("Platform") or []), "profile platform is iOS",
                      "profile platform is %s, not iOS" % (pl.get("Platform"),))
            ptype = I.profile_type(pl)
            rep.ev("profile_name", pl.get("Name", ""))
            rep.ev("profile_uuid", pl.get("UUID", ""))
            rep.ev("profile_type", ptype)
            rep.check(ptype == "app-store", "profile type is app-store (no device list, get-task-allow false)",
                      "profile type is '%s', an App Store/TestFlight build needs an app-store profile" % ptype)
            rep.check(team in (pl.get("TeamIdentifier") or []), "profile TeamIdentifier is %s" % team,
                      "profile TeamIdentifier %s does not contain %s" % (pl.get("TeamIdentifier"), team))
            app_ident = profile_ents.get("application-identifier", "")
            rep.check(app_ident == "%s.%s" % (team, bundle_id), "profile App ID is exactly %s.%s" % (team, bundle_id),
                      "profile application-identifier '%s' is not exactly %s.%s (wildcards are refused)" % (app_ident, team, bundle_id))
            exp = pl.get("ExpirationDate")
            if exp is None or not isinstance(exp, datetime.datetime):
                rep.fail("profile has no ExpirationDate")
            else:
                left = (exp - now).total_seconds() / 86400.0
                rep.ev("profile_expires", exp.strftime("%Y-%m-%dT%H:%M:%SZ"))
                rep.ev("profile_days_left", int(left))
                if left <= 0:
                    rep.fail("profile expired on %s" % exp)
                elif left < args.warn_days:
                    rep.warn("profile expires in %d days (%s)" % (int(left), exp))
                    rep.ok("profile is not expired")
                else:
                    rep.ok("profile is valid for %d more days" % int(left))
            if pl.get("ProvisionedDevices"):
                rep.fail("profile lists devices (an ad-hoc/development profile)")

        # ---- main executable signature ----
        main = check_code_signature(rep, "main executable %s" % exe_name, exe_path, app_dir, bundle_id, team, bundle_id, True)
        signer = main["signer"]
        if signer:
            leaf_cn = (signer["subject"].get("CN") or [""])[0]
            issuer_cn = (signer["issuer"].get("CN") or [""])[0]
            rep.ev("signer_subject", dn_text(signer["subject"]))
            rep.ev("signer_issuer", dn_text(signer["issuer"]))
            rep.ev("signer_sha256", signer["sha256"])
            rep.ev("signer_sha1", signer["sha1"])
            rep.ev("signer_not_before", signer["not_before"])
            rep.ev("signer_not_after", signer["not_after"])
            rep.check(any(leaf_cn.startswith(p) for p in args.leaf_prefix), "signing certificate is a distribution certificate (%s)" % leaf_cn,
                      "signing certificate '%s' is not a distribution certificate (%s)" % (leaf_cn, " / ".join(args.leaf_prefix)))
            rep.check(team in signer["subject"].get("OU", []), "signing certificate belongs to Team ID %s" % team,
                      "signing certificate OU %s is not Team ID %s" % (signer["subject"].get("OU"), team))
            rep.check(issuer_cn == args.issuer_cn, "signing certificate issuer NAME is '%s' (a name is not proof: see the pin and the trust anchors)" % issuer_cn,
                      "signing certificate issuer is '%s', expected '%s'" % (issuer_cn, args.issuer_cn))
            marked = [t for t in SYNTHETIC_MARKERS if any(t in v for d in (signer["subject"], signer["issuer"]) for vals in d.values() for v in vals)]
            if marked and (not args.allow_synthetic or env == "production"):
                rep.fail("the signing certificate is a %s identity (%s): not a genuine Apple-issued identity%s"
                         % (marked[0].lower(), dn_text(signer["subject"]), " (never accepted for production)" if env == "production" else ""))
            elif marked:
                rep.warn("accepting a %s identity because --allow-synthetic was given (tests only)" % marked[0].lower())
            if args.trust_anchors:
                extra = [c["der"] for c in (main["cms_certs"] or []) if c["sha256"] != signer["sha256"]]
                probs = I.chain_problems(signer["der"], extra, args.trust_anchors, int(now.replace(tzinfo=datetime.timezone.utc).timestamp()))
                rep.check(not probs, "the signing certificate chains to the supplied trust anchors",
                          "the signing certificate does not chain to the supplied trust anchors: %s" % "; ".join(probs))
                if prof is not None and prof["signer"] is not None:
                    pextra = [c["der"] for c in prof["certs"] if c["sha256"] != prof["signer"]["sha256"]]
                    pprobs = I.chain_problems(prof["signer"]["der"], pextra, args.trust_anchors, int(now.replace(tzinfo=datetime.timezone.utc).timestamp()))
                    rep.check(not pprobs, "the provisioning profile's signer chains to the supplied trust anchors",
                              "the provisioning profile's signer does not chain to the supplied trust anchors: %s" % "; ".join(pprobs))
            else:
                rep.warn("no --trust-anchors: the issuer is checked by name only; a certificate chain to Apple was not verified")
            nb, na = iso_to_dt(signer["not_before"]), iso_to_dt(signer["not_after"])
            rep.check(nb <= now <= na, "signing certificate is valid now (until %s)" % signer["not_after"],
                      "signing certificate is not valid now (%s to %s)" % (signer["not_before"], signer["not_after"]))
            pins = [p.lower() for p in (args.expect_cert_sha256 or [])]
            if pins:
                rep.check(signer["sha256"] in pins, "certificate fingerprint %s is pinned" % signer["sha256"],
                          "certificate fingerprint %s is none of the pinned fingerprints" % signer["sha256"])
            elif env == "production":
                rep.fail("production verification needs --expect-cert-sha256 (the custody register's fingerprint)")
            else:
                rep.warn("certificate fingerprint %s is not pinned (recorded only)" % signer["sha256"])
            if prof is not None:
                listed = [hashlib.sha256(bytes(c)).hexdigest() for c in prof["plist"].get("DeveloperCertificates", [])]
                rep.check(signer["sha256"] in listed, "the profile contains the signing certificate",
                          "the signing certificate is not one of the profile's DeveloperCertificates")

        # ---- entitlements ----
        ents = main["ents"]
        if ents is None:
            rep.fail("the main executable has no embedded entitlements")
        else:
            rep.ev("entitlement_keys", ",".join(sorted(ents)))
            rep.check(ents.get("application-identifier") == "%s.%s" % (team, bundle_id),
                      "entitlement application-identifier is %s.%s" % (team, bundle_id),
                      "entitlement application-identifier is '%s', expected %s.%s" % (ents.get("application-identifier"), team, bundle_id))
            rep.check(ents.get("com.apple.developer.team-identifier") == team, "entitlement team identifier is %s" % team,
                      "entitlement com.apple.developer.team-identifier is '%s', expected %s" % (ents.get("com.apple.developer.team-identifier"), team))
            rep.check(not ents.get("get-task-allow"), "get-task-allow is absent or false (not debuggable)",
                      "get-task-allow is true (a development entitlement)")
            if "aps-environment" in ents:
                rep.check(ents["aps-environment"] == "production", "aps-environment is production",
                          "aps-environment is '%s', an App Store build needs production" % ents["aps-environment"])
            elif "remote-notification" in (info.get("UIBackgroundModes") or []):
                rep.warn("Info.plist declares the remote-notification background mode but the app has no aps-environment entitlement")
            if prof is not None:
                missing = [k for k, v in sorted(ents.items()) if not entitlement_allowed(k, v, profile_ents)]
                rep.check(not missing, "every entitlement is granted by the provisioning profile",
                          "entitlements not granted by the profile: %s" % ", ".join(missing))

        check_nested_and_seals(rep, app_dir, exe_name, bundle_id, team, signer, structure_only=False)

        # ---- provenance ----
        provenance(rep, args, app_dir, env, bundle_id, info, ipa_sha, tmp)

    return finish(rep, args)


def check_nested_and_seals(rep, app_dir, exe_name, bundle_id, team, signer, structure_only):
    """Every nested Mach-O is signed and sealed, the app's CodeResources cover the bundle, and the
    nested cdhashes it lists are the nested code's. With structure_only the Team ID is not judged
    and several signers are reported instead of refused (used to read what Apple's codesign wrote)."""
    macho = [r for r in all_macho(app_dir) if r != exe_name]
    distinct = set() if signer is None else {signer["sha256"]}
    verified_nested = set()
    nested_bundle_dirs = set()
    for rel in macho:
        full = os.path.join(app_dir, rel)
        bundle = os.path.dirname(full)
        has_bundle = os.path.isfile(os.path.join(bundle, "Info.plist")) and bundle != app_dir
        ident = None
        res = check_code_signature(rep, rel, full, bundle if has_bundle else None, bundle_id, team, ident, False)
        if res["signer"] is not None:
            distinct.add(res["signer"]["sha256"])
            if signer is not None and res["signer"]["sha256"] != signer["sha256"] and not structure_only:
                rep.fail("%s is signed by a different certificate than the main executable" % rel)
        if has_bundle:
            nested_bundle_dirs.add(os.path.relpath(bundle, app_dir).replace(os.sep, "/") + "/")
            if not os.path.isfile(os.path.join(bundle, "_CodeSignature", "CodeResources")):
                rep.fail("%s is not sealed (no _CodeSignature/CodeResources)" % os.path.relpath(bundle, app_dir))
            else:
                probs, _n = I.code_resources_problems(bundle, os.path.basename(full))
                for p in probs:
                    rep.fail("%s: %s" % (os.path.relpath(bundle, app_dir), p))
                if not probs:
                    rep.ok("%s: CodeResources match the files" % os.path.relpath(bundle, app_dir))
        verified_nested.add(rel)
    rep.ev("nested_code_count", len(macho))
    rep.info("%d nested Mach-O file(s) checked" % len(macho))

    # ---- the bundle seal ----
    probs, checked = I.code_resources_problems(app_dir, exe_name, tuple(sorted(nested_bundle_dirs)))
    # A nested Mach-O is signed and verified on its own, so "not covered by the app's CodeResources" is
    # tolerated for it; "was modified after signing" (a stale seal) is never tolerated.
    probs = [p for p in probs if not (any(p.startswith(v + " ") for v in verified_nested) and "not covered by CodeResources" in p)]
    for key, want in I.code_resources_cdhashes(app_dir):
        bundle = os.path.join(app_dir, key.rstrip("/"))
        nested_exe = None
        try:
            with open(os.path.join(bundle, "Info.plist"), "rb") as f:
                nested_exe = plistlib.load(f).get("CFBundleExecutable")
        except Exception:
            pass
        got = []
        if nested_exe and os.path.isfile(os.path.join(bundle, nested_exe)):
            for sl in I.read_signature(os.path.join(bundle, nested_exe))["slices"]:
                got += [I.cd_hash(cd, cd["hash_name"]) for _k, cd in sl["cds"]]
        if want not in got:
            probs.append("the app's CodeResources lists a cdhash for %s that is not the nested code's cdhash" % key)
    for p in probs:
        rep.fail("bundle: %s" % p)
    if not probs:
        rep.ok("bundle: CodeResources cover the bundle (%d files hash-checked)" % checked)
    rep.ev("code_resources_files_checked", checked)
    if structure_only:
        rep.info("%d distinct signing certificate(s) across the bundle" % len(distinct))
        rep.ev("distinct_signers", len(distinct))


def provenance(rep, args, app_dir, env, bundle_id, info, ipa_sha, tmp):
    manifest = None
    if args.manifest:
        manifest = BM.read_json(args.manifest)
        if manifest.get("schema") != BM.SCHEMA:
            rep.fail("%s is not a %s manifest" % (args.manifest, BM.SCHEMA))
            manifest = None
    if manifest is not None:
        rep.check(manifest.get("environment") == env, "build manifest environment is %s" % env,
                  "build manifest environment is '%s', not %s" % (manifest.get("environment"), env))
        rep.check(manifest["application"]["id"] == bundle_id, "build manifest application ID matches the IPA",
                  "build manifest application ID '%s' differs from the IPA's '%s'" % (manifest["application"]["id"], bundle_id))
        rep.check(manifest["version"]["platform_version_name"] == info.get("CFBundleShortVersionString") and
                  str(manifest["version"]["platform_build_number"]) == str(info.get("CFBundleVersion")),
                  "build manifest version and build number match the IPA",
                  "build manifest version %s+%s differs from the IPA's %s+%s" % (
                      manifest["version"]["platform_version_name"], manifest["version"]["platform_build_number"],
                      info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")))
        rep.check(manifest["signing"]["status"] == "unsigned", "the manifest describes an unsigned build",
                  "the manifest's signing status is '%s', expected the unsigned build job's manifest" % manifest["signing"]["status"])
        rep.ev("source_commit", manifest["source"]["commit"])
        rep.ev("ci_build_id", manifest["ci"]["build_id"])
        rep.info("built from commit %s, CI build %s" % (manifest["source"]["commit"], manifest["ci"]["build_id"]))
    if args.unsigned_app:
        if not os.path.isdir(args.unsigned_app):
            rep.fail("--unsigned-app %s is not a directory" % args.unsigned_app)
            return
        digest = BM.tree_digest(args.unsigned_app)
        rep.ev("unsigned_app_digest", digest)
        if manifest is not None:
            art = manifest["artifact"]
            rep.check(art.get("digest_kind") == "directory-manifest" and digest == art.get("sha256"),
                      "the unsigned bundle matches the build manifest's digest (%s)" % digest,
                      "the unsigned bundle digest %s differs from the manifest's %s (it is not the artifact that was built)" % (digest, art.get("sha256")))
        same_code_check(rep, args.unsigned_app, app_dir)
    elif manifest is not None:
        rep.warn("no --unsigned-app: whether the IPA is the built code plus signatures only was not checked")


def same_code_check(rep, unsigned, signed):
    def added_ok(r):
        # signing adds the profile at the top and one CodeResources seal per bundle; nothing else
        if r in ("embedded.mobileprovision", "_CodeSignature/CodeResources"):
            return True
        tail = "/_CodeSignature/CodeResources"
        return r.endswith(tail) and os.path.isdir(os.path.join(unsigned, r[:-len(tail)]))
    uf, sf = set(I.bundle_files(unsigned)), set(I.bundle_files(signed))
    missing = sorted(uf - sf)
    extra = sorted(r for r in sf - uf if not added_ok(r))
    changed, same_macho, same_plain = [], 0, 0
    for rel in sorted(uf & sf):
        a, b = os.path.join(unsigned, rel), os.path.join(signed, rel)
        if os.path.islink(a) or os.path.islink(b):
            if not (os.path.islink(a) and os.path.islink(b) and os.readlink(a) == os.readlink(b)):
                changed.append(rel)
            continue
        if I.is_macho(a):
            ok, why = I.same_code(a, b)
            if ok:
                same_macho += 1
            else:
                changed.append("%s (%s)" % (rel, why))
        elif sha256_path(a) == sha256_path(b):
            same_plain += 1
        elif rel.endswith("_CodeSignature/CodeResources"):
            continue
        else:
            changed.append(rel)
    rep.ev("same_code_macho_files", same_macho)
    rep.ev("same_code_other_files", same_plain)
    rep.check(not missing, "no file of the unsigned build is missing from the IPA",
              "files missing from the IPA: %s" % ", ".join(missing[:8]))
    rep.check(not extra, "the IPA adds no file beyond the profile and the signatures",
              "files added to the IPA: %s" % ", ".join(extra[:8]))
    rep.check(not changed, "the IPA is the unsigned build plus signatures only (%d executables identical apart from the signature, %d other files byte-identical)" % (same_macho, same_plain),
              "files that differ from the unsigned build: %s" % "; ".join(changed[:6]))


def finish(rep, args, unverified=True):
    print("")
    if unverified:
        print("NOT VERIFIED by this tool (needs a real Apple-signed IPA, Apple's trust anchors or Apple):")
        for t in NOT_VERIFIED:
            print("  - " + t)
    rep.ev("checks_passed", rep.passed)
    rep.ev("checks_failed", rep.failed)
    rep.ev("checks_warned", rep.warned)
    rep.ev("verified_by", "tool/verify_ipa.py")
    if args.evidence:
        with open(args.evidence, "w", encoding="utf-8") as f:
            for k, v in rep.evidence:
                f.write("%s=%s\n" % (k, v))
    print("")
    if rep.failed:
        print("verify_ipa: %d check(s) FAILED, %d passed, %d warning(s)" % (rep.failed, rep.passed, rep.warned))
        return 1
    print("verify_ipa: all %d checks passed (%d warning(s))" % (rep.passed, rep.warned))
    return 0


# ---- structure ----------------------------------------------------------------------------------


def structure(args):
    """Is the signing STRUCTURE of an app (a Runner.app directory or an .ipa) intact and readable?
    It runs the same signature, entitlement and seal checks as `verify` but judges no identity: no Team
    ID, no certificate policy, no profile. It is for reading what Apple's own codesign wrote (a
    throwaway identity, no Apple account) and comparing the result with Apple's `codesign --verify`."""
    rep = Report()
    print("verify_ipa structure: %s" % os.path.basename(args.target.rstrip("/")))
    with tempfile.TemporaryDirectory(prefix="verify_ipa_") as tmp:
        target = args.target
        if os.path.isfile(target):
            app_dir, extra = extract_ipa(target, tmp)
            if app_dir is None:
                for p in extra:
                    rep.fail("container: %s" % p)
                return finish(rep, args, unverified=False)
        elif os.path.isdir(target):
            app_dir = target
        else:
            die("%s is neither an .ipa nor a directory" % target)
        try:
            with open(os.path.join(app_dir, "Info.plist"), "rb") as f:
                info = plistlib.load(f)
            exe_name, bundle_id = info["CFBundleExecutable"], info["CFBundleIdentifier"]
        except Exception as e:
            rep.fail("Info.plist is unreadable: %s" % e)
            return finish(rep, args, unverified=False)
        if not isinstance(exe_name, str) or not exe_name or "/" in exe_name:
            rep.fail("CFBundleExecutable %r is not a plain file name" % (exe_name,))
            return finish(rep, args, unverified=False)
        main = check_code_signature(rep, "main executable %s" % exe_name, os.path.join(app_dir, exe_name), app_dir,
                                    bundle_id, None, bundle_id, True)
        if main["ents"] is not None:
            rep.info("entitlements: %s" % ", ".join(sorted(main["ents"])))
            rep.ev("entitlement_keys", ",".join(sorted(main["ents"])))
        check_nested_and_seals(rep, app_dir, exe_name, bundle_id, None, main["signer"], structure_only=True)
    return finish(rep, args, unverified=False)


# ---- compare ------------------------------------------------------------------------------------


def compare(args):
    """Is SIGNED (a Runner.app directory or an .ipa) the UNSIGNED bundle plus signatures only?
    This is the check for the signing job: nothing was recompiled, changed or injected."""
    rep = Report()
    if not os.path.isdir(args.unsigned):
        die("%s is not a directory" % args.unsigned)
    print("verify_ipa compare: %s  vs  %s" % (os.path.basename(args.unsigned.rstrip("/")), os.path.basename(args.signed.rstrip("/"))))
    with tempfile.TemporaryDirectory(prefix="verify_ipa_") as tmp:
        signed = args.signed
        if os.path.isfile(signed):
            signed, extra = extract_ipa(signed, tmp)
            if signed is None:
                for p in extra:
                    rep.fail("container: %s" % p)
                return finish(rep, args, unverified=False)
        elif not os.path.isdir(signed):
            die("%s is neither an .ipa nor a directory" % args.signed)
        same_code_check(rep, args.unsigned, signed)
    args.evidence = None
    return finish(rep, args, unverified=False)


# ---- analyze-unsigned --------------------------------------------------------------------------


def analyze_unsigned(args):
    """What re-signing an unsigned `flutter build ios --no-codesign` bundle has to deal with."""
    app = args.app
    plist_path = os.path.join(app, "Info.plist")
    if not os.path.isfile(plist_path):
        die("%s has no Info.plist (pass the Runner.app directory)" % app)
    with open(plist_path, "rb") as f:
        info = plistlib.load(f)
    print("analyze-unsigned: %s" % app)
    print("  bundle id %s, version %s+%s, minimum iOS %s, SDK %s" % (
        info.get("CFBundleIdentifier"), info.get("CFBundleShortVersionString"), info.get("CFBundleVersion"),
        info.get("MinimumOSVersion"), info.get("DTSDKName")))
    unsigned, adhoc, signed_other, other = [], [], [], []
    for rel in all_macho(app):
        sig = I.read_signature(os.path.join(app, rel))
        if sig["error"]:
            other.append((rel, sig["error"]))
            continue
        for s in sig["slices"]:
            if not s["signed"]:
                unsigned.append(rel)
            else:
                cds = [cd for _k, cd in s["cds"]]
                if cds and all(cd["flags"] & I.CS_ADHOC for cd in cds):
                    adhoc.append(rel)
                else:
                    who = ""
                    if s["cms"]:
                        try:
                            c = I.parse_cms(s["cms"])
                            who = dn_text(c["signer"]["subject"]) if c["signer"] else ""
                        except Exception:
                            who = "unreadable"
                    signed_other.append((rel, cds[0]["team_id"] if cds else "", who))
    unsigned, adhoc = sorted(set(unsigned)), sorted(set(adhoc))
    print("  Mach-O files: %d with no signature, %d ad-hoc signed, %d signed by an identity"
          % (len(unsigned), len(adhoc), len(signed_other)))
    for rel in unsigned:
        print("    unsigned   %s" % rel)
    for rel in adhoc:
        print("    ad-hoc     %s (must be re-signed with --force)" % rel)
    for rel, team, who in signed_other:
        print("    signed     %s  team %s  by %s (must be re-signed with --force: App Store builds need ONE identity)" % (rel, team or "-", who))
    for rel, err in other:
        print("    unreadable %s: %s" % (rel, err))
    print("  sealed bundles: %s" % ", ".join(sorted(
        d for d in os.listdir(os.path.join(app, "Frameworks"))
        if os.path.isfile(os.path.join(app, "Frameworks", d, "_CodeSignature", "CodeResources")))) or "none")
    print("  has embedded.mobileprovision: %s; has _CodeSignature: %s" % (
        os.path.exists(os.path.join(app, "embedded.mobileprovision")), os.path.isdir(os.path.join(app, "_CodeSignature"))))
    print("  entitlements file embedded: none (nothing is signed, so none exists)")
    notes = []
    if "ITSAppUsesNonExemptEncryption" not in info:
        notes.append("Info.plist has no ITSAppUsesNonExemptEncryption (export-compliance question at upload)")
    if "remote-notification" in (info.get("UIBackgroundModes") or []):
        notes.append("UIBackgroundModes has remote-notification: the App ID needs the Push Notifications capability "
                     "(aps-environment) or App Store Connect warns")
    privacy = [d for d in os.listdir(os.path.join(app, "Frameworks")) if os.path.isfile(os.path.join(app, "Frameworks", d, "PrivacyInfo.xcprivacy"))]
    if not os.path.isfile(os.path.join(app, "PrivacyInfo.xcprivacy")):
        notes.append("the app has no PrivacyInfo.xcprivacy (frameworks with one: %s)" % (", ".join(privacy) or "none"))
    for n in notes:
        print("  NOTE  " + n)
    return 0


# ---- command line -----------------------------------------------------------------------------


def main(argv):
    ap = argparse.ArgumentParser(prog="verify_ipa.py", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd")
    v = sub.add_parser("verify", help="verify a signed IPA")
    v.add_argument("env", choices=["staging", "production"])
    v.add_argument("ipa")
    v.add_argument("--team-id", required=True)
    v.add_argument("--expect-cert-sha256", action="append", default=[], metavar="HEX")
    v.add_argument("--expect-sha256", metavar="HEX", help="digest of the IPA handed over by the signing job")
    v.add_argument("--issuer-cn", default=DEFAULT_ISSUER_CN)
    v.add_argument("--leaf-prefix", action="append", default=None, help="accepted prefixes of the signing certificate CN")
    v.add_argument("--manifest", help="build manifest (JSON) of the UNSIGNED build")
    v.add_argument("--unsigned-app", help="the unsigned Runner.app directory the manifest describes")
    v.add_argument("--trust-anchors", metavar="PEM", help="trust-anchor certificates (PEM) the signing chain must reach; supplied by the operator")
    v.add_argument("--allow-synthetic", action="store_true", help="tests only: accept a throwaway/synthetic identity (never for production)")
    v.add_argument("--min-sdk", type=int)
    v.add_argument("--warn-days", type=int, default=30)
    v.add_argument("--now", help="UTC time to judge validity at (default now), e.g. 2026-10-22T12:00:00Z")
    v.add_argument("--repo", default=os.path.dirname(HERE))
    v.add_argument("--evidence", help="write text evidence (key=value) here")
    a = sub.add_parser("analyze-unsigned", help="describe what re-signing an unsigned Runner.app involves")
    a.add_argument("app")
    st = sub.add_parser("structure", help="check the signing structure of an app or IPA without judging the identity")
    st.add_argument("target", help="a Runner.app directory or an .ipa")
    st.add_argument("--evidence")
    c = sub.add_parser("compare", help="is SIGNED the UNSIGNED bundle plus signatures only?")
    c.add_argument("unsigned", help="the unsigned Runner.app directory")
    c.add_argument("signed", help="the signed Runner.app directory or the .ipa")
    args = ap.parse_args(argv[1:])
    if args.cmd == "verify":
        if args.leaf_prefix is None:
            args.leaf_prefix = list(LEAF_PREFIXES)
        if not re.match(r"^[A-Z0-9]{10}$", args.team_id):
            die("--team-id must be a 10-character Apple Team ID")
        if args.trust_anchors and not os.path.isfile(args.trust_anchors):
            die("--trust-anchors %s is not a file" % args.trust_anchors)
        try:
            return verify(args)
        except SystemExit:
            raise
        except Exception as e:  # fail closed: an unexpected error is a failed verification, never a pass
            print("  FAIL  internal error while verifying (%s: %s); the IPA is NOT verified" % (type(e).__name__, e))
            print("")
            print("verify_ipa: verification aborted, treated as FAILED")
            return 1
    if args.cmd == "analyze-unsigned":
        return analyze_unsigned(args)
    if args.cmd == "structure":
        try:
            return structure(args)
        except SystemExit:
            raise
        except Exception as e:
            print("  FAIL  internal error while reading the structure (%s: %s)" % (type(e).__name__, e))
            return 1
    if args.cmd == "compare":
        try:
            return compare(args)
        except SystemExit:
            raise
        except Exception as e:
            print("  FAIL  internal error while comparing (%s: %s)" % (type(e).__name__, e))
            return 1
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
