package com.navilive.android.ui

import com.navilive.android.model.SharedProductRules
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
