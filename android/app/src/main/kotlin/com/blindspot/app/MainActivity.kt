package com.blindspot.app

import android.media.MediaPlayer
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var player: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "vibrate" -> {
                        vibrate(call.argument<Int>("ms") ?: 0)
                        result.success(null)
                    }
                    "playAlarm" -> {
                        playAlarm()
                        result.success(null)
                    }
                    "stopAlarm" -> {
                        stopAlarm()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun vibrator(): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as? Vibrator
        }

    private fun vibrate(milliseconds: Int) {
        if (milliseconds <= 0) return
        val vibrator = vibrator() ?: return
        if (!vibrator.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createOneShot(
                    milliseconds.toLong(),
                    VibrationEffect.DEFAULT_AMPLITUDE
                )
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(milliseconds.toLong())
        }
    }

    private fun playAlarm() {
        stopAlarm()
        val created = MediaPlayer()
        try {
            created.setDataSource(alarmFile().absolutePath)
            created.setOnCompletionListener { completed ->
                completed.release()
                if (player === completed) player = null
            }
            created.prepare()
            player = created
            created.start()
        } catch (_: Exception) {
            created.release()
            if (player === created) player = null
        }
    }

    private fun stopAlarm() {
        player?.let { active ->
            try {
                if (active.isPlaying) active.stop()
            } catch (_: IllegalStateException) {
            }
            active.release()
        }
        player = null
        vibrator()?.cancel()
    }

    /// Copies the bundled alarm to the cache once, because MediaPlayer cannot
    /// open a Flutter asset path directly.
    private fun alarmFile(): File {
        val file = File(cacheDir, "alarm.mp3")
        if (!file.exists()) {
            assets.open("flutter_assets/assets/audio/alarm.mp3").use { input ->
                file.outputStream().use { output -> input.copyTo(output) }
            }
        }
        return file
    }

    private companion object {
        const val CHANNEL = "blindspot/system"
    }
}
