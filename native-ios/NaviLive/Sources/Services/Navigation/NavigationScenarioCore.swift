import Foundation

struct HeadingAlignment: Equatable {
  let signedDeltaDegrees: Double
  let isAligned: Bool
  let isAlmostAligned: Bool
}

struct StepConfirmationDecision: Equatable {
  let confirmedStepIndex: Int?
  let pendingStepIndex: Int?
  let consecutiveFixes: Int
}

struct RouteStatusConfirmationDecision: Equatable {
  let offRouteConfirmed: Bool
  let recoveryConfirmed: Bool
  let consecutiveOffRouteFixes: Int
  let consecutiveOnRouteFixes: Int
}

enum NavigationScenarioCore {
  static func maneuverAdvanceThresholdMeters(accuracyMeters: Double) -> Double {
    min(
      max(accuracyMeters, SharedProductRules.Navigation.maneuverAdvanceAccuracyMinMeters),
      SharedProductRules.Navigation.maneuverAdvanceAccuracyMaxMeters
    ) * SharedProductRules.Navigation.maneuverAdvanceMultiplier
  }

  static func offRouteThresholdMeters(accuracyMeters: Double) -> Int {
    max(
      Int(
        (
          min(
            max(accuracyMeters, SharedProductRules.Navigation.offRouteAccuracyMinMeters),
            SharedProductRules.Navigation.offRouteAccuracyMaxMeters
          ) * SharedProductRules.Navigation.offRouteMultiplier
        ).rounded()
      ),
      SharedProductRules.Navigation.offRouteMinimumThresholdMeters
    )
  }

  static func immediateAnnouncementThresholdMeters(accuracyMeters: Double) -> Int {
    let clampedAccuracy = min(
      max(accuracyMeters, SharedProductRules.Navigation.immediateInstructionAccuracyMinMeters),
      SharedProductRules.Navigation.immediateInstructionAccuracyMaxMeters
    )
    return min(
      max(
        Int(clampedAccuracy.rounded()),
        SharedProductRules.Navigation.immediateInstructionThresholdMinMeters
      ),
      SharedProductRules.Navigation.immediateInstructionThresholdMaxMeters
    )
  }

  static func maneuverActivationLeadMeters(accuracyMeters: Double) -> Double {
    Double(SharedProductRules.Navigation.guidanceLeadMeters + immediateAnnouncementThresholdMeters(accuracyMeters: accuracyMeters))
  }

  static func maneuverPassThresholdMeters(accuracyMeters: Double) -> Double {
    min(max(accuracyMeters, 5), 12)
  }

  static func arrivalThresholdMeters(accuracyMeters: Double) -> Double {
    min(
      max(accuracyMeters, SharedProductRules.Navigation.arrivalAccuracyMinMeters),
      SharedProductRules.Navigation.arrivalAccuracyMaxMeters
    ) * SharedProductRules.Navigation.arrivalAccuracyMultiplier
  }

  static func shouldMarkArrived(
    distanceToDestinationMeters: Double?,
    remainingRouteMeters: Double?,
    accuracyMeters: Double
  ) -> Bool {
    let validDistances: [Double] = [distanceToDestinationMeters, remainingRouteMeters]
      .compactMap { value in
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
      }
    let nearestDistance = validDistances.min() ?? .greatestFiniteMagnitude
    return nearestDistance <= arrivalThresholdMeters(accuracyMeters: accuracyMeters)
  }

  static func hasPassedManeuverPoint(
    projectedDistanceAlongRouteMeters: Double,
    maneuverDistanceAlongRouteMeters: Double,
    accuracyMeters: Double
  ) -> Bool {
    projectedDistanceAlongRouteMeters >=
      maneuverDistanceAlongRouteMeters + maneuverPassThresholdMeters(accuracyMeters: accuracyMeters)
  }

  static func countdownMilestoneMeters(distanceToNext: Int) -> Int? {
    SharedProductRules.Navigation.countdownMilestonesMeters.first { distanceToNext <= $0 }
  }

  static func countdownMilestoneSeconds(secondsToNext: Int) -> Int? {
    SharedProductRules.Navigation.countdownMilestonesSeconds.first { secondsToNext <= $0 }
  }

  static func estimatedSecondsToManeuver(distanceToNextMeters: Int) -> Int {
    let walkingSeconds = (
      Double(max(distanceToNextMeters, 0)) /
      SharedProductRules.Search.walkingEtaMetersPerMinute
    ) * 60.0
    return max(Int(walkingSeconds.rounded(.up)), 1)
  }

  static func distanceBasedEtaMinutes(distanceMeters: Int) -> Int {
    let walkingMinutes = Double(max(distanceMeters, 0)) / SharedProductRules.Search.walkingEtaMetersPerMinute
    return max(Int(walkingMinutes.rounded(.up)), 1)
  }

  static func routeEtaMinutes(distanceMeters: Int, providerDurationSeconds: Double) -> Int {
    let providerMinutes = max(Int((max(providerDurationSeconds, 0) / 60.0).rounded(.up)), 1)
    return max(distanceBasedEtaMinutes(distanceMeters: distanceMeters), providerMinutes)
  }

  static func shouldAdvanceStep(distanceToManeuverMeters: Double, accuracyMeters: Double) -> Bool {
    distanceToManeuverMeters <= maneuverAdvanceThresholdMeters(accuracyMeters: accuracyMeters)
  }

