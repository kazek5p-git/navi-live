import Foundation

struct LiveNavigationUpdate {
  let state: ActiveNavigationState
  let currentStepIndex: Int
  let upcomingInstruction: String?
  let currentStepKind: RouteStepKind
  let upcomingStepKind: RouteStepKind?
  let stepChanged: Bool
  let offRouteTriggered: Bool
  let shouldAutoRecalculate: Bool
  let hasArrived: Bool
}

final class LiveNavigationEngine {
  private struct RouteSession {
    let destination: Place
    let steps: [RouteStep]
    let pathPoints: [GeoPoint]
    let stepDistancesAlongRoute: [Double]
    var currentStepIndex: Int
    var lastProjectedDistanceAlongRouteMeters: Double
  }

  private static let approachManeuverType = "approach"

  private var session: RouteSession?
  private var lastAutoRecalculateAt: Date = .distantPast

  var currentDestination: Place? {
    session?.destination
  }

  func loadRoute(destination: Place, summary: RouteSummary, fix: LocationFix?) -> ActiveNavigationState {
    let normalizedSteps = summary.steps.isEmpty
      ? [
          RouteStep(
            instruction: summary.currentInstruction.isEmpty
              ? L10n.text("route.follow_default", table: .navigation)
              : summary.currentInstruction,
            distanceMeters: max(summary.distanceMeters, 1),
            maneuverPoint: destination.point,
            roadName: destination.name
          )
        ]
      : summary.steps

    let stepDistances = stepDistancesAlongRoute(
      steps: normalizedSteps,
      pathPoints: summary.pathPoints
    )
    session = RouteSession(
      destination: destination,
      steps: normalizedSteps,
      pathPoints: summary.pathPoints,
      stepDistancesAlongRoute: stepDistances,
      currentStepIndex: 0,
      lastProjectedDistanceAlongRouteMeters: 0
    )

    return buildState(
      currentStepIndex: 0,
      fix: fix,
      previous: ActiveNavigationState(),
      isOffRoute: false,
      isRecalculating: false,
      offRouteDistanceMeters: nil
    )
  }

  func rebuildCurrentState(fix: LocationFix?, previous: ActiveNavigationState) -> ActiveNavigationState? {
    guard let session else { return nil }
    return buildState(
      currentStepIndex: session.currentStepIndex,
      fix: fix,
      previous: previous,
      isOffRoute: false,
      isRecalculating: false,
      offRouteDistanceMeters: nil
    )
  }

