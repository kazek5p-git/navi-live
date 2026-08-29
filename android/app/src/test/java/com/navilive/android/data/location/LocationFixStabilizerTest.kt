package com.navilive.android.data.location

import com.navilive.android.model.GeoPoint
import com.navilive.android.model.LocationFix
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocationFixStabilizerTest {
    @Test
    fun firstFixIsAccepted() {
        val stabilizer = LocationFixStabilizer()
        val fix = fix(latitude = 51.0, longitude = 19.0, accuracy = 8f, timestampMs = 1_000)

        val stabilized = stabilizer.stabilize(fix)

        assertEquals(fix, stabilized)
    }

    @Test
    fun smallStationaryJitterKeepsPreviousPoint() {
        val stabilizer = LocationFixStabilizer()
        val first = fix(latitude = 51.0, longitude = 19.0, accuracy = 8f, timestampMs = 1_000)
        val jitter = first.copy(
            point = first.point.movedNorth(meters = 3.0),
            timestampMs = 2_000,
        )

        stabilizer.stabilize(first)
        val stabilized = stabilizer.stabilize(jitter)

        assertEquals(first.point.latitude, stabilized?.point?.latitude ?: 0.0, 0.0000001)
        assertEquals(first.point.longitude, stabilized?.point?.longitude ?: 0.0, 0.0000001)
        assertEquals(jitter.timestampMs, stabilized?.timestampMs)
    }

    @Test
    fun implausibleWalkingJumpKeepsPreviousPoint() {
        val stabilizer = LocationFixStabilizer()
        val first = fix(latitude = 51.0, longitude = 19.0, accuracy = 5f, timestampMs = 1_000)
        val jump = first.copy(
            point = first.point.movedNorth(meters = 80.0),
            timestampMs = 2_000,
        )

        stabilizer.stabilize(first)
        val stabilized = stabilizer.stabilize(jump)

        assertEquals(first.point.latitude, stabilized?.point?.latitude ?: 0.0, 0.0000001)
        assertEquals(first.point.longitude, stabilized?.point?.longitude ?: 0.0, 0.0000001)
    }

    @Test
    fun realisticMovementIsSmoothed() {
        val stabilizer = LocationFixStabilizer()
        val first = fix(latitude = 51.0, longitude = 19.0, accuracy = 10f, timestampMs = 1_000)
        val movement = first.copy(
            point = first.point.movedNorth(meters = 20.0),
            accuracyMeters = 6f,
            timestampMs = 7_000,
        )

        stabilizer.stabilize(first)
        val stabilized = stabilizer.stabilize(movement)

        val latitude = stabilized?.point?.latitude ?: 0.0
        assertTrue(latitude > first.point.latitude)
        assertTrue(latitude < movement.point.latitude)
        assertNotEquals(movement.point.latitude, latitude, 0.0000001)
    }

    @Test
    fun staleFixResetsStabilization() {
        val stabilizer = LocationFixStabilizer()
        val first = fix(latitude = 51.0, longitude = 19.0, accuracy = 5f, timestampMs = 1_000)
        val later = first.copy(
            point = first.point.movedNorth(meters = 80.0),
            timestampMs = 25_000,
        )

        stabilizer.stabilize(first)
        val stabilized = stabilizer.stabilize(later)

        assertEquals(later.point.latitude, stabilized?.point?.latitude ?: 0.0, 0.0000001)
        assertEquals(later.point.longitude, stabilized?.point?.longitude ?: 0.0, 0.0000001)
    }

    @Test
    fun invalidNegativeAccuracyIsRejected() {
        val stabilizer = LocationFixStabilizer()
        val invalid = fix(latitude = 51.0, longitude = 19.0, accuracy = -1f, timestampMs = 1_000)

        assertEquals(null, stabilizer.stabilize(invalid))
    }

    private fun fix(latitude: Double, longitude: Double, accuracy: Float, timestampMs: Long): LocationFix {
        return LocationFix(
            point = GeoPoint(latitude = latitude, longitude = longitude),
            accuracyMeters = accuracy,
            timestampMs = timestampMs,
        )
    }

    private fun GeoPoint.movedNorth(meters: Double): GeoPoint {
        return copy(latitude = latitude + meters / metersPerDegreeLatitude)
    }

    private companion object {
        const val metersPerDegreeLatitude = 111_320.0
    }
}
