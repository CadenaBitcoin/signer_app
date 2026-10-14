# Build-time configuration and application variants

The backend and Bitcoin network of every build are chosen **explicitly, at build
time**, by a configuration file, and the platform **application identity** by a Flutter
flavor of the same name. There is **no default environment and no default flavor**: a
build without a complete, consistent configuration, or whose flavor disagrees with it,
does not compile. This applies to local debug builds, `flutter run`, release/AOT builds
and CI alike. Neither environment can fall back to the other, and the Git branch name
never selects an environment.

This is the mechanism behind sections 5 and 6 of [RELEASE_POLICY.md](RELEASE_POLICY.md).
It is shared by Android and iOS. Android and iOS CI validation:
[ANDROID_CI.md](ANDROID_CI.md), [IOS_CI.md](IOS_CI.md).

## Files

```text
config/build/staging.json      non-secret staging values
config/build/production.json   non-secret production values
lib/config/build_config.dart   BuildConfig: the one place the values are read and validated
android/app/build.gradle.kts   the two Android flavors (identity only)
ios/Flutter/Flavor-<flavor>.xcconfig        iOS identity per flavor
ios/Flutter/{Debug,Profile,Release}-<flavor>.xcconfig   the six iOS configurations' xcconfig
ios/Runner.xcodeproj/xcshareddata/xcschemes/{staging,production}.xcscheme
tool/verify_build_config.sh    test matrix, AOT checks, analyzer guard, resolve helper
tool/verify_version.sh         version and flavor wiring (source only)
tool/verify_artifact.sh        reads a BUILT artifact and checks it
tool/build_config_probe.dart   helper compiled by verify_build_config.sh (not part of the app)
.github/workflows/build-variants.yml   compiles and verifies the five variants (all, or one)
tool/plan_build_variants.sh            which variants a run requires (trigger -> selection)
```

| Key | Staging | Production |
|---|---|---|
| `APP_ENV` | `staging` | `production` |
| `NETWORK_ENVIRONMENT` | `signet` | `bitcoin` |
| `USE_TESTNET` | `true` | `false` |
| `API_BASE_URL` | `https://staging.purabitcoin.com/app` | `https://cadenabitcoin.com/app` |

The files hold no secrets. The staging values are those documented in
[SECURITY_BOUNDARY.md](SECURITY_BOUNDARY.md); the native library accepts only
`bitcoin` and `signet`. `AppController.USE_TESTNET`, `NETWORK_ENVIRONMENT` and
`API_BASE_URL` are aliases of `BuildConfig`, so no other application code reads
the environment from anywhere else.

## The two flavors: application identity

| | `production` | `staging` |
|---|---|---|
| Android application ID | `com.app.cadenabitcoin` (unchanged) | `com.app.cadenabitcoin.staging` |
| iOS bundle ID | `com.app.cadenabitcoin` (unchanged) | `com.app.cadenabitcoin.staging` |
| Display name (both platforms) | Cadena Bitcoin (unchanged) | Cadena Signer STAGING |
| Configuration file | `config/build/production.json` | `config/build/staging.json` |

Staging and production are **different applications that install side by side**; they
share no storage, keychain items or keystore entries. The staging identifiers are the
proposal of [RELEASE_POLICY.md](RELEASE_POLICY.md) section 5. They are **not registered
anywhere** (Apple, Google): nothing in this repository needs them to be until something
is signed. The flavor changes nothing else: not the version, the Android namespace, the
`MainActivity` package, the signing configuration, the native library or any wallet code.

**Android.** `flavorDimensions "environment"` with `production` and `staging`;
`staging` adds `applicationIdSuffix ".staging"`, and each flavor supplies the launcher
label through the `${appLabel}` manifest placeholder. The `release` build type still
uses the temporary debug signing configuration. Each flavor also passes a distinct,
functionless CMake argument: Flutter's Gradle plugin adds an empty CMake build only to
make the Android Gradle plugin download the NDK, and without a difference between the
flavors the plugin shares one native-build task between them and ties it to a single
flavor, so a production build would also run the staging Dart compile with production
defines (which the consistency check below rightly rejects). With the argument each
flavor builds only itself.

**iOS.** Two Xcode schemes, `production` and `staging`, and six build configurations
`Debug|Profile|Release-<flavor>` (Flutter derives the configuration from the scheme
name). Each configuration's xcconfig includes the CocoaPods xcconfig of its own name,
`Generated.xcconfig` and `Flavor-<flavor>.xcconfig`, which holds the only identity values
(`PRODUCT_BUNDLE_IDENTIFIER`, `APP_DISPLAY_NAME`). The app target no longer sets a
bundle identifier itself (project settings would override the xcconfig), and
`Info.plist` reads `CFBundleDisplayName` from `$(APP_DISPLAY_NAME)`. `DEVELOPMENT_TEAM`,
the version settings and everything else are unchanged. There is **no unflavored
scheme or configuration**, so Flutter stops an iOS build without `--flavor` before
CocoaPods or Xcode run. `ios/Podfile` maps the six configurations, and the
`PODFILE CHECKSUM` of `ios/Podfile.lock` is the SHA-1 of the Podfile.

