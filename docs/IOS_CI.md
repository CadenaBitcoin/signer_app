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
| Ruby | whatever the runner image provides (recorded, not pinned) |

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

### Deployment targets: what each value governs

Four values existed and none is wrong by itself; they govern different things.
`tool/verify_ios_toolchain.sh` lists them on every run and fails on a value below
Apple's iOS 13 floor.

| Value | File | Governs |
|---|---|---|
| **14.0** | `Runner.xcodeproj` (`IPHONEOS_DEPLOYMENT_TARGET`, identical in all 6 configurations, no override on the Runner target) | the **Runner app**: its executable's minimum OS and `MinimumOSVersion` |
| **15.5** | `ios/Podfile` (`platform :ios, '15.5'`) | the **Pods project**: every pod compiled into a framework |
| 13.0 | `ios/Flutter/AppFrameworkInfo.plist` | `MinimumOSVersion` in the Info.plist of `App.framework` (the compiled Dart code) |
| 12.0 | `dlc_wallet.podspec` (`s.platform`) | the lowest iOS the plugin declares it supports; a floor, not a target |

Effective result: the app declares iOS **14.0** (`MinimumOSVersion`), but the pods are
built for **15.5**, so an installed copy needs iOS 15.5 to load those frameworks. This has
**not been changed** (a deployment target is a product decision, not a toolchain one); it
is measured on every build (`deployment_target_conflicts`, a WARN line) so that the
difference is visible and cannot grow unnoticed. Resolve it, if wanted, in a separate
decision by raising the project target to the Podfile's value or by lowering the Podfile
platform. The Rust library's own minimum (10.0) is only a floor of its objects and is
not a target (next section).

### `ios/Podfile.lock` drift

The hosted iOS builds inspected (runs 39264546620 and 39298431155) report `ios/Podfile.lock drift`
(CocoaPods rewrites the file). The build does not hide it and does not commit it. Findings so far:

- The committed lock's contents were last generated by CocoaPods **1.16.2** (commit `6385bc2`,
  2026-09-21), before the
  reproducible dependency baseline (`pubspec.lock`, Issue #40, 2026-10-05), so its
  `SPEC CHECKSUMS` describe plugin versions that may differ from today's locked versions.
  Later commits changed only the `PODFILE CHECKSUM` line (#65).
- The runner image provides CocoaPods **1.17.0**, which may rewrite the `COCOAPODS:` line.
  Whether the rewrite also changes checksums or versions is **not yet known**: job logs need
  authentication, and the lock cannot be regenerated on Linux.
- Every `build-variants` iOS job now uploads, also when the build fails, the artifact
  `ios-diagnostics_<variant>_a<attempt>` (text only, 14 days, a different prefix from the
  `build-evidence_*` artifacts so that the verdict never sees it): `build.log` (the output of
  `flutter build ios`, for reading an exact compiler or CocoaPods failure), `pods.txt` (CocoaPods
  and Ruby versions, the lock's checksum before and after), `Podfile.lock.diff` and
  `Podfile.lock.generated`. That is the evidence for the disposition, which needs a reviewed
  decision: commit the regenerated lock (the exact change is reviewed first), or pin the
  CocoaPods version used to produce it. Until then the drift stays a warning.

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
records these values (`rust_lib_build_versions`).

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
- **Build-configuration steps not yet confirmed on a hosted macOS run.** The
  configuration verification under `/bin/bash` 3.2 and the check of
  `App.framework/App` were validated on Linux only; they have to pass on a real
  `macos-15` run before the change is accepted.
- **First hosted run.** The workflow was validated locally with emulated macOS
  commands only (no Mac was available). Its first real run may need adjustment.
- **Deployment targets** differ by purpose (project 14.0, `Podfile` 15.5,
  `AppFrameworkInfo.plist` 13.0, podspec 12.0; see the table above). They are measured on every
  build and intentionally not changed.
- **Xcode 26.3 is pinned** and must remain on the `macos-15` image. Flutter 3.35.3 with
  Xcode 26 has no compatibility statement from Flutter; the status of the hosted builds
  is in "Verification status" below.
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

Local (Linux) verification of the Issue #70 changes: the static checks and the tests above.
**Hosted builds under Xcode 26.3 are the open evidence:** run `build-variants` by hand for
`ios-staging` and `ios-production` and the iOS validation workflow, on the branch, and record
the run IDs here or in the issue. A failure that comes from Flutter 3.35.3 or a pod is
reported with its exact error, not worked around.
