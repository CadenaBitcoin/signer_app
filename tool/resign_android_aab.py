#!/usr/bin/env python3
"""Offline re-signing of a RETAINED Android AAB (Stage 3B of issue #54; docs/RETAINED_ARTIFACTS.md section 6).

Stage 2 retains the verified production AAB, debug-signed by the CI validation build and encrypted to
the custodians' public keys. This tool gives that exact file a release-style signature WITHOUT
recompiling it and without touching its verified application content:

  resign_android_aab.py sign RETAINED_DIR --identity AGE_IDENTITY --expect-cert-sha256 FP --out DIR
                        [--signing-properties FILE] [--repo ROOT] [--age BIN] [--sigalg ALG]
  resign_android_aab.py verify SIGNED_DIR --expect-cert-sha256 FP [--repo ROOT]

`sign`
  1. recovers the retained bundle with tool/retain_artifact.py (checksums, age header, the retained
     manifest against the build manifest and evidence, decryption, plaintext checksum and size, the
     content digest); anything wrong stops here;
  2. accepts only the production AAB of a compile-validation build that carries the CI debug signature;
  3. removes the signature entries (META-INF/MANIFEST.MF and *.SF *.RSA *.DSA *.EC) and nothing else,
     and proves that the content digest is unchanged;
  4. signs with `jarsigner` (the mechanism that Google Play takes for a bundle) using a keystore that is
     supplied from OUTSIDE the repository, exactly like android/app/build.gradle.kts: the same four
     variables (CADENA_KEYSTORE_FILE, CADENA_KEY_ALIAS, CADENA_KEYSTORE_PASSWORD, CADENA_KEY_PASSWORD) or
     a properties file (CADENA_SIGNING_PROPERTIES / --signing-properties), and a REQUIRED expected
     certificate fingerprint that the keystore's certificate must equal BEFORE anything is signed. There is
     no fallback to the debug key. Passwords reach jarsigner through environment variables of the child
     process only; they are never printed, never put on a command line and never written to a file;
  5. verifies the signed AAB: jarsigner, the content digest again (it must equal the retained one) and the
     existing release verifier tool/verify_android_release.py (identity, signature, certificate class,
     native libraries, ledgers), with the expected fingerprint;
  6. writes the signed AAB, signing-record.json (cadena-resigned-artifact/1), the verification output,
     copies of the retained manifest, build manifest and evidence, and SHA256SUMS.

`verify` re-checks such a directory later (for example before an upload): checksums, the provenance
chain back to the build manifest, the content digest, jarsigner, the certificate and the verifier.

The signed file has a different SHA-256 than the retained one, by construction. What must not change is
the verified APPLICATION CONTENT, and the record shows both digests side by side. A signed AAB from
this tool is not authorization to publish and is not shown to be accepted by Google Play: only an
authorized upload shows that. Nothing here reads, creates or prints a private key, or uploads anything.

Exit status: 0 success, 1 verification failed, 2 usage or tool error.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_manifest as bm  # noqa: E402
import retain_artifact as ra  # noqa: E402
import verify_android_release as var  # noqa: E402  (only until_date: the one keytool date parser)

SCHEMA = "cadena-resigned-artifact/1"
HERE = os.path.dirname(os.path.abspath(__file__))
VERIFIER = os.path.join(HERE, "verify_android_release.py")
CRED_ENV = (("storeFile", "CADENA_KEYSTORE_FILE"), ("keyAlias", "CADENA_KEY_ALIAS"),
            ("storePassword", "CADENA_KEYSTORE_PASSWORD"), ("keyPassword", "CADENA_KEY_PASSWORD"))
CHILD_STORE = "CADENA_RESIGN_CHILD_STOREPASS"
CHILD_KEY = "CADENA_RESIGN_CHILD_KEYPASS"
FP = re.compile(r"^[0-9A-Fa-f]{2}(:?[0-9A-Fa-f]{2}){31}$")
DIGEST_ALG = "SHA-256"
DEFAULT_SIGALG = "SHA256withRSA"


class Fail(Exception):
    """A usage or tool error (exit 2)."""


class Failed(Exception):
    """A verification failure (exit 1): the message lists what failed."""


def norm_fp(text):
    t = (text or "").strip()
    if not FP.match(t):
        raise Fail("--expect-cert-sha256 must be a SHA-256 fingerprint (64 hex digits, colons optional)")
    return t.replace(":", "").lower()


def colon(fp):
    return ":".join(fp[i:i + 2] for i in range(0, 64, 2)).upper()


def clean_env():
    """The environment of every child process that does NOT need a credential: the signing variables of this
    process are not passed on (not to keytool -printcert, jarsigner -verify or the release verifier)."""
    drop = {env for _, env in CRED_ENV} | {"CADENA_SIGNING_PROPERTIES", CHILD_STORE, CHILD_KEY}
    return {k: v for k, v in os.environ.items() if k not in drop}


def run(cmd, what, env=None):
    try:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env if env is not None else clean_env(), check=False)
    except OSError as e:
        raise Fail("%s: cannot run %s (%s)" % (what, cmd[0], e))
    return r


def sha256_file(path):
    return ra.sha256_file(path)


# ---- credentials: the same rules as android/app/build.gradle.kts --------------------------------------
def read_properties(path):
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("!"):
                continue
            k, sep, v = line.partition("=")
            if sep:
                out[k.strip()] = v.strip()
    return out


def load_credentials(props_path, repo):
    """The keystore path, alias and the two passwords. An environment variable wins over the properties
    file. Errors name WHAT is missing, never a value."""
    props = {}
    path = props_path or os.environ.get("CADENA_SIGNING_PROPERTIES") or ""
    if path:
        real = os.path.realpath(path)
        if not os.path.isfile(real):
            raise Fail("the signing properties file does not exist")
        if real.startswith(os.path.realpath(repo) + os.sep):
            raise Fail("the signing properties file must be outside the repository directory")
        props = read_properties(real)
    values, missing = {}, []
    for key, env in CRED_ENV:
        v = os.environ.get(env) or props.get(key) or ""
        if not v:
            missing.append("%s (%s)" % (key, env))
        values[key] = v
    if missing:
        raise Fail("the signing credentials are incomplete. Missing: %s. There is no fallback to the debug key." % ", ".join(missing))
    store = os.path.realpath(values["storeFile"])
    if not os.path.isfile(store):
        raise Fail("the keystore file does not exist")
    if store.startswith(os.path.realpath(repo) + os.sep):
        raise Fail("the keystore must be outside the repository directory")
    values["storeFile"] = store
    return values


def child_env(creds):
    """The environment of jarsigner and keytool when they open the keystore: only they receive the passwords."""
    env = clean_env()
    env[CHILD_STORE] = creds["storePassword"]
    env[CHILD_KEY] = creds["keyPassword"]
    return env


def keystore_cert_fingerprint(creds):
    """SHA-256 of the certificate of the alias, via keytool (the passwords go through the environment)."""
    r = run(["keytool", "-exportcert", "-alias", creds["keyAlias"], "-keystore", creds["storeFile"],
             "-storepass:env", CHILD_STORE], "keytool", env=child_env(creds))
    if r.returncode != 0 or not r.stdout:
        raise Fail("the keystore could not be opened with the supplied credentials, or the alias does not exist")
    return hashlib.sha256(r.stdout).hexdigest()


# ---- the AAB ---------------------------------------------------------------------------------------------
def strip_signature_entries(src, dst):
    """Copy src to dst without the signature entries (and without changing any other entry or its order).
    Returns the names that were removed."""
    removed = []
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, "w") as zout:
        for info in zin.infolist():
            if ra.is_signature_entry(info.filename):
                removed.append(info.filename)
                continue
            with zin.open(info) as f:
                data = f.read()
            zout.writestr(info, data, compress_type=info.compress_type)
    return removed


def entry_names(path):
    with zipfile.ZipFile(path) as z:
        return [i.filename for i in z.infolist()]


def jarsigner_sign(unsigned, signed, creds, sigalg):
    r = run(["jarsigner", "-keystore", creds["storeFile"], "-storepass:env", CHILD_STORE, "-keypass:env", CHILD_KEY,
             "-sigalg", sigalg, "-digestalg", DIGEST_ALG, "-signedjar", signed, unsigned, creds["keyAlias"]],
            "jarsigner", env=child_env(creds))
    if r.returncode != 0 or not os.path.isfile(signed):
        # jarsigner names the problem (wrong key password, unsupported algorithm); it never prints a password.
        raise Fail("jarsigner could not sign: %s" % (r.stderr.decode("utf-8", "replace").strip().splitlines() or ["no message"])[-1][:300])


def jarsigner_verify(path):
    r = run(["jarsigner", "-verify", path], "jarsigner")
    text = (r.stdout + r.stderr).decode("utf-8", "replace")
    return r.returncode == 0 and "jar verified" in text and "unsigned entries" not in text, text


def signer_of(path):
    """(sha256 hex, subject, number of signers) of the jar signature, via keytool."""
    r = run(["keytool", "-printcert", "-jarfile", path], "keytool")
    text = r.stdout.decode("utf-8", "replace")
    sha = re.findall(r"SHA256:\s*([0-9A-F:]{95})", text)
    owner = re.findall(r"Owner:\s*(.+)", text)
    until = re.findall(r"(?i)valid from: .* until: (.+)", text)
    return (sha[0].replace(":", "").lower() if sha else "", owner[0].strip() if owner else "", len(sha), until[0].strip() if until else "")


def iso_date(text):
    """The certificate's end of validity as an ISO date, whatever the locale or time zone of keytool's text
    (the verifier's own parser); None if it cannot be read."""
    d = var.until_date(text) if text else None
    return d.isoformat() if d else None


def tool_version(cmd):
    r = run(cmd, cmd[0])
    return ((r.stdout + r.stderr).decode("utf-8", "replace").strip().splitlines() or [""])[0]


def verifier_failures(text):
    """The lines of the verifier's output that say what failed (or the tail, if none is marked)."""
    lines = [l.strip() for l in text.splitlines() if l.strip().startswith(("FAIL", "ERROR")) or "FAILED" in l]
    return "\n".join(lines) if lines else text.strip()[-800:]


def run_verifier(repo, signed, fp, out_file):
    """The existing release verifier, with the expected certificate. Returns its exit code."""
    r = run([sys.executable, "-I", VERIFIER, "aab", "production", signed, "--expect-cert-sha256", colon(fp), "--repo", repo],
            "verify_android_release")
    text = (r.stdout + r.stderr).decode("utf-8", "replace")
    if out_file:
        with open(out_file, "w", encoding="utf-8") as f:
            f.write(text)
    return r.returncode, text


# ---- sign ------------------------------------------------------------------------------------------------
def retained_inputs(bundle):
    names = os.listdir(bundle)
    rj = [n for n in names if n.endswith(".retained.json")]
    if len(rj) != 1:
        raise Failed("the retained bundle has no single *.retained.json")
    r = bm.read_json(os.path.join(bundle, rj[0]))
    variant = r.get("variant", "")
    m = bm.read_json(os.path.join(bundle, variant + ".manifest.json"))
    return r, m, variant


def signed_name(m):
    base = bm.canonical_name(m)
    if not base.endswith(".aab"):
        raise Fail("unexpected canonical name %s" % base)
    return base[:-len(".aab")] + ".upload-signed.aab"


def cmd_sign(a):
    repo = os.path.abspath(a.repo)
    expected = norm_fp(a.expect_cert_sha256)
    creds = load_credentials(a.signing_properties, repo)
    if os.path.exists(a.out) and os.listdir(a.out):
        raise Fail("the output directory %s is not empty" % a.out)
    ks_fp = keystore_cert_fingerprint(creds)
    if ks_fp != expected:
        raise Failed("the keystore's certificate is %s, the expected certificate is %s. Nothing was signed."
                     % (colon(ks_fp), colon(expected)))

    work = tempfile.mkdtemp(prefix="resign-")
    os.chmod(work, 0o700)
    created_out = not os.path.exists(a.out)
    try:
        # 1. the retained bundle, verified and decrypted. It is copied once and everything below uses the copy,
        # so what was verified is what is used (and the retained directory is never written to).
        if not os.path.isdir(a.dir):
            raise Failed("the retained artifact does not verify: %s is not a directory" % a.dir)
        bundle = os.path.join(work, "bundle")
        shutil.copytree(a.dir, bundle)
        keep = os.path.join(work, "recovered")
        os.makedirs(keep)
        problems = ra.verify_bundle(bundle, repo, None, a.identity, a.age, keep=keep)
        if problems:
            raise Failed("the retained artifact does not verify: " + "; ".join(problems.items))
        r, m, variant = retained_inputs(bundle)
        # 2. what may be re-signed
        if r["artifact"]["kind"] != "aab" or variant != "android-production-aab" or r["environment"] != "production":
            raise Failed("only the production AAB can be re-signed here (this is %s, %s)" % (variant, r["artifact"]["kind"]))
        if r["signing"]["status"] != "debug" or m["classification"] != "compile-validation":
            raise Failed("the retained artifact is not a debug-signed compile-validation build (signing %s, classification %s)"
                         % (r["signing"]["status"], m["classification"]))
        recovered = os.path.join(keep, r["artifact"]["plaintext"]["file_name"])
        content = r["artifact"]["content"]["sha256"]
        # 3. strip the CI signature, prove the content is unchanged
        stripped = os.path.join(work, "stripped.aab")
        removed = strip_signature_entries(recovered, stripped)
        if not removed:
            raise Failed("the retained AAB carries no signature entries; the CI debug signature was expected")
        if ra.zip_content_digest(stripped) != content:
            raise Failed("removing the signature changed the content digest: refusing")
        # 4. sign
        signed = os.path.join(work, "signed.aab")
        jarsigner_sign(stripped, signed, creds, a.sigalg)
        # 5. verify
        ok, js = jarsigner_verify(signed)
        if not ok:
            raise Failed("jarsigner does not verify the signed bundle")
        signed_content = ra.zip_content_digest(signed)
        if signed_content != content:
            raise Failed("the signed bundle's content digest %s differs from the verified %s" % (signed_content, content))
        sha, owner, nsig, until = signer_of(signed)
        if nsig != 1 or sha != expected:
            raise Failed("the signed bundle has %d signer(s), the certificate is %s; expected exactly %s" % (nsig, colon(sha) if sha else "none", colon(expected)))
        os.makedirs(a.out, exist_ok=True)
        out_aab = os.path.join(a.out, signed_name(m))
        shutil.copyfile(signed, out_aab)
        rc, vtext = run_verifier(repo, out_aab, expected, os.path.join(a.out, "verify_android_release.txt"))
        if rc != 0:
            raise Failed("tool/verify_android_release.py rejects the signed bundle (exit %d):\n%s" % (rc, verifier_failures(vtext)))
        # 6. the record and the provenance copies
        for n in (variant + ".retained.json", variant + ".manifest.json", variant + ".txt"):
            shutil.copyfile(os.path.join(bundle, n), os.path.join(a.out, n))
        added = sorted(set(entry_names(out_aab)) - set(entry_names(stripped)))
        rec = {
            "schema": SCHEMA,
            "original": {
                "variant": variant,
                "source": {"commit": r["source"]["commit"], "ref": r["source"]["ref"], "event": r["source"]["event"]},
                "ci": {"run_id": r["ci"]["run_id"], "run_attempt": r["ci"]["run_attempt"], "run_url": r["ci"]["run_url"]},
                "version": r["version"],
                "retained_manifest": {"file": variant + ".retained.json", "sha256": sha256_file(os.path.join(a.out, variant + ".retained.json"))},
                "build_manifest": {"file": variant + ".manifest.json", "sha256": sha256_file(os.path.join(a.out, variant + ".manifest.json"))},
                "build_evidence": {"file": variant + ".txt", "sha256": sha256_file(os.path.join(a.out, variant + ".txt"))},
                "plaintext": r["artifact"]["plaintext"],
                "signing": r["signing"]["status"],
                "content_sha256": content,
                "ciphertext_sha256": r["encryption"]["ciphertext"]["sha256"],
            },
            "signed": {
                "file": os.path.basename(out_aab),
                "sha256": sha256_file(out_aab),
                "size": os.path.getsize(out_aab),
                "content_sha256": signed_content,
                "signature_entries_removed": sorted(removed),
                "signature_entries_added": added,
                "certificate_sha256": colon(sha),
                "certificate_subject": owner,
                "certificate_valid_until": until,
                "certificate_valid_until_date": iso_date(until),
            },
            "signing": {"tool": "jarsigner", "java": tool_version(["jarsigner", "-J-version"]),
                        "digest_algorithm": DIGEST_ALG, "signature_algorithm": a.sigalg,
                        "keystore": "supplied from outside the repository; never recorded"},
            "verification": {"jarsigner_verify": True, "content_unchanged": True,
                             "release_verifier": "tool/verify_android_release.py aab production: exit 0",
                             "release_verifier_output": "verify_android_release.txt"},
            "distributable": False,
            "note": "A signed bundle is not authorization to publish and is not shown to be accepted by Google Play.",
        }
        ra.write_json(os.path.join(a.out, "signing-record.json"), rec)
        ra.write_sums(a.out)
    except BaseException:
        if created_out:
            shutil.rmtree(a.out, ignore_errors=True)
        else:
            for n in os.listdir(a.out):
                p = os.path.join(a.out, n)
                shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) else os.remove(p)
        raise
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("signed: %s" % os.path.join(a.out, rec["signed"]["file"]))
    print("original content sha256 %s == signed content sha256 %s" % (content, signed_content))
    print("signed file sha256 %s (retained plaintext sha256 %s)" % (rec["signed"]["sha256"], rec["original"]["plaintext"]["sha256"]))
    print("signer %s" % colon(sha))
    print("RESULT: OK %s" % a.out)
    return 0