### Why the flavor cannot select anything

The flavor selects only the native identity. Flutter passes it to Dart as
`FLUTTER_APP_FLAVOR` (and refuses to let it be set by hand), and `BuildConfig` fails the
build unless it equals `APP_ENV`. The flavor names are the environment names, so there is
no mapping table and no second environment selector: `config/build/<env>.json` remains the
only definition of what an environment is. Do **not** set `default-flavor` in
`pubspec.yaml`; that would be a default.

## Selecting an environment: commands

Every Flutter command that compiles the app needs the flavor and the file of the same
environment:

```bash
# Local development and testing: STAGING (Signet) with a disposable test account
flutter run                       --flavor staging --dart-define-from-file=config/build/staging.json
flutter build apk --debug         --flavor staging --dart-define-from-file=config/build/staging.json

# Production builds (never test with a wallet that holds value)
flutter build apk --release       --flavor production --dart-define-from-file=config/build/production.json
flutter build appbundle --release --flavor production --dart-define-from-file=config/build/production.json

# iOS (same flags; macOS only)
flutter build ios --release --no-codesign --flavor staging --dart-define-from-file=config/build/staging.json
```

- **Android Studio / IntelliJ:** *Run → Edit Configurations →* the Flutter run
  configuration *→ Build flavor:* `staging`, *Additional run args:*
  `--dart-define-from-file=config/build/staging.json`.
- **VS Code:** in your own (uncommitted) `.vscode/launch.json` add
  `"args": ["--flavor", "staging", "--dart-define-from-file=config/build/staging.json"]`.
- **Xcode directly:** choose the scheme `staging` or `production`. Xcode uses the defines of
  the last Flutter-generated configuration, so run `flutter build ios --config-only
  --flavor <flavor> --dart-define-from-file=<file>` first. This path has not been exercised.
