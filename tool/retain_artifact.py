#!/usr/bin/env python3
"""Retained build artifacts (Stage 2 of the release pipeline, issue #54; docs/RETAINED_ARTIFACTS.md).

A verified build can be KEPT, not only described. The kept file is encrypted to the public keys of
the release custodians (age, https://age-encryption.org), so the public workflow run exposes only
ciphertext, public checksums and manifests. The runner never holds a key that can read it.

  retain_artifact.py plan --event E [--retain true|false] [--recipient KEY] --recipients-file F
      Decides whether a run retains artifacts and with which recipients. Prints key=value lines
      (retain, recipients, recipient_count, source, note).
        push:               retains if and only if the committed recipients file lists a key.
        workflow_dispatch:  retains if --retain true; the recipients are the committed ones plus
                            the optional --recipient (a PUBLIC key). Retaining without any
                            recipient fails: it would produce an unreadable artifact.

  retain_artifact.py write-recipients --list KEY,KEY --out FILE
      Writes the age recipients file the build jobs use (every key is validated).

  retain_artifact.py pack --variant V --kind apk|aab|ios-xcarchive --artifact PATH
        --evidence V.txt --manifest V.manifest.json --recipients FILE --out DIR
        [--archive-evidence F] [--retention-days N] [--require-identical] [--age BIN --age-keygen BIN]
      Packs the artifact the build job has just verified: plaintext checksum and content digest,
      encryption to the recipients, a round-trip proof with a one-time key that is discarded, the
      retained manifest, the build evidence and SHA256SUMS. Then verifies the bundle.

  retain_artifact.py verify DIR [--repo ROOT] [--against EVIDENCE_DIR] [--identity FILE] [--age BIN]
      Without --identity: everything checkable without a key (file set, checksums, age header,
      the manifest against the build manifest and evidence). With --identity: also decrypts and
      checks the plaintext checksum, size, content digest and (iOS) the archive's application.

  retain_artifact.py unpack DIR --identity FILE --out OUT [--repo ROOT] [--age BIN]
      verify with the identity, then writes the artifact: the APK/AAB file, or Runner.xcarchive.

Exit status: 0 success, 1 verification failed, 2 usage or tool error. Nothing here signs or
publishes anything, reads a signing credential, or prints a secret.
"""
import argparse
import gzip
import hashlib
import io
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile

sys.dont_write_bytecode = True
# `python3 -I` does not put the script's directory on the import path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_manifest as bm  # noqa: E402

SCHEMA = "cadena-retained-artifact/1"
AGE_HEADER = b"age-encryption.org/v1\n"
RECIPIENT = re.compile(r"^age1[02-9ac-hj-np-z]{58}$")
SECRET_KEY = re.compile(r"AGE-SECRET-KEY-")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
KINDS = ("apk", "aab", "ios-xcarchive")
KIND_OF_VARIANT_KIND = {"apk": "apk", "aab": "aab", "ios-app": "ios-xcarchive"}
LABEL = "NON-DISTRIBUTABLE_INTERNAL-EVALUATION_"
ARCHIVE_ROOT = "Runner.xcarchive"
APP_IN_ARCHIVE = ARCHIVE_ROOT + "/Products/Applications/Runner.app"
# Identity and version facts of the archive's application that must equal the validated build's.
IDENTITY_KEYS = ("application_id", "display_name", "version_name", "version_code", "environment",
                 "signing", "minimum_os_version", "executable_archs")
DIGEST_KEYS = (("artifact_sha256", "app_directory_sha256_equal"),
               ("executable_sha256", "executable_sha256_equal"),
               ("app_snapshot_sha256", "app_snapshot_sha256_equal"))


class Fail(Exception):
    """A usage or tool error (exit 2)."""


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, sort_keys=False)
        f.write("\n")


# ---- recipients ---------------------------------------------------------------------------
def recipient_id(key):
    """Short public identifier of a recipient key, so a custodian can see which key was used."""
    return hashlib.sha256(key.encode("ascii")).hexdigest()[:16]


