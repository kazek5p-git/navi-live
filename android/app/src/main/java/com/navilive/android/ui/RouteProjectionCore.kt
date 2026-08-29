package com.navilive.android.ui

import com.navilive.android.model.GeoPoint
import com.navilive.android.model.RouteStep
import com.navilive.android.model.SharedProductRules
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.math.sqrt

internal data class RouteProgressProjection(
    val distanceAlongRouteMeters: Double,
    val remainingRouteMeters: Double,
    val lateralDistanceMeters: Double,
    val segmentBearingDegrees: Double,
)

/** Wybiera stabilny odcinek trasy zamiast przypadkowego odcinka przy skrzyżowaniu. */
internal object RouteProjectionCore {
    private const val PROJECTION_BOUNDARY_TOLERANCE_METERS = 0.05

    fun project(
        pathPoints: List<GeoPoint>,
        point: GeoPoint,
        minimumDistanceAlongRouteMeters: Double = 0.0,
        maximumDistanceAlongRouteMeters: Double = Double.POSITIVE_INFINITY,
        preferredCourseDegrees: Double? = null,
        speedMetersPerSecond: Double? = null,
        accuracyMeters: Double? = null,
        monotonicFloorMeters: Double? = null,
    ): RouteProgressProjection? {
        if (pathPoints.size < 2) return null
        if (!minimumDistanceAlongRouteMeters.isFinite() ||
            (!maximumDistanceAlongRouteMeters.isFinite() &&
                maximumDistanceAlongRouteMeters != Double.POSITIVE_INFINITY) ||
            minimumDistanceAlongRouteMeters > maximumDistanceAlongRouteMeters ||
            monotonicFloorMeters != null && monotonicFloorMeters > maximumDistanceAlongRouteMeters
        ) return null

        val segments = pathPoints.zipWithNext { start, end ->
            projectOntoSegment(point, start, end)
        }
        val routeLength = segments.sumOf { it.lengthMeters }
        if (routeLength <= 0.0) return null
        val upperBound = minOf(maximumDistanceAlongRouteMeters, routeLength)
        if (minimumDistanceAlongRouteMeters > upperBound) return null

        val courseForProjection = preferredCourseDegrees
            ?.takeIf { it.isFinite() }
            ?.takeIf {
                speedMetersPerSecond?.isFinite() == true &&
                    speedMetersPerSecond >= SharedProductRules.Navigation.routeProjectionCourseUseMinimumSpeedMetersPerSecond &&
                    accuracyMeters?.isFinite() == true &&
                    accuracyMeters <= SharedProductRules.Navigation.routeProjectionCourseMaximumAccuracyMeters
            }

        var distanceBeforeSegment = 0.0
        var best: Candidate? = null
        for (segment in segments) {
            val distanceAlongRoute = distanceBeforeSegment + segment.lengthMeters * segment.ratio
            if (distanceAlongRoute < minimumDistanceAlongRouteMeters - PROJECTION_BOUNDARY_TOLERANCE_METERS ||
                distanceAlongRoute > upperBound + PROJECTION_BOUNDARY_TOLERANCE_METERS
            ) {
                distanceBeforeSegment += segment.lengthMeters
                continue
            }
            val boundedDistanceAlongRoute = distanceAlongRoute.coerceIn(
                minimumDistanceAlongRouteMeters,
                upperBound,
            )

            val coursePenalty = courseForProjection?.let { course ->
                val difference = directedBearingDifference(
                    course,
                    segment.bearingDegrees,
                )
                difference / 180.0 * SharedProductRules.Navigation.routeProjectionCourseMismatchPenaltyMeters
            } ?: 0.0
            val candidate = Candidate(
                distanceAlongRouteMeters = boundedDistanceAlongRoute,
                lateralDistanceMeters = segment.lateralDistanceMeters,
                segmentBearingDegrees = segment.bearingDegrees,
                score = segment.lateralDistanceMeters + coursePenalty,
            )
            val currentBest = best
            val scoreDifference = currentBest?.let { candidate.score - it.score }
            if (
                currentBest == null ||
                scoreDifference!! < -0.01 ||
                kotlin.math.abs(scoreDifference) <= 0.01 &&
                    candidate.distanceAlongRouteMeters > currentBest.distanceAlongRouteMeters
            ) {
                best = candidate
            }
            distanceBeforeSegment += segment.lengthMeters
        }

        val selected = best ?: return null
        val monotonicDistance = maxOf(
            selected.distanceAlongRouteMeters,
            monotonicFloorMeters ?: selected.distanceAlongRouteMeters,
        ).coerceIn(0.0, routeLength)
        return RouteProgressProjection(
            distanceAlongRouteMeters = monotonicDistance,
            remainingRouteMeters = (routeLength - monotonicDistance).coerceAtLeast(0.0),
            lateralDistanceMeters = selected.lateralDistanceMeters,
            segmentBearingDegrees = selected.segmentBearingDegrees,
        )
    }

