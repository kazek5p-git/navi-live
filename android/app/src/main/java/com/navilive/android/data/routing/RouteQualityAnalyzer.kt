package com.navilive.android.data.routing

import com.navilive.android.model.GeoPoint
import com.navilive.android.model.RouteStep
import com.navilive.android.model.SharedProductRules
import com.navilive.android.ui.RouteProjectionCore
import java.text.Normalizer
import java.util.Locale

/** Konkretna przyczyna, dla której asystent zaleca ręczne sprawdzenie trasy. */
internal enum class RouteQualityIssue {
    UnnamedTurn,
    RepeatedInstruction,
    MissingManeuverData,
    CloseOppositeManeuvers,
    ManeuverGeometryMismatch,
    IncompleteGeometry,
}

/** Ogólny poziom wyniku lokalnej analizy. Nie jest oceną bezpieczeństwa trasy. */
internal enum class RouteQualityLevel {
    Good,
    Review,
    InsufficientData,
}

/** Zalecenie dla interfejsu po analizie danych routera. */
internal enum class RouteQualityRecommendation {
    FollowCurrentGuidance,
    ReviewBeforeStarting,
    WaitForCompleteData,
}

/** Wynik ostrożnej, lokalnej analizy danych trasy. */
internal data class RouteQualityReport(
    val stepCount: Int,
    val unnamedTurnCount: Int,
    val repeatedInstructionCount: Int,
    val missingManeuverDataCount: Int,
    val closeOppositeManeuverCount: Int,
    val maneuverGeometryMismatchCount: Int,
    val hasIncompleteGeometry: Boolean,
    val qualityScore: Int,
    val confidencePercent: Int,
    val level: RouteQualityLevel,
) {
    /** Stabilna kolejność powoduje przewidywalny komunikat dla czytnika ekranu. */
    val issues: List<RouteQualityIssue>
        get() = buildList {
            if (unnamedTurnCount > 0) add(RouteQualityIssue.UnnamedTurn)
            if (repeatedInstructionCount > 0) add(RouteQualityIssue.RepeatedInstruction)
            if (missingManeuverDataCount > 0) add(RouteQualityIssue.MissingManeuverData)
            if (closeOppositeManeuverCount > 0) add(RouteQualityIssue.CloseOppositeManeuvers)
            if (maneuverGeometryMismatchCount > 0) add(RouteQualityIssue.ManeuverGeometryMismatch)
            if (hasIncompleteGeometry) add(RouteQualityIssue.IncompleteGeometry)
        }

    val issueCount: Int
        get() = unnamedTurnCount + repeatedInstructionCount + missingManeuverDataCount +
            closeOppositeManeuverCount +
            maneuverGeometryMismatchCount +
            if (hasIncompleteGeometry) 1 else 0

    val hasPotentialIssues: Boolean
        get() = level != RouteQualityLevel.Good

    val recommendation: RouteQualityRecommendation
        get() = when (level) {
            RouteQualityLevel.Good -> RouteQualityRecommendation.FollowCurrentGuidance
            RouteQualityLevel.Review -> RouteQualityRecommendation.ReviewBeforeStarting
            RouteQualityLevel.InsufficientData -> RouteQualityRecommendation.WaitForCompleteData
        }
}

/**
 * Analizuje tylko dane dostarczone przez router. Nie zastępuje routera i nie tworzy nowych
 * manewrów, dzięki czemu wynik może służyć jako wyjaśnialna pomoc dla użytkownika.
 */
internal object RouteQualityAnalyzer {
    private const val CLOSE_OPPOSITE_MANEUVER_DISTANCE_METERS = 60.0
    private const val MANEUVER_GEOMETRY_MAX_LATERAL_DISTANCE_METERS = 45.0
    private const val MANEUVER_GEOMETRY_ORDER_TOLERANCE_METERS = 25.0

