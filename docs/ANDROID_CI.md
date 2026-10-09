# Android CI validation build

> **CI VALIDATION — NOT APPROVED FOR PUBLIC DISTRIBUTION.**
> The APK produced by this workflow is an infrastructure check. It is not a
> release, not a staging release candidate and must not be distributed.
>
> **It currently contains the PRODUCTION backend configuration**
> (`https://cadenabitcoin.com/app`, `"bitcoin"`), because environment selection
> is still the manual constants in `lib/src/ui/controllers/appController.dart`.
> The branch name does not select the environment.

Workflow: `.github/workflows/android-ci-validation.yml`

## Trigger

- **Automatic:** every push to `staging`. Because `staging` is protected, a push
  only happens when an authorized maintainer merges a pull request into it
  (see `GOVERNANCE.md`). The workflow adds no authorization logic of its own.
- **Manual:** `workflow_dispatch` (Actions tab → *Android CI validation build* →
  *Run workflow*) builds any chosen ref without promoting anything. It is only
  offered once the workflow file exists on the default branch (`development`).

The workflow only runs where its file exists, so it first appears on `staging`
through the normal `development` → `staging` promotion pull request.

## What the build does

On a GitHub-hosted `ubuntu-latest` runner, with token permission
`contents: read` only and **no secrets**:

1. Check out the exact pushed commit.
2. Install JDK 17 (Temurin) and Flutter 3.35.3 (stable).
3. `flutter pub get --enforce-lockfile` (root), then `flutter pub get` in
   `flutter_plugin/flutter_plugin`.
4. `flutter analyze --no-fatal-infos --no-fatal-warnings`: only analyzer
   **errors** fail the build. The accepted baseline is 0 errors; the existing
   warnings/info are known technical debt (`CLAUDE.md` section 4).
5. `flutter build apk --debug`.
6. Rename the APK, write a notice file, and upload both as one Actions artifact.

There is deliberately **no `flutter test` step**: the repository has no `test/`
directory. Add it when tests exist.

The same commands run locally (JDK 17) as the bootstrap in `CLAUDE.md` section 4.

## Retrieving the artifact

1. Open the workflow run (Actions tab, or the run link in the notice file).
2. Download the artifact from the **Artifacts** section (a GitHub login is
   required, even for a public repository). Artifacts are kept for **14 days**.
3. Unzip it. It contains the APK and `CI-VALIDATION-NOTICE.txt`.

The artifact and APK are named

```text
CI-VALIDATION-NOT-APPROVED-FOR-PUBLIC-DISTRIBUTION_cadena-signer_v<version>_<sha7>_run<run>-<attempt>[_debug.apk]
```

where `<version>` is the unchanged `version:` from `pubspec.yaml`, `<sha7>` is the
short commit SHA, and `<run>-<attempt>` is the GitHub run number and attempt.
The notice file records the full SHA, the run URL, the APK SHA-256 and the
environment constants found in the source. The run summary and a workflow
warning annotation repeat the production-configuration warning.

## Known limitations

- **Production configuration:** see the box above. Do not point this build at
  anything but disposable test accounts, and never use a wallet holding value.
- **Debug-signed with an ephemeral key.** Each run's key differs, so these APKs
  cannot update one another or any locally built APK. There is no signing
  policy yet.
- **Same application ID** (`com.app.cadenabitcoin`) as production, so it cannot
  coexist with an installed production app.
- **Prebuilt Rust binaries:** the committed `.so` files are used as they are. The
  Rust library is not rebuilt, and its provenance is not verified here.
- **Version is not modified**, and the `versionCode` is not unique per run.
- **Not a release:** no GitHub Release is created and nothing is published.
- `GOVERNANCE.md` says a staging *build* is intended to be manually triggered.
  This workflow only produces a short-lived validation artifact; it deploys
  nothing. The wording should be reconciled when staging builds are specified.
