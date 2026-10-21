# Apple account questionnaire (template)

For Issue #71 ([IOS_SIGNING.md](IOS_SIGNING.md)). It collects **account metadata and
confirmations only**, so that iOS signing and TestFlight delivery can be designed without
guessing. This file is a **template**: it stays blank in the repository.

**Where answers go.** Not here, and not in any issue, pull request or chat. Answers go to the
private custody register of the Cadena organization (outside the public repository), which
records holders, fingerprints, dates and decisions, and no secret values. The repository
learns only the resulting decisions, written as documentation by a reviewed pull request.

## What must never be sent

Do not send, paste, attach or describe the content of: private keys, `.p12` or `.pfx` files,
certificates that contain a private key, `.p8` API keys, provisioning-profile files,
passwords, one-time codes, session cookies, tokens, recovery keys. Screenshots are welcome if
they show **no** key material or secret. If a question seems to need any of these, answer yes
or no instead and stop.

Answer each question with a value, "unknown", or "not applicable". "Unknown" is a useful answer.

---

## Part A. Initial questionnaire (priority)

Twelve questions. The answers decide what can be built and in what order.

### A1. Account identity and authority
1. Is the Apple Developer Program membership an **Organization** or an **Individual**
   enrollment? Under which legal entity?
2. Is Team ID `D65458CPDP` (committed in the Xcode project) the team that owns the Cadena
   apps?
3. Who is the Account Holder, and who holds the Admin role in App Store Connect Users and
   Access? Can a second, independent Admin be added?
4. When does the membership renew, who pays and tracks it, and are all agreements accepted
   in the Developer portal and in App Store Connect?

### A2. Existing apps and bundle identifiers
5. Does an iOS app record for Cadena Signer exist in App Store Connect? For each record: name,
   SKU, **exact bundle ID**, and status.
6. If an app is live: current App Store version, and the **highest build number ever
   uploaded** (including builds never released).
7. Is the live app's bundle ID `com.app.cadenabitcoin`? (The published **Android** package is
   `com.cadenabitcoin.mobile.signer`, so please do not assume the iOS ID matches the
   repository.)

### A3. Registration status
8. Is `com.app.cadenabitcoin` registered as an App ID in this team, and is
   `com.app.cadenabitcoin.staging` registered? Is a separate staging record named
   "Cadena Signer STAGING" acceptable?

### A4. Signing assets
9. Which Apple Distribution certificates exist (name, expiry, creator) and how many certificate
   slots are used? Which App Store provisioning profiles exist for which bundle ID, and when do
   they expire?
10. Who is the custodian of each certificate's private key (a role is enough), and where
    are the backups kept? Is a separate certificate for staging and production acceptable?

### A5. Available permissions
11. Can you create a **dedicated service user** restricted to the staging app only, and can
    that user generate an individual API key (the "Generate Individual API Keys" permission)?
    In the live Roles matrix (developer.apple.com/support/roles), which roles show **Upload
    builds**, and which show **Submit apps**?

### A6. Compliance
12. What is the organization's answer to Apple's export-compliance question for an app that
    signs with secp256k1 and uses HTTPS, and has legal counsel reviewed it?

---

## Part B. Follow-up topics (after Part A)

Same rules. Ask only what Part A leaves open.

### B1. Account and roles
- Who can create and revoke certificates, profiles, App IDs and App Store Connect users?
- Is "Access to all apps" disabled for the roles that will be used by the pipeline?
- Is there an Apple Business Manager, DUNS or other constraint that limits adding users?

### B2. App Store Connect records
- Staging record: name, SKU, primary language, category, privacy policy URL, support URL.
- Does the production record have a privacy policy URL, support URL and marketing URL?
- App Privacy answers: data types collected and linked, tracking. The app uses camera,
  microphone, location and photo library for KYC through the Sumsub and Fingerprint Pro SDKs.

### B3. Capabilities and entitlements
- Which capabilities are enabled on the production App ID (push notifications, background
  modes, associated domains, others)?
- Does the app depend on server-sent push notifications, or only on local notifications and
  background tasks?

### B4. API credential handling
- Which person will generate each API key, and through which secure channel will it reach the
  holders of the GitHub environment secrets? (A role and a channel, never the key.)
- Is a key generated for the staging service user kept separate from any production key?
- How will keys be revoked and replaced, and who is told?

### B5. TestFlight (internal only)
- Roles and count of the intended internal testers (internal TestFlight is limited to team
  members); do they already have App Store Connect users?
- Who administers the internal tester group, and who may add a processed build to it?
- Is automatic distribution of new builds switched **off** for the group?

### B6. Operations
- Who is notified of failed processing, expiring certificates and expiring profiles?
- Who can expire a superseded TestFlight build?

---

## Record of answers (kept privately)

| Part | Answered by (role) | Date | Stored in the custody register as |
|---|---|---|---|
| A | | | |
| B | | | |
