import {registerPlugin} from "@capacitor/core";

import type {TokenVaultPlugin} from "./definitions";

/**
 * The web implementation is lazy-loaded: native builds never pull it into the
 * bundle, and the web build only pays for it when the plugin is first used.
 */
export const TokenVault = registerPlugin<TokenVaultPlugin>("TokenVault", {
  web: () => import("./web").then((m) => new m.TokenVaultWeb()),
});

export * from "./definitions";
