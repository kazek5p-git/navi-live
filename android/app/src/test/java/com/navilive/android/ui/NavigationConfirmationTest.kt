package com.navilive.android.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NavigationConfirmationTest {

    @Test
    fun stepChangeRequiresTwoConsecutiveFixes() {
        val first = NavigationScenarioCore.confirmStepCandidate(
            currentStepIndex = 0,
            candidateStepIndex = 1,
            pendingStepIndex = null,
            consecutiveFixes = 0,
        )
        assertEquals(null, first.confirmedStepIndex)
        assertEquals(1, first.pendingStepIndex)
        assertEquals(1, first.consecutiveFixes)

        val second = NavigationScenarioCore.confirmStepCandidate(
            currentStepIndex = 0,
            candidateStepIndex = 1,
            pendingStepIndex = first.pendingStepIndex,
            consecutiveFixes = first.consecutiveFixes,
        )
        assertEquals(1, second.confirmedStepIndex)
        assertEquals(null, second.pendingStepIndex)
        assertEquals(0, second.consecutiveFixes)
    }

    @Test
    fun differentCandidateResetsPendingStep() {
        val decision = NavigationScenarioCore.confirmStepCandidate(
            currentStepIndex = 2,
            candidateStepIndex = 1,
            pendingStepIndex = 3,
            consecutiveFixes = 1,
        )

        assertEquals(null, decision.confirmedStepIndex)
        assertEquals(null, decision.pendingStepIndex)
        assertEquals(0, decision.consecutiveFixes)
    }

    @Test
    fun leavingRouteRequiresThreeFixesAndRecoveryRequiresTwo() {
        var consecutiveOffRouteFixes = 0
        repeat(2) {
            val decision = NavigationScenarioCore.confirmRouteStatus(
                currentlyOffRoute = false,
                measurementIsOffRoute = true,
                consecutiveOffRouteFixes = consecutiveOffRouteFixes,
                consecutiveOnRouteFixes = 0,
            )
            consecutiveOffRouteFixes = decision.consecutiveOffRouteFixes
            assertFalse(decision.offRouteConfirmed)
        }

        val confirmed = NavigationScenarioCore.confirmRouteStatus(
            currentlyOffRoute = false,
            measurementIsOffRoute = true,
            consecutiveOffRouteFixes = consecutiveOffRouteFixes,
            consecutiveOnRouteFixes = 0,
        )
        assertTrue(confirmed.offRouteConfirmed)

        val firstRecovery = NavigationScenarioCore.confirmRouteStatus(
            currentlyOffRoute = true,
            measurementIsOffRoute = false,
            consecutiveOffRouteFixes = confirmed.consecutiveOffRouteFixes,
            consecutiveOnRouteFixes = 0,
        )
        assertFalse(firstRecovery.recoveryConfirmed)

        val recovered = NavigationScenarioCore.confirmRouteStatus(
            currentlyOffRoute = true,
            measurementIsOffRoute = false,
            consecutiveOffRouteFixes = firstRecovery.consecutiveOffRouteFixes,
            consecutiveOnRouteFixes = firstRecovery.consecutiveOnRouteFixes,
        )
        assertTrue(recovered.recoveryConfirmed)
    }

    @Test
    fun speechWaitsHalfASecondAfterQueuedSoundPlayback() {
        assertEquals(
            500L,
            NavigationScenarioCore.speechDelayAfterSound(0L),
        )
        assertEquals(
            1_340L,
            NavigationScenarioCore.speechDelayAfterSound(840L),
        )
        assertEquals(
            500L,
            NavigationScenarioCore.speechDelayAfterSound(-50L),
        )
    }

    @Test
    fun crossingFilterRejectsParallelAndShallowGeometry() {
        assertTrue(NavigationScenarioCore.isMeaningfulCrossing(90.0, 55.0))
        assertFalse(NavigationScenarioCore.isMeaningfulCrossing(54.9, 55.0))
        assertFalse(NavigationScenarioCore.isMeaningfulCrossing(0.0, 55.0))
        assertFalse(NavigationScenarioCore.isMeaningfulCrossing(Double.NaN, 55.0))
    }
}
