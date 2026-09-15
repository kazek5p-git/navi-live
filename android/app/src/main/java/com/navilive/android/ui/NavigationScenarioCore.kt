package com.navilive.android.ui

import com.navilive.android.model.SharedProductRules
import kotlin.math.ceil
import kotlin.math.roundToInt

internal data class HeadingAlignment(
    val signedDeltaDegrees: Double,
    val isAligned: Boolean,
    val isAlmostAligned: Boolean,
)

internal data class StepConfirmationDecision(
    val confirmedStepIndex: Int?,
    val pendingStepIndex: Int?,
    val consecutiveFixes: Int,
)

internal data class RouteStatusConfirmationDecision(
    val offRouteConfirmed: Boolean,
    val recoveryConfirmed: Boolean,
    val consecutiveOffRouteFixes: Int,
    val consecutiveOnRouteFixes: Int,
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

    /** Dodaje pół sekundy po zakończeniu dźwięku, zanim rozpocznie się mowa. */
    fun speechDelayAfterSound(soundPlaybackDelayMs: Long): Long {
        return soundPlaybackDelayMs.coerceAtLeast(0L) +
            SharedProductRules.Navigation.speechAfterSoundDelayMs
    }

    /** Odrzuca geometrię biegnącą równolegle lub prawie równolegle do trasy. */
    fun isMeaningfulCrossing(
        crossingAngleDegrees: Double,
        minimumBearingDifferenceDegrees: Double,
    ): Boolean {
        return crossingAngleDegrees.isFinite() &&
            minimumBearingDifferenceDegrees.isFinite() &&
            minimumBearingDifferenceDegrees in 0.0..90.0 &&
            crossingAngleDegrees in 0.0..90.0 &&
            crossingAngleDegrees >= minimumBearingDifferenceDegrees
    }

    /** Wymaga dwóch kolejnych pomiarów wskazujących ten sam następny krok. */
    fun confirmStepCandidate(
        currentStepIndex: Int,
        candidateStepIndex: Int,
        pendingStepIndex: Int?,
        consecutiveFixes: Int,
    ): StepConfirmationDecision {
        if (candidateStepIndex <= currentStepIndex) {
            return StepConfirmationDecision(
                confirmedStepIndex = null,
                pendingStepIndex = null,
                consecutiveFixes = 0,
            )
        }

        val nextFixes = if (pendingStepIndex == candidateStepIndex) {
            consecutiveFixes + 1
        } else {
            1
        }
        return if (nextFixes >= SharedProductRules.Navigation.stepConfirmationRequiredFixes) {
            StepConfirmationDecision(
                confirmedStepIndex = candidateStepIndex,
                pendingStepIndex = null,
                consecutiveFixes = 0,
            )
        } else {
            StepConfirmationDecision(
                confirmedStepIndex = null,
                pendingStepIndex = candidateStepIndex,
                consecutiveFixes = nextFixes,
            )
        }
    }

    /** Odfiltrowuje pojedyncze skoki GPS poza trasę i pojedyncze powroty. */
    fun confirmRouteStatus(
        currentlyOffRoute: Boolean,
        measurementIsOffRoute: Boolean,
        consecutiveOffRouteFixes: Int,
        consecutiveOnRouteFixes: Int,
    ): RouteStatusConfirmationDecision {
        if (!currentlyOffRoute) {
            val nextOffRouteFixes = if (measurementIsOffRoute) {
                consecutiveOffRouteFixes + 1
            } else {
                0
            }
            return RouteStatusConfirmationDecision(
                offRouteConfirmed = measurementIsOffRoute &&
                    nextOffRouteFixes >= SharedProductRules.Navigation.offRouteConfirmationRequiredFixes,
                recoveryConfirmed = false,
                consecutiveOffRouteFixes = nextOffRouteFixes,
                consecutiveOnRouteFixes = 0,
            )
        }

        val nextOnRouteFixes = if (measurementIsOffRoute) {
            0
        } else {
            consecutiveOnRouteFixes + 1
        }
        return RouteStatusConfirmationDecision(
            offRouteConfirmed = measurementIsOffRoute,
            recoveryConfirmed = !measurementIsOffRoute &&
                nextOnRouteFixes >= SharedProductRules.Navigation.offRouteRecoveryRequiredFixes,
            consecutiveOffRouteFixes = if (measurementIsOffRoute) {
                SharedProductRules.Navigation.offRouteConfirmationRequiredFixes
            } else {
                0
            },
            consecutiveOnRouteFixes = nextOnRouteFixes,
        )
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
