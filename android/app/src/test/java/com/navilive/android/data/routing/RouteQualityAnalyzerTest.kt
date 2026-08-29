package com.navilive.android.data.routing

import com.navilive.android.model.GeoPoint
import com.navilive.android.model.RouteStep
import com.navilive.android.model.RouteStepKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RouteQualityAnalyzerTest {

    @Test
    fun reportsUnnamedTurn() {
        val report = RouteQualityAnalyzer.analyze(
            steps = listOf(
                RouteStep(
                    instruction = "Skręć w lewo",
                    distanceMeters = 100,
                    maneuverType = "turn",
                    maneuverModifier = "left",
                    roadName = null,
                ),
            ),
            pathPoints = routePoints(),
        )

        assertEquals(1, report.unnamedTurnCount)
        assertTrue(RouteQualityIssue.UnnamedTurn in report.issues)
        assertTrue(report.hasPotentialIssues)
        assertEquals(RouteQualityLevel.Review, report.level)
        assertEquals(RouteQualityRecommendation.ReviewBeforeStarting, report.recommendation)
    }

    @Test
    fun reportsRepeatedAdjacentInstruction() {
        val repeatedInstruction = "Skręć w prawo w Lipową"
        val report = RouteQualityAnalyzer.analyze(
            steps = listOf(
                RouteStep(instruction = repeatedInstruction, distanceMeters = 12),
                RouteStep(instruction = repeatedInstruction, distanceMeters = 80),
            ),
            pathPoints = routePoints(),
        )

        assertEquals(1, report.repeatedInstructionCount)
        assertTrue(RouteQualityIssue.RepeatedInstruction in report.issues)
    }

    @Test
    fun reportsIncompleteGeometry() {
        val report = RouteQualityAnalyzer.analyze(
            steps = emptyList(),
            pathPoints = listOf(GeoPoint(latitude = 51.0, longitude = 19.0)),
        )

        assertTrue(report.hasIncompleteGeometry)
        assertTrue(RouteQualityIssue.IncompleteGeometry in report.issues)
        assertEquals(1, report.issueCount)
        assertEquals(0, report.qualityScore)
        assertEquals(0, report.confidencePercent)
        assertEquals(RouteQualityLevel.InsufficientData, report.level)
        assertEquals(RouteQualityRecommendation.WaitForCompleteData, report.recommendation)
    }

    @Test
    fun reportsInvalidGeometryInsteadOfTreatingItAsReliable() {
        val report = RouteQualityAnalyzer.analyze(
            steps = listOf(RouteStep(instruction = "Idź prosto", distanceMeters = 40)),
            pathPoints = listOf(
                GeoPoint(latitude = 91.0, longitude = 19.0),
                GeoPoint(latitude = 51.0, longitude = 19.001),
            ),
        )

        assertTrue(report.hasIncompleteGeometry)
        assertEquals(RouteQualityLevel.InsufficientData, report.level)
        assertEquals(0, report.qualityScore)
    }

    @Test
    fun reportsMissingManeuverData() {
        val report = RouteQualityAnalyzer.analyze(
            steps = listOf(
                RouteStep(
                    instruction = "",
                    distanceMeters = 30,
                    maneuverType = "turn",
                    maneuverModifier = "right",
                    roadName = "Lipowa",
                ),
            ),
            pathPoints = routePoints(),
        )

        assertEquals(1, report.missingManeuverDataCount)
        assertTrue(RouteQualityIssue.MissingManeuverData in report.issues)
        assertFalse(report.hasIncompleteGeometry)
        assertTrue(report.hasPotentialIssues)
    }

    @Test
    fun reportsCloseOppositeManeuversAsReviewSignal() {
        val report = RouteQualityAnalyzer.analyze(
            steps = listOf(
                RouteStep(
                    instruction = "Skręć w lewo w Lipową",
                    distanceMeters = 20,
                    maneuverType = "turn",
                    maneuverModifier = "left",
                    maneuverPoint = GeoPoint(51.0, 19.0),
                    roadName = "Lipowa",
                ),
                RouteStep(
                    instruction = "Skręć w prawo w Dębową",
                    distanceMeters = 25,
                    maneuverType = "turn",
                    maneuverModifier = "right",
                    maneuverPoint = GeoPoint(51.0, 19.0002),
                    roadName = "Dębowa",
                ),
            ),
            pathPoints = routePoints(),
        )

        assertEquals(1, report.closeOppositeManeuverCount)
        assertTrue(RouteQualityIssue.CloseOppositeManeuvers in report.issues)
        assertTrue(report.hasPotentialIssues)
    }

    @Test
    fun reportsCloseOppositeManeuversSeparatedByCrossingStep() {
        val report = RouteQualityAnalyzer.analyze(
            steps = listOf(
                RouteStep(
                    instruction = "Skręć w lewo w Lipową",
                    distanceMeters = 20,
                    maneuverType = "turn",
                    maneuverModifier = "left",
                    maneuverPoint = GeoPoint(51.0, 19.0002),
                    roadName = "Lipowa",
                ),
                RouteStep(
                    instruction = "Przejście dla pieszych",
                    distanceMeters = 12,
                    kind = RouteStepKind.PedestrianCrossing,
                ),
                RouteStep(
                    instruction = "Skręć w prawo w Dębową",
                    distanceMeters = 25,
                    maneuverType = "turn",
                    maneuverModifier = "right",
                    maneuverPoint = GeoPoint(51.0, 19.0003),
                    roadName = "Dębowa",
                ),
            ),
            pathPoints = routePoints(),
        )

        assertEquals(1, report.closeOppositeManeuverCount)
        assertTrue(RouteQualityIssue.CloseOppositeManeuvers in report.issues)
    }

    @Test
    fun reportsManeuverPointOutsideRouteGeometry() {
        val report = RouteQualityAnalyzer.analyze(
            steps = listOf(
                RouteStep(
                    instruction = "Skręć w prawo w Lipową",
                    distanceMeters = 60,
                    maneuverType = "turn",
                    maneuverModifier = "right",
                    maneuverPoint = GeoPoint(51.001, 19.0005),
                    roadName = "Lipowa",
                ),
            ),
            pathPoints = routePoints(),
        )

        assertEquals(1, report.maneuverGeometryMismatchCount)
        assertTrue(RouteQualityIssue.ManeuverGeometryMismatch in report.issues)
        assertEquals(RouteQualityLevel.Review, report.level)
    }

    @Test
    fun reportsManeuverPointsInReverseRouteOrder() {
        val report = RouteQualityAnalyzer.analyze(
            steps = listOf(
                RouteStep(
                    instruction = "Skręć w prawo w Lipową",
                    distanceMeters = 60,
                    maneuverType = "turn",
                    maneuverModifier = "right",
                    maneuverPoint = GeoPoint(51.0, 19.0008),
                    roadName = "Lipowa",
                ),
                RouteStep(
                    instruction = "Skręć w lewo w Dębową",
                    distanceMeters = 60,
                    maneuverType = "turn",
                    maneuverModifier = "left",
                    maneuverPoint = GeoPoint(51.0, 19.0002),
                    roadName = "Dębowa",
                ),
            ),
            pathPoints = listOf(
                GeoPoint(51.0, 19.0),
                GeoPoint(51.0, 19.001),
            ),
        )

        assertEquals(1, report.maneuverGeometryMismatchCount)
        assertTrue(RouteQualityIssue.ManeuverGeometryMismatch in report.issues)
    }

    @Test
    fun doesNotUseStepDistancesAsReplacementForManeuverGeometry() {
        val report = RouteQualityAnalyzer.analyze(
            steps = listOf(
                RouteStep(
                    instruction = "Skręć w lewo w Lipową",
                    distanceMeters = 20,
                    maneuverType = "turn",
                    maneuverModifier = "left",
                    maneuverPoint = GeoPoint(51.0, 19.0),
                    roadName = "Lipowa",
                ),
                RouteStep(
                    instruction = "Skręć w prawo w Dębową",
                    distanceMeters = 25,
                    maneuverType = "turn",
                    maneuverModifier = "right",
                    maneuverPoint = GeoPoint(51.0, 19.002),
                    roadName = "Dębowa",
                ),
            ),
            pathPoints = routePoints(),
        )

        assertEquals(0, report.closeOppositeManeuverCount)
    }

    @Test
    fun nearbyParallelReturnLegIsReportedAsGeometryOrderIssue() {
        val path = listOf(
            GeoPoint(51.0, 19.0),
            GeoPoint(51.0009, 19.0),
            GeoPoint(51.0009, 19.00015),
            GeoPoint(51.0, 19.00015),
        )
        val report = RouteQualityAnalyzer.analyze(
            steps = listOf(
                RouteStep(
                    instruction = "Skręć w lewo w Lipową",
                    distanceMeters = 60,
                    maneuverType = "turn",
                    maneuverModifier = "left",
                    maneuverPoint = GeoPoint(51.00045, 19.00015),
                    roadName = "Lipowa",
                ),
                RouteStep(
                    instruction = "Skręć w prawo w Dębową",
                    distanceMeters = 60,
                    maneuverType = "turn",
                    maneuverModifier = "right",
                    maneuverPoint = GeoPoint(51.00045, 19.0),
                    roadName = "Dębowa",
                ),
            ),
            pathPoints = path,
        )

        assertEquals(0, report.closeOppositeManeuverCount)
        assertEquals(1, report.maneuverGeometryMismatchCount)
    }

    @Test
    fun doesNotReportHealthyRoute() {
        val report = RouteQualityAnalyzer.analyze(
            steps = listOf(
                RouteStep(
                    instruction = "Skręć w lewo w Lipową",
                    distanceMeters = 100,
                    maneuverType = "turn",
                    maneuverModifier = "left",
                    maneuverPoint = GeoPoint(51.0, 19.0),
                    roadName = "Lipowa",
                ),
                RouteStep(instruction = "Idź dalej prosto", distanceMeters = 80),
            ),
            pathPoints = routePoints(),
        )

        assertFalse(report.hasPotentialIssues)
        assertTrue(report.issues.isEmpty())
        assertEquals(0, report.issueCount)
        assertEquals(100, report.qualityScore)
        assertEquals(100, report.confidencePercent)
        assertEquals(RouteQualityLevel.Good, report.level)
        assertEquals(RouteQualityRecommendation.FollowCurrentGuidance, report.recommendation)
    }

    private fun routePoints() = listOf(
        GeoPoint(latitude = 51.0, longitude = 19.0),
        GeoPoint(latitude = 51.0, longitude = 19.001),
    )
}
