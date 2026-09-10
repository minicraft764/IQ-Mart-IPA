package scar.iqmart.sa

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MyFirebaseMessagingService : FirebaseMessagingService() {
    companion object {
        private const val TAG = "MyFirebaseMsgService"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        Log.d(TAG, "From: ${remoteMessage.from}")

        val data = remoteMessage.data
        val notification = remoteMessage.notification

        val title = notification?.title
            ?: data["title"]
            ?: "IQ Mart Offer"
        val body = notification?.body
            ?: data["body"]
            ?: ""
        val productId = data["product_id"]
            ?: data["productId"]
            ?: ""
        val link = data["link"]
            ?: data["url"]
            ?: data["target_url"]
            ?: ""

        val id = (System.currentTimeMillis() % 100000).toInt()
        DiscountNotificationHelper.showSystemNotification(
            applicationContext,
            id,
            title,
            body,
            productId.ifEmpty { null },
            link.ifEmpty { null }
        )
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "Refreshed FCM token: $token")
    }
}
