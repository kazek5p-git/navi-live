package com.navilive.android.data.location

import android.Manifest
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.ScanResult as WifiScanResult
import android.net.wifi.WifiManager
import android.os.Build
import android.os.SystemClock
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.resume

/**
 * Krótko skanuje radio tylko wtedy, gdy usługa lokalizacji o to poprosi.
 * Nie zbiera nazw sieci, treści reklam ani danych użytkownika.
 */
internal class AndroidRadioLocationProvider(
    context: Context,
) : RadioLocationProvider {

    private val appContext = context.applicationContext
    private val wifiManager = appContext.getSystemService(WifiManager::class.java)
    private val bluetoothManager = appContext.getSystemService(BluetoothManager::class.java)

    override suspend fun scan(): RadioObservationBatch = coroutineScope {
        val wifi = async { scanWifi() }
        val bluetooth = async { scanBluetooth() }
        val observations = (wifi.await() + bluetooth.await())
            .distinctBy { it.kind to it.identifier }
        RadioObservationBatch(
            observations = observations,
            capturedAtMs = System.currentTimeMillis(),
        )
    }

    private suspend fun scanWifi(): List<RadioObservation> {
        val manager = wifiManager ?: return emptyList()
        if (!hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)) return emptyList()
        if (!runCatching { manager.isWifiEnabled }.getOrDefault(false)) return emptyList()

        val freshResults = withTimeoutOrNull(RadioLocationConfig.scanWindowMs) {
            awaitWifiScan(manager)
        }.orEmpty()
        val results = freshResults.ifEmpty { readRecentWifiResults(manager) }
        return results
            .mapNotNull(::wifiObservation)
            .distinctBy { it.identifier }
            .sortedByDescending { it.signalStrengthDbm }
            .take(RadioLocationConfig.maximumWifiObservations)
    }

    @Suppress("DEPRECATION")
    private suspend fun awaitWifiScan(manager: WifiManager): List<WifiScanResult> =
        kotlinx.coroutines.suspendCancellableCoroutine { continuation ->
            lateinit var receiver: BroadcastReceiver
            var registered = false
            var finished = false

            fun unregister() {
                if (!registered) return
                registered = false
                runCatching { appContext.unregisterReceiver(receiver) }
            }

            fun finish(results: List<WifiScanResult>) {
                if (finished) return
                finished = true
                unregister()
                if (continuation.isActive) continuation.resume(results)
            }

            receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    if (intent.action != WifiManager.SCAN_RESULTS_AVAILABLE_ACTION) return
                    finish(readRecentWifiResults(manager))
                }
            }

            try {
                ContextCompat.registerReceiver(
                    appContext,
                    receiver,
                    IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION),
                    ContextCompat.RECEIVER_NOT_EXPORTED,
                )
                registered = true
                if (!manager.startScan()) {
                    finish(readRecentWifiResults(manager))
                }
            } catch (_: SecurityException) {
                finish(emptyList())
            } catch (_: RuntimeException) {
                finish(emptyList())
            }

            continuation.invokeOnCancellation { unregister() }
        }

    @Suppress("MissingPermission")
    private fun readRecentWifiResults(manager: WifiManager): List<WifiScanResult> {
        val nowElapsedMs = SystemClock.elapsedRealtime()
        return runCatching {
            manager.scanResults.filter { result ->
                val resultElapsedMs = result.timestamp / 1_000L
                resultElapsedMs <= 0L ||
                    nowElapsedMs - resultElapsedMs in 0..RadioLocationConfig.wifiResultMaxAgeMs
            }
        }.getOrDefault(emptyList())
    }

    private fun wifiObservation(result: WifiScanResult): RadioObservation? {
        val identifier = normalizeMac(result.BSSID) ?: return null
        return RadioObservation(
            kind = RadioObservationKind.WifiAccessPoint,
            identifier = identifier,
            signalStrengthDbm = result.level.coerceIn(-127, 0),
            observedAtMs = System.currentTimeMillis(),
        )
    }

    private suspend fun scanBluetooth(): List<RadioObservation> {
        if (!hasBluetoothPermission()) return emptyList()
        val adapter = runCatching { bluetoothManager?.adapter }.getOrNull() ?: return emptyList()
        if (!runCatching { adapter.isEnabled }.getOrDefault(false)) return emptyList()
        val scanner = runCatching { adapter.bluetoothLeScanner }.getOrNull() ?: return emptyList()
        val results = ConcurrentHashMap<String, RadioObservation>()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                if (!isBeaconAdvertisement(result)) return
                val identifier = normalizeMac(runCatching { result.device.address }.getOrNull()) ?: return
                results[identifier] = RadioObservation(
                    kind = RadioObservationKind.BluetoothBeacon,
                    identifier = identifier,
                    signalStrengthDbm = result.rssi.coerceIn(-127, 0),
                    observedAtMs = System.currentTimeMillis(),
                )
            }

            override fun onBatchScanResults(batchResults: MutableList<ScanResult>) {
                batchResults.forEach { onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, it) }
            }
        }
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_POWER)
            .build()

        return try {
            withContext(Dispatchers.Main.immediate) {
                scanner.startScan(null, settings, callback)
            }
            try {
                delay(RadioLocationConfig.scanWindowMs)
            } finally {
                withContext(Dispatchers.Main.immediate) {
                    scanner.stopScan(callback)
                }
            }
            results.values
                .sortedByDescending { it.signalStrengthDbm }
                .take(RadioLocationConfig.maximumBluetoothBeaconObservations)
        } catch (_: SecurityException) {
            emptyList()
        } catch (_: RuntimeException) {
            emptyList()
        }
    }

    private fun isBeaconAdvertisement(result: ScanResult): Boolean {
        val record = result.scanRecord ?: return false
        val manufacturerData = record.manufacturerSpecificData
        for (index in 0 until manufacturerData.size()) {
            val data = manufacturerData.valueAt(index) ?: continue
            if (isIBeaconData(data) || isAltBeaconData(data)) return true
        }
        return record.serviceUuids.orEmpty().any { uuid ->
            uuid.uuid.toString().startsWith("0000feaa-", ignoreCase = true)
        }
    }

    private fun isIBeaconData(data: ByteArray): Boolean {
        return data.size >= 2 &&
            data[0].toInt() and 0xff == 0x02 &&
            data[1].toInt() and 0xff == 0x15
    }

    private fun isAltBeaconData(data: ByteArray): Boolean {
        return data.size >= 2 &&
            data[0].toInt() and 0xff == 0xbe &&
            data[1].toInt() and 0xff == 0xac
    }

    private fun hasBluetoothPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return hasPermission(Manifest.permission.BLUETOOTH_SCAN) &&
            hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(appContext, permission) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun normalizeMac(value: String?): String? {
        val normalized = value?.trim()?.lowercase(Locale.ROOT) ?: return null
        if (!MacPattern.matches(normalized) || normalized == EmptyMac) return null
        return normalized
    }

    private companion object {
        val MacPattern = Regex("^[0-9a-f]{2}(:[0-9a-f]{2}){5}$")
        const val EmptyMac = "02:00:00:00:00:00"
    }
}
