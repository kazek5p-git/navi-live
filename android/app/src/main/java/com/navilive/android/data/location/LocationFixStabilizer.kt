package com.navilive.android.data.location

import com.navilive.android.model.GeoPoint
import com.navilive.android.model.LocationFix
import com.navilive.android.model.SharedProductRules
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

internal class LocationFixStabilizer {
    private var stableFix: LocationFix? = null

    fun reset() {
        stableFix = null
    }

    fun stabilize(rawFix: LocationFix): LocationFix? {
        if (!rawFix.accuracyMeters.isFinite() || rawFix.accuracyMeters < 0f) return null
        val normalizedFix = rawFix
        val previous = stableFix
        if (previous == null) {
            stableFix = normalizedFix
            return normalizedFix
        }

        val elapsedMs = normalizedFix.timestampMs - previous.timestampMs
        if (elapsedMs <= 0L) return null
        if (elapsedMs > SharedProductRules.Navigation.locationStabilizationStaleResetMs) {
            stableFix = normalizedFix
            return normalizedFix
        }

        if (normalizedFix.accuracyMeters > SharedProductRules.Navigation.locationStabilizationMaxUsableAccuracyMeters) {
            return holdPreviousPoint(previous, normalizedFix)
        }

        val distanceMeters = distanceMeters(previous.point, normalizedFix.point)
        if (distanceMeters <= stationaryThresholdMeters(previous, normalizedFix)) {
            return holdPreviousPoint(previous, normalizedFix)
        }

        val elapsedSeconds = elapsedMs / 1000.0
        val jumpDistanceThreshold = max(
            SharedProductRules.Navigation.locationStabilizationJumpDistanceMinMeters,
            (previous.accuracyMeters + normalizedFix.accuracyMeters).toDouble() *
                SharedProductRules.Navigation.locationStabilizationJumpAccuracyMultiplier,
        )
        val speedMetersPerSecond = distanceMeters / elapsedSeconds
        if (
            speedMetersPerSecond > SharedProductRules.Navigation.locationStabilizationMaxWalkingSpeedMetersPerSecond &&
            distanceMeters > jumpDistanceThreshold
        ) {
            return holdPreviousPoint(previous, normalizedFix)
        }

        val stabilized = if (distanceMeters <= SharedProductRules.Navigation.locationStabilizationSmoothingMaxDistanceMeters) {
            smooth(previous, normalizedFix)
        } else {
            normalizedFix
        }
        stableFix = stabilized
        return stabilized
    }

    private fun holdPreviousPoint(previous: LocationFix, incoming: LocationFix): LocationFix {
        val held = previous.copy(
            accuracyMeters = incoming.accuracyMeters,
            timestampMs = incoming.timestampMs,
            courseDegrees = incoming.courseDegrees ?: previous.courseDegrees,
            speedMetersPerSecond = incoming.speedMetersPerSecond ?: previous.speedMetersPerSecond,
        )
        stableFix = held
        return held
    }

    private fun stationaryThresholdMeters(previous: LocationFix, incoming: LocationFix): Double {
        val accuracyWeighted = max(previous.accuracyMeters, incoming.accuracyMeters).toDouble() *
            SharedProductRules.Navigation.locationStabilizationStationaryAccuracyMultiplier
        return min(
            max(
                SharedProductRules.Navigation.locationStabilizationStationaryDistanceMeters,
                accuracyWeighted,
            ),
            SharedProductRules.Navigation.locationStabilizationStationaryMaxDistanceMeters,
        )
    }

    private fun smooth(previous: LocationFix, incoming: LocationFix): LocationFix {
        val alpha = if (incoming.accuracyMeters <= previous.accuracyMeters) {
            SharedProductRules.Navigation.locationStabilizationSmoothingAlphaWhenAccuracyImproves
        } else {
            SharedProductRules.Navigation.locationStabilizationSmoothingAlphaWhenAccuracyWorsens
        }
        return incoming.copy(
            point = GeoPoint(
                latitude = previous.point.latitude + (incoming.point.latitude - previous.point.latitude) * alpha,
                longitude = previous.point.longitude + (incoming.point.longitude - previous.point.longitude) * alpha,
            ),
            courseDegrees = incoming.courseDegrees ?: previous.courseDegrees,
            speedMetersPerSecond = incoming.speedMetersPerSecond ?: previous.speedMetersPerSecond,
        )
    }

    private fun distanceMeters(a: GeoPoint, b: GeoPoint): Double {
        val earthRadiusMeters = 6_371_000.0
        val dLat = Math.toRadians(b.latitude - a.latitude)
        val dLon = Math.toRadians(b.longitude - a.longitude)
        val lat1 = Math.toRadians(a.latitude)
        val lat2 = Math.toRadians(b.latitude)
        val h = sin(dLat / 2).pow(2.0) + cos(lat1) * cos(lat2) * sin(dLon / 2).pow(2.0)
        return 2 * earthRadiusMeters * asin(sqrt(h.coerceIn(0.0, 1.0)))
    }
}
