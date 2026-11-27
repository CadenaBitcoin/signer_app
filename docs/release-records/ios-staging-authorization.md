# Staging authorization record: automatic iOS staging delivery (TestFlight)

> **Status: WITHDRAWN (after the successful delivery of `1.0.5+10005002`, run `46005605593`, 2026-11-27).** The lines below keep the authorization that was given for that one delivery as history (the CTO's decisions of 2026-11-27, section 3, and the recovery decision named by `G2S-STAGING-AUTHORIZATION`); with the status `WITHDRAWN` they authorize nothing. The first attempt, `1.0.5+10005001`, failed before signing and its number is consumed; the second, `1.0.5+10005002`, succeeded (section 5). A new delivery needs a new version, a reviewed pull request and a new CTO decision.
> The staging delivery workflow
> (`.github/workflows/ios-staging-delivery.yml`) reads this file, and `tool/check_staging_authorization.sh` refuses to let it sign or upload unless it says `AUTHORIZED` and
> binds the version, the implementation and the source of the run. Design, prerequisites and the meaning of every line: [docs/IOS_STAGING_DELIVERY.md](../IOS_STAGING_DELIVERY.md).

This is **not** a production record and not part of `ios-1.0.4-1000035.md`. The production gate, its record and its consumed authorizations are untouched. This
record can only ever authorize the **staging** bundle ID and a **staging** App Store Connect application: both are constants of the gate, not values of this file.

## 1. What this record authorizes when it is AUTHORIZED

Exactly this, and nothing else:

- one automatic run of the staging delivery workflow for **each merge commit that is pushed to `staging`** and whose `pubspec.yaml` version equals
  `G2S-STAGING-VERSION` below (a new build number needs this line updated, in the reviewed pull request that advances the version);
- that run builds the unsigned archive of that commit and then **waits for the approval of the environment `ios-hosted-signing-stg`** (the CTO's deployment confirmation, S2/S3);
  only after that approval does it sign with Apple's cloud-managed Distribution certificate named by `G2S-STAGING-CERT-SHA256`, verify the signed IPA, and upload **that same IPA**
  to the staging App Store Connect application `G2S-STAGING-APP-APPLE-ID`;
- the only secrets involved are the three of the GitHub environment `ios-hosted-signing-stg`, **provisioned by the CTO for that run and removed after it** (never stored permanently).

The environment approval is **not** an authorization: without this record in the state `AUTHORIZED` nothing is signed, whoever approves. And without the approval and the temporary secrets nothing is signed, whatever this record says.

It does **not** authorize: tester assignment, App Review, a public or external TestFlight group, a release, the production bundle ID or application, any other
team, a different certificate, a different native library, a different workflow, gate or tool than the blobs below name, or any commit that is not a reviewed
merge of `development` into `staging`.

## 2. The authorization lines

Each line is read by the production gate's strict parser: at column 0, exactly once, LF only, outside code blocks and comments. The values below are the
state **WITHDRAWN**; every other line is the authorization that was given for version `1.0.5+10005002` (the CTO's decisions, section 3, and the recovery decision named by `G2S-STAGING-AUTHORIZATION`), kept as history. The certificate value is the one observed in the production runs
(decision C1: accepted with that provenance, corroborated by the attributes of Apple's certificate records but not by a fingerprint comparison), and the native-library value is the STAGING archive's own hash (section 2.1; decision C2).

G2S-STAGING-STATUS: WITHDRAWN
G2S-STAGING-OPERATION: sign-verify-and-upload
G2S-STAGING-VERSION: 1.0.5+10005002
G2S-STAGING-BUNDLE-ID: com.app.cadenabitcoin.staging
G2S-STAGING-TEAM-ID: D65458CPDP
G2S-STAGING-APP-APPLE-ID: 6839776198
G2S-STAGING-CERT-SHA256: 7ee3f6ce78eea83748e198102f6ab66527c626296baaea437c3a90db81ef418e
G2S-STAGING-DLC-WALLET-SHA256: 92231f38c71864833cd6bcdf03c4849c72e6e0a7d66bd59b826dd2798680646d
G2S-STAGING-WORKFLOW-BLOB: 0336bf49730851b0bda8bb7dffbeba1fee943809
G2S-STAGING-GATE-BLOB: 46483dff8204a2cbfb98d6c2b670cedd4242d049
G2S-STAGING-TOOL-BLOBS: tool/build_manifest.py=3041c560adcac9ad2f3b052378825762518df30e,tool/check_signing_authorization.sh=fe841d2d5eb5b533551f28608e294ca3165f1ac0,tool/ipa_inspect.py=20b7efc972d55b40a23276c5ed29a0e4b281269b,tool/validate_handover_archive.py=ef4ce2c686e2ae7c3eacb61d078764f8c5b71c3d,tool/verify_artifact.sh=b9d81a3aa171d4e3d900137f3a0c68fb8441fde4,tool/verify_build_config.sh=0e1bce96d68ade109ffb961258008b13a15beec4,tool/verify_ipa.py=7d31b621efa82448384f08f67ee119e765eb9338
G2S-STAGING-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7218186057
G2S-STAGING-DECISION-S1: Decided by CadenaWizard on 2026-11-27
G2S-STAGING-DECISION-S2: Decided by CadenaWizard on 2026-11-27
G2S-STAGING-DECISION-S3: Decided by CadenaWizard on 2026-11-27
G2S-STAGING-DECISION-S4: Decided by CadenaWizard on 2026-11-27

### 2.1 Provenance of the native-library line (a proposal, not an approval)

The line `G2S-STAGING-DLC-WALLET-SHA256` is the SHA-256 of `Frameworks/dlc_wallet.framework/dlc_wallet` inside the **unsigned staging archive**, the file the delivery's `sign` job hashes before any secret exists.

- **Value:** `92231f38c71864833cd6bcdf03c4849c72e6e0a7d66bd59b826dd2798680646d`. It replaces the first proposal, the production archives' value `9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13`, which stays the (unchanged) value of the production record.
- **Measured by** two independent runs of the credential-free `iOS staging archive preflight`: `45967581978` and `45969558826` (https://github.com/CadenaBitcoin/signer_app/actions/runs/45967581978 and https://github.com/CadenaBitcoin/signer_app/actions/runs/45969558826), both on `development` commit `2aac65d2b3ee33918f4a636c7442d52e139abdec` (tree `a94a58588209aaa57233a916b0217bdf08aa3bcb`), version `1.0.5+10005001`, `flutter build ipa --release --no-codesign --flavor staging --dart-define-from-file=config/build/staging.json`, runner image `macos15 20261118.0550.1`, macOS 15.8.2, Xcode 26.3 (17C529), iPhoneOS SDK 26.2, Flutter 3.35.3, Dart 3.9.2, CocoaPods 1.17.0, Rust library `203dcd7abe4187de0b756638a55f691b2d5c680b17d4fbfa7dda550ed703949b`.
- **Reproducibility:** both runs gave this exact hash although their archive tars differ (`d288829b…500b`, `d13a735b…20e5`), as the production archives' tars did while their framework stayed equal. Both used the same runner image, so equality across images is **not** shown here.
- **Why the production value cannot be reused:** the compiled framework embeds Xcode's object-file paths, which carry the flavor and the build action (production archive: `…/ArchiveIntermediates/production/IntermediateBuildFilesPath/Pods.build/Release-production-iphoneos/dlc_wallet.build/…`; staging: `…/Release-staging-iphoneos/dlc_wallet.build/…`). With those four path strings normalized, the two binaries' string tables are identical; the bytes still differ. A staging archive can never equal the production hash.
- **Limitation:** any change of Xcode, the runner image's tools or paths, the runner work directory, the Pods build layout or other compiler-generated paths can change this hash. The delivery then stops before Xcode and before any secret, and the promotion's build number is consumed (RELEASE_POLICY.md 7.3). Run the preflight again on the final `development` tip before the promotion.
- Run `45976062284` (on `f754453`, build content identical to `2aac65d`) is the one run that is a `MATCH` against this value as recorded in the pin; runs `45967581978` and `45969558826` measured it while the pin still held the production value. The same framework hash was therefore measured three times, and matched the corrected pin once.
- The CTO accepted this value as decision C2 on 2026-11-27 (section 3), acknowledging the toolchain and runner-image limitation above: a hash mismatch stops the delivery before any secret.

## 3. The decisions (taken by the CTO on 2026-11-27)

A decision line has the form `Decided by <name> on YYYY-MM-DD`. The gate checks the form, not the person: the CTO's written decision on the issue named by
`G2S-STAGING-AUTHORIZATION` is the authority, and the reviewed pull request that sets these lines is its record. The CTO (account `CadenaWizard`) approved S1 to S4 and
C1 to C4 in that comment on 2026-11-27; the table below is the content of S1 to S4, as approved.

| ID | Decision | Notes |
|---|---|---|
| S1 | **Staging identity and application.** Staging is delivered to its own App Store Connect application, bundle ID `com.app.cadenabitcoin.staging` ("Cadena Signer STAGING"), never to the production record. | The record must exist in App Store Connect before the first run; its numeric Apple ID is `G2S-STAGING-APP-APPLE-ID`. This also ends the one-release exception of the production record's D4 for later releases. |
| S2 | **Credential: temporary provisioning of the Admin key, with an environment approval.** The Admin-role App Store Connect Team API key (the existing key of D16 to D18 or a dedicated new one, the CTO's choice) is held **offline** by the CTO. It is registered as the three secrets of the GitHub environment `ios-hosted-signing-stg` **only while the `sign` job waits for approval**, the CTO then approves the job, and **removes the three secrets at once after the run**, whatever its result. **Permanent storage of the key in GitHub is not authorized.** | The production runs established that cloud-managed signing needed the **Admin** role (Developer and App Manager keys failed with identical errors; whether Admin is strictly necessary is not proven) and that a team key cannot be limited to one application: the same accepted risks as D16 apply (account-wide scope, broad administrative capabilities, temporary exposure to the protected environment, deferred independent backup, no guarantee of success), and removing the secrets does not revoke the key (a separate CTO decision). The environment is restricted to the branch `staging` and has required reviewers (docs/IOS_STAGING_DELIVERY.md section 5). |
| S3 | **Authorization model.** The reviewed merge into `staging`, carrying this record, is the authorization; the environment approval after the merge **confirms the deployment only** and neither replaces nor creates an authorization (as D12 for production; the reviewers are one person and no independence is claimed). This record is bound to the version, identity, certificate, native library and implementation, and is withdrawn on `development`. | Replaces the per-operation, consumed, manually dispatched authorization of the production workflow for staging only. RELEASE_POLICY.md 2.3 ("no step follows the merge") and IOS_SIGNING.md section 6 ("required reviewers are not used") still read otherwise: reconciling them is a reviewed amendment, not made here. |
| S4 | **Zero-value rule.** Staging is Signet (`config/build/staging.json`); the delivered application never holds mainnet funds. | The gate and the workflow check the staging configuration and the absence of the production backend URL in the signed app (V6). |

**C1 to C4 and the operational decisions** (same comment; C1 and C2 are the values of the lines above, C3 and C4 have no line):

- **C1** The certificate with SHA-256 `G2S-STAGING-CERT-SHA256` is accepted on its provenance from the previously signed production IPAs. On 2026-11-27 the CTO inspected the Apple Developer certificate records and found: name Cadena Bitcoin S.A. de C.V., type Distribution Managed, expiration 2027-07-09, automatic rotation 2027-04-10, and only one managed distribution certificate listed; these corroborate the certificate seen in the production signing runs. Direct fingerprint verification was not possible in Apple's interface; the CTO accepted that limitation. A certificate fingerprint mismatch prevents the upload.
- **C2** The framework hash `G2S-STAGING-DLC-WALLET-SHA256` (section 2.1) and the Rust library hash are accepted; the toolchain and runner-image limitation is acknowledged; a hash mismatch stops the delivery.
- **C3** Build number `10005001` is consumed when the promotion reaches `staging`, whatever the outcome. After a failure the next attempt is a reviewed pull request with a new number; reruns and reuse are prohibited. Applied once: `10005001` failed (section 5), the next attempt is `10005002`.
- **C4** This delivery has no `-rc.N` identifier and no Git tag; traceability is the version, the build number, the commit, this record and the workflow run.
- The debug-signed Android staging validation APK is accepted for this delivery (public retrievability through Actions and an ephemeral signing key acknowledged).
- No separate experiment on the timing of environment secrets is required: GitHub's documented lifecycle is accepted, this exact sequence being not yet exercised here. If it fails, the secrets are removed and the next reviewed attempt may provision them before the promotion.
- No further credential-free preflight is required while the build content (`lib`, `ios`, `flutter_plugin`, `pubspec.yaml`, `pubspec.lock`, `config/build`, `android`) and the bound implementation files stay unchanged and no concrete technical reason arises.
- Reconciliation of the release-policy documents (RELEASE_POLICY.md 2.3, 3.1, 7.1 to 7.4; IOS_SIGNING.md section 6) is deferred until after the first successful staging delivery; the deviations are authorized for this delivery only.
- Not authorized: production delivery, public release, external TestFlight distribution, tester assignment by this record.

**Recovery decision of 2026-11-27 for `1.0.5+10005002`** (https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7218186057, the line `G2S-STAGING-AUTHORIZATION`; failure evidence: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7217999694):

- **R1** One merge-triggered delivery of `1.0.5+10005002` under S1 to S4 and C1 to C4, subject to R2 and R3; identities, certificate fingerprint, native-library hashes and security controls unchanged. The CodeQL alert #1 risk acceptance is extended to this delivery while the relevant workflow, cache configuration and assessed security conditions stay unchanged. All other restrictions and temporary policy exceptions of the first authorization remain in effect.
- **R2** The three secrets `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` are provisioned in `ios-hosted-signing-stg` **before** the merge into `staging` (preferably immediately before it, after review and CI), and their existence is verified by name and count before the promotion. The increased credential-exposure window is accepted. The environment approval remains mandatory; the secrets are removed immediately after completion, failure or cancellation. This amends S2 for this delivery only.
- **R3** No additional preflight is required solely because of the build-number increment; other changed build-relevant inputs or bound files require reassessment.

## 4. How to authorize, and how to withdraw

**Authorize** (one reviewed pull request into `development`, carried to `staging` with the version advance):

1. Complete the Apple and GitHub prerequisites of docs/IOS_STAGING_DELIVERY.md section 5 (they are not repository changes): the environment exists with the branch restriction and the required reviewers, and **holds no secret**.
2. Take the decisions S1 to S4 in writing on Issue #71 (the CTO's revised credential decision of 2026-11-26 is the basis of S2 and S3; its comment URL goes into `G2S-STAGING-AUTHORIZATION`).
3. In this file: set `G2S-STAGING-AUTHORIZATION` and the four decision lines (`G2S-STAGING-APP-APPLE-ID` is already the verified `6839776198`); confirm or correct the certificate line from the production evidence and the native-library line from section 2.1 (and a fresh preflight on the final `development` tip); set `G2S-STAGING-VERSION` to the version in `pubspec.yaml` of the same pull request; refresh the three blob lines with
   `bash tool/check_staging_authorization.sh --print-expected --tools-root .`; and only then set `G2S-STAGING-STATUS` to `AUTHORIZED`.
4. `tool/test_check_staging_authorization.sh` refuses an AUTHORIZED record whose blobs are not those of the checkout.

**Withdraw** (done after the delivery of `1.0.5+10005002`; immediately effective for every later run): a pull request into `development` that sets `G2S-STAGING-STATUS` to `WITHDRAWN`. The gate reads this file on the
**current tip of `development`** at run time, so a withdrawal there stops a delivery even if the promotion already carries `AUTHORIZED`. To stop at once without a merge:
**reject** the waiting `sign` job, or do not provision the secrets (the environment holds none between deliveries); if they were already provisioned, remove them.

**Per delivery** (not part of this record's lines; docs/IOS_STAGING_DELIVERY.md section 1.1; for `10005002` the three secrets are provisioned and checked **before** the merge, section 5): the run waits at the environment approval; the CTO provisions the three secrets, approves within one day of the
build (the unsigned archive is kept one day), and removes the secrets after the run.

## 5. Delivery history

| Attempt | Version | Run | Outcome |
|---|---|---|---|
| 1 | `1.0.5+10005001` | https://github.com/CadenaBitcoin/signer_app/actions/runs/45995314041 (push of PR #150, `staging` at `a6ed42f`, 2026-11-27) | **Failed before signing.** `authorize` and `build` passed; the framework hash check passed on the real merge commit; `sign` was approved by `CadenaWizard` about 31 seconds after it began waiting and its step "Export and sign ... (the only step with secrets)" stopped with `A secret of the environment ios-hosted-signing-stg is missing`: all three secrets were empty in the step, and the environment, the production environment and the repository held none. No key file was written, nothing was exported, signed or uploaded. The number `10005001` is **consumed** (C3). Recorded on Issue #71: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7217999694 |
| 2 | `1.0.5+10005002` | https://github.com/CadenaBitcoin/signer_app/actions/runs/46005605593 (push of PR #152, `staging` at `f31e598`, 2026-11-27) | **Succeeded technically.** The three secrets had been provisioned and checked by name and count before the merge; the environment approval came about 72 seconds after `sign` began waiting. The `dlc_wallet` framework equalled the pin; the IPA was signed with the pinned certificate `7ee3f6ce…ef418e`; V1 to V9 passed; `altool` validated and uploaded the same IPA (SHA-256 `b08cc7c2…ab4f07`); delivery UUID `4baabc47-2809-445c-a7ec-4cd24998923b`; the key file was removed; the maintainer then removed the three secrets and the API showed 0 secrets everywhere. Apple's two warnings (deployment target 14.0, SDK 26.2; both dated April 2027) did not block. **CTO-reported afterwards (2026-11-27, verified by the CTO in App Store Connect):** processing completed, export compliance (including the France-specific questions) completed, internal group assignment confirmed, TestFlight status "Testing", 90 days remaining. **Also CTO-reported (2026-11-27):** an internal tester installed the build through TestFlight, launched it, completed the initial setup and logged in; the CTO considers the basic end-to-end acceptance satisfied. This is a basic smoke test, **not** a test of wallet or DLC functionality (not tested). Full record and checksums: [staging-delivery-1.0.5-10005002.adoc](staging-delivery-1.0.5-10005002.adoc). No workflow, gate or tool changed (the blob lines above are unchanged). |
