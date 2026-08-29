import Foundation

/// Konkretna przyczyna, dla której asystent zaleca ręczne sprawdzenie trasy.
enum RouteQualityIssue: String, Equatable, Hashable {
  case unnamedTurn
  case repeatedInstruction
  case missingManeuverData
  case closeOppositeManeuvers
  case maneuverGeometryMismatch
  case incompleteGeometry
}

/// Ogólny poziom wyniku lokalnej analizy. Nie jest oceną bezpieczeństwa trasy.
enum RouteQualityLevel: Equatable, Hashable {
  case good
  case review
  case insufficientData
}

/// Zalecenie dla interfejsu po analizie danych routera.
enum RouteQualityRecommendation: Equatable, Hashable {
  case followCurrentGuidance
  case reviewBeforeStarting
  case waitForCompleteData
}

/// Wynik ostrożnej, lokalnej analizy danych trasy.
struct RouteQualityReport: Equatable {
  let stepCount: Int
  let unnamedTurnCount: Int
  let repeatedInstructionCount: Int
  let missingManeuverDataCount: Int
  let closeOppositeManeuverCount: Int
  let maneuverGeometryMismatchCount: Int
  let hasIncompleteGeometry: Bool
  let qualityScore: Int
  let confidencePercent: Int
  let level: RouteQualityLevel

  /// Stabilna kolejność powoduje przewidywalny komunikat dla VoiceOvera.
  var issues: [RouteQualityIssue] {
    var result: [RouteQualityIssue] = []
    if unnamedTurnCount > 0 { result.append(.unnamedTurn) }
    if repeatedInstructionCount > 0 { result.append(.repeatedInstruction) }
    if missingManeuverDataCount > 0 { result.append(.missingManeuverData) }
    if closeOppositeManeuverCount > 0 { result.append(.closeOppositeManeuvers) }
    if maneuverGeometryMismatchCount > 0 { result.append(.maneuverGeometryMismatch) }
    if hasIncompleteGeometry { result.append(.incompleteGeometry) }
    return result
  }

  var issueCount: Int {
    unnamedTurnCount + repeatedInstructionCount + missingManeuverDataCount + closeOppositeManeuverCount +
      maneuverGeometryMismatchCount +
      (hasIncompleteGeometry ? 1 : 0)
  }

  var hasPotentialIssues: Bool {
    level != .good
  }

  var recommendation: RouteQualityRecommendation {
    switch level {
    case .good:
      return .followCurrentGuidance
    case .review:
      return .reviewBeforeStarting
    case .insufficientData:
      return .waitForCompleteData
    }
  }
}

/// Analizuje tylko dane routera, bez tworzenia nowych manewrów i bez wysyłania danych do sieci.
enum RouteQualityAnalyzer {
  private static let closeOppositeManeuverDistanceMeters = 60.0
  private static let maneuverGeometryMaxLateralDistanceMeters = 45.0
  private static let maneuverGeometryOrderToleranceMeters = 25.0

