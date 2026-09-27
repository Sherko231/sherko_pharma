package com.samo.sherkopharma

import android.media.AudioManager
import android.media.ToneGenerator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val SCANNER_FEEDBACK_CHANNEL =
            "com.samo.sherkopharma/scanner_feedback"
    }

    private var scannerTone: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCANNER_FEEDBACK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "playSuccessBeep" -> {
                    playSuccessBeep()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun playSuccessBeep() {
        val tone = scannerTone ?: ToneGenerator(
            AudioManager.STREAM_MUSIC,
            100,
        ).also { scannerTone = it }

        tone.stopTone()
        tone.startTone(ToneGenerator.TONE_PROP_BEEP, 160)
    }

    override fun onDestroy() {
        scannerTone?.release()
        scannerTone = null
        super.onDestroy()
    }
}
