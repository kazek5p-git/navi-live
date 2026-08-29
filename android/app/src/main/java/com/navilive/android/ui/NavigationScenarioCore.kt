package com.navilive.android.ui

import com.navilive.android.model.SharedProductRules
import kotlin.math.ceil
import kotlin.math.roundToInt

internal data class HeadingAlignment(
    val signedDeltaDegrees: Double,
    val isAligned: Boolean,
    val isAlmostAligned: Boolean,
)

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

    fun maneuverActivationLeadMeters(accuracyMeters: Float): Double {
        return (
            SharedProductRules.Navigation.guidanceLeadMeters +
                immediateAnnouncementThresholdMeters(accuracyMeters)
            ).toDouble()
    }

    fun maneuverPassThresholdMeters(accuracyMeters: Float): Double {
        return accuracyMeters.coerceIn(5f, 12f).toDouble()
    }

    fun arrivalThresholdMeters(accuracyMeters: Float): Double {
        return accuracyMeters.coerceIn(
            SharedProductRules.Navigation.arrivalAccuracyMinMeters,
            SharedProductRules.Navigation.arrivalAccuracyMaxMeters,
        ).toDouble() * SharedProductRules.Navigation.arrivalAccuracyMultiplier
    }

    fun shouldMarkArrived(
        distanceToDestinationMeters: Double?,
        remainingRouteMeters: Double?,
        accuracyMeters: Float,
    ): Boolean {
        val nearestDistance = listOfNotNull(distanceToDestinationMeters, remainingRouteMeters)
            .filter { it.isFinite() && it >= 0.0 }
            .minOrNull()
            ?: return false
        return nearestDistance <= arrivalThresholdMeters(accuracyMeters)
    }

    fun hasPassedManeuverPoint(
        projectedDistanceAlongRouteMeters: Double,
        maneuverDistanceAlongRouteMeters: Double,
        accuracyMeters: Float,
    ): Boolean {
        return projectedDistanceAlongRouteMeters >=
            maneuverDistanceAlongRouteMeters + maneuverPassThresholdMeters(accuracyMeters)
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

    fun isFreshLocation(
        timestampMs: Long?,
        nowMs: Long,
        maximumAgeMs: Long = SharedProductRules.Navigation.assistantFreshLocationMaxAgeMs,
    ): Boolean {
        val timestamp = timestampMs ?: return false
        if (timestamp <= 0L) return false
        val ageMs = nowMs - timestamp
        return ageMs in -5_000L..maximumAgeMs
    }

    /** Oblicza najkrótszą korektę obrotu telefonu względem kierunku trasy. */
    fun headingAlignment(
        currentHeadingDegrees: Double,
        routeBearingDegrees: Double,
    ): HeadingAlignment? {
        if (!currentHeadingDegrees.isFinite() || !routeBearingDegrees.isFinite()) return null
        val signedDelta = ((routeBearingDegrees - currentHeadingDegrees + 540.0) % 360.0) - 180.0
        val absoluteDelta = kotlin.math.abs(signedDelta)
        return HeadingAlignment(
            signedDeltaDegrees = signedDelta,
            isAligned = absoluteDelta <= 15.0,
            isAlmostAligned = absoluteDelta <= 35.0,
        )
    }
}
