# capacitor-token-vault

Keeps an auth token in the safest place each platform offers — iOS Keychain, Android Keystore,
`sessionStorage` on the web — behind one small API. **Zero runtime dependencies.**

Deliberately narrow: this is not a key-value store. It holds tokens, so that a security review of
"what is in the Keychain?" has one answer. Design and rationale: [docs/DESIGN.md](docs/DESIGN.md).

## Install

```bash
pnpm add capacitor-token-vault
pnpm exec cap sync
```

Then two install steps that a plugin cannot do for you:

**1. Keep the native build lean** — pin the plugin allowlist so no unexpected plugin gets linked:

```ts
// capacitor.config.ts
const config: CapacitorConfig = {
  includePlugins: ["capacitor-token-vault"],
};
```

**2. Exclude the Android store from cloud backups** — otherwise the encrypted blob travels to a new
device (the key does not, so it would only ever fail to decrypt, but shipping it is pointless):

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<application android:allowBackup="false" ...>
```

Prefer to keep backups on? Use a `dataExtractionRules` exclusion for `token_vault.xml` instead.
iOS needs nothing: `WhenUnlockedThisDeviceOnly` items are never in a backup.

## Use

```ts
import {TokenVault} from "capacitor-token-vault";

await TokenVault.setToken({value: refreshToken});          // slot "refresh"
const {value} = await TokenVault.getToken();               // string | null
await TokenVault.removeToken();
await TokenVault.clear();                                  // logout

const caps = await TokenVault.getCapabilities();
// { backend: "keychain" | "keystore" | "session-storage" | "memory",
//   secure, persistent, hardwareBacked }
if (!caps.persistent) {
  // web tab / private mode: do not promise "stay signed in"
}
```

Named slots when one is not enough: `setToken({value, name: "secondary"})`. Names match
`^[a-zA-Z0-9._-]{1,64}$`.

Errors reject with `code` = `UNAVAILABLE` | `INVALID_ARGUMENT` | `STORAGE_FAILURE`. Reading an empty
slot is **not** an error — it resolves `{value: null}`. No error message ever contains a token.

## What each platform actually does

| Platform | Where the token goes | Fixed parameters |
| --- | --- | --- |
| iOS 14+ | Keychain (`kSecClassGenericPassword`, service `<bundleId>.token-vault`) | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`, `kSecUseDataProtectionKeychain = true` |
| Android 6+ | AES-256-GCM ciphertext in `SharedPreferences("token_vault", MODE_PRIVATE)` | key `capacitor.token-vault.v1` generated in `AndroidKeyStore`, GCM, no padding, randomized IV per write, no user-auth requirement |
| Web / PWA | `sessionStorage` under `token-vault.`, in-memory when storage is blocked | `secure: false` is reported — no browser has a secure store, and `localStorage` is never used |

## Threat model

**Protects against:** another app or a shell on a rooted/jailbroken device reading the token off
disk; the token surviving in a device backup and being restored elsewhere; iCloud Keychain sync
carrying it to another device.

**Does not protect against:** code execution inside your app (XSS in the WebView, a malicious
dependency) — that code can call `getToken()` like yours does. Strict CSP and supply-chain hygiene
are the controls there; storage choice only limits theft *at rest*.

No biometric gate in v1 — that is a session-policy decision, not a storage one. See
[docs/DESIGN.md](docs/DESIGN.md) non-goals.

## Develop

```bash
npm install
npm run verify        # typecheck + web unit tests + build
```

| Layer | Command | Needs |
| --- | --- | --- |
| Web + contract | `npm run verify` | node ≥20 |
| iOS | `swift test` (or the Xcode test action) | macOS + Xcode; hits the real Keychain, asserts the item attributes |
| Android | `./gradlew connectedAndroidTest` from a consumer app | device/emulator — `AndroidKeyStore` has no JVM implementation |

The native suites are the security tests: they assert accessibility/sync attributes on iOS and, on
Android, that a second process instance can decrypt, that ciphertext differs per write, and that the
plaintext never appears in the stored value.
