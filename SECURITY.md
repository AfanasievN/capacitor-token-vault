# Security policy

## Reporting a vulnerability

Please report security issues **privately** through GitHub's private vulnerability reporting
(Security → Report a vulnerability on this repository). Do not open a public issue for a
vulnerability, and please do not include real tokens in a report.

Useful in a report: platform and OS version, plugin version, what an attacker can reach, and a
minimal reproduction. First response within a week; if a fix is warranted it ships as a patch
release with the advisory published alongside it.

## Supported versions

The latest minor release receives fixes. Until 1.0 there are no backports to earlier minors.

## What this plugin does and does not defend against

**In scope** — the reason the plugin exists:

- another app, or a shell on a rooted/jailbroken device, reading the token off disk;
- the token surviving in a device backup and being restored onto another device;
- iCloud Keychain sync carrying the token to another device.

**Out of scope**, and no configuration changes this:

- **Code execution inside the host app.** XSS in the WebView, a malicious npm dependency or a
  tampered build can call `getToken()` exactly like your own code. Strict CSP and supply-chain
  hygiene are the controls; storage choice only limits theft *at rest*.
- **A compromised OS.** If the platform keystore is defeated, so is this plugin.
- **The web target.** No browser has a secure store. The plugin reports
  `capabilities.secure === false` on the web instead of implying protection it cannot provide, and it
  never uses `localStorage`.
- **Token lifetime and revocation.** Rotation, reuse detection and expiry are server-side concerns.

If you find a case where the plugin's *own* behavior weakens one of the in-scope guarantees — a
wrong Keychain attribute, a reused IV, a plaintext write, a secret in an error message — that is a
vulnerability in this project and the report is very welcome.
