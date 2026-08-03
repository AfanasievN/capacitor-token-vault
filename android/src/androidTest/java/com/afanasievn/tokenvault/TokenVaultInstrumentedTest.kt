package com.afanasievn.tokenvault

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumented on purpose: AndroidKeyStore has no JVM implementation, so a Robolectric
 * test would prove nothing about the thing this class exists for.
 */
@RunWith(AndroidJUnit4::class)
class TokenVaultInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var vault: TokenVault

    @Before
    fun setUp() {
        vault = TokenVault(context)
        vault.clear()
    }

    @After
    fun tearDown() {
        vault.clear()
    }

    @Test
    fun roundTrip() {
        vault.set("refresh", "rt-1")
        assertEquals("rt-1", vault.get("refresh"))
    }

    @Test
    fun missingSlotReadsAsNull() {
        assertNull(vault.get("refresh"))
    }

    @Test
    fun namedSlotsAreIndependent() {
        vault.set("refresh", "a")
        vault.set("secondary", "b")
        assertEquals("a", vault.get("refresh"))
        assertEquals("b", vault.get("secondary"))
    }

    @Test
    fun clearRemovesEverySlot() {
        vault.set("refresh", "a")
        vault.set("secondary", "b")
        vault.clear()
        assertNull(vault.get("refresh"))
        assertNull(vault.get("secondary"))
    }

    /** A new instance must decrypt what the previous one wrote - the key is in the Keystore,
     *  not in the process. This is what makes "session survives restart" true. */
    @Test
    fun anotherInstanceReadsTheSameValue() {
        vault.set("refresh", "rt-1")
        assertEquals("rt-1", TokenVault(context).get("refresh"))
    }

    /** Randomized IV: the same plaintext must not produce the same stored bytes. */
    @Test
    fun cipherTextDiffersPerWrite() {
        val prefs = context.getSharedPreferences("token_vault", android.content.Context.MODE_PRIVATE)

        vault.set("refresh", "same-token")
        val first = prefs.getString("refresh", null)
        vault.set("refresh", "same-token")
        val second = prefs.getString("refresh", null)

        assertNotEquals(first, second)
    }

    /** The stored form must not contain the plaintext anywhere. */
    @Test
    fun storedValueIsNotPlaintext() {
        val secret = "super-secret-token"
        vault.set("refresh", secret)

        val stored = context
            .getSharedPreferences("token_vault", android.content.Context.MODE_PRIVATE)
            .getString("refresh", null)

        assert(stored != null && !stored.contains(secret))
    }

    /**
     * hardwareBacked must report what the Keystore says - not a constant. Emulators
     * typically answer false, real devices true, so the assertion is "matches an
     * independently asked platform", which is what catches a regression to `true`.
     */
    @Test
    fun hardwareBackedMatchesTheKeystore() {
        vault.set("refresh", "rt")

        val keyStore = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = (keyStore.getEntry("capacitor.token-vault.v1", null) as java.security.KeyStore.SecretKeyEntry).secretKey
        val info = javax.crypto.SecretKeyFactory
            .getInstance(key.algorithm, "AndroidKeyStore")
            .getKeySpec(key, android.security.keystore.KeyInfo::class.java) as android.security.keystore.KeyInfo
        val expected = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            info.securityLevel == android.security.keystore.KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT ||
                info.securityLevel == android.security.keystore.KeyProperties.SECURITY_LEVEL_STRONGBOX
        } else {
            @Suppress("DEPRECATION") info.isInsideSecureHardware
        }

        assertEquals(expected, vault.isHardwareBacked())
    }

    @Test(expected = TokenVaultException::class)
    fun rejectsMalformedName() {
        vault.set("bad name!", "rt")
    }

    @Test(expected = TokenVaultException::class)
    fun rejectsEmptyValue() {
        vault.set("refresh", "")
    }

    /** A corrupted slot degrades to "absent" instead of throwing - a broken value must not
     *  prevent a fresh sign-in. */
    @Test
    fun corruptSlotReadsAsNull() {
        vault.set("refresh", "rt")
        context.getSharedPreferences("token_vault", android.content.Context.MODE_PRIVATE)
            .edit().putString("refresh", "not-base64-at-all").commit()

        assertNull(vault.get("refresh"))
    }
}
