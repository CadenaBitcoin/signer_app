# Release record: iOS 1.0.4 (1000035), skeleton

> **Record Status: `DRAFT`. NOT AUTHORIZED. This file is a skeleton.** Every blank is unknown until someone
> with the stated role fills it, in a reviewed pull request. A blank or "TBD" is a stop, never a
> default. Procedure: [../IOS_RELEASE.md](../IOS_RELEASE.md); this file holds only what is specific to
> this release. It contains no secret, no key material and no credential, and must never receive
> one. Counterpart of [../ANDROID_RELEASE.md](../ANDROID_RELEASE.md) section 9.

## 0. Record status

Allowed values: `DRAFT`, `G1 AUTHORIZED`, `G2 AUTHORIZED`, `WITHDRAWN` (IOS_RELEASE.md section 3). Changed only by a reviewed
pull request; `M` (section 3 below) never changes after G1 without a new G1.

**Record Status: `DRAFT`**

## 1. Fixed by the repository (not an authorization)

| | |
|---|---|
| Platform, channel | iOS, App Store Connect / TestFlight (production record, first delivery internal only) |
| Bundle ID | `com.app.cadenabitcoin` |
| Version / build | `1.0.4` / `1000035` (`pubspec.yaml`; Android already published 1.0.4 (1000035)) |
| Configuration | `config/build/production.json` (SHA-256: TBD) |
| Reviewed content (`CONTENT_REF`) | `862831e0b3a0f30c4155d2e086c69fc28bdab286` (`development`, merge of PR #97; includes PRs #97, #98 and #99) unless the coordinator records another reviewed commit |
| Unsigned compile validation of `CONTENT_REF` | run `43210431581`, `ios-production`, success (compile and link only; no signing, no runtime evidence) |

## 2. Roles for this release (names or accounts; no role is implied by another)

| Role | Held by | Date confirmed |
|---|---|---|
| Release coordinator | TBD | TBD |
| Apple-side operator | TBD | TBD |
| Independent release authorizer (not the coordinator, not the operator) | TBD | TBD |

## 3. Approved source (G1, by the release coordinator)

| | |
|---|---|
| `APPROVED_SHA` = `M` (a `production` merge commit; never the commit of a record pull request) | TBD |
| Also written on Issue #71 by the coordinator / by the independent authorizer | TBD / TBD |
| Proof that its application content equals `CONTENT_REF` | output of the empty `git diff --stat` of IOS_RELEASE.md section 5: TBD |
| `build-variants` runs of the two promotions | staging: TBD; production: TBD |
| Native library SHA-256 | `203dcd7abe4187de0b756638a55f691b2d5c680b17d4fbfa7dda550ed703949b` (pinned; confirm unchanged) |

## 4. Dispositions and accepted deviations

| Item | Decision | By | Date |
|---|---|---|---|
| Issue #22 for this release (IOS_RELEASE.md section 11). #22 stays open. The deterministic-nonce helper is removed from the source interfaces (PR #97) but remains in the precompiled library; no identified call path | TBD | TBD | TBD |
| **Proposed:** retain the existing native Rust binary for the 1.0.4 TestFlight candidate; no rebuild. **Requires the CTO's explicit approval before G2 is requested**; the independent authorizer accepts or rejects it at G2 | TBD | TBD | TBD |
| Production App Store Connect record used for the first TestFlight delivery (IOS_SIGNING.md section 2 item 1 names a staging record) | TBD | TBD | TBD |
| Mac-local signing instead of a protected CI environment (policy section 2.1) | TBD | TBD | TBD |
| `gate --channel production` read as applicable to iOS only (IOS_RELEASE.md section 4) | TBD | TBD | TBD |
| Push entitlement and `remote-notification` mode | TBD | TBD | TBD |
| Export-compliance and App Privacy answers (owner and legal) | TBD | TBD | TBD |
| Privacy-manifest finding | TBD | TBD | TBD |
| Xcode other than 26.3 (17C529), if any | none | TBD | TBD |
| Existing production App Store Connect record used for the first internal TestFlight delivery, instead of the staging record of IOS_SIGNING.md section 2 (one-release exception; no policy change) | TBD | TBD | TBD |

## 5. Facts confirmed by the operator before signing (IOS_RELEASE.md section 6)

| # | Fact | Answer |
|---|---|---|
| 1 | Team, enrollment type, Team ID | TBD |
| 2 | App Store Connect record: name, SKU, bundle ID, status | TBD |
| 3 | Live version and highest build ever uploaded | TBD |
| 4 | App ID registration and capabilities | TBD |
| 5 | Operator's role and access | TBD |
| 6 | Distribution certificate: SHA-256 fingerprint, expiry, creator, key holder | TBD |
| 7 | Signing route (A automatic / B manual) | TBD |
| 8 | Agreements accepted | TBD |
| 9 | Export compliance and privacy answers given | TBD |
| 10 | Push and privacy-manifest decisions known | TBD |
| 11 | Mac, Xcode, SDK, Flutter, CocoaPods versions; test devices and iOS versions | TBD |
| 12 | Zero-value production test account approved by | TBD |

## 6. Authorization gates (IOS_RELEASE.md section 1)

| Gate | Decision | By | Date | Reference |
|---|---|---|---|---|
| G1 source | TBD | TBD | TBD | TBD |
| G2 production signing and upload to App Store Connect | TBD | TBD | TBD | TBD |
| G3 assignment to named internal testers | TBD | TBD | TBD | TBD |
| G4 submission to App Review (needs the 12-hour evidence, IOS_RELEASE.md section 11) | **not given** | | | |
| G5 public release | **not given** | | | |

## 7. Results (filled from the operator's evidence; hashes and text only)

| | |
|---|---|
| IPA SHA-256 and size | TBD |
| Verification V1 to V9 | TBD |
| Symbol inspection (a) to (c); the nine exported names (expected to include `_create_deterministic_nonce_c`: the library is not rebuilt) | TBD |
| Upload time, tool, App Store Connect messages (verbatim) | TBD |
| Processed build as shown in App Store Connect | TBD |
| Tester group and testers (roles or names) | TBD |
| 12-hour session log summary: total hours, devices, iOS versions, overnight interval | TBD |
| Tests T1 to T10 | TBD |
| Crashes; device-log secret check hit counts | TBD |
| Retention (IOS_RELEASE.md section 12): `SHA256SUMS` value, storage kind, custodian role, access list, transfers | TBD |
| Ledger entry in `config/release/published_versions.json` (PR) | TBD |