- `flutter pub get` and `flutter analyze` need **no** configuration (see
  [The analyzer](#the-analyzer-and-its-one-suppression)).

Forgetting either is safe: the build stops with, for example,

```text
Error: Constant evaluation error:
  This assertion failed with message: Build flavor "staging" does not match APP_ENV
  "production". The flavor selects the application identity and must agree with the
  environment: use --flavor production with config/build/production.json.
```

and produces no app. On Android, a build with no `--flavor` makes Gradle assemble every
flavor with the one configuration, so the flavor that does not match it rejects the
build. Switching environments never involves editing source files.

## What is rejected

Validation is a set of constant assertions in `lib/config/build_config.dart`. A
violated rule is a **compile-time error in debug, profile and release/AOT builds**.
The first violated rule is printed.

| Situation | Result |
|---|---|
| No configuration at all | rejected, no default |
| `APP_ENV` missing/empty but other keys present | rejected (partial) |
| `APP_ENV` anything but `staging` or `production` (typo, wrong case) | rejected |
| `NETWORK_ENVIRONMENT`, `USE_TESTNET` or `API_BASE_URL` missing | rejected (incomplete) |
| `NETWORK_ENVIRONMENT` not `bitcoin`/`signet`; `USE_TESTNET` not `true`/`false` | rejected |
| `USE_TESTNET=true` unless `signet` (either direction) | rejected (contradictory) |
| Staging with any URL but `https://staging.purabitcoin.com/app`, or not `signet` | rejected |
| Production with any URL but `https://cadenabitcoin.com/app`, or not `bitcoin` | rejected |
| Staging values labelled production, or the reverse | rejected |
| `http://`, trailing-slash variants, unknown hosts | rejected |
| Valid configuration but **no flavor** (Dart level; iOS stops even earlier) | rejected |
| **Staging flavor with `production.json`**, or production flavor with `staging.json` | rejected |
| Flavor in another case or an unknown flavor (`dev`, `Staging`) | rejected |

A new backend endpoint therefore needs a reviewed change to `build_config.dart`
as well as the JSON file. Extra keys in the JSON file are ignored by Dart.

## The five build variants

The repository compiles five variants, **without any signing credential**:

| # | Variant | Command (plus `--dart-define-from-file=config/build/<env>.json`) | Signing today |
|---|---|---|---|
| 1 | staging Android APK | `flutter build apk --release --flavor staging` | temporary debug signing |
| 2 | staging iOS app | `flutter build ios --release --no-codesign --flavor staging` | unsigned |
| 3 | production Android APK | `flutter build apk --release --flavor production` | temporary debug signing |
| 4 | production Android AAB | `flutter build appbundle --release --flavor production` | temporary debug signing |
| 5 | production iOS app | `flutter build ios --release --no-codesign --flavor production` | unsigned |

**These are compile proofs, not release artifacts.** The Android `release` build type
still uses the debug signing configuration, so the APKs and AAB are signed with an
ordinary debug certificate and a Play upload or an update of a real installation would
be refused or insecure. The iOS apps are unsigned and cannot be installed. None of the
five is distributable, official or a release candidate. Official signing, Apple
provisioning, TestFlight, store delivery and release identifiers are separate, later
steps ([RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md)). No version
override is used: the version comes only from `pubspec.yaml`.

Outputs: `build/app/outputs/flutter-apk/app-<flavor>-release.apk`,
`build/app/outputs/bundle/<flavor>Release/app-<flavor>-release.aab`,
`build/ios/Release-<flavor>-iphoneos/Runner.app`. The `build/` directory is not ignored
by Git: never `git add` it.

## Verifying the mechanism and the artifacts

```bash
flutter pub get                        # once (also in flutter_plugin/flutter_plugin)
tool/verify_version.sh                 # version + flavor wiring in the source (no Flutter needed)
tool/verify_build_config.sh            # configuration matrix, flavor cases, AOT, analyzer guard
tool/verify_build_config.sh resolve config/build/staging.json staging   # what the app resolves
tool/verify_artifact.sh apk production app-production-release.apk --signing debug
tool/verify_artifact.sh aab production app-production-release.aab --signing debug   # needs BUNDLETOOL_JAR
tool/verify_artifact.sh ios staging build/ios/Release-staging-iphoneos/Runner.app
tool/verify_artifact.sh selftest apk staging app-staging-release.apk --signing debug
```

`tool/verify_build_config.sh verify` runs, in well under a minute: a static scan for bash
constructs that macOS's bash 3.2 lacks; the analyzer guard; the configuration matrix (2
valid and 37 invalid combinations of configuration and flavor, each rejected by the
*intended* rule); and AOT compilation with `dart compile exe` (valid pairs compile and
resolve to the right backend; a missing configuration, a missing flavor and every
mismatch produce no binary). `tool/verify_version.sh` additionally fails if the wiring
deviates: exactly the two flavors, the staging suffix only on staging, no
`versionNameSuffix`, ABI split or version override, the six iOS configurations and two
schemes, the identity files, and a `Podfile.lock` checksum that matches the Podfile.

`tool/verify_artifact.sh` reads what the **built artifact itself** says (aapt2, bundletool,
the `Info.plist`), not what the build command was, and checks:

- the application ID / bundle identifier and display name for the environment;
- the version name and number against `pubspec.yaml` (`X.Y.Z+BUILD`);
- the signing status: Android `debug` (the temporary debug signing, recorded with the
  signer's certificate digest) or `unsigned`; iOS must be unsigned (no provisioning
  profile, no signature resources, no signing authority);
- that a release artifact is not debuggable, and that the Dart snapshot (`libapp.so`
  for every ABI, `App.framework/App`) contains the environment's backend URL and not the
  other's;
- with `consistent`, that the production APK and AAB are one update family.

`selftest` proves the checks can fail: the same artifact claimed for the other environment,
and a debug-signed artifact claimed unsigned, must be rejected. Each run prints an
`evidence` block of `key=value` lines (artifact SHA-256 and size, identity, version,
signing, environment-check result, SHA-256 of the committed native libraries). For an
iOS app the SHA-256 is that of the sorted per-file SHA-256 manifest of the bundle.
The scripts are written for the bash 3.2 that ships with macOS (no arrays, no `mapfile`);
CI runs them there as `/bin/bash`.

### The analyzer and its one suppression

`flutter analyze` and IDEs run without a build configuration. The analyzer
evaluates the rules with empty inputs and reports their intended failure as
`const_eval_throws_exception`. `lib/config/build_config.dart` suppresses exactly
that diagnostic on exactly one line, so the project keeps its 0-error analyzer
baseline. The suppression does not weaken the build: the compiler front end, which
receives the real defines, still rejects every violation, and the script proves it
for debug (`dart run`), AOT (`dart compile exe`) and real `flutter build` runs; the
analyzer guard fails if the suppression is missing, duplicated or changed. If a
Flutter upgrade changes this behavior the guard will say so.

### Inspecting built artifacts: what it proves

Passing a configuration to Flutter is not proof that the resulting artifact uses it. As
supporting evidence the verifier inspects a **release/AOT** build: the compiled Dart
snapshot must contain the selected environment's backend URL and must not contain the
other's.

Limits, stated plainly:

- **Debug builds are inconclusive.** A debug APK embeds the whole kernel, including
  both URLs and every assertion message, so the check cannot distinguish them. The
  Android CI validation build is a debug build; its evidence is the verified
  resolved configuration, the build command and the identity read from the APK
  (`--debug-build`).
- A string match is **not proof of application runtime behavior** or of complete
  network isolation. It does not show how the rest of the app behaves, and later code
  may legitimately contain other strings. It is one check among several (the probe
  matrix, AOT compile checks, the identity and version read from the artifact).
- Nothing here installs or runs an artifact. In particular, side-by-side installation of
  the staging and production apps follows from the different identifiers but has not been
  exercised on a device.

## GitHub Actions

| Workflow | Builds | Uploads |
|---|---|---|
| `android-ci-validation.yml` | debug APK, `staging` flavor | the labelled staging debug APK (14 days) |
| `ios-ci-validation.yml` | unsigned `Runner.app`, `staging` flavor | the labelled staging app, zipped (14 days) |
| `build-variants.yml` | the five variants (above), all or one | **text evidence only** |

The two validation workflows are unchanged in meaning; they build the `staging` flavor
and now also read the identity back from what they built.

### Running the variants: individually or together

`build-variants.yml` has `contents: read`, no secrets and no deployment permission. Each
variant has one identifier, used as the manual selector, the job name and the evidence
file name:

| Identifier | Variant |
|---|---|
| `android-staging-apk` | 1. staging Android APK |
| `ios-staging` | 2. staging iOS app |
| `android-production-apk` | 3. production Android APK |
| `android-production-aab` | 4. production Android AAB |
| `ios-production` | 5. production iOS app |

- **Manual (Actions → Build variants → Run workflow):** choose `all` or exactly one
  identifier. A single variant runs only its own build job plus the shared checks: the
  static checks, and for an Android variant the real-build rejection checks. The other
  four are not executed. (As for any new workflow file, the manual button needs the file
  to be on the default branch.)
- **Coordinated:** a run executes every variant its trigger requires and the `verdict`
  job fails if any *required* job failed, was cancelled or was skipped, or if a required
  variant has no verification evidence. Variants that were not selected are not required.
- **One implementation:** the builds are written once, in the `android` and `ios` jobs.
  `tool/plan_build_variants.sh` decides which variants a trigger requires, the `plan` job
  passes that as the jobs' matrix, and nothing else knows the mapping. It can be run
  locally: `tool/plan_build_variants.sh push issue/65-x`,
  `tool/plan_build_variants.sh workflow_dispatch x ios-staging`.
- **Triggers today (temporary):** a push to `staging` or to an `issue/**` branch runs all
  five, to establish the five-build baseline and to validate a feature branch before its
  pull request exists. **Eventual architecture:** a merge into `staging` runs the two
  staging builds and a merge into `production` the three production builds; both keep
  manual execution of any single variant. Getting there changes only the push mapping in
  `tool/plan_build_variants.sh` (its comment shows the two lines) and the branch list of
  the workflow, not a build.

What a run does:

1. *Plan:* the required variants and their matrices (shown in the run summary).
2. *Static checks (always):* `verify_version.sh`, `verify_build_config.sh verify`,
   `flutter analyze`.
3. *Rejection by real builds (when an Android variant is required):* a staging flavor with
   `production.json`, a production flavor with `staging.json`, no flavor, and no
   configuration must each fail and leave no APK or AAB.
4. *Android jobs:* variants 1, 3 and 4, each followed by `verify_artifact.sh` with its
   self-test. The pinned `bundletool` 1.18.3 (SHA-256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`)
   reads the AAB.
5. *iOS jobs (`macos-15`, Xcode 16.4, the pinned toolchain checks of the iOS validation
   workflow):* a build without `--flavor` must fail; variants 2 and 5; `verify_artifact.sh`;
   the mismatched flavor/configuration pairing must fail; any tracked file other than
   `ios/Podfile.lock` changed by the build is an error, and `Podfile.lock` drift is
   **reported, not hidden**.
6. *Verdict:* every required job must be `success` (and every unselected one `skipped`),
   each required variant must have its evidence, and the cross-artifact checks that apply
   to the selection run: APK/AAB consistency (when both were built) and that staging and
   production differ on each platform (when both were built). The run summary lists each
   variant's identity, version, signing and SHA-256.

**No application binary is uploaded** (and no production binary is retained anywhere): the
uploaded evidence files contain only metadata and hashes. The workflow shows that the
repository compiles and what each artifact claims; it is not a build you can install.

## What this does not do

Not part of this mechanism, by design: release identifiers (`vX.Y.Z-rc.N`) and any change
to the version, official signing, Apple provisioning and registration of the staging
identifiers, TestFlight or store delivery, and per-environment icons (see
[RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md)). It selects the
environment and the application identity and changes no application behavior, wallet
derivation or cryptographic code.
