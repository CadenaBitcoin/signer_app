# iOS CI validation build

> **CI VALIDATION — NOT APPROVED FOR PUBLIC DISTRIBUTION.**
> The artifact produced by this workflow is an infrastructure check. It is an
> **unsigned** `Runner.app`: it cannot be installed on a device, has not been run
> anywhere, and is not a release, a TestFlight build or an App Store build.
>
> **It is built with the STAGING configuration** (`config/build/staging.json`:
> `https://staging.purabitcoin.com/app`, Signet), selected explicitly with
> `--dart-define-from-file`, never by the branch name; a build without a complete
> configuration fails (see [BUILD_CONFIGURATION.md](BUILD_CONFIGURATION.md)). The
> notice inside every artifact states the resolved environment.

Workflow: `.github/workflows/ios-ci-validation.yml` (companion to the Android
workflow described in `docs/ANDROID_CI.md`).

## Goal and scope

Prove that the iOS app compiles and links on a GitHub-hosted macOS runner
**without any Apple credentials**, and keep the unsigned `Runner.app` as a
downloadable artifact for inspection. Signing, TestFlight, App Store
distribution, device installation and runtime testing are out of scope.

## Trigger

- **Automatic:** every push to `staging`. Because `staging` is protected, a push
  only happens when an authorized maintainer merges a pull request into it
  (see `GOVERNANCE.md`). The workflow adds no authorization logic of its own.
- **Manual:** `workflow_dispatch` (Actions tab → *iOS CI validation build* →
  *Run workflow*) builds any chosen ref without promoting anything. It is only
  offered once the workflow file exists on the default branch (`development`).

Token permission is `contents: read`. There are **no secrets** and no signing
material. All actions are pinned by commit SHA.

## Environment

| Item | Value |
|---|---|
| Runner | `macos-15` (Apple-silicon arm64; not `macos-latest`) |
| Xcode | 26.3, selected explicitly (`/Applications/Xcode_26.3.app`) |
| iPhoneOS SDK | 26.x (Xcode 26.3 provides 26.2); at least **26** is required |
| Flutter | 3.35.3 stable (arm64 SDK, revision `a402d9a437`), Dart 3.9.2 |
| CocoaPods | 1.17.0 (the version of the `macos-15` image; asserted, not installed) |
| Ruby | 3.3.12 on the image (recorded, not pinned; its `json` gem 2.7.2 decides the plugin checksums in `Podfile.lock`, see "`ios/Podfile.lock` drift") |

The workflow **fails** unless the runner is arm64, Xcode is 26.3, the iPhoneOS SDK is
26 or later, CocoaPods is 1.17.0, and Flutter and Dart are the versions above. The
actual versions, the runner image version and the iPhoneOS SDK version are recorded
in the artifact notice. The same values are pinned in `build-variants.yml`; the
static check `tool/verify_ios_toolchain.sh` (run by every `build-variants` run, and
tested by `tool/test_ios_toolchain.sh`) fails if the two workflows differ.

### Why this toolchain (Issue #70)

- **Apple:** since 2026-04-28 binaries uploaded to App Store Connect must be built with
  Xcode 26 or later and an iOS 26 SDK
  ([upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)). The
  rule limits the SDK, not the deployment target. Apple's page does not mention TestFlight
  separately; TestFlight delivery goes through App Store Connect, so the same toolchain is
  assumed to be required.
- **Runner:** the `macos-15` image (checked 2026-10-20, image 20260907) provides Xcode 26.0.1,
  26.1.1, 26.2 and 26.3 next to its default Xcode 16.4, and CocoaPods 1.17.0. Xcode 26.3 is the
  newest 26.x on that image. The `macos-26` image (default Xcode 26.6) was not chosen: it
  changes the operating system as well as the toolchain. If GitHub removes Xcode 26.3 from
  `macos-15`, the explicit selection fails with a clear message and the options are another
  26.x on `macos-15` or `macos-26`, each a reviewed change of the pins.
