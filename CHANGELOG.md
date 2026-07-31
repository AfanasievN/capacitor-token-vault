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
