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

/**
 * Łączy wynik beaconDB z GPS-em wyłącznie jako niewielką korektę słabego GPS-u.
 * Wynik radiowy nie może zastąpić GPS-u ani wykonać dużego skoku pozycji.
 */
internal object RadioLocationFusion {
    fun fuse(
        gpsFix: LocationFix,
        radioEstimate: RadioLocationEstimate,
        nowMs: Long = radioEstimate.timestampMs,
    ): LocationFix? {
        if (!gpsFix.accuracyMeters.isFinite() || !radioEstimate.accuracyMeters.isFinite()) return null
        if (gpsFix.accuracyMeters < SharedProductRules.Navigation.gpsWeakAccuracyMeters) return null
        if (radioEstimate.observationCount < RadioLocationConfig.minimumObservationsForLookup) return null
        if (radioEstimate.accuracyMeters <= 0f ||
            radioEstimate.accuracyMeters > RadioLocationConfig.maximumAcceptedAccuracyMeters
        ) {
            return null
        }
        if (kotlin.math.abs(nowMs - radioEstimate.timestampMs) > RadioLocationConfig.maximumEstimateAgeMs) {
            return null
        }

        val distance = distanceMeters(gpsFix.point, radioEstimate.point)
        val agreementLimit = min(
            RadioLocationConfig.maximumGpsRadioAgreementMeters,
            max(
                45.0,
                (gpsFix.accuracyMeters + radioEstimate.accuracyMeters) * 0.75,
            ),
        )
        if (distance > agreementLimit) return null

        val gpsWeight = 1.0 / gpsFix.accuracyMeters.toDouble().pow(2.0)
        val radioWeight = 1.0 / radioEstimate.accuracyMeters.toDouble().pow(2.0)
        val radioShare = (radioWeight / (gpsWeight + radioWeight)).coerceAtMost(0.35)
        val boundedShare = if (distance > 0.0) {
            min(radioShare, RadioLocationConfig.maximumFusionShiftMeters / distance)
        } else {
            0.0
        }
        val fusedPoint = interpolate(gpsFix.point, radioEstimate.point, boundedShare)
        return gpsFix.copy(
            point = fusedPoint,
            timestampMs = max(gpsFix.timestampMs, radioEstimate.timestampMs),
        )
    }

    private fun interpolate(start: GeoPoint, end: GeoPoint, ratio: Double): GeoPoint {
        val boundedRatio = ratio.coerceIn(0.0, 1.0)
        return GeoPoint(
            latitude = start.latitude + (end.latitude - start.latitude) * boundedRatio,
            longitude = start.longitude + (end.longitude - start.longitude) * boundedRatio,
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
