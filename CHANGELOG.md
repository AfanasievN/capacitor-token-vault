# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-03

### Added

- First cut of the plugin: `getCapabilities`, `setToken`, `getToken`, `removeToken`, `clear`.
- iOS: Keychain (`kSecClassGenericPassword`) with `WhenUnlockedThisDeviceOnly`, iCloud sync off,
  and per-slot installation ownership markers.
- Android: AES-256-GCM under an `AndroidKeyStore` key (`capacitor.token-vault.v1`), randomized IV,
  ciphertext in app-private preferences; instrumented tests for cross-instance decryption,
  per-write ciphertext difference and corrupt-slot degradation.
- Web: `sessionStorage` with an in-memory fallback, reporting `secure: false` honestly.
- Zero runtime dependencies; `@capacitor/core` is a peer dependency.
- Integration patterns, AI integration prompts, `llms.txt`, contributor templates, Dependabot, and a
  release checklist.
- CI checks for the npm archive, both JS module formats, Android build/test compilation/lint, iOS
  compilation and ownership tests, dependency review, and multi-language CodeQL analysis.
- Project funding links for GitHub Sponsors, thanks.dev, and TON donations.

### Changed

- `hardwareBacked` is now asked of the Android Keystore (`KeyInfo.securityLevel` /
  `isInsideSecureHardware`) instead of being hardcoded `true`. Emulators and software-Keystore
  devices report `false`; unknown states also report `false`. The iOS value stays
  `true` but the contract now says precisely what it means (data-protection class key derived from the
  device UID, not Secure Enclave residency).
- The package ships **CommonJS alongside ESM**, and relative imports carry explicit `.js` extensions
  so the ESM output loads in Node as well as bundlers. `tsc` now enforces
  this (`moduleResolution: NodeNext`).
- Minimum platforms now match Capacitor 8: iOS 15 and Android API 24.
- Web capabilities report `persistent: false` because neither `sessionStorage` nor the memory fallback
  survives closing the tab.

### Fixed

- iOS bridge errors now use the Capacitor 8 API available through Swift Package Manager.
- iOS installation ownership is tracked per slot, so writing one slot after reinstall cannot expose
  a different slot inherited from an earlier installation.
- Android and Swift CodeQL jobs use explicit supported builds instead of failing autobuilds.
- Android removal and clear operations resolve only after the encrypted preference change is durable.
