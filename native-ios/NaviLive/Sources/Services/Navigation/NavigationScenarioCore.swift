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
