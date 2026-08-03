# Integrating capacitor-token-vault

Three shapes, from smallest to most structured. Pick the one that matches how your app is already
built - the plugin does not care, and none of them requires configuration.

Whichever you pick, two rules carry over:

1. **Persist the refresh token only.** Keep the access token in a variable. A short-lived token that
   never reaches disk cannot be stolen from disk.
2. **Ask `getCapabilities()` before promising anything.** On a browser tab the session dies with the
   tab; do not render "stay signed in" there.

## Architecture

```
      your code
          │  setToken / getToken / removeToken / clear / getCapabilities
          ▼
   registerPlugin("TokenVault")            src/index.ts - picks the implementation
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
  ThisDeviceOnly      key never leaves TEE
```

The bridge files hold no logic, so the platform code is testable without Capacitor. Your app talks to
one API and never branches on the platform - branch on `getCapabilities()` instead.

## 1. Direct - small apps, one auth service

```ts
// auth/tokenStorage.ts
import {TokenVault} from "capacitor-token-vault";

export const tokenStorage = {
  save: (refreshToken: string) => TokenVault.setToken({value: refreshToken}),
  load: async () => (await TokenVault.getToken()).value,
  clear: () => TokenVault.clear(),
};
```

```ts
// on sign-in
await tokenStorage.save(response.refreshToken);
accessToken = response.accessToken;          // memory only

// on app start
const refreshToken = await tokenStorage.load();
if (refreshToken) accessToken = await refreshSession(refreshToken);

// on logout
await tokenStorage.clear();
accessToken = null;
```

## 2. Behind your own port - layered / hexagonal / DI projects

If your architecture forbids features from touching infrastructure directly, declare the capability
you need and let one adapter know the plugin exists.

```ts
// domain/ports.ts - no plugin import here
export interface TokenStore {
  load(): Promise<string | null>;
  save(token: string): Promise<void>;
  clear(): Promise<void>;
}
```

```ts
// infrastructure/vaultTokenStore.ts - the ONLY file that imports the plugin
import {TokenVault} from "capacitor-token-vault";
import type {TokenStore} from "../domain/ports";

export function createVaultTokenStore(): TokenStore {
  return {
    load: async () => (await TokenVault.getToken()).value,
    save: (token) => TokenVault.setToken({value: token}),
    clear: () => TokenVault.clear(),
  };
}
```

```ts
// composition root / DI container
const tokenStore = createVaultTokenStore();
const auth = createAuthService({tokenStore});
```

Tests get a fake without touching Capacitor:

```ts
export function createFakeTokenStore(): TokenStore {
  let value: string | null = null;
  return {
    load: async () => value,
    save: async (t) => void (value = t),
    clear: async () => void (value = null),
  };
}
```

Angular is the same idea with an `InjectionToken`; React with a context provider; Vue with a
composable that returns the store from `provide`/`inject`.

## 3. With refresh and a fetch interceptor - the usual production shape

Access token in memory, refresh token in the vault, one refresh shared by all concurrent 401s.

```ts
import {TokenVault} from "capacitor-token-vault";

let accessToken: string | null = null;
let inFlight: Promise<string | null> | null = null;

async function refresh(): Promise<string | null> {
  // Single-flight: ten parallel 401s must trigger one refresh, not ten.
  if (inFlight) return inFlight;

  inFlight = (async () => {
    try {
      const stored = (await TokenVault.getToken()).value;
      if (!stored) return null;

      const res = await fetch("/api/auth/refresh", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({refreshToken: stored}),
      });

      if (res.status === 401) {
        // The refresh token is dead - end the session.
        await TokenVault.clear();
        accessToken = null;
        return null;
      }
      if (!res.ok) return accessToken;          // transient: keep the session

      const pair = await res.json();
      await TokenVault.setToken({value: pair.refreshToken});   // rotated
      accessToken = pair.accessToken;
      return accessToken;
    } finally {
      inFlight = null;
    }
  })();

  return inFlight;
}

export async function apiFetch(input: RequestInfo | URL, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  if (accessToken) headers.set("Authorization", `Bearer ${accessToken}`);

  const response = await fetch(input, {...init, headers});
  if (response.status !== 401) return response;

  const fresh = await refresh();
  if (!fresh) return response;                  // signed out; let the caller route to login

  headers.set("Authorization", `Bearer ${fresh}`);
  return fetch(input, {...init, headers});      // exactly one retry
}
```

Three details worth keeping when you adapt this:

- **A transient failure must not log the user out.** Only a `401` from the refresh endpoint clears the
  vault; a network blip returns the current token and lets the caller retry.
- **Store the rotated refresh token** if your backend rotates on every refresh (it should).
- **Retry once.** A second 401 after a fresh token means the session is genuinely over.

## Restoring the session on start

```ts
// Boot: the vault read is fast, but it is I/O - do it before rendering the guarded screens.
export async function restoreSession(): Promise<boolean> {
  const {value} = await TokenVault.getToken();
  if (!value) return false;
  return (await refresh()) !== null;
}
```

On the web this returns `false` in a new tab by design; on iOS/Android it is what keeps the user
signed in. Do not treat `false` as an error.

## Deciding what to promise the user

```ts
const caps = await TokenVault.getCapabilities();

if (!caps.persistent) {
  // browser tab / private mode: no "remember me" checkbox
} else if (!caps.hardwareBacked) {
  // Android emulator or software Keystore: fine, but if your risk policy requires
  // hardware-backed keys, this is where you notice
}
```

## Platform setup you must not skip

```ts
// capacitor.config.ts - link only the plugins you actually use
const config: CapacitorConfig = {
  includePlugins: ["capacitor-token-vault"],
};
```

```xml
<!-- android/app/src/main/AndroidManifest.xml - keep the encrypted store out of cloud backups -->
<application android:allowBackup="false" ...>
```

iOS needs nothing: `WhenUnlockedThisDeviceOnly` items are never in a backup.

## Notes for specific setups

- **SSR / prerendering (Nuxt, Next, Angular Universal)**: the web implementation is lazy-loaded on
  first use, so importing the plugin on the server is safe - just do not *call* it there. Guard with
  `typeof window !== "undefined"` in code that can run on both.
- **Jest / CommonJS toolchains**: the package ships CJS as well as ESM, so `require()` works.
- **Multiple secrets**: use named slots (`setToken({value, name: "device"})`) rather than packing
  unrelated data into one JSON blob - `clear()` still removes all of them at logout.
- **Testing your integration**: mock the module, not the platform. `vi.mock("capacitor-token-vault")`
  or inject the fake store from pattern 2.
