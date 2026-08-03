# capacitor-token-vault - design

A Capacitor plugin whose only job is to keep **one kind of secret - an auth token - in the safest
place each platform offers**, with zero runtime dependencies.

## Why it exists

Surveyed alternatives (July 2026) each fail one requirement:

| Candidate | Problem |
| --- | --- |
| `@capacitor/preferences` | plain `UserDefaults` / `SharedPreferences` - a token there is a plaintext file |
| `capacitor-secure-storage-plugin` | no control over Keychain accessibility or iCloud sync; pre-1.0 |
| `@aparajita/capacitor-secure-storage` | a capable general-purpose store with the right Keychain API; different scope (arbitrary key/value) and, as published, it lists `@capacitor/app` + `@capacitor/keyboard` as dependencies, so `cap sync` links plugins a token store does not need |
| `androidx.security` EncryptedSharedPreferences | deprecated since `security-crypto:1.1.0-alpha07` (main-thread performance, OEM keyset corruption) |

The requirements that survive: **explicit** Keychain accessibility, iCloud sync off, no backup
inclusion, Keystore-backed encryption on Android without a deprecated support library, an honest web
story, and no dependency we did not choose.

## Non-goals (deliberately narrow)

1. **Not a key-value store.** A general store invites callers to put profile data, PII or caches in
   the Keychain - the wrong tool, and it makes every consumer's security review bigger. The API takes
   *tokens*: short opaque strings, a handful of named slots.
2. **No biometric gate** in v1. `kSecAccessControl` / `setUserAuthenticationRequired` change the
   failure surface (enrollment invalidation, cancel flows) and belong to a session-policy feature,
   not to storage. The design leaves a door: a `requireUserPresence` option can be added without
   changing the stored format.
3. **No sync/sharing**: no iCloud, no Keychain access groups, no cross-app sharing in v1.
4. **No crypto of our own.** Everything is platform APIs: `SecItem*` on iOS, `AndroidKeyStore` +
   `javax.crypto` AES-GCM on Android. We choose parameters; we never implement a primitive.

## API

```ts
type TokenName = string;               // default "refresh"; [a-zA-Z0-9._-]{1,64}
type VaultBackend = "keychain" | "keystore" | "session-storage" | "memory";

interface VaultCapabilities {
  backend: VaultBackend;
  /** The OS keeps the secret outside storage other app code can read. */
  secure: boolean;
  /** Survives an app restart. */
  persistent: boolean;
  /** Key material is bound to this device's hardware - see the note below; not assumed. */
  hardwareBacked: boolean;
}

interface TokenVaultPlugin {
  getCapabilities(): Promise<VaultCapabilities>;
  setToken(options: {value: string; name?: TokenName}): Promise<void>;
  getToken(options?: {name?: TokenName}): Promise<{value: string | null}>;
  removeToken(options?: {name?: TokenName}): Promise<void>;
  /** Removes every slot this plugin owns. Used on logout and on account switch. */
  clear(): Promise<void>;
}
```

`hardwareBacked` is **asked of the platform, never assumed**: on Android it comes from
`KeyInfo.securityLevel` (API 31+) or `isInsideSecureHardware`, so emulators and software-Keystore
devices report `false`; anything unexpected also reports `false`, because a security claim defaults to
"no". On iOS it is `true` and means the item is encrypted with a data-protection class key derived by
the hardware AES engine from the device UID - *not* Secure Enclave residency, which applies to keys
rather than payloads.

`getCapabilities()` is what makes the web story honest: a caller can see it got
`{backend: "session-storage", secure: false, persistent: false}` and decide (our app: keep using it,
because the alternative on web is worse - see the platform table).

Errors reject with a Capacitor error whose `code` is one of `UNAVAILABLE`, `INVALID_ARGUMENT`,
`STORAGE_FAILURE`. No error message ever contains a token value.

## Per-platform behavior