  /// Dodaje pół sekundy po zakończeniu dźwięku, zanim rozpocznie się mowa.
  static func speechDelayAfterSound(soundPlaybackDelay: TimeInterval) -> TimeInterval {
    max(soundPlaybackDelay, 0) +
      TimeInterval(SharedProductRules.Navigation.speechAfterSoundDelayMs) / 1000.0
  }

  /// Odrzuca geometrię biegnącą równolegle lub prawie równolegle do trasy.
  static func isMeaningfulCrossing(
    crossingAngleDegrees: Double,
    minimumBearingDifferenceDegrees: Double
  ) -> Bool {
    crossingAngleDegrees.isFinite &&
      minimumBearingDifferenceDegrees.isFinite &&
      (0...90).contains(minimumBearingDifferenceDegrees) &&
      (0...90).contains(crossingAngleDegrees) &&
      crossingAngleDegrees >= minimumBearingDifferenceDegrees
  }

  /// Wymaga dwóch kolejnych pomiarów wskazujących ten sam następny krok.
  static func confirmStepCandidate(
    currentStepIndex: Int,
    candidateStepIndex: Int,
    pendingStepIndex: Int?,
    consecutiveFixes: Int
  ) -> StepConfirmationDecision {
    guard candidateStepIndex > currentStepIndex else {
      return StepConfirmationDecision(
        confirmedStepIndex: nil,
        pendingStepIndex: nil,
        consecutiveFixes: 0
      )
    }

    let nextFixes = pendingStepIndex == candidateStepIndex ? consecutiveFixes + 1 : 1
    if nextFixes >= SharedProductRules.Navigation.stepConfirmationRequiredFixes {
      return StepConfirmationDecision(
        confirmedStepIndex: candidateStepIndex,
        pendingStepIndex: nil,
        consecutiveFixes: 0
      )
    }
    return StepConfirmationDecision(
      confirmedStepIndex: nil,
      pendingStepIndex: candidateStepIndex,
      consecutiveFixes: nextFixes
    )
  }

  /// Odfiltrowuje pojedyncze skoki GPS poza trasę i pojedyncze powroty.
  static func confirmRouteStatus(
    currentlyOffRoute: Bool,
    measurementIsOffRoute: Bool,
    consecutiveOffRouteFixes: Int,
    consecutiveOnRouteFixes: Int
  ) -> RouteStatusConfirmationDecision {
    guard currentlyOffRoute else {
      let nextOffRouteFixes = measurementIsOffRoute ? consecutiveOffRouteFixes + 1 : 0
      return RouteStatusConfirmationDecision(
        offRouteConfirmed: measurementIsOffRoute &&
          nextOffRouteFixes >= SharedProductRules.Navigation.offRouteConfirmationRequiredFixes,
        recoveryConfirmed: false,
        consecutiveOffRouteFixes: nextOffRouteFixes,
        consecutiveOnRouteFixes: 0
      )
    }

    let nextOnRouteFixes = measurementIsOffRoute ? 0 : consecutiveOnRouteFixes + 1
    return RouteStatusConfirmationDecision(
      offRouteConfirmed: measurementIsOffRoute,
      recoveryConfirmed: !measurementIsOffRoute &&
        nextOnRouteFixes >= SharedProductRules.Navigation.offRouteRecoveryRequiredFixes,
      consecutiveOffRouteFixes: measurementIsOffRoute
        ? SharedProductRules.Navigation.offRouteConfirmationRequiredFixes
        : 0,
      consecutiveOnRouteFixes: nextOnRouteFixes
    )
  }

  static func shouldTriggerOffRoute(deviationMeters: Int?, accuracyMeters: Double) -> Bool {
    guard let deviationMeters else { return false }
    return deviationMeters > offRouteThresholdMeters(accuracyMeters: accuracyMeters)
  }

  static func shouldAllowAutoRecalculate(
    isRouteRecalculating: Bool,
    elapsedSinceLastRecalculateMs: Int
  ) -> Bool {
    !isRouteRecalculating &&
      elapsedSinceLastRecalculateMs >= SharedProductRules.Navigation.autoRecalculateCooldownMs
  }

  static func isFreshLocation(
    timestamp: Date?,
    now: Date,
    maximumAge: TimeInterval = TimeInterval(SharedProductRules.Navigation.assistantFreshLocationMaxAgeMs) / 1000.0
  ) -> Bool {
    guard let timestamp else { return false }
    let age = now.timeIntervalSince(timestamp)
    return (-5.0...maximumAge).contains(age)
  }

  /// Oblicza najkrótszą korektę obrotu telefonu względem kierunku trasy.
  static func headingAlignment(
    currentHeadingDegrees: Double,
    routeBearingDegrees: Double
  ) -> HeadingAlignment? {
    guard currentHeadingDegrees.isFinite, routeBearingDegrees.isFinite else { return nil }
    let signedDelta = ((routeBearingDegrees - currentHeadingDegrees + 540).truncatingRemainder(dividingBy: 360)) - 180
    let absoluteDelta = abs(signedDelta)
    return HeadingAlignment(
      signedDeltaDegrees: signedDelta,
      isAligned: absoluteDelta <= 15,
      isAlmostAligned: absoluteDelta <= 35
    )
  }
}
