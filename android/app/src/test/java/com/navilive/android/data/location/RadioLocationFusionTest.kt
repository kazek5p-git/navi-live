package com.navilive.android.data.location

import com.navilive.android.model.GeoPoint
import com.navilive.android.model.LocationFix
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RadioLocationFusionTest {
    @Test
    fun goodGpsIsNeverChangedByRadioEstimate() {
        val result = RadioLocationFusion.fuse(
            gpsFix = fix(51.0, 19.0, accuracy = 20f, timestampMs = 1_000L),
            radioEstimate = estimate(51.0003, 19.0003, accuracy = 30f),
            nowMs = 2_000L,
        )

        assertNull(result)
    }

    @Test
    fun singleObservationCannotChangeWeakGps() {
        val result = RadioLocationFusion.fuse(
            gpsFix = fix(51.0, 19.0, accuracy = 90f, timestampMs = 1_000L),
            radioEstimate = estimate(51.0003, 19.0003, accuracy = 30f, observationCount = 1),
            nowMs = 2_000L,
        )

        assertNull(result)
    }

    @Test
    fun distantRadioEstimateIsRejected() {
        val result = RadioLocationFusion.fuse(
            gpsFix = fix(51.0, 19.0, accuracy = 90f, timestampMs = 1_000L),
            radioEstimate = estimate(51.002, 19.002, accuracy = 40f),
            nowMs = 2_000L,
        )

        assertNull(result)
    }

    @Test
    fun agreedRadioEstimateMakesOnlyBoundedCorrection() {
        val gps = fix(51.0, 19.0, accuracy = 90f, timestampMs = 1_000L)
        val result = RadioLocationFusion.fuse(
            gpsFix = gps,
            radioEstimate = estimate(51.00045, 19.00045, accuracy = 50f),
            nowMs = 2_000L,
        )

        assertNotNull(result)
        assertTrue(result!!.point.latitude > gps.point.latitude)
        assertTrue(result.point.longitude > gps.point.longitude)
        assertTrue(result.point.latitude < 51.00045)
        assertTrue(result.point.longitude < 19.00045)
        assertEquals(gps.accuracyMeters, result.accuracyMeters)
    }

    @Test
    fun staleRadioEstimateIsRejected() {
        val result = RadioLocationFusion.fuse(
            gpsFix = fix(51.0, 19.0, accuracy = 90f, timestampMs = 1_000L),
            radioEstimate = estimate(51.0003, 19.0003, accuracy = 40f, timestampMs = 1L),
            nowMs = RadioLocationConfig.maximumEstimateAgeMs + 2L,
        )

        assertNull(result)
    }

    private fun fix(latitude: Double, longitude: Double, accuracy: Float, timestampMs: Long): LocationFix {
        return LocationFix(
            point = GeoPoint(latitude = latitude, longitude = longitude),
            accuracyMeters = accuracy,
            timestampMs = timestampMs,
        )
    }

    private fun estimate(
        latitude: Double,
        longitude: Double,
        accuracy: Float,
        observationCount: Int = 2,
        timestampMs: Long = 2_000L,
    ): RadioLocationEstimate {
        return RadioLocationEstimate(
            point = GeoPoint(latitude = latitude, longitude = longitude),
            accuracyMeters = accuracy,
            observationCount = observationCount,
            wifiObservationCount = observationCount,
            bluetoothBeaconObservationCount = 0,
            timestampMs = timestampMs,
        )
    }
}
