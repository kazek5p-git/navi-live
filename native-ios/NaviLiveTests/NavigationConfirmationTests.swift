import XCTest
@testable import NaviLive

final class NavigationConfirmationTests: XCTestCase {
  func testStepChangeRequiresTwoConsecutiveFixes() {
    let first = NavigationScenarioCore.confirmStepCandidate(
      currentStepIndex: 0,
      candidateStepIndex: 1,
      pendingStepIndex: nil,
      consecutiveFixes: 0
    )
    XCTAssertNil(first.confirmedStepIndex)
    XCTAssertEqual(first.pendingStepIndex, 1)
    XCTAssertEqual(first.consecutiveFixes, 1)

    let second = NavigationScenarioCore.confirmStepCandidate(
      currentStepIndex: 0,
      candidateStepIndex: 1,
      pendingStepIndex: first.pendingStepIndex,
      consecutiveFixes: first.consecutiveFixes
    )
    XCTAssertEqual(second.confirmedStepIndex, 1)
    XCTAssertNil(second.pendingStepIndex)
    XCTAssertEqual(second.consecutiveFixes, 0)
  }

  func testDifferentStepCandidateClearsPendingConfirmation() {
    let decision = NavigationScenarioCore.confirmStepCandidate(
      currentStepIndex: 2,
      candidateStepIndex: 1,
      pendingStepIndex: 3,
      consecutiveFixes: 1
    )

    XCTAssertNil(decision.confirmedStepIndex)
    XCTAssertNil(decision.pendingStepIndex)
    XCTAssertEqual(decision.consecutiveFixes, 0)
  }

  func testLeavingRouteRequiresThreeFixesAndRecoveryRequiresTwo() {
    var consecutiveOffRouteFixes = 0
    for _ in 0..<2 {
      let decision = NavigationScenarioCore.confirmRouteStatus(
        currentlyOffRoute: false,
        measurementIsOffRoute: true,
        consecutiveOffRouteFixes: consecutiveOffRouteFixes,
        consecutiveOnRouteFixes: 0
      )
      consecutiveOffRouteFixes = decision.consecutiveOffRouteFixes
      XCTAssertFalse(decision.offRouteConfirmed)
    }

    let confirmed = NavigationScenarioCore.confirmRouteStatus(
      currentlyOffRoute: false,
      measurementIsOffRoute: true,
      consecutiveOffRouteFixes: consecutiveOffRouteFixes,
      consecutiveOnRouteFixes: 0
    )
    XCTAssertTrue(confirmed.offRouteConfirmed)

    let firstRecovery = NavigationScenarioCore.confirmRouteStatus(
      currentlyOffRoute: true,
      measurementIsOffRoute: false,
      consecutiveOffRouteFixes: confirmed.consecutiveOffRouteFixes,
      consecutiveOnRouteFixes: 0
    )
    XCTAssertFalse(firstRecovery.recoveryConfirmed)

    let recovered = NavigationScenarioCore.confirmRouteStatus(
      currentlyOffRoute: true,
      measurementIsOffRoute: false,
      consecutiveOffRouteFixes: firstRecovery.consecutiveOffRouteFixes,
      consecutiveOnRouteFixes: firstRecovery.consecutiveOnRouteFixes
    )
    XCTAssertTrue(recovered.recoveryConfirmed)
  }

  func testSpeechWaitsHalfASecondAfterQueuedSoundPlayback() {
    XCTAssertEqual(
      NavigationScenarioCore.speechDelayAfterSound(soundPlaybackDelay: 0),
      0.5,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      NavigationScenarioCore.speechDelayAfterSound(soundPlaybackDelay: 0.84),
      1.34,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      NavigationScenarioCore.speechDelayAfterSound(soundPlaybackDelay: -0.05),
      0.5,
      accuracy: 0.0001
    )
  }

  func testCrossingFilterRejectsParallelAndShallowGeometry() {
    XCTAssertTrue(
      NavigationScenarioCore.isMeaningfulCrossing(
        crossingAngleDegrees: 90,
        minimumBearingDifferenceDegrees: 55
      )
    )
    XCTAssertFalse(
      NavigationScenarioCore.isMeaningfulCrossing(
        crossingAngleDegrees: 54.9,
        minimumBearingDifferenceDegrees: 55
      )
    )
    XCTAssertFalse(
      NavigationScenarioCore.isMeaningfulCrossing(
        crossingAngleDegrees: 0,
        minimumBearingDifferenceDegrees: 55
      )
    )
    XCTAssertFalse(
      NavigationScenarioCore.isMeaningfulCrossing(
        crossingAngleDegrees: .nan,
        minimumBearingDifferenceDegrees: 55
      )
    )
  }
}
