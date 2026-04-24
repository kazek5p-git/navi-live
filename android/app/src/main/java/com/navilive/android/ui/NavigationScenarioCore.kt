package com.navilive.android.ui

import com.navilive.android.model.SharedProductRules
import kotlin.math.ceil
import kotlin.math.roundToInt

internal object NavigationScenarioCore {

    fun maneuverAdvanceThresholdMeters(accuracyMeters: Float): Double {
        return accuracyMeters
            .coerceIn(
                SharedProductRules.Navigation.maneuverAdvanceAccuracyMinMeters,
                SharedProductRules.Navigation.maneuverAdvanceAccuracyMaxMeters,
            )
            .toDouble() * SharedProductRules.Navigation.maneuverAdvanceMultiplier
    }

    fun offRouteThresholdMeters(accuracyMeters: Float): Int {
        return (
            accuracyMeters.coerceIn(
                SharedProductRules.Navigation.offRouteAccuracyMinMeters,
                SharedProductRules.Navigation.offRouteAccuracyMaxMeters,
            ) * SharedProductRules.Navigation.offRouteMultiplier
            )
            .roundToInt()
            .coerceAtLeast(SharedProductRules.Navigation.offRouteMinimumThresholdMeters)
    }

    fun immediateAnnouncementThresholdMeters(accuracyMeters: Float): Int {
        return accuracyMeters
            .coerceIn(
                SharedProductRules.Navigation.immediateInstructionAccuracyMinMeters,
                SharedProductRules.Navigation.immediateInstructionAccuracyMaxMeters,
            )
            .roundToInt()
            .coerceIn(
                SharedProductRules.Navigation.immediateInstructionThresholdMinMeters,
                SharedProductRules.Navigation.immediateInstructionThresholdMaxMeters,
            )
    }

    fun countdownMilestoneMeters(distanceToNext: Int): Int? {
        return SharedProductRules.Navigation.countdownMilestonesMeters.firstOrNull {
            distanceToNext <= it
        }
    }

    fun countdownMilestoneSeconds(secondsToNext: Int): Int? {
        return SharedProductRules.Navigation.countdownMilestonesSeconds.firstOrNull {
            secondsToNext <= it
        }
    }

    fun estimatedSecondsToManeuver(distanceToNextMeters: Int): Int {
        val walkingSeconds = (
            distanceToNextMeters.coerceAtLeast(0).toDouble() /
                SharedProductRules.Search.walkingEtaMetersPerMinute
            ) * 60.0
        return ceil(walkingSeconds).toInt().coerceAtLeast(1)
    }

    fun distanceBasedEtaMinutes(distanceMeters: Int): Int {
        val walkingMinutes = distanceMeters.coerceAtLeast(0).toDouble() /
            SharedProductRules.Search.walkingEtaMetersPerMinute
        return ceil(walkingMinutes).toInt().coerceAtLeast(1)
    }

    fun routeEtaMinutes(distanceMeters: Int, providerDurationSeconds: Double): Int {
        val providerMinutes = ceil(providerDurationSeconds.coerceAtLeast(0.0) / 60.0).toInt().coerceAtLeast(1)
        return maxOf(distanceBasedEtaMinutes(distanceMeters), providerMinutes)
    }

    fun shouldAdvanceStep(distanceToManeuverMeters: Double, accuracyMeters: Float): Boolean {
        return distanceToManeuverMeters <= maneuverAdvanceThresholdMeters(accuracyMeters)
    }

    fun shouldTriggerOffRoute(deviationMeters: Int?, accuracyMeters: Float): Boolean {
        return deviationMeters != null && deviationMeters > offRouteThresholdMeters(accuracyMeters)
    }

    fun shouldAllowAutoRecalculate(
        isRouteRecalculating: Boolean,
        elapsedSinceLastRecalculateMs: Long,
    ): Boolean {
        return !isRouteRecalculating &&
            elapsedSinceLastRecalculateMs >= SharedProductRules.Navigation.autoRecalculateCooldownMs
    }
}
