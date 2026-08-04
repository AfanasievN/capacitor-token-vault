<h1 align="center">Capacitor Token Vault</h1>

<p align="center">A focused, zero-runtime-dependency vault for refresh tokens in Capacitor 8 applications.</p>

[![npm version](https://img.shields.io/npm/v/capacitor-token-vault?logo=npm&color=CB3837)](https://www.npmjs.com/package/capacitor-token-vault)
[![CI](https://github.com/AfanasievN/capacitor-token-vault/actions/workflows/ci.yml/badge.svg)](https://github.com/AfanasievN/capacitor-token-vault/actions/workflows/ci.yml)
[![CodeQL](https://github.com/AfanasievN/capacitor-token-vault/actions/workflows/codeql.yml/badge.svg)](https://github.com/AfanasievN/capacitor-token-vault/actions/workflows/codeql.yml)
[![runtime dependencies](https://img.shields.io/badge/runtime%20dependencies-0-brightgreen)](#zero-dependencies-and-why-it-matters)
[![Capacitor](https://img.shields.io/badge/Capacitor-8%2B-119EFF)](https://capacitorjs.com)
[![platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20Android%20%7C%20Web-lightgrey)](#what-each-platform-actually-does)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/AfanasievN/capacitor-token-vault/blob/main/LICENSE)

**Where do you keep a refresh token in a Capacitor app?** Not in `localStorage`. This is **secure
storage** scoped to one job: it keeps the token in the safest store each platform offers: **iOS
Keychain**, **Android Keystore**, or `sessionStorage` on the web. The same five-method API has **zero
runtime dependencies**.

[Quick start](#quick-start) · [Integration patterns](https://github.com/AfanasievN/capacitor-token-vault/blob/main/docs/INTEGRATION.md) ·
[AI prompts](https://github.com/AfanasievN/capacitor-token-vault/blob/main/docs/AI.md) · [Compatibility](#compatibility) ·
[What each platform does](#what-each-platform-actually-does) · [Threat model](#threat-model) ·
[FAQ](#faq) · [Design notes](https://github.com/AfanasievN/capacitor-token-vault/blob/main/docs/DESIGN.md) ·
[Support ☕](#support-this-project)

```ts
await TokenVault.setToken({value: refreshToken});
const {value} = await TokenVault.getToken();   // string | null
await TokenVault.clear();                      // logout
```

## Support this project

Free and open source, maintained in spare time — a donation helps fund security updates, fixes,
documentation, and new releases. 🙏 [Sponsor AfanasievN on GitHub](https://github.com/sponsors/AfanasievN),
or donate in **TON**: [![Donate TON](https://img.shields.io/badge/Donate-TON-0098EA)](https://app.tonkeeper.com/transfer/UQAMfkOwBBk_TZyn7LP2o9UgMrNW3GCLs3IJKOVxYBdzr0IK)

<details>
<summary>Donate via QR / address</summary>

<img src="docs/images/donate-ton-qr.png" alt="Donate TON — scan with any TON wallet" width="200" />

```
UQAMfkOwBBk_TZyn7LP2o9UgMrNW3GCLs3IJKOVxYBdzr0IK
```

</details>

## Why another storage plugin

Storing a refresh token is the most common Capacitor security question, and the usual answers do not
hold up:

| Common choice | What goes wrong |
| --- | --- |
| `localStorage` / `sessionStorage` in a native app | a plaintext file inside the app sandbox - readable on a rooted or jailbroken device |
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
devices (the key never leaves the device, so it could only fail to decrypt - but shipping it is
pointless):

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<application android:allowBackup="false" ...>
```

Want backups on? Use a `dataExtractionRules` exclusion for `token_vault.xml` instead. **iOS needs
nothing** - `WhenUnlockedThisDeviceOnly` items are never included in a backup.

## How it works

```
      your code
          |  setToken / getToken / removeToken / clear / getCapabilities
          ▼
   registerPlugin("TokenVault")            picks the implementation, 13 lines
          │
    ┌─────┴───────────────┬────────────────────────────┐
    ▼                     ▼                            ▼
  iOS bridge          Android bridge                 web
  TokenVaultPlugin    TokenVaultPlugin               TokenVaultWeb
    │ argument            │ argument                   │
    │ plumbing only       │ plumbing only              │
    ▼                     ▼                            ▼
  TokenVault.swift    TokenVault.kt                  sessionStorage
  SecItemAdd/Copy     Keystore key + AES-GCM         (memory fallback)
    │                     │                            │
    ▼                     ▼                            ▼
  Keychain            SharedPreferences              browser storage
  WhenUnlocked        (ciphertext only)              secure: false
  ThisDeviceOnly      hardware status queried
```

The bridge files are argument plumbing only, so the platform code is unit-testable without Capacitor.
Your app talks to one API and never branches on the platform - it branches on `getCapabilities()`.

The value is not code volume. It is the storage attributes, crypto parameters, failure behavior, and
tests. See [docs/DESIGN.md](https://github.com/AfanasievN/capacitor-token-vault/blob/main/docs/DESIGN.md).

## Integrating into your project

Three shapes, depending on how your app is built - direct in an auth service, behind your own
port/DI, or wrapped in an HTTP interceptor with single-flight refresh. Full working examples:
**[docs/INTEGRATION.md](https://github.com/AfanasievN/capacitor-token-vault/blob/main/docs/INTEGRATION.md)**.

Using an AI agent to wire it up? **[docs/AI.md](https://github.com/AfanasievN/capacitor-token-vault/blob/main/docs/AI.md)** has copy-paste prompts that adapt to your
architecture and state the security rules an agent tends to get wrong (persisting the access token,
logging users out on a network blip, branching on the platform instead of capabilities). Agents that
read URLs can start from [`llms.txt`](https://github.com/AfanasievN/capacitor-token-vault/blob/main/llms.txt).

## Compatibility

| | Supported |
| --- | --- |
| Capacitor | **8.x** (`@capacitor/core` is a peer dependency, `>=8.0.0`) |
| iOS | 15.0+ · SPM (a podspec is included for CocoaPods projects) |
| Android | API 24+ (Android 7) · compileSdk 36 · JDK 21 |
| Web | any browser with `sessionStorage`; degrades to memory without it |
| Node (tooling) | 20, 22, 24 - tested in CI |
| Module formats | ESM **and** CommonJS (`import` and `require` both work) |

Capacitor 6/7 are not supported: the plugin uses the `CAPBridgedPlugin` registration introduced for
Capacitor 6+ and is only tested against 8. If you need an older major, open an issue - the native
code itself has no version-specific dependencies.

## Usage

```ts
import {TokenVault} from "capacitor-token-vault";

// write / read / delete the default slot ("refresh")
await TokenVault.setToken({value: refreshToken});
const {value} = await TokenVault.getToken();     // null when empty - not an error
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
`UNAVAILABLE` | `INVALID_ARGUMENT` | `STORAGE_FAILURE` - and never contain the token value.

### API

| Method | Result |
| --- | --- |
| `getCapabilities()` | `{backend, secure, persistent, hardwareBacked}` |
| `setToken({value, name?})` | writes or overwrites a slot |
| `getToken({name?})` | `{value: string \| null}` |
| `removeToken({name?})` | idempotent delete |
| `clear()` | removes every slot owned by this plugin |

## Migrating from another plugin

The API is small, so a migration is a one-time copy on first launch. Read with the old plugin, write
with this one, delete the old value:

```ts
import {Preferences} from "@capacitor/preferences";        // or your current plugin
import {TokenVault} from "capacitor-token-vault";

async function migrateToken(): Promise<void> {
  if ((await TokenVault.getToken()).value !== null) return;   // already migrated

  const {value} = await Preferences.get({key: "refreshToken"});
  if (!value) return;

  await TokenVault.setToken({value});
  await Preferences.remove({key: "refreshToken"});           // stop leaving a plaintext copy
}
```

| Coming from | Notes |
| --- | --- |
| `@capacitor/preferences`, `localStorage` | the old value is plaintext - remove it after copying, as above |
| `capacitor-secure-storage-plugin` | `get`/`set`/`remove` map 1:1; its iOS items live under a different Keychain service, so read them with that plugin during the migration window |
| `@aparajita/capacitor-secure-storage` | same shape; if you only stored a token, you can drop that dependency (and the two Capacitor plugins it pulls in) afterwards |

Keep the migration for a release or two, then delete it - a user who skips versions still passes
through it as long as the code is there.

## What each platform actually does

| Platform | Where the token goes | Fixed parameters |
| --- | --- | --- |
| **iOS 15+** | Keychain, `kSecClassGenericPassword`, service `<bundleId>.token-vault` | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (also what keeps it out of backups), `kSecAttrSynchronizable = false` |
| **Android 7+ (API 24)** | AES-256-GCM ciphertext in `SharedPreferences("token_vault", MODE_PRIVATE)` | key `capacitor.token-vault.v1` generated in `AndroidKeyStore`, GCM, no padding, 256-bit, randomized IV per write, no user-auth requirement |
| **Web / PWA** | `sessionStorage` under `token-vault.`, in-memory when storage is blocked | reports `secure: false`; `localStorage` is never used |

Why these choices, in short - the long version is in [docs/DESIGN.md](https://github.com/AfanasievN/capacitor-token-vault/blob/main/docs/DESIGN.md):

- **`WhenUnlockedThisDeviceOnly`** is the only Keychain class that both requires an unlocked device
  *and* is excluded from backup/restore onto another device. Cost: background code cannot read the
  token while the device is locked - fine, since a refresh follows app use.
- **Keystore directly instead of `EncryptedSharedPreferences`** - see the table above; ~60 lines with
  no library lifecycle risk.
- **A versioned key alias** so a future parameter change becomes a new alias plus a documented
  migration, not silent decryption failures on real installs.
- **`sessionStorage` on the web rather than an `Unavailable` error**, so consumers get working
  behavior everywhere and the ones who care read `capabilities.secure`.
- **A corrupt or undecryptable slot reads as "absent"** on every platform: broken storage must never
  lock a user out of signing in again.
- **A token written by a previous installation is not returned.** iOS keeps Keychain items when an app
  is deleted, so a fresh install can find someone else's token on a resold or shared device. The
  plugin writes a per-slot marker into `UserDefaults`, which *is* removed with the app, and treats a token
  without its matching marker as absent, clearing it. Android needs nothing: its store goes away with
  the app.

## FAQ

### Should I store the access token here too?
Usually no. Keep the access token in memory and only persist the refresh token: a short-lived token
in memory cannot be stolen from disk at all. Named slots exist if you genuinely need a second secret.

### Can I store a JSON pair?
Yes - `setToken({value: JSON.stringify(pair)})`. The plugin deliberately does not parse your payload;
it stores an opaque string.

### Why does `secure` report `false` on the web?
Because no browser has a secure store. The plugin uses `sessionStorage` (tab-scoped, the smallest
window) and never `localStorage`, and tells you the truth so you can decide what to promise the user.

### What happens after an app reinstall?
Nothing is inherited: see the note above. Plan for the user to sign in again.

### Does it support biometrics (Face ID / fingerprint) to read the token?
Not in v1 - it changes the failure surface (enrollment invalidation, cancel flows) and belongs to a
session-policy layer. The design leaves room for an opt-in `requireUserPresence` without changing the
stored format; open an issue if you need it.

### Is `hardwareBacked` always true on Android?
No. It is asked of the Keystore per key, so emulators and devices with a software Keystore report
`false`. Branch on the value rather than assuming it.

### Does it work with `require()` and Jest (CommonJS)?
Yes - the package ships ESM and CommonJS, and CI loads both.

### Does it need any permissions?
No. The Android manifest is empty and iOS needs no entitlement (no Keychain sharing, no iCloud).

## Threat model

**Protects against:** another app or a shell on a rooted/jailbroken device reading the token off
disk; the token surviving in a device backup and being restored elsewhere; iCloud Keychain sync
carrying it to another device.

**Does not protect against:** code execution inside your app - XSS in the WebView or a malicious
dependency can call `getToken()` exactly like your code does. Strict CSP and supply-chain hygiene are
the controls there; storage choice only limits theft *at rest*. Full statement: [SECURITY.md](https://github.com/AfanasievN/capacitor-token-vault/blob/main/SECURITY.md).

No biometric gate in v1: `kSecAccessControl` / `setUserAuthenticationRequired` change the failure
surface (enrollment invalidation, cancel flows) and belong to a session-policy feature rather than to
storage. The design leaves room for an opt-in `requireUserPresence` without changing the stored format.

## Zero dependencies, and why it matters

`npm ls --omit=dev --all` prints an empty tree, and [CI asserts it](https://github.com/AfanasievN/capacitor-token-vault/blob/main/.github/workflows/ci.yml) on
every push. Concretely: `@capacitor/core` is a **peer** dependency (declaring it as a dependency is
what pulls a second Capacitor into a consumer's tree); Android compiles against platform Keystore
APIs only; iOS depends on Capacitor alone; the build is plain `tsc`, so there is no bundler chain
either. For a package that holds credentials, every transitive dependency is someone else's write
access to your token store.

## Development

```bash
npm install
npm run verify        # typecheck + web unit tests + dual (ESM + CJS) build
```

iOS ownership tests run directly in the simulator package. Tests that hit the real Keychain need an
app-hosted test target with Keychain entitlements; a bare Swift Package test process cannot prove
those guarantees:

```bash
xcodebuild test -scheme CapacitorTokenVault \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TokenVaultPluginTests/InstallationOwnershipTests
```

The Android library build, instrumented-test compilation, and lint run from this repository:

```bash
./android/gradlew -p android assembleDebug assembleDebugAndroidTest lintDebug
```

Executing the instrumented tests still needs a device or emulator. `AndroidKeyStore` has no JVM
implementation, so a Robolectric test would not prove the part that matters.

Status, honestly: CI verifies TypeScript, web behavior, both package module formats, the npm archive,
the Android library build/test compilation/lint, the iOS library build, and the pure iOS ownership
tests. Executing the Keychain and Android Keystore integration suites still needs properly hosted
native test applications.

The native suites are the security tests: on iOS they assert the accessibility and sync attributes;
on Android that a second instance decrypts what the first wrote, that ciphertext differs per write
(randomized IV), and that the plaintext never appears in the stored value.

Contributions welcome - [CONTRIBUTING.md](https://github.com/AfanasievN/capacitor-token-vault/blob/main/CONTRIBUTING.md) explains the one rule that shapes every
review: this plugin stays small.

## License

MIT © [AfanasievN](https://github.com/AfanasievN)
