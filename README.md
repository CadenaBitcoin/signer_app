# signer flutter version 3.35.3

signer_app

Requirements

Flutter version: 3.35.3

Dart SDK bundled with that Flutter version

Android Studio / Xcode for platform specific builds

Running the Project

Clone the repository

Run flutter pub get inside the main app

Important: Also run flutter pub get inside the flutter_plugin folder before running the app

Start application: flutter run --flavor staging --dart-define-from-file=config/build/staging.json (every build needs an explicit environment and the matching flavor, staging or production; see [docs/BUILD_CONFIGURATION.md](docs/BUILD_CONFIGURATION.md))

## Contributing and governance

- [CONTRIBUTING.md](CONTRIBUTING.md) — how to propose changes
- [GOVERNANCE.md](GOVERNANCE.md) — branch model, authority levels, release and versioning policy
- [docs/RELEASE_POLICY.md](docs/RELEASE_POLICY.md) — release branches, the five signed artifacts, application identity, versioning (draft); with [signing architecture](docs/RELEASE_SIGNING_ARCHITECTURE.md), [implementation plan](docs/RELEASE_IMPLEMENTATION_PLAN.md) and the [release-branch build triggers](docs/RELEASE_TRIGGERS.md)
- [SECURITY.md](SECURITY.md) — reporting vulnerabilities privately

## Security

See [docs/SECURITY_BOUNDARY.md](docs/SECURITY_BOUNDARY.md) for the backend transport (HTTPS-only) and runtime-logging rules.

## CI

See [docs/ANDROID_CI.md](docs/ANDROID_CI.md) for the Android CI validation build and [docs/IOS_CI.md](docs/IOS_CI.md) for the iOS one (neither is for distribution).

## Development with Claude Code

Project rules for AI-assisted development are in [CLAUDE.md](CLAUDE.md); the workflow is described in [docs/AI_DEVELOPMENT_WORKFLOW.md](docs/AI_DEVELOPMENT_WORKFLOW.md).
