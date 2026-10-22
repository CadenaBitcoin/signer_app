# CLAUDE.md — Cadena Bitcoin Signer

Instructions for Claude Code working in this repository. They describe the
**currently established** policy and setup. Where something is not yet decided
it says so — do not fill gaps with guesses; ask the human.

Longer workflow detail: `docs/AI_DEVELOPMENT_WORKFLOW.md`.
Transport/logging security rules: `docs/SECURITY_BOUNDARY.md`.
Branch model, authority levels and contribution rules: `GOVERNANCE.md`,
`CONTRIBUTING.md`.

## 1. What this repository is

- **Cadena Bitcoin Signer**: a Flutter mobile app (Android and iOS) that signs
  Discreet Log Contract (DLC) Bitcoin transactions (Funding, Refund, CET adaptor
  signatures) for the DLCPlaza backend. Manual and automatic signing modes exist.
- **Non-custodial**: wallet secrets (mnemonic, keys) are created, stored and used
  on the device. The backend layer sends only account credentials, the XPUB and
  signatures — never the mnemonic or private keys. This boundary must not erode.
- **Backend interaction**: HTTPS only, through `DataService`
  (`lib/services/dataService/`) and the endpoint wrappers in `ApiService`.
  Authentication is a backend-issued JWT; see `docs/SECURITY_BOUNDARY.md`.
- **Native code**: a Rust crypto library (`dlcplazacryptlib`, source in
  `flutter_plugin/src`, `flutter_plugin/Cargo.toml`) is reached through FFI by the
  local Flutter plugin `dlc_wallet` (`flutter_plugin/flutter_plugin`, a path
  dependency in the root `pubspec.yaml`). Prebuilt binaries (`.so` under
  `jniLibs/`, `.a` under `ios/Classes/`) are committed.

## 2. Source of truth and branch policy

- **Current branch model** (see `GOVERNANCE.md`): `development` (default,
  integration) → `staging` (Signet promotion) → `production` (Mainnet
  release branch). Promotion is forward only; no application logic is developed
  independently on `staging` or `production`.