  func update(
    fix: LocationFix,
    previous: ActiveNavigationState,
    autoRecalculateEnabled: Bool
  ) -> LiveNavigationUpdate? {
    guard var session else { return nil }

    let deviation = routeDeviationMeters(session: session, fix: fix)
    let isOffRoute = NavigationScenarioCore.shouldTriggerOffRoute(
      deviationMeters: deviation,
      accuracyMeters: fix.accuracyMeters
    )
    let distanceToDestination = session.destination.point.map { fix.point.distance(to: $0) }
    let routeProgressForArrival = routeProgressProjection(
      session: session,
      point: fix.point,
      currentStepIndex: session.currentStepIndex,
      fix: fix
    )

    if NavigationScenarioCore.shouldMarkArrived(
      distanceToDestinationMeters: distanceToDestination,
      remainingRouteMeters: routeProgressForArrival?.remainingRouteMeters,
      accuracyMeters: fix.accuracyMeters
    ) {
      let state = buildState(
        currentStepIndex: session.currentStepIndex,
        fix: fix,
        previous: previous,
        isOffRoute: false,
        isRecalculating: false,
        offRouteDistanceMeters: nil
      )
      return LiveNavigationUpdate(
        state: state,
        currentStepIndex: session.currentStepIndex,
        upcomingInstruction: session.steps[safe: session.currentStepIndex + 1]?.instruction,
        currentStepKind: session.steps[safe: session.currentStepIndex]?.kind ?? .instruction,
        upcomingStepKind: session.steps[safe: session.currentStepIndex + 1]?.kind,
        stepChanged: false,
        offRouteTriggered: false,
        shouldAutoRecalculate: false,
        hasArrived: true
      )
    }

    let isApproachingRouteStart = session.steps[safe: session.currentStepIndex]?.maneuverType == Self.approachManeuverType
    if !isApproachingRouteStart, isOffRoute, let deviation {
      let state = buildState(
        currentStepIndex: session.currentStepIndex,
        fix: fix,
        previous: previous,
        isOffRoute: true,
        isRecalculating: previous.isRecalculating,
        offRouteDistanceMeters: deviation
      )
      let autoRecalculate = autoRecalculateEnabled && shouldAutoRecalculate(now: fix.timestamp)
      if autoRecalculate {
        lastAutoRecalculateAt = fix.timestamp
      }
      return LiveNavigationUpdate(
        state: state,
        currentStepIndex: session.currentStepIndex,
        upcomingInstruction: session.steps[safe: session.currentStepIndex + 1]?.instruction,
        currentStepKind: session.steps[safe: session.currentStepIndex]?.kind ?? .instruction,
        upcomingStepKind: session.steps[safe: session.currentStepIndex + 1]?.kind,
        stepChanged: false,
        offRouteTriggered: !previous.isOffRoute,
        shouldAutoRecalculate: autoRecalculate,
        hasArrived: false
      )
    }

    let progressBeforeStepChange = routeProgressProjection(
      session: session,
      point: fix.point,
      currentStepIndex: session.currentStepIndex,
      fix: fix
    )
    let nextStepIndex = resolveStepIndex(session: session, fix: fix)
    let stepChanged = nextStepIndex != session.currentStepIndex
    session.currentStepIndex = nextStepIndex
    let progressAfterStepChange = routeProgressProjection(
      session: session,
      point: fix.point,
      currentStepIndex: nextStepIndex,
      fix: fix
    ) ?? progressBeforeStepChange
    session.lastProjectedDistanceAlongRouteMeters = max(
      session.lastProjectedDistanceAlongRouteMeters,
      progressAfterStepChange?.distanceAlongRouteMeters ?? 0
    )
    self.session = session

    let state = buildState(
      currentStepIndex: nextStepIndex,
      fix: fix,
      previous: previous,
      isOffRoute: false,
      isRecalculating: false,
      offRouteDistanceMeters: nil
    )

    return LiveNavigationUpdate(
      state: state,
      currentStepIndex: nextStepIndex,
      upcomingInstruction: session.steps[safe: nextStepIndex + 1]?.instruction,
      currentStepKind: session.steps[safe: nextStepIndex]?.kind ?? .instruction,
      upcomingStepKind: session.steps[safe: nextStepIndex + 1]?.kind,
      stepChanged: stepChanged,
      offRouteTriggered: false,
      shouldAutoRecalculate: false,
      hasArrived: false
    )
  }

  func reset() {
    session = nil
    lastAutoRecalculateAt = .distantPast
  }

  private func shouldAutoRecalculate(now: Date) -> Bool {
    NavigationScenarioCore.shouldAllowAutoRecalculate(
      isRouteRecalculating: false,
      elapsedSinceLastRecalculateMs: Int((now.timeIntervalSince(lastAutoRecalculateAt) * 1000.0).rounded())
    )
  }

  private func resolveStepIndex(session: RouteSession, fix: LocationFix) -> Int {
    var index = session.currentStepIndex
    while index < session.steps.count - 1 {
      let currentStep = session.steps[safe: index]
      if currentStep?.maneuverType == Self.approachManeuverType {
        guard let approachTarget = currentStep?.maneuverPoint else { break }
        if NavigationScenarioCore.shouldAdvanceStep(
          distanceToManeuverMeters: fix.point.distance(to: approachTarget),
          accuracyMeters: fix.accuracyMeters
        ) {
          index += 1
          continue
        }
        break
      }
      guard let nextManeuver = session.steps[safe: index + 1]?.maneuverPoint else { break }
      let projectedProgress = routeProgressProjection(
        session: session,
        point: fix.point,
        currentStepIndex: index,
        fix: fix
      )
      let nextDistanceAlongRoute = session.stepDistancesAlongRoute[safe: index + 1] ?? .greatestFiniteMagnitude
      let hasPassedManeuver = projectedProgress != nil &&
        NavigationScenarioCore.hasPassedManeuverPoint(
          projectedDistanceAlongRouteMeters: projectedProgress!.distanceAlongRouteMeters,
          maneuverDistanceAlongRouteMeters: nextDistanceAlongRoute,
          accuracyMeters: fix.accuracyMeters
        )
      let fallbackPassedManeuver = projectedProgress == nil &&
        fix.point.distance(to: nextManeuver) <=
        NavigationScenarioCore.maneuverPassThresholdMeters(accuracyMeters: fix.accuracyMeters)
      if hasPassedManeuver {
        index += 1
        continue
      }
      if fallbackPassedManeuver {
        index += 1
        break
      } else {
        break
      }
    }
    return index
  }

