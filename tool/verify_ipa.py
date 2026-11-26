#!/usr/bin/env python3
"""Independent verification of a signed iOS IPA, before anything is uploaded.

  tool/verify_ipa.py verify ENV IPA --team-id TEAM [options]
  tool/verify_ipa.py certificate RUNNER_APP_OR_IPA [--pem FILE] [--team-id TEAM] [--trust-anchors PEM]
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


def emit(text, file=None):
    """Every line this tool writes goes through here. The text may contain things from the IPA being judged (member names,
    property list keys, certificate fields, exception texts): control characters are written as escapes and an absurdly long
    line is cut, so a hostile IPA cannot end a line early, start one with a GitHub workflow command (`::`) or send a
    terminal escape sequence. The checks themselves never see the escaped text."""
    print(I.escape_text(text, limit=I.MAX_LINE_CHARS), file=file if file is not None else sys.stdout)


class Report(object):
    def __init__(self):
        self.failed = 0
        self.passed = 0
        self.warned = 0
        self.evidence = []

    def ok(self, text):
        self.passed += 1
        emit("  PASS  " + text)

    def fail(self, text):
        self.failed += 1
        emit("  FAIL  " + text)

    def warn(self, text):
        self.warned += 1
        emit("  WARN  " + text)

    def info(self, text):
        emit("  INFO  " + text)

    def check(self, cond, ok_text, bad_text):
        (self.ok if cond else self.fail)(ok_text if cond else bad_text)
        return bool(cond)

    def ev(self, key, value):
        # An evidence record is ONE `key=value` line. The key is encoded so that it can hold no `=`, no space and no line break
        # and two different identifiers never share a key; the value has its control characters and its backslashes escaped, so
        # that the escaping is reversible. Fixed keys and ordinary values are unchanged.
        self.evidence.append((I.evidence_key(key), "" if value is None else I.escape_text(value, backslash=True, limit=I.MAX_LINE_CHARS)))


def die(text, code=2):
    emit("verify_ipa: %s" % text, file=sys.stderr)
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


def contained(rep, what, fn, *args):
    """Run an OBSERVATIONAL diagnostic. Whatever it does, the verification outcome is unchanged: an exception inside it is
    reported as "diagnostics unavailable" and nothing else (no counter, no verdict, no earlier finding is touched; the checks that
    already ran have already reported). KeyboardInterrupt and SystemExit are not caught."""
    try:
        fn(*args)
    except Exception as e:
        try:
            rep.info("%s: diagnostics unavailable (%s)" % (what, type(e).__name__))
        except Exception:
            pass


def describe_der_failure(rep, tag, diag):
    """The DER entitlements of one executable could not be read: report what the blob looks like (bounded). STRUCTURE only: its
    size and SHA-256, its header and an ASN.1 outline of classes, tags and lengths; never the bytes and never string content of
    a real IPA (the probe prints those for disposable synthetic input only). INFO lines only: the failure itself was already
    reported and stays a failure."""
    if "error" in diag:
        rep.info("%s: the DER entitlements blob could not be described (%s)" % (tag, diag["error"]))
        return
    rep.info("%s: the DER entitlements blob is %d byte(s), sha256 %s; %s" % (tag, diag["length"], diag["sha256"], diag["header"]))
    for line in diag["outline"]:
        rep.info("%s: DER outline: %s" % (tag, line))
    if not diag.get("raw"):
        rep.info("%s: the bytes of a real IPA's DER blob are not printed" % tag)


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
        if s.get("der_diag"):
            contained(rep, "%s: DER diagnostic" % tag, describe_der_failure, rep, tag, s["der_diag"])
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
        embedded, embedded_err = None, None
        try:
            embedded = I.embedded_info_plist(s["data"], s["macho"])
        except I.MachOError as e:
            embedded_err = str(e)
            result["ok"] = False
            rep.fail("%s: %s" % (tag, embedded_err))
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
            if info and os.path.isfile(info):
                slot_check(I.SLOT_INFO, info, "Info.plist")
            elif embedded_err is None:
                # No Info.plist file: Apple's codesign seals the Mach-O's own `__TEXT,__info_plist` section in slot 1
                # when it has one (and nothing, a zero hash, when it has none). Either way the slot must agree with
                # what is actually there: a section whose hash differs, a section that is not sealed, and a seal with
                # neither a file nor a section are all refused by slot_check.
                slot_check(I.SLOT_INFO, embedded, "Info.plist" if embedded is None else "the embedded Info.plist section")
            res = os.path.join(bundle_dir, "_CodeSignature", "CodeResources") if bundle_dir else None
            slot_check(I.SLOT_RESOURCES, res if res and os.path.isfile(res) else None, "CodeResources")
            slot_check(I.SLOT_REQUIREMENTS, s["requirements_blob"], "the code requirements")
            slot_check(I.SLOT_ENTITLEMENTS, s["entitlements_blob"], "the entitlements")
            slot_check(I.SLOT_DER_ENTITLEMENTS, s["der_entitlements_blob"], "the DER entitlements")
        # ---- what does not depend on the CMS signature: entitlements and the recorded cdhash ----
        # (If the CMS stage below fails, these still run on the data that is present: a failure of one check must not
        # hide the others. Entitlements read from a signature whose CMS did not verify are for diagnosis only, and the
        # run fails anyway: every CMS failure sets result["ok"] = False.)
        if s["entitlements"] is not None:
            # Equal in value AND type, all the way down: Python's == treats True as 1 and 1 as 1.0, and a DER BOOLEAN that
            # the XML declares as an INTEGER (or the reverse) is a real difference for the kernel.
            if s["der_entitlements"] is not None and not I.plist_equal_strict(s["der_entitlements"], s["entitlements"]):
                result["ok"] = False
                rep.fail("%s: the DER entitlements (enforced by the kernel) differ from the XML entitlements" % tag)
            if result["ents"] is None:
                result["ents"] = s["entitlements"]
            elif not I.plist_equal_strict(result["ents"], s["entitlements"]):
                # every slice of a universal executable must carry the same entitlements, in value AND type (the same reason as above)
                result["ok"] = False
                rep.fail("%s: the entitlements differ between architecture slices" % tag)
        elif s["der_entitlements"] is not None:
            result["ok"] = False
            rep.fail("%s has DER entitlements but no XML entitlements" % tag)
        if result["cdhash"] is None and s["cds"]:
            result["cdhash"] = I.cd_hash(s["cds"][0][1], s["cds"][0][1]["hash_name"]).hex()

        # ---- the CMS signature, and the checks that need it ----
        cms = bound = None
        bound_read = False
        if s["cms"] is None:
            result["ok"] = False
            rep.fail("%s has no CMS signature (no signing identity)" % tag)
            rep.warn("%s: NOT CHECKED, there is no CMS signature: its validity, the signer, the digest algorithm and the CodeDirectory binding" % tag)
            continue
        verified = I.cms_verify(s["cms"], detached=s["slots"].get(I.SLOT_CODEDIRECTORY))
        if not verified["ok"]:
            result["ok"] = False
            rep.fail("%s CMS signature is not valid: %s" % (tag, verified["why"]))
        try:
            cms = I.parse_cms(s["cms"])
        except (I.Asn1Error, IndexError, ValueError, KeyError) as e:
            result["ok"] = False
            rep.fail("%s CMS signature is unreadable: %s" % (tag, e))
            rep.warn("%s: NOT CHECKED, the CMS structure is unreadable: the signer, the digest algorithm and the signer's consistency across slices" % tag)
        try:
            bound = I.cms_cdhashes(s["cms"])
            bound_read = True
        except (I.Asn1Error, IndexError, ValueError, KeyError) as e:
            result["ok"] = False
            rep.fail("%s CMS cdhashes attribute is unreadable: %s" % (tag, e))
            rep.warn("%s: NOT CHECKED, the cdhashes attribute is unreadable: that each CodeDirectory is bound by the signature" % tag)
        if cms is not None:
            if verified["ok"] and verified["signer_sha256"] != cms["signer"]["sha256"]:
                result["ok"] = False
                rep.fail("%s: the signer certificate read from the signature is not the one that verified it" % tag)
            if cms["digest_oid"] not in I.OID_SHA256_FAMILY:
                result["ok"] = False
                rep.fail("%s CMS signature uses a digest weaker than SHA-256 (%s)" % (tag, cms["digest_oid"]))
        if bound_read:
            if bound is None:
                result["ok"] = False
                rep.fail("%s CMS signature does not bind the cdhashes" % tag)
            else:
                for key, cd in s["cds"]:
                    if I.cd_hash(cd, cd["hash_name"]) not in bound:
                        result["ok"] = False
                        rep.fail("%s CodeDirectory 0x%x is not bound by the signature (it was replaced)" % (tag, key))
        if cms is None:
            continue
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

    emit("verify_ipa: %s (%s)" % (os.path.basename(args.ipa), env))
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
        except Exception as e:  # any malformed plist is a failure, never a crash and never a pass
            rep.fail("Info.plist is unreadable: %s" % I.plist_failure_text(e))  # never the parser's own text
            return finish(rep, args)
        if not isinstance(info, dict):
            rep.fail("Info.plist is unreadable: it is not a dictionary")
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
            for key in args.forbid_entitlement:
                rep.check(key not in ents, "entitlement %s is absent, as required" % key,
                          "entitlement %s is present (%r) but the release record requires it to be absent" % (key, ents.get(key)))
            for key in sorted(ents):
                rep.ev("entitlement." + key, repr(ents[key]))
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
        # The unsigned build job may have run an older commit's tools (schema 1); every field read below exists in both schemas.
        if manifest.get("schema") not in BM.ACCEPTED_SCHEMAS:
            rep.fail("%s is not a %s manifest" % (args.manifest, " or ".join(BM.ACCEPTED_SCHEMAS)))
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


MAX_PLIST_REPORTS = 3
MAX_PLIST_REPORT_LINES = 40


def describe_plist_differences(rep, differing):
    """For each property list that differs between the unsigned build and the IPA, say HOW it differs: keys added, removed or
    changed (with the value types and sizes), and whether the content is equal in value and type (a difference of serialization
    only). Diagnostics only: the comparison has already failed on these files and stays failed; nothing here excuses a
    difference. A value is shown only for an approved low-risk key (tool/ipa_inspect.py PLIST_DISPLAY_KEYS); for every other
    key only the path, the kind of change, the type and a size are given. A file larger than the cap is not read at all
    beyond the cap, and one that cannot be described is reported as such; a failure here never touches the verdict."""
    for rel, a, b in differing[:MAX_PLIST_REPORTS]:
        contained(rep, "%s: description of the difference" % rel, describe_one_plist, rep, rel, a, b)
    if len(differing) > MAX_PLIST_REPORTS:
        rep.info("%d further property list(s) differ and are not described" % (len(differing) - MAX_PLIST_REPORTS))


def describe_one_plist(rep, rel, a, b):
    try:
        old = I.read_capped(a, I.MAX_PLIST_DIFF_BYTES)
        new = I.read_capped(b, I.MAX_PLIST_DIFF_BYTES)
    except OSError as e:
        rep.info("%s: cannot be read for a description of the difference: %s" % (rel, type(e).__name__))
        return
    key = "plist_difference_" + rel
    if old is None or new is None:
        rep.info("%s differs from the unsigned build; a file is larger than %d bytes and is not described" % (rel, I.MAX_PLIST_DIFF_BYTES))
        rep.ev(key, "not_described_too_large")
        return
    d = I.plist_difference(old, new)
    head = "%s differs from the unsigned build: %d byte(s) -> %d byte(s)" % (rel, len(old), len(new))
    if not d["readable"]:
        rep.info("%s; not readable as a property list (%s)" % (head, d["error"]))
        rep.ev(key, "unreadable")
        return
    verdict = ("same content in value and type, different serialization only (%s -> %s)" % (d["old_format"], d["new_format"])
               if d["serialization_only"] else
               "DIFFERENT CONTENT: %d added, %d removed, %d changed (%s -> %s)" % (d["counts"]["added"], d["counts"]["removed"], d["counts"]["changed"], d["old_format"], d["new_format"]))
    rep.info("%s; %s" % (head, verdict))
    lines = []
    for kind, items in (("added", d["added"]), ("removed", d["removed"]), ("changed", d["changed"])):
        for path, what, old_v, new_v in items:
            label = " [identity, version, platform or privilege key]" if I.plist_sensitive(path) else ""
            shown = I.escape_text(path, backslash=True, limit=I.PLIST_PATH_LIMIT)
            if kind == "added":
                lines.append("+ %s (%s) = %s%s" % (shown, what, new_v, label))
            elif kind == "removed":
                lines.append("- %s (%s) was %s%s" % (shown, what, old_v, label))
            else:
                lines.append("~ %s (%s): %s -> %s%s" % (shown, what, old_v, new_v, label))
    for line in lines[:MAX_PLIST_REPORT_LINES]:
        rep.info("%s: %s" % (rel, line))
    total = d["counts"]["added"] + d["counts"]["removed"] + d["counts"]["changed"]
    shown = min(len(lines), MAX_PLIST_REPORT_LINES)
    incomplete = shown < total
    if incomplete:
        # the totals above are exact; the listing is not complete
        rep.info("%s: LISTING INCOMPLETE: %d of %d differences listed" % (rel, shown, total))
    # the counts are exact totals; only the listing is cut, which is said apart from them
    rep.ev(key, "serialization_only" if d["serialization_only"] else
           "added=%d removed=%d changed=%d%s" % (d["counts"]["added"], d["counts"]["removed"], d["counts"]["changed"],
                                                 " listing_incomplete=1" if incomplete else ""))


def info_plist_reserialization(a, b):
    """The two top-level Info.plist FILES (unsigned, signed) -> ((digest, digest, length, length) or None, why). Reads at most the cap
    plus one byte of each; anything unreadable, larger, or refused by ipa_inspect.info_plist_reserialized_only is a refusal."""
    try:
        old = I.read_capped(a, I.INFO_PLIST_RESERIALIZE_MAX_BYTES)
        new = I.read_capped(b, I.INFO_PLIST_RESERIALIZE_MAX_BYTES)
        if old is None or new is None:
            return None, "a file is larger than %d bytes" % I.INFO_PLIST_RESERIALIZE_MAX_BYTES
        ok, why = I.info_plist_reserialized_only(old, new)
        if not ok:
            return None, why
        return (hashlib.sha256(old).hexdigest(), hashlib.sha256(new).hexdigest(), len(old), len(new)), ""
    except Exception as e:  # a VERDICT path, unlike the diagnostics: whatever goes wrong is a refusal (KeyboardInterrupt is not caught)
        return None, "the files could not be compared (%s)" % type(e).__name__


def same_code_check(rep, unsigned, signed):
    """V8: is `signed` the unsigned build plus signatures only? Every file is compared byte for byte (Mach-O files with the signature
    excluded), with ONE exception: the app's TOP-LEVEL Info.plist, which may differ in serialization only (see
    ipa_inspect.info_plist_reserialized_only for the exact rule and its residual risks; nested and framework Info.plist files, every
    other property list and every other resource stay byte-strict).

    For that one file V8 therefore settles SEMANTIC equality (content and types), not bytewise immutability: bytes the content does not reach may differ.

    THIS FUNCTION AUTHENTICATES NO SIGNATURE. That the signed Info.plist is the file Apple's signature seals (the CodeDirectory's slot-1
    seal, and the CMS signature over that CodeDirectory) is checked by `verify` (check_code_signature), never here. The `compare` command, which
    calls this function alone, says so on every invocation."""
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
    reserialized, refused_reserialization = None, None  # the top-level Info.plist: (unsigned digest, signed digest, lengths) / why not
    differing_plists = []  # (relative path, unsigned file, signed file): described below, never excused
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
        elif rel == "embedded.mobileprovision":
            # A baseline taken from a signed archive (Xcode's automatic signing embeds a development
            # profile there) legitimately gets the distribution profile at export. The profile is
            # judged on its own by `verify`; it is never part of the code.
            continue
        else:
            if rel == "Info.plist":  # the TOP-LEVEL file only; nested Info.plist files are named like "PlugIns/X.appex/Info.plist"
                accepted, why = info_plist_reserialization(a, b)
                if accepted:
                    reserialized = accepted
                    continue
                refused_reserialization = why
            changed.append(rel)
            if rel.endswith(".plist"):
                differing_plists.append((rel, a, b))
    rep.ev("same_code_macho_files", same_macho)
    rep.ev("same_code_other_files", same_plain)
    rep.check(not missing, "no file of the unsigned build is missing from the IPA",
              "files missing from the IPA: %s" % ", ".join(missing[:8]))
    rep.check(not extra, "the IPA adds no file beyond the profile and the signatures",
              "files added to the IPA: %s" % ", ".join(extra[:8]))
    rep.check(not changed, "the IPA is the unsigned build plus signatures only (%d executables identical apart from the signature, %d other files byte-identical%s)" % (
                  same_macho, same_plain, ", and the top-level Info.plist re-serialized with identical content and types" if reserialized else ""),
              "files that differ from the unsigned build: %s" % "; ".join(changed[:6]))
    describe_plist_differences(rep, differing_plists)
    if reserialized:
        rep.ev("same_code_info_plist", "reserialized_identical_content_and_types")
        rep.ev("same_code_info_plist_sha256", "unsigned %s signed %s" % (reserialized[0], reserialized[1]))
        rep.info("Info.plist: the top-level file differs from the unsigned build in SERIALIZATION ONLY and is accepted: binary property list, "
                 "%d byte(s) -> %d byte(s), SHA-256 %s -> %s, identical keys, values and types: equal in content, NOT byte for byte (docs/IOS_SIGNING.md section 3.1e)" % (reserialized[2], reserialized[3], reserialized[0], reserialized[1]))
    elif refused_reserialization:
        rep.info("Info.plist: not accepted as a re-serialization (%s); it stays a failure" % refused_reserialization)


def finish(rep, args, unverified=True):
    emit("")
    if unverified:
        emit("NOT VERIFIED by this tool (needs a real Apple-signed IPA, Apple's trust anchors or Apple):")
        for t in NOT_VERIFIED:
            emit("  - " + t)
    rep.ev("checks_passed", rep.passed)
    rep.ev("checks_failed", rep.failed)
    rep.ev("checks_warned", rep.warned)
    rep.ev("verified_by", "tool/verify_ipa.py")
    if args.evidence:
        with open(args.evidence, "w", encoding="utf-8") as f:
            for k, v in rep.evidence:
                f.write("%s=%s\n" % (k, v))
    emit("")
    if rep.failed:
        emit("verify_ipa: %d check(s) FAILED, %d passed, %d warning(s)" % (rep.failed, rep.passed, rep.warned))
        return 1
    emit("verify_ipa: all %d checks passed (%d warning(s))" % (rep.passed, rep.warned))
    return 0


# ---- certificate -------------------------------------------------------------------------------


def pem_of(der):
    import base64
    b = base64.b64encode(der).decode("ascii")
    return "-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n" % "\n".join(b[i:i + 64] for i in range(0, len(b), 64))


def certificate(args):
    """Collect the PUBLIC signing certificate of an Apple-signed app or IPA, with its SHA-256 fingerprint.

    This is how the fingerprint of a cloud-managed distribution certificate (which exists in no local
    keychain, so `security find-certificate` cannot show it) is read from the signed artifact itself. It
    judges nothing and pins nothing: it reports who signed, whether every executable agrees, and what the
    embedded profile says, so that the fingerprint can be recorded and later pinned with
    `verify --expect-cert-sha256`. It reads public data only; no private key exists in an IPA."""
    rep = Report()
    emit("verify_ipa certificate: %s" % os.path.basename(args.target.rstrip("/")))
    with tempfile.TemporaryDirectory(prefix="verify_ipa_") as tmp:
        target = args.target
        if os.path.isfile(target):
            rep.ev("ipa_sha256", sha256_path(target))
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
            exe_name = info["CFBundleExecutable"]
        except Exception as e:
            rep.fail("Info.plist is unreadable: %s" % I.plist_failure_text(e))  # never the parser's own text
            return finish(rep, args, unverified=False)
        if not isinstance(exe_name, str) or not exe_name or "/" in exe_name or exe_name.startswith("."):
            rep.fail("CFBundleExecutable %r is not a plain file name" % (exe_name,))
            return finish(rep, args, unverified=False)
        rep.ev("bundle_id", info.get("CFBundleIdentifier", ""))
        rep.ev("version_name", info.get("CFBundleShortVersionString", ""))
        rep.ev("version_code", info.get("CFBundleVersion", ""))

        signers, main_signer, main_certs = {}, None, None
        files = [exe_name] + [r for r in all_macho(app_dir) if r != exe_name]
        for rel in files:
            path = os.path.join(app_dir, rel)
            if not os.path.isfile(path):
                rep.fail("executable '%s' is missing" % rel)
                continue
            sig = I.read_signature(path)
            if sig["error"] or not sig["slices"]:
                rep.fail("%s: %s" % (rel, sig["error"] or "no architecture slice"))
                continue
            for s in sig["slices"]:
                if not s["signed"] or s["cms"] is None:
                    rep.fail("%s is not signed by an identity (no CMS signature)" % rel)
                    continue
                try:
                    cms = I.parse_cms(s["cms"])
                except (I.Asn1Error, IndexError, ValueError, KeyError) as e:
                    rep.fail("%s: the signature is unreadable: %s" % (rel, e))
                    continue
                if cms["signer"] is None:
                    rep.fail("%s: the signature carries no signer certificate" % rel)
                    continue
                v = I.cms_verify(s["cms"], detached=s["slots"].get(I.SLOT_CODEDIRECTORY))
                if not v["ok"] or v["signer_sha256"] != cms["signer"]["sha256"]:
                    rep.fail("%s: the CMS signature is not valid (%s)" % (rel, v["why"] or "signer mismatch"))
                    continue
                signers.setdefault(cms["signer"]["sha256"], (cms["signer"], []))[1].append(rel)
                if rel == exe_name and main_signer is None:
                    main_signer, main_certs = cms["signer"], cms["certs"]
        if main_signer is None:
            rep.fail("the main executable has no verifiable signing certificate")
            return finish(rep, args, unverified=False)

        sg = main_signer
        for k, v in (("subject", dn_text(sg["subject"])), ("issuer", dn_text(sg["issuer"])), ("serial", sg["serial"]),
                     ("not_before", sg["not_before"]), ("not_after", sg["not_after"]),
                     ("sha256", sg["sha256"]), ("sha1", sg["sha1"])):
            emit("  %-10s %s" % (k, v))
            rep.ev("signer_" + k, v)
        rep.check(len(signers) == 1, "all %d signed executable(s) carry this one certificate" % sum(len(v[1]) for v in signers.values()),
                  "the bundle is signed by %d different certificates (an App Store build needs one): %s" % (
                      len(signers), "; ".join("%s: %d file(s)" % (h[:16], len(v[1])) for h, v in sorted(signers.items()))))
        leaf_cn = (sg["subject"].get("CN") or [""])[0]
        prefixes = args.leaf_prefix or list(LEAF_PREFIXES)
        rep.check(any(leaf_cn.startswith(p) for p in prefixes), "the certificate's name is a distribution certificate (%s)" % leaf_cn,
                  "the certificate '%s' is not named as a distribution certificate (%s)" % (leaf_cn, " / ".join(prefixes)))
        marked = [t for t in SYNTHETIC_MARKERS if any(t in v for d in (sg["subject"], sg["issuer"]) for vals in d.values() for v in vals)]
        if marked and not args.allow_synthetic:
            rep.fail("the certificate is a %s identity, not a genuine Apple-issued one" % marked[0].lower())
        elif marked:
            rep.warn("accepting a %s identity because --allow-synthetic was given (tests only)" % marked[0].lower())
        if args.team_id:
            rep.check(args.team_id in sg["subject"].get("OU", []), "the certificate belongs to Team ID %s" % args.team_id,
                      "the certificate's OU %s is not Team ID %s" % (sg["subject"].get("OU"), args.team_id))
        prof_path = os.path.join(app_dir, "embedded.mobileprovision")
        if os.path.isfile(prof_path):
            try:
                prof = I.read_profile(prof_path)
                listed = [hashlib.sha256(bytes(c)).hexdigest() for c in prof["plist"].get("DeveloperCertificates", [])]
                rep.ev("profile_type", I.profile_type(prof["plist"]))
                rep.info("embedded profile: '%s', type %s, lists %d certificate(s)" % (
                    prof["plist"].get("Name", ""), I.profile_type(prof["plist"]), len(listed)))
                rep.check(prof["signature_valid"], "the profile's CMS signature is valid",
                          "the profile's CMS signature is not valid: %s" % prof["signature_error"])
                rep.check(sg["sha256"] in listed, "the embedded profile lists this certificate",
                          "the profile does not list this certificate")
            except Exception as e:
                rep.fail("embedded.mobileprovision is unreadable: %s" % e)
        else:
            rep.warn("no embedded.mobileprovision: the profile's listing of the certificate could not be compared")
        if args.trust_anchors:
            extra = [c["der"] for c in (main_certs or []) if c["sha256"] != sg["sha256"]]
            probs = I.chain_problems(sg["der"], extra, args.trust_anchors,
                                     int(parse_now(args.now).replace(tzinfo=datetime.timezone.utc).timestamp()))
            rep.check(not probs, "the certificate chains to the supplied trust anchors",
                      "the certificate does not chain to the supplied trust anchors: %s" % "; ".join(probs))
        else:
            rep.warn("no --trust-anchors: nothing here shows the certificate chains to an Apple root")
        rep.warn("revocation is never checked (no OCSP/CRL lookup): a revoked certificate would look the same here")
        if args.pem:
            with open(args.pem, "w", encoding="ascii") as f:
                f.write(pem_of(sg["der"]))
            rep.info("wrote the PUBLIC certificate to %s" % args.pem)
        emit("")
        if not rep.failed:
            emit("RECORD (a public value; the pin for `verify --expect-cert-sha256`): %s" % sg["sha256"])
            emit("This command pins and approves nothing: a fingerprint read from the artifact it will later")
            emit("judge is evidence only after the release coordinator has recorded it and it agrees with an")
            emit("independent source (trust anchors, the profile, the Apple account).")
        else:
            emit("Nothing to record: the checks above failed.")
    return finish(rep, args, unverified=False)


# ---- structure ----------------------------------------------------------------------------------


def structure(args):
    """Is the signing STRUCTURE of an app (a Runner.app directory or an .ipa) intact and readable?
    It runs the same signature, entitlement and seal checks as `verify` but judges no identity: no Team
    ID, no certificate policy, no profile. It is for reading what Apple's own codesign wrote (a
    throwaway identity, no Apple account) and comparing the result with Apple's `codesign --verify`."""
    rep = Report()
    emit("verify_ipa structure: %s" % os.path.basename(args.target.rstrip("/")))
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
            rep.fail("Info.plist is unreadable: %s" % I.plist_failure_text(e))  # never the parser's own text
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


