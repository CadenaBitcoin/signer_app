# Staging authorization record: automatic iOS staging delivery (TestFlight)

> **Status: WITHDRAWN (the committed default).** Nothing in this record authorizes anything until the CTO's written decision exists and a reviewed pull
> request sets the lines of section 2 to real values and `G2S-STAGING-STATUS` to `AUTHORIZED`. The staging delivery workflow
> (`.github/workflows/ios-staging-delivery.yml`) reads this file, and `tool/check_staging_authorization.sh` refuses to let it sign or upload while it says
> anything else. Design, prerequisites and the meaning of every line: [docs/IOS_STAGING_DELIVERY.md](../IOS_STAGING_DELIVERY.md).

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
committed default (**WITHDRAWN**). `PENDING` marks a value that only the human owner can supply; the candidate values for the certificate and the native library are the
ones recorded for production and are **proposals** until the CTO accepts them.

G2S-STAGING-STATUS: WITHDRAWN
G2S-STAGING-OPERATION: sign-verify-and-upload
G2S-STAGING-VERSION: 1.0.4+1000035
G2S-STAGING-BUNDLE-ID: com.app.cadenabitcoin.staging
G2S-STAGING-TEAM-ID: D65458CPDP
G2S-STAGING-APP-APPLE-ID: 6839776198
G2S-STAGING-CERT-SHA256: 7ee3f6ce78eea83748e198102f6ab66527c626296baaea437c3a90db81ef418e
G2S-STAGING-DLC-WALLET-SHA256: 9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13
G2S-STAGING-WORKFLOW-BLOB: 0336bf49730851b0bda8bb7dffbeba1fee943809
G2S-STAGING-GATE-BLOB: 46483dff8204a2cbfb98d6c2b670cedd4242d049
G2S-STAGING-TOOL-BLOBS: tool/build_manifest.py=3041c560adcac9ad2f3b052378825762518df30e,tool/check_signing_authorization.sh=fe841d2d5eb5b533551f28608e294ca3165f1ac0,tool/ipa_inspect.py=20b7efc972d55b40a23276c5ed29a0e4b281269b,tool/validate_handover_archive.py=ef4ce2c686e2ae7c3eacb61d078764f8c5b71c3d,tool/verify_artifact.sh=b9d81a3aa171d4e3d900137f3a0c68fb8441fde4,tool/verify_build_config.sh=0e1bce96d68ade109ffb961258008b13a15beec4,tool/verify_ipa.py=7d31b621efa82448384f08f67ee119e765eb9338
G2S-STAGING-AUTHORIZATION: PENDING
G2S-STAGING-DECISION-S1: PENDING
G2S-STAGING-DECISION-S2: PENDING
G2S-STAGING-DECISION-S3: PENDING
G2S-STAGING-DECISION-S4: PENDING

## 3. The decisions that must be taken before `AUTHORIZED`

A decision line has the form `Decided by <name> on YYYY-MM-DD`. The gate checks the form, not the person: the CTO's written decision on the issue named by
`G2S-STAGING-AUTHORIZATION` is the authority, and the reviewed pull request that sets these lines is its record.

| ID | Decision | Notes |
|---|---|---|
| S1 | **Staging identity and application.** Staging is delivered to its own App Store Connect application, bundle ID `com.app.cadenabitcoin.staging` ("Cadena Signer STAGING"), never to the production record. | The record must exist in App Store Connect before the first run; its numeric Apple ID is `G2S-STAGING-APP-APPLE-ID`. This also ends the one-release exception of the production record's D4 for later releases. |
| S2 | **Credential: temporary provisioning of the Admin key, with an environment approval.** The Admin-role App Store Connect Team API key (the existing key of D16 to D18 or a dedicated new one, the CTO's choice) is held **offline** by the CTO. It is registered as the three secrets of the GitHub environment `ios-hosted-signing-stg` **only while the `sign` job waits for approval**, the CTO then approves the job, and **removes the three secrets at once after the run**, whatever its result. **Permanent storage of the key in GitHub is not authorized.** | The production runs established that cloud-managed signing needed the **Admin** role (Developer and App Manager keys failed with identical errors; whether Admin is strictly necessary is not proven) and that a team key cannot be limited to one application: the same accepted risks as D16 apply (account-wide scope, broad administrative capabilities, temporary exposure to the protected environment, deferred independent backup, no guarantee of success), and removing the secrets does not revoke the key (a separate CTO decision). The environment is restricted to the branch `staging` and has required reviewers (docs/IOS_STAGING_DELIVERY.md section 5). |
| S3 | **Authorization model.** The reviewed merge into `staging`, carrying this record, is the authorization; the environment approval after the merge **confirms the deployment only** and neither replaces nor creates an authorization (as D12 for production; the reviewers are one person and no independence is claimed). This record is bound to the version, identity, certificate, native library and implementation, and is withdrawn on `development`. | Replaces the per-operation, consumed, manually dispatched authorization of the production workflow for staging only. RELEASE_POLICY.md 2.3 ("no step follows the merge") and IOS_SIGNING.md section 6 ("required reviewers are not used") still read otherwise: reconciling them is a reviewed amendment, not made here. |
| S4 | **Zero-value rule.** Staging is Signet (`config/build/staging.json`); the delivered application never holds mainnet funds. | The gate and the workflow check the staging configuration and the absence of the production backend URL in the signed app (V6). |

## 4. How to authorize, and how to withdraw

**Authorize** (one reviewed pull request into `development`, carried to `staging` with the version advance):

1. Complete the Apple and GitHub prerequisites of docs/IOS_STAGING_DELIVERY.md section 5 (they are not repository changes): the environment exists with the branch restriction and the required reviewers, and **holds no secret**.
2. Take the decisions S1 to S4 in writing on Issue #71 (the CTO's revised credential decision of 2026-11-26 is the basis of S2 and S3; its comment URL goes into `G2S-STAGING-AUTHORIZATION`).
3. In this file: set `G2S-STAGING-AUTHORIZATION` and the four decision lines (`G2S-STAGING-APP-APPLE-ID` is already the verified `6839776198`); confirm or correct the certificate and native-library lines
   from the production evidence; set `G2S-STAGING-VERSION` to the version in `pubspec.yaml` of the same pull request; refresh the three blob lines with
   `bash tool/check_staging_authorization.sh --print-expected --tools-root .`; and only then set `G2S-STAGING-STATUS` to `AUTHORIZED`.
4. `tool/test_check_staging_authorization.sh` refuses an AUTHORIZED record whose blobs are not those of the checkout.

**Withdraw** (immediately effective for every later run): a pull request into `development` that sets `G2S-STAGING-STATUS` to `WITHDRAWN`. The gate reads this file on the
**current tip of `development`** at run time, so a withdrawal there stops a delivery even if the promotion already carries `AUTHORIZED`. To stop at once without a merge:
**reject** the waiting `sign` job, or do not provision the secrets (the environment holds none between deliveries); if they were already provisioned, remove them.

**Per delivery** (not part of this record's lines; docs/IOS_STAGING_DELIVERY.md section 1.1): the run waits at the environment approval; the CTO provisions the three secrets, approves within one day of the
build (the unsigned archive is kept one day), and removes the secrets after the run.
