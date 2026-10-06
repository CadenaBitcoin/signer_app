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
  integration) → `staging` (Signet promotion) → `production` (planned Mainnet
  release branch). Promotion is forward only; no application logic is developed
  independently on `staging` or `production`.
- `development` is the **active integration and GitHub default branch**. `staging`
  is a protected promotion branch. `main` is legacy and is not an integration
  target. `production` has not yet been created because release provenance must be
  established first.
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
flutter build apk --debug
```

- **Accepted analyzer baseline: 0 errors.** Existing warnings/info are technical
  debt. Do **not** mass-clean them during unrelated work.
- The nested plugin's `pubspec.lock` and `.dart_tool/` are ignored by Git; never
  commit them.
- A debug build compiles whatever environment constants are in
  `lib/src/ui/controllers/appController.dart` (see section 10).

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
- environment selection (`AppController` constants)
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
- **Environment selection is manual**: `USE_TESTNET`, `NETWORK_ENVIRONMENT` and
  `API_BASE_URL` are source constants in `appController.dart`. Production is
  `https://cadenabitcoin.com/app` (`false`, `"bitcoin"`); the verified staging
  setup is `true`, `"signet"`, `https://staging.purabitcoin.com/app`. Switching is
  for local testing only: **never commit a staging configuration**, and restore the
  committed production values afterwards. This area still needs deliberate
  treatment.
- The release build currently uses the **debug signing config**
  (`android/app/build.gradle.kts`). An official release-signing procedure is **not
  yet established**.
- Native binary provenance and the release process for the committed `.so`/`.a`
  files are **not documented** (separate technical debt).
- `.gitignore` lists `/android/app`, although files under it are tracked; a new
  file there needs `git add -f`.