    fun analyze(steps: List<RouteStep>, pathPoints: List<GeoPoint>): RouteQualityReport {
        val unnamedTurns = steps.count { step ->
            RouteStepSimplificationCore.isTurnLikeManeuver(step) &&
                !step.maneuverType.equals("approach", ignoreCase = true) &&
                step.roadName?.trim().isNullOrEmpty()
        }
        val repeatedInstructions = steps.zipWithNext().count { (left, right) ->
            val leftInstruction = normalize(left.instruction)
            val rightInstruction = normalize(right.instruction)
            leftInstruction.isNotEmpty() &&
                leftInstruction == rightInstruction &&
                (left.distanceMeters <= 20 || right.distanceMeters <= 20)
        }
        val missingManeuverData = steps.count { step ->
            RouteStepSimplificationCore.isTurnLikeManeuver(step) &&
                !step.maneuverType.equals("approach", ignoreCase = true) &&
                (step.instruction.isBlank() || step.maneuverPoint == null)
        }
        // Router może wstawić przejście dla pieszych między dwoma skrętami.
        // Porównujemy więc kolejne rzeczywiste manewry, a nie tylko sąsiednie wiersze.
        val maneuverSteps = steps.filter { step ->
            RouteStepSimplificationCore.isTurnLikeManeuver(step) &&
                step.maneuverPoint != null
        }
        var previousManeuverStep: RouteStep? = null
        var previousManeuverDistance = 0.0
        var hasPreviousManeuverProjection = false
        var closeOppositeManeuvers = 0
        maneuverSteps.forEach { step ->
            val projection = step.maneuverPoint?.let { point ->
                val unconstrainedProjection = RouteProjectionCore.project(
                    pathPoints = pathPoints,
                    point = point,
                ) ?: return@let null
                if (unconstrainedProjection.lateralDistanceMeters >
                    MANEUVER_GEOMETRY_MAX_LATERAL_DISTANCE_METERS ||
                    hasPreviousManeuverProjection &&
                    unconstrainedProjection.distanceAlongRouteMeters +
                    MANEUVER_GEOMETRY_ORDER_TOLERANCE_METERS < previousManeuverDistance
                ) {
                    return@let null
                }
                RouteProjectionCore.project(
                    pathPoints = pathPoints,
                    point = point,
                    minimumDistanceAlongRouteMeters =
                        (previousManeuverDistance - MANEUVER_GEOMETRY_ORDER_TOLERANCE_METERS)
                            .coerceAtLeast(0.0),
                )
            }?.takeIf {
                it.lateralDistanceMeters <= MANEUVER_GEOMETRY_MAX_LATERAL_DISTANCE_METERS
            }
            if (projection == null) return@forEach
            val maneuverGap = projection.distanceAlongRouteMeters - previousManeuverDistance
            if (
                hasPreviousManeuverProjection &&
                previousManeuverStep != null &&
                areOppositeTurnModifiers(
                    previousManeuverStep.maneuverModifier,
                    step.maneuverModifier,
                ) &&
                maneuverGap >= -MANEUVER_GEOMETRY_ORDER_TOLERANCE_METERS &&
                maneuverGap <= CLOSE_OPPOSITE_MANEUVER_DISTANCE_METERS
            ) {
                closeOppositeManeuvers += 1
            }
            previousManeuverStep = step
            previousManeuverDistance = maxOf(
                previousManeuverDistance,
                projection.distanceAlongRouteMeters,
            )
            hasPreviousManeuverProjection = true
        }
        val hasIncompleteGeometry = steps.isEmpty() || pathPoints.size < 2 || pathPoints.any { point ->
            !point.latitude.isFinite() || !point.longitude.isFinite() ||
                point.latitude !in -90.0..90.0 || point.longitude !in -180.0..180.0
        }
        val maneuverGeometryMismatches = if (hasIncompleteGeometry) {
            0
        } else {
            countManeuverGeometryMismatches(steps, pathPoints)
        }
        val qualityScore = if (hasIncompleteGeometry) {
            0
        } else {
            (100 -
                unnamedTurns.coerceAtMost(3) * 12 -
                repeatedInstructions.coerceAtMost(2) * 12 -
                missingManeuverData.coerceAtMost(2) * 20 -
                closeOppositeManeuvers.coerceAtMost(2) * 15 -
                maneuverGeometryMismatches.coerceAtMost(2) * 18).coerceIn(0, 100)
        }
        val confidencePercent = if (hasIncompleteGeometry) {
            0
        } else {
            (100 -
                missingManeuverData.coerceAtMost(5) * 15 -
                maneuverGeometryMismatches.coerceAtMost(3) * 10).coerceIn(0, 100)
        }
        val level = when {
            hasIncompleteGeometry -> RouteQualityLevel.InsufficientData
            issuesFor(
                unnamedTurns = unnamedTurns,
                repeatedInstructions = repeatedInstructions,
                missingManeuverData = missingManeuverData,
                closeOppositeManeuvers = closeOppositeManeuvers,
                maneuverGeometryMismatches = maneuverGeometryMismatches,
                hasIncompleteGeometry = hasIncompleteGeometry,
            ).isNotEmpty() -> RouteQualityLevel.Review
            else -> RouteQualityLevel.Good
        }
        return RouteQualityReport(
            stepCount = steps.size,
            unnamedTurnCount = unnamedTurns,
            repeatedInstructionCount = repeatedInstructions,
            missingManeuverDataCount = missingManeuverData,
            closeOppositeManeuverCount = closeOppositeManeuvers,
            maneuverGeometryMismatchCount = maneuverGeometryMismatches,
            hasIncompleteGeometry = hasIncompleteGeometry,
            qualityScore = qualityScore,
            confidencePercent = confidencePercent,
            level = level,
        )
    }

