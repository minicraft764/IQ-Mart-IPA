package scar.iqmart.sa

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.ecommerce/notifications"
    private val LOCATION_REQ_CODE = 2001
    private var pendingLocationResult: MethodChannel.Result? = null
    private var pendingProductId: String? = null
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize notification channel for push alerts
        DiscountNotificationHelper.createNotificationChannel(this)

        // Subscribe to Firebase Cloud Messaging (FCM) topics for instant discount broadcasts
        try {
            com.google.firebase.messaging.FirebaseMessaging.getInstance().subscribeToTopic("iqmart_discounts")
                .addOnCompleteListener { task ->
                    if (task.isSuccessful) {
                        Log.d("FCM", "Subscribed to iqmart_discounts topic successfully!")
                    }
                }
            com.google.firebase.messaging.FirebaseMessaging.getInstance().subscribeToTopic("all")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error subscribing to FCM topics", e)
        }

        // Cancel any legacy polling alarms so bandwidth is completely preserved
        DiscountNotificationHelper.cancelAlarms(this)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "IQ Mart Offer"
                    val body = call.argument<String>("body") ?: ""
                    val id = call.argument<Int>("id") ?: title.hashCode()
                    val productId = call.argument<String>("productId")

                    DiscountNotificationHelper.showSystemNotification(this, id, title, body, productId)
                    result.success(true)
                }
                "setLanguage" -> {
                    val lang = call.argument<String>("lang") ?: "en"
                    val prefs = getSharedPreferences("iqmart_prefs", Context.MODE_PRIVATE)
                    prefs.edit().putString("lang", lang).apply()
                    result.success(true)
                }
                "share" -> {
                    val title = call.argument<String>("title") ?: ""
                    val text = call.argument<String>("text") ?: ""
                    val url = call.argument<String>("url") ?: ""
                    val sendIntent = Intent().apply {
                        action = Intent.ACTION_SEND
                        val fullText = buildString {
                            if (title.isNotEmpty()) append(title).append("\n")
                            if (text.isNotEmpty()) append(text).append("\n")
                            if (url.isNotEmpty()) append(url)
                        }.trim()
                        putExtra(Intent.EXTRA_TEXT, fullText)
                        if (title.isNotEmpty()) {
                            putExtra(Intent.EXTRA_SUBJECT, title)
                        }
                        type = "text/plain"
                    }
                    val shareIntent = Intent.createChooser(sendIntent, title.ifEmpty { "Share via" }).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(shareIntent)
                    result.success(true)
                }
                "getPendingProduct" -> {
                    val p = pendingProductId
                    pendingProductId = null
                    result.success(p)
                }
                "getLocation" -> {
                    handleGetLocation(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        handleIntent(intent)
    }

    private fun handleGetLocation(result: MethodChannel.Result) {
        val fineGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarseGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

        if (!fineGranted && !coarseGranted) {
            pendingLocationResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                LOCATION_REQ_CODE
            )
        } else {
            fetchCurrentLocation(result)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LOCATION_REQ_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            val res = pendingLocationResult
            pendingLocationResult = null
            if (granted && res != null) {
                fetchCurrentLocation(res)
            } else {
                res?.success(mapOf("success" to false, "error" to "Location permission was denied"))
            }
        }
    }

    private fun fetchCurrentLocation(result: MethodChannel.Result) {
        try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            if (lm == null) {
                result.success(mapOf("success" to false, "error" to "Location manager not available"))
                return
            }

            var bestLoc: Location? = null
            try {
                if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    bestLoc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                }
            } catch (_: SecurityException) {}

            try {
                if (bestLoc == null && lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    bestLoc = lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                }
            } catch (_: SecurityException) {}

            try {
                if (bestLoc == null) {
                    bestLoc = lm.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER)
                }
            } catch (_: SecurityException) {}

            // If last known location is fresh (< 3 minutes), return immediately
            if (bestLoc != null && (System.currentTimeMillis() - bestLoc.time) < 180000) {
                result.success(mapOf(
                    "success" to true,
                    "latitude" to bestLoc.latitude,
                    "longitude" to bestLoc.longitude
                ))
                return
            }

            var hasAnswered = false
            val mainHandler = Handler(Looper.getMainLooper())

            val listener = object : LocationListener {
                override fun onLocationChanged(loc: Location) {
                    if (!hasAnswered) {
                        hasAnswered = true
                        try { lm.removeUpdates(this) } catch (_: Exception) {}
                        result.success(mapOf(
                            "success" to true,
                            "latitude" to loc.latitude,
                            "longitude" to loc.longitude
                        ))
                    }
                }
                override fun onStatusChanged(p: String?, s: Int, b: Bundle?) {}
                override fun onProviderEnabled(p: String) {}
                override fun onProviderDisabled(p: String) {}
            }

            // 10-second timeout fallback
            mainHandler.postDelayed({
                if (!hasAnswered) {
                    hasAnswered = true
                    try { lm.removeUpdates(listener) } catch (_: Exception) {}
                    if (bestLoc != null) {
                        result.success(mapOf(
                            "success" to true,
                            "latitude" to bestLoc.latitude,
                            "longitude" to bestLoc.longitude
                        ))
                    } else {
                        result.success(mapOf(
                            "success" to false,
                            "error" to "Location request timed out. Please ensure GPS is enabled."
                        ))
                    }
                }
            }, 10000)

            var requested = false
            try {
                if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 0L, 0f, listener, Looper.getMainLooper())
                    requested = true
                }
            } catch (_: SecurityException) {}

            try {
                if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 0L, 0f, listener, Looper.getMainLooper())
                    requested = true
                }
            } catch (_: SecurityException) {}

            if (!requested && bestLoc != null) {
                hasAnswered = true
                result.success(mapOf(
                    "success" to true,
                    "latitude" to bestLoc.latitude,
                    "longitude" to bestLoc.longitude
                ))
            } else if (!requested) {
                hasAnswered = true
                result.success(mapOf(
                    "success" to false,
                    "error" to "GPS and Network location providers are disabled. Please enable Location in phone settings."
                ))
            }
        } catch (e: Exception) {
            result.success(mapOf("success" to false, "error" to (e.message ?: "Failed to get location")))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val extras = intent?.extras
        var linkUrl = intent?.getStringExtra("link")
            ?: intent?.getStringExtra("url")
            ?: intent?.getStringExtra("target_url")
            ?: extras?.getString("link")
            ?: extras?.getString("url")
            ?: extras?.getString("target_url")
            ?: intent?.dataString

        val prodId = intent?.getStringExtra("product_id")
            ?: extras?.getString("product_id")

        if (!linkUrl.isNullOrEmpty()) {
            val validUrl = if (!linkUrl.startsWith("http://") && !linkUrl.startsWith("https://")) {
                "https://$linkUrl"
            } else {
                linkUrl
            }
            try {
                val browserIntent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(validUrl)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(browserIntent)
            } catch (e: Exception) {
                Log.e("MainActivity", "Error opening browser link: $validUrl", e)
            }
        } else if (!prodId.isNullOrEmpty()) {
            pendingProductId = prodId
            methodChannel?.invokeMethod("openProduct", prodId)
        }
    }
}