    fun routeLengthMeters(pathPoints: List<GeoPoint>): Double {
        if (pathPoints.size < 2) return 0.0
        return pathPoints.zipWithNext().sumOf { (start, end) -> distanceMeters(start, end) }
    }

    /**
     * Zwraca pozycję początku każdego kroku na geometrii trasy.
     *
     * Punkt manewru z routera jest źródłem pierwszego wyboru. Jeżeli go brakuje,
     * pozycja jest rekonstruowana z długości poprzednich kroków między znanymi
     * punktami. Dzięki temu brak jednego punktu nie przenosi całej reszty trasy
     * na jej koniec.
     */
    fun stepDistancesAlongRoute(
        steps: List<RouteStep>,
        pathPoints: List<GeoPoint>,
    ): List<Double> {
        if (steps.isEmpty()) return emptyList()
        val routeLength = routeLengthMeters(pathPoints)
        if (!routeLength.isFinite() || routeLength <= 0.0) {
            return List(steps.size) { 0.0 }
        }

        val positions = arrayOfNulls<Double>(steps.size)
        positions[0] = 0.0
        var lastKnownPosition = 0.0

        // Pierwszy krok zawsze zaczyna się na początku przekazanej geometrii.
        // Jest to ważne także dla sztucznego kroku dojścia do trasy.
        for (index in 1 until steps.size) {
            val projected = steps[index].maneuverPoint
                ?.let { point ->
                    project(
                        pathPoints = pathPoints,
                        point = point,
                        minimumDistanceAlongRouteMeters = lastKnownPosition,
                        maximumDistanceAlongRouteMeters = routeLength,
                    )?.distanceAlongRouteMeters
                }
                ?.takeIf { it.isFinite() && it >= lastKnownPosition }
                ?.coerceIn(lastKnownPosition, routeLength)
            if (projected != null) {
                positions[index] = projected
                lastKnownPosition = projected
            }
        }

        var knownIndex = 0
        while (knownIndex < positions.lastIndex) {
            val nextKnownIndex = (knownIndex + 1 until positions.size)
                .firstOrNull { positions[it] != null }
            val upperPosition = nextKnownIndex?.let { positions[it] } ?: routeLength
            val endExclusive = nextKnownIndex ?: positions.size
            val span = endExclusive - knownIndex
            val weights = (knownIndex until endExclusive)
                .map { stepTimelineWeight(steps[it]) }
            val totalWeight = weights.sum()
            val lowerPosition = positions[knownIndex] ?: 0.0

            for (index in knownIndex + 1 until endExclusive) {
                val weightBefore = weights
                    .take(index - knownIndex)
                    .sum()
                val ratio = if (totalWeight > 0.0) {
                    weightBefore / totalWeight
                } else {
                    (index - knownIndex).toDouble() / span.toDouble()
                }
                positions[index] = (
                    lowerPosition + (upperPosition - lowerPosition) * ratio
                    ).coerceIn(lowerPosition, upperPosition)
            }

            if (nextKnownIndex == null) break
            knownIndex = nextKnownIndex
        }

        return positions.map { it?.coerceIn(0.0, routeLength) ?: 0.0 }
    }

