package com.navilive.android.ui

import com.navilive.android.model.GeoPoint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RoutePolylineIntersectionTest {

    @Test
    fun findsRealCrossingAndPreservesRouteDistance() {
        val route = listOf(
            GeoPoint(51.000000, 19.000000),
            GeoPoint(51.000000, 19.001000),
        )
        val crossingStreet = listOf(
            GeoPoint(50.999500, 19.000500),
            GeoPoint(51.000500, 19.000500),
        )

        val intersections = RouteProjectionCore.polylineIntersections(route, crossingStreet)

        val intersection = intersections.single()
        assertEquals(0, intersection.routeSegmentIndex)
        assertEquals(0, intersection.otherSegmentIndex)
        assertEquals(51.0, intersection.point.latitude, 0.00001)
        assertEquals(19.0005, intersection.point.longitude, 0.00001)
        assertEquals(
            RouteProjectionCore.routeLengthMeters(route) / 2.0,
            intersection.distanceAlongRouteMeters,
            1.0,
        )
        assertEquals(90.0, intersection.crossingAngleDegrees, 0.5)
    }

    @Test
    fun ignoresParallelPathBesideTheRoute() {
        val route = listOf(
            GeoPoint(51.000000, 19.000000),
            GeoPoint(51.000000, 19.001000),
        )
        val parallelCycleway = listOf(
            GeoPoint(51.000020, 19.000000),
            GeoPoint(51.000020, 19.001000),
        )

        assertTrue(RouteProjectionCore.polylineIntersections(route, parallelCycleway).isEmpty())
    }

    @Test
    fun shallowStreetCrossingIsNotMeaningfulForJunctionAlert() {
        val route = listOf(
            GeoPoint(51.000000, 19.000000),
            GeoPoint(51.000000, 19.001000),
        )
        val shallowStreet = listOf(
            GeoPoint(50.999500, 19.000000),
            GeoPoint(51.000500, 19.001500),
        )

        val intersection = RouteProjectionCore.polylineIntersections(route, shallowStreet).single()

        assertFalse(
            NavigationScenarioCore.isMeaningfulCrossing(
                crossingAngleDegrees = intersection.crossingAngleDegrees,
                minimumBearingDifferenceDegrees = 55.0,
            ),
        )
    }

    @Test
    fun deduplicatesCrossingReportedOnAdjacentRouteSegments() {
        val route = listOf(
            GeoPoint(51.000000, 19.000000),
            GeoPoint(51.000000, 19.000500),
            GeoPoint(51.000000, 19.001000),
        )
        val crossingStreet = listOf(
            GeoPoint(50.999500, 19.000500),
            GeoPoint(51.000500, 19.000500),
        )

        val intersections = RouteProjectionCore.polylineIntersections(
            route,
            crossingStreet,
            endpointToleranceMeters = 2.0,
        )

        assertEquals(1, intersections.size)
    }

    @Test
    fun rejectsNegativeEndpointTolerance() {
        val route = listOf(
            GeoPoint(51.000000, 19.000000),
            GeoPoint(51.000000, 19.001000),
        )
        val crossingStreet = listOf(
            GeoPoint(50.999500, 19.000500),
            GeoPoint(51.000500, 19.000500),
        )

        assertTrue(
            RouteProjectionCore.polylineIntersections(
                route,
                crossingStreet,
                endpointToleranceMeters = -1.0,
            ).isEmpty(),
        )
    }
}
