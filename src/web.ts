import {WebPlugin} from "@capacitor/core";

import {
  DEFAULT_TOKEN_NAME,
  TOKEN_NAME_PATTERN,
  type TokenName,
  type TokenVaultErrorCode,
  type TokenVaultPlugin,
  type VaultCapabilities,
} from "./definitions.js";

const KEY_PREFIX = "token-vault.";

function fail(code: TokenVaultErrorCode, message: string): never {
  // Capacitor surfaces `code` to JS callers; keep values out of the message.
  const error = new Error(message) as Error & {code: TokenVaultErrorCode};
  error.code = code;
  throw error;
}

function slot(name: TokenName | undefined): string {
  const resolved = name ?? DEFAULT_TOKEN_NAME;
  if (!TOKEN_NAME_PATTERN.test(resolved)) {
    fail("INVALID_ARGUMENT", `token name must match ${String(TOKEN_NAME_PATTERN)}`);
  }
  return KEY_PREFIX + resolved;
}

/**
 * Session-scoped store: the browser has no secure storage, so the honest choice is
 * the smallest window instead of the longest life — `sessionStorage` (dies with the
 * tab), never `localStorage`. When storage is unavailable at all (private mode,
 * blocked cookies, sandboxed iframe) the plugin degrades to an in-process Map so a
 * signed-in session still works for as long as the page lives.
 */
function resolveStorage(): {storage: Storage | null; probeFailed: boolean} {
  try {
    const candidate = globalThis.sessionStorage;
    if (!candidate) return {storage: null, probeFailed: false};
    // Safari in private mode throws only on write — probe before trusting it.
    const probeKey = `${KEY_PREFIX}__probe__`;
    candidate.setItem(probeKey, "1");
    candidate.removeItem(probeKey);
    return {storage: candidate, probeFailed: false};
  } catch {
    return {storage: null, probeFailed: true};
  }
}

export class TokenVaultWeb extends WebPlugin implements TokenVaultPlugin {
  private readonly storage: Storage | null;
  private readonly memory = new Map<string, string>();

  constructor() {
    super();
    this.storage = resolveStorage().storage;
  }

  async getCapabilities(): Promise<VaultCapabilities> {
    const usingStorage = this.storage !== null;
    return {
      backend: usingStorage ? "session-storage" : "memory",
      // No browser store is secure against local code; say so rather than imply it.
      secure: false,
      // sessionStorage survives a reload within the same tab; memory does not.
      persistent: usingStorage,
      hardwareBacked: false,
    };
  }

  async setToken(options: {value: string; name?: TokenName}): Promise<void> {
    if (typeof options?.value !== "string" || options.value.length === 0) {
      fail("INVALID_ARGUMENT", "value must be a non-empty string");
    }
    const key = slot(options.name);
    try {
      if (this.storage) this.storage.setItem(key, options.value);
      else this.memory.set(key, options.value);
    } catch (cause) {
      fail("STORAGE_FAILURE", `could not write the token slot (${describe(cause)})`);
    }
  }

  async getToken(options?: {name?: TokenName}): Promise<{value: string | null}> {
    const key = slot(options?.name);
    try {
      const value = this.storage ? this.storage.getItem(key) : (this.memory.get(key) ?? null);
      return {value};
    } catch (cause) {
      fail("STORAGE_FAILURE", `could not read the token slot (${describe(cause)})`);
    }
  }

  async removeToken(options?: {name?: TokenName}): Promise<void> {
    const key = slot(options?.name);
    try {
      if (this.storage) this.storage.removeItem(key);
      else this.memory.delete(key);
    } catch (cause) {
      fail("STORAGE_FAILURE", `could not remove the token slot (${describe(cause)})`);
    }
  }

  async clear(): Promise<void> {
    try {
      if (this.storage) {
        // Only this plugin's keys — the tab's sessionStorage belongs to the app too.
        const owned: string[] = [];
        for (let i = 0; i < this.storage.length; i += 1) {
          const key = this.storage.key(i);
          if (key?.startsWith(KEY_PREFIX)) owned.push(key);
        }
        for (const key of owned) this.storage.removeItem(key);
      }
      this.memory.clear();
    } catch (cause) {
      fail("STORAGE_FAILURE", `could not clear the vault (${describe(cause)})`);
    }
  }
}

/** Error text for logs: type only, never the payload. */
function describe(cause: unknown): string {
  return cause instanceof Error ? cause.name : typeof cause;
}