def check_recipient(key, where):
    if SECRET_KEY.search(key):
        raise Fail("%s holds a SECRET key; only public keys (age1...) may be listed" % where)
    if not RECIPIENT.match(key):
        raise Fail("%s is not an age X25519 public key (age1 + 58 characters)" % where)
    return key


def parse_recipients_file(path):
    keys = []
    try:
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                text = line.strip()
                if not text or text.startswith("#"):
                    continue
                key = check_recipient(text, "%s:%d" % (path, n))
                if key not in keys:
                    keys.append(key)
    except OSError as e:
        raise Fail("cannot read the recipients file %s: %s" % (path, e))
    return keys


def cmd_plan(a):
    committed = parse_recipients_file(a.recipients_file)
    keys, note = list(committed), ""
    if a.event == "push":
        if a.retain not in ("", None) or a.recipient:
            raise Fail("a push cannot carry retention inputs")
        retain = bool(committed)
        source = "committed" if committed else "none"
        if not retain:
            note = "no recipient is configured in %s: nothing is retained" % a.recipients_file
    elif a.event == "workflow_dispatch":
        if a.retain not in ("", "true", "false", None):
            raise Fail("--retain must be true or false")
        retain = a.retain == "true"
        if a.recipient and not retain:
            raise Fail("a recipient was given but retention was not requested")
        if a.recipient:
            key = check_recipient(a.recipient, "the recipient input")
            if key not in keys:
                keys.append(key)
        if retain and not keys:
            raise Fail("retention was requested but no recipient exists (the committed file is empty and none was given)")
        source = ("committed+input" if committed and a.recipient else "input" if a.recipient
                  else "committed" if committed else "none")
        if not retain:
            keys, source = [], "none"
    else:
        raise Fail("unsupported event '%s'" % a.event)
    print("retain=%s" % ("true" if retain else "false"))
    print("recipients=%s" % ",".join(keys if retain else []))
    print("recipient_count=%d" % (len(keys) if retain else 0))
    print("source=%s" % source)
    if note:
        print("note=%s" % note)
    return 0


def cmd_write_recipients(a):
    keys = [check_recipient(k, "--list entry %d" % (i + 1)) for i, k in enumerate(a.list.split(",")) if k]
    if not keys:
        raise Fail("--list holds no recipient")
    with open(a.out, "w", encoding="utf-8") as f:
        f.write("# age recipients (public keys) for this run; written by tool/retain_artifact.py\n")
        for k in dict.fromkeys(keys):
            f.write(k + "\n")
    print("%d recipient(s) written to %s" % (len(set(keys)), a.out))
    return 0


# ---- artifact content ------------------------------------------------------------------------
def is_signature_entry(name):
    """JAR/APK signature files: they change when the artifact is signed, nothing else does."""
    up = name.upper()
    if up == "META-INF/MANIFEST.MF":
        return True
    return up.startswith("META-INF/") and "/" not in up[len("META-INF/"):] and up.rsplit(".", 1)[-1] in ("SF", "RSA", "DSA", "EC")


def zip_content_digest(path):
    """SHA-256 over the sorted "<sha256>  <entry>" lines of every entry except the signature
    files: it is the same before and after the artifact is (re-)signed, so a signing stage can
    prove it changed nothing but the signature."""
    entries = {}
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            if info.is_dir() or is_signature_entry(info.filename):
                continue
            if info.filename in entries:
                raise Fail("the archive has two entries named %s (ambiguous)" % info.filename)
            h = hashlib.sha256()
            with z.open(info) as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
            entries[info.filename] = h.hexdigest()
    lines = "".join("%s  %s\n" % (entries[n], n) for n in sorted(entries, key=lambda s: s.encode("utf-8")))
    return hashlib.sha256(lines.encode("utf-8")).hexdigest()