- **Flutter 3.35.3 is kept.** It predates Xcode 26, so Xcode 26 is not covered by a
  compatibility statement from Flutter; the hosted build is the proof. If it, or a pod
  (Sumsub `IdensicMobileSDK` 1.42.0, `FingerprintPro` 2.14.0), does not build, the failure
  is reported as it is: a Flutter or dependency upgrade is a separate, explicitly approved
  issue (`CLAUDE.md` sections 3 and 7).

## What the build does

1. Check out the exact pushed commit.
2. Select Xcode 26.3 and verify it. Install Flutter 3.35.3.
3. Record and verify the toolchain (above), including the iPhoneOS SDK major version and
   the CocoaPods version.
4. `flutter pub get --enforce-lockfile` (root), then in `flutter_plugin/flutter_plugin`.
5. `/bin/bash tool/verify_build_config.sh verify`: the configuration test matrix,
   release/AOT compile checks, the analyzer guard and the portability scan, run
   with macOS's system bash 3.2 on purpose. Then record what the app itself
   resolves from `config/build/staging.json` with `--flavor staging` and require
   `APP_ENV=staging`.
6. `flutter analyze --no-fatal-infos --no-fatal-warnings`: only analyzer errors
   fail the build (baseline 0 errors; existing warnings/info are known technical
   debt, `CLAUDE.md` section 4). There is no `test/` directory, so no `flutter test`.
7. Record the bundled Rust static library and verify it is unchanged (below).
8. `flutter build ios --release --no-codesign --flavor staging --dart-define-from-file=config/build/staging.json`.
   Flutter runs `pod install` itself; `--no-codesign` sets `CODE_SIGNING_ALLOWED=NO`,
   so no certificate or profile is needed. The `staging` flavor is the Xcode scheme
   `staging` with the configurations `Debug|Profile|Release-staging`: bundle ID
   `com.app.cadenabitcoin.staging`, display name "Cadena Signer STAGING".
   Right after it, `tool/check_build_drift.sh` **fails the job if the build changed any tracked
   file**, in particular if CocoaPods rewrote `ios/Podfile.lock` (see "`ios/Podfile.lock` drift").
9. Locate `Runner.app`, check its executable is arm64, and read its bundle
   identifier and version.
10. Check the compiled Dart snapshot (`Frameworks/App.framework/App`): it must contain
    the staging backend URL and must not contain the production one. This is
    supporting evidence, not proof of network isolation
    ([BUILD_CONFIGURATION.md](BUILD_CONFIGURATION.md)).
    Then `tool/verify_artifact.sh ios staging Runner.app --min-sdk 26`: bundle identifier,
    display name, version fields and the unsigned state, read from the built app, and the
    toolchain the app itself records (next section).
11. Zip the **complete** bundle with `ditto` (this preserves symlinks and
    permissions), write the notice and a SHA-256 checksum file, and upload them.

Equivalent on a Mac (it cannot be run on Linux):

```bash
flutter pub get --enforce-lockfile
(cd flutter_plugin/flutter_plugin && flutter pub get)
flutter build ios --release --no-codesign --flavor staging --dart-define-from-file=config/build/staging.json
```

The five-variant compile validation (both iOS apps among them) is the separate
`build-variants` workflow: [BUILD_CONFIGURATION.md](BUILD_CONFIGURATION.md#the-five-build-variants).

### What the built app proves about the toolchain

The runner's `xcodebuild -version` says what was installed, not what compiled the app.
`tool/verify_artifact.sh ios … --min-sdk 26` therefore reads the **built app**:

| Read from | Fact | Rule |
|---|---|---|
| `Info.plist` | `DTPlatformName`, `DTSDKName` (for example `iphoneos26.2`), `DTXcode`, `DTXcodeBuild`, `DTSDKBuild` | a device build; the SDK major version is at least `--min-sdk` |
| `Runner` executable (Mach-O, `tool/macho_info.py`) | platform, minimum OS, SDK of every architecture slice | iOS device (not a simulator); SDK at least `--min-sdk`; minimum OS equals `MinimumOSVersion` |
| `Info.plist` | `MinimumOSVersion` | present, and at least iOS 13 (App Store Connect, from 2026-09-09) |
| Every `Frameworks/*.framework` binary | platform, minimum OS, SDK | not a simulator build; **a framework that needs a newer OS than the app declares is a warning** and is counted in `deployment_target_conflicts` |

The same facts are in the run's evidence (`built_*`, `executable_*`, `minimum_os_version`,
`framework.*`, `deployment_target_conflicts`) and in the notice. The tool's self-test also
proves the SDK check can fail (a newer required SDK is rejected). `tool/macho_info.py`
needs no Xcode tools and is tested on synthetic binaries (`tool/test_ios_toolchain.sh`).
These are facts the binary states about itself: recorded evidence, not authentication.

