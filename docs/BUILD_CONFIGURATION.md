# Build-time configuration

The backend and Bitcoin network of every build are chosen **explicitly, at build
time**, by a configuration file. There is **no default environment**: a build
without a complete, consistent configuration does not compile. This applies to
local debug builds, `flutter run`, release/AOT builds and CI alike. Neither
environment can fall back to the other, and the Git branch name never selects an
environment.

This is the mechanism behind section 6 of [RELEASE_POLICY.md](RELEASE_POLICY.md).
It is shared by Android and iOS (pure Dart, no platform code). Android and iOS CI
validation: [ANDROID_CI.md](ANDROID_CI.md), [IOS_CI.md](IOS_CI.md).

## Files

```text
config/build/staging.json      non-secret staging values
config/build/production.json   non-secret production values
lib/config/build_config.dart   BuildConfig: the one place the values are read and validated
tool/verify_build_config.sh    test matrix, AOT checks, analyzer guard, resolve helper
tool/build_config_probe.dart   helper compiled by that script (not part of the app)
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

## Selecting an environment: commands

Every Flutter command that compiles the app needs the flag, with the file of the
environment you want:

```bash
# Local development and testing: STAGING (Signet) with a disposable test account
flutter run                         --dart-define-from-file=config/build/staging.json
flutter build apk --debug           --dart-define-from-file=config/build/staging.json

# Production builds (never test with a wallet that holds value)
flutter build apk --release         --dart-define-from-file=config/build/production.json
flutter build appbundle --release   --dart-define-from-file=config/build/production.json

# iOS (same flag; macOS only)
flutter build ios --release --no-codesign --dart-define-from-file=config/build/staging.json
flutter build ipa                   --dart-define-from-file=config/build/production.json
```

- **Android Studio / IntelliJ:** *Run → Edit Configurations →* the Flutter run
  configuration *→ Additional run args:* `--dart-define-from-file=config/build/staging.json`.
- **VS Code:** in your own (uncommitted) `.vscode/launch.json` add
  `"args": ["--dart-define-from-file=config/build/staging.json"]`.
- **Xcode directly:** Xcode uses the defines of the last Flutter-generated
  configuration, so run `flutter build ios --config-only
  --dart-define-from-file=<file>` first. This path has not been exercised.
- `flutter pub get` and `flutter analyze` need **no** configuration (see
  [The analyzer](#the-analyzer-and-its-one-suppression)).

Forgetting the flag is safe: the build stops with, for example,

```text
Error: Constant evaluation error:
  This assertion failed with message: No build configuration was supplied and
  there is no default environment. Pass --dart-define-from-file=...
```

and produces no app. Switching environments never involves editing source files.

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

A new backend endpoint therefore needs a reviewed change to `build_config.dart`
as well as the JSON file. Extra keys in the JSON file are ignored by Dart.

## Verifying the mechanism

```bash
flutter pub get                        # once (also in flutter_plugin/flutter_plugin)
tool/verify_build_config.sh            # everything below; non-zero exit on any failure
tool/verify_build_config.sh matrix     # valid / invalid configurations only
tool/verify_build_config.sh aot        # release/AOT compiles and binary checks
tool/verify_build_config.sh analyzer   # analyzer clean + exactly one narrow suppression
tool/verify_build_config.sh portability
tool/verify_build_config.sh resolve config/build/staging.json   # what the app resolves
```

`verify` runs, in well under a minute: a static scan for bash constructs that macOS's
bash 3.2 lacks; the analyzer guard; the configuration matrix (2 valid and 30 invalid
configurations, each rejected by the *intended* rule); and AOT compilation with
`dart compile exe` (valid configurations compile and resolve to the right backend;
a missing configuration and a staging/production mix-up produce no binary).

The script is written for the bash 3.2 that ships with macOS (no arrays, no
`mapfile`). CI runs it on the macOS runner as `/bin/bash tool/verify_build_config.sh`
so that the system bash is what is tested. `tool/verify_version.sh` is unaffected
(`tool/verify_version.sh` still passes; neither script depends on the other).

### The analyzer and its one suppression

`flutter analyze` and IDEs run without a build configuration. The analyzer
evaluates the rules with empty inputs and reports their intended failure as
`const_eval_throws_exception`. `lib/config/build_config.dart` suppresses exactly
that diagnostic on exactly one line, so the project keeps its 0-error analyzer
baseline. The suppression does not weaken the build: the compiler front end, which
receives the real defines, still rejects every violation, and the script proves it
for debug (`dart run`), AOT (`dart compile exe`) and the analyzer guard fails if
the suppression is missing, duplicated or changed. If a Flutter upgrade changes
this behavior the guard will say so.

### Inspecting built artifacts

Passing a configuration to Flutter is not proof that the resulting artifact uses
it. As supporting evidence, the pipeline can inspect a **release/AOT** build:

```bash
tool/verify_build_config.sh check-binary staging path/to/libapp.so        # Android release
tool/verify_build_config.sh check-binary staging Runner.app/Frameworks/App.framework/App   # iOS
```

It requires the selected environment's backend URL in the compiled Dart snapshot
and requires the **other** environment's URL to be absent. Measured on release
APKs built from this repository: the staging build contained only the staging URL
and the production build only the production URL.

Limits, stated plainly:

- **Debug builds are inconclusive.** A debug APK embeds the whole kernel, including
  both URLs and every assertion message, so the check cannot distinguish them. The
  Android CI validation build is a debug build; its evidence is the verified
  resolved configuration plus the build command, not the binary.
- A string match is **not proof of complete network isolation**. It does not show
  how the rest of the app behaves, and later code may legitimately contain other
  strings. It is one check among several (the probe matrix, AOT compile checks and,
  later, per-artifact identity checks).
- iOS: the AOT check on `App.framework/App` is performed by the macOS CI workflow;
  it has to be confirmed on a hosted run.

## What this does not do

Not part of this mechanism, by design: Flutter flavors, separate application IDs,
iOS schemes, release identifiers, signing, TestFlight or store delivery (see
[RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md)). It is strictly
build-time configuration: it selects the environment and changes no application
behavior, wallet derivation or cryptographic code.
