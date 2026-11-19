# nm -u fixtures from the Xcode 26.3 diagnostics run

Verbatim `nm -u` output (`nm` = llvm-nm, "compatible with GNU nm") of five frameworks of the unsigned production
build `1.0.4+1000035`, taken from the evidence artifact of GitHub Actions run 44619876867 (workflow "iOS release
diagnostics", macos-15 image 20261118.0550.1, Xcode 26.3 17C529), directory `preflight/nm-u/`. Their SHA-256 sums
equal those in that artifact's `SHA256SUMS.txt`; `tool/test_required_reason_scan.sh` checks that. Symbol names only:
no token, credential, path or personal data.

This layout has one bare symbol name per line (`_stat`), with no `U` column. It is what the first scan pattern
(`' _(stat|...)$'`, which needed a space before the name) could not read. Do not edit these files.
