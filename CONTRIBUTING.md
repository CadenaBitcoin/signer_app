# Contributing

Thank you for helping improve Cadena Bitcoin Signer. This is a signing application:
correctness and security matter more than speed. Read [GOVERNANCE.md](GOVERNANCE.md)
first; it defines who can merge, promote, release and sign. Contributing does not
grant any of those.

## Ways to contribute

- **Public contributors:** fork the repository, create a branch in your fork, and open
  a pull request. You do not need any special permission, and you receive no write,
  merge, release, signing or administrative access by contributing.
- **Authorized collaborators / maintainers:** people explicitly invited by the
  repository owner may work on issue branches directly in the official repository.
  Because the repository belongs to a personal GitHub account, collaborator access is
  granted only to people trusted with merge-level authority. Merge authority is held
  only by the authorized maintainers named in [GOVERNANCE.md](GOVERNANCE.md).

Do not report security vulnerabilities in public issues or pull requests; see
[SECURITY.md](SECURITY.md).

## Before you start

1. Open or find an issue describing the problem. Agree on scope with a maintainer
   for anything non-trivial, and always for changes touching wallet, authentication,
   signing, FFI/native code, environment selection, release signing or transport
   security. These areas require investigation and human approval before changes.
2. Branch from the current integration branch:
   - `development`, once the branch migration described in
     [GOVERNANCE.md](GOVERNANCE.md) is complete;
   - until then, the current `staging`.
3. Name the branch `issue/<number>-<short-name>`.

Historical or reference branches are not merge targets or starting points.

## Making a change

- Keep the change small and tied to the issue. No unrelated cleanup, renames,
  reformatting or lint sweeps.
- Do not modernize dependencies or the toolchain in unrelated work. Do not run broad
  `flutter pub upgrade`. Dependency or toolchain changes need their own issue and the
  full verification below.
- Never commit secrets, real credentials, mnemonics, keys, keystores, `.env` files or
  production data, and never put them in issues, logs or screenshots. Use disposable
  staging/test credentials only. Do not add logging that exposes sensitive values.
- Do not change wallet derivation, signing or cryptographic behavior as collateral
  cleanup.

## Verification

The accepted baseline (see [CLAUDE.md](CLAUDE.md) for the pinned toolchain versions):

```bash
flutter pub get

cd flutter_plugin/flutter_plugin
flutter pub get
cd ../..

flutter analyze
flutter build apk --debug
```

`flutter analyze` must report **0 errors**. Existing warnings are known technical debt
and must not be mass-cleaned in unrelated pull requests. Run any other relevant checks
and say what you could not test.

## Pull requests

Use the pull request template. A pull request needs:

- **Issue linkage:** write `Implements #N`. Do **not** use automatic closing keywords
  such as `fixes #N`, `closes #N` or `resolves #N`; a maintainer closes the issue
  explicitly (see [GOVERNANCE.md](GOVERNANCE.md)).
- **Scope and rationale:** what changed and why, and what is deliberately not included.
- **Verification:** what you ran and the results, including anything not exercised.
- **Security impact:** whether the change touches secrets, logging, transport, wallet,
  authentication, signing or native code, and how you checked.
- **Dependency/toolchain changes:** none, or each one with its justification.
- **Human review before merge.** Merge is performed only by an authorized maintainer.
  Review approval is not merge, promotion, release or signing authority.

Commit messages follow `type: summary` (for example `fix: ...`, `docs: ...`,
`chore: ...`). Maintainers may require signed commits.

### AI-assisted changes

AI-assisted or AI-generated changes follow exactly the same contribution, review,
security and merge requirements as human-authored changes. The submitter remains
responsible for the proposed change: understand it, verify it, and keep secrets out of
AI tools. Project-specific rules for AI tools are in [CLAUDE.md](CLAUDE.md).

## License

By submitting a contribution you agree that it is provided under the repository's
[MIT License](LICENSE).

## Conduct

Be respectful and constructive. Maintainers may close issues or pull requests that are
off-topic, unsafe or abusive.
