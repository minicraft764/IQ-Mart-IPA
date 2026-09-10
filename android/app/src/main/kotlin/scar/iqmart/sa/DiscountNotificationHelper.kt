package scar.iqmart.sa

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import org.json.JSONArray
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.regex.Pattern

object DiscountNotificationHelper {
    private const val TAG = "DiscountNotifHelper"
    const val NOTIFICATION_CHANNEL_ID = "iqmart_offers_channel"
    private const val PREFS_NAME = "iqmart_discounts"
    private const val APP_PREFS = "iqmart_prefs"

    // In-memory deduplication cache: prevents duplicate notification within 3 minutes
    private val recentIdNotifications = ConcurrentHashMap<Int, Long>()
    private val recentTitleNotifications = ConcurrentHashMap<String, Long>()

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Offers & Discounts"
            val descriptionText = "Notifications for special discounts and offers"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                enableVibration(true)
            }
            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun showSystemNotification(context: Context, id: Int, title: String, body: String, productId: String? = null, link: String? = null) {
        val now = System.currentTimeMillis()
        val stableId = if (id != 0) Math.abs(id) else Math.abs(body.hashCode())

        // 1. Deduplicate by stable ID (3 minutes window)
        val lastIdTime = recentIdNotifications[stableId]
        if (lastIdTime != null && (now - lastIdTime) < 180000) {
            Log.d(TAG, "Ignoring duplicate notification by ID: $stableId")
            return
        }

        // 2. Deduplicate by clean body/title text (3 minutes window)
        val cleanKey = body.replace(Regex("[^a-zA-Z0-9\\u0600-\\u06FF]"), "").lowercase()
        if (cleanKey.isNotEmpty()) {
            val lastKeyTime = recentTitleNotifications[cleanKey]
            if (lastKeyTime != null && (now - lastKeyTime) < 180000) {
                Log.d(TAG, "Ignoring duplicate notification by text: $cleanKey")
                return
            }
            recentTitleNotifications[cleanKey] = now
        }
        recentIdNotifications[stableId] = now

        createNotificationChannel(context)

        val intent = if (!link.isNullOrEmpty()) {
            val validUrl = if (!link.startsWith("http://") && !link.startsWith("https://")) {
                "https://$link"
            } else {
                link
            }
            Intent(Intent.ACTION_VIEW, Uri.parse(validUrl)).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
        } else {
            Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                if (!productId.isNullOrEmpty()) {
                    putExtra("product_id", productId)
                }
            }
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            stableId,
            intent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )

        // Use the official app icon for both small status-bar icon and large expanded notification card icon
        val largeAppIcon = try {
            BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)
        } catch (_: Exception) {
            null
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setAutoCancel(true)
            .setPriority(Notification.PRIORITY_HIGH)
            .setDefaults(Notification.DEFAULT_ALL)
            .setContentIntent(pendingIntent)

        if (largeAppIcon != null) {
            builder.setLargeIcon(largeAppIcon)
        }

        val notification = builder.build()

        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(stableId, notification)
        Log.d(TAG, "Notification displayed with app icon: $title -> $body (product: $productId)")
    }

    fun cancelAlarms(context: Context) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, DiscountCheckReceiver::class.java).apply {
                action = "scar.iqmart.sa.CHECK_DISCOUNTS"
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                1001,
                intent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
            )
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            Log.d(TAG, "All background polling alarms cancelled successfully.")
        } catch (e: Exception) {
            Log.e(TAG, "Error cancelling alarms", e)
        }
    }
}

class DiscountCheckReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null) return
        if (intent?.action == "scar.iqmart.sa.TEST_NOTIFICATION") {
            val title = intent.getStringExtra("title") ?: "🔥 Special Offer & Discount!"
            val body = intent.getStringExtra("body") ?: "25% OFF on iPhone 17 Pro Max! Check it out now."
            val productId = intent.getStringExtra("product_id") ?: ""
            val dynamicId = (System.currentTimeMillis() % 100000).toInt()
            DiscountNotificationHelper.showSystemNotification(context, dynamicId, title, body, productId)
        }
    }
}

