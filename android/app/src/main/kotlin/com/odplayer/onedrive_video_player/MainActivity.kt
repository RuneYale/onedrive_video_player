package com.odplayer.onedrive_video_player

import android.media.AudioManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
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