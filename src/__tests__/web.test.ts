import {beforeEach, describe, expect, it, vi} from "vitest";

import {TokenVaultWeb} from "../web.js";

/** Minimal Storage double — sessionStorage semantics, with hooks to make it misbehave. */
function createStorage(overrides: {failWrites?: boolean} = {}): Storage {
  const map = new Map<string, string>();
  return {
    get length() {
      return map.size;
    },
    key: (i: number) => [...map.keys()][i] ?? null,
    getItem: (k: string) => map.get(k) ?? null,
    setItem: (k: string, v: string) => {
      if (overrides.failWrites) throw new DOMException("quota", "QuotaExceededError");
      map.set(k, v);
    },
    removeItem: (k: string) => void map.delete(k),
    clear: () => map.clear(),
  } as Storage;
}

function withStorage(storage: Storage | undefined): void {
  vi.stubGlobal("sessionStorage", storage);
}

describe("TokenVaultWeb", () => {
  beforeEach(() => {
    vi.unstubAllGlobals();
  });

  it("round-trips a token in sessionStorage and reports the backend honestly", async () => {
    withStorage(createStorage());
    const vault = new TokenVaultWeb();

    expect(await vault.getCapabilities()).toEqual({
      backend: "session-storage",
      secure: false,
      persistent: true,
      hardwareBacked: false,
    });

    await vault.setToken({value: "rt-1"});
    expect(await vault.getToken()).toEqual({value: "rt-1"});
  });

  it("reads an empty slot as null rather than failing", async () => {
    withStorage(createStorage());
    expect(await new TokenVaultWeb().getToken()).toEqual({value: null});
  });

  it("overwrites the same slot and keeps named slots apart", async () => {
    withStorage(createStorage());
    const vault = new TokenVaultWeb();

    await vault.setToken({value: "first"});
    await vault.setToken({value: "second"});
    await vault.setToken({value: "other", name: "secondary"});

    expect(await vault.getToken()).toEqual({value: "second"});
    expect(await vault.getToken({name: "secondary"})).toEqual({value: "other"});
  });

  it("removeToken is idempotent", async () => {
    withStorage(createStorage());
    const vault = new TokenVaultWeb();

    await vault.removeToken();
    await vault.setToken({value: "rt"});
    await vault.removeToken();

    expect(await vault.getToken()).toEqual({value: null});
  });

  it("clear removes only this plugin's keys", async () => {
    const storage = createStorage();
    storage.setItem("app.theme", "dark");
    withStorage(storage);
    const vault = new TokenVaultWeb();

    await vault.setToken({value: "rt"});
    await vault.setToken({value: "rt2", name: "secondary"});
    await vault.clear();

    expect(await vault.getToken()).toEqual({value: null});
    expect(await vault.getToken({name: "secondary"})).toEqual({value: null});
    expect(storage.getItem("app.theme")).toBe("dark");
  });

  it("falls back to memory when storage is missing, and says it is not persistent", async () => {
    withStorage(undefined);
    const vault = new TokenVaultWeb();

    expect(await vault.getCapabilities()).toMatchObject({backend: "memory", persistent: false});
    await vault.setToken({value: "rt"});
    expect(await vault.getToken()).toEqual({value: "rt"});
  });

  it("falls back to memory when the write probe throws (Safari private mode)", async () => {
    withStorage(createStorage({failWrites: true}));
    const vault = new TokenVaultWeb();

    expect(await vault.getCapabilities()).toMatchObject({backend: "memory"});
    await vault.setToken({value: "rt"});
    expect(await vault.getToken()).toEqual({value: "rt"});
  });

  it("rejects an empty value and a malformed name with INVALID_ARGUMENT", async () => {
    withStorage(createStorage());
    const vault = new TokenVaultWeb();

    await expect(vault.setToken({value: ""})).rejects.toMatchObject({code: "INVALID_ARGUMENT"});
    await expect(vault.setToken({value: "rt", name: "bad name!"})).rejects.toMatchObject({
      code: "INVALID_ARGUMENT",
    });
    await expect(vault.getToken({name: "x".repeat(65)})).rejects.toMatchObject({
      code: "INVALID_ARGUMENT",
    });
  });

  it("never puts a token value into an error message", async () => {
    withStorage(createStorage());
    const vault = new TokenVaultWeb();
    const secret = "super-secret-token";

    const error = await vault.setToken({value: secret, name: "bad name!"}).catch((e: Error) => e);

    expect(error).toBeInstanceOf(Error);
    expect((error as Error).message).not.toContain(secret);
  });
});
