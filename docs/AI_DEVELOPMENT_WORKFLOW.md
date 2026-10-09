# AI-assisted development workflow

How Claude Code is used on this repository. This records the operating model
that was exercised on real work (issue #42 Workmanager build fix, issue #37
secure transport and log hygiene) — not an aspirational process. Policy lives in
`CLAUDE.md`; this file explains the flow and the separation of responsibilities.

## Operating model

```text
technical owner
    ↓
Claude Code
    ↓
local issue branch (from the current integration branch)
    ↓
tests / build / runtime verification
    ↓
human diff review
    ↓
signed commit
    ↓
GitHub PR
    ↓
integration branch (`development`)
```

- The **technical owner** sets scope, approves plans that touch architecture or
  security, reviews the diff, and decides what is merged.
- **Claude Code** investigates, proposes, implements the smallest coherent change
  and verifies it. It is not a release authority.
- **Git and GitHub remain authoritative**: issues define scope, PRs are the only
  way into the shared branches, history is never rewritten on shared branches.

## Four levels — kept separate

| Level | What lives here | Where | Who handles it |
|---|---|---|---|
| **Workstation** | The `claude` program, JDK, Flutter, Android Studio | The machine (outside this repository) | Workstation setup scripts, kept in their own repository |
| **User / auth** | Login to the owner's Claude account, user-level settings | `~/.claude` | The user, interactively (`claude`, then `/login`; check with `claude auth status`) |
| **Project** | Rules, baseline versions, workflow, security boundary | `CLAUDE.md`, `docs/` in this repository | Committed through normal issue PRs |
| **Secret** | Passwords, JWTs, mnemonics, seeds, keys, signing material, production credentials | Never given to Claude, never committed | The human only; test secrets are disposable staging credentials |

A change at one level never silently reaches another: the installer script does
not log in, `CLAUDE.md` contains no credentials, and secrets are typed by the
human into the app, not into prompts, scripts or files.

## Standard sequence for an issue

1. **Start clean**: switch to `development` and `git pull --ff-only`; confirm
   `git status` is clean; create `issue/<N>-<short-name>` from it.
2. **Inspect first**: read the code and trace the real runtime path. Report facts
   before proposing changes.
3. **Plan** and obtain human approval where the change involves architecture or
   security (wallet, auth, signing, FFI, environment, release, transport).
4. **Implement** the smallest coherent change; no unrelated cleanup.
5. **Verify** with the baseline commands in `CLAUDE.md` section 4
   (`flutter analyze` 0 errors, `flutter build apk --debug`) and, where relevant,
   runtime checks on the Android emulator.
6. **Inspect the diff** (`git diff --stat`, `git diff --check`, `git status`);
   confirm no temporary test configuration remains.
7. **Human review**, then a **signed commit** with the Claude `Co-Authored-By`
   trailer.
8. **PR to `development`**, opened by the human unless arranged otherwise.
   Protected-branch approval and merge are performed through the Maintainer-controlled
   GitHub workflow.

## Runtime verification practice

Established while verifying #37:

- Runtime tests use the **staging** backend and a dedicated test account, never
  production. Staging is selected by temporarily editing the environment
  constants in `appController.dart`; that edit is shown as a diff before running,
  is **never committed**, and is reverted (restored from a saved copy) afterwards.
- Secrets that must be typed (mnemonic, real passwords) are entered by the human
  in the emulator window. `adb shell input text` would put them in a command line
  and in `adbd` logs.
- Log hygiene is checked by searching app-generated logcat for the specific
  secret patterns; tooling echoes (`adbd`) and keyboard/system metadata are
  reported separately from application logging.
- Anything that could not be exercised safely (for example signing without a
  staging DLC) is reported as such, with the static evidence — never as verified.

## Permissions

Conservative, per-command approval is the normal mode. Destructive Git
operations, credentials, production systems, release signing and
security-sensitive changes need explicit human approval each time.
`--dangerously-skip-permissions` is not part of this workflow.

## Rebuilding the workstation

Install Claude Code with the workstation setup script `60_claude_code.sh`
(per-user, no sudo, no credentials, pinned to a validated version), authenticate
interactively, clone this repository, and follow `CLAUDE.md` section 4. The JDK
and Flutter versions in `CLAUDE.md` section 3 are part of the baseline.
