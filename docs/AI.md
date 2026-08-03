# Integrating with an AI agent

Copy a prompt, paste it into Claude Code / Cursor / Copilot / Codex with your repository open. Each
one is written so the agent adapts to *your* architecture instead of pasting a fixed snippet - and so
it cannot quietly get the security-relevant parts wrong.

If your agent can read URLs, point it at
[`llms.txt`](https://raw.githubusercontent.com/AfanasievN/capacitor-token-vault/main/llms.txt) first:
it is the whole contract and every rule in one page.

## 1. Install and wire it into an existing app

```
Add capacitor-token-vault (https://github.com/AfanasievN/capacitor-token-vault) to this app to store
the refresh token.

Until the first npm release, install it with
`npm install github:AfanasievN/capacitor-token-vault#main`, then run `npx cap sync`.

Read docs/INTEGRATION.md from the package (or the repo) first, then match MY architecture:
- If the project has ports/interfaces or a DI container, put the plugin behind one adapter and wire it
  where dependencies are composed. Feature code must not import the plugin.
- If it is a small app with a single auth service, use it directly there.

Rules that are not negotiable:
1. Persist ONLY the refresh token. The access token stays in memory - never in the vault, never in
   localStorage.
2. Do not store anything other than tokens in the vault.
3. Call getCapabilities() and use `persistent` to decide whether the UI may offer "stay signed in".
   Do not branch on the platform name.
4. Add `includePlugins: ["capacitor-token-vault"]` to capacitor.config.ts.
5. On Android, keep the store out of cloud backups (`allowBackup=false` or a dataExtractionRules
   exclusion for token_vault.xml).
6. Reading an empty slot returns {value: null} - that is normal, not an error. Do not treat it as one.

Then show me the diff and tell me which files now know that this plugin exists.
```

## 2. Add refresh-on-401 around it

```
Using capacitor-token-vault for the refresh token, implement token refresh in this app's HTTP layer.
Follow docs/INTEGRATION.md pattern 3 and keep these properties:

- Access token in memory; refresh token read from the vault.
- Single-flight: N concurrent 401s trigger exactly ONE refresh, and all of them retry with the new
  token.
- Retry a request once. A second 401 means the session is over.
- Clear the vault ONLY when the refresh endpoint answers 401 (dead refresh token). A network error or
  5xx must NOT log the user out.
- If the backend rotates refresh tokens, store the new one after every refresh.

Wire it into the HTTP client this project already uses (fetch wrapper, axios interceptor, Angular
HttpInterceptor - whatever is here), not a new one. Add tests for the single-flight and
"transient error does not log out" cases.
```

## 3. Migrate from another storage plugin

```
This app currently stores its refresh token with <@capacitor/preferences | localStorage |
capacitor-secure-storage-plugin | @aparajita/capacitor-secure-storage>. Migrate it to
capacitor-token-vault.

Write a one-time migration that runs on app start: if the vault is empty and the old storage has a
token, copy it into the vault and DELETE it from the old storage (leaving a plaintext copy behind
defeats the point). Keep the migration for a couple of releases, and add a comment saying when it can
be removed.

Do not remove the old dependency until the migration has shipped. Show me the diff.
```

## 4. Review my token handling

```
Audit how this app stores and uses auth tokens, using capacitor-token-vault's guarantees as the
baseline (see its SECURITY.md).

Report concrete findings on:
- any token written to localStorage / sessionStorage / preferences / a plain file;
- the access token being persisted at all;
- tokens appearing in logs, analytics events, error messages or crash reports;
- refresh logic that logs the user out on a transient network error;
- refresh logic without single-flight (a burst of 401s causing parallel refreshes);
- code that assumes hardware-backed storage without reading getCapabilities().hardwareBacked;
- Android backups including the token store; iOS Keychain items shared or synced when they should
  not be.

For each finding: file, why it matters, and the smallest fix. Do not change code yet.
```

## 5. Explain what the plugin guarantees (before you trust it)

```
Read https://raw.githubusercontent.com/AfanasievN/capacitor-token-vault/main/llms.txt and tell me, in
plain terms: where exactly does the refresh token end up on iOS, on Android and in a browser; what
this plugin protects against; what it explicitly does NOT protect against; and what I have to do
myself in my app. Then tell me whether that is enough for MY threat model, which is: <describe it>.
```

## Why the prompts are shaped like this

Agents reliably get three things wrong when wiring token storage, so every prompt above states them
outright rather than hoping:

- **Storing the access token too**, because "store the tokens" reads as plural. It is the one token
  that should never touch disk.
- **Logging the user out on any refresh failure**, which turns a subway tunnel into a forced re-login.
  Only a 401 from the refresh endpoint means the token is dead.
- **Branching on `Capacitor.getPlatform()`** instead of on capabilities, which produces code that is
  wrong on an installed PWA, in a private-mode tab and on an emulator.

If an agent produces something that violates one of these, the fix is usually to paste the relevant
rule back at it - they are all short and testable.
