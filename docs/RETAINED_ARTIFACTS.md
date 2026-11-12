# Retained build artifacts (Stage 2)

**Status: implemented for review (issue #54, Stage 2). Nothing here signs, uploads to a store or
publishes anything.** It extends `build-variants.yml`
([RELEASE_TRIGGERS.md](RELEASE_TRIGGERS.md)); it is not a second release system. Policy:
[RELEASE_POLICY.md](RELEASE_POLICY.md). Stage 3 (automated signing and store delivery) is separate
work, with its prerequisites listed in section 8.

## 1. What is retained

A run that retains artifacts keeps, **per required variant**, the artifact that the same job
built and verified, together with its verification evidence:

| Variant | Kept artifact | Why this file | Signing state |
|---|---|---|---|
| `android-production-aab` | the release AAB | what Google Play takes (after upload-key signing) | debug-signed (CI validation) |
| `android-production-apk` | the universal release APK | the website APK (after release signing) | debug-signed |
| `android-staging-apk` | the staging release APK | internal evaluation / signing | debug-signed |
| `ios-production`, `ios-staging` | `Runner.xcarchive` (a tar.gz) from `flutter build ipa --no-codesign` | the input of the supported export route (Route B of [IOS_SIGNING.md](IOS_SIGNING.md) section 3.2) | **unsigned** |

The Android artifacts carry the repository's temporary debug signature
([ANDROID_RELEASE.md](ANDROID_RELEASE.md) section 2): they are **not** release artifacts and are
never distributable. The iOS archive has no signature, no embedded profile and no entitlements
beyond what the project declares. File names say so, also after decryption:
`NON-DISTRIBUTABLE_INTERNAL-EVALUATION_cadena-signer-<env>-<version>+<build>-<platform>-<kind>-<commit7>-run<id>.<attempt>.<ext>`
(the canonical name of `tool/build_manifest.py name`, plus the existing evaluation label).

## 2. Who can read it: encryption to public keys

The repository is public, and so are the artifacts and logs of its runs; any GitHub account can
download them ([RELEASE_POLICY.md](RELEASE_POLICY.md) sections 3 and 8.2). A kept build therefore
never leaves the runner in readable form:

- The artifact is encrypted with [age](https://age-encryption.org) to the **public** keys listed
  in `config/release/artifact_recipients.txt` (plus, for a manual run, one public key given as an
  input). Only the holder of a matching private key can open it.
- The runner needs no key that can read the file and no credential of any kind: workflow
  permissions stay `contents: read`, there is no secret, no environment, no token. Access control
  is cryptographic, not a setting that can be misconfigured on the repository.
- What is public (and meant to be): the ciphertext, SHA-256 checksums, the build manifest, the
  text evidence and the retained manifest. They contain no key and no binary.
- `age` is installed by `tool/install_age.sh` from the project's release URL with a pinned
  SHA-256 per platform (the same pattern as the pinned bundletool), and nowhere else.
- Every bundle is also encrypted to a **one-time key** that the build job creates, uses to
  decrypt the artifact it just wrote, compares the result with the recorded checksum, and
  deletes. That is the automated proof that the retained ciphertext contains exactly the verified
  file; the recipient the one-time key leaves behind cannot be used by anyone.
- Retention is **days, not weeks** (`RETENTION_DAYS`, 14), the retention the existing evidence
  already has.

### When a run retains

| Trigger | Retains? |
|---|---|
| Push to `staging` / `production` (promotion) | **Only if** `config/release/artifact_recipients.txt` lists at least one key. It is empty today, so promotions behave exactly as before Stage 2 and the run summary says so |
| Manual run with `retain` ticked | Yes, for the committed keys plus the optional `recipient` public key; a run with no key at all is refused (it would be unreadable) |
| Manual run without `retain`, pull requests, other branches | No |

The decision is one tested function (`tool/retain_artifact.py plan`). A push cannot carry the
inputs, and a secret key (`AGE-SECRET-KEY-...`) or any malformed key is refused wherever it appears.

## 3. What a retained bundle contains

One GitHub artifact per variant, `retained_<variant>_a<attempt>`, with exactly five files
(anything else fails verification, so a plaintext binary cannot slip in):

| File | Content |
|---|---|
| `NON-DISTRIBUTABLE_INTERNAL-EVALUATION_<canonical name>.age` | the ciphertext (an `.apk`, `.aab` or `.xcarchive.tar.gz`) |
| `<variant>.retained.json` | the **retained manifest** (`cadena-retained-artifact/1`): source commit and ref, run and attempt, version and build, application ID, configuration file digest, plaintext SHA-256 and size, content digest, the correspondence to the validated build, the recipients' short ids, ciphertext SHA-256 and size, the round-trip result |
| `<variant>.manifest.json` | the unchanged **build manifest** (`cadena-build-manifest/1`: toolchain with Flutter, Dart, Java or Xcode, SDK, CocoaPods and runner image; native library SHA-256; configuration; signing status) |
| `<variant>.txt` | the unchanged text evidence of `tool/verify_artifact.sh` and the workflow |
| `SHA256SUMS` | `sha256sum -c` compatible checksums of the four other files |

Traceability: the retained manifest names the commit, the run, the version, the configuration
digest and the SHA-256 of the build manifest and of the evidence; the build manifest carries the
toolchain. `plaintext.sha256` is the checksum a consumer compares after decrypting.

**Content digest** (`artifact.content`): a digest that does not change when the artifact is signed.
For an APK/AAB it is the SHA-256 of the sorted `<sha256>  <entry>` lines of every zip entry
except `META-INF/MANIFEST.MF` and the `*.SF/*.RSA/*.DSA/*.EC` signature files. For the iOS archive
it is the application directory digest of `tool/verify_artifact.sh` (the digest of the validated
build's `Runner.app`), plus the executable and Dart snapshot digests. A signing stage uses it to
prove that signing changed nothing but the signature (section 6).

## 4. How the retained artifact is tied to the verified build

Inside the build job, in this order, and each step fails the job:

1. The build is made and read back by `tool/verify_artifact.sh` (identity, version, signing,
   environment); the manifest is created and verified against the repository
   (`tool/build_manifest.py`). **Unchanged by Stage 2.**
2. **Android:** the file that is packed must have the SHA-256 and size that the evidence recorded
   for the verified artifact. It is the same file, not a rebuild.
3. **iOS:** the archive is built with `flutter build ipa --release --no-codesign` (same flavor, same
   configuration file); its `Runner.app` is verified by the same `tool/verify_artifact.sh`; the
   identity, version, signing state, minimum OS and architecture must equal the validated
   `flutter build ios` build, and `tool/check_build_drift.sh` must still find no changed tracked
   file. The archive application's directory, executable and Dart-snapshot digests are compared
   with the validated build's and the result is **recorded** (`correspondence_to_validated_build`),
   because an archive is a second compile; `--require-identical` makes inequality fatal.
4. The bundle is written, then verified by `tool/retain_artifact.py verify` (section 5).

The `verdict` job then requires one bundle per required variant (and none for others), downloads
them, and verifies each against the repository and **against the evidence of the same run**
(byte-equal build manifest and text evidence). A run that retains is green only if every required
artifact was retained and verified.

## 5. Verification, by anyone and by the key holder

```bash
# Anyone (no key): the bundle is consistent, ciphertext only, and describes the verified build.
python3 -I tool/retain_artifact.py verify DIR --repo . --against EVIDENCE_DIR

# A key holder (with the identity file kept off the repository and off GitHub):
python3 -I tool/retain_artifact.py verify DIR --identity age-identity.txt
python3 -I tool/retain_artifact.py unpack DIR --identity age-identity.txt --out OUT
```

`verify` without a key checks: the exact file set; every checksum of `SHA256SUMS`; that the `.age`
file starts with the age header; that the ciphertext checksum and size match the retained manifest;
that no file other than the ciphertext exceeds 1 MiB or contains a secret-key marker; that the
retained manifest equals the build manifest (commit, ref, run, attempt, build id, version,
application ID, configuration digest, environment, signing) and that both verify against
`tool/build_manifest.py`. With a key it also decrypts and checks the plaintext checksum and size,
the content digest, and for the iOS archive: safe extraction (regular files only, no path
escapes), the application digest, `Info.plist` identity and version, and that the application is
**unsigned** (no `_CodeSignature`, no profile). `unpack` writes the APK/AAB, or `Runner.xcarchive`.

`tool/test_retained_artifacts.sh` (run by the `plan` job before any build, with the pinned age
required) demonstrates all of it on synthetic fixtures with real manifests: which runs retain; the
refusals (a secret key, a malformed key, no recipient, a push with inputs); a bundle that is
ciphertext only; the content digest staying stable under re-signing and changing with content; a
tampered ciphertext, an extra plaintext file, a missing or wrong `SHA256SUMS`, another commit or
another build's evidence, a missing round trip, a signed archive, and an artifact that is not the
verified one; and the round trip to the key holder, byte for byte.

## 6. Consuming a retained artifact (the signing stage)

Both stages below are **Stage 3** work and need credentials that do not exist in the pipeline
today (section 8). What a signing job must do, and what is already provided:

**Common.** The job runs on the commit of the retained manifest (`source.commit`), unpacks the
bundle with a key that is a recipient (`unpack`), and refuses to continue unless `verify` with that
key passes and the retained manifest's commit is the one the release authority approved.

**Android (AAB for Google Play, APK for the website).**
1. `unpack` gives the debug-signed file; its `content.sha256` is the signature-independent digest.
2. Remove the debug signature and sign with the Cadena upload key: for an AAB delete the
   `META-INF/*.SF|*.RSA|*.DSA|*.EC` entries and `META-INF/MANIFEST.MF`, then `jarsigner` with the upload
   key; for an APK `apksigner sign` (it replaces an existing signature) after `zipalign`.
3. Compute the same content digest of the signed file (`zip_content_digest` in
   `tool/retain_artifact.py`) and require equality with the retained manifest: the signed artifact
   contains exactly the verified entries. Then run the existing release verifier
   (`tool/verify_android_release.py`, [ANDROID_RELEASE.md](ANDROID_RELEASE.md) section 4) for the
   certificate fingerprint, schemes and ledger gate.
   Re-signing keeps the verified bits; the alternative of the existing procedure
   (`tool/release_android.sh`: rebuild the commit with `CADENA_SIGNING=release`) stays valid and
   is what produced 1.0.4; a signing job may prefer it, in which case the retained debug-signed file is
   the reference for comparing the content digest.

**iOS (App Store Connect / TestFlight).**
1. `unpack` gives `OUT/Runner.xcarchive` with `Products/Applications/Runner.app` (unsigned) and `dSYMs/`.
2. On macOS with Xcode 26.3, export and sign it with Xcode's supported route and the same
   `ExportOptions.plist` as [IOS_RELEASE.md](IOS_RELEASE.md) section 8 (`method`
   `app-store-connect`, `manageAppVersionAndBuildNumber` false, manual signing with the profile of the
   bundle ID):
   ```bash
   xcodebuild -exportArchive -archivePath OUT/Runner.xcarchive \
     -exportOptionsPlist ExportOptions.plist -exportPath OUT/ipa
   ```
3. Verify the IPA with `tool/verify_ipa.py` and compare it with the unsigned application using its
   `compare` mode (the signed `Runner.app` must equal the retained one apart from the signature;
   the retained `content.sha256`, `executable_sha256` and `app_snapshot_sha256` are the references).
4. Upload with the App Store Connect API key (Transporter / `xcrun altool`), delivering to
   TestFlight with **TestFlight & App Store**, never "Internal Only"
   ([IOS_RELEASE.md](IOS_RELEASE.md) section 8).

**Not shown yet.** Whether `xcodebuild -exportArchive` signs an archive that was built unsigned is
**unconfirmed**: it can only be tested with Apple-authorised signing material (IOS_SIGNING.md
section 3.2). The archive carries only the entitlements the project declares (none today), so
the open source decisions (push entitlement, privacy manifest, export-compliance key) must be made
**before** the archive is built; export does not invent them.

## 7. Running it

- **Demonstration or one-off:** Actions, *Build variants*, *Run workflow*, choose a variant or
  `all`, tick **retain**, and give your own age **public** key in **recipient**. Generate the pair
  with `age-keygen -o identity.txt` and publish only the `age1...` line. Keep `identity.txt` off the
  repository, off GitHub and out of chats. Download `retained_<variant>_a<attempt>` and use
  `retain_artifact.py verify` / `unpack` as in section 5.
- **Every promotion:** a reviewed pull request adds the custodians' public keys to
  `config/release/artifact_recipients.txt`. From the next promotion, each of the 2 (staging) or 3
  (production) verified builds is retained. Removing the keys turns retention off again.
- Disabling or removing a key does not affect artifacts that already exist; they expire after
  `RETENTION_DAYS`.

## 8. What Stage 3 still needs (technical and credential prerequisites)

Stage 3 must sign and deliver both platforms from a retained artifact. Nothing below exists yet;
none of it is created by Stage 2.

| # | Prerequisite | Kind | Notes |
|---|---|---|---|
| 1 | **Recipient keys**: the custodians' and a dedicated key for the signing job | Decision, then a reviewed PR | The signing job's **private** key becomes a protected-environment secret. Decide who holds the custodian keys and whether the signing job decrypts or instead builds and signs in one job |
| 2 | **Protected GitHub environments** (`staging-android`, `staging-ios`, `production-android`, `production-ios`) with branch restriction and required reviewers | GitHub administration | None exist ([RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md) section 4). The two Maintainers accounts are one individual, so a second human reviewer is needed for independent approval of production signing |
| 3 | **Android upload key** in `production-android` (and a staging key) | Credential | Today held by the CFO and used locally; moving it to CI is a custody decision. Needs `CADENA_EXPECTED_CERT_SHA256` of the upload key (public) |
| 4 | **Google Play delivery**: a service account with the Play Developer API and a track decision (internal, then production) | Credential and decision | The AAB version code must be above the published floor |
| 5 | **Apple distribution certificate and App Store profile** (or an App Store Connect API key for automatic signing) in `production-ios` / `staging-ios` | Credential | Cadena-held, not individual; [IOS_SIGNING.md](IOS_SIGNING.md) section 2 |
| 6 | **App Store Connect API key** (issuer id, key id, `.p8`) for upload to TestFlight | Credential | One key per scope; upload only, no App Review submission |
| 7 | **Which App Store Connect record** receives builds (the staging record of the policy, or the production record as for 1.0.4) | Decision | |
| 8 | **macOS signing job**: a `macos-15` runner with Xcode 26.3, a temporary keychain, `xcodebuild -exportArchive` (the untested step of section 6) | Technical | The first run with real material answers the unconfirmed export question |
| 9 | **Resolved source decisions** that the archive bakes in: push entitlement, privacy manifest, export-compliance key, minimum iOS, BGTask identifier | Source change through the normal release cycle | See [IOS_RELEASE.md](IOS_RELEASE.md) section 13 and the 1.0.4 record |
| 10 | **Release identifier and tag** (`vX.Y.Z-rc.N` / `vX.Y.Z`), who creates it | Decision | RELEASE_VERSIONING.md open decisions 1 to 3 |
| 11 | **Provenance**: GitHub artifact attestations for the retained and the signed files | Technical | Needs `id-token` and `attestations` write permission on the job that attests |
| 12 | **iOS ledger entry** after delivery, and a platform-scoped `gate` | Source change | `gate --channel production` reports Android's published build as an iOS failure today |
| 13 | **Approval model for publication** | Decision | A merge builds and signs; publishing to a store stays behind its own approval ([RELEASE_POLICY.md](RELEASE_POLICY.md) section 8) |
| 14 | **Acceptance test**: a new application version built and delivered by the pipeline alone | Test | Needs 1 to 8 and a version above both platforms' floors |

## 9. Limits, stated plainly

- This is **compile validation plus retention**. The kept artifacts are debug-signed (Android) or
  unsigned (iOS). They prove what was built from which commit; they do not prove runtime behaviour,
  and a signing stage has not been run on them.
- The iOS archive is a second compile of the same source. Its application is verified like the
  validated build and compared with it; whether it is bit-identical is recorded per run, not assumed
  (see the run evidence in the pull request).
- Encryption protects the content from readers without a key. It does not hide that an artifact
  exists, its size, its checksums or its manifest, which are public by design.
- Anyone who holds a recipient private key can read every artifact encrypted to it; key custody is
  the release authority's responsibility. A lost key means the artifact is unrecoverable (rebuild
  it from the commit).
- Nothing in this stage changes the application, a build variant, a version, a signing
  configuration or any promotion. The release `production` branch and the published 1.0.4 are untouched.