    fun initialBearingDegrees(
        pathPoints: List<GeoPoint>,
        minimumSegmentMeters: Double = 3.0,
    ): Double? {
        if (pathPoints.size < 2) return null
        pathPoints.zipWithNext().forEach { (start, end) ->
            if (distanceMeters(start, end) >= minimumSegmentMeters) {
                return bearingDegrees(start, end)
            }
        }
        return null
    }

    fun bearingDegrees(from: GeoPoint, to: GeoPoint): Double? {
        if (from == to) return null
        val latitude1 = Math.toRadians(from.latitude)
        val latitude2 = Math.toRadians(to.latitude)
        val longitudeDifference = Math.toRadians(to.longitude - from.longitude)
        val y = sin(longitudeDifference) * cos(latitude2)
        val x = cos(latitude1) * sin(latitude2) -
            sin(latitude1) * cos(latitude2) * cos(longitudeDifference)
        return (Math.toDegrees(atan2(y, x)) + 360.0) % 360.0
    }

    private data class Candidate(
        val distanceAlongRouteMeters: Double,
        val lateralDistanceMeters: Double,
        val segmentBearingDegrees: Double,
        val score: Double,
    )

    private data class SegmentProjection(
        val ratio: Double,
        val lengthMeters: Double,
        val lateralDistanceMeters: Double,
        val bearingDegrees: Double,
    )

    private fun projectOntoSegment(point: GeoPoint, start: GeoPoint, end: GeoPoint): SegmentProjection {
        val latitudeReference = Math.toRadians((point.latitude + start.latitude + end.latitude) / 3.0)
        val earthRadius = 6_371_000.0

        fun project(geoPoint: GeoPoint): Pair<Double, Double> {
            val x = Math.toRadians(geoPoint.longitude) * earthRadius * cos(latitudeReference)
            val y = Math.toRadians(geoPoint.latitude) * earthRadius
            return x to y
        }

        val (pointX, pointY) = project(point)
        val (startX, startY) = project(start)
        val (endX, endY) = project(end)
        val dx = endX - startX
        val dy = endY - startY
        val lengthSquared = dx * dx + dy * dy
        if (lengthSquared <= 0.0) {
            return SegmentProjection(
                ratio = 0.0,
                lengthMeters = 0.0,
                lateralDistanceMeters = hypot(pointX - startX, pointY - startY),
                bearingDegrees = 0.0,
            )
        }

        val ratio = (((pointX - startX) * dx + (pointY - startY) * dy) / lengthSquared)
            .coerceIn(0.0, 1.0)
        val nearestX = startX + dx * ratio
        val nearestY = startY + dy * ratio
        return SegmentProjection(
            ratio = ratio,
            // Proporcja wynika z lokalnej projekcji, ale postęp trasy musi używać
            // tej samej geograficznej długości co routeLengthMeters().
            lengthMeters = distanceMeters(start, end),
            lateralDistanceMeters = hypot(pointX - nearestX, pointY - nearestY),
            bearingDegrees = normalizedBearingDegrees(atan2(dx, dy)),
        )
    }

    private fun stepTimelineWeight(step: RouteStep): Double {
        if (step.maneuverType?.trim()?.equals("approach", ignoreCase = true) == true) {
            return 0.0
        }
        return step.distanceMeters.coerceAtLeast(0).toDouble()
    }

    private fun directedBearingDifference(left: Double, right: Double): Double {
        return kotlin.math.abs(((left - right + 540.0) % 360.0) - 180.0)
    }

    private fun normalizedBearingDegrees(radians: Double): Double {
        return (Math.toDegrees(radians) + 360.0) % 360.0
    }

    private fun distanceMeters(a: GeoPoint, b: GeoPoint): Double {
        val earthRadius = 6_371_000.0
        val lat1 = Math.toRadians(a.latitude)
        val lat2 = Math.toRadians(b.latitude)
        val dLat = lat2 - lat1
        val dLon = Math.toRadians(b.longitude - a.longitude)
        val h = sin(dLat / 2).let { it * it } +
            cos(lat1) * cos(lat2) * sin(dLon / 2).let { it * it }
        return 2.0 * earthRadius * asin(sqrt(h))
    }
}
