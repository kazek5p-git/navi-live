import Foundation

struct LiveNavigationUpdate {
  let state: ActiveNavigationState
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
    var currentStepIndex: Int
  }

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
            maneuverPoint: destination.point
          )
        ]
      : summary.steps

    session = RouteSession(
      destination: destination,
      steps: normalizedSteps,
      pathPoints: summary.pathPoints,
      currentStepIndex: 0
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

    let deviation = routeDeviationMeters(pathPoints: session.pathPoints, point: fix.point)
    let isOffRoute = deviation != nil && deviation! > offRouteThresholdMeters(accuracyMeters: fix.accuracyMeters)
    let distanceToDestination = session.destination.point.map { Int(fix.point.distance(to: $0).rounded()) } ?? 0
    let arrivedThreshold = max(12, Int(fix.accuracyMeters.rounded()))

    if distanceToDestination > 0 && distanceToDestination <= arrivedThreshold {
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
        stepChanged: false,
        offRouteTriggered: false,
        shouldAutoRecalculate: false,
        hasArrived: true
      )
    }

    if isOffRoute, let deviation {
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
        stepChanged: false,
        offRouteTriggered: !previous.isOffRoute,
        shouldAutoRecalculate: autoRecalculate,
        hasArrived: false
      )
    }

    let nextStepIndex = resolveStepIndex(session: session, fix: fix)
    let stepChanged = nextStepIndex != session.currentStepIndex
    session.currentStepIndex = nextStepIndex
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
    now.timeIntervalSince(lastAutoRecalculateAt) >= 15
  }

  private func resolveStepIndex(session: RouteSession, fix: LocationFix) -> Int {
    var index = session.currentStepIndex
    let threshold = maneuverAdvanceThresholdMeters(accuracyMeters: fix.accuracyMeters)
    while index < session.steps.count - 1 {
      guard let nextManeuver = session.steps[index + 1].maneuverPoint else { break }
      if fix.point.distance(to: nextManeuver) <= threshold {
        index += 1
      } else {
        break
      }
    }
    return index
  }

  private func maneuverAdvanceThresholdMeters(accuracyMeters: Double) -> Double {
    min(max(accuracyMeters, 10), 20) * 1.5
  }

  private func offRouteThresholdMeters(accuracyMeters: Double) -> Int {
    max(Int((min(max(accuracyMeters, 15), 32) * 1.8).rounded()), 30)
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

    let distanceToNext: Int = {
      if let maneuverPoint = nextStep?.maneuverPoint, let fix {
        return max(Int(fix.point.distance(to: maneuverPoint).rounded()), 1)
      }
      if let nextStep, nextStep.distanceMeters > 0 {
        return nextStep.distanceMeters
      }
      if let destinationPoint = session.destination.point, let fix {
        return max(Int(fix.point.distance(to: destinationPoint).rounded()), 1)
      }
      return max(currentStep.distanceMeters, 1)
    }()

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
      distanceToNextMeters: distanceToNext,
      remainingDistanceMeters: max(remainingFromSteps, remainingFromDestination),
      progressLabel: L10n.text("active.progress", table: .navigation, safeIndex + 1, session.steps.count),
      isPaused: previous.isPaused,
      isOffRoute: isOffRoute,
      isRecalculating: isRecalculating,
      offRouteDistanceMeters: offRouteDistanceMeters
    )
  }

  private func routeDeviationMeters(pathPoints: [GeoPoint], point: GeoPoint) -> Int? {
    guard pathPoints.count >= 3 else { return nil }
    var minimumMeters = Double.greatestFiniteMagnitude
    for index in 0..<(pathPoints.count - 1) {
      let candidate = pointToSegmentDistanceMeters(
        point: point,
        start: pathPoints[index],
        end: pathPoints[index + 1]
      )
      minimumMeters = min(minimumMeters, candidate)
    }
    return Int(minimumMeters.rounded())
  }

  private func pointToSegmentDistanceMeters(point: GeoPoint, start: GeoPoint, end: GeoPoint) -> Double {
    let latitudeReference = ((point.latitude + start.latitude + end.latitude) / 3.0) * .pi / 180.0
    let earthRadius = 6_371_000.0

    func project(_ geoPoint: GeoPoint) -> (x: Double, y: Double) {
      let x = geoPoint.longitude * .pi / 180.0 * earthRadius * cos(latitudeReference)
      let y = geoPoint.latitude * .pi / 180.0 * earthRadius
      return (x, y)
    }

    let pointProjection = project(point)
    let startProjection = project(start)
    let endProjection = project(end)
    let dx = endProjection.x - startProjection.x
    let dy = endProjection.y - startProjection.y

    guard dx != 0 || dy != 0 else {
      return hypot(pointProjection.x - startProjection.x, pointProjection.y - startProjection.y)
    }

    let t = (((pointProjection.x - startProjection.x) * dx) + ((pointProjection.y - startProjection.y) * dy)) / ((dx * dx) + (dy * dy))
    let clamped = min(max(t, 0), 1)
    let nearestX = startProjection.x + (clamped * dx)
    let nearestY = startProjection.y + (clamped * dy)
    return hypot(pointProjection.x - nearestX, pointProjection.y - nearestY)
  }
}