  private func buildState(
    currentStepIndex: Int,
    fix: LocationFix?,
    previous: ActiveNavigationState,
    isOffRoute: Bool,
    isRecalculating: Bool,
    offRouteDistanceMeters: Int?
  ) -> ActiveNavigationState {
    guard let session else {
      return ActiveNavigationState()
    }

    let safeIndex = min(max(currentStepIndex, 0), session.steps.count - 1)
    let currentStep = session.steps[safeIndex]
    let nextStep = safeIndex < session.steps.count - 1 ? session.steps[safeIndex + 1] : nil
    let routeProgress = fix.flatMap {
      routeProgressProjection(
        session: session,
        point: $0.point,
        currentStepIndex: safeIndex,
        fix: $0
      ) ??
        routeProgressProjection(pathPoints: session.pathPoints, point: $0.point)
    }

    let rawDistanceToNext: Int = {
      if currentStep.maneuverType == Self.approachManeuverType,
         let maneuverPoint = currentStep.maneuverPoint,
         let fix {
        return max(Int(fix.point.distance(to: maneuverPoint).rounded()), 1)
      }
      if nextStep != nil, let routeProgress {
        let nextDistance = session.stepDistancesAlongRoute[safe: safeIndex + 1] ?? routeProgress.distanceAlongRouteMeters
        return max(Int((nextDistance - routeProgress.distanceAlongRouteMeters).rounded()), 0)
      }
      if let maneuverPoint = nextStep?.maneuverPoint, let fix {
        return max(Int(fix.point.distance(to: maneuverPoint).rounded()), 1)
      }
      if let nextStep, nextStep.distanceMeters > 0 {
        return nextStep.distanceMeters
      }
      if let destinationPoint = session.destination.point, let fix {
        return max(Int(fix.point.distance(to: destinationPoint).rounded()), 0)
      }
      return max(currentStep.distanceMeters, 1)
    }()
    let distanceToNext = currentStep.maneuverType == Self.approachManeuverType
      ? rawDistanceToNext
      : adjustedGuidanceDistanceToNext(rawDistanceToNext, upcomingStep: nextStep)

    let remainingFromSteps = session.steps.dropFirst(safeIndex).reduce(0) { $0 + $1.distanceMeters }
    let remainingFromDestination = {
      if let destinationPoint = session.destination.point, let fix {
        return Int(fix.point.distance(to: destinationPoint).rounded())
      }
      return 0
    }()

    return ActiveNavigationState(
      currentInstruction: currentStep.instruction,
      nextInstruction: nextStep?.instruction ?? L10n.text("active.destination_ahead", table: .navigation),
      currentStepIndex: safeIndex,
      distanceToNextMeters: distanceToNext,
      remainingDistanceMeters: routeProgress.map { max(Int($0.remainingRouteMeters.rounded()), 0) } ?? max(remainingFromSteps, remainingFromDestination),
      progressLabel: L10n.text("active.progress", table: .navigation, safeIndex + 1, session.steps.count),
      isPaused: previous.isPaused,
      isOffRoute: isOffRoute,
      isRecalculating: isRecalculating,
      offRouteDistanceMeters: offRouteDistanceMeters
    )
  }

  private func adjustedGuidanceDistanceToNext(_ rawDistanceMeters: Int, upcomingStep: RouteStep?) -> Int {
    guard shouldApplyGuidanceLead(to: upcomingStep) else { return rawDistanceMeters }
    return max(rawDistanceMeters - SharedProductRules.Navigation.guidanceLeadMeters, 0)
  }

