package com.giaohanggps.gps_delivery_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class OAuthKeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int) {
        stopSelf()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager?.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Xác thực đăng nhập GHST",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    setShowBadge(false)
                }
                manager?.createNotificationChannel(channel)
            }
            return Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("GHST EXPRESS")
                .setContentText("Đang hoàn tất đăng nhập Google...")
                .setOngoing(true)
                .build()
        }
        @Suppress("DEPRECATION")
        return Notification.Builder(this)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("GHST EXPRESS")
            .setContentText("Đang hoàn tất đăng nhập Google...")
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "ghst_oauth_keepalive"
        private const val NOTIFICATION_ID = 8766
    }
}
