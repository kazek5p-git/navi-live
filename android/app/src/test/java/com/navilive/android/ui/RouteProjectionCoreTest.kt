package com.navilive.android.ui

import com.navilive.android.model.GeoPoint
import com.navilive.android.model.RouteStep
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RouteProjectionCoreTest {

    @Test
    fun projectionNeverMovesBeforeMonotonicFloor() {
        val path = listOf(
            GeoPoint(51.0, 19.0),
            GeoPoint(51.0, 19.001),
            GeoPoint(51.001, 19.001),
        )

        val projection = RouteProjectionCore.project(
            pathPoints = path,
            point = GeoPoint(51.0, 19.0002),
            monotonicFloorMeters = 60.0,
        )

        assertTrue(projection != null)
        assertTrue(projection!!.distanceAlongRouteMeters >= 60.0)
    }

    @Test
    fun projectionReturnsNullForDegeneratePath() {
        val point = GeoPoint(51.0, 19.0)
        assertEquals(null, RouteProjectionCore.project(listOf(point, point), point))
    }

    @Test
    fun routeLengthUsesAllSegments() {
        val path = listOf(
            GeoPoint(51.0, 19.0),
            GeoPoint(51.0, 19.001),
            GeoPoint(51.001, 19.001),
        )

        val length = RouteProjectionCore.routeLengthMeters(path)
        assertTrue(length > 150.0)
        assertTrue(length < 220.0)
    }

    @Test
    fun projectionRespectsTheForwardSearchWindow() {
        val path = listOf(
            GeoPoint(0.0, 0.0),
            GeoPoint(0.0, 0.001),
            GeoPoint(0.001, 0.001),
        )

        val projection = RouteProjectionCore.project(
            pathPoints = path,
            point = GeoPoint(0.0008, 0.001),
            maximumDistanceAlongRouteMeters = 50.0,
        )

        assertEquals(null, projection)
    }

    @Test
    fun projectionReturnsNullWhenMonotonicFloorExceedsSearchWindow() {
        val path = listOf(
            GeoPoint(51.0, 19.0),
            GeoPoint(51.0, 19.001),
            GeoPoint(51.001, 19.001),
        )

        assertEquals(
            null,
            RouteProjectionCore.project(
                pathPoints = path,
                point = GeoPoint(51.0, 19.0002),
                maximumDistanceAlongRouteMeters = 40.0,
                monotonicFloorMeters = 60.0,
            ),
        )
    }

    @Test
    fun missingManeuverPointIsPlacedBetweenKnownRoutePoints() {
        val path = listOf(
            GeoPoint(51.0, 19.0),
            GeoPoint(51.0, 19.001),
            GeoPoint(51.0, 19.002),
        )
        val routeLength = RouteProjectionCore.routeLengthMeters(path)

        val positions = RouteProjectionCore.stepDistancesAlongRoute(
            steps = listOf(
                RouteStep("Start", 100, maneuverPoint = path[0], maneuverType = "depart"),
                RouteStep("Brak punktu", 100, maneuverType = "turn"),
                RouteStep("Koniec", 0, maneuverPoint = path[2], maneuverType = "arrive"),
            ),
            pathPoints = path,
        )

        assertEquals(0.0, positions[0], 1.0)
        assertTrue(positions[1] > 40.0)
        assertTrue(positions[1] < routeLength - 40.0)
        assertEquals(routeLength, positions[2], 1.0)
    }

    @Test
    fun projectionKeepsRouteEndpointInsideFiniteRouteWindow() {
        val path = listOf(
            GeoPoint(51.0, 19.0),
            GeoPoint(51.0, 19.001),
            GeoPoint(51.0, 19.002),
        )
        val routeLength = RouteProjectionCore.routeLengthMeters(path)

        val projection = RouteProjectionCore.project(
            pathPoints = path,
            point = path[2],
            maximumDistanceAlongRouteMeters = routeLength,
        )

        assertTrue(projection != null)
        assertEquals(routeLength, projection!!.distanceAlongRouteMeters, 0.01)
    }

    @Test
    fun missingFinalManeuverPointUsesRouteEndInsteadOfZero() {
        val path = listOf(
            GeoPoint(51.0, 19.0),
            GeoPoint(51.0, 19.001),
        )
        val routeLength = RouteProjectionCore.routeLengthMeters(path)

        val positions = RouteProjectionCore.stepDistancesAlongRoute(
            steps = listOf(
                RouteStep("Start", 100, maneuverPoint = path[0], maneuverType = "depart"),
                RouteStep("Cel", 0, maneuverType = "arrive"),
            ),
            pathPoints = path,
        )

        assertEquals(routeLength, positions.last(), 1.0)
    }
}
