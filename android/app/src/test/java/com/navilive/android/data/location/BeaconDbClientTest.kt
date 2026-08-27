package com.navilive.android.data.location

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class BeaconDbClientTest {
    @Test
    fun requestContainsOnlySupportedRadioIdentifiers() {
        val client = BeaconDbClient()
        val body = JSONObject(
            client.buildRequestBodyForTesting(
                batch(
                    observation(
                        kind = RadioObservationKind.WifiAccessPoint,
                        identifier = "aa:bb:cc:dd:ee:ff",
                        signalStrengthDbm = -48,
                    ),
                    observation(
                        kind = RadioObservationKind.BluetoothBeacon,
                        identifier = "11:22:33:44:55:66",
                        signalStrengthDbm = -70,
                    ),
                ),
            ),
        )

        val wifi = body.getJSONArray("wifiAccessPoints")
        val bluetooth = body.getJSONArray("bluetoothBeacons")
        assertEquals("aa:bb:cc:dd:ee:ff", wifi.getJSONObject(0).getString("macAddress"))
        assertEquals(-48, wifi.getJSONObject(0).getInt("signalStrength"))
        assertEquals("11:22:33:44:55:66", bluetooth.getJSONObject(0).getString("macAddress"))
        assertEquals(-70, bluetooth.getJSONObject(0).getInt("signalStrength"))
    }

    @Test
    fun lookupIsSkippedForOneObservation() = runBlocking {
        var requestCount = 0
        val client = BeaconDbClient(
            postRequest = { _, _, _ ->
                requestCount += 1
                response()
            },
        )

        val estimate = client.geolocate(
            batch(
                observation(
                    kind = RadioObservationKind.WifiAccessPoint,
                    identifier = "aa:bb:cc:dd:ee:ff",
                    signalStrengthDbm = -48,
                ),
            ),
        )

        assertNull(estimate)
        assertEquals(0, requestCount)
    }

    @Test
    fun successfulLookupIsCachedForSameObservationSet() = runBlocking {
        var now = 1_000L
        var requestCount = 0
        val client = BeaconDbClient(
            nowMs = { now },
            postRequest = { _, _, _ ->
                requestCount += 1
                response()
            },
        )
        val observations = batch(
            observation(
                kind = RadioObservationKind.WifiAccessPoint,
                identifier = "aa:bb:cc:dd:ee:ff",
                signalStrengthDbm = -48,
            ),
            observation(
                kind = RadioObservationKind.WifiAccessPoint,
                identifier = "aa:bb:cc:dd:ee:01",
                signalStrengthDbm = -65,
            ),
        )

        val first = client.geolocate(observations)
        now += RadioLocationConfig.lookupCacheTtlMs - 1
        val second = client.geolocate(observations)

        assertNotNull(first)
        assertNotNull(second)
        assertEquals(1, requestCount)
        assertEquals(now, second?.timestampMs)
    }

    @Test
    fun cacheExpiresAfterConfiguredTtl() = runBlocking {
        var now = 1_000L
        var requestCount = 0
        val client = BeaconDbClient(
            nowMs = { now },
            postRequest = { _, _, _ ->
                requestCount += 1
                response()
            },
        )
        val observations = batch(
            observation(
                kind = RadioObservationKind.WifiAccessPoint,
                identifier = "aa:bb:cc:dd:ee:ff",
                signalStrengthDbm = -48,
            ),
            observation(
                kind = RadioObservationKind.WifiAccessPoint,
                identifier = "aa:bb:cc:dd:ee:01",
                signalStrengthDbm = -65,
            ),
        )

        client.geolocate(observations)
        now += RadioLocationConfig.lookupCacheTtlMs
        client.geolocate(observations)

        assertEquals(2, requestCount)
    }

    @Test
    fun responseParserAcceptsNestedLocationAndRejectsInvalidCoordinates() {
        val parsed = BeaconDbResponseParser.parse(
            payload = response(),
            observationCount = 2,
            wifiObservationCount = 2,
            bluetoothBeaconObservationCount = 0,
            timestampMs = 5_000L,
        )
        val invalid = BeaconDbResponseParser.parse(
            payload = JSONObject()
                .put("location", JSONObject().put("lat", 95.0).put("lng", 19.0))
                .put("accuracy", 30.0)
                .toString(),
            observationCount = 2,
            wifiObservationCount = 2,
            bluetoothBeaconObservationCount = 0,
            timestampMs = 5_000L,
        )

        assertEquals(51.759, parsed?.point?.latitude ?: 0.0, 0.000001)
        assertEquals(19.456, parsed?.point?.longitude ?: 0.0, 0.000001)
        assertEquals(35f, parsed?.accuracyMeters ?: 0f)
        assertNull(invalid)
    }

    private fun batch(vararg observations: RadioObservation): RadioObservationBatch {
        return RadioObservationBatch(observations = observations.toList(), capturedAtMs = 1_000L)
    }

    private fun response(): String {
        return JSONObject()
            .put("location", JSONObject().put("lat", 51.759).put("lng", 19.456))
            .put("accuracy", 35.0)
            .put("source", JSONArray().put("beaconDB"))
            .toString()
    }

    private fun observation(
        kind: RadioObservationKind,
        identifier: String,
        signalStrengthDbm: Int,
    ): RadioObservation {
        return RadioObservation(
            kind = kind,
            identifier = identifier,
            signalStrengthDbm = signalStrengthDbm,
            observedAtMs = 1_000L,
        )
    }
}
