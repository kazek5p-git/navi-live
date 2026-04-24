import Foundation

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
}
