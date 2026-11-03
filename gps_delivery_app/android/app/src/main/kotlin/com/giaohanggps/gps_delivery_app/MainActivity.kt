package com.giaohanggps.gps_delivery_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensurePushChannel()
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
                    "areNotificationsEnabled" -> {
                        result.success(areNotificationsPermitted())
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                                PackageManager.PERMISSION_GRANTED
                            ) {
                                result.success(areNotificationsPermitted())
                            } else {
                                pendingNotificationPermissionResult?.success(false)
                                pendingNotificationPermissionResult = result
                                requestPermissions(
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    REQUEST_POST_NOTIFICATIONS,
                                )
                            }
                        } else {
                            result.success(areNotificationsPermitted())
                        }
                    }
                    "showLocalNotification" -> {
                        val title = call.argument<String>("title")?.trim().orEmpty()
                            .ifEmpty { "GHST EXPRESS" }
                        val body = call.argument<String>("body")?.trim().orEmpty()
                        val idKey = call.argument<String>("id")?.trim().orEmpty()
                        result.success(showPushAlert(title, body, idKey))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_POST_NOTIFICATIONS) {
            val callback = pendingNotificationPermissionResult
            pendingNotificationPermissionResult = null
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED &&
                areNotificationsPermitted()
            callback?.success(granted)
        }
    }

    private fun areNotificationsPermitted(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val manager = getSystemService(NotificationManager::class.java)
            return manager?.areNotificationsEnabled() != false
        }
        return true
    }

    private fun ensurePushChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(PUSH_CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    PUSH_CHANNEL_ID,
                    "Thông báo đơn hàng & khuyến mãi",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Cập nhật trạng thái vận đơn, đơn mua sắm và ưu đãi GHST EXPRESS"
                    enableVibration(true)
                    setShowBadge(true)
                }
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun showPushAlert(title: String, body: String, idKey: String): Boolean {
        if (body.isEmpty() || !areNotificationsPermitted()) return false
        return try {
            ensurePushChannel()
            val manager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                getSystemService(NotificationManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                getSystemService(NOTIFICATION_SERVICE) as? NotificationManager
            } ?: return false

            val launchIntent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val notificationId = if (idKey.isNotEmpty()) {
                ((idKey.hashCode() and 0x7fffffff) % 900000) + 10000
            } else {
                ((System.currentTimeMillis().toInt() and 0x7fffffff) % 900000) + 10000
            }
            val pendingIntent = PendingIntent.getActivity(
                this,
                notificationId,
                launchIntent,
                pendingFlags,
            )

            val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, PUSH_CHANNEL_ID)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setStyle(Notification.BigTextStyle().bigText(body))
                    .setAutoCancel(true)
                    .setContentIntent(pendingIntent)
                    .build()
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setStyle(Notification.BigTextStyle().bigText(body))
                    .setPriority(Notification.PRIORITY_HIGH)
                    .setAutoCancel(true)
                    .setContentIntent(pendingIntent)
                    .build()
            }
            manager.notify(notificationId, notification)
            true
        } catch (_: Exception) {
            false
        }
    }

    companion object {
        private const val WINDOW_CHANNEL = "ghst/window"
        private const val PUSH_CHANNEL_ID = "ghst_push_alerts"
        private const val REQUEST_POST_NOTIFICATIONS = 8801
    }
}