def deterministic_tar_gz(src_dir, root_name, out_path):
    """The directory src_dir as <root_name>/... in a gzip-compressed tar with fixed owner, time
    and normalized modes, so the same tree gives the same bytes. Only regular files and
    directories are accepted (a link in an archive would be an unnecessary risk)."""
    entries = []
    for base, dirs, files in os.walk(src_dir, followlinks=False):
        dirs.sort()
        for n in sorted(dirs) + sorted(files):
            full = os.path.join(base, n)
            if os.path.islink(full) or not (os.path.isdir(full) or os.path.isfile(full)):
                raise Fail("%s is a link or special file; only regular files and directories are archived" % full)
            entries.append(full)
    entries.sort(key=lambda p: os.path.relpath(p, src_dir).encode("utf-8"))
    with open(out_path, "wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0) as gz:
            with tarfile.open(fileobj=gz, mode="w", format=tarfile.PAX_FORMAT) as tar:
                def add(info, fileobj=None):
                    info.mtime, info.uid, info.gid, info.uname, info.gname = 0, 0, 0, "", ""
                    tar.addfile(info, fileobj)
                top = tarfile.TarInfo(root_name)
                top.type, top.mode = tarfile.DIRTYPE, 0o755
                add(top)
                for full in entries:
                    rel = root_name + "/" + os.path.relpath(full, src_dir).replace(os.sep, "/")
                    ti = tarfile.TarInfo(rel)
                    if os.path.isdir(full):
                        ti.type, ti.mode = tarfile.DIRTYPE, 0o755
                        add(ti)
                    else:
                        ti.size = os.path.getsize(full)
                        ti.mode = 0o755 if os.stat(full).st_mode & 0o111 else 0o644
                        with open(full, "rb") as f:
                            add(ti, f)


def safe_extract_tar_gz(path, dest):
    """Extract only regular files and directories whose names stay inside dest."""
    real = os.path.realpath(dest)
    with tarfile.open(path, mode="r:gz") as tar:
        for member in tar:
            name = member.name
            if member.isdir():
                kind = "dir"
            elif member.isreg():
                kind = "file"
            else:
                raise Fail("the archive has a member that is not a regular file or directory: %s" % name)
            if name.startswith("/") or ".." in name.split("/") or "\\" in name:
                raise Fail("the archive has an unsafe member name: %s" % name)
            target = os.path.realpath(os.path.join(dest, name))
            if target != real and not target.startswith(real + os.sep):
                raise Fail("the archive member %s would leave the target directory" % name)
            if kind == "dir":
                os.makedirs(target, exist_ok=True)
            else:
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with tar.extractfile(member) as src, open(target, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                os.chmod(target, 0o755 if member.mode & 0o111 else 0o644)


def plaintext_name(m, kind):
    """The label and the canonical name of the build (tool/build_manifest.py name), with the
    archive suffix for iOS. The label says what the file is, also after it is decrypted."""
    base = LABEL + bm.canonical_name(m)
    if kind == "ios-xcarchive":
        if not base.endswith(".app"):
            raise Fail("unexpected canonical name %s" % base)
        base = base[:-len(".app")].replace("-ios-app-", "-ios-xcarchive-", 1) + ".xcarchive.tar.gz"
    return base


# ---- age ---------------------------------------------------------------------------------------
def run(cmd, what):
    try:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    except OSError as e:
        raise Fail("%s: cannot run %s (%s)" % (what, cmd[0], e))
    if r.returncode != 0:
        # age's messages name files and reasons, never key material; still keep only its stderr.
        raise Fail("%s failed (exit %d): %s" % (what, r.returncode, r.stderr.decode("utf-8", "replace").strip()[:400]))
    return r


def encrypt_with_roundtrip(age, age_keygen, recipients_file, plaintext, out_path):
    """Encrypt to the recipients AND to a one-time key, decrypt with the one-time key and compare.
    The one-time private key lives in a private temp directory and is deleted at once; it is an
    extra recipient of the ciphertext that nobody can use afterwards. The round trip proves that
    exactly the recorded plaintext is inside the file that is retained."""
    tmp = tempfile.mkdtemp(prefix="retain-")
    os.chmod(tmp, 0o700)
    try:
        ident = os.path.join(tmp, "one-time.key")
        run([age_keygen, "-o", ident], "age-keygen")
        pub = None
        with open(ident, encoding="utf-8") as f:
            for line in f:
                if line.startswith("# public key:"):
                    pub = line.split(":", 1)[1].strip()
        if not pub or not RECIPIENT.match(pub):
            raise Fail("age-keygen did not report a public key")
        run([age, "-R", recipients_file, "-r", pub, "-o", out_path, plaintext], "age encrypt")
        back = os.path.join(tmp, "roundtrip")
        run([age, "-d", "-i", ident, "-o", back, out_path], "age decrypt (round trip)")
        want_sha, want_size = sha256_file(plaintext), os.path.getsize(plaintext)
        if sha256_file(back) != want_sha or os.path.getsize(back) != want_size:
            raise Fail("the round trip returned different bytes")
        return True
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def decrypt(age, identity, cipher, out_path):
    run([age, "-d", "-i", identity, "-o", out_path, cipher], "age decrypt")


# ---- pack --------------------------------------------------------------------------------------
def check_variant_kind(m, kind):
    variant = m.get("variant")
    if variant not in bm.VARIANTS:
        raise Fail("the manifest names an unknown variant %r" % variant)
    want = KIND_OF_VARIANT_KIND[bm.VARIANTS[variant][1]]
    if kind != want:
        raise Fail("variant %s is retained as %s, not %s" % (variant, want, kind))


def cmd_pack(a):
    age, age_keygen = a.age, a.age_keygen
    m = bm.read_json(a.manifest)
    ev = bm.read_kv(a.evidence)
    if m.get("variant") != a.variant or ev.get("variant") != a.variant:
        raise Fail("the manifest or the evidence is not that of variant %s" % a.variant)
    check_variant_kind(m, a.kind)
    problems = bm.verify_manifest(m, None, ev)
    if problems:
        raise Fail("the build manifest does not verify: " + "; ".join(problems.items))
    if m["signing"]["status"] not in ("unsigned", "debug") or m["distribution"]["distributable"] is not False:
        raise Fail("only unsigned or debug-signed, non-distributable builds can be retained here")
    keys = parse_recipients_file(a.recipients)
    if not keys:
        raise Fail("no recipient: the artifact would be unreadable")
    if os.path.exists(a.out) and os.listdir(a.out):
        raise Fail("the output directory %s is not empty" % a.out)
    os.makedirs(a.out, exist_ok=True)

    name = plaintext_name(m, a.kind)
    staging = tempfile.mkdtemp(prefix="retain-plain-")
    try:
        correspondence = {}
        if a.kind in ("apk", "aab"):
            if not os.path.isfile(a.artifact) or not zipfile.is_zipfile(a.artifact):
                raise Fail("%s is not an APK/AAB (zip) file" % a.artifact)
            plain = a.artifact
            sha, size = sha256_file(plain), os.path.getsize(plain)
            if sha != ev.get("artifact_sha256") or str(size) != ev.get("artifact_bytes"):
                raise Fail("the artifact is not the file whose verification evidence was recorded")
            correspondence["plaintext_sha256_equals_verified_artifact"] = True
            content = {"digest_kind": "zip-entries-without-signature-files",
                       "sha256": zip_content_digest(plain),
                       "basis": "sha256 of the sorted '<sha256>  <entry>' lines of every zip entry except META-INF/MANIFEST.MF and *.SF *.RSA *.DSA *.EC"}
            fmt = "file"
        else:
            if not a.archive_evidence:
                raise Fail("--archive-evidence is required for an iOS archive")
            aev = bm.read_kv(a.archive_evidence)
            app = os.path.join(a.artifact, "Products", "Applications", "Runner.app")
            if not os.path.isdir(app):
                raise Fail("%s has no Products/Applications/Runner.app" % a.artifact)
            tree = bm.tree_digest(app)
            if tree != aev.get("artifact_sha256"):
                raise Fail("the application inside the archive is not the one whose verification evidence was recorded")
            for k in IDENTITY_KEYS:
                if aev.get(k) != ev.get(k):
                    raise Fail("%s differs between the archive's application (%r) and the validated build (%r)"
                               % (k, aev.get(k), ev.get(k)))
            correspondence["identity_and_version_equal"] = True
            for key, label in DIGEST_KEYS:
                correspondence[label] = bool(aev.get(key)) and aev.get(key) == ev.get(key)
            if a.require_identical and not all(correspondence.values()):
                raise Fail("the archive's application is not bit-identical to the validated build: %s"
                           % json.dumps(correspondence, sort_keys=True))
            plain = os.path.join(staging, name)
            deterministic_tar_gz(a.artifact, ARCHIVE_ROOT, plain)
            sha, size = sha256_file(plain), os.path.getsize(plain)
            content = {"digest_kind": "directory-manifest", "sha256": tree,
                       "basis": "sha256 of the sorted per-file sha256 manifest of Runner.app inside the archive (the digest of tool/verify_artifact.sh)",
                       "executable_sha256": aev.get("executable_sha256", ""),
                       "app_snapshot_sha256": aev.get("app_snapshot_sha256", "")}
            fmt = "tar.gz"

        cipher_name = name + ".age"
        cipher_path = os.path.join(a.out, cipher_name)
        roundtrip = encrypt_with_roundtrip(age, age_keygen, a.recipients, plain, cipher_path)

        variant = a.variant
        shutil.copyfile(a.evidence, os.path.join(a.out, variant + ".txt"))
        shutil.copyfile(a.manifest, os.path.join(a.out, variant + ".manifest.json"))
        r = {
            "schema": SCHEMA,
            "variant": variant,
            "platform": m["platform"],
            "environment": m["environment"],
            "source": {"commit": m["source"]["commit"], "ref": m["source"]["ref"], "event": m["source"]["event"]},
            "ci": {"run_id": m["ci"]["run_id"], "run_attempt": m["ci"]["run_attempt"], "run_url": m["ci"]["run_url"],
                   "build_id": m["ci"]["build_id"]},
            "version": {"name": m["version"]["name"], "build": m["version"]["platform_build_number"]},
            "application": dict(m["application"]),
            "configuration": {"file": m["configuration"]["file"], "sha256": m["configuration"]["sha256"]},
            "build_manifest": {"file": variant + ".manifest.json", "sha256": sha256_file(os.path.join(a.out, variant + ".manifest.json"))},
            "build_evidence": {"file": variant + ".txt", "sha256": sha256_file(os.path.join(a.out, variant + ".txt"))},
            "artifact": {
                "kind": a.kind,
                "format": fmt,
                "plaintext": {"file_name": name, "sha256": sha, "size": size},
                "content": content,
                "correspondence_to_validated_build": correspondence,
            },
            "signing": {"status": m["signing"]["status"], "distributable": False},
            "encryption": {
                "format": "age-encryption.org/v1",
                "recipients": [recipient_id(k) for k in keys],
                "one_time_verification_recipient": "private key created and discarded inside the build job",
                "round_trip_verified": roundtrip,
                "ciphertext": {"file_name": cipher_name, "sha256": sha256_file(cipher_path), "size": os.path.getsize(cipher_path)},
            },
            "retention": {"days": a.retention_days, "access": "only the holders of a recipient key can read the artifact"},
        }
        write_json(os.path.join(a.out, variant + ".retained.json"), r)
        write_sums(a.out)
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    rc = report_verify(a.out, verify_bundle(a.out, repo=None, against=None, identity=None, age=age), a.out)
    if rc == 0:
        print("retained %s: plaintext sha256 %s, ciphertext sha256 %s (%d bytes)"
              % (a.variant, sha, r["encryption"]["ciphertext"]["sha256"], r["encryption"]["ciphertext"]["size"]))
    return rc


def write_sums(directory):
    lines = []
    for n in sorted(os.listdir(directory)):
        if n == "SHA256SUMS":
            continue
        lines.append("%s  %s\n" % (sha256_file(os.path.join(directory, n)), n))
    with open(os.path.join(directory, "SHA256SUMS"), "w", encoding="utf-8") as f:
        f.writelines(lines)


# ---- verify ----------------------------------------------------------------------------------
def verify_bundle(directory, repo, against, identity, age, keep=None):
    """Returns a bm.Problems. With `keep` (a directory) the decrypted artifact is left there."""
    p = bm.Problems()
    if not os.path.isdir(directory):
        p.add("%s is not a directory" % directory)
        return p
    names = sorted(os.listdir(directory))
    retained = [n for n in names if n.endswith(".retained.json")]
    if len(retained) != 1:
        p.add("expected exactly one *.retained.json, found %d" % len(retained))
        return p
    try:
        r = bm.read_json(os.path.join(directory, retained[0]))
    except SystemExit:
        p.add("%s is not readable JSON" % retained[0])
        return p
    if r.get("schema") != SCHEMA:
        p.add("schema is %r, expected %r" % (r.get("schema"), SCHEMA))
        return p
    try:
        variant = r["variant"]
        art, enc = r["artifact"], r["encryption"]
        cipher = enc["ciphertext"]
        plain = art["plaintext"]
        kind = art["kind"]
        content = art["content"]
    except (KeyError, TypeError):
        p.add("the retained manifest lacks a required section")
        return p
    if variant not in bm.VARIANTS:
        p.add("unknown variant %r" % variant)
        return p
    if retained[0] != variant + ".retained.json":
        p.add("the manifest file name does not match its variant")
    if kind != KIND_OF_VARIANT_KIND[bm.VARIANTS[variant][1]]:
        p.add("kind %s does not fit variant %s" % (kind, variant))

    # -- exactly the expected files, with the expected checksums ---------------------------------
    expected = sorted([variant + ".txt", variant + ".manifest.json", variant + ".retained.json",
                       str(cipher.get("file_name")), "SHA256SUMS"])
    if names != expected:
        p.add("the bundle holds %s, expected exactly %s (no plaintext artifact may be uploaded)" % (names, expected))
        return p
    try:
        sums = {}
        with open(os.path.join(directory, "SHA256SUMS"), encoding="utf-8") as f:
            for line in f:
                h, _, n = line.rstrip("\n").partition("  ")
                sums[n] = h
    except OSError:
        p.add("SHA256SUMS is not readable")
        return p
    if sorted(sums) != sorted(n for n in names if n != "SHA256SUMS"):
        p.add("SHA256SUMS does not list exactly the other files")
    for n in names:
        if n != "SHA256SUMS" and sums.get(n) != sha256_file(os.path.join(directory, n)):
            p.add("SHA-256 of %s differs from SHA256SUMS" % n)
    for n in names:
        if n != cipher["file_name"]:
            with open(os.path.join(directory, n), "rb") as f:
                head = f.read(1 << 20)
            if SECRET_KEY.search(head.decode("latin-1")):
                p.add("%s contains a secret key marker" % n)
            if os.path.getsize(os.path.join(directory, n)) > (1 << 20):
                p.add("%s is larger than 1 MiB; only the .age file may be large" % n)

    # -- the ciphertext ------------------------------------------------------------------------
    cpath = os.path.join(directory, cipher["file_name"])
    if not cipher["file_name"].endswith(".age") or not cipher["file_name"].startswith(LABEL):
        p.add("the ciphertext file name is not the labelled <canonical name>.age")
    if cipher.get("sha256") != sha256_file(cpath) or cipher.get("size") != os.path.getsize(cpath):
        p.add("the ciphertext differs from the retained manifest (checksum or size)")
    with open(cpath, "rb") as f:
        if f.read(len(AGE_HEADER)) != AGE_HEADER:
            p.add("the file is not an age ciphertext (no age header): a plaintext artifact must never be retained")
    if enc.get("round_trip_verified") is not True:
        p.add("the build job did not record a successful round trip")
    if not enc.get("recipients"):
        p.add("no recipient is recorded")
    for field in ("sha256",):
        for label, val in (("plaintext", plain.get("sha256")), ("content", content.get("sha256")), ("ciphertext", cipher.get("sha256"))):
            if not (isinstance(val, str) and HEX64.match(val)):
                p.add("%s %s is not a SHA-256" % (label, field))

    # -- the manifest against the build manifest and the evidence --------------------------------
    bm_path = os.path.join(directory, variant + ".manifest.json")
    ev_path = os.path.join(directory, variant + ".txt")
    m = bm.read_json(bm_path)
    ev = bm.read_kv(ev_path)
    if r["build_manifest"].get("sha256") != sha256_file(bm_path) or r["build_evidence"].get("sha256") != sha256_file(ev_path):
        p.add("the retained manifest does not match the build manifest or evidence it names")
    for item in bm.verify_manifest(m, repo, ev).items:
        p.add("build manifest: " + item)
    if m.get("variant") != variant:
        p.add("the build manifest is that of variant %r" % m.get("variant"))
    else:
        pairs = (
            ("source.commit", r["source"]["commit"], m["source"]["commit"]),
            ("source.ref", r["source"]["ref"], m["source"]["ref"]),
            ("ci.run_id", r["ci"]["run_id"], m["ci"]["run_id"]),
            ("ci.run_attempt", r["ci"]["run_attempt"], m["ci"]["run_attempt"]),
            ("ci.build_id", r["ci"]["build_id"], m["ci"]["build_id"]),
            ("version.name", r["version"]["name"], m["version"]["platform_version_name"]),
            ("version.build", r["version"]["build"], m["version"]["platform_build_number"]),
            ("application.id", r["application"]["id"], m["application"]["id"]),
            ("configuration.sha256", r["configuration"]["sha256"], m["configuration"]["sha256"]),
            ("environment", r["environment"], m["environment"]),
            ("signing.status", r["signing"]["status"], m["signing"]["status"]),
        )
        for label, got, want in pairs:
            if got != want:
                p.add("%s is %r in the retained manifest but %r in the build manifest" % (label, got, want))
        if r["signing"].get("distributable") is not False or m["distribution"]["distributable"] is not False:
            p.add("a retained build-variant artifact must be non-distributable")
        if plain.get("file_name") != plaintext_name(m, kind):
            p.add("the plaintext name %r is not the canonical name of this build" % plain.get("file_name"))
        if cipher.get("file_name") != str(plain.get("file_name")) + ".age":
            p.add("the ciphertext name is not the plaintext name plus .age")
        corr = art.get("correspondence_to_validated_build", {})
        if kind in ("apk", "aab"):
            if plain.get("sha256") != ev.get("artifact_sha256") or str(plain.get("size")) != ev.get("artifact_bytes"):
                p.add("the retained plaintext is not the file whose checksum the build evidence records")
            if corr.get("plaintext_sha256_equals_verified_artifact") is not True:
                p.add("the correspondence to the verified artifact is not recorded")
        else:
            if corr.get("identity_and_version_equal") is not True:
                p.add("the identity of the archive's application was not shown equal to the validated build")
    if against:
        for n in (variant + ".txt", variant + ".manifest.json"):
            other = os.path.join(against, n)
            if not os.path.isfile(other) or sha256_file(other) != sha256_file(os.path.join(directory, n)):
                p.add("%s differs from the verified build evidence in %s" % (n, against))

    # -- with a key: the plaintext ----------------------------------------------------------------
    if identity and not p:
        tmp = tempfile.mkdtemp(prefix="retain-verify-")
        try:
            out = os.path.join(tmp, "plain")
            try:
                decrypt(age, identity, cpath, out)
            except Fail as e:
                p.add(str(e))
                return p
            if sha256_file(out) != plain["sha256"] or os.path.getsize(out) != plain["size"]:
                p.add("the decrypted file differs from the recorded plaintext (checksum or size)")
                return p
            try:
                if kind in ("apk", "aab"):
                    if not zipfile.is_zipfile(out):
                        p.add("the decrypted file is not a zip")
                    elif zip_content_digest(out) != content["sha256"]:
                        p.add("the content digest of the decrypted file differs from the manifest")
                else:
                    ex = os.path.join(tmp, "x")
                    os.makedirs(ex)
                    safe_extract_tar_gz(out, ex)
                    app = os.path.join(ex, APP_IN_ARCHIVE)
                    if not os.path.isdir(app):
                        p.add("the archive has no %s" % APP_IN_ARCHIVE)
                    else:
                        if bm.tree_digest(app) != content["sha256"]:
                            p.add("the application digest inside the archive differs from the manifest")
                        check_archive_app(app, r, p)
                    if keep and not p:
                        shutil.copytree(os.path.join(ex, ARCHIVE_ROOT), os.path.join(keep, ARCHIVE_ROOT))
                if keep and not p and kind in ("apk", "aab"):
                    shutil.copyfile(out, os.path.join(keep, plain["file_name"]))
            except (Fail, zipfile.BadZipFile, tarfile.TarError, OSError) as e:
                p.add("the decrypted artifact cannot be read: %s" % e)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    return p


def check_archive_app(app, r, p):
    if os.path.exists(os.path.join(app, "_CodeSignature")) or os.path.exists(os.path.join(app, "embedded.mobileprovision")):
        p.add("the archive's application is signed or carries a profile; a retained iOS archive must be unsigned")
    plist_path = os.path.join(app, "Info.plist")
    try:
        with open(plist_path, "rb") as f:
            info = plistlib.load(f)
    except (OSError, plistlib.InvalidFileException, ValueError):
        p.add("the application's Info.plist cannot be read")
        return
    for key, want in (("CFBundleIdentifier", r["application"]["id"]),
                      ("CFBundleShortVersionString", r["version"]["name"]),
                      ("CFBundleVersion", str(r["version"]["build"]))):
        if str(info.get(key)) != str(want):
            p.add("Info.plist %s is %r, the manifest says %r" % (key, info.get(key), want))


def report_verify(label, problems, shown):
    if problems:
        for text in problems.items:
            print("  FAIL  %s" % text)
        print("RESULT: FAILED (%d) %s" % (len(problems.items), shown))
        return 1
    print("RESULT: OK %s" % shown)
    return 0


def cmd_verify(a):
    p = verify_bundle(a.dir, a.repo, a.against, a.identity, a.age)
    return report_verify(a.dir, p, a.dir + (" (with the key: plaintext verified)" if a.identity else " (without a key)"))


def cmd_unpack(a):
    os.makedirs(a.out, exist_ok=True)
    if os.listdir(a.out):
        raise Fail("the output directory %s is not empty" % a.out)
    p = verify_bundle(a.dir, a.repo, None, a.identity, a.age, keep=a.out)
    rc = report_verify(a.dir, p, a.dir + " (with the key: plaintext verified)")
    if rc == 0:
        for n in sorted(os.listdir(a.out)):
            print("unpacked: %s" % os.path.join(a.out, n))
    return rc


def main(argv):
    ap = argparse.ArgumentParser(prog="retain_artifact.py", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("plan")
    s.add_argument("--event", required=True)
    s.add_argument("--retain", default="")
    s.add_argument("--recipient", default="")
    s.add_argument("--recipients-file", required=True)
    s.set_defaults(fn=cmd_plan)

    s = sub.add_parser("write-recipients")
    s.add_argument("--list", required=True)
    s.add_argument("--out", required=True)
    s.set_defaults(fn=cmd_write_recipients)

    s = sub.add_parser("pack")
    s.add_argument("--variant", required=True)
    s.add_argument("--kind", required=True, choices=KINDS)
    s.add_argument("--artifact", required=True)
    s.add_argument("--evidence", required=True)
    s.add_argument("--manifest", required=True)
    s.add_argument("--recipients", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--archive-evidence", default="")
    s.add_argument("--retention-days", type=int, default=14)
    s.add_argument("--require-identical", action="store_true")
    s.add_argument("--age", default="age")
    s.add_argument("--age-keygen", default="age-keygen")
    s.set_defaults(fn=cmd_pack)

    s = sub.add_parser("verify")
    s.add_argument("dir")
    s.add_argument("--repo", default=None)
    s.add_argument("--against", default=None)
    s.add_argument("--identity", default=None)
    s.add_argument("--age", default="age")
    s.set_defaults(fn=cmd_verify)

    s = sub.add_parser("unpack")
    s.add_argument("dir")
    s.add_argument("--identity", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--repo", default=None)
    s.add_argument("--age", default="age")
    s.set_defaults(fn=cmd_unpack)

    a = ap.parse_args(argv[1:])
    try:
        return a.fn(a)
    except Fail as e:
        print("retain_artifact: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
