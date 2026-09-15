package com.navilive.android.data.routing

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PedestrianCrossingCoreTest {

    @Test
    fun rejectsCyclewayCrossingWithoutPedestrianAccess() {
        assertFalse(
            PedestrianCrossingCore.isPedestrianCrossing(
                mapOf("highway" to "cycleway", "crossing" to "yes"),
            ),
        )
    }

    @Test
    fun keepsSharedCrossingWithExplicitPedestrianAccess() {
        assertTrue(
            PedestrianCrossingCore.isPedestrianCrossing(
                mapOf("highway" to "cycleway", "crossing" to "yes", "foot" to "designated"),
            ),
        )
    }

    @Test
    fun rejectsCrossingExplicitlyClosedToPedestrians() {
        assertFalse(
            PedestrianCrossingCore.isPedestrianCrossing(
                mapOf("highway" to "crossing", "foot" to "no"),
            ),
        )
    }

    @Test
    fun rejectsCrossingMarkedAsCyclewayWithoutPedestrianAccess() {
        assertFalse(
            PedestrianCrossingCore.isPedestrianCrossing(
                mapOf("crossing:carriageway" to "cycleway"),
            ),
        )
    }

    @Test
    fun ignoresElementWithoutCrossingTags() {
        assertFalse(
            PedestrianCrossingCore.isPedestrianCrossing(
                mapOf("highway" to "cycleway"),
            ),
        )
    }
}
