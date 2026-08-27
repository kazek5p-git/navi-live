package com.navilive.android.data.location

import com.navilive.android.model.GeoPoint
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** Klient publicznego, eksperymentalnego API beaconDB. */
internal class BeaconDbClient(
    private val endpoint: String = DefaultEndpoint,
    private val nowMs: () -> Long = System::currentTimeMillis,
    private val postRequest: ((url: String, body: String, timeoutMs: Int) -> String)? = null,
) {

    private data class CachedLookup(
        val fingerprint: String,
        val expiresAtMs: Long,
        val estimate: RadioLocationEstimate,
    )

    private var cachedLookup: CachedLookup? = null

    suspend fun geolocate(batch: RadioObservationBatch): RadioLocationEstimate? {
        val observations = selectObservations(batch)
        if (observations.size < RadioLocationConfig.minimumObservationsForLookup ||
            observations.map { it.identifier }.distinct().size < RadioLocationConfig.minimumObservationsForLookup
        ) {
            return null
        }

        val fingerprint = fingerprint(observations)
        val now = nowMs()
        cachedLookup?.let { cached ->
            if (cached.fingerprint == fingerprint && now < cached.expiresAtMs) {
                return cached.estimate.copy(timestampMs = now)
            }
        }

        val body = buildRequestBody(observations)
        val response = withTimeoutOrNull(RadioLocationConfig.lookupTimeoutMs) {
            withContext(Dispatchers.IO) {
                runCatching {
                    postRequest?.invoke(endpoint, body, RadioLocationConfig.lookupTimeoutMs.toInt())
                        ?: postJson(endpoint, body, RadioLocationConfig.lookupTimeoutMs.toInt())
                }.getOrNull()
            }
        } ?: return null

        val estimate = BeaconDbResponseParser.parse(
            payload = response,
            observationCount = observations.size,
            wifiObservationCount = observations.count { it.kind == RadioObservationKind.WifiAccessPoint },
            bluetoothBeaconObservationCount = observations.count {
                it.kind == RadioObservationKind.BluetoothBeacon
            },
            timestampMs = now,
        ) ?: return null

        cachedLookup = CachedLookup(
            fingerprint = fingerprint,
            expiresAtMs = now + RadioLocationConfig.lookupCacheTtlMs,
            estimate = estimate,
        )
        return estimate
    }

    internal fun buildRequestBodyForTesting(batch: RadioObservationBatch): String {
        return buildRequestBody(selectObservations(batch))
    }

    private fun selectObservations(batch: RadioObservationBatch): List<RadioObservation> {
        return batch.observations
            .asSequence()
            .filter { it.identifier.isNotBlank() && it.signalStrengthDbm in -127..0 }
            .distinctBy { it.kind to it.identifier }
            .groupBy { it.kind }
            .flatMap { (kind, values) ->
                values.sortedByDescending { it.signalStrengthDbm }.take(
                    when (kind) {
                        RadioObservationKind.WifiAccessPoint ->
                            RadioLocationConfig.maximumWifiObservations
                        RadioObservationKind.BluetoothBeacon ->
                            RadioLocationConfig.maximumBluetoothBeaconObservations
                    },
                )
            }
            .sortedWith(compareBy<RadioObservation> { it.kind.ordinal }.thenByDescending { it.signalStrengthDbm })
            .toList()
    }

    private fun buildRequestBody(observations: List<RadioObservation>): String {
        val root = JSONObject()
        val wifi = JSONArray()
        val bluetooth = JSONArray()
        observations.forEach { observation ->
            val item = JSONObject()
                .put("macAddress", observation.identifier)
                .put("signalStrength", observation.signalStrengthDbm)
            when (observation.kind) {
                RadioObservationKind.WifiAccessPoint -> wifi.put(item)
                RadioObservationKind.BluetoothBeacon -> bluetooth.put(item)
            }
        }
        if (wifi.length() > 0) root.put("wifiAccessPoints", wifi)
        if (bluetooth.length() > 0) root.put("bluetoothBeacons", bluetooth)
        return root.toString()
    }

    private fun fingerprint(observations: List<RadioObservation>): String {
        val canonical = observations
            .sortedWith(compareBy<RadioObservation> { it.kind.ordinal }.thenBy { it.identifier })
            .joinToString("|") {
                "${it.kind.name}:${it.identifier}:${it.signalStrengthDbm}"
            }
        val digest = MessageDigest.getInstance("SHA-256").digest(canonical.toByteArray())
        return digest.joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun postJson(url: String, body: String, timeoutMs: Int): String {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = timeoutMs
            readTimeout = timeoutMs
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("User-Agent", "NaviLive/1.0 (beaconDB-helper)")
        }
        return try {
            connection.outputStream.bufferedWriter(Charsets.UTF_8).use { writer ->
                writer.write(body)
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val payload = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                throw IllegalStateException("beaconDB HTTP $status")
            }
            payload
        } finally {
            connection.disconnect()
        }
    }

    private companion object {
        const val DefaultEndpoint = "https://api.beacondb.net/v1/geolocate"
    }
}

internal object BeaconDbResponseParser {
    fun parse(
        payload: String,
        observationCount: Int,
        wifiObservationCount: Int,
        bluetoothBeaconObservationCount: Int,
        timestampMs: Long,
    ): RadioLocationEstimate? {
        val root = runCatching { JSONObject(payload) }.getOrNull() ?: return null
        val location = root.optJSONObject("location")
        val latitude = firstFinite(
            location?.optDouble("lat", Double.NaN),
            location?.optDouble("latitude", Double.NaN),
            root.optDouble("lat", Double.NaN),
            root.optDouble("latitude", Double.NaN),
        )
        val longitude = firstFinite(
            location?.optDouble("lng", Double.NaN),
            location?.optDouble("lon", Double.NaN),
            location?.optDouble("longitude", Double.NaN),
            root.optDouble("lng", Double.NaN),
            root.optDouble("lon", Double.NaN),
            root.optDouble("longitude", Double.NaN),
        )
        val accuracy = firstFinite(
            root.optDouble("accuracy", Double.NaN),
            location?.optDouble("accuracy", Double.NaN),
        )
        if (!latitude.isFinite() || latitude !in -90.0..90.0) return null
        if (!longitude.isFinite() || longitude !in -180.0..180.0) return null
        if (!accuracy.isFinite() || accuracy <= 0.0) return null
        if (observationCount < RadioLocationConfig.minimumObservationsForLookup) return null

        return RadioLocationEstimate(
            point = GeoPoint(latitude = latitude, longitude = longitude),
            accuracyMeters = accuracy.toFloat(),
            observationCount = observationCount,
            wifiObservationCount = wifiObservationCount,
            bluetoothBeaconObservationCount = bluetoothBeaconObservationCount,
            timestampMs = timestampMs,
        )
    }

    private fun firstFinite(vararg values: Double?): Double {
        return values.firstOrNull { it?.isFinite() == true } ?: Double.NaN
    }
}
