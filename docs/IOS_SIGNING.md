# iOS signing and TestFlight delivery (Issue #71)

> **Status: readiness documentation. iOS signing and TestFlight delivery are NOT
> implemented.** No certificate, provisioning profile, App Store Connect API key,
> App Store Connect record, GitHub environment or signing workflow has been created, and
> none may be created from this document alone. The only iOS builds that exist are the
> unsigned compile-validation builds of [IOS_CI.md](IOS_CI.md). This page records what is
> verified, what is approved, and what is still undecided, so that nobody mistakes one
> for another. Parent issue: #54. It follows [RELEASE_POLICY.md](RELEASE_POLICY.md) and
> [RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md) and adds no rule to
> either.
>
> **Update 2026-11-08.** The credential-free hosted signing experiment was run, failed and was
> diagnosed; it is closed (section 3.3). The cause is the throwaway self-signed identity, not the
> application, the workflow or a missing Apple resource. It also means that **nothing about signing
> this application with `codesign` has been shown yet**: everything that remains needs
> Apple-authorised signing material. App Store Connect API access is reported disabled for the
> organization (section 4, item 13).

Every statement below carries one of three labels:

| Label | Meaning |
|---|---|
| **Verified** | Checked in the repository, on GitHub or in Apple's documentation, on the stated date. |
| **Approved** | Decided by the project owners. It is the architecture to build, not a statement of fact about the world. |
| **Unresolved** | Not decided, or not yet confirmable. Nothing may assume an answer. |

## 1. Verified facts (checked 2026-10-21 on `development` `b7e523a`)

### Repository

| Fact | Where |
|---|---|
| Two flavors exist, `staging` and `production`, with their own Xcode schemes and `Debug/Profile/Release-<flavor>` configurations. | `ios/Runner.xcodeproj`, `ios/Flutter/*-staging.xcconfig`, `*-production.xcconfig` |
| Bundle IDs: staging `com.app.cadenabitcoin.staging` ("Cadena Signer STAGING"), production `com.app.cadenabitcoin` ("Cadena Bitcoin"). | `ios/Flutter/Flavor-*.xcconfig` |
| `DEVELOPMENT_TEAM = D65458CPDP` is committed (an identifier, not a secret). The Runner target sets no `CODE_SIGN_STYLE`, profile specifier or signing identity, so Xcode's default (automatic) applies. | `ios/Runner.xcodeproj/project.pbxproj` |
| No entitlements file, no `ExportOptions.plist`, no certificate, profile, `.p8`, keystore or `key.properties` is tracked. | `git ls-files` |
| The app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`). `CFBundleShortVersionString` and `CFBundleVersion` come from `pubspec.yaml` (`1.0.3+1000034`). | project, `Info.plist` |
| `Info.plist` has no `ITSAppUsesNonExemptEncryption`. It lists `UIBackgroundModes` `fetch` and `remote-notification` and one `BGTaskSchedulerPermittedIdentifiers` entry; there is no `processing` mode and no push entitlement. The app has no `PrivacyInfo.xcprivacy`. The App Store icon `1024.png` is a JPEG with a `.png` name. | `ios/Runner` |
| `RELEASE_IDENTIFIER` and an in-app staging identifier do not exist yet. | `lib`, `config`, `tool` |
| Both iOS workflows use `contents: read`, no secrets, SHA-pinned actions, `--no-codesign`. They run on `macos-15` with Xcode 26.3. | `.github/workflows`, [IOS_CI.md](IOS_CI.md) |
| The minimum-iOS requirement of [IOS_CI.md](IOS_CI.md) is open: app 14.0, five frameworks 15.5, eight Rust objects 18.5. | [IOS_CI.md](IOS_CI.md) |
| No iOS build number is recorded as published, so no iOS floor is enforced. The published **Android** package is `com.cadenabitcoin.mobile.signer`, which differs from the bundle ID used here. Git history shows the iOS bundle ID has never been anything but `com.app.cadenabitcoin`, so nothing in the repository shows what Apple has registered. | `config/release/published_versions.json`, `git log` |

### GitHub

| Fact | Source |
|---|---|
| The repository is **public**. Run logs and artifacts are readable by any GitHub account. | GitHub API |
| No GitHub environment exists (`total_count` 0). | GitHub API |
| `CadenaBitcoin/Maintainers` has two accounts. **They are controlled by one individual** (statement of the project owner, 2026-10-21; restated by the CTO 2026-11-17), so they are **one** person. The merge by that person is the authorization (section 6). | owner statement; [GOVERNANCE.md](../GOVERNANCE.md) |
| No release maintainers or signing custodians are named. | [GOVERNANCE.md](../GOVERNANCE.md) |

### Apple (documentation read 2026-10-21)

| Fact | Source |
|---|---|
| There are two kinds of App Store Connect API key: team keys ("access to all apps, with varying levels of access based on selected roles") and individual keys ("access and roles of the associated user"). | [Creating API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) |
| "Team keys give access that's not isolated to a single app, but individual key access is tied to the apps and permissions of the user." "Team API keys are applied across all apps, so app access can't be limited for an API key." | same; [App Store Connect Help](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api) |
| Individual keys "aren't able to use Provisioning endpoints, access Sales and Finance, or notaryTool". | [Creating API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) |
| "Each user can only have one active API key at a time." A key's name and access cannot be edited after it is generated. Generating a team key needs the Account Holder or Admin role. Generating an individual key needs the "Generate Individual API Keys" permission, which an Admin can remove. | [App Store Connect Help](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api) |
| The private key can be downloaded **once**; Apple keeps no copy. A revoked key cannot be reinstated. | both pages |
| The role-permission matrix has rows "Upload builds", "Submit apps", "Manage internal TestFlight groups and add builds" and "Manage app access". Certificate and profile tasks are marked as needing access to Certificates, Identifiers & Profiles, "granted as a separate permission in Users and Access". | [Roles](https://developer.apple.com/support/roles/) |
| "Users with the Developer role can create and revoke development certificates, submit certificate signing requests, download provisioning profiles, upload binaries to App Store Connect, manage internal TestFlight users, and more. Their access can be limited to certain apps." | [Developer role](https://developer.apple.com/help/glossary/developer) |
| "If you're enrolled as an individual and add users in App Store Connect, users receive access only to App Store Connect and are not considered part of your team in the Apple Developer Program." | [Developer role](https://developer.apple.com/help/glossary/developer) |

The role matrix's per-role marks could not be extracted from the page text, so **which role may
upload, which may submit for review, and which needs Certificates, Identifiers & Profiles
access is not verified** here (section 4, item 3).

## 2. Approved architecture

Decided by the project owners (Issue #71 audit and approval, 2026-10-21). Staging and
production contexts and the five-artifact target are in [RELEASE_POLICY.md](RELEASE_POLICY.md).

1. **First delivery target: internal-only TestFlight** of a separate staging record. No
   external tester group, no public link, no Beta App Review, no App Store submission.
2. **Separate GitHub environments** for staging and production, each deployable from one
   protected branch only.
3. **No public App Store submission or publication** by any pipeline: approved 2026-10-21 and
   confirmed by the CTO on 2026-11-17: automatic App Review submission and public publication are outside the
   configured automated delivery, and may be added only by an explicit architectural extension of
   RELEASE_POLICY.md 2.3.
   Production signing and production upload are authorized by the merge into `production`
   (RELEASE_POLICY.md 2.3), not by a separate approval.
4. **Controlled signed testing is permitted** to establish runtime compatibility. The
   effective minimum supported iOS version remains an **open release-readiness
   requirement** ([IOS_CI.md](IOS_CI.md)); a production release needs verified runtime
   compatibility, and this issue does not change a deployment target.
5. **The authorized merge is the authorization** (section 6); no second human is required or claimed.
6. **Internal tester delivery** runs on the staging merge (RELEASE_POLICY.md 8.1). Until a pipeline
   exists, assigning a processed build to internal testers is a manual operation the CTO authorizes in writing.
7. **Least-privilege Apple authentication**, with app-restricted individual API
   credentials as the preferred direction. The model is **not final** (section 5).
8. Signed IPAs are never stored as GitHub artifacts, Releases or log content.

## 3. Planned pipeline (proposed; not built; shape subject to a spike)

Everything in this section, and every "will" or imperative in sections 5 to 8, describes the
intended design. None of it exists yet.

```text
push to staging (reviewed PR merge)
  -> build job, NO secrets: dependencies, compile, unsigned archive, digest
  -> signing job, environment staging-ios: sign, export, verify, record evidence
  -> upload to the staging App Store Connect record, read processing state
  -> STOP: a build is assigned to internal testers only after explicit approval
