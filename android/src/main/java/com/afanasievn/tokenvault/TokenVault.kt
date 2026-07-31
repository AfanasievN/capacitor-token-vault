package com.afanasievn.tokenvault

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Token slots encrypted with an AES-256-GCM key that never leaves the Android Keystore
 * (docs/DESIGN.md). No androidx.security dependency — EncryptedSharedPreferences is
 * deprecated (security-crypto 1.1.0-alpha07) and the Keystore API is enough for a value
 * this small.
 *
 * Storage layout: SharedPreferences file "token_vault" (MODE_PRIVATE), one entry per
 * slot, value = base64(iv) + ":" + base64(ciphertext). The IV is random per write
 * (setRandomizedEncryptionRequired), so writing the same token twice yields different
 * bytes — no equality oracle on disk.
 *
 * Excluding this file from cloud backups is the host app's job (manifest
 * `allowBackup=false` or a dataExtractionRules exclusion) — a library cannot edit it.
 */
class TokenVaultException(val code: String, message: String) : Exception(message)

class TokenVault(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun set(name: String, value: String) {
        validate(name)
        if (value.isEmpty()) throw TokenVaultException("INVALID_ARGUMENT", "value must be a non-empty string")
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, secretKey())
            val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
            val encoded = "${base64(cipher.iv)}:${base64(ciphertext)}"
            if (!prefs.edit().putString(name, encoded).commit()) {
                throw TokenVaultException("STORAGE_FAILURE", "could not persist the token slot")
            }
        } catch (e: TokenVaultException) {
            throw e
        } catch (e: Exception) {
            throw TokenVaultException("STORAGE_FAILURE", "encryption failed (${e.javaClass.simpleName})")
        }
    }

    fun get(name: String): String? {
        validate(name)
        val encoded = prefs.getString(name, null) ?: return null
        val parts = encoded.split(":")
        if (parts.size != 2) {
            // Unreadable slot: drop it and report "absent" so a corrupt value cannot
            // lock the user out of signing in again.
            remove(name)
            return null
        }
        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(GCM_TAG_BITS, decode(parts[0])))
            String(cipher.doFinal(decode(parts[1])), Charsets.UTF_8)
        } catch (e: Exception) {
            // Key rotated / uninstalled-reinstalled / tampered ciphertext: same policy.
            remove(name)
            null
        }
    }

    fun remove(name: String) {
        validate(name)
        prefs.edit().remove(name).apply()
    }

    /** Removes every slot. The Keystore key is kept: a new sign-in reuses it. */
    fun clear() {
        prefs.edit().clear().apply()
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        return generateKey()
    }

    private fun generateKey(): SecretKey {
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            // A repeated IV under the same key breaks GCM; let the platform pick it.
            .setRandomizedEncryptionRequired(true)
            // No setUserAuthenticationRequired: a biometric gate is a session-policy
            // decision, not a storage one (docs/DESIGN.md non-goals).
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun validate(name: String) {
        if (!NAME_PATTERN.matches(name)) {
            throw TokenVaultException("INVALID_ARGUMENT", "token name must match ^[a-zA-Z0-9._-]{1,64}$")
        }
    }

    private fun base64(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.NO_WRAP)

    private fun decode(value: String) = Base64.decode(value, Base64.NO_WRAP)

    companion object {
        private const val PREFS_NAME = "token_vault"
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"

        /**
         * Versioned: changing key parameters later becomes a new alias plus a documented
         * migration, instead of silent decryption failures on existing installs.
         */
        private const val KEY_ALIAS = "capacitor.token-vault.v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_BITS = 128
        private val NAME_PATTERN = Regex("^[a-zA-Z0-9._-]{1,64}$")
    }
}