    private fun issuesFor(
        unnamedTurns: Int,
        repeatedInstructions: Int,
        missingManeuverData: Int,
        closeOppositeManeuvers: Int,
        maneuverGeometryMismatches: Int,
        hasIncompleteGeometry: Boolean,
    ): List<RouteQualityIssue> = buildList {
        if (unnamedTurns > 0) add(RouteQualityIssue.UnnamedTurn)
        if (repeatedInstructions > 0) add(RouteQualityIssue.RepeatedInstruction)
        if (missingManeuverData > 0) add(RouteQualityIssue.MissingManeuverData)
        if (closeOppositeManeuvers > 0) add(RouteQualityIssue.CloseOppositeManeuvers)
        if (maneuverGeometryMismatches > 0) add(RouteQualityIssue.ManeuverGeometryMismatch)
        if (hasIncompleteGeometry) add(RouteQualityIssue.IncompleteGeometry)
    }

    /** Weryfikuje, czy punkty skrętów pasują do przebiegu trasy i występują po kolei. */
    private fun countManeuverGeometryMismatches(
        steps: List<RouteStep>,
        pathPoints: List<GeoPoint>,
    ): Int {
        val maneuverSteps = steps.filter { step ->
            RouteStepSimplificationCore.isTurnLikeManeuver(step) &&
                !step.maneuverType.equals("approach", ignoreCase = true) &&
                step.maneuverPoint != null
        }
        if (maneuverSteps.isEmpty()) return 0

        var mismatches = 0
        var previousDistanceAlongRoute = 0.0
        var hasPreviousProjection = false
        maneuverSteps.forEach { step ->
            val point = step.maneuverPoint ?: run {
                mismatches += 1
                return@forEach
            }
            val unconstrainedProjection = RouteProjectionCore.project(
                pathPoints = pathPoints,
                point = point,
            )
            if (unconstrainedProjection == null ||
                unconstrainedProjection.lateralDistanceMeters >
                MANEUVER_GEOMETRY_MAX_LATERAL_DISTANCE_METERS
            ) {
                mismatches += 1
                return@forEach
            }
            if (hasPreviousProjection &&
                unconstrainedProjection.distanceAlongRouteMeters +
                MANEUVER_GEOMETRY_ORDER_TOLERANCE_METERS < previousDistanceAlongRoute
            ) {
                mismatches += 1
                return@forEach
            }
            val projection = RouteProjectionCore.project(
                pathPoints = pathPoints,
                point = point,
                minimumDistanceAlongRouteMeters =
                    (previousDistanceAlongRoute - MANEUVER_GEOMETRY_ORDER_TOLERANCE_METERS)
                        .coerceAtLeast(0.0),
            )
            if (projection == null || projection.lateralDistanceMeters > MANEUVER_GEOMETRY_MAX_LATERAL_DISTANCE_METERS) {
                mismatches += 1
                return@forEach
            }
            if (hasPreviousProjection &&
                projection.distanceAlongRouteMeters + MANEUVER_GEOMETRY_ORDER_TOLERANCE_METERS <
                previousDistanceAlongRoute
            ) {
                mismatches += 1
            }
            previousDistanceAlongRoute = maxOf(previousDistanceAlongRoute, projection.distanceAlongRouteMeters)
            hasPreviousProjection = true
        }
        return mismatches
    }

    private fun areOppositeTurnModifiers(left: String?, right: String?): Boolean {
        val normalizedLeft = left?.let(SharedProductRules.Instructions::normalizeModifier)
        val normalizedRight = right?.let(SharedProductRules.Instructions::normalizeModifier)
        val leftDirection = when {
            normalizedLeft?.contains("left") == true -> "left"
            normalizedLeft?.contains("right") == true -> "right"
            else -> null
        }
        val rightDirection = when {
            normalizedRight?.contains("left") == true -> "left"
            normalizedRight?.contains("right") == true -> "right"
            else -> null
        }
        return leftDirection != null && rightDirection != null && leftDirection != rightDirection
    }

    private fun normalize(value: String): String {
        return Normalizer.normalize(value, Normalizer.Form.NFD)
            .replace("\\p{M}+".toRegex(), "")
            .lowercase(Locale.ROOT)
            .replace("[^\\p{L}\\p{N}]+".toRegex(), " ")
            .replace("\\s+".toRegex(), " ")
            .trim()
    }
}
