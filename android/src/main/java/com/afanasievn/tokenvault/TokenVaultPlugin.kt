package com.afanasievn.tokenvault

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import java.util.concurrent.Executors

/**
 * Capacitor bridge. Argument plumbing only — the Keystore work lives in TokenVault.kt so
 * it can be tested without a bridge.
 */
@CapacitorPlugin(name = "TokenVault")
class TokenVaultPlugin : Plugin() {
    // Keystore + GCM calls are blocking; keep them off the WebView thread.
    private val io = Executors.newSingleThreadExecutor()
    private val vault by lazy { TokenVault(context) }

    @PluginMethod
    fun getCapabilities(call: PluginCall) {
        val result = JSObject().apply {
            put("backend", "keystore")
            put("secure", true)
            put("persistent", true)
            // AES keys in AndroidKeyStore are held by the TEE (or StrongBox) on every
            // device this plugin supports; the key bytes never enter app memory.
            put("hardwareBacked", true)
        }
        call.resolve(result)
    }

    @PluginMethod
    fun setToken(call: PluginCall) {
        val value = call.getString("value")
        if (value.isNullOrEmpty()) {
            call.reject("value must be a non-empty string", "INVALID_ARGUMENT")
            return
        }
        run(call) {
            vault.set(name(call), value)
            null
        }
    }

    @PluginMethod
    fun getToken(call: PluginCall) {
        run(call) {
            JSObject().apply { put("value", vault.get(name(call))) }
        }
    }

    @PluginMethod
    fun removeToken(call: PluginCall) {
        run(call) {
            vault.remove(name(call))
            null
        }
    }

    @PluginMethod
    fun clear(call: PluginCall) {
        run(call) {
            vault.clear()
            null
        }
    }

    private fun name(call: PluginCall): String = call.getString("name") ?: DEFAULT_NAME

    private fun run(call: PluginCall, work: () -> JSObject?) {
        io.execute {
            try {
                call.resolve(work() ?: JSObject())
            } catch (e: TokenVaultException) {
                call.reject(e.message, e.code)
            } catch (e: Exception) {
                call.reject("unexpected keystore failure (${e.javaClass.simpleName})", "STORAGE_FAILURE")
            }
        }
    }

    companion object {
        private const val DEFAULT_NAME = "refresh"
    }
}