COMPARE_NOTICE = ("NOTE  compare authenticates NO signature: it reads no CodeDirectory, no seal and no CMS signature (`verify` does). "
                  "Never accept an IPA on `compare` alone.")


def compare(args):
    """Is SIGNED (a Runner.app directory or an .ipa) the UNSIGNED bundle plus signatures only?
    This is the check for the signing job: nothing was recompiled, changed or injected.

    `compare` AUTHENTICATES NO SIGNATURE: it does not read a CodeDirectory, a seal or a CMS signature, and it says so (COMPARE_NOTICE) on every
    invocation. The signed top-level Info.plist may differ from the unsigned one in serialization only (same_code_check: equal content, not equal
    bytes); that it is the file Apple's signature seals is checked by `verify`. Never accept an IPA on `compare` alone."""
    # Said on EVERY invocation, whatever the outcome, before anything can fail: this command reads no signature at all.
    emit(COMPARE_NOTICE)
    sys.stdout.flush()  # before any error can be written to the other stream
    rep = Report()
    if not os.path.isdir(args.unsigned):
        die("%s is not a directory" % args.unsigned)
    emit("verify_ipa compare: %s  vs  %s" % (os.path.basename(args.unsigned.rstrip("/")), os.path.basename(args.signed.rstrip("/"))))
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
    emit("analyze-unsigned: %s" % app)
    emit("  bundle id %s, version %s+%s, minimum iOS %s, SDK %s" % (
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
    emit("  Mach-O files: %d with no signature, %d ad-hoc signed, %d signed by an identity"
          % (len(unsigned), len(adhoc), len(signed_other)))
    for rel in unsigned:
        emit("    unsigned   %s" % rel)
    for rel in adhoc:
        emit("    ad-hoc     %s (must be re-signed with --force)" % rel)
    for rel, team, who in signed_other:
        emit("    signed     %s  team %s  by %s (must be re-signed with --force: App Store builds need ONE identity)" % (rel, team or "-", who))
    for rel, err in other:
        emit("    unreadable %s: %s" % (rel, err))
    emit("  sealed bundles: %s" % ", ".join(sorted(
        d for d in os.listdir(os.path.join(app, "Frameworks"))
        if os.path.isfile(os.path.join(app, "Frameworks", d, "_CodeSignature", "CodeResources")))) or "none")
    emit("  has embedded.mobileprovision: %s; has _CodeSignature: %s" % (
        os.path.exists(os.path.join(app, "embedded.mobileprovision")), os.path.isdir(os.path.join(app, "_CodeSignature"))))
    emit("  entitlements file embedded: none (nothing is signed, so none exists)")
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
        emit("  NOTE  " + n)
    return 0


# ---- command line -----------------------------------------------------------------------------


# ---- capture-evidence (Phase 7C, Issue #71): READ-ONLY evidence for V8 and for the Distribution DER blob ------------------------------
# What it is for. The first Apple-signed IPA (run 44834801248) failed V8 because its top-level Info.plist differed from the archive's, and
# neither the IPA nor its Info.plist was kept, so the difference is still unknown. This subcommand makes the NEXT signing run keep what
# is needed to find out: the two Info.plist files (exact bytes, as base64 text), their sizes and digests, how they differ, and whether the
# CodeDirectory's slot-1 seal matches each; and the DER entitlements blob of the Distribution-signed executable (exact bytes, as hex).
# What it is not. It decides nothing: V7 and V8 keep their rules and their verdicts, this runs apart from them, and a difference between the
# two files is NOT a failure of the capture. It never retains the IPA, a profile or any credential; it reads the IPA by path and writes only
# text under --out. Everything it keeps is judged by ipa_inspect.evidence_unsafe_reason on the DECODED bytes first (base64 is an encoding,
# not sanitisation): content that fails is not kept, and the reason (the KIND of material, never the material) is recorded instead.
# The log gets counts, digests and file names only, never a property list value.
CAPTURE_MEMBER_RE = re.compile(r"^Payload/([^/]+)\.app/Info\.plist$")
CAPTURE_EXE_CAP = 256 << 20


def _cap_kv(path, limit=65536):
    """key=value lines of a small evidence file; {} when it is missing or unreadable."""
    out = {}
    try:
        with open(path, "rb") as f:
            text = f.read(limit).decode("utf-8", "replace")
    except OSError:
        return out
    for line in text.splitlines():
        if "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip()
    return out


def _cap_write(out_dir, name, text):
    """Write one evidence file. A LINE that would trip the evidence seal is replaced by a note, so that the seal can never be made to
    delete ALL the evidence by one hostile string (the note names the kind of material, not the material)."""
    kept = []
    for line in text.splitlines():
        why = I.evidence_unsafe_reason(line)
        kept.append("[line withheld: it contained %s]" % why if why else line)
    with open(os.path.join(out_dir, name), "w", encoding="utf-8") as f:
        f.write("\n".join(kept) + "\n")


def _cap_esc(value, limit=120):
    return I.escape_text(str(value), backslash=True, limit=limit)


def _cap_read_member(zf, info, cap):
    if info.file_size > cap:
        return None, "larger than %d bytes (%d)" % (cap, info.file_size)
    with zf.open(info) as f:
        data = f.read(cap + 1)
    if len(data) > cap:
        return None, "larger than %d bytes" % cap
    return data, None


def _cap_file_facts(label, data, show_keys):
    """Lines that describe one property list file (bytes in, text out; no values). Its top-level key NAMES are listed only when the file's
    bytes may be kept (`show_keys`): for a file that is withheld, whatever the reason, no content of it is shown in any form."""
    lines = ["%s: size=%d bytes" % (label, len(data)), "%s: sha256=%s" % (label, hashlib.sha256(data).hexdigest()),
             "%s: sha1=%s" % (label, hashlib.sha1(data).hexdigest()), "%s: container_format=%s" % (label, I.plist_container_format(data))]
    st = I.bplist_structure(data)
    if st is not None:
        lines.append("%s: bplist version/sort=%d offset_int_size=%d object_ref_size=%d num_objects=%d top_object=%d offset_table_offset=%d trailer_consistent=%s"
                     % (label, st["sort_version"], st["offset_int_size"], st["object_ref_size"], st["num_objects"], st["top_object"],
                        st["offset_table_offset"], "yes" if st["consistent"] else "NO"))
    keys = I.plist_top_keys(data) if show_keys else None
    if not show_keys:
        lines.append("%s: top-level keys not listed: the bytes of this file are withheld, so nothing of its content is shown" % label)
    elif keys is None:
        lines.append("%s: top-level keys: not readable as a property list dictionary" % label)
    else:
        shown = ", ".join(_cap_esc(k, 60) for k in keys[:I.EVIDENCE_KEY_LIST_MAX])
        lines.append("%s: top-level keys (%d, in file order): %s%s" % (label, len(keys), shown, " ..." if len(keys) > I.EVIDENCE_KEY_LIST_MAX else ""))
    return lines


def _cap_plist_retention(data):
    """(reason, kept) for a property list: reason is None when its bytes may be kept, otherwise why not (the KIND of problem); `kept` is the
    status word. One decision, used everywhere, so that what may be SHOWN about a file is exactly what may be KEPT of it."""
    if len(data) > I.EVIDENCE_PLIST_MAX_BYTES:
        return "larger than %d bytes" % I.EVIDENCE_PLIST_MAX_BYTES, "withheld: too large"
    unsafe = I.plist_evidence_unsafe_reason(data)
    return ("the content has %s" % unsafe, "withheld: " + unsafe) if unsafe else (None, "kept")


def _cap_seal_lines(label, cds, data, slot, slot_name):
    """For each CodeDirectory: the sealed hash of `slot`, the hash of `data` under that CodeDirectory's algorithm, and whether they agree."""
    lines = []
    for key, cd in cds:
        want = I.slot_hash(cd, slot)
        got = hash_with(cd, data) if data is not None else None
        verdict = "n/a" if got is None else ("no seal in this CodeDirectory" if want is None else ("MATCH" if want == got else "DIFFERENT"))
        lines.append("seal: CodeDirectory 0x%x (%s): %s slot %d sealed=%s %s=%s -> %s" % (
            key, cd["hash_name"], slot_name, slot, want.hex() if want else "none", label, got.hex() if got else "none", verdict))
    return lines


def capture_evidence(args):
    out_dir, ev_dir = args.out, args.evidence_dir
    os.makedirs(out_dir, exist_ok=True)
    problems = []
    prov = []
    src, arch, res, xc = (_cap_kv(os.path.join(ev_dir, n)) for n in ("source.txt", "archive.txt", "export-result.txt", "xcode.txt"))
    for label, d, keys in (("source", src, ("approved_sha", "tools_commit", "workflow_blob", "run")), ("archive", arch, ("archive_tar_sha256", "archive_app_files")),
                           ("export", res, ("xcodebuild_exportArchive_exit", "ipa_sha256_after_export", "ipa_size")), ("xcode", xc, ("xcode",))):
        for k in keys:
            prov.append("provenance: %s %s=%s" % (label, k, _cap_esc(d.get(k, "(absent)"))))
    prov.append("provenance: this run id=%s attempt=%s, tools commit=%s" % (_cap_esc(args.run_id or "(not given)"), _cap_esc(args.run_attempt or "(not given)"), _cap_esc(args.tools_sha or "(not given)")))
    for n in ("ExportOptions-used.txt", "archive-app.sha256"):
        p = os.path.join(ev_dir, n)
        prov.append("provenance: %s sha256=%s" % (n, sha256_path(p) if os.path.isfile(p) else "(absent)"))

    # ---- which situation is this? (decided from the export evidence, never guessed)
    if "xcodebuild_exportArchive_exit" not in res:
        state = "export-not-reached"
    elif res["xcodebuild_exportArchive_exit"] != "0":
        state = "export-failed"
    else:
        state = "export-succeeded"
    ipa = args.ipa or ""
    if state == "export-succeeded" and not (ipa and os.path.isfile(ipa)):
        state = "ipa-missing-after-export"
        problems.append("the export reported success but there is no IPA to read (a diagnostic failure, not a skip)")

    # ---- the archive's Info.plist (the V8 baseline)
    archive_plist, archive_why = None, None
    if args.archive_app:
        ap_path = os.path.join(args.archive_app, "Info.plist")
        try:
            with open(ap_path, "rb") as f:
                archive_plist = f.read(I.EVIDENCE_READ_CAP + 1)
            if len(archive_plist) > I.EVIDENCE_READ_CAP:
                archive_plist, archive_why = None, "larger than %d bytes" % I.EVIDENCE_READ_CAP
        except OSError as e:
            archive_why = "cannot be read (%s)" % type(e).__name__
    else:
        archive_why = "no archive app was given"
    if archive_plist is None and state in ("export-succeeded", "ipa-missing-after-export"):
        problems.append("the archived Info.plist is unavailable: %s" % archive_why)

    # ---- the IPA's Info.plist and the main executable
    ipa_plist, ipa_why, exe_bytes, exe_name, app_name, exe_note, names_ok = None, None, None, None, None, None, False
    ipa_sha = None
    if state == "export-succeeded":
        try:
            ipa_sha = sha256_path(ipa)
            if res.get("ipa_sha256_after_export") and res["ipa_sha256_after_export"] != ipa_sha:
                problems.append("the IPA's SHA-256 differs from the one recorded right after the export")
            with zipfile.ZipFile(ipa) as zf:
                cands = [i for i in zf.infolist() if CAPTURE_MEMBER_RE.match(i.filename)]
                if len(cands) != 1:
                    ipa_why = "the IPA holds %d top-level Info.plist member(s), expected exactly 1" % len(cands)
                else:
                    app_name = CAPTURE_MEMBER_RE.match(cands[0].filename).group(1)
                    ipa_plist, ipa_why = _cap_read_member(zf, cands[0], I.EVIDENCE_READ_CAP)
                    exe = None
                    if ipa_plist is not None:
                        try:
                            exe, _fmt = I.read_plist_exact(ipa_plist)
                            exe = exe.get("CFBundleExecutable") if isinstance(exe, dict) else None
                        except ValueError:
                            exe = None
                    # CFBundleExecutable is a VALUE of the exported Info.plist. It is used to find the executable, but it may be NAMED in an
                    # output (der-summary.txt, status.txt, the log) only if that plist may be kept: for a withheld plist it is untrusted, and a
                    # confidential value must not leave through a diagnostic that the pattern scan would not recognise (Phase 7C-R2).
                    names_ok = ipa_plist is not None and _cap_plist_retention(ipa_plist)[0] is None
                    exe_name = exe if isinstance(exe, str) and exe and "/" not in exe and not exe.startswith(".") else app_name
                    try:
                        exe_info = zf.getinfo("Payload/%s.app/%s" % (app_name, exe_name))
                        exe_bytes, exe_why = _cap_read_member(zf, exe_info, CAPTURE_EXE_CAP)
                    except KeyError:
                        exe_why = "the IPA has no executable named %r" % exe_name if names_ok else "no executable was found under the name the exported Info.plist gives (the name is not shown: that file is withheld)"
                    if exe_bytes is None:
                        exe_note = "the exported executable could not be located: %s" % _cap_esc(exe_why)
        except (OSError, zipfile.BadZipFile, ValueError, RuntimeError) as e:
            ipa_why = "the IPA cannot be read (%s)" % type(e).__name__
        if ipa_plist is None:
            problems.append("the exported Info.plist is unavailable: %s" % _cap_esc(ipa_why))
    elif state == "export-failed":
        ipa_why = "the export failed (exit %s): there is no exported file, and none is invented" % _cap_esc(res.get("xcodebuild_exportArchive_exit"))
    elif state == "export-not-reached":
        ipa_why = "the export step did not run, so there is no exported file"

    # ---- the Info.plist evidence
    # A file is RETAINABLE only if it is within the size bound and passes ipa_inspect.plist_evidence_unsafe_reason (raw bytes with UTF-16 views,
    # every parsed key and string, binary data values; a file that cannot be inspected is not retainable). Nothing derived from a file that is
    # not retainable is shown in ANY form, hex and base64 included: no byte window, no key name, no value, no key-difference line. Sizes,
    # digests, formats, counts, offsets as numbers and the reason are safe metadata and stay.
    info_lines = ["Info.plist evidence (Phase 7C). Exact bytes are kept as base64 text only when the content passes the safety check.", ""] + prov + [""]
    kept, retainable = {}, {}
    for label, data, why in (("archive", archive_plist, archive_why), ("ipa", ipa_plist, ipa_why)):
        if data is None:
            info_lines.append("%s: Info.plist not captured: %s" % (label, _cap_esc(why)))
            kept[label] = "absent"
            retainable[label] = False
            continue
        reason, kept[label] = _cap_plist_retention(data)
        retainable[label] = reason is None
        info_lines.extend(_cap_file_facts(label, data, retainable[label]))
        if reason is not None:
            info_lines.append("%s: bytes NOT kept: %s" % (label, reason))
            continue
        _cap_write(out_dir, "%s-Info.plist.b64" % label, I.b64_lines(data))
        info_lines.append("%s: bytes kept as %s-Info.plist.b64 (base64 of the exact file)" % (label, label))
    if archive_plist is not None and ipa_plist is not None:
        detail = retainable["archive"] and retainable["ipa"]
        fd = I.first_difference(archive_plist, ipa_plist)
        info_lines += ["", "comparison (archive -> ipa):", "bytes_identical=%s equal_length=%s" % ("yes" if fd["identical"] else "NO", "yes" if fd["equal_length"] else "NO")]
        if not detail:
            info_lines.append("detail withheld: at least one of the two files is not retainable, so no byte window, key name, value or key-difference line is shown; only counts, offsets and flags")
        if fd["offset"] is not None:
            info_lines.append("first_differing_byte_offset=%d differing_bytes=%d%s" % (fd["offset"], fd["differing_bytes"], " window_start=%d" % fd["window_start"] if detail else ""))
            if detail:
                info_lines.append("window archive (hex): %s" % fd["window_a"])
                info_lines.append("window ipa     (hex): %s" % fd["window_b"])
        d = I.plist_difference(archive_plist, ipa_plist)
        if not d["readable"]:
            info_lines.append("typed comparison: not possible (%s)" % (_cap_esc(d["error"]) if detail else "a file is not readable as a property list"))
        else:
            tc = [c for c in d["changed"] if " -> " in c[1] and not c[1].startswith("array of")]
            info_lines.append("typed comparison (every key, value AND type): semantic=%s serialization_only=%s" % (d["semantic"], "yes" if d["serialization_only"] else "no"))
            info_lines.append("formats: %s -> %s; added=%d removed=%d changed=%d (of which type-changed=%d%s)" % (
                d["old_format"], d["new_format"], d["counts"]["added"], d["counts"]["removed"], d["counts"]["changed"], len(tc),
                "; listing truncated" if d["truncated"] else ""))
            if detail:
                for kind, items in (("added", d["added"]), ("removed", d["removed"]), ("changed", d["changed"])):
                    for path, what, old_v, new_v in items[:I.EVIDENCE_KEY_LIST_MAX]:
                        info_lines.append("%s: %s (%s) %s%s" % (kind, _cap_esc(path, 100), _cap_esc(what, 60),
                                                               "" if old_v is None else "old=%s " % _cap_esc(old_v, 100), "" if new_v is None else "new=%s" % _cap_esc(new_v, 100)))
        ka, kb = (I.plist_top_keys(archive_plist), I.plist_top_keys(ipa_plist)) if detail else (None, None)
        if ka is not None and kb is not None:
            idx = next((i for i, (x, y) in enumerate(zip(ka, kb)) if x != y), None)
            info_lines.append("top_level_key_order_equal=%s%s" % ("yes" if ka == kb else "NO", "" if idx is None else " first_difference_at_index=%d (archive %s, ipa %s)" % (idx, _cap_esc(ka[idx], 60), _cap_esc(kb[idx], 60))))
    # ---- the slot-1 seal of the exported executable, for both files
    der_lines = ["DER entitlements evidence (Phase 7C). The blob is kept as hex whether or not the parser reads it.", ""] + prov + [""]
    der_status = "not captured"
    if exe_bytes is not None:
        with tempfile.TemporaryDirectory(prefix="verify_ipa_cap_") as tmp:
            exe_path = os.path.join(tmp, "exe")
            with open(exe_path, "wb") as f:
                f.write(exe_bytes)
            sig = I.read_signature(exe_path)
        der_lines.append("source executable: %s, %d bytes, sha256=%s" % (
            "Payload/%s.app/%s" % (_cap_esc(app_name), _cap_esc(exe_name)) if names_ok else "the main executable of the IPA (its name is not shown: the exported Info.plist is withheld)",
            len(exe_bytes), hashlib.sha256(exe_bytes).hexdigest()))
        if sig["error"] or not sig["slices"]:
            der_lines.append("the executable's signature cannot be read: %s" % _cap_esc(sig["error"] or "no architecture slice"))
            problems.append("the exported executable's signature cannot be read")
        for si, sl in enumerate(sig["slices"]):
            tag = "slice %d (cpu 0x%x)" % (si, sl["cpu"])
            cds = sl.get("cds") or []
            if ipa_plist is not None or archive_plist is not None:
                info_lines.append("")
                for lab, dat in (("ipa_info_plist", ipa_plist), ("archive_info_plist", archive_plist)):
                    if dat is not None:
                        info_lines += ["%s: %s" % (tag, line) for line in _cap_seal_lines(lab, cds, dat, I.SLOT_INFO, "Info.plist")]
                if not cds:
                    info_lines.append("%s: no readable CodeDirectory: the Info.plist seal cannot be compared" % tag)
            blob = sl.get("der_entitlements_blob")
            if blob is None:
                der_lines.append("%s: no DER entitlements slot (slot %d)" % (tag, I.SLOT_DER_ENTITLEMENTS))
                der_status = "absent"
                continue
            too_large = len(blob) > I.EVIDENCE_DER_MAX_BYTES
            unsafe = None if too_large else I.evidence_unsafe_reason(blob)
            keepable = not too_large and unsafe is None
            der_lines.append("%s: DER entitlements blob: %d bytes, sha256=%s" % (tag, len(blob), hashlib.sha256(blob).hexdigest()))
            if keepable:  # header bytes and the parser's own words (they can quote a key) only for a blob whose bytes may be kept
                der_lines.append("%s: header: magic=%s declared_length=%s" % (tag, blob[:4].hex(), int.from_bytes(blob[4:8], "big") if len(blob) >= 8 else "n/a"))
            der_lines += ["%s: %s" % (tag, line) for line in _cap_seal_lines("der_blob", cds, blob, I.SLOT_DER_ENTITLEMENTS, "DER entitlements")]
            try:
                parsed = I.parse_der_entitlements(blob)
                verdict = "accepted, %d top-level entitlement(s)" % len(parsed)
            except (I.Asn1Error, IndexError, ValueError, struct.error, RecursionError) as e:
                verdict = "refused: %s" % _cap_esc(e, 200) if keepable else "refused (the parser's text is not shown for a blob that is withheld)"
            der_lines.append("%s: parser verdict (information only, does not decide what is kept): %s" % (tag, verdict))
            if too_large:
                der_lines.append("%s: bytes NOT kept: larger than %d bytes" % (tag, I.EVIDENCE_DER_MAX_BYTES))
                der_status = "withheld: too large"
                continue
            if unsafe:
                der_lines.append("%s: bytes NOT kept: the content has %s" % (tag, unsafe))
                der_status = "withheld: " + unsafe
                continue
            name = "der-entitlements-slice%d-cpu%x.hex" % (si, sl["cpu"])
            _cap_write(out_dir, name, I.hex_lines(blob))
            der_lines.append("%s: bytes kept as %s (hex of the exact blob)" % (tag, name))
            der_status = "kept"
    elif state == "export-succeeded":
        der_lines.append("not captured: %s" % (exe_note or "the executable was unavailable"))
        problems.append("the DER entitlements could not be read: %s" % (exe_note or "the executable was unavailable"))
    else:
        der_lines.append("not captured: %s" % ("the export failed: no exported executable exists" if state == "export-failed" else "no export happened"))

    status = ["state=%s" % state, "infoplist_archive=%s" % kept.get("archive", "absent"), "infoplist_ipa=%s" % kept.get("ipa", "absent"), "der=%s" % der_status,
              "problems=%d" % len(problems)] + ["problem: %s" % p for p in problems]
    _cap_write(out_dir, "infoplist-summary.txt", "\n".join(info_lines) + "\n")
    _cap_write(out_dir, "der-summary.txt", "\n".join(der_lines) + "\n")
    _cap_write(out_dir, "status.txt", "\n".join(status) + "\n")
    emit("capture-evidence: state=%s, Info.plist archive=%s ipa=%s, DER %s, %d problem(s)" % (state, kept.get("archive", "absent"), kept.get("ipa", "absent"), der_status, len(problems)))
    if archive_plist is not None and ipa_plist is not None:
        emit("capture-evidence: archive Info.plist %d bytes sha256 %s; exported %d bytes sha256 %s; byte-identical: %s" % (
            len(archive_plist), hashlib.sha256(archive_plist).hexdigest(), len(ipa_plist), hashlib.sha256(ipa_plist).hexdigest(), "yes" if archive_plist == ipa_plist else "NO"))
    for p in problems:
        emit("  FAIL  evidence capture: %s" % p)
    return 1 if problems else 0


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
    v.add_argument("--forbid-entitlement", action="append", default=[], metavar="KEY",
                   help="fail when the app's signed entitlements contain KEY (repeatable), e.g. aps-environment "
                        "when the release record decides there is no push capability")
    v.add_argument("--min-sdk", type=int)
    v.add_argument("--warn-days", type=int, default=30)
    v.add_argument("--now", help="UTC time to judge validity at (default now), e.g. 2026-10-22T12:00:00Z")
    v.add_argument("--repo", default=os.path.dirname(HERE))
    v.add_argument("--evidence", help="write text evidence (key=value) here")
    ce = sub.add_parser("certificate", help="read the public signing certificate and its SHA-256 fingerprint from a signed app or IPA")
    ce.add_argument("target", help="a Runner.app directory or an .ipa")
    ce.add_argument("--pem", metavar="FILE", help="write the PUBLIC signing certificate (PEM) here")
    ce.add_argument("--team-id")
    ce.add_argument("--leaf-prefix", action="append", default=None, help="accepted prefixes of the certificate CN (default: Apple Distribution:, iPhone Distribution:)")
    ce.add_argument("--allow-synthetic", action="store_true", help="tests only")
    ce.add_argument("--trust-anchors", metavar="PEM")
    ce.add_argument("--now")
    ce.add_argument("--evidence")
    a = sub.add_parser("analyze-unsigned", help="describe what re-signing an unsigned Runner.app involves")
    a.add_argument("app")
    st = sub.add_parser("structure", help="check the signing structure of an app or IPA without judging the identity")
    st.add_argument("target", help="a Runner.app directory or an .ipa")
    st.add_argument("--evidence")
    c = sub.add_parser("compare", help="is SIGNED the UNSIGNED bundle plus signatures only? (authenticates NO signature: use `verify` for that)",
                       description="Is SIGNED the UNSIGNED bundle plus signatures only? This command authenticates NO signature: it reads no CodeDirectory, no seal and no CMS signature "
                                   "(`verify` does). Every file must be byte-identical, except that the top-level Info.plist may differ in serialization only.")
    c.add_argument("unsigned", help="the unsigned Runner.app directory")
    c.add_argument("signed", help="the signed Runner.app directory or the .ipa")
    cap = sub.add_parser("capture-evidence", help="keep the Info.plist files and the DER entitlements blob as text evidence (read-only; decides nothing)")
    cap.add_argument("--out", required=True, help="directory the evidence files are written to")
    cap.add_argument("--evidence-dir", required=True, help="the existing evidence directory (provenance files are read from it)")
    cap.add_argument("--ipa", default="", help="the exported IPA (read, never copied)")
    cap.add_argument("--archive-app", default="", help="the archive's Runner.app directory (the V8 baseline)")
    cap.add_argument("--run-id", default="")
    cap.add_argument("--run-attempt", default="")
    cap.add_argument("--tools-sha", default="")
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
            emit("  FAIL  internal error while verifying (%s: %s); the IPA is NOT verified" % (type(e).__name__, e))
            emit("")
            emit("verify_ipa: verification aborted, treated as FAILED")
            return 1
    if args.cmd == "analyze-unsigned":
        return analyze_unsigned(args)
    if args.cmd == "certificate":
        if args.team_id and not re.match(r"^[A-Z0-9]{10}$", args.team_id):
            die("--team-id must be a 10-character Apple Team ID")
        if args.trust_anchors and not os.path.isfile(args.trust_anchors):
            die("--trust-anchors %s is not a file" % args.trust_anchors)
        try:
            return certificate(args)
        except SystemExit:
            raise
        except Exception as e:
            emit("  FAIL  internal error while reading the certificate (%s: %s)" % (type(e).__name__, e))
            return 1
    if args.cmd == "structure":
        try:
            return structure(args)
        except SystemExit:
            raise
        except Exception as e:
            emit("  FAIL  internal error while reading the structure (%s: %s)" % (type(e).__name__, e))
            return 1
    if args.cmd == "compare":
        try:
            return compare(args)
        except SystemExit:
            raise
        except Exception as e:
            emit("  FAIL  internal error while comparing (%s: %s)" % (type(e).__name__, e))
            return 1
    if args.cmd == "capture-evidence":
        try:
            return capture_evidence(args)
        except SystemExit:
            raise
        except Exception as e:  # fail closed: a failed capture is reported, and it is never a pass
            emit("  FAIL  internal error while capturing evidence (%s)" % type(e).__name__)
            return 1
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