```

- **Two-job split (Proposed).** Everything that downloads or runs third-party code (`pod install`,
  Flutter, Gradle-style fetches) runs in a job with no secrets. The job that holds signing
  material runs only scripts owned and tested in this repository and Apple's own tools, and
  checks the archive digest produced by the first job. The unsigned archive would be a
  one-day artifact (it is the open-source app, like today's unsigned validation artifact).
  **Open technical question:** whether an unsigned archive can be exported and re-signed
  cleanly, or the signing job must codesign and package the IPA itself. The
  credential-free spike (a throwaway self-signed identity on a hosted runner) could not answer it
  (section 3.3), so it is answered by the first signing run with Apple-authorised material. If the
  split proves impossible, a single job is the fallback and its extra exposure is documented. What is already
  established without Apple, and what the spike still has to show, is in section 3.2.
- **New workflow files** (stage T3 of [RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md));
  the unsigned validation workflows keep their meaning.
- **Verification before upload** (`tool/verify_ipa.py`, written and tested on synthetic fixtures,
  not yet used by any workflow; section 3.1): bundle ID, version and build number against
  `pubspec.yaml` and the manifest, Team ID, signing authority and certificate fingerprint,
  provisioning-profile type, team, App ID and expiry, entitlements (`get-task-allow` absent),
  signature integrity. Evidence is text only.
- **Build numbers** stay single-sourced from `pubspec.yaml`. Apple rejects a repeated build
  number, and the pipeline treats that as a hard stop, never as something to work around.
- A static test must fail if any workflow uses `pull_request_target`, or contains a
  review-submission or release call to App Store Connect.

### 3.1 IPA verification tooling (implemented 2026-10-22; not wired into any workflow)

| File | Purpose |
|---|---|
| `tool/verify_ipa.py` | `verify ENV IPA --team-id T`: the checks below. `structure APP_OR_IPA`: the same signature, entitlement and seal checks without judging the identity (used to read what Apple's `codesign` wrote). `compare UNSIGNED SIGNED`: is the signed bundle the unsigned one plus signatures only (the embedded profile may differ, so a baseline taken from a development-signed archive is accepted). `analyze-unsigned APP`: what re-signing a given unsigned bundle involves. `certificate APP_OR_IPA [--pem FILE]`: reads the **public** signing certificate and its SHA-256 fingerprint from the signed artifact (no keychain, no private key; the way to obtain the fingerprint of a cloud-managed certificate), checks that every executable carries that one certificate and that the embedded profile lists it; it pins and approves nothing, shows a chain to Apple only when `--trust-anchors` is given, and never checks revocation. Discovering a certificate is not approving it: the identity is approved by the release coordinator's record, not by this command. `verify --forbid-entitlement KEY` (repeatable): fails when a signed entitlement, e.g. `aps-environment`, is present. |
| `tool/ipa_inspect.py` | The reader (Mach-O, code signature, CodeDirectory, entitlements, CodeResources, CMS, provisioning profile). Standard library plus the `openssl` command for CMS signature validity. Read-only; it needs no credential and no Xcode. |
| `tool/ipa_fixture.py` | **Test tooling only.** Synthetic apps, a throwaway certificate chain whose names say "Synthetic", a fake profile and a signer that writes the structures Apple's `codesign` writes. Nothing it makes is accepted by Apple or a device. |
| `tool/test_verify_ipa.sh` | 117 checks (118 with a real build): acceptance cases and about 70 rejections. `REAL_UNSIGNED_APP=...` also re-signs a real unsigned build. |
| `tool/test_ios_signing_experiment.sh` | 17 static checks of the hosted experiment (section 3.3). |

`verify` checks, from the IPA alone: bundle identifier, display name, version and build number for the
environment and `pubspec.yaml` (staging and production cannot mix); that every executable is signed
(not ad hoc) by **one** certificate for the expected Team ID; the CodeDirectory page hashes, special
slots (Info.plist, requirements, CodeResources, entitlements) and the bundle's CodeResources against
the files (nothing changed or added after signing); the CMS signature and that it binds every
CodeDirectory; the certificate (distribution certificate, Team ID, issuer, validity, SHA-256
fingerprint, **pinned** with `--expect-cert-sha256`, required for production); the embedded profile
(CMS signature valid, app-store type, no device list, exact App ID, team, not expired, contains the
signing certificate); the entitlements (application identifier, team, `get-task-allow` absent,
`aps-environment` production, every entitlement granted by the profile); the IPA digest handed over by
the signing job; and, with the build manifest and the unsigned bundle, that the manifest describes
that bundle and the IPA contains the same code with signatures only. Archives with unsafe member
names, links leaving the bundle or more than one app are refused.

| Evidence level | What it covers |
|---|---|
| **Verified on real data** (accepted run `39608182641`, its unsigned artifact) | The parser reads the real signatures: the Apple-signed Swift runtime library has two CodeDirectories (SHA-1 and SHA-256), `openssl` verifies its CMS signature, and the Apple "cdhashes" attribute lists both; page hashes, the Info.plist, requirements and CodeResources special slots and the `CodeResources` of Flutter's and `App`'s frameworks all match. |
| **Verified on real data** (Authorization C, run `44834801248`: the first Apple-signed IPA; Phase 1 of the verifier repair) | The 16 CMS signatures that Apple's cloud-managed signing service returned parse; their `cdhashes` attribute is an XML property list that starts with `<!DOCTYPE plist` and has **no XML declaration**, which Python's automatic plist detection rejects, so it is read with an explicit format; the RSA signature over their signed attributes verifies with `openssl`, and a modified attribute does not. The Info.plist seal (special slot 1) of the Apple-signed Swift runtime library is the hash of its embedded `__TEXT,__info_plist` section, in both CodeDirectories, so a Mach-O without an Info.plist file is checked against that section. Fixtures and provenance: `tool/fixtures/`, `tool/test_verify_ipa.sh` section 11. **Not confirmed on real data at that time:** the layout of the DER entitlements (the parser then assumed a `SET` body; it is `[CONTEXT 16]`, see section 3.1a: observed in D1, repaired in Phase 6B) and what Xcode's export changes in the app's `Info.plist` (the V8 comparison; the signed IPA was not retained). |
| **Verified on synthetic fixtures** | Every check above, including the rejections: tampered executable, resource, Info.plist or CMS; added file; replaced alternate CodeDirectory; ad-hoc or unsigned code; foreign signer; wrong team, certificate, issuer, expiry or pin; missing, expired, ad-hoc, development, wildcard or foreign profile; entitlements not granted, `get-task-allow`, `aps-environment`; wrong bundle, version or environment; unsafe archives; manifest of another environment; recompiled or injected content. Breaking three of the checks on purpose made the matching test fail. |
| **Needs a real Apple-signed IPA** | The certificate chain to an Apple root and revocation (no Apple trust anchors are used); how Apple's `codesign` lists nested bundles in the app's `CodeResources` (each nested bundle is verified on its own; the outer linkage is not); the keys of a real App Store profile and of the entitlements Xcode adds (a missing grant is a failure here, so the first real IPA may need a documented, reviewed allowance); whether export rewrites any file (`compare` requires byte-identical non-executables and names any file that differs); the `SwiftSupport` folder. |
| **Needs Apple or a device** | App Store Connect validation and processing; installation and runtime behaviour. |

Every run prints what it cannot verify. A pass is evidence about the files, not an Apple approval.

**Genuine versus synthetic identities.** The issuer is compared **by name only** unless the operator
supplies `--trust-anchors` (the Apple root and intermediate certificates, kept and reviewed by the
operator; nothing here ships or assumes them), in which case the signing chain and the profile's signer
chain are verified with `openssl verify` at the time given by `--now`. A certificate whose name says
"Synthetic" or "Throwaway" is refused unless `--allow-synthetic` is given, and is **never** accepted for
production. Production also requires `--expect-cert-sha256`, the fingerprint from the custody register: a
pinned leaf certificate is the strongest statement this tool can make without Apple's trust anchors.

**Security review of the verifier (2026-10-22).** Thirteen ways to a false pass were found, each
reproduced against the first version (all thirteen passed it) and now rejected, with a regression test:
a CMS signature naming its signer by key identifier so that the pinned certificate could be listed first
and reported as the signer; a CodeDirectory hashing only the first pages of the file; data appended
after the signature; DER entitlements (the form the kernel enforces) differing from the XML ones, or
changed after signing; an executable not built for arm64; a 32-bit Mach-O skipped as "not code"; a
nested app extension that would need its own profile; a `..` path in `CodeResources`; a nested cdhash in
`CodeResources` that is not the nested code's; a nested binary signed again after the app was sealed
(the stale seal was filtered out as "covered separately"); files hidden in `_CodeSignature/`; a profile
for another platform. Also closed: a CMS signature read differently by this parser and by `openssl`
(the signer and the verified content are now the ones `openssl` used), a weak CMS digest, duplicate or
encrypted archive members, a non-plain `CFBundleExecutable`, and any internal error (it is a failed
verification, never a pass or a stack trace).

One rule was **removed** because real data contradicted it: non-zero bytes between the end of the
SuperBlob and the end of its reserved area. Real Apple and Flutter signatures leave stale data there
(seen in the accepted CI artifact), so refusing it would reject genuine IPAs; bytes after the reserved
area are still refused.

**Still unverified against a real Apple-signed IPA** (the first one may need a reviewed adjustment):
the DER-entitlements layout of a **Distribution-signed** IPA (the layout of Apple's own ad-hoc output is known since D1, section 3.1a; it was first decoded from public descriptions and wrongly assumed to be a `SET`), how Apple's
`codesign` lists nested bundles in `CodeResources` (the hosted experiment, section 3.3, reads this from
a real `codesign` run), the keys of a real App Store profile, and whether a certificate chain from
Apple's real roots verifies as expected.

### 3.1a Phase 2 of the verifier repair (Issue #71): DER entitlements and the Info.plist comparison

Phase 1 repaired what the first Apple-signed IPA (Authorization C, run `44834801248`) proved wrong in the verifier. Two failures
remained and **no acceptance rule was changed for either of them in Phase 2**: there was not yet genuine evidence to change them on.
Each conclusion below is labelled **confirmed**, **probable** or **unresolved**.

**Current contract for the DER entitlements (Phases 6B and 6C-B; this supersedes the Phase 2 table below, which is kept as the history of what
was assumed and why).** Observed on the output of Apple's own `codesign --generate-entitlement-der` (Authorization D1, run `44956044650`: seven
distinct blobs, the same on iOS and macOS targets), and parsed by `parse_der_entitlements` (`tool/ipa_inspect.py`):

```
magic 0xfade7172 | length | [APPLICATION 16] constructed {
    INTEGER 1,                                   (the version)
    [CONTEXT 16] constructed {                   (the entitlements dictionary: NOT an ASN.1 SET)
        SEQUENCE { UTF8String key, value } ...   (one SEQUENCE per entry)
    }
}
value = BOOLEAN (00 or ff) | INTEGER (shortest two's complement) | UTF8String
      | SEQUENCE { value ... }          (an array)
      | [CONTEXT 16] { SEQUENCE { UTF8String key, value } ... }   (a nested dictionary: the same encoding as the root, also inside an array)
```

The root holds exactly these two elements. Apple writes the entries of every dictionary sorted bytewise by key. The parser refuses the obsolete `SET` layout everywhere, checks the
class, tag and constructed flag of every element it reads, and keeps the version requirement and the refusal of duplicate keys, malformed
entries and unsupported values. The seven Apple blobs are committed byte for byte, with their SHA-256 digests, as independent test vectors
(`tool/fixtures/apple_der_entitlements_d1_run44956044650.txt`, `tool/test_verify_ipa.sh` section 14); the synthetic writer in
`tool/ipa_fixture.py` follows the same layout and is checked against them, never the other way round. The DER entitlements must equal the XML
entitlements in value **and type** (`plist_equal_strict`: a BOOLEAN is not an INTEGER), and so must the entitlements of every slice of a
universal executable.

**Strict DER (Phase 6C-B).** `parse_der_entitlements` reads the blob with a strict DER reader of its own (`_der_strict_node`; the lenient BER
reader that CMS verification needs is unchanged). DER has exactly one encoding for every value, so refusing the others removes specific
encoding ambiguities and **reduces the risk of a parser differential** with the kernel's reader. It does **not** establish that the two
readers are equivalent: Apple's reader has not been examined, and what it accepts or refuses beyond DER is unknown.

What the reader refuses, naming the rule and the byte offset. *Because ASN.1 DER forbids it:* an indefinite length; a length that is not
minimal (the long form for a value below 128, or a leading zero octet) or that takes more than four octets (the four-octet bound is a
practical limit of this reader); a tag number in the high-tag form below 31 or with a leading zero; a BOOLEAN that is not exactly one octet,
`00` or `ff` (BER reads any non-zero octet as TRUE, so `01` would be ambiguous); an INTEGER that is empty or not in its shortest
two's-complement form. *Because of this application, not because DER requires it:* a root with other than exactly two elements (the layout
Apple's output shows: version, dictionary), and nesting deeper than `MAX_DER_ENTITLEMENTS_DEPTH` = 32 levels (the root being level 0, each
nested dictionary adding two levels and each nested array one; Apple's deepest observed blob has 7, a blob at the limit needs about 35 stack
frames).

Every refusal is a recorded problem of the verification (`DER entitlements are unreadable: ...`): the other checks still run and the evidence
is still written, a `RecursionError` included. All seven Apple blobs satisfy every rule. The synthetic cases are in `tool/test_verify_ipa.sh`
section 15.

Not part of the contract (still deferred): key order, empty or NUL keys, non-ASCII keys, Unicode normalisation, and limits on the size of a
value or on the number of entries.
Not observed: non-ASCII keys, integers wider than 32 bits, `real`, `data` and `date` values (Apple's XML parser rejected those shapes, and
duplicate keys, before any DER was written), and whether the blob of a **Distribution** signature equals that of an ad-hoc one.

**DER entitlements, at the end of Phase 2** (history; `parse_der_entitlements`, `tool/ipa_inspect.py`; the real blob was not kept):

| | |
|---|---|
| Confirmed | The failure text `unsupported DER entitlements version or layout` is raised only after the blob header (magic, length) was right, the whole blob was one valid ASN.1 element and that element was `[APPLICATION 16]`. So Apple's real blob has that outer shape, and fails on exactly one of: the first child is not `INTEGER 1`, or the second child is not tag 17 (`SET`). This follows from the message and the code, not from the blob. (D1 showed it was the second.) |
| Probable | The second child is a context-specific `[16]`, as public descriptions say (Project Zero, `apple-codesign`): the parser's `SET` is then wrong. Not seen on Apple data at that time. **Confirmed by D1:** the dictionary is `[CONTEXT 16]` (see the current contract above). |
| Unresolved | The exact layout; the encodings of integers, arrays, nested dictionaries and booleans; key order; what Apple's tool does with duplicate keys and with `real`, `data` and `date` values; whether the blob of a Distribution signature equals that of an ad-hoc one. **After D1:** the layout, the encodings of integers, arrays, nested dictionaries and booleans, and the key order are known (ad-hoc output); the XML parser of Apple's tool refused duplicate keys, `real`, `data` and `date` values; the Distribution question remains open. |
| Evidence search | No suitable blob exists: `Packaging.log` holds no DER bytes (it logs the `codesign` arguments, including `--generate-entitlement-der`, and the cloud request, which carries only the CodeDirectory digest); a scan of every file of the preserved unsigned archive finds no DER entitlements blob (magic `0xfade7172`, 0 hits); the earlier feasibility experiment never completed and never asked for DER entitlements. |
| Prepared; temporary activation copy prepared in Phase 4, never run | `docs/workflow-templates/ios-der-entitlements-diagnostics.yml.template` is the reviewed **template, not a workflow** (outside `.github/workflows/`, so nothing can start it) and stays in the repository. Phase 4 prepares its **activation copy**, `.github/workflows/ios-der-entitlements-diagnostics.yml` (identical code), for **one** authorized run: it exists on `development` only from the merge of a reviewed activation pull request until a second reviewed pull request removes it, and a workflow file there can be started by anyone with write access, from any branch, with no gate of GitHub's; nothing starts it without a separate written authorization that names the run (section 3.1c). It runs `tool/probe_der_entitlements.sh`: Apple's own `codesign --generate-entitlement-der` signs a **disposable** program ad hoc on a macOS runner with the real app's four entitlements and then every value type, and `tool/der_entitlements_probe.py` prints, per case, the file identity, the CodeDirectory facts, the special-slot seals, the DER blob's size, digest, bytes (hex, at most 4 KiB) and an outline that assumes no layout; the whole signed file (base64, at most 64 KiB) for **three** chosen cases only. A case counts as DER evidence only if signing, Apple's `codesign --verify` **and** the probe's evidence checks all succeed (readable Mach-O, every slice signed with a CodeDirectory, DER and XML blobs present, a valid container whose body is exactly one ASN.1 element, both blobs sealed by the CodeDirectory); the current parser's verdict is reported apart and **never required**, because it may legitimately refuse genuine Apple data. The script exits 0 only if the three required (dump) cases yield evidence **and** their complete signed executables were actually emitted (`fixture_dump`, reported apart from the evidence: the script decodes each dump and checks its size and SHA-256; a dump withheld because the identifier differs, refused because the file exceeds 64 KiB, or cut short is a failed required case, however complete the DER evidence is); a `codesign` that "succeeds" but leaves an unreadable or unsigned file, or no DER blob, is a failed run. Raw output is an explicit operator-given control (`--synthetic-identifier`): the probe prints it only when every CodeDirectory identifier equals the given one exactly and no CMS signature is present. **That does not prove a file was made by the disposable procedure** (anyone controlling a file can write that identifier); it guards against printing a real application's bytes by mistake, and the script is what makes the input disposable by building and signing it itself. An ad-hoc blob shows the format Apple's `codesign` writes. **Confirmed in `Packaging.log`:** Xcode's own local call for every one of the 16 signed items, the main app included, is itself an ad-hoc call (`codesign -f -s - ... --generate-entitlement-der`), the cloud request carries only the CodeDirectory digest, and the CMS signature is attached afterwards (`codesign -e --edit-cms`). The blob in the real IPA was therefore written by a call of the kind the probe makes (strong evidence of its layout, not proof: the real entitlements and exact flags differ). The signing variants and their roles, the evidence-recovery procedure and the logging exception are in section 3.1b; the temporary activation, its safeguards, lifecycle and failure handling are in section 3.1c. |
| Also kept | If a verification meets an unreadable DER blob again, its report now prints the blob's size, SHA-256, header and an ASN.1 outline of **structure only** (classes, tags, lengths, small integers and booleans). It never prints a real IPA's bytes or the text of its strings; those are printed only for the disposable synthetic input of the probe. The failure itself is unchanged. |

**Info.plist comparison** (`same_code_check`, the V8 check; the signed IPA was not retained):

| | |
|---|---|
| Confirmed | The only file that differs from the unsigned build, apart from the signature seals and the embedded profile, is the top-level `Info.plist` (77 other files byte-identical, 16 executables identical apart from signatures, no file missing or added). The packaging log shows Xcode's `IDEDistributionInfoPlistStep` skipping every framework ("is a framework or embedded in a framework") and records no change for the app. The export used `manageAppVersionAndBuildNumber = 0`. In the signed `Info.plist` the verifier read the same bundle identifier, display name, version (1.0.4), build (1000035), platform (iphoneos), minimum OS (14.0) and SDK (iphoneos26.2) as in the archive, and no `ITSAppUsesNonExemptEncryption` (as in the archive). |
| Probable | The archive's `Info.plist` is a binary property list; Xcode may have re-serialized it and/or added keys. Neither is shown. |
| Unresolved | **What Xcode changed.** Not asserted harmless. The log records no key or value. |
| Diagnostic added | When a property list differs, the comparison now lists keys added, removed and changed (with value types), says whether the content is equal in value **and type** (a difference of serialization only) and labels identity, version, platform and privilege keys. A **value** is shown only for an approved low-risk key (a fixed display list in `tool/ipa_inspect.py`: bundle identifier, versions, platform and SDK keys, `DT*` build identifiers, a few capability arrays) and only as a short string of letters, digits and `. _ + -`; for every other key the report gives the path, the kind of change, the type and a size, never the content, whatever the key is called. Every difference is counted, so the totals (added / removed / changed) are exact; at most 60 entries of each kind are kept, at most 3 files and 40 lines are listed, and when the listing is shorter than the totals the report says `LISTING INCOMPLETE: n of m` and the evidence record carries `listing_incomplete=1`. A file over 4 MiB is not read beyond the cap, and a failing diagnostic is reported as unavailable without touching the verdict. **The comparison still fails on every difference**; there is no exclusion and no acceptance allowlist (the display list is not read by any check). |
| Output hygiene | Everything the verifier writes passes one escaping step: line breaks, carriage returns, escape sequences (including the C1 range), bidirectional and zero-width characters and surrogates become visible escapes, so text from an IPA (member names, property list keys, values, certificate fields) cannot end a line, start a GitHub workflow command or move a terminal; an evidence key is encoded reversibly (`/` is `%2F`, so two identifiers never share a key) and an evidence value has its backslashes escaped. The checks themselves still use the real names and values. Not covered: the other tools of the signing job (`tool/verify_artifact.sh`, `tool/validate_handover_archive.py`) were not changed. |
| Proposed in Phase 2, IMPLEMENTED in Phase 9 | If a future real run shows `serialization only` for exactly the app's top-level `Info.plist`: accept it only when the two files are equal after reading each with an explicit format, with the same keys, the same value **types** (`True` is not `1`, `1` is not `1.0`), the same values, the same array order, and when the CodeDirectory's Info.plist seal matches the **IPA's** bytes (already checked by `verify`). Any key added, removed or changed, however harmless it looks, stays a failure. Run `45148346007` showed exactly that case, and the rule is implemented in its narrower form (binary to binary only, bounded, equal length, no date, UID, data or real): **section 3.1e**. |
| Smallest evidence for a future signing run | The signed `Payload/Runner.app/Info.plist` itself (public data) and its SHA-256, and the verifier's own report of the difference, which now prints the delta without any workflow change. Retaining the signed IPA's `Info.plist` and the raw DER blobs in the evidence folder would settle both questions in one run; that workflow change is made in Phase 7C and described in section 3.1d (the evidence is captured by `verify_ipa.py capture-evidence`; V8 itself is unchanged and stays byte-strict). |

### 3.1b Phase 3 preparation of the DER experiment: variants, evidence recovery, logging exception (prepared 2026-11-21; nothing run, nothing activated)

**Status.** The CTO authorized the PREPARATION of the credential-free DER evidence experiment, not its execution. As of Phase 3 the workflow was only a template outside `.github/workflows/` and nothing was run on macOS, dispatched or activated; the activation preparation of Phase 4 is section 3.1c. The experiment is **separate from the exhausted Apple Distribution Authorizations A, B and C**: it uses no Apple account, certificate, profile, key, Distribution signing, upload or release, and no earlier authorization is reused or needed.

**Signing variants: which are mandatory and which are exploratory.** A case is named `CASE-TARGET-VARIANT` (CASE one of 12 entitlement shapes, TARGET `ios` or `mac`). 32 cases are signed per run. Every call is ad hoc (`-s -`), takes no timestamp (`--timestamp=none`) and asks for `--generate-entitlement-der`.

| Variant | The call | Role |
|---|---|---|
| `plain` | `codesign -f -s - -i IDENT --timestamp=none --entitlements E --generate-entitlement-der` | Every case. **Mandatory** for `runner-mac-plain`; supporting (reported in full, never blocks) for the other 23. |
| `xcodelike` | A **controlled variant** of the flags of the call Xcode made for the real app: `--signature-size 16000`, `--preserve-metadata=...`, `--omit-adhoc-flag`, `--team-identifier`, `--strip-disallowed-xattrs`, `-vvv`, with the identifier set explicitly (`-i IDENT`) and **without** the certificate-dependent designated requirement. Cases `runner` and `arrays` only. | **Mandatory** for `runner-ios-xcodelike` and `arrays-ios-xcodelike`; supporting for the two macOS ones. |
| `logref` | The call as `Packaging.log` shows it, with a made-up team and a made-up certificate name, no `-i`, **including its certificate-dependent designated requirement**. Cases `runner` and `arrays` only (4 cases). | **Exploratory**: reference evidence of what Apple's tool does with that call on an ad-hoc signature. Whether it signs, whether it verifies and what it writes is a result; a failure of it never fails the run, and it is never a required case. |

The three **mandatory** cases (`dump_cases`, whose complete signed executables are emitted as fixtures) are `runner-ios-xcodelike`, `runner-mac-plain` and `arrays-ios-xcodelike`. A mandatory case succeeds only with signing, a successful Apple `codesign --verify`, complete DER evidence **and** a complete, self-checked fixture dump; the current parser's verdict is reported and never required. The other 29 cases are supporting or exploratory.

**Why `xcodelike` differs from the observed command, and what that does not claim.** An ad-hoc signature carries no certificate, so a designated requirement anchored in Apple's certificate chain (`anchor apple generic ... certificate leaf[...]`) is not expected to be satisfiable; Apple's own `codesign --verify`, which is a condition of DER evidence, would then be expected to fail for a reason unrelated to the DER entitlements. That is an expectation, **not an observation**: nothing here has run on macOS. The requirement is therefore removed from the controlled variant and kept, unchanged, in `logref` so that the real behaviour is recorded. The `xcodelike` call is **NOT the command Xcode ran** and is **not claimed to reproduce Xcode's Distribution process** (it has no certificate, no CMS signature and no requirement); it is a controlled ad-hoc call whose DER-entitlements slot is written by the same `--generate-entitlement-der` flag. `-i` is set explicitly because the probe's raw-output safeguard compares the CodeDirectory identifier with the disposable program's, and the controlled variant must not depend on how `codesign` would derive it.

**Evidence recovery and validation (offline; after an authorized run only).** The experiment uploads nothing: the job log is the only copy, and the log of this public repository is publicly readable. `tool/extract_probe_fixtures.py` rebuilds the three signed synthetic executables from a log you saved:

1. Take the log of the run **you started**, by its run number. Save it to a file: `gh run view RUN_ID --log > job.log` (or the job-log download of the Actions page). Anyone can write a log that looks like this one, so a consistent log is not proof that it is genuine.
2. Check the verdict lines first: the probe step must be green and `grep '^RESULT' job.log` must show `RESULT OK: DER evidence and the fixture dump were obtained for every required case`.
3. Extract: `python3 -I tool/extract_probe_fixtures.py --log job.log --out der-fixtures`. `--out` must not exist (it is created, mode 0700) or be an empty directory that is not a link; its parent must exist. Exit 0 = extracted; 1 = the log was rejected (nothing written); 2 = a usage or file error. There is no default for either option and standard input is not accepted.
4. The tool accepts only a log with exactly the three required dumps, each inside the log group of its own case, labelled `CASE/com.example.disposable`, with nothing between the BEGIN-FILE and END-FILE records; a size field that is a plain decimal number of at most 5 digits (at most 64 KiB, checked as text before any conversion); base64 that decodes strictly (100-character lines, padding only at the end) to the stated size and SHA-256; a file that is a **structurally valid Mach-O** (one thin 64-bit little-endian image, or a fat container of such images) in which every image has exactly one code-signature command, a well-formed signature SuperBlob and a CodeDirectory (primary, and any alternate) whose identifier, read **at the offset the CodeDirectory declares**, is exactly `com.example.disposable` (the string appearing anywhere else in the file proves nothing and is ignored); exactly one `PROBE-RESULT der_evidence=complete parser=P fixture_dump=complete` line inside the group of each required case (P is `accepted` or `rejected`: a parser refusal does not invalidate complete evidence), whose parser verdict equals that of the case's `RESULT` line; exactly one success `RESULT` line per required case and one closing `RESULT OK` line, and no `RESULT FAILED`. It rejects anything incomplete, duplicated, interleaved, truncated, malformed, contradictory or in another group or label, a file that is not such a Mach-O, a missing, conflicting or unexpected identifier, and a log over 64 MiB, and then writes nothing. It prints no text taken from the log. **The Mach-O reading is a structural consistency check only**: it does not check the code hashes, the entitlement seals or any CMS signature, and it is no proof of Apple's signature authenticity.
5. It writes only `CASE.macho` (mode 0600) for the three cases and `MANIFEST.txt` into the destination, under names it chooses (never taken from the log), created with `O_EXCL` and `O_NOFOLLOW`: nothing is overwritten and no link is followed. It imports no process, network or loading module and sets no execute permission.
6. Confirm independently: `shasum -a 256 der-fixtures/*.macho` against `MANIFEST.txt` and against the `BEGIN-FILE ... sha256` lines of the log; then read a file (it is only read, never run) with `python3 -I tool/der_entitlements_probe.py --synthetic-identifier com.example.disposable der-fixtures/runner-ios-xcodelike.macho`.
7. **Never execute an extracted file, never upload it automatically, and keep it outside the repository** until a reviewed pull request adds selected files as test fixtures (a separate decision). They are evidence, not trusted code.

**Logging policy: a narrow exception.** The rule of section 7 stays as it is: no IPA, profile, certificate or key in an artifact, Release, comment or log; derived values, a base64 string included, are never printed. The experiment prints base64 of a signed executable, and that is allowed **only** for:
- a **disposable executable generated specifically for this experiment**: the do-nothing C program that `tool/probe_der_entitlements.sh` builds and signs itself in a fresh directory;
- **explicitly designated synthetic input**: the probe emits raw output or a dump only when it is given the program's exact identifier (`--synthetic-identifier`), every CodeDirectory identifier equals it exactly, no CMS signature is present and the file is at most 64 KiB;
- **the three approved fixture-capture cases** (`dump_cases`) only; every other case prints structure, digests and bounded hex.

The exception does **not** apply to a production or staging application; a real IPA or archive; a signing credential or certificate; a provisioning profile; a secret or any authentication material; or **any arbitrary binary given to the probe** (it withholds raw output and the dump from those). The identifier check is a safeguard against a mistake, **not proof of where a file came from**. GitHub Actions logs of this public repository are **publicly accessible** and may be cached or copied, so anything printed must be treated as published: that is why only synthetic data may be printed. There is no general-purpose exception; a different use of base64 in any log needs its own authorization.

**Future activation.** The default branch of `CadenaBitcoin/signer_app` is `development` (read-only query, 2026-11-21). GitHub starts a `workflow_dispatch` workflow only from a file that exists on the default branch, so a run needs a reviewed pull request that adds the workflow to `development`. Phase 4 prepares that pull request; its lifecycle, safeguards and failure handling are in section 3.1c. Nothing is authorized to run.

**What this preparation does not establish (macOS-specific, never run).** (1) Whether Apple's `codesign` accepts every flag of the `xcodelike` call on an ad-hoc signature (`--signature-size`, `--team-identifier`, `--omit-adhoc-flag`, `--preserve-metadata` with the constraint keywords, `-i` together with `--preserve-metadata=identifier`); a refusal makes a mandatory case fail. (2) Whether `codesign --verify --strict` passes for the controlled variants and whether it fails for `logref`, as expected but unobserved. (3) That the linker's own ad-hoc signature and the identifier derivation behave as assumed. (4) The real DER layout: the point of the experiment. (5) Log size, line limits and retention on GitHub: unmeasured. (6) The script under macOS's bash 3.2 and BSD tools: scanned for newer features, not run. (7) An ad-hoc blob is evidence of the format Apple's tool writes, not proof about a Distribution-signed IPA. `actionlint` and `shellcheck` were not available, so no linter has read the template; the YAML parses and every shell block passes `bash -n`.

### 3.1c Phase 4: temporary activation of the DER experiment: safeguards, lifecycle, failure handling (prepared 2026-11-21; nothing dispatched, nothing run)

**Status.** The CTO authorized preparing the activation, not starting it. The workflow `.github/workflows/ios-der-entitlements-diagnostics.yml` is prepared in the activation pull request; it exists on `development` only after that pull request is merged, and even then nothing runs until a person with write access dispatches it, which needs a **separate written CTO authorization for that one run**. No earlier authorization is reused: the experiment is separate from the exhausted Apple Distribution Authorizations A, B and C, uses no Apple account, certificate, profile, key, Distribution signing, upload or release, and is not recorded in, and does not touch, the signing authorization gate.

**What enforces what.** Three different things apply, and only the first two are technical:
- **GitHub's technical restrictions.** GitHub starts a `workflow_dispatch` workflow only from a file on the default branch, only for someone with write access, and with the permissions the file declares (`contents: read`). That is all. GitHub knows nothing of the CTO's authorization and **does not technically enforce it**: a sufficiently privileged repository contributor can dispatch the workflow, from any branch, as often as they like, with or without an authorization.
- **The workflow's execution guard.** The first step refuses anything but a manual start from `refs/heads/development` at run attempt 1. It **rejects re-run attempts** (the "Re-run" button) but **does not prevent independently dispatched new runs**: each new dispatch is attempt 1 and passes. It protects the reviewed file against accidents, not against a person who dispatches again, and not against an altered copy on another branch.
- **The CTO's written governance authorization.** This is the only control on *whether and how often* the experiment is run, and it is procedural: it binds people, not GitHub. **One authorization permits exactly one dispatch.** It is **consumed by that dispatch even if the guard, the checkout or the Xcode selection then fails** (a run that stops there still counted: nothing is retried on the strength of it). **Any subsequent dispatch needs a new written CTO authorization.** A dispatch without one is a breach of procedure that the repository cannot prevent, only make visible (the run is listed in the Actions history with its commit and starter).

**What the file is.** The executable part of the template `docs/workflow-templates/ios-der-entitlements-diagnostics.yml.template`, copied unchanged (`tool/test_ios_der_diagnostics.sh` fails if the two differ in anything but comments), with its own header. The template stays when the workflow is removed. The safeguards, each checked by the tests:

| Safeguard | How |
|---|---|
| Manual only, no inputs | `on: workflow_dispatch` and nothing else: no push, pull request, schedule or `workflow_run`. |
| Least privilege | One top-level `permissions: contents: read`, no job override: every other scope, the OIDC `id-token` included, is none. |
| No credential, no Apple service | No secret, environment, token, certificate, profile, keychain, App Store Connect or export reference; no expression (`${{ }}`) reaches a shell; the only action is `actions/checkout`, pinned to a full commit SHA, with `persist-credentials: false`. |
| No upload | No artifact upload or download. The evidence is the job log, which is public (section 3.1b). |
| Runner and toolchain | `macos-15` (not `macos-latest`), Xcode 26.3 at `/Applications/Xcode_26.3.app`, the pins of the iOS validation workflow. The step fails, before anything is signed, unless `xcodebuild` reports exactly 26.3, so an image without it is a failed run, not a run on another Xcode. |
| Bounded | One job, 20-minute timeout, one `concurrency` group, the probe script run exactly once. |
| Guard (first step) | Refuses anything but a manual start (`workflow_dispatch`), from exactly `refs/heads/development`, at run attempt 1; so the reviewed file is not run by accident from a feature branch and the "Re-run" button of the Actions page (attempt 2) fails. It does **not** stop a new, independently dispatched run (attempt 1), and it does not enforce the written authorization. It prints the commit, run id and attempt, which is how the commit that ran is compared with the one the authorization names. The guard is shell on the runner's own variables only. |
| Disposable and ad hoc | The script builds and signs its own do-nothing program with `codesign -s -`; the tests check that no other identity, no application, archive or IPA is touched. |
| Unchanged elsewhere | The DER parser, the verifier's acceptance rules, the gate, the release records and the application are not part of the activation. |

**Security implications of the temporary activation.**
- **Anyone with write access can start the workflow, from any branch.** A workflow file on the selected branch is the one that runs, so a *modified copy* on another branch carries no guard. That is not a new capability: a writer who can push a branch can already run any new workflow file from it, and this file references no secret, so the reviewed copy gives nothing a writer lacks. The risk the file adds is **accidental or unauthorized use of the reviewed copy**, which the guard and the procedure address; the guard does not stop a deliberately altered copy. Repository rules (branch protection, who has write access) were not inspected here.
- **The log is public and permanent enough to be copied.** Only synthetic data is printed (section 3.1b); the three signed disposable files appear as base64.
- **The window is the time the file exists on `development`.** It should be short: remove it after the one run, or if the run is not authorized soon after the merge.
- Nothing signed here is Apple-Distribution-signed or can be installed or released; runner minutes in a public repository are free of charge; the run is bounded to 20 minutes.

**Lifecycle (one run).**
1. **Review and approve the activation pull request.** It adds the workflow, the test and documentation changes, and nothing else; the reviewer re-reads the template, `tool/probe_der_entitlements.sh` and `tool/der_entitlements_probe.py` as they then are. Merging does not start anything.
2. **Merge into `development`.**
3. **Separate CTO authorization for one specific dispatch**, in writing (one authorization, exactly one dispatch), naming: the experiment (credential-free, ad hoc, disposable), the commit on `development` that is to run, the person who starts it, and that Authorizations A, B and C are neither reused nor needed.
4. **Dispatch once**, by the authorized person: `gh workflow run ios-der-entitlements-diagnostics.yml --ref development` (or the Actions page, branch `development`). Note the run id and check `gh run view RUN_ID --json headSha` against the authorized commit.
5. **Preserve the log and validate the three fixture dumps.** At once, `gh run view RUN_ID --log > job.log`, record `shasum -a 256 job.log`, keep a second copy outside the repository (a GitHub log expires and is the only copy of the dumps), then follow the recovery procedure of section 3.1b (verdict lines, `tool/extract_probe_fixtures.py`, independent digests). Nothing extracted is executed or uploaded.
6. **Remove the temporary workflow** in a separate reviewed pull request that deletes only `.github/workflows/ios-der-entitlements-diagnostics.yml`. The tests accept both states (with the file, equal to the template; without it, nothing under `.github/` refers to the experiment), so removal needs no test change. Remove it whether the run succeeded or failed, unless a re-run has been authorized.
7. **Only then** evaluate the evidence (what the real DER layout is, whether the parser needs a reviewed change). Fixtures enter the repository only through a further reviewed pull request; none of that is part of this activation.

**Failure handling.**
- **The guard refuses** (wrong branch, wrong event, attempt 2): nothing was signed, and the authorization of that dispatch is consumed all the same. Do not dispatch again without a new written authorization.
- **Failure before the probe starts** (checkout, Xcode 26.3 not present): nothing was signed, and the authorization is consumed all the same. Treat it as a failed run: do not retry on your own; a new dispatch needs a new written authorization.
- **The probe fails** (`RESULT FAILED`, a required case without evidence or dump): the log still holds each case's results (signing, verification, evidence, parser) and is the most valuable output; preserve it as in step 5. Do not re-run. Fix `tool/probe_der_entitlements.sh` (for example a flag Apple's `codesign` refuses) in a normal reviewed pull request and ask for a new authorization.
- **The extractor rejects the log** (truncated by a GitHub limit, a record missing): do not re-run to "get a better log". Keep the log, inspect it by hand, report; a re-run is a new authorization.
- **Cancelled, timed out, or the log lost or expired:** the same, a new authorization is needed to run again.
- **Anything unexpected in the log** (any text that is not synthetic): stop, report, and leave deleting the run's logs to a decision of the CTO.
- **Approval for any further dispatch:** a new written CTO authorization that cites the previous run id and why a repeat is needed, names the commit to run, and again does not rely on any earlier authorization. The guard makes "Re-run" from the Actions page fail by design, but a new dispatch is a new run that the guard accepts: that approval must exist **before** it, because nothing but this procedure requires it.

**Validation gaps (this preparation).** The workflow was validated statically only: the YAML parses, every embedded shell block passes `bash -n`, the guard's shell was run against the allowed and refused environments, and the test suites pass in both states (workflow present, workflow absent). `actionlint`, `shellcheck` and `yamllint` are not installed, so **no linter has read the workflow**. Nothing was dispatched or run on macOS; everything listed under "What this preparation does not establish" in section 3.1b still applies.

### 3.1d Phase 7C: evidence capture for the open V8 question and for the Distribution DER blob (implemented; no signing run authorized)

**Why.** The first Apple-signed IPA (Authorization C, run `44834801248`) failed V8: its top-level `Info.plist` differed from the archive's,
yet both were 2,551 bytes (archive: `Info.plist` SHA-256 `34fd28f0…`; the exported file's bytes were not kept). What the export changed is **not
known**. The existing hypothesis (a different serialisation of the same content) is **unproven**: it fits the equal length, and nothing else
is shown. The same run left no copy of the DER entitlements blob of the Distribution-signed executable, and a failed export leaves its
`Packaging.log` in a temporary directory that nothing collected. Phase 7C makes the **next** authorized signing run keep what is needed. It is
evidence only: **V8 stays byte-strict, V7 and V9 and the DER rules are unchanged, and no relaxation is made before the evidence exists.** (The evidence now exists, and Phase 9 relaxes V8 for exactly one file: section 3.1e.)

**The step.** `Capture the Info.plist and DER entitlements evidence` in `.github/workflows/ios-hosted-signing.yml` runs
`tool/verify_ipa.py capture-evidence`. It comes after V7, V8, V9 and the digest check and before the evidence is sealed; it has `if: always()` (so
it runs after a failed V7 or V8), no `continue-on-error`, no secret and no network access, writes only under `evidence/v8-capture/`, and reads
the IPA by path without copying or keeping it. It decides nothing: a difference between the two files is not a failure of the capture. It fails
only when evidence that should exist cannot be produced: the export reported success and there is no IPA, or the IPA, the archive's
`Info.plist` or the executable cannot be read. If the export failed it says so and invents nothing; the archive's `Info.plist` is still kept.

**What is kept** (text only; `status.txt` also appears in the job summary, with states and counts only):

| File | Content |
|---|---|
| `infoplist-summary.txt` | for the archive's and the exported top-level `Info.plist`: exact length, SHA-256 and SHA-1, container format, the bplist trailer (object count, offset and reference widths, offset-table position), the top-level keys in file order; then the comparison: byte identity, equal length, the first differing offset with 16 bytes of hex on each side, the typed comparison of every key, value **and type** (semantic equality, serialisation-only, counts of added, removed, changed and type-changed keys, the keys named, values shown only for the verifier's approved low-risk keys), whether the key order differs and where; then, for each CodeDirectory of the executable, the slot-1 (Info.plist) seal and the hash of each of the two files, with `MATCH` or `DIFFERENT`; and provenance (approved commit, archive tar digest, export result and IPA digest, Xcode version, the run, the digests of `ExportOptions-used.txt` and `archive-app.sha256`) |
| `archive-Info.plist.b64`, `ipa-Info.plist.b64` | the exact bytes of each file as base64 (76 columns), nothing normalised before hashing or encoding |
| `der-summary.txt`, `der-entitlements-slice<N>-cpu<hex>.hex` | the DER entitlements blob of each architecture slice of the main executable as hex, its length and SHA-256, the executable it came from, the slot-7 seal against its CodeDirectories, and the parser's verdict **as information only** (the blob is kept whether or not the parser reads it; the parser is not changed) |
| `status.txt` | `state` (`export-succeeded`, `export-failed`, `export-not-reached`, `ipa-missing-after-export`), what was kept or withheld, and the problems |

**Content safety.** Base64 and hex are encodings, not sanitisation, and a binary property list stores a string with a non-ASCII character as
UTF-16, so a token inside it never appears as ASCII bytes. A file is therefore **retained only after a format-aware inspection**
(`ipa_inspect.plist_evidence_unsafe_reason`): (1) its raw bytes, also read as UTF-16 (both byte orders and alignments); (2) every **parsed** key and
every string at any depth in any dictionary or array, whatever encoding the file uses (so a token spelled with XML character references is found);
(3) every `<data>` value, judged as bytes, and refused when longer than 16 bytes because opaque binary data cannot be shown safe by looking at it;
(4) a file that cannot be read with an explicit format (garbage, truncated, entity declarations, repeated keys) cannot be inspected and is **not
kept**. Content that fails is withheld: the file's bytes are not kept, and the reason (the KIND of material, never the material) is recorded. A
property list above 64 KiB, and a DER blob above 16 KiB, are also withheld (length and digest kept); nothing larger than 1 MiB is read. The DER
blob is judged the same way (raw bytes and UTF-16 views).

**Nothing derived from a withheld file is shown.** For a file whose bytes are withheld, for any reason, the summary shows no key name, no value, no
byte window (hex), no key-difference line and no key-order name, and for a withheld DER blob no header bytes and no parser text (it can quote a key). The same holds for **`CFBundleExecutable`**: the capture uses that value to find the executable, but names it in an output (`der-summary.txt`, `status.txt`, the log) only when the exported `Info.plist` may be kept; otherwise it says that the executable could not be located, or describes it by length and SHA-256 only, and shows no name.
What stays is safe metadata: lengths, SHA-256 and SHA-1, formats, the bplist trailer numbers, whether the files are byte-identical, equal in
length and semantically equal, the counts of added, removed, changed and type-changed keys, the first differing offset **as a number**, the seal
results and the reason. The detailed byte-difference diagnostics are kept for every pair that passes the policy. Every line written is also scanned
for the evidence seal's markers and replaced by a note if it would trip them, so one hostile string cannot make the seal delete all the evidence. The
job log gets counts, digests and states only. The IPA, the profile and every credential are never kept. The real archive `Info.plist` of the first
run (40 keys, no URL, address or token; SHA-256 `34fd28f0…`) passes the inspection and would be kept. **What this cannot do:** recognise secret
material that has no recognisable shape (for example an arbitrary short string), or one encoded in a way no pattern knows; the policy is
fail-closed for what it cannot parse, not a guarantee about every possible value.

**The failed-export distribution log.** When `xcodebuild -exportArchive` fails, Xcode leaves `Packaging.log` in a `.xcdistributionlogs` bundle
named on the first line of its own output ("Created bundle at path ..."), and does not copy it into the export directory (the evidence of
Authorizations A and B has none). The credential step now keeps **this run's** log, through the same redaction as `export.log`, and only if the
bundle is a plain directory directly inside the step's own `TMPDIR`, is not a link, is newer than a marker written just before `xcodebuild`
started, and holds a plain `Packaging.log` within the size the redaction reads. Otherwise `packaging-log-source.txt` holds a one-line reason (no
path, no content). If the redaction fails the log is withheld and the step says so. Nothing else in the runner's directories is read.

**Limits.** The capture cannot say **why** Xcode changed a file, only what changed. A property list that fails the safety check is described but
not kept, so a hostile or unexpectedly sensitive `Info.plist` loses its bytes (its digest and size remain). The seal comparison needs a readable
CodeDirectory. The step runs only in a signing run, which needs its own written authorization and a refreshed G2S record: this change alters the
workflow and two gate-bound tool files (`tool/ipa_inspect.py`, `tool/verify_ipa.py`), so their recorded blobs are out of date until that record
pull request. Nothing here authorizes or prepares a run.

### 3.1e Phase 9: V8 accepts ONE re-serialization, the top-level Info.plist (implemented; no signing run authorized)

**Why.** The Distribution-signed export of Authorization D (run `45148346007`) is the first whose evidence was kept: Authorization C's run (`44834801248`) had produced a signed export too, but nothing of its IPA was retained. Phase 7C's capture showed what it was built to show. The exported top-level `Info.plist` and the
archive's are both binary property lists of 2,551 bytes with the **same 40 keys, values and types**; the export wrote them in another key order (the archive's
are alphabetical, the exported file's are not) and laid the objects out differently (96 objects each, the same trailer, 83 identical leaf encodings). V8 compares every
file byte for byte, so it refused an app whose only difference was serialization. The CodeDirectory's slot-1 seal matched the exported file. Why Xcode re-serializes is
**not shown** by the evidence, and whether its key order is the same in every run is **unknown** (one exported sample exists). The real pair is kept as a test fixture:
`tool/fixtures/apple_runner_info_plist_run45148346007.txt`. This section implements the rule that section 3.1a recorded as "proposed, not active" for exactly this
situation (a real run showing "serialization only" for the top-level `Info.plist`).

**Semantic equality is not bytewise immutability.** For this one file V8 no longer proves that the signed bytes are the archive's bytes. It proves that the two files have the same **content** as Python reads it (keys, values,
types, array order). Bytes that the content does not reach, such as objects that no dictionary or array refers to, are **not compared**, and the files are different byte strings by design. Every other file is still proven byte for byte.

**The rule** (`tool/ipa_inspect.py` `info_plist_reserialized_only`, called from `same_code_check` in `tool/verify_ipa.py` for the relative path `Info.plist` only).
The signed file is accepted in place of a byte-identical one only when **all** of this holds, and every error, a `RecursionError` and a `MemoryError` included, is a refusal:

| Condition | Value |
|---|---|
| Which file | The app's **top-level** `Info.plist`, by exact name. Nested apps and extensions (`PlugIns/X.appex/Info.plist`), frameworks, every other property list and every other resource stay **byte-strict**; Mach-O files are compared as before; a symbolic link is never compared by content |
| Format | **Both** files are binary property lists (`bplist00`, no bytes before the magic). Binary to XML, XML to binary and XML to XML are refused (only binary to binary was observed) |
| Reader | `read_plist_exact`: explicit format, a repeated dictionary key refused, no entity declaration; the root is a dictionary |
| Size and shape | At most **64 KiB** per file, nesting at most **16 levels**, at most **5000 values** counted with multiplicity (an iterative walk, so a self-referencing or heavily shared structure ends at a limit and never recurses) |
| Accepted types | boolean, integer (64-bit range), string, array, dictionary (string keys). A date, a UID, data, a real or a 16-byte integer is refused: the real file has none, and they are where Python's and Apple's readers are most likely to differ |
| Equality | `plist_equal_strict`: equal in **value and type** all the way down (`True` is not `1`, `1` is not `1.0`), arrays in the same order, dictionaries without regard to key order at any depth |
| Length | **Equal length**, a coarse extra bound and **not** a guarantee about bytes. A re-serialization of the same objects keeps its size, so a length change (padding, an added or a dropped object) is refused. A same-length difference in bytes the content does not reach is **not** excluded: an unreferenced object replaced in place, or one object added while another of the same size is dropped (the real pair: 2,551 and 2,551 bytes; a test pins that a changed unreferenced `true` is accepted) |

What the verdict looks like: V8's PASS line says that the top-level `Info.plist` was re-serialized with identical content and types; an `INFO` line gives both lengths and both
SHA-256 digests (never a value); the evidence file records `same_code_info_plist` and the two digests. The `INFO` line says that the files are equal in content, **not byte for byte**. A refusal keeps the existing failure and its diagnostics and adds one
`INFO` line with the reason: a **fixed sentence** that names a rule and never quotes the files or the text of an exception (a reader's message can quote the file, so it is never used; a test pins this). Any added, removed or changed key, however harmless, and any other file that differs by a single byte, remain failures.

**What this does NOT do: it authenticates nothing.** That the signed bytes are the bytes Apple's signature seals is checked, independently, by `verify`
(`check_code_signature` in `tool/verify_ipa.py`: the CodeDirectory's slot-1 seal of this very file, and the CMS signature over that CodeDirectory), **whether or not V8
accepts the file**. **The standalone `compare` command reads no CodeDirectory, no seal and no CMS signature and authenticates no signature**: it says so on **every invocation**, whatever the outcome (a `NOTE` line before anything can fail),
and its help text says so. `verify` does not print that note, because it does authenticate. An IPA must never be accepted on `compare` alone; the hosted workflow runs `verify` (which also runs this comparison, with `--unsigned-app`) and then `compare`.
The tests pin both halves: an `Info.plist` re-serialized **after** signing (same content, other bytes) is accepted by V8 and by `compare`, and refused by `verify` ("Info.plist was changed after signing").

**Residual risks, accepted and documented.**

1. **Unreferenced objects.** A binary property list can hold objects that no dictionary or array refers to. They are not part of the content, so two files that differ only in such
   objects are "equal" here (the real files carry two unreferenced `true` objects each, and a test pins that a changed one is accepted). **They are still bytes of the signed app, and this rule
   does not compare them with the archive's**: the distinction between semantic equality and bytewise immutability is real and is not removed by any condition above. After signing, the slot-1 seal
   covers every byte of the file, so a later change is caught; before signing, nothing compares those bytes. The equal-length condition is a coarse bound, **not** a guarantee: it refuses a length
   change, and it does not exclude an unreferenced object replaced in place or one added while another of the same size is dropped. No reader of the content reaches such an object; that is the whole of the argument, and it is an argument, not a proof.
2. **Python is not Apple's parser.** Equality is judged with Python's `plistlib`; the app is read by CoreFoundation. A construct the two read differently could make files that look equal here differ for the
   app. The limits above (binary only, no repeated key, no date, UID, data or real, bounded size, depth and node count, string keys, 64-bit integers) keep the accepted language to what the real file uses,
   and the real pair was read by `plistlib` **and** by an independent reader written for the audit with the same result; they do not prove that CoreFoundation agrees on every file. `plistlib`'s behavior
   also depends on the Python that runs the tool (a self-referencing dictionary is parsed by recent versions, which is why the walk is iterative and bounded).
3. **Determinism.** Whether Xcode writes the same key order in every run, and in other Xcode versions, is not known. If a later export changes the format, the length or the content, V8 fails closed and the
   Phase 7C evidence shows what changed.
4. **Diagnostics never carry a property-list parser's own message.** A parser's exception text can quote the file it read (the name of a repeated key, an unexpected element, a value that is not a number). The V8 difference description
   (`describe_one_plist`, through `plist_difference` and `read_plist_exact`), the capture evidence's typed comparison, the `Info.plist` reader of `verify`, `structure` and `certificate`, the `cdhashes` attribute reader, the entitlements-blob reader and the
   provisioning-profile reader say what KIND of failure it was (the exception's class, or a fixed sentence) and nothing else; `plist_failure_text` is the one helper. The decisions are unchanged: an unreadable file is still unreadable, and a failure
   the reader did not anticipate (plistlib raises `AttributeError` for a date that is not a date) is now a refusal, not a crash. **Not covered, by decision:** the DER entitlements parser's own messages (they can name an entitlement key), a message that names
   a path listed by `CodeResources`, and a readable property list's difference listing, which shows key *paths* by design and never values.
5. **Not covered by this change:** V9 (the native library inspection) has still never run on a real IPA; the certificate chain, App Store Connect acceptance and runtime behavior are not verified here.

**Tests** (`tool/test_verify_ipa.sh` section 17): the real pair (digests, facts read with `plistlib`, the sealed hash); positive cases (the real pair in both directions, reversed and nested key order);
fifteen one-change-at-a-time refusals (an added or removed key, changed strings, booleans and integers, boolean to integer, integer to real, an array reordered, shortened, changed deep inside nested
dictionaries, a renamed key); real bytes edited, truncated, extended, with a corrupted offset table and trailer; format changes; hostile structures (a repeated key, a self-referencing dictionary, nesting of 900 and 3000
levels, 100-fold shared sub-objects, a non-string key, a 16-byte integer, an oversized file, dates, UIDs, data, reals); the exact limits; the length rule; failing closed when the comparison or the reader raises;
diagnostic confidentiality (no refusal reason quotes a key, a value or the text of an exception; malformed XML and binary property lists carrying distinctive strings through every reader named in item 4 of the residual risks, end to end); scope isolation (framework, app extension, another property list, a lower-case name, a changed byte in another file, a changed executable, a symbolic link, an added key, binary to XML);
the `compare` notice on every invocation; and `verify` against `compare` for the seal. The mutation run of the new code is reported with the change.

**Authorization.** This changes a verification rule (the CTO decided it on the evidence of run `45148346007`) and two gate-bound tool files (`tool/ipa_inspect.py`, `tool/verify_ipa.py`): their recorded G2S blobs are out of date
until a reviewed record pull request refreshes them, and **no G2S authorization is open**. Nothing here authorizes or prepares a signing run, and the workflow is unchanged.

### 3.2 Signing-job separation: findings (2026-10-22, credential-free)

Question: can the existing unsigned build be signed and packaged in a separate job without recompiling?

**Established**
- The unsigned artifact of the accepted staging run contains 16 Mach-O files: 13 with no signature
  (including `Runner`), 2 ad-hoc signed (`Flutter`, `App`) and 1 signed by Apple (the embedded
  `libswift_Concurrency.dylib`, team `59GAB85EFG`, signing certificate valid until 2026-10-24). All 16
  must be re-signed with `--force` so that the app carries one identity; the old `_CodeSignature`
  folders of the sealed frameworks are replaced.
- Every one of the 16 has room for a signature without relinking. Re-signing the real artifact with the
  synthetic fixture signer left all 16 executables identical apart from the signature and all 76 other
  files byte-identical (`verify_ipa.py compare`), and the result passes all 56 checks of `verify` with a
  synthetic identity and profile. This shows the transformation is structurally possible and that the
  check for "no recompile, nothing injected" works on real build output.
- Flutter 3.35.3 can produce an unsigned **archive** without credentials: `flutter build ipa --no-codesign`
  runs the archive with `CODE_SIGNING_ALLOWED=NO`, skips the export, and still runs Flutter's app-icon and
  launch-image validation (from the Flutter source of the pinned version, not yet run here).

**Not established (needs macOS and, for the last two, Apple assets)**
- That Apple's `codesign --force` and `--entitlements` accept every one of these files the way the fixture
  signer does. `tool/spike_resign_unsigned_ios.sh` was written to test it with a throwaway identity in a
  throwaway keychain. It was run twice on a hosted runner and **failed before it touched the
  application**, because macOS does not let `codesign` use an untrusted self-signed identity (section
  3.3). Not even ad-hoc signing of the application's files was tried. This stays open until a run with
  Apple-authorised signing material.
- Which route the signing job takes: **A** manual `codesign` of the existing `Runner.app` (credential-free
  testable, as above, but the job must build the IPA layout, embed the profile and create `SwiftSupport`
  itself), or **B** `flutter build ipa --no-codesign` in the build job and `xcodebuild -exportArchive`
  with a manual-signing `ExportOptions.plist` in the signing job (Xcode lays out the IPA, but whether
  export accepts an archive that was built unsigned can only be tested with a real distribution
  certificate and profile). B also changes the build artifact from the validated `flutter build ios` output
  to an archive, so it needs its own validation run.
- That App Store Connect accepts either result.

**Apple's procedure and the two routes (research of 2026-10-22; sources at the end of this section)**

What could and could not be established. Apple's own documentation pages (TN3125 and the `xcodebuild`
documentation) are rendered by script and could not be read from here, so the statements below rest on
the pinned Flutter source, on a DTS engineer's answer, on Apple's archived Q&A 1886 and on developer
forum reports. **No Apple statement was found** on whether `xcodebuild -exportArchive` signs an archive
that was built unsigned, or on the order in which embedded code must be signed.

| | Route A: sign the existing `Runner.app`, build the IPA ourselves | Route B: unsigned `.xcarchive`, then Xcode's `-exportArchive` |
|---|---|---|
| Credential-free part | Less than hoped: the self-signed experiment failed before it signed anything (section 3.3), so Apple's `codesign` on the real artifact is also first tested with Apple-authorised material | Producing the archive: `flutter build ipa --no-codesign` (pinned Flutter source) |
| Needs Apple assets to test | Embedding a real profile, entitlements, upload validation | The export itself: `-exportArchive` with `app-store-connect` needs the distribution certificate and profile |
| Apple-supported path | Not documented by Apple for this use; practised by third-party tools (not verified here) | Yes: export with an `ExportOptions.plist`; a DTS engineer lists the methods (`app-store-connect`, `release-testing`, ...) |
| Reports found | none beyond the mechanics | Developers report that an "empty-signed" archive can be exported with the signing done at export time, and one then hit ITMS-90078 (missing push entitlement) after upload: entitlements the archive was built without are not invented by the export |
| What we must supply | The IPA layout, `embedded.mobileprovision`, entitlements, the `SwiftSupport` folder | `ExportOptions.plist` (manual signing, profile per bundle ID), entitlements in the project (there is no entitlements file today) |
| Effect on the validated build | None: the input is the build of the accepted runs | The build artifact changes from `flutter build ios` output to an archive: it needs its own validation run |
| Verdict | Technically viable by the credential-free evidence; not yet shown to be accepted by Apple | Viable as the supported route; not yet tested with an unsigned archive; needs Apple assets |

Both routes need the entitlements decided: `Info.plist` declares the `remote-notification` background
mode and the project has no entitlements file, so a push entitlement (`aps-environment`) is currently
nowhere (questionnaire B3). Neither route can be chosen on credential-free evidence alone; the choice
and the first real IPA need the Apple account.

**The Apple-signed Swift runtime library.** `Frameworks/libswift_Concurrency.dylib` is the back-deployment
copy of Swift Concurrency (the app's minimum iOS is 14.0, below the iOS 15 that ships it). The copy in the
artifact is signed by Apple (team `59GAB85EFG`, certificate "Software Signing"). Whether to re-sign it is
**not assumed**; the evidence is:
- Apple's archived Q&A 1886 documents that on a device an embedded Swift library whose signature does not
  carry the app's Team ID is refused ("mapped file has no team identifier and is not a platform binary");
  it concerns a missing team identifier, not a foreign one, so it does not settle the foreign-team case.
- Xcode's own embed step signs the Swift libraries it copies with the target's identity (reported in forums
  and visible in the `swift-stdlib-tool --sign` usage text); an export is generally understood to re-sign embedded code too (not verified here).
- `codesign --verify` does not judge team-identity consistency; the kernel does, at load time.
So re-signing it with the app's identity matches what Xcode does and is the working hypothesis, but only a
device run (the controlled internal TestFlight build, or a development build) can show whether leaving it
alone would also load. The experiment was written to run **both** variants and report the team identifiers
it finds (it never got that far); it would not have decided.

Sources: Flutter 3.35.3 `build_ios.dart` (pinned SDK; `--no-codesign` skips the export);
[Apple Developer Forums, `method` values of `xcodebuild -exportArchive` (DTS engineer)](https://developer.apple.com/forums/thread/773749);
[Apple Developer Forums, signing an empty-signed archive at export (community; no Apple answer)](https://developer.apple.com/forums/thread/686345);
[Apple Q&A 1886 (2015), Swift libraries and the Team ID](https://developer.apple.com/library/archive/qa/qa1886/_index.html);
[Apple Developer Forums, re-signing an IPA and the `SwiftSupport` folder](https://developer.apple.com/forums/thread/94151).

**Obstacles and risks found**
- `Info.plist` declares `UIBackgroundModes` `remote-notification`: the App ID then needs the Push
  Notifications capability (`aps-environment`), otherwise App Store Connect warns (questionnaire B3).
- `ITSAppUsesNonExemptEncryption` is absent: the export-compliance question is asked at upload (questionnaire A6).
- The app has no `PrivacyInfo.xcprivacy` (Flutter and FingerprintPro frameworks have one).
- Third-party frameworks (Idensic, FingerprintPro) are unsigned vendor binaries that will be signed by us;
  a vendor's signature requirement, if any, is not known.
- The first real IPA will probably need one reviewed adjustment of the verifier (see "Needs a real
  Apple-signed IPA" above); that is the purpose of verifying before uploading.

### 3.3 Hosted feasibility experiment (run 2026-10-22 and 2026-11-06/08; FAILED; diagnosed; closed)

`.github/workflows/ios-signing-feasibility.yml`, started by hand only (`workflow_dispatch`), asked whether
Apple's `codesign` can sign the existing unsigned staging `Runner.app` with a **throwaway self-signed identity
in a throwaway keychain**. It uses no Apple credential, certificate, profile or App Store Connect key, no
secret, no environment, contacts no Apple service, uploads nothing and cannot be started by a push or pull
request (`tool/test_ios_signing_experiment.sh` checks this statically). It failed, for a reason that lies in
the test and not in the pipeline. **It is closed: no further disposable-certificate experiment is planned
unless a specific unresolved production-signing question justifies one.**

**Runs** (all `macos-15`, Xcode 26.3)

| Run | Date | Commit | Result |
|---|---|---|---|
| 39820242689 | 2026-10-22 | `358a43f` (`development`) | Failed in the signing step. The script discarded `codesign`'s output, so the cause was not visible. |
| 42230234012 | 2026-11-06 | `5d90291` (`development`) | A fresh "iOS CI validation build" (the unsigned input, version 1.0.4+1000035): **succeeded**. Current `development` compiles for iOS under Xcode 26.3. |
| 42231261892 | 2026-11-06 | `61cca29` (`issue/71-ios-signing-diagnosis`) | Same input, `codesign`'s error text now printed. Failed in 28 seconds: the cause became visible. |
| 42515210134 | 2026-11-08 | `9afcf4e` (same branch) | One bounded attempt to make the identity valid (below). Failed; stopped. |

**What worked:** the input run was checked (right workflow, success, this repository), the downloaded archive
matched its SHA-256 (`a0d6f610b909a90bb44dcc4ee4d9842debfaa9de7e5952785605d91b55ec3e80`), `tool/verify_artifact.sh`
accepted the unsigned app, a throwaway keychain and identity were created, and afterwards the identity, the
keychain and the files were verified to be gone (run 42515210134 also found no trust setting left in the
user or admin domain).

**The error.** Every `codesign` call failed, including a harmless control (a copy of `/bin/ls`):

```text
error: The specified item could not be found in the keychain.
```

Beside it the preflight listing showed the identity as `"Spike Throwaway Signer" (CSSMERR_TP_NOT_TRUSTED)`
and `0 valid identities found` (`security find-identity -v -p codesigning`). The second run recorded 32
failures: 16 in the first variant (15 embedded frameworks and libraries, and the app), 15 in the second
(the Apple-signed Swift library is skipped there) and the control. In run
42515210134 an **ad-hoc** `codesign --sign -` of the same control file succeeded (exit 0).

**Cause (diagnosis by elimination; no run has yet shown a trusted identity signing successfully).**
`codesign` works on the runner, and the failure is independent of the application's contents (it fails
identically on `/bin/ls`). What differs is that the throwaway certificate is self-signed and **not trusted for
code signing**, so macOS lists it as invalid and `codesign` cannot select it, reporting the misleading "item
could not be found". The reading that `codesign` only selects valid identities is an inference from these
observations and not from an Apple statement. Classification:

| Possible cause | Finding |
|---|---|
| The CI implementation (workflow, runner, Xcode, input handling) | No: everything before the signing step passed, and ad-hoc `codesign` works on the same runner. |
| The application or the unsigned input | No: the control file fails the same way, and the input verified. |
| Missing Apple-authorised signing resources | Not the reason this run failed (none were involved), but see below. |
| **The test-signing procedure** | **Yes: the throwaway self-signed identity is not trusted for code signing.** |

**The attempt to make it valid.** Trust for a self-signed certificate lives in a trust-settings *domain* (user,
admin or system), not in the throwaway keychain, so it cannot be confined to the experiment. Run 42515210134
tried the narrowest form: `security add-trusted-cert -r trustRoot -p codeSign -k <throwaway keychain>` in the
**user** domain, on the hosted (ephemeral) runner only, limited to 30 seconds and removed again on exit (the
script refused to run it anywhere else). It did not finish within the limit (exit 124) and wrote nothing,
which is consistent with an authorization prompt that nobody can answer on a headless runner (not observed
directly). The only remaining way is `sudo security add-trusted-cert -d` in the **admin** domain, which is a
system-wide trust change. It was **not** approved and was not tried.

**Decision (2026-11-08): the trust workaround is not adopted, and nothing from it is to be merged into the
repository's production infrastructure.** A disposable-certificate trust override is the opposite of what the
signing pipeline needs, the experiment's own header says that success would not prove Apple acceptance, and an
Apple-issued distribution certificate needs no such override: its chain ends at an Apple root that macOS
trusts. (That the signing keychain then also needs Apple's intermediate certificate, and that `codesign`
selects the identity without a trust change, are expectations to be confirmed by the first real signing run,
not facts.)

**Not demonstrated by any run** (all of these remain unverified and are the questions for the first signing run
with Apple-authorised material): that `codesign --force` and `--entitlements` accept all 16 Mach-O files of
this application (staging or production); the two variants for the Apple-signed Swift runtime copy;
`codesign --verify --deep --strict`; `tool/verify_ipa.py structure` and `compare` against real Apple output;
route A or B (section 3.2); the production unsigned artifact (no production input was built); entitlements;
profile embedding; and acceptance by `xcodebuild -exportArchive`, App Store Connect or a device.

**Where the evidence is.** The branch `issue/71-ios-signing-diagnosis` is **kept as a record and is not to be
merged**. Its commits: `61cca29` makes `codesign`'s output visible (a harmless change that could be proposed
separately if wanted), `9afcf4e` and `f50d8fc` add the bounded trust attempt and a staging/production input to
the workflow, and `6327dd2` records the outcome in the script header. GitHub keeps run logs for a limited time
(the default is 90 days), so this section carries the facts that matter. The workflow and script on
`development` are unchanged: they would fail in the same place if started, and **should not be started**.
Nothing was uploaded, published or signed with a real credential, and no Apple service was contacted.

### 3.4 Stage C: audit of the staging prerequisites (2026-10-22; read-only, nothing changed)

| Requirement | Finding | Needed |
|---|---|---|
| In-app staging identification | A "Test Environment: you are using Signet environment" banner appears on the Home screen only, and only because the build is Signet (`AppController.USE_TESTNET`). Nothing in the app says "STAGING", names the API host or shows a version, and the wallet creation and seed screens have no indicator. The launcher name "Cadena Signer STAGING" is outside the app. | An indicator on every screen that handles keys (design and approval; sensitive code, `CLAUDE.md` section 6). |
| Installed application version | Not available in the app. There is no `package_info_plus` dependency and no compile-time version define. "App: x \| API: y" on the Home screen shows the backend's *newest app version*, not the installed one. `RELEASE_IDENTIFIER` and its scheme do not exist (`RELEASE_POLICY.md` open decision 6). | A decision: `package_info_plus` (changes `pubspec.lock`), a define in the committed configuration (changes `BuildConfig`), or a platform channel. |
| Signet XPUB and address validation | Derivation is network-consistent by construction (Signet version bytes `0x045f1cf6`, path `m/84'/1'/0'`, `tb` addresses; the mainnet equivalents otherwise, all from `USE_TESTNET`). Nothing validates an externally supplied XPUB or address: `isValidBitcoinAddress` is unused and accepts only mainnet forms; the backend XPUB is compared with the local one as a string. Address checks inside the Rust library were not read (out of scope). | A pure Dart validator (prefix and address HRP must match the build) and the first `test/` directory; sensitive code. |
| Staging/production mixing | Satisfied at build time: `BuildConfig` fails on any inconsistency, the flavor must equal `APP_ENV`, the bundle IDs differ, and `verify_version`, `verify_artifact`, the build workflows and now `verify_ipa.py` check it. Open: the missing in-app indicator and the finding below. | |
| Background-task identifier | `ios/Runner/Info.plist` permits `com.app.cadenabitcoin.auto_signing_task`, but `AppDelegate.swift` registers `auto_signing_task`, and the same production-style name is permitted inside the staging bundle. iOS requires a registered identifier to be in the permitted list; the effect on a device (a failed registration or a crash) was **not tested**. | A decision and a device test; the controlled internal TestFlight build will exercise it. |
| Push entitlement | `UIBackgroundModes` includes `remote-notification`, but the project has no entitlements file (`aps-environment`). | The Push Notifications capability decision (questionnaire B3) before either signing route. |

No application code was changed for any of these.

## 4. Unresolved decisions and prerequisites

| # | Item | Needed from |
|---|---|---|
| 1 | Apple account identity, ownership, administrators, renewal | Apple account owner (questionnaire part A) |
| 2 | Whether an iOS app is live, its exact bundle ID, version and highest build number; whether `com.app.cadenabitcoin` is that ID | Apple account owner. **No production signing work starts until this is known.** |
| 3 | The role matrix: which role can upload a build, read processing status, and submit for review; whether a restricted service user can be created without Certificates, Identifiers & Profiles access, and who would hold its Apple ID sign-in | Apple account owner (the live Roles page and Users and Access) |
| 4 | App ID registration and App Store Connect record for `com.app.cadenabitcoin.staging` (not assumed registered) | Apple account owner |
| 5 | Existing distribution certificates, profiles and their custodians; shared or per-context certificates | Apple account owner, signing custodians |
| 6 | Capabilities and entitlements the app really needs (`remote-notification`, background tasks) | Apple account owner, maintainers |
| 7 | Export-compliance answer and App Privacy answers; then `ITSAppUsesNonExemptEncryption` in `Info.plist` (a native-config change, separate approval) | Apple account owner, legal |
| 8 | Internal tester list and who administers the tester group | Apple account owner |
| 9 | Continuity signing custodians (no approval role; the release authority is the authorized merge, section 6) | project owners |
| 10 | Release identifier scheme, in-app staging identifier, Signet XPUB/address validation (prerequisites of [RELEASE_POLICY.md](RELEASE_POLICY.md) 8.1) | maintainers; separate issues |
| 11 | **Resolved (RELEASE_POLICY.md 2.3), as amended by P1:** the written, version-bound decision carried by the reviewed promotion is the authorization; the environment reviewers confirm the deployment only | CTO |
| 12 | The effective minimum iOS version and its device testing | product decision; [IOS_CI.md](IOS_CI.md) |
| 13 | **App Store Connect API access is disabled** for the Apple Developer organization (reported by Noah, 2026-11-08; not checked here). The Account Holder (Kevin) has been asked to enable it. Until it is on, no API key of any kind (team or individual, section 5) can be created, so the upload and status-reading half of the pipeline cannot be configured. An earlier note on #71 said the account might be held under a personal Apple ID, so item 1 (account type and ownership) is still open. | Account Holder |

## 5. Apple authentication model (investigated; not final)

Goal: the credential in the pipeline must be able to upload a build and read its processing
state, and must **not** be able to submit for review, release, create certificates or touch
another app. The model is **not finalized** before items 2 and 3 of section 4 are confirmed.

| Option | Isolation | Notes |
|---|---|---|
| **A. Team API key** | None: "access to all apps"; only the role limits it | Every team key reaches the production app too. Rejected as the staging credential, because a staging leak would reach production data. |
| **B. Individual API key of a dedicated, app-restricted service user (Preferred, to be confirmed)** | The key has "the access and roles of the associated user", so it is limited to the apps that user may see | One active key per user, so staging and production need **two** service users. No Provisioning endpoints, so it cannot create certificates (an advantage). Needs the "Generate Individual API Keys" permission, and the user's role must allow the upload. |
| C. Admin-level key or Xcode cloud-managed signing | None | Rejected: far above what an upload needs. |
| D. Apple ID app-specific password | A personal account | Rejected. |

**Prerequisite (section 4, item 13):** every option above that uses an API key needs App Store Connect
API access to be enabled for the organization by the Account Holder; it is reported disabled. Until then no
key is requested or created, and no signing or upload secret is configured.

**Exception for the iOS 1.0.4 hosted signing operation (Issue #71; CTO decisions D3, D7 and D14 of the release record, 2026-11-20).** For the one G2S
signing-and-verification operation the credential is a **dedicated Developer-role team API key** (option A) used for **Xcode cloud-managed signing** (the
approach of option C), which this section otherwise rejects. The deviations are accepted in writing: the key's scope cannot be restricted to the application;
the goal above that the credential must not create certificates does not hold, because cloud-managed Distribution signing may create certificates and
profiles in the team's account (D7); the fallback below applies, with the loss of app isolation recorded (D14) and compensated by the required reviewers of the
protected environment `ios-hosted-signing` ([IOS_HOSTED_SIGNING.md](IOS_HOSTED_SIGNING.md) section 4). Rotation and revocation remain available; automatic
revocation is not mandatory; a temporary Admin-level key would need its own authorization. This exception covers G2S only: it is **not** a decision for any
staging or upload credential, and the model below stays "not final" for them.

Open points the account owner must confirm: that a service user can be restricted to the
staging app only; the lowest role that still shows **Upload builds**; that this role does not
show **Submit apps**; and that the organization accepts a dedicated service user. If B is not
possible, the fallback is the lowest-role team key, with the loss of app isolation recorded
and compensated by reviewer approval on the staging environment.

### Certificates, Identifiers & Profiles (CIP) access

- **The preferred credential cannot reach provisioning.** Individual keys "aren't able to use
  Provisioning endpoints" (section 1). The pipeline therefore can never create or download a
  certificate, a profile or an App ID with it, and it must not be designed to. This is a
  least-privilege advantage, and it has a cost: the distribution certificate, the provisioning
  profiles and the App IDs are created by the Apple account administrator **in the developer
  portal** (a role with CIP access) and handed to the custodians as environment secrets.
  Profiles and certificates expire, so renewal is a **manual administrator task**, scheduled
  in the custody register; `tool/verify_ipa.py` checks expiry so that a lapse fails
  visibly before an upload.
- **The service user must not receive CIP access.** The Developer role can, with that access,
  create and revoke development certificates and download profiles (section 1). The service
  user exists only to hold an upload-capable individual key limited to the staging app, so it
  gets no CIP access, no user-management permission and no access to other apps.
- **The service user is an Apple ID.** Someone must sign in once, with its second factor, to
  generate the key. Who holds that Apple ID's credentials and second factor, and how they are
  recovered, is a custody question for the account owner (questionnaire B4); the credentials are
  never shared with the pipeline or the repository.
- **Individual enrollment caveat.** If the team is an Individual enrollment, users added in
  App Store Connect are not part of the Developer Program team (section 1). Whether such a user
  can hold the upload role and generate an individual key is unconfirmed, and portal access is
  then limited to the Account Holder. If so, this model may be unavailable and the fallback of
  this section applies. Questionnaire A1 question 1 decides it.

The `.p8` is shown once; it is handed to the custodians through a secure channel, never through
chat, email, issues or the repository.

## 6. Authorization of production signing and delivery

**The release authorization is the CTO's written, version-bound decision,** carried by the reviewed
promotion into `production` (and into `staging`, for staging) and recorded in the authorization
record that the gate reads (RELEASE_POLICY.md principle 9 and section 2.3, as amended by step P1;
`DEC-05` and `DEC-08` of the release-framework specification). The merge executes it.

> **Amended by P1 (REC-02, 2026-11-28).** The protected signing environments **do** require
> reviewers: `ios-hosted-signing-stg` for staging (verified, `docs/IOS_STAGING_DELIVERY.md` section 1.1)
> and, according to `docs/IOS_HOSTED_SIGNING.md` section 4, `ios-hosted-signing` for production
> (the production setting is not re-verified by P1). Their approval **confirms the deployment** of an
> already authorized release. It creates no authorization and is not an independent review. Temporary
> credentials are provisioned and verified before the promotion merge and removed after the delivery
> (`DEC-28`). The first and second bullets below record the earlier position and are superseded where
> they say that required reviewers are not used.

- The two `Maintainers` accounts (`sziller` prepares, `CadenaWizard` reviews and merges) are
  **the same person**. They are not, and the repository does not pretend they are, independent
  reviewers. A GitHub environment's "required reviewers" setting would therefore add no
  independence. It was first planned as "not used"; it is now used as a deployment
  confirmation only (see the amendment above).
- What protects the release is automated and mandatory: protected, branch-restricted
  environments; GitHub-hosted ephemeral runners only; the two-job split; no recompilation while
  signing; `tool/verify_ipa.py` after signing; a failed verification stops delivery
  (RELEASE_POLICY.md section 2.3).
- The same custodian separation applies to secrets: nobody should be the only holder of a
  credential that can ship the production app (see
  [RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md) section 7). That is
  continuity, not approval.
- **Before the pipeline can sign**, a person signs by hand (iOS 1.0.4, [IOS_RELEASE.md](IOS_RELEASE.md)).
  That is an operational exception to the future automation, **not** an exception to this
  authorization rule, and it needs the CTO's written authorization of that operation.

## 7. Public-repository security model

The repository is public. Anyone can read workflow logs, download artifacts, fork, and open
pull requests. The rules below are **requirements for the future signing workflows**. Today's
unsigned validation workflows already use `contents: read`, SHA-pinned actions and no secrets;
no signing workflow, environment or secret exists.

| Threat | Rule |
|---|---|
| Secrets or binaries leaving through logs and artifacts | No IPA, profile, certificate or key in an artifact, Release, comment or log. Only digests, fingerprints and verification text. No `set -x` near secrets. Derived values (a decoded profile, a base64 string) are never printed; masking only covers exact matches. The only exception is the narrow one for the disposable synthetic fixtures of the DER experiment, section 3.1b; it is not a general exception. |
| Pull requests from forks and from branches | No secret reaches them. Environments are restricted to one protected branch. No `pull_request_target`, and no `workflow_run` against untrusted code. |
| A contributor with Write access edits a workflow on a branch | The environment's deployment-branch rule refuses it. `staging` and `production` change only by reviewed pull request. |
| Third-party code seeing secrets | Two-job split (section 3). Actions pinned by SHA. No third-party action receives signing material. |
| Unsafe runners | GitHub-hosted, ephemeral runners only. **No self-hosted runner on this public repository.** |
| Credential scope | `GITHUB_TOKEN` is `contents: read`. Secrets only at environment level, never repository or organization level. Environment secrets are administered by Organization Owners only. The keychain is temporary and deleted in an `always()` step. |
| Tokens | A short-lived (20 minutes or less) JWT is derived per run from the `.p8`. |
| Accidental commits | Ask the Organization Owners to enable secret scanning and push protection. |
| Concurrency and duplicates | One upload at a time per environment; a build number already present is refused before upload. |
| Public publication | The credential cannot submit for review (section 5), the workflows contain no such call (tested), and production upload is authorized by the merge into `production` and is limited to the configured operations (section 6). |

## 8. Operating procedure (skeleton; every step is planned, none exists yet)

| Who | What |
|---|---|
| **Automated (after the pipeline exists and is approved)** | Build, sign, verify, record evidence, upload to the staging record, report processing state. |
| **Authorized by the merge** | A pipeline run on `staging` or `production`, including signing and the configured delivery. |
| **Manual operations before automation exists** | Each needs the CTO's written authorization of that specific operation (RELEASE_POLICY.md 2.3): for example the iOS 1.0.4 signing, upload and tester assignment. |
| **Apple account administrator (Noah)** | App IDs, App Store Connect records, certificates, profiles, service users and their keys, tester group, agreements and renewal, export-compliance and privacy answers. Not required to build or sign locally. |
| **Cadena maintainers** | Review and merge, workflow changes, environment settings (Owners), custody register (no secrets in the repository). |

- **Failed upload:** read the job's text evidence and the processing state; the commonest
  causes are a repeated build number, an expired or mismatched profile, a missing compliance
  answer, or a validation message from Apple. Fix the cause in a reviewed change; never rerun
  by editing a number outside `pubspec.yaml`.
- **Superseded build:** a newer reviewed version replaces it; the old build is expired in
  TestFlight by the account administrator. Build numbers are never reused.
- **Rotation and revocation:** revoke a leaked `.p8` immediately in App Store Connect (a
  revoked key cannot be reinstated); revoke a leaked certificate and re-sign; rotate secrets
  in the environment; record the event in the private custody register. A recovery drill is
  scheduled as in [RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md) section 7.

## 9. What can proceed without Apple credentials

| Work | Notes |
|---|---|
| This documentation and the questionnaire | Stages A and B. |
| Static workflow guards (no `pull_request_target`, no review-submission calls, explicit permissions, pinned actions) | Linux-testable. |
| `tool/verify_ipa.py` and its fixtures | **Done** (section 3.1), not yet wired into a workflow. |
| Signing spike with a throwaway self-signed identity | Linux part **done** (section 3.2). The hosted run **failed and is closed** (section 3.3): macOS does not let `codesign` use an untrusted self-signed identity, and a trust override is not adopted. Not to be repeated. |
| Unsigned archive job; privacy-manifest check of the pods | Open, credential-free. The archive job would also answer part of the route question of section 3.2. |
| Static guards over all workflows (no `pull_request_target`, no review-submission calls, explicit permissions, pinned actions) | Open, credential-free; only the Android release tests have such guards today. |
| Release identifier scheme, in-app staging display, Signet validation | Separate issues, partly sensitive code. |
| Everything that needs a real certificate, profile, API key or App Store Connect record | Blocked on section 4 items 1 to 5 and 13. |

Questionnaire: [APPLE_ACCOUNT_QUESTIONNAIRE.md](APPLE_ACCOUNT_QUESTIONNAIRE.md).
