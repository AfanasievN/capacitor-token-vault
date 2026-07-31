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
        // Asks the Keystore rather than assuming: emulators and devices with a software
        // Keystore report false, and lying here would let a caller believe a guarantee the
        // device does not provide. Resolving this creates the key if it does not exist yet
        // (it would be created on the first write anyway).
        run(call) {
            JSObject().apply {
                put("backend", "keystore")
                put("secure", true)
                put("persistent", true)
                put("hardwareBacked", vault.isHardwareBacked())
            }
        }
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
