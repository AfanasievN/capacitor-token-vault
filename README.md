# capacitor-token-vault

[![npm version](https://img.shields.io/npm/v/capacitor-token-vault.svg)](https://www.npmjs.com/package/capacitor-token-vault)
[![CI](https://github.com/AfanasievN/capacitor-token-vault/actions/workflows/ci.yml/badge.svg)](https://github.com/AfanasievN/capacitor-token-vault/actions/workflows/ci.yml)
[![CodeQL](https://github.com/AfanasievN/capacitor-token-vault/actions/workflows/codeql.yml/badge.svg)](https://github.com/AfanasievN/capacitor-token-vault/actions/workflows/codeql.yml)
[![runtime dependencies](https://img.shields.io/badge/runtime%20dependencies-0-brightgreen)](#zero-dependencies-and-why-it-matters)
[![Capacitor](https://img.shields.io/badge/Capacitor-8%2B-119EFF)](https://capacitorjs.com)
[![platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20Android%20%7C%20Web-lightgrey)](#what-each-platform-actually-does)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Keeps an auth token in the safest place each platform offers** — iOS Keychain, Android Keystore,
`sessionStorage` on the web — behind five methods and **zero runtime dependencies**.

[Quick start](#quick-start) · [What each platform does](#what-each-platform-actually-does) ·
[Threat model](#threat-model) · [Design notes](docs/DESIGN.md) · [Contributing](CONTRIBUTING.md)

```ts
await TokenVault.setToken({value: refreshToken});
const {value} = await TokenVault.getToken();   // string | null
await TokenVault.clear();                      // logout
```

## Why another storage plugin

Storing a refresh token is the most common Capacitor security question, and the usual answers do not
hold up:

| Common choice | What goes wrong |
| --- | --- |
| `localStorage` / `sessionStorage` in a native app | a plaintext file inside the app sandbox — readable on a rooted or jailbroken device |
| `@capacitor/preferences` | plain `UserDefaults` / `SharedPreferences`; it is not encrypted storage and does not claim to be |
| generic secure-storage plugins | usually no control over **Keychain accessibility** or **iCloud sync**, so tokens can travel into backups and onto other devices |
| `androidx.security` `EncryptedSharedPreferences` | deprecated since `security-crypto:1.1.0-alpha07` (main-thread performance, OEM keyset corruption) |

This plugin does one thing with a **fixed, documented security posture** that a caller cannot
accidentally weaken.

## Quick start

```bash
npm install capacitor-token-vault
npx cap sync
```

Two install steps a plugin cannot do for you:

**1. Keep the native build lean.** Capacitor links every plugin it finds; pin the allowlist:

```ts
// capacitor.config.ts
const config: CapacitorConfig = {
  includePlugins: ["capacitor-token-vault"],
};
```

**2. Exclude the Android store from cloud backups**, so the encrypted blob does not travel to other
devices (the key never leaves the device, so it could only fail to decrypt — but shipping it is
pointless):

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<application android:allowBackup="false" ...>
```

Want backups on? Use a `dataExtractionRules` exclusion for `token_vault.xml` instead. **iOS needs
nothing** — `WhenUnlockedThisDeviceOnly` items are never included in a backup.

## Usage

```ts
import {TokenVault} from "capacitor-token-vault";

// write / read / delete the default slot ("refresh")
await TokenVault.setToken({value: refreshToken});
const {value} = await TokenVault.getToken();     // null when empty — not an error
await TokenVault.removeToken();

// more than one secret? named slots
await TokenVault.setToken({value: deviceToken, name: "device"});

// logout: every slot this plugin owns
await TokenVault.clear();

// branch on what you actually got, not on the platform name
const caps = await TokenVault.getCapabilities();
if (!caps.persistent) {
  // web tab or private mode: do not promise "stay signed in"
}
```

Slot names match `^[a-zA-Z0-9._-]{1,64}$`. Rejections carry `code`:
`UNAVAILABLE` | `INVALID_ARGUMENT` | `STORAGE_FAILURE` — and never contain the token value.

### API

| Method | Result |
| --- | --- |
| `getCapabilities()` | `{backend, secure, persistent, hardwareBacked}` |
| `setToken({value, name?})` | writes or overwrites a slot |
| `getToken({name?})` | `{value: string \| null}` |
| `removeToken({name?})` | idempotent delete |
| `clear()` | removes every slot owned by this plugin |

## What each platform actually does

| Platform | Where the token goes | Fixed parameters |
| --- | --- | --- |
| **iOS 14+** | Keychain, `kSecClassGenericPassword`, service `<bundleId>.token-vault` | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (also what keeps it out of backups), `kSecAttrSynchronizable = false`, `kSecUseDataProtectionKeychain = true` |
| **Android 6+ (API 23)** | AES-256-GCM ciphertext in `SharedPreferences("token_vault", MODE_PRIVATE)` | key `capacitor.token-vault.v1` generated in `AndroidKeyStore`, GCM, no padding, 256-bit, randomized IV per write, no user-auth requirement |
| **Web / PWA** | `sessionStorage` under `token-vault.`, in-memory when storage is blocked | reports `secure: false`; `localStorage` is never used |

Why these choices, in short — the long version is in [docs/DESIGN.md](docs/DESIGN.md):

- **`WhenUnlockedThisDeviceOnly`** is the only Keychain class that both requires an unlocked device
  *and* is excluded from backup/restore onto another device. Cost: background code cannot read the
  token while the device is locked — fine, since a refresh follows app use.
- **Keystore directly instead of `EncryptedSharedPreferences`** — see the table above; ~60 lines with
  no library lifecycle risk.
- **A versioned key alias** so a future parameter change becomes a new alias plus a documented
  migration, not silent decryption failures on real installs.
- **`sessionStorage` on the web rather than an `Unavailable` error**, so consumers get working
  behavior everywhere and the ones who care read `capabilities.secure`.
- **A corrupt or undecryptable slot reads as "absent"** on every platform: broken storage must never
  lock a user out of signing in again.

## Threat model

**Protects against:** another app or a shell on a rooted/jailbroken device reading the token off
disk; the token surviving in a device backup and being restored elsewhere; iCloud Keychain sync
carrying it to another device.

**Does not protect against:** code execution inside your app — XSS in the WebView or a malicious
dependency can call `getToken()` exactly like your code does. Strict CSP and supply-chain hygiene are
the controls there; storage choice only limits theft *at rest*. Full statement: [SECURITY.md](SECURITY.md).

No biometric gate in v1: `kSecAccessControl` / `setUserAuthenticationRequired` change the failure
surface (enrollment invalidation, cancel flows) and belong to a session-policy feature rather than to
storage. The design leaves room for an opt-in `requireUserPresence` without changing the stored format.

## Zero dependencies, and why it matters

`npm ls --omit=dev --all` prints an empty tree, and [CI asserts it](.github/workflows/ci.yml) on
every push. Concretely: `@capacitor/core` is a **peer** dependency (declaring it as a dependency is
what pulls a second Capacitor into a consumer's tree); Android compiles against platform Keystore
APIs only; iOS depends on Capacitor alone; the build is plain `tsc`, so there is no bundler chain
either. For a package that holds credentials, every transitive dependency is someone else's write
access to your token store.

## Development

```bash
npm install
npm run verify        # typecheck + web unit tests + build
swift test            # iOS: real Keychain, asserts the item attributes
```

Android instrumented tests need a device or emulator and a host app
(`./gradlew connectedAndroidTest`) — `AndroidKeyStore` has no JVM implementation, so a Robolectric
test would prove nothing about the part that matters.

The native suites are the security tests: on iOS they assert the accessibility and sync attributes;
on Android that a second instance decrypts what the first wrote, that ciphertext differs per write
(randomized IV), and that the plaintext never appears in the stored value.

Contributions welcome — [CONTRIBUTING.md](CONTRIBUTING.md) explains the one rule that shapes every
review: this plugin stays small.

## License

MIT © [AfanasievN](https://github.com/AfanasievN)