| Platform | Backend | Parameters (fixed by this plugin, not by the caller) |
| --- | --- | --- |
| iOS 15+ | Keychain, `kSecClassGenericPassword` | `kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (device-only means never in an iTunes/iCloud backup), `kSecAttrSynchronizable = false`, `service = "<bundleId>.token-vault"`, `account = name` |
| Android 7+ (API 24) | `AndroidKeyStore` AES-256-GCM + app-private prefs | key alias `capacitor.token-vault.v1`, `KeyGenParameterSpec(ENCRYPT \| DECRYPT)`, `BLOCK_MODE_GCM`, `ENCRYPTION_PADDING_NONE`, `setKeySize(256)`, `setRandomizedEncryptionRequired(true)`; ciphertext + IV base64 in `SharedPreferences("token_vault", MODE_PRIVATE)`; hardware backing is queried, never assumed |
| Web / PWA | `sessionStorage`, `memory` fallback | prefix `token-vault.`; falls back to an in-process `Map` when storage is blocked (private mode, disabled cookies). Reports `secure: false` - the browser has no secure store, and `localStorage` is deliberately never used |

Notes that drove these choices:

- **Why `WhenUnlockedThisDeviceOnly`** rather than `AfterFirstUnlock`: it is the only class that both
  requires an unlocked device and is excluded from backups/restore onto another device. The cost is
  that background code cannot read the token while the device is locked - acceptable, because a
  refresh happens in response to app use.
- **Why not `EncryptedSharedPreferences`**: deprecated (see table above). Using the Keystore directly
  is ~60 lines and has no library lifecycle risk. Backup exclusion stays the app's job (manifest
  `allowBackup=false` or a `dataExtractionRules` exclusion for `token_vault.xml`) - a plugin cannot
  edit the consumer's manifest, so the README states it as an install step.
- **Why a versioned key alias** (`…v1`): a future parameter change (StrongBox-only, user presence)
  becomes a new alias plus a documented migration instead of silent decryption failures.
- **Why `sessionStorage` on web and not `Unavailable`**: consumers that treat the plugin as
  "all platforms" get working behavior everywhere, and the ones that care read `capabilities.secure`.
  Returning `Unavailable` on web would push every consumer into writing the same fallback.

## Inherited tokens after a reinstall

iOS keeps Keychain items when an app is deleted: the iOS 10.3 beta change that removed them was rolled
back, and Apple has never documented the behavior. A freshly installed app can therefore read a token
written by a previous installation - plausibly by a different person, on a resold or shared device.

The plugin refuses to hand that back. Every write also stores a per-slot marker in `UserDefaults`,
which *is* removed with the app; a stored token without its matching marker is treated as absent and cleared, so the
app asks for a fresh sign-in. Android needs none of this - its preferences file goes away with the app.

This is deliberately handled in the library rather than documented as a caveat: every consumer would
otherwise have to rediscover it, and the failure mode (resuming a stranger's session) is bad enough
that "read the README" is not an acceptable mitigation.

## Threat model (what this does and does not buy)

Protects against: another app or a shell on a rooted/jailbroken device reading tokens off disk;
tokens surviving in device backups and being restored elsewhere; tokens leaking through iCloud sync.

Does **not** protect against: an attacker with code execution inside the app (XSS in the WebView,
a malicious dependency) - they can call `getToken()` like any other code. That is a CSP and
supply-chain problem, and the README says so instead of implying more.

## Zero dependencies, concretely

- npm `dependencies`: **{}**. `@capacitor/core` is a `peerDependency` - the consumer already has it,
  and declaring it as a dependency is exactly the mistake that pulls a second Capacitor into the tree.
- Android: Capacitor Android is supplied by the consumer and linked as a sibling project by the local
  build harness; production code adds **no** direct AndroidX or Tink dependency.
- iOS: SPM target and a podspec, both depending only on `Capacitor` itself; no external Swift
  packages.
- Build: `tsc` only - twice, emitting ESM (`dist/`) and CommonJS (`dist/cjs/`, marked with a
  four-line generated `package.json`). No bundler, so no bundler dependency chain. Relative imports
  carry `.js` extensions and `moduleResolution: NodeNext` enforces it, because ESM output with
  extensionless imports loads in bundlers but **not** in Node - a trap worth closing at the compiler.
- devDependencies are limited to the TypeScript/test toolchain and Capacitor's core/Android build
  surfaces. They never reach a consumer's production dependency tree.

## Verification

| Layer | How |
| --- | --- |
| Web implementation | vitest unit tests (storage present, storage throwing, memory fallback, name validation, capability reporting) |
| Contract and package | `tsc --noEmit`, ESM import, CommonJS require, and archive-content checks |
| iOS in CI | Library compile plus pure ownership-marker tests on an iOS simulator |
| iOS hosted integration | App-hosted XCTest with Keychain entitlements: set/get/remove, overwrite, attribute assertions, and inherited-item behavior |
| Android in CI | Library build, instrumented-test compilation, and lint |
| Android hosted integration | Instrumented tests on a device/emulator: set/get/remove, cross-instance decrypt, randomized ciphertext, plaintext absence, corruption behavior, and `hardwareBacked` reporting |

CI compiles both native implementations and every Android instrumented test. Executing the real
Keychain and Keystore integration suites requires app-hosted targets with the appropriate runtime.
