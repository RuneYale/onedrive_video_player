package com.odplayer.onedrive_video_player

import android.media.AudioManager
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Player brightness gestures. Uses the per-window brightness override
        // (WindowManager.LayoutParams.screenBrightness), which needs no
        // WRITE_SETTINGS permission and only affects this activity.
        MethodChannel(messenger, "com.example.app/brightness").setMethodCallHandler { call, result ->
            when (call.method) {
                "getBrightness" -> result.success(readBrightness())
                "setBrightness" -> {
                    val value = call.argument<Double>("value")
                    if (value == null) {
                        result.error("bad_args", "missing 'value'", null)
                    } else {
                        val attrs = window.attributes
                        attrs.screenBrightness = value.toFloat().coerceIn(0f, 1f)
                        window.attributes = attrs
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Player volume gestures. Maps the music stream's discrete steps to a
        // 0.0-1.0 ratio so the Dart side stays platform-agnostic.
        MethodChannel(messenger, "com.example.app/volume").setMethodCallHandler { call, result ->
            val audio = getSystemService(AUDIO_SERVICE) as AudioManager
            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            when (call.method) {
                "getVolume" -> {
                    val current = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                    result.success(if (max > 0) current / max.toDouble() else 0.0)
                }
                "setVolume" -> {
                    val value = call.argument<Double>("value")
                    if (value == null) {
                        result.error("bad_args", "missing 'value'", null)
                    } else {
                        val index = (value.coerceIn(0.0, 1.0) * max).roundToInt()
                        audio.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Token storage: AES-GCM with a key held by the Android Keystore. Only
        // the ciphertext is written to a private preferences file; the key
        // never leaves the Keystore, so a copied file is useless elsewhere.
        MethodChannel(messenger, "odplayer/secure").setMethodCallHandler { call, result ->
            val key = call.argument<String>("key")
            if (key == null) {
                result.error("bad_args", "missing 'key'", null)
                return@setMethodCallHandler
            }
            try {
                when (call.method) {
                    "read" -> result.success(secureRead(key))
                    "write" -> {
                        val value = call.argument<String>("value")
                        if (value == null) {
                            result.error("bad_args", "missing 'value'", null)
                        } else {
                            secureWrite(key, value)
                            result.success(null)
                        }
                    }
                    "delete" -> {
                        secureDelete(key)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("secure_error", e.message, null)
            }
        }
    }

    // --- Secure token storage (Android Keystore) ----------------------------

    private val securePrefs by lazy {
        getSharedPreferences("odvp_secure", MODE_PRIVATE)
    }

    // Get-or-create the AES key. Rotating the alias would orphan old values,
    // which is fine: they just become unreadable and the user signs in again.
    private fun secureKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getEntry(SECURE_KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey

        val generator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                SECURE_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    // Stored as "base64(iv):base64(ciphertext)".
    private fun secureRead(key: String): String? {
        val stored = securePrefs.getString(key, null) ?: return null
        val parts = stored.split(":")
        if (parts.size != 2) return null
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val iv = Base64.decode(parts[0], Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, secureKey(), GCMParameterSpec(128, iv))
            val plain = cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP))
            String(plain, Charsets.UTF_8)
        } catch (e: Exception) {
            // Key invalidated (device lock change) or corrupt value: behave as
            // "not stored" so the app returns to the sign-in screen.
            null
        }
    }

    private fun secureWrite(key: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secureKey())
        val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val stored =
            Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
                Base64.encodeToString(ciphertext, Base64.NO_WRAP)
        securePrefs.edit().putString(key, stored).apply()
    }

    private fun secureDelete(key: String) {
        securePrefs.edit().remove(key).apply()
    }

    private companion object {
        const val SECURE_KEY_ALIAS = "odvp_secure_v1"
    }

    // Current brightness as a 0.0-1.0 ratio. The window override is -1
    // ("follow system") until setBrightness is called, so fall back to the
    // system brightness (reading it needs no permission).
    private fun readBrightness(): Double {
        val windowValue = window.attributes.screenBrightness
        if (windowValue >= 0f) return windowValue.toDouble()
        return try {
            val system = Settings.System.getInt(
                contentResolver,
                Settings.System.SCREEN_BRIGHTNESS,
            )
            (system / 255.0).coerceIn(0.0, 1.0)
        } catch (e: Settings.SettingNotFoundException) {
            0.5
        }
    }
}