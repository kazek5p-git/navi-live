package com.navilive.android.data.location

import com.navilive.android.model.GeoPoint
import com.navilive.android.model.LocationFix
import org.junit.Assert.assertEquals
import org.junit.Test

class LocationTrackerStoreTest {

    @Test
    fun delayedFixIsIgnoredAfterTrackingStops() {
        LocationTrackerStore.setTracking(false)

        LocationTrackerStore.pushFix(
            LocationFix(
                point = GeoPoint(latitude = 51.0, longitude = 19.0),
                accuracyMeters = 8f,
                timestampMs = 1_000L,
            ),
        )

        assertEquals(null, LocationTrackerStore.state.value.latestFix)
        assertEquals(false, LocationTrackerStore.state.value.isTracking)
    }
}