# ---- verify --------------------------------------------------------------------------------------------------
def verify_signed(directory, expected, repo):
    p = bm.Problems()
    names = sorted(os.listdir(directory))
    if "signing-record.json" not in names:
        p.add("no signing-record.json")
        return p
    rec = bm.read_json(os.path.join(directory, "signing-record.json"))
    if rec.get("schema") != SCHEMA:
        p.add("schema is %r, expected %r" % (rec.get("schema"), SCHEMA))
        return p
    try:
        o, s = rec["original"], rec["signed"]
        variant = o["variant"]
        want = sorted([s["file"], "signing-record.json", "SHA256SUMS", "verify_android_release.txt",
                       variant + ".retained.json", variant + ".manifest.json", variant + ".txt"])
    except (KeyError, TypeError):
        p.add("the signing record lacks a required section")
        return p
    if names != want:
        p.add("the directory holds %s, expected exactly %s" % (names, want))
        return p
    sums = {}
    with open(os.path.join(directory, "SHA256SUMS"), encoding="utf-8") as f:
        for line in f:
            h, _, n = line.rstrip("\n").partition("  ")
            sums[n] = h
    if sorted(sums) != sorted(n for n in names if n != "SHA256SUMS"):
        p.add("SHA256SUMS does not list exactly the other files")
    for n in names:
        if n != "SHA256SUMS" and sums.get(n) != sha256_file(os.path.join(directory, n)):
            p.add("SHA-256 of %s differs from SHA256SUMS" % n)
    if p:
        return p
    path = os.path.join(directory, s["file"])
    # the provenance chain: record -> retained manifest -> build manifest -> evidence
    for key, fname in (("retained_manifest", variant + ".retained.json"), ("build_manifest", variant + ".manifest.json"), ("build_evidence", variant + ".txt")):
        if o[key]["sha256"] != sha256_file(os.path.join(directory, fname)):
            p.add("the record's %s digest differs from the file" % key)
    r = bm.read_json(os.path.join(directory, variant + ".retained.json"))
    m = bm.read_json(os.path.join(directory, variant + ".manifest.json"))
    ev = bm.read_kv(os.path.join(directory, variant + ".txt"))
    for item in bm.verify_manifest(m, repo, ev).items:
        p.add("build manifest: " + item)
    if variant != "android-production-aab" or m.get("variant") != variant:
        p.add("this is not the production AAB")
    for label, got, w in (("source.commit", o["source"]["commit"], m["source"]["commit"]), ("ci.run_id", o["ci"]["run_id"], m["ci"]["run_id"]),
                          ("content digest", o["content_sha256"], r["artifact"]["content"]["sha256"]),
                          ("plaintext sha256", o["plaintext"]["sha256"], r["artifact"]["plaintext"]["sha256"]),
                          ("plaintext sha256 vs build evidence", o["plaintext"]["sha256"], ev.get("artifact_sha256"))):
        if got != w:
            p.add("%s: the record says %r, the source says %r" % (label, got, w))
    if o["signing"] != "debug" or m["signing"]["status"] != "debug":
        p.add("the original is not the debug-signed validation build")
    if s["sha256"] != sha256_file(path) or s["size"] != os.path.getsize(path):
        p.add("the signed file differs from the record (checksum or size)")
    # the signed file itself
    try:
        content = ra.zip_content_digest(path)
    except (zipfile.BadZipFile, ra.Fail) as e:
        p.add("the signed file cannot be read: %s" % e)
        return p
    if content != o["content_sha256"] or content != s["content_sha256"]:
        p.add("the signed file's content digest %s is not the verified content digest %s: the application content changed" % (content, o["content_sha256"]))
    ok, _ = jarsigner_verify(path)
    if not ok:
        p.add("jarsigner does not verify the signed file")
    sha, _, nsig, _ = signer_of(path)
    if nsig != 1 or sha != expected:
        p.add("the signer is %s (%d signer(s)), the expected certificate is %s" % (colon(sha) if sha else "none", nsig, colon(expected)))
    if not sha or colon(sha) != s.get("certificate_sha256"):
        p.add("the record names another certificate than the file carries")
    rc, text = run_verifier(repo, path, expected, None)
    if rc != 0:
        p.add("tool/verify_android_release.py rejects the file (exit %d): %s" % (rc, verifier_failures(text)))
    return p


