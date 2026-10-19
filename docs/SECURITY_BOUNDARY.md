# Signer App — Transport and Runtime-Logging Security Boundary

Establishes the minimum baseline from issue #37. It describes behavior as implemented, not future plans.

## 1. Backend transport

| Environment | Endpoint | Status | Requirement |
|---|---|---|---|
| Production | `https://cadenabitcoin.com/app` | CONFIRMED | Explicit HTTPS |
| Staging | `https://staging.purabitcoin.com/app` | CONFIRMED | Explicit HTTPS; used with `USE_TESTNET = true` and `NETWORK_ENVIRONMENT = "signet"` |

Basis for the staging classification: the repository has documented this endpoint as the staging configuration since the initial import (always paired with `USE_TESTNET = true`), the project owner confirmed it as the DLCPlaza staging backend, and it was exercised at runtime on 2026-10-06 (login, profile, session restoration and DLC API calls over HTTPS, Signet build). It had returned HTTP 502 on 2026-10-05, before the server was brought back up. Any other staging backend used by the Signer MUST also use HTTPS.

Infrastructure note (does not affect the Signer): the staging server also answers on plain HTTP (port 80) without redirecting. The Signer never selects or falls back to it.

Enforcement in the app:
- `AppController.API_BASE_URL` is an explicit `https://` URL (`lib/src/ui/controllers/appController.dart`).
- `DataService` (the only backend HTTP path) refuses any request whose base URL scheme is not `https` and does not fall back to another scheme. The refusal is returned as a synthetic response with `statusCode == DataService.insecureTransportStatus` (-1), distinct from real HTTP statuses, from a plain network failure (null response) and from 401 auth failures (no auth-failure counters are touched).
- Android: `android:usesCleartextTraffic="false"` is set on `<application>`; no Network Security Config exists. iOS: default App Transport Security, no exceptions.
- Certificate pinning is not part of this baseline.

Observed redirect behavior (production probed 2026-10-05, staging probed 2026-10-06; no credentials):
- Old configuration: `http://cadenabitcoin.com/app` -> 301 -> `http://cadenabitcoin.com/app/`. The redirect stayed on cleartext HTTP, so the old configuration gave no transport confidentiality for authenticated traffic.
- Current configuration: `https://cadenabitcoin.com/app` -> 301 -> `https://cadenabitcoin.com/app/`. No HTTPS -> HTTP downgrade observed.
- Staging: `https://staging.purabitcoin.com/app` -> 301 -> `https://staging.purabitcoin.com/app/`, no downgrade.
- The app does not rely on redirects for security. Infrastructure behavior may change and should be re-verified.

## 2. Runtime logging

Never logged (any build mode, regardless of logging API):
- passwords; JWTs / bearer tokens / `Authorization` headers
- mnemonics, entropy, seeds, private keys, XPRIV, cryptographic secret/nonce material
- authentication response payloads, request bodies, whole user/wallet/secure-storage records
- raw exception/response objects that may embed any of the above (log `runtimeType`, status code, endpoint instead)

Minimized: emails, addresses, XPUBs, signature values, QR contents. Their values are not logged; counts, statuses and state transitions are.

Allowed diagnostics: operation names, success/failure, HTTP status codes, non-sensitive state transitions, error category, DLC identifiers.

## 3. Trust boundary

```
Signer App --(HTTPS only)--> DLCPlaza backend
App secret state (password, JWT, mnemonic, keys) --X--> runtime logs
```

## 4. Verification status

Runtime tests used an Android emulator against staging only (Signet build) with a dedicated test account; no production backend or production state was used.

| Property | Status | Evidence |
|---|---|---|
| Production HTTPS configuration | Statically verified | `API_BASE_URL` is `https://cadenabitcoin.com/app`; HTTPS guard; cleartext disabled in manifest; redirect probe shows no downgrade |
| Staging HTTPS configuration | Verified at runtime | Every backend URL logged by the app was `https://staging.purabitcoin.com/app/...`; calls returned 200 |
| HTTP refusal | Verified at runtime | Build with an `http://` base URL: all calls refused locally (status -1), no URL or request logged |
| Password, JWT/bearer, Authorization not logged | Verified at runtime | Searches of app-generated logcat over login, restoration and recovery flows: no hits |
| Mnemonic, seed, entropy, private key/XPRIV not logged | Verified at runtime | Mnemonic recovery and wallet creation flows: no phrase, words, seed or key material in app logs (BIP39-word-run detector and keyword searches) |
| Wallet creation / mnemonic recovery | Verified at runtime | Both flows exercised; recovered wallet matched the staging account's XPUB |
| Login, profile and authenticated API calls | Verified at runtime | `POST /auth/app-token`, `GET /auth/users-app-profile` and DLC poll returned 200 over HTTPS |
| Session restoration | Verified at runtime | Relaunch with stored JWT re-fetched profile and version info |
| 401 / error handling and response-body logging | Verified at runtime (401) / statically (others) | Invalid stored token produced 401 with only endpoint and status logged; other error paths: `${e.runtimeType}`/status-only logging by code review |
| Token refresh | Not safely exercised | Needs an expired-signature 401; log statements reviewed statically (no credentials or payloads logged) |
| Manual and automatic signing | Not safely exercised | The staging test account had no DLCs; signing log statements reviewed statically (no signature, nonce or key values logged) |

## 5. Not covered here
JWT storage location, password-based token refresh design, secure-storage consolidation, certificate pinning, a centralized logging framework, cryptlib secret-memory handling. Many unrelated non-sensitive `print()` calls remain.