- `development` is the **active integration and GitHub default branch**. `staging`
  is a protected promotion branch. `main` is legacy and is not an integration
  target. `production` exists and is protected; it was created at the adopted
  initial baseline `7b63c97` (Issue #68), the best-supported historical commit and not
  an exact reconstruction of the published application, and it changes only by
  promotion pull requests from `staging`.
- Every issue starts from `development` (`git switch development &&
  git pull --ff-only`, confirm clean, then branch). Branch name:
  `issue/<N>-<short-name>` (older branches use other spellings).
- Issue branches enter the integration branch **by pull request**. Never commit
  directly to `development`, `staging`, `production` or `main`.
- PRs reference their issue with `Implements #N`, not automatic closing keywords
  (`fixes #N`, `closes #N`); a maintainer closes the issue explicitly.
- Protected-branch review and merge authority belongs to the
  `CadenaBitcoin/Maintainers` team. Promotion, release and signing follow the
  additional authority boundaries in `GOVERNANCE.md`; Claude never exercises them.
- Historical branches (`cadena(v1.0.3+1000033)`, `cryptlib`, `cryptlib1`,
  `cryptlib2`, `index4_*`, `sziller/firebase-installation-work`) are
  **references only** unless a human explicitly reactivates one.
- Do **not** mechanically merge old Firebase or cryptlib branches.
- GitHub issues and PRs are authoritative for scope and decisions. If the issue
  text is unavailable to you, ask rather than infer.

## 3. Required baseline tooling (do not modernize)

| Item | Version |
|---|---|
| Flutter | 3.35.3 (stable) |
| Dart | 3.9.2 |
| JDK | 17 (Flutter must be pointed at it with `flutter config --jdk-dir`) |
| Gradle | 8.13 |
| Android Gradle Plugin | 8.11.2 |
| Kotlin | 2.1.0 |
| compileSdk / targetSdk | 36 |
| NDK | 27.0.12077973 |

Upgrading any of these is a separate, explicitly approved issue.

Known environment trap: Android Studio's bundled JBR is JDK 25, which breaks the
Android build (`IllegalArgumentException: 25.0.3` from the Kotlin compiler). Use
JDK 17 for command-line builds.

## 4. Standard bootstrap and verification

```bash
flutter pub get

cd flutter_plugin/flutter_plugin
flutter pub get
cd ../..

flutter analyze
flutter build apk --debug --flavor staging --dart-define-from-file=config/build/staging.json
```

- **Accepted analyzer baseline: 0 errors.** Existing warnings/info are technical
  debt. Do **not** mass-clean them during unrelated work.
- The nested plugin's `pubspec.lock` and `.dart_tool/` are ignored by Git; never
  commit them.
- **Every build needs an explicit environment and the matching flavor**:
  `--flavor staging --dart-define-from-file=config/build/staging.json` (or
  `--flavor production ... production.json`) on `flutter run`, `flutter build ...` and IDE
  run configurations. Without them, or with a flavor that does not match the file, the
  build fails; there is no default (see section 10 and `docs/BUILD_CONFIGURATION.md`).
  `flutter pub get` and `flutter analyze` need none. Use the staging pair with
  disposable test accounts.

## 5. Security boundaries — what must never reach Claude or Git

Never ask for, read, print, paste, store or commit:

- production passwords, JWTs / bearer tokens, API credentials
- mnemonics, entropy, seeds, private keys, XPRIVs
- DLC signing secrets and nonce/adaptor secret material
- Android `.jks`/keystore files or `key.properties`; Apple private signing keys
  or certificates
- Firebase service-account credentials, private SSH keys, production `.env`
  secrets
- sensitive production user data

Rules:

- Test secrets must be **disposable staging/test credentials** for a test account
  only — never a mainnet wallet or any wallet holding value.
- Prefer that the human types secrets into the app UI themselves. Anything typed
  through `adb shell input text` appears in the shell command and in the device's
  `adbd` log, so do not route mnemonics or real credentials through `adb`,
  scripts, temp files or command output.
- Never log secrets. The never-log list and the HTTPS-only transport rule are in
  `docs/SECURITY_BOUNDARY.md`; do not weaken either, in any build mode.

## 6. Sensitive code — investigate first, never "clean up"

Read the code path and report before changing anything in:

- mnemonic / wallet creation, recovery and persistence (`StorageService`,
  `lib/src/ui/screens/createWallet/`, `mnemonic_screen.dart`)
- authentication, JWT handling and token refresh (`DataService`, `ApiService`)
- manual signing (`SignTransactionScreen.dart`) and automatic signing
  (`lib/services/auto_signing_service.dart`)
- FFI boundaries and the Rust `dlcplazacryptlib` / `dlc_wallet` plugin
- environment selection (`BuildConfig` and the `AppController` constants it feeds)
- release signing
- backend transport security (`DataService` HTTPS guard,
  `android:usesCleartextTraffic="false"`)

Do not alter wallet-derivation, signing or cryptographic semantics as collateral
cleanup, and do not make cryptographic design decisions.

## 7. Dependency policy

- No dependency or toolchain modernization during unrelated work.
- Never run broad `flutter pub upgrade`.
- Do not delete or regenerate lockfiles casually. The **root `pubspec.lock` is
  part of the reproducibility contract** and is committed.
- Dependency changes need an issue-scoped justification and the full
  verification in section 4. Example: `workmanager_platform_interface` is pinned
  to `>=0.9.3 <0.9.4` (issue #42) because 0.9.4 breaks `workmanager_apple` 0.9.4,
  the newest version compatible with Flutter 3.35.

## 8. Agent workflow

```text
inspect
-> report the runtime / code path
-> propose a plan
-> human approval where architecture or security is involved
-> implement the smallest coherent change
-> run verification (section 4, plus runtime checks where relevant)
-> inspect the Git diff
-> signed commit
-> PR to the integration branch
```

- Commits must be signed and end with the `Co-Authored-By` trailer for Claude.
  Message style: `fix: <summary> (#<N>)`.
- Keep changes issue-scoped. No unrelated cleanup, renames or reformatting.
- Do not commit until the human has reviewed the diff.

Claude may help with Git operations but must **not**, without explicit human
authorization:

- force push, or delete important branches
- alter release keys or signing configuration
- deploy to production
- change security architecture
- make cryptographic design decisions
- weaken transport or security constraints
- treat itself as release authority (the human owner decides what ships)

## 9. Permission model

- Conservative permissions are the normal mode. Approve commands individually.
- `--dangerously-skip-permissions` is **not** part of the project workflow.
- Destructive Git operations, anything involving credentials, production
  systems, release signing, or security-sensitive changes require explicit
  human approval at the time.
- No project-level Claude settings file is committed yet.

## 10. Known cautions (established facts only)

- The Firebase branch is reference-only; the repository has no Firebase
  dependency today.
- The cryptlib branches are research/reference. Current cryptlib compatibility
  must not be inferred from branch names.
- The application version source is the `version:` field in `pubspec.yaml`, not
  historical branch names.
- **Environment selection is explicit and fail-closed**: `BuildConfig`
  (`lib/config/build_config.dart`) is the only source of `USE_TESTNET`,
  `NETWORK_ENVIRONMENT` and `API_BASE_URL` (the `AppController` constants are
  aliases of it). It is selected per build with
  `--dart-define-from-file=config/build/staging.json` (`true`, `"signet"`,
  `https://staging.purabitcoin.com/app`) or `production.json` (`false`,
  `"bitcoin"`, `https://cadenabitcoin.com/app`). A missing, incomplete or
  contradictory configuration fails the build, including release/AOT. Never edit the
  `AppController` constants to switch environments, never add a default or a
  fallback to `build_config.dart`, and treat changes to it as sensitive (section 6).
  The files contain no secrets and are meant to be committed. See
  `docs/BUILD_CONFIGURATION.md`.
- **Two flavors, `staging` and `production`, select only the application identity**:
  Android `com.cadenabitcoin.mobile.signer.staging` / `com.cadenabitcoin.mobile.signer` (the
  production ID is the package published on Google Play; the Kotlin namespace stays
  `com.app.cadenabitcoin`), iOS the separate bundle IDs `com.app.cadenabitcoin.staging` /
  `com.app.cadenabitcoin`, launcher names "Cadena Signer STAGING" / "Cadena Bitcoin". Staging and production
  install side by side. The build fails unless the flavor equals `APP_ENV` of the
  configuration file (`BuildConfig`, `FLUTTER_APP_FLAVOR`); do not add a default flavor
  (`default-flavor`) or a second environment selector. `tool/verify_version.sh` checks the
  wiring, `tool/verify_artifact.sh` checks built artifacts, and the `build-variants`
  workflow compiles the five variants without signing credentials; it
  can be run for all of them or for one chosen variant, and a push (merge) to `staging`
  runs the two staging variants and to `production` the three production variants
  (`tool/plan_build_variants.sh` decides what a trigger requires; `docs/RELEASE_TRIGGERS.md`).
  Every build also writes a JSON build manifest (source commit, run, version, toolchain,
  artifact SHA-256, signing status; `tool/build_manifest.py`), and
  `config/release/published_versions.json` records the version codes already published:
  never reuse one (`docs/RELEASE_VERSIONING.md`). The application version changes only by a
  reviewed edit of `pubspec.yaml`; no workflow may write or override it.
- Android release signing is **explicit** (Issue #72, `docs/ANDROID_RELEASE.md`): without
  `CADENA_SIGNING` the release build type is debug-signed (the credential-free CI validation;
  never distributable); `CADENA_SIGNING=release` signs with a keystore supplied from outside
  the repository and fails, with no fallback to the debug key, when anything is missing or the
  certificate is not the expected one, and signs the production flavor only (any release task of
  another flavor fails the build). Never set `CADENA_SIGNING`, never create or read a
  keystore, and never put a signing credential in the repository, a log or a chat. The Google
  Play app-signing key is held by Google and stays unchanged; the upload key is Cadena-controlled
  and held by the CFO. `tool/release_android.sh` is the local procedure, run by the key holder.
- Native binary provenance and the release process for the committed `.so`/`.a`
  files are **not documented** (separate technical debt).
- `.gitignore` lists `/android/app`, although files under it are tracked; a new
  file there needs `git add -f`.
