package com.lifepilot.app.lifepilot_ai

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Provides the 256-bit key LifePilot uses to encrypt its records file and
 * receipt photos. The key is stored wrapped (AES-GCM) by a key that lives in
 * the Android Keystore, which is hardware-backed on most phones and cannot be
 * exported. Neither key leaves the device or is included in backups.
 */
object DeviceKey {
    private const val KEYSTORE = "AndroidKeyStore"
    private const val ALIAS = "lifepilot_data_wrapping_key"
    private const val PREFS = "lifepilot_security"
    private const val WRAPPED = "wrapped_data_key"

    @Synchronized
    fun dataKey(context: Context): ByteArray {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        val stored = prefs.getString(WRAPPED, null)
        if (stored != null) {
            // Never replace an existing key: data sealed with it would be lost.
            val wrappingKey = keyStore.getKey(ALIAS, null) as? SecretKey
                ?: throw IllegalStateException("Wrapping key is missing")
            val bytes = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, wrappingKey, GCMParameterSpec(128, bytes, 0, 12))
            return cipher.doFinal(bytes, 12, bytes.size - 12)
        }
        if (!keyStore.containsAlias(ALIAS)) {
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
            generator.init(
                KeyGenParameterSpec.Builder(
                    ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build(),
            )
            generator.generateKey()
        }
        val wrappingKey = keyStore.getKey(ALIAS, null) as SecretKey
        val dataKey = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey)
        val wrapped = cipher.iv + cipher.doFinal(dataKey)
        val saved = prefs.edit()
            .putString(WRAPPED, Base64.encodeToString(wrapped, Base64.NO_WRAP))
            .commit()
        if (!saved) throw IllegalStateException("Could not save the data key")
        return dataKey
    }
}