def cmd_verify(a):
    expected = norm_fp(a.expect_cert_sha256)
    p = verify_signed(a.dir, expected, os.path.abspath(a.repo))
    if p:
        for t in p.items:
            print("  FAIL  %s" % t)
        print("RESULT: FAILED (%d) %s" % (len(p.items), a.dir))
        return 1
    print("RESULT: OK %s (signed bundle: content unchanged, signature and provenance verified)" % a.dir)
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="resign_android_aab.py", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sign")
    s.add_argument("dir")
    s.add_argument("--identity", required=True)
    s.add_argument("--expect-cert-sha256", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--signing-properties", default=None)
    s.add_argument("--repo", default=bm.DEFAULT_ROOT)
    s.add_argument("--age", default="age")
    s.add_argument("--sigalg", default=DEFAULT_SIGALG)
    s.set_defaults(fn=cmd_sign)
    v = sub.add_parser("verify")
    v.add_argument("dir")
    v.add_argument("--expect-cert-sha256", required=True)
    v.add_argument("--repo", default=bm.DEFAULT_ROOT)
    v.set_defaults(fn=cmd_verify)
    a = ap.parse_args(argv[1:])
    try:
        return a.fn(a)
    except Fail as e:
        print("resign_android_aab: %s" % e, file=sys.stderr)
        return 2
    except Failed as e:
        print("  FAIL  %s" % e)
        print("RESULT: FAILED")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