  private func shouldApplyGuidanceLead(to step: RouteStep?) -> Bool {
    guard let step, step.kind != .pedestrianCrossing else { return false }
    return step.maneuverType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "arrive"
  }

  private func routeDeviationMeters(session: RouteSession, fix: LocationFix) -> Int? {
    guard session.pathPoints.count >= 2 else { return nil }
    let routeLength = routeLengthMeters(session.pathPoints)
    guard routeLength > 0 else { return nil }
    let minimumAlong = max(
      session.lastProjectedDistanceAlongRouteMeters -
        SharedProductRules.Navigation.routeProjectionBacktrackToleranceMeters,
      0
    )
    let maximumAlong = min(
      session.lastProjectedDistanceAlongRouteMeters +
        SharedProductRules.Navigation.routeProjectionDeviationLookAheadMeters,
      routeLength
    )
    return routeProgressProjection(
      pathPoints: session.pathPoints,
      point: fix.point,
      minimumDistanceAlongRouteMeters: minimumAlong,
      maximumDistanceAlongRouteMeters: maximumAlong,
      fix: fix,
      monotonicFloorMeters: session.lastProjectedDistanceAlongRouteMeters
    )
      .map { Int($0.lateralDistanceMeters.rounded()) }
  }

  private func routeLengthMeters(_ pathPoints: [GeoPoint]) -> Double {
    RouteProjectionCore.routeLengthMeters(pathPoints)
  }

  private func stepDistancesAlongRoute(
    steps: [RouteStep],
    pathPoints: [GeoPoint]
  ) -> [Double] {
    RouteProjectionCore.stepDistancesAlongRoute(steps: steps, pathPoints: pathPoints)
  }

  private func routeProgressProjection(
    session: RouteSession,
    point: GeoPoint,
    currentStepIndex: Int,
    fix: LocationFix
  ) -> RouteProgressProjection? {
    let routeLength = routeLengthMeters(session.pathPoints)
    let currentAlong = session.stepDistancesAlongRoute[safe: currentStepIndex] ?? 0
    let nextAlong = session.stepDistancesAlongRoute[safe: currentStepIndex + 1] ?? routeLength
    let backtrackTolerance = SharedProductRules.Navigation.routeProjectionBacktrackToleranceMeters
    let lookAheadTolerance = SharedProductRules.Navigation.routeProjectionLookAheadToleranceMeters
    let minimumAlong = max(
      max(currentAlong - backtrackTolerance, 0),
      max(session.lastProjectedDistanceAlongRouteMeters - backtrackTolerance, 0)
    )
    let maximumAlong = min(
      max(
        nextAlong + lookAheadTolerance,
        session.lastProjectedDistanceAlongRouteMeters + backtrackTolerance
      ),
      routeLength
    )
    return routeProgressProjection(
      pathPoints: session.pathPoints,
      point: point,
      minimumDistanceAlongRouteMeters: minimumAlong,
      maximumDistanceAlongRouteMeters: maximumAlong,
      fix: fix,
      monotonicFloorMeters: session.lastProjectedDistanceAlongRouteMeters
    )
  }

  private func routeProgressProjection(
    pathPoints: [GeoPoint],
    point: GeoPoint,
    minimumDistanceAlongRouteMeters: Double = 0,
    maximumDistanceAlongRouteMeters: Double = .greatestFiniteMagnitude,
    fix: LocationFix? = nil,
    monotonicFloorMeters: Double? = nil
  ) -> RouteProgressProjection? {
    return RouteProjectionCore.project(
      pathPoints: pathPoints,
      point: point,
      minimumDistanceAlongRouteMeters: minimumDistanceAlongRouteMeters,
      maximumDistanceAlongRouteMeters: maximumDistanceAlongRouteMeters,
      preferredCourseDegrees: fix?.courseDegrees,
      speedMetersPerSecond: fix?.speedMetersPerSecond,
      accuracyMeters: fix?.accuracyMeters,
      monotonicFloorMeters: monotonicFloorMeters
    )
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
