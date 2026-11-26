# Android CI validation build

> **CI VALIDATION — NOT APPROVED FOR PUBLIC DISTRIBUTION.**
> The APK produced by this workflow is an infrastructure check. It is not a
> release, not a staging release candidate and must not be distributed.
>
> **It is built with the STAGING configuration** (`config/build/staging.json`:
> `https://staging.purabitcoin.com/app`, Signet), selected explicitly with
> `--dart-define-from-file`. The branch name does not select the environment, and
> a build without a complete configuration fails (see
> [BUILD_CONFIGURATION.md](BUILD_CONFIGURATION.md)). It is the **`staging` flavor**:
> the separate application `com.cadenabitcoin.mobile.signer.staging` ("Cadena Signer STAGING"),
> which installs next to production. It is still only a CI validation build.
>
> The five-variant compile validation (staging/production APK, production AAB, both iOS
> apps) is the separate `build-variants` workflow, described in
> [BUILD_CONFIGURATION.md](BUILD_CONFIGURATION.md#the-five-build-variants).

Workflow: `.github/workflows/android-ci-validation.yml`

## Trigger

- **Automatic:** every push to `staging`. Because `staging` is protected, a push
  only happens when an authorized maintainer merges a pull request into it
  (see `GOVERNANCE.md`). The workflow adds no authorization logic of its own.
- **Manual, MANUALLY GENERATED:** `workflow_dispatch` (Actions tab → *Android CI validation build* →
  *Run workflow*, workflow from **`development`**) builds the **current tip of `development`** without
  promoting anything: the way to get an installable staging APK whenever it is wanted. It is only offered once
  the workflow file exists on the default branch (`development`). A manual run is refused, before anything is
  built, from any other branch or tag and whenever its commit is no longer the tip of `development` (a re-run
  of an old run included); `tool/plan_build_variants.sh` decides, the same rule as for `build-variants.yml`
  (`docs/RELEASE_TRIGGERS.md`). It is the same build, verification and upload as a promotion; the artifact
  name, the APK file name, the notice and the run summary say **MANUALLY GENERATED** and record the full
  commit SHA. iOS is a different workflow and cannot prevent it. (Earlier, a manual run built any ref; that
  is no longer possible.)

The workflow only runs where its file exists, so it first appears on `staging`
through the normal `development` → `staging` promotion pull request.

## What the build does

On a GitHub-hosted `ubuntu-latest` runner, with token permission
`contents: read` only and **no secrets**:

1. Check out the exact pushed commit.
2. Install JDK 17 (Temurin) and Flutter 3.35.3 (stable).
3. `flutter pub get --enforce-lockfile` (root), then `flutter pub get` in
   `flutter_plugin/flutter_plugin`.
4. `tool/verify_build_config.sh verify`: the configuration test matrix, release/AOT
   compile checks, the analyzer guard and the portability scan. Then record what
   the app itself resolves from `config/build/staging.json` with `--flavor staging`
   and require `APP_ENV=staging`.
5. `flutter analyze --no-fatal-infos --no-fatal-warnings`: only analyzer
   **errors** fail the build. The accepted baseline is 0 errors; the existing
   warnings/info are known technical debt (`CLAUDE.md` section 4).
6. `flutter build apk --debug --flavor staging --dart-define-from-file=config/build/staging.json`.
7. `tool/verify_artifact.sh apk staging ... --signing debug --debug-build`: read the
   application ID, display name, version name/code and signer **from the built APK**
   and compare them with the identity matrix and `pubspec.yaml`.
8. Rename the APK, write a notice file, and upload both as one Actions artifact.

There is deliberately **no `flutter test` step**: the repository has no `test/`
directory. Add it when tests exist.

The same commands run locally (JDK 17) as the bootstrap in `CLAUDE.md` section 4.

These builds are **debug-signed validation builds** (no `CADENA_SIGNING`, no secret). The
production-signed APK and AAB are made by the local release procedure of
[ANDROID_RELEASE.md](ANDROID_RELEASE.md), which no workflow runs.
Every build needs the configuration flag and the matching `--flavor`; see
[BUILD_CONFIGURATION.md](BUILD_CONFIGURATION.md).

## Retrieving the artifact

1. Open the workflow run (Actions tab, or the run link in the notice file).
2. Download the artifact from the **Artifacts** section (a GitHub login is
   required, even for a public repository). Artifacts are kept for **14 days**.
3. Unzip it. It contains the APK and `CI-VALIDATION-NOTICE.txt`. A manual run's artifact, APK and notice
   start with `MANUALLY_GENERATED_` / `MANUALLY GENERATED`.

The artifact and APK are named

```text
CI-VALIDATION-NOT-APPROVED-FOR-PUBLIC-DISTRIBUTION_cadena-signer_v<version>_<environment>_<sha7>_run<run>-<attempt>[_debug.apk]
MANUALLY_GENERATED_CI-VALIDATION-NOT-APPROVED-FOR-PUBLIC-DISTRIBUTION_cadena-signer_v...   (a manual run)
```

where `<version>` is the unchanged `version:` from `pubspec.yaml`, `<environment>` is
the `APP_ENV` the app resolved (`staging`), `<sha7>` is the short commit SHA, and
`<run>-<attempt>` is the GitHub run number and attempt. The notice file records the
full SHA, the run URL, the APK SHA-256, the resolved environment values and the
file that selected them. The run summary and a workflow annotation repeat them.

## Known limitations

- **Staging configuration, compile-time validated only.** CI has not exercised this
  APK against the backend. Use disposable test accounts only, never a wallet
  holding value.
- **The debug APK cannot be checked by inspecting its binary.** A debug build embeds
  both environments' URLs, so the post-build string check
  ([BUILD_CONFIGURATION.md](BUILD_CONFIGURATION.md)) only works on release/AOT
  builds; this workflow's evidence is the verified resolved configuration plus the
  build command.
- **Debug-signed with an ephemeral key.** Each run's key differs, so these APKs
  cannot update one another or any locally built APK. There is no signing
  policy yet.
- **A debug build.** It is the debuggable, unoptimized Flutter debug build (about 200 MB, slower than a release
  build) with the staging configuration; `build-variants` verifies the release/AOT build of the same variant.
  Install it for testing only: uninstall an earlier run's APK first, then allow "install unknown apps".
- **Separate application ID** `com.cadenabitcoin.mobile.signer.staging` (the `staging` flavor:
  the production ID, the package published on Google Play, plus `.staging`), so it installs
  next to the production app. The staging ID is a proposal of
  [RELEASE_POLICY.md](RELEASE_POLICY.md) section 5 and is not registered anywhere.
- **Prebuilt Rust binaries:** the committed `.so` files are used as they are. The
  Rust library is not rebuilt, and its provenance is not verified here.
- **Version is not modified**, and the `versionCode` is not unique per run.
- **Not a release:** no GitHub Release is created and nothing is published.
- Staging builds are specified in [RELEASE_POLICY.md](RELEASE_POLICY.md): a merge
  into `staging` is designed to trigger a separate signed staging pipeline. This
  workflow only produces a short-lived validation artifact; it signs and deploys
  nothing and is not one of the five signed artifacts.
