# iOS CI validation build

> **CI VALIDATION — NOT APPROVED FOR PUBLIC DISTRIBUTION.**
> The artifact produced by this workflow is an infrastructure check. It is an
> **unsigned** `Runner.app`: it cannot be installed on a device, has not been run
> anywhere, and is not a release, a TestFlight build or an App Store build.
>
> **It currently contains the PRODUCTION backend configuration**
> (`https://cadenabitcoin.com/app`, `"bitcoin"`), because environment selection is
> still the constants in `lib/src/ui/controllers/appController.dart`. The notice
> inside every artifact says so.

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
| Xcode | 16.4, selected explicitly (`/Applications/Xcode_16.4.app`) |
| Flutter | 3.35.3 stable (arm64 SDK, revision `a402d9a437`), Dart 3.9.2 |
| CocoaPods / Ruby | whatever the runner image provides (recorded, not pinned) |

The workflow **fails** unless the runner is arm64, Xcode is 16.4, and Flutter and
Dart are the versions above. The actual versions, the runner image version and the
iPhoneOS SDK version are recorded in the artifact notice.

## What the build does

1. Check out the exact pushed commit.
2. Select Xcode 16.4 and verify it. Install Flutter 3.35.3.
3. Record and verify the toolchain (above).
4. `flutter pub get --enforce-lockfile` (root), then in `flutter_plugin/flutter_plugin`.
5. `flutter analyze --no-fatal-infos --no-fatal-warnings`: only analyzer errors
   fail the build (baseline 0 errors; existing warnings/info are known technical
   debt, `CLAUDE.md` section 4). There is no `test/` directory, so no `flutter test`.
6. Record the bundled Rust static library and verify it is unchanged (below).
7. `flutter build ios --release --no-codesign`. Flutter runs `pod install` itself;
   `--no-codesign` sets `CODE_SIGNING_ALLOWED=NO`, so no certificate or profile is needed.
8. Locate `Runner.app`, check its executable is arm64, and read its bundle
   identifier and version.
9. Zip the **complete** bundle with `ditto` (this preserves symlinks and
   permissions), write the notice and a SHA-256 checksum file, and upload them.

Equivalent on a Mac (it cannot be run on Linux):

```bash
flutter pub get --enforce-lockfile
(cd flutter_plugin/flutter_plugin && flutter pub get)
flutter build ios --release --no-codesign
```

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
CI-VALIDATION-NOT-APPROVED-FOR-PUBLIC-DISTRIBUTION_cadena-signer-ios_v<version>_unsigned_<sha7>_run<run>-<attempt>
```

`<version>` is the unchanged `version:` from `pubspec.yaml`, `<sha7>` the short commit
SHA and `<run>-<attempt>` the GitHub run number and attempt. The notice also lists
the full SHA, run URL, archive size and SHA-256, the toolchain, the Rust library
details, the bundle identity and the production-configuration warning. The run
summary and a workflow warning annotation repeat the warning.

## Known limitations

- **Unsigned and unrun.** Compilation and linking only; nothing has launched this
  app. Real signing, installation, TestFlight and App Store use need Apple
  credentials and a separate, reviewed design.
- **Production configuration.** No build-configuration mechanism exists on this
  branch, so the committed constants (production) apply. When the Android
  build-configuration work lands, this workflow should pass the staging file with
  `--dart-define-from-file` exactly as that workflow does.
- **First hosted run.** The workflow was validated locally with emulated macOS
  commands only (no Mac was available). Its first real run may need adjustment.
- **Deployment targets are inconsistent** (project 14.0, `Podfile` 15.5,
  `AppFrameworkInfo.plist` 13.0, podspec 12.0). They are intentionally not changed
  unless a real build failure shows it is needed.
- **Xcode 16.4 is pinned** and must remain on the `macos-15` image; Xcode 26 and
  Flutter 3.35.3 are untested together.
- **Versioning is undecided.** The version is not modified. iOS requires a numeric
  `CFBundleShortVersionString`, so a prerelease suffix such as `-rc.1` cannot be
  used there as is.
- **Same bundle identifier** (`com.app.cadenabitcoin`) as Android and production.
- The `DEVELOPMENT_TEAM` value in the Xcode project is committed but unused by this
  build (no signing).
