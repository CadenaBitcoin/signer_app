# Security policy

Cadena Bitcoin Signer handles Bitcoin signing authority. Please report suspected
vulnerabilities **privately**.

## Reporting a vulnerability

- **Do not** open a public issue, pull request or discussion for a suspected
  vulnerability, and do not include exploit details, secrets or real wallet data
  in any public place.
- Prefer GitHub **Private Vulnerability Reporting** for this repository. Use the
  repository's **Security** page and select **Report a vulnerability** so the report
  remains private to the authorized repository security/administration roles.
- If GitHub Private Vulnerability Reporting cannot be used, email
  **sziller@cadenabitcoin.com** as the fallback private security contact.
- Include a description, affected version or commit, steps to reproduce and the
  impact you expect.
- Never send mnemonics, private keys, passwords, production tokens or real user
  data. Use disposable test material to demonstrate a problem.

This project does not currently publish response-time commitments. Reports will
be assessed by the authorized project maintainers.

## Scope

In scope: the application source in this repository, its backend transport
handling, secret and logging handling, and the committed native crypto library
integration.

The transport and logging rules the project already enforces are described in
[docs/SECURITY_BOUNDARY.md](docs/SECURITY_BOUNDARY.md).

Out of scope here: problems in third-party dependencies (report them upstream),
and the DLCPlaza backend and other services, unless the issue is in how this
application interacts with them.

## Supported versions

Support policy will be defined with the release process.

## Handling secrets found in the repository

If you find a committed secret or sensitive data, report it privately as above
instead of opening an issue.
