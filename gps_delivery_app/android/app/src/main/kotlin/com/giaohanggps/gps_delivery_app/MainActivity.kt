package com.giaohanggps.gps_delivery_app

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WINDOW_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startOAuthKeepAlive" -> {
                        try {
                            val serviceIntent = Intent(this, OAuthKeepAliveService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(serviceIntent)
                            } else {
                                startService(serviceIntent)
                            }
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "stopOAuthKeepAlive" -> {
                        try {
                            stopService(Intent(this, OAuthKeepAliveService::class.java))
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    "focus" -> {
                        try {
                            val focusIntent = Intent(this, MainActivity::class.java).apply {
                                addFlags(
                                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                                )
                            }
                            startActivity(focusIntent)
                        } catch (_: Exception) {
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val WINDOW_CHANNEL = "ghst/window"
    }
}
