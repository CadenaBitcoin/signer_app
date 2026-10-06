<!--
Read CONTRIBUTING.md and GOVERNANCE.md. Do not put secrets, real credentials,
mnemonics, keys or production data anywhere in this pull request.
Report security vulnerabilities privately (SECURITY.md), not here.
-->

## Issue

Implements #<!-- issue number. Do not use automatic closing keywords (fixes/closes/resolves). -->

## Scope and rationale

<!-- What changed and why. What is deliberately NOT included. -->

## Verification

<!-- Commands run and results. State anything you could not test. -->

- [ ] `flutter pub get` (root and `flutter_plugin/flutter_plugin`)
- [ ] `flutter analyze` — 0 errors
- [ ] `flutter build apk --debug` (when the change can affect the build)
- [ ] Runtime check, if relevant (describe, using test/staging credentials only)

## Security impact

<!-- Does this touch secrets, logging, backend transport, wallet/mnemonic, authentication,
signing (manual/automatic), FFI/native code, environment selection or release signing?
If yes, explain how it was investigated and checked. If no, say "none". -->

## Dependency / toolchain changes

<!-- "None", or list each change and its justification. No modernization in unrelated work. -->

## Checklist

- [ ] The change is limited to the linked issue's scope
- [ ] No secrets, credentials, keys or production data are included
- [ ] No sensitive values are logged
- [ ] No temporary test or environment configuration is committed
- [ ] AI-assisted changes meet the same requirements as any other change; I reviewed and verified them and am responsible for them
- [ ] I understand merge, promotion, release and signing are reserved to authorized maintainers
