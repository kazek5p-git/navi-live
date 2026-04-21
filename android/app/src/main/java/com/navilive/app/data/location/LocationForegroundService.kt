package com.navilive.app.data.location

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.navilive.app.MainActivity
import com.navilive.app.R
import com.navilive.app.model.GeoPoint
import com.navilive.app.model.LocationFix

class LocationForegroundService : Service() {

    private lateinit var fusedClient: FusedLocationProviderClient
    private var locationCallback: LocationCallback? = null
    private var isTracking = false

    override fun onCreate() {
        super.onCreate()
        fusedClient = LocationServices.getFusedLocationProviderClient(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startTracking()
            ACTION_STOP -> stopTracking()
            else -> startTracking()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopTracking()
        super.onDestroy()
    }

    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    @Suppress("MissingPermission")
    private fun startTracking() {
        if (isTracking) return
        if (!hasLocationPermission()) {
            stopSelf()
            return
        }

        val notification = buildNotification(getString(R.string.notification_tracking))
        startForeground(NOTIFICATION_ID, notification)
        LocationTrackerStore.setTracking(true)

        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 4_000L)
            .setMinUpdateIntervalMillis(2_000L)
            .setWaitForAccurateLocation(false)
            .build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val latest = result.lastLocation ?: return
                LocationTrackerStore.pushFix(
                    LocationFix(
                        point = GeoPoint(
                            latitude = latest.latitude,
                            longitude = latest.longitude,
                        ),
                        accuracyMeters = latest.accuracy,
                        timestampMs = latest.time,
                    ),
                )
            }
        }

        fusedClient.requestLocationUpdates(
            request,
            locationCallback!!,
            mainLooper,
        )
        isTracking = true
    }

    private fun stopTracking() {
        if (!isTracking) return
        locationCallback?.let { fusedClient.removeLocationUpdates(it) }
        locationCallback = null
        isTracking = false
        LocationTrackerStore.setTracking(false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun buildNotification(text: String) = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(android.R.drawable.ic_dialog_map)
        .setContentTitle(getString(R.string.app_name))
        .setContentText(text)
        .setContentIntent(openAppPendingIntent())
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setCategory(NotificationCompat.CATEGORY_SERVICE)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .build()

    private fun openAppPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            1001,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = getString(R.string.notification_channel_description)
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "navilive_location_tracking"
        private const val NOTIFICATION_ID = 2401
        const val ACTION_START = "com.navilive.app.location.START"
        const val ACTION_STOP = "com.navilive.app.location.STOP"

        fun startIntent(context: Context): Intent =
            Intent(context, LocationForegroundService::class.java).apply { action = ACTION_START }

        fun stopIntent(context: Context): Intent =
            Intent(context, LocationForegroundService::class.java).apply { action = ACTION_STOP }
    }
}
