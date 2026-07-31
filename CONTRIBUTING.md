# Contributing

Thanks for looking at this. The plugin is small on purpose, and keeping it small is the main
review criterion — please read this before opening a change.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before opening a change

1. **Keep the scope: tokens, not data.** The API deliberately does not accept arbitrary key/value
   pairs. A general store leads to profile data and caches in the Keychain, which makes every
   consumer's security review larger. Features that only make sense for non-token data belong in a
   different plugin.
2. **No new runtime dependencies.** The production dependency tree is empty and CI asserts it.
   `@capacitor/core` stays a peer dependency; Android uses platform Keystore APIs (no
   `androidx.security`), iOS depends on Capacitor only.
3. **Security parameters are not caller-configurable without a reason.** Keychain accessibility,
   iCloud sync, GCM parameters and the key alias are fixed so that a consumer cannot silently
   weaken them. If an option is genuinely needed, explain the use case and the safe default.
4. **Changing the stored format needs a migration.** The Android key alias is versioned
   (`capacitor.token-vault.v1`) for exactly this: bump it and describe the migration, never change
   parameters under an existing alias — that turns into silent decryption failures on real installs.
5. **A broken vault must never lock a user out.** Corrupt or undecryptable slots read as "absent"
   so the app can ask for a fresh sign-in. Do not turn these into thrown errors.
6. **No secret in an error, log or test name.** Messages carry error *types*, never values. There is
   a test for this; keep it passing.
7. **Tests at the level that proves the change.** Web behavior → vitest. Anything about Keychain or
   Keystore behavior → the native suites, because that is where the guarantee lives. A change to
   platform parameters must come with an assertion on those parameters.
8. **Avoid company-specific details.** No internal hostnames, project names or private URLs in code,
   docs or tests.

## Good first contributions

- Device/OS compatibility reports — "works / fails on X with Y" is a genuinely useful issue even
  without code.
- Wiring the Android instrumented suite into CI with an emulator runner (see the TODO in
  `.github/workflows/ci.yml`).
- An example app showing the plugin behind an app's own storage port.
- Documentation: clarifying the threat model or the install steps a plugin cannot do for you.

## Local verification

```bash
npm install
npm run verify        # typecheck + web unit tests + build
swift test            # iOS, needs macOS + Xcode (real Keychain)
```

Android instrumented tests need a device or emulator and a host app —
`./gradlew connectedAndroidTest` from a consumer project. Say in the PR which of these you ran;
"web only" is fine and honest, and reviewers will run the rest.

## Pull requests

Describe what changed and why, which platforms you verified on, and anything you deliberately did
not do. If a change alters the security posture (storage location, attributes, error behavior), say
so explicitly in the description — that is the part that gets the closest read.

Open an issue first for API changes and for anything that widens the plugin's scope.
