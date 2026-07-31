/**
 * Public contract of capacitor-token-vault (docs/DESIGN.md).
 *
 * Scope on purpose: tokens, not arbitrary data. A general key-value store in the
 * Keychain invites profile data and caches into a place that should hold exactly
 * one class of secret — and makes every consumer's security review larger.
 */

/**
 * Slot name. Defaults to `"refresh"`. Constrained so it can be used verbatim as a
 * Keychain account, a preferences key and a storage key without escaping.
 */
export type TokenName = string;

export const TOKEN_NAME_PATTERN = /^[a-zA-Z0-9._-]{1,64}$/;
export const DEFAULT_TOKEN_NAME = "refresh";

export type VaultBackend = "keychain" | "keystore" | "session-storage" | "memory";

export interface VaultCapabilities {
  backend: VaultBackend;
  /**
   * The OS keeps the value outside storage that other app code on the device can
   * read. False on the web — no browser has a secure store, and pretending
   * otherwise is how tokens end up in `localStorage`.
   */
  secure: boolean;
  /** The value survives an app (or tab) restart. */
  persistent: boolean;
  /** Key material lives in a TEE / Secure Enclave / StrongBox. */
  hardwareBacked: boolean;
}

/** Error codes carried on rejections. Messages never contain a token value. */
export type TokenVaultErrorCode = "UNAVAILABLE" | "INVALID_ARGUMENT" | "STORAGE_FAILURE";

export interface TokenVaultPlugin {
  /**
   * What this platform actually provides. Callers that care about the difference
   * (e.g. "may I keep the user signed in across restarts?") branch on this
   * instead of on the platform name.
   */
  getCapabilities(): Promise<VaultCapabilities>;

  /** Writes (or overwrites) the token in the slot. */
  setToken(options: {value: string; name?: TokenName}): Promise<void>;

  /** Reads the slot. `value` is `null` when nothing is stored — not an error. */
  getToken(options?: {name?: TokenName}): Promise<{value: string | null}>;

  /** Removes one slot. Removing an empty slot succeeds (idempotent). */
  removeToken(options?: {name?: TokenName}): Promise<void>;

  /** Removes every slot this plugin owns — logout, account switch, wipe. */
  clear(): Promise<void>;
}