  static func analyze(steps: [RouteStep], pathPoints: [GeoPoint]) -> RouteQualityReport {
    let unnamedTurns = steps.filter { step in
      RouteStepSimplificationCore.isTurnLikeManeuver(step) &&
        step.maneuverType?.lowercased() != "approach" &&
        (step.roadName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }.count

    let repeatedInstructions = zip(steps, steps.dropFirst()).filter { left, right in
      let leftInstruction = normalize(left.instruction)
      let rightInstruction = normalize(right.instruction)
      return !leftInstruction.isEmpty &&
        leftInstruction == rightInstruction &&
        (left.distanceMeters <= 20 || right.distanceMeters <= 20)
    }.count
    let missingManeuverData = steps.filter { step in
      RouteStepSimplificationCore.isTurnLikeManeuver(step) &&
        step.maneuverType?.lowercased() != "approach" &&
        (step.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
          step.maneuverPoint == nil)
    }.count
    // Router może wstawić przejście dla pieszych między dwoma skrętami.
    // Porównujemy więc kolejne rzeczywiste manewry, a nie tylko sąsiednie wiersze.
    let maneuverSteps = steps.filter { step in
      RouteStepSimplificationCore.isTurnLikeManeuver(step) && step.maneuverPoint != nil
    }
    var previousManeuverStep: RouteStep?
    var previousManeuverDistance = 0.0
    var hasPreviousManeuverProjection = false
    var closeOppositeManeuvers = 0
    for step in maneuverSteps {
      let projection: RouteProgressProjection? = {
        guard let point = step.maneuverPoint,
              let unconstrainedProjection = RouteProjectionCore.project(
                pathPoints: pathPoints,
                point: point
              ),
              unconstrainedProjection.lateralDistanceMeters <= maneuverGeometryMaxLateralDistanceMeters,
              !hasPreviousManeuverProjection ||
                unconstrainedProjection.distanceAlongRouteMeters + maneuverGeometryOrderToleranceMeters >= previousManeuverDistance,
              let projection = RouteProjectionCore.project(
                pathPoints: pathPoints,
                point: point,
                minimumDistanceAlongRouteMeters: max(
                  previousManeuverDistance - maneuverGeometryOrderToleranceMeters,
                  0
                )
              ),
              projection.lateralDistanceMeters <= maneuverGeometryMaxLateralDistanceMeters else {
          return nil
        }
        return projection
      }()
      guard let projection else { continue }
      let maneuverGap = projection.distanceAlongRouteMeters - previousManeuverDistance
      if hasPreviousManeuverProjection,
         let previousManeuverStep,
         areOppositeTurnModifiers(previousManeuverStep.maneuverModifier, step.maneuverModifier),
         maneuverGap >= -maneuverGeometryOrderToleranceMeters,
         maneuverGap <= closeOppositeManeuverDistanceMeters {
        closeOppositeManeuvers += 1
      }
      previousManeuverStep = step
      previousManeuverDistance = max(previousManeuverDistance, projection.distanceAlongRouteMeters)
      hasPreviousManeuverProjection = true
    }

    let hasIncompleteGeometry = steps.isEmpty || pathPoints.count < 2 || pathPoints.contains { point in
      !point.latitude.isFinite || !point.longitude.isFinite ||
        !(-90.0...90.0).contains(point.latitude) || !(-180.0...180.0).contains(point.longitude)
    }
    let maneuverGeometryMismatches = hasIncompleteGeometry
      ? 0
      : countManeuverGeometryMismatches(steps: steps, pathPoints: pathPoints)
    let qualityScore: Int
    if hasIncompleteGeometry {
      qualityScore = 0
    } else {
      qualityScore = max(
        0,
        min(
          100,
          100 -
            min(unnamedTurns, 3) * 12 -
            min(repeatedInstructions, 2) * 12 -
            min(missingManeuverData, 2) * 20 -
            min(closeOppositeManeuvers, 2) * 15 -
            min(maneuverGeometryMismatches, 2) * 18
        )
      )
    }
    let confidencePercent = hasIncompleteGeometry
      ? 0
      : max(
        0,
        min(
          100,
          100 -
            min(missingManeuverData, 5) * 15 -
            min(maneuverGeometryMismatches, 3) * 10
        )
      )
    let level: RouteQualityLevel
    if hasIncompleteGeometry {
      level = .insufficientData
    } else if unnamedTurns > 0 || repeatedInstructions > 0 || missingManeuverData > 0 ||
      closeOppositeManeuvers > 0 || maneuverGeometryMismatches > 0 {
      level = .review
    } else {
      level = .good
    }

    return RouteQualityReport(
      stepCount: steps.count,
      unnamedTurnCount: unnamedTurns,
      repeatedInstructionCount: repeatedInstructions,
      missingManeuverDataCount: missingManeuverData,
      closeOppositeManeuverCount: closeOppositeManeuvers,
      maneuverGeometryMismatchCount: maneuverGeometryMismatches,
      hasIncompleteGeometry: hasIncompleteGeometry,
      qualityScore: qualityScore,
      confidencePercent: confidencePercent,
      level: level
    )
  }

  /// Weryfikuje, czy punkty skrętów pasują do przebiegu trasy i występują po kolei.
  private static func countManeuverGeometryMismatches(
    steps: [RouteStep],
    pathPoints: [GeoPoint]
  ) -> Int {
    let maneuverSteps = steps.filter { step in
      RouteStepSimplificationCore.isTurnLikeManeuver(step) &&
        step.maneuverType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "approach" &&
        step.maneuverPoint != nil
    }
    guard !maneuverSteps.isEmpty else { return 0 }

    var mismatches = 0
    var previousDistanceAlongRoute = 0.0
    var hasPreviousProjection = false
    for step in maneuverSteps {
      guard let point = step.maneuverPoint,
            let unconstrainedProjection = RouteProjectionCore.project(
              pathPoints: pathPoints,
              point: point
            ),
            unconstrainedProjection.lateralDistanceMeters <= maneuverGeometryMaxLateralDistanceMeters else {
        mismatches += 1
        continue
      }
      if hasPreviousProjection &&
        unconstrainedProjection.distanceAlongRouteMeters + maneuverGeometryOrderToleranceMeters < previousDistanceAlongRoute {
        mismatches += 1
        continue
      }
      guard let projection = RouteProjectionCore.project(
        pathPoints: pathPoints,
        point: point,
        minimumDistanceAlongRouteMeters: max(
          previousDistanceAlongRoute - maneuverGeometryOrderToleranceMeters,
          0
        )
      ),
      projection.lateralDistanceMeters <= maneuverGeometryMaxLateralDistanceMeters else {
        mismatches += 1
        continue
      }
      if hasPreviousProjection &&
        projection.distanceAlongRouteMeters + maneuverGeometryOrderToleranceMeters < previousDistanceAlongRoute {
        mismatches += 1
      }
      previousDistanceAlongRoute = max(previousDistanceAlongRoute, projection.distanceAlongRouteMeters)
      hasPreviousProjection = true
    }
    return mismatches
  }

  private static func areOppositeTurnModifiers(_ left: String?, _ right: String?) -> Bool {
    let leftValue = left.map { SharedProductRules.Instructions.normalizeModifier($0) }
    let rightValue = right.map { SharedProductRules.Instructions.normalizeModifier($0) }
    let leftDirection = leftValue?.contains("left") == true
      ? "left"
      : (leftValue?.contains("right") == true ? "right" : nil)
    let rightDirection = rightValue?.contains("left") == true
      ? "left"
      : (rightValue?.contains("right") == true ? "right" : nil)
    return leftDirection != nil && rightDirection != nil && leftDirection != rightDirection
  }

  private static func normalize(_ value: String) -> String {
    value
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
