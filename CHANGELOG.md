# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- First cut of the plugin: `getCapabilities`, `setToken`, `getToken`, `removeToken`, `clear`.
- iOS: Keychain (`kSecClassGenericPassword`) with `WhenUnlockedThisDeviceOnly`, iCloud sync off,
  data-protection keychain; XCTest suite asserting those attributes.
- Android: AES-256-GCM under an `AndroidKeyStore` key (`capacitor.token-vault.v1`), randomized IV,
  ciphertext in app-private preferences; instrumented tests for cross-instance decryption,
  per-write ciphertext difference and corrupt-slot degradation.
- Web: `sessionStorage` with an in-memory fallback, reporting `secure: false` honestly.
- Zero runtime dependencies; `@capacitor/core` is a peer dependency.

### Changed
- `hardwareBacked` is now asked of the Android Keystore (`KeyInfo.securityLevel` /
  `isInsideSecureHardware`) instead of being hardcoded `true`. Emulators and software-Keystore
  devices report `false`, which is the truth; unknown states also report `false`. The iOS value stays
  `true` but the contract now says precisely what it means (data-protection class key derived from the
  device UID, not Secure Enclave residency).
- The package ships **CommonJS alongside ESM**, and relative imports carry explicit `.js` extensions
  so the ESM output actually loads in Node — it did not before, only in bundlers. `tsc` now enforces
  this (`moduleResolution: NodeNext`).

### Added
- iOS: a token written by a *previous installation* is no longer returned. iOS keeps Keychain items
  across app deletion, so the plugin stores a marker in `UserDefaults` (which is removed with the app)
  and clears any token that has no matching marker — a fresh install never resumes an inherited
  session. Covered by two new XCTest cases.
- README: compatibility matrix, migration guide from `@capacitor/preferences` and the other
  secure-storage plugins, and a FAQ.

### Added
- `docs/INTEGRATION.md`: three integration shapes (direct, behind your own port/DI, HTTP interceptor
  with single-flight refresh), session restore on boot, SSR/Jest/named-slot notes, and the platform
  setup steps a plugin cannot perform itself.
- `docs/AI.md`: copy-paste prompts for wiring the plugin with an agent, adding refresh-on-401,
  migrating from another plugin, and auditing existing token handling — each stating the rules agents
  usually break (persisting the access token, logging out on transient errors, branching on platform
  instead of capabilities).
- `llms.txt` at the repository root: the whole contract, rules, per-platform behavior and threat model
  in one machine-readable page, shipped in the npm tarball as well.
- README: architecture diagram of the bridge, "How it works", "Integrating into your project".

### Changed
- README FAQ entries are now headings, so each has an anchor and can be linked and extracted; internal
  document links are absolute, which keeps them working when the README is rendered on npm.