### What a green run shows, and what it does not

A green run is **compile and link validation**. It shows that, on the pinned toolchain, the
sources build and link into an unsigned `Runner.app` that records the iOS 26 SDK, the expected
bundle identity and environment, and an unchanged `ios/Podfile.lock`. It does **not** show
**runtime compatibility**: nothing launched the app, no loader (`dyld`) checked a framework against
an iOS version, no simulator or device ran any code, and no signing, provisioning or entitlement
was exercised. In particular, a green run says nothing about which iOS versions the app really
runs on (see the requirement below), about the behaviour of the Rust library on any iOS version,
or about the backend, Sumsub or Fingerprint Pro working with this bundle. Those need their own
tests on devices, as part of the distribution approval (Issue #71 and later).

### Deployment targets: what each value governs

Four values existed and none is wrong by itself; they govern different things.
`tool/verify_ios_toolchain.sh` lists them on every run and fails on a value below
Apple's iOS 13 floor.

| Value | File | Governs |
|---|---|---|
| **14.0** | `Runner.xcodeproj` (`IPHONEOS_DEPLOYMENT_TARGET`, identical in all 6 configurations, no override on the Runner target) | the **Runner app**: its executable's minimum OS and `MinimumOSVersion` |
| **15.5** | `ios/Podfile` (`platform :ios, '15.5'`) | the **Pods project**; a pod whose podspec declares a minimum below iOS 13 inherits it (Flutter's `podhelper.rb`: `flutter_additional_ios_build_settings`), pods that declare 13.0 or higher keep their own |
| 13.0 | `ios/Flutter/AppFrameworkInfo.plist` | `MinimumOSVersion` in the Info.plist of `App.framework` (the compiled Dart code) |
| 12.0 | `dlc_wallet.podspec` (`s.platform`) | the lowest iOS the plugin declares it supports; a floor, not a target |

Effective result: the app declares iOS **14.0** (`MinimumOSVersion`), but five of its own
frameworks need more. **This is an unresolved discrepancy and has not been changed** (a
deployment target is a product decision, not a toolchain one; nothing edits the declared
minimum automatically). It is measured on every build (`deployment_target_conflicts`, a WARN
line) so that it is visible and cannot grow unnoticed.

Measured on the hosted builds at commit `cbe1e6b` (runs 39586225426 production and 39587627313
staging validation; `framework.*` in the evidence):

| Binary | Minimum OS it records | Why |
|---|---|---|
| `Runner` (the app) | **14.0** | Xcode project |
| `dlc_wallet`, `flutter_local_notifications`, `flutter_secure_storage`, `fluttertoast`, `mobile_scanner` | **15.5** (the 5 conflicts) | their podspecs declare a minimum below iOS 13 (12.0, 11.0, 9.0, none, 12.0), so they inherit the Podfile platform |
| `workmanager_apple` | 14.0 | its podspec |
| `App`, `Flutter`, `flutter_idensic_mobile_sdk_plugin`, `path_provider_foundation`, `shared_preferences_foundation`, `FingerprintPro`, `IdensicMobileSDK_Fisherman` | 13.0 | their own podspecs or binaries |
| `IdensicMobileSDK` | 12.0 | prebuilt binary |
| the **eight secp256k1 C objects** inside the Rust library (linked into `dlc_wallet.framework`) | **18.5** (SDK 18.5) | built with the build machine's default target; the other 450 objects say 10.0 |

What this means, stated as the facts the evidence supports and no more: the app advertises iOS
14.0, but a copy installed on iOS 14.0 to 15.4 is expected to be refused by the loader (dyld
checks each image's minimum OS) because five embedded frameworks are built for 15.5. That has not been
tried on a device. The eight Rust objects are linked into a framework
that records 15.5, so the loader does not enforce their own 18.5; whether those C objects
use anything that exists only on newer iOS is **not known** and is a question for the
owner of the library. Resolving the first needs a product decision: raise the project target to
15.5, or lower the Podfile platform (then the five inherit it, and each would have to build
at the new value). Neither is done here. The Rust library's own minimum (10.0) is only a floor
of most of its objects and is not a target (see below).

#### Release-compatibility requirement (open; recorded by Issue #70, accepted 2026-10-21)

The values below are recorded as a requirement that **must be met before any build is approved for
distribution** (TestFlight, App Store or any other). Issue #70 does not meet it and changes none of
the values.

| Component | Minimum iOS it records |
|---|---|
| Application (`Runner`, `MinimumOSVersion`) | **14.0** |
| Five embedded frameworks (`dlc_wallet`, `flutter_local_notifications`, `flutter_secure_storage`, `fluttertoast`, `mobile_scanner`) | **15.5** |
| Eight secp256k1 C objects inside the Rust library (linked into `dlc_wallet.framework`) | **18.5** |

1. **The effective minimum supported iOS version must be established** (a product decision that
   names one value and makes the app, the Podfile platform and the frameworks agree with it), **and
   tested on real iOS versions at and near that minimum** (installation, launch, and the paths that use
   the five frameworks and the Rust library) before a distribution build is approved. Until then the
   advertised 14.0 is not a verified claim.
2. The eight 18.5 objects need an answer from the owner of the Rust library: whether the code in
   them uses anything that exists only on newer iOS. The loader enforces the minimum of the
   framework (15.5), not of those objects, so the evidence cannot answer it.
3. **The existing Rust library must not be replaced or modified without separate
   authorization.** Rebuilding it to lower the 18.5 is such a change and is not part of #70.
4. Raising the project target to 15.5, or lowering the Podfile platform, are the two ways to remove the
   discrepancy between the app and its frameworks. Both change a declared minimum and need the
   same decision as item 1.

Compile and link success (see "What a green run shows") does not satisfy this requirement.

### `ios/Podfile.lock` drift

**Resolved (Issue #70); drift now fails the build.** The hosted iOS builds reported
`ios/Podfile.lock drift` (CocoaPods rewrote the file). The production run 39586225426 uploaded
the exact diff and the regenerated lock; the analysis below was done from them and from an
independent local recomputation.

**What changed** (9 `SPEC CHECKSUMS` lines and the `COCOAPODS:` line; nothing else):

| Pod | Committed (CocoaPods 1.16.2) | Generated on the runner (1.17.0) |
|---|---|---|
| `dlc_wallet` | `3de40703…` | `a27b2e65…` |
| `flutter_idensic_mobile_sdk_plugin` | `6b7b8274…` | `9a56e094…` |
| `flutter_local_notifications` | `a5a732f0…` | `ff50f840…` |
| `flutter_secure_storage` | `1ed9476f…` | `d33dac7a…` |
| `fluttertoast` | `2c67e14d…` | `21eecd69…` |
| `mobile_scanner` | `91579364…` | `77265f3d…` |
| `path_provider_foundation` | `bb55f6db…` | `0b743cbb…` |
| `shared_preferences_foundation` | `7036424c…` | `5086985c…` |
| `workmanager_apple` | `904529ae…` | `4cb452c5…` |
| `COCOAPODS:` | `1.16.2` | `1.17.0` |

`PODS` (every pod version, including `FingerprintPro` 2.14.0 and `IdensicMobileSDK` 1.42.0),
`DEPENDENCIES`, `SPEC REPOS`, `EXTERNAL SOURCES`, the checksums of the external pods
(`FingerprintPro`, `IdensicMobileSDK`), `Flutter` and `PODFILE CHECKSUM` are byte-identical. No
dependency version, external checksum or resolution changed.

**Why** (reproduced, not assumed): for a plugin pod loaded from a path, CocoaPods stores the
podspec as pretty-printed JSON and records the SHA-1 of that JSON. That checksum therefore
depends on the podspec **and on the Ruby `json` gem of the machine that writes the lock**.

- The plugin podspecs at the versions pinned in `pubspec.lock`, evaluated with Ruby 3.3.12 and
  `cocoapods-core` 1.17.0 (the runner's), give exactly the nine generated checksums
  (the Idensic plugin with the Podfile's `IDENSIC_WITH_FISHERMAN=true`).
- With `json` 2.8.2 or later (tested: 2.8.2, 2.9.1 as bundled with Ruby 3.4, and 2.10.2; the tested
  2.3.0, 2.6.3 and 2.7.2 give the runner's values), the same podspecs give the
  **committed** checksums for eight of the nine pods (`dlc_wallet`, whose podspec has not changed since
  2025-11, included). The difference is one formatting detail: json 2.7 and earlier print an empty
  list as `[` newline newline `]`, the later ones as `[]` (the `Flutter` dependency list of each pod).
  `cocoapods-core` 1.16.2 and 1.17.0 give identical results; the CocoaPods version did not matter.
- The ninth, `workmanager_apple`, differs in substance: the committed value is the podspec of
  `workmanager_apple` 0.9.1 to 0.9.1+2, while `pubspec.lock` (Issue #40, #42) pins 0.9.4. The lock was
  written before the reproducible baseline and had not been refreshed.

So the committed lock is consistent with a machine that had a newer Ruby (`json` 2.8 or later) and an
older `workmanager_apple`; the regenerated one is what the pinned sources produce on the pinned runner image
(Ruby 3.3.12, CocoaPods 1.17.0). The lock was replaced by the runner's file unchanged.

**Consequences:**

- `ios/Podfile.lock` must be taken **from the pinned runner image** (the `Podfile.lock.generated`
  file of the `ios-diagnostics_*` artifact), not generated on a developer Mac: a Mac with a
  newer Ruby writes different plugin checksums and every hosted build would then fail the drift check.
- Both iOS workflows now run `tool/check_build_drift.sh` after the build. **Any** tracked file changed
  by the build fails the job; `ios/Podfile.lock` drift prints the diff and an error naming the cause.
  `tool/verify_ios_toolchain.sh` fails if either workflow lacks the check, runs it before the
  build, allows a step to fail silently, or still reports the drift as a warning, and if the
  committed lock names a CocoaPods version other than the pinned one. `PODFILE CHECKSUM` is
  checked by `tool/verify_version.sh`. A runner image with a different Ruby or CocoaPods now fails
  visibly instead of passing with a warning.
- Every `build-variants` iOS job still uploads, also when the build fails, the text-only artifact
  `ios-diagnostics_<variant>_a<attempt>` (14 days; `build.log`, `pods.txt`, `Podfile.lock.diff`,
  `Podfile.lock.generated`), so the next required lock change can be read and reviewed the same way.

### External downloads (during `pod install`)

The CocoaPods CDN (`FingerprintPro`), the `SumSubstance/Specs` git spec repository
and Sumsub's `IdensicMobileSDK-1.42.0.zip` on raw.githubusercontent. A failure of
any of them fails the build. The build is otherwise self-contained.

## Native Rust library (unverified provenance)

`dlc_wallet` links `flutter_plugin/flutter_plugin/ios/Classes/libdlcplazacryptlib.a`
(podspec: `-force_load`). This is a **prebuilt static library committed once**
(commit `df269f6`); nothing here rebuilds it, and nothing proves it matches
`flutter_plugin/src`. It is a fat archive: **arm64 = iOS device**,
**x86_64 = iOS simulator**; the arm64-simulator slice lives in the unused
`Classes/simulator/` copy, so an Apple-silicon simulator build is not supported by
the linked file. The `device/`, `simulator/` and `_selected` copies and
`select_library.sh` are not referenced by the podspec.

Recorded facts (Issue #70, `tool/macho_info.py`, read-only): SHA-256
`203dcd7abe4187de0b756638a55f691b2d5c680b17d4fbfa7dda550ed703949b`; 43,723,576 bytes;
arm64 slice = 458 objects (406 with minimum iOS 10.0 and no SDK recorded, 44 with 10.0 and SDK
17.2, **8 with minimum iOS 18.5 and SDK 18.5**) and an x86_64 slice. The 8 objects of the
secp256k1 C sources (`secp256k1.o`, `precomputed_ecmult.o`, `precomputed_ecmult_gen.o`,
`lax_der_parsing.o`, each twice) were evidently compiled with the build machine's default
target (iOS 18.5) instead of the minimum of the Rust objects. The linker accepts older
objects; objects built for a newer OS than the link target may raise a linker warning and
are a question for the library's owner, not something this issue changes. Every iOS build
records these values (`rust_lib_build_versions`); the hosted builds reproduced them exactly
(the x86_64 slice has the same 8 objects, recorded as `ios-simulator`). The linker did not fail.
The library is linked into `dlc_wallet.framework`, which records minimum iOS 15.5.

To make any change visible, the workflow pins the library's SHA-256
(`EXPECTED_RUST_LIB_SHA256`) and fails if it differs before or after the build. If
the library is legitimately replaced, review it, document where it came from, and
update that value in the same pull request.

## Retrieving the artifact

1. Open the workflow run (Actions tab, or the run link in the notice file).
2. Download the artifact from the **Artifacts** section (a GitHub login is
   required, even for a public repository). Artifacts are kept for **14 days**.
3. Unzip the download. It contains:
   - `…_Runner.app.zip`: the complete app bundle,
   - `SHA256SUMS.txt`: verify with `shasum -a 256 -c SHA256SUMS.txt`,
   - `CI-VALIDATION-NOTICE.txt`.
4. Extract the bundle on a Mac with `ditto -x -k <file>_Runner.app.zip <dir>` (a
   plain `unzip` can lose symlinks inside frameworks).

Artifact naming:

```text
CI-VALIDATION-NOT-APPROVED-FOR-PUBLIC-DISTRIBUTION_cadena-signer-ios_v<version>_<environment>_unsigned_<sha7>_run<run>-<attempt>
```

`<version>` is the unchanged `version:` from `pubspec.yaml`, `<environment>` the
`APP_ENV` the app resolved (`staging`), `<sha7>` the short commit SHA and
`<run>-<attempt>` the GitHub run number and attempt. The notice also lists the full
SHA, run URL, archive size and SHA-256, the toolchain, the Rust library details, the
bundle identity, the resolved environment values with the file that selected them,
and the result of the built-app check. The run summary and a workflow annotation
repeat the environment.

## Known limitations

- **Unsigned and unrun.** Compilation and linking only; nothing has launched this
  app. Real signing, installation, TestFlight and App Store use need Apple
  credentials and a separate, reviewed design.
- **Staging configuration, compile-time validated only.** Use of this bundle against
  the backend has not been exercised (it cannot be installed anyway).
- **Deployment targets** differ by purpose and are an **unresolved discrepancy**: the app
  declares iOS 14.0, five frameworks are built for 15.5 and eight Rust C objects for 18.5 (see
  "Deployment targets"). Measured on every build, intentionally not changed. Establishing and
  testing the effective minimum iOS version is a **release-compatibility requirement that blocks
  distribution approval** (see "Release-compatibility requirement").
- **Compile and link validation is not runtime compatibility** (see "What a green run shows").
- **Xcode 26.3 is pinned** and must remain on the `macos-15` image. Flutter 3.35.3 with
  Xcode 26 has no compatibility statement from Flutter, but it built on the hosted runs
  listed under "Verification status".
- **The version is not modified.** iOS requires a numeric
  `CFBundleShortVersionString`, so a prerelease suffix such as `-rc.1` is never
  embedded; staging candidates are named by a release identifier instead
  ([RELEASE_POLICY.md](RELEASE_POLICY.md) section 7).
- **Separate bundle identifier** `com.app.cadenabitcoin.staging` (the `staging` flavor),
  the same value as the Android application ID and different from production's
  `com.app.cadenabitcoin`. It is not registered with Apple; an unsigned build needs no
  registration.
- The `DEVELOPMENT_TEAM` value in the Xcode project is committed but unused by this
  build (no signing).

## Verification status

### Acceptance runs (Issue #70, accepted 2026-10-21)

Hosted runs of commit `f299fdb4bfaf5fd1521a1038d97dec8fc66d18ee` (branch
`issue/70-ios-release-toolchain`, `workflow_dispatch`, 2026-10-21; Xcode 26.3, iPhoneOS SDK 26.2,
Flutter 3.35.3, CocoaPods 1.17.0, Ruby 3.3.12 on `macos-15`). This commit carries the regenerated
`ios/Podfile.lock` and the strict `tool/check_build_drift.sh`.

| Run | Workflow | Result |
|---|---|---|
| [39597753070](https://github.com/CadenaBitcoin/signer_app/actions/runs/39597753070) | `build-variants`, `ios-staging` | success; "Verify the built app" and "No tracked file may be changed by the build (ios/Podfile.lock drift fails)" both passed |
| [39599011459](https://github.com/CadenaBitcoin/signer_app/actions/runs/39599011459) | `build-variants`, `ios-production` | success; the same two steps passed |
| [39608182641](https://github.com/CadenaBitcoin/signer_app/actions/runs/39608182641) | `ios-ci-validation` | success; the same two steps passed (unsigned staging `Runner.app`) |

What they establish: the application compiles and links with Xcode 26.3 and the iPhoneOS 26.2
SDK, the built-app check (which requires an SDK of at least 26) passes for both iOS variants and
the validation build, and **no tracked file was modified by any of the three builds**, so the
committed `ios/Podfile.lock` is exactly what the pinned runner produces. Compile and link only; see
"What a green run shows, and what it does not". The deployment-target values in the tables above
were measured at the earlier commit below; nothing that sets them (`ios/Podfile`, the Xcode project,
any podspec or dependency) changed between the two commits, and the minimum-iOS requirement
remains open.

### Earlier runs (before the lock update and the strict drift check)

Hosted runs of commit `cbe1e6b08c5d0394418e334d6a6e83f3b6d60fad` (same branch and image, `macos15`
image 20260907.0337.1, Xcode 26.3 (17C529), CocoaPods 1.17.0, Ruby 3.3.12):

| Run | Workflow | Result |
|---|---|---|
| 39583491602 | `build-variants`, `ios-staging` | success (plan, static checks, iOS job and verdict) |
| 39586225426 | `build-variants`, `ios-production` | success (same jobs) |
| 39587627313 | `ios-ci-validation` | success; unsigned staging `Runner.app` (SHA-256 `3b250a2b…` of the zip, matching `SHA256SUMS.txt`) |

Facts read from the evidence of the production run and the validation notice: the app records
`iphoneos26.2` (Info.plist and the Mach-O), platform `ios`, `MinimumOSVersion` 14.0, SDK build
`23C57`, Xcode `2630`/`17C529`; the right environment and identity per variant; 5 deployment-target
conflicts (listed above); the Rust library's SHA-256 unchanged. Flutter 3.35.3, Sumsub
(`IdensicMobileSDK` 1.42.0) and `FingerprintPro` 2.14.0 compiled and linked under Xcode 26.3, and the
unsigned build records the `DT*` keys and `MinimumOSVersion`. Those runs reported the lock drift as a
warning, which led to the lock update and the strict check accepted above.
