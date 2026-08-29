import XCTest
@testable import NaviLive

final class RouteAssistantCoreTests: XCTestCase {
  func testClassifiesPolishOverviewQuestion() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Podsumuj trasę"),
      .routeOverview
    )
  }

  func testClassifiesCurrentInstructionWithDiacritics() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Co mam teraz zrobić?"),
      .currentInstruction
    )
  }

  func testClassifiesCurrentLocationQuestion() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Gdzie jestem?"),
      .currentLocation
    )
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Jaki mam adres?"),
      .currentLocation
    )
  }

  func testClassifiesNaturalShortCurrentInstructionQuestion() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Co teraz?"),
      .currentInstruction
    )
  }

  func testClassifiesRepeatCommandWithoutGuessingAnotherIntent() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Powtórz"),
      .repeatInstruction
    )
    XCTAssertFalse(RouteAssistantCore.requiresFreshLocation(for: .repeatInstruction))
  }

  func testClassifiesNaturalCurrentInstructionWithExtraContext() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Powiedz proszę, w którą stronę mam się teraz kierować?"),
      .currentInstruction
    )
  }

  func testClassifiesNaturalCurrentInstructionWithInsertedVerb() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Co jest teraz, mam skręcić czy iść prosto?"),
      .currentInstruction
    )
  }

  func testClassifiesNaturalNextInstructionWithDifferentWordOrder() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Jak dalej iść?"),
      .nextInstruction
    )
  }

  func testClassifiesNaturalRouteConcernQuestion() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Co może być nie tak z tą trasą?"),
      .routeQuality
    )
  }

  func testClassifiesNaturalCrossingQuestion() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Czy będzie przejście przede mną?"),
      .pedestrianCrossing
    )
  }

  func testClassifiesNaturalCrossingQuestionWithInsertedWords() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Czy muszę teraz przejść przez ulicę?"),
      .pedestrianCrossing
    )
  }

  func testClassifiesNextCrossingWithNaturalWordOrder() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Gdzie jest następne przejście?"),
      .pedestrianCrossing
    )
  }

  func testQuickQuestionTokenIsIndependentFromDisplayedLanguage() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: RouteAssistantCore.routeQualityToken),
      .routeQuality
    )
  }

  func testOnlyDynamicAnswersRequireFreshLocation() {
    XCTAssertTrue(RouteAssistantCore.requiresFreshLocation(for: .nextInstruction))
    XCTAssertTrue(RouteAssistantCore.requiresFreshLocation(for: .progress))
    XCTAssertTrue(RouteAssistantCore.requiresFreshLocation(for: .pedestrianCrossing))
    XCTAssertTrue(RouteAssistantCore.requiresFreshLocation(for: .currentLocation))
    XCTAssertFalse(RouteAssistantCore.requiresFreshLocation(for: .routeOverview))
    XCTAssertFalse(RouteAssistantCore.requiresFreshLocation(for: .routeQuality))
  }

  func testClassifiesRouteQualityQuestionBeforeGenericGPSStatus() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Czy GPS jest dokładny?"),
      .routeQuality
    )
  }

  func testClassifiesNextCrossingBeforeGenericNextInstruction() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Gdzie jest następne przejście?"),
      .pedestrianCrossing
    )
  }

  func testClassifiesNaturalProgressQuestion() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Kiedy dotrę do celu i ile minut zostało?"),
      .progress
    )
  }

  func testClassifiesNaturalNextInstructionQuestion() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Po tym skręcie co będzie dalej?"),
      .nextInstruction
    )
  }

  func testClassifiesNaturalOverviewQuestionWithInsertedWords() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Jak wygląda cała moja trasa do celu?"),
      .routeOverview
    )
  }

  func testClassifiesNaturalStatusQuestionWithInsertedWords() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Czy jestem nadal na właściwej trasie?"),
      .routeStatus
    )
  }

  func testClassifiesNaturalRouteExplanationAsOverview() {
    XCTAssertEqual(
      RouteAssistantCore.intent(for: "Wyjaśnij trasę krok po kroku"),
      .routeOverview
    )
  }

  func testRejectsUnknownQuestionInsteadOfGuessing() {
    let match = RouteAssistantCore.match(for: "Opowiedz mi coś niezwiązanego z trasą")

    XCTAssertEqual(match.intent, .help)
    XCTAssertFalse(match.isConfident)
    XCTAssertEqual(match.confidence, 0)
  }

  func testDoesNotUseEditDistanceForVeryShortSemanticWords() {
    let match = RouteAssistantCore.match(for: "Nie opowiadaj o ile")

    XCTAssertEqual(match.intent, .help)
    XCTAssertFalse(match.isConfident)
  }

  func testFlagsQuestionContainingTwoStrongIntentsAsAmbiguous() {
    let match = RouteAssistantCore.match(for: "Co dalej i czy GPS jest dokładny?")

    XCTAssertEqual(match.intent, .help)
    XCTAssertTrue(match.isAmbiguous)
    XCTAssertFalse(match.isConfident)
  }

  func testGPSQualityUsesExplicitAccuracyBands() {
    XCTAssertEqual(
      RouteAssistantCore.gpsQuality(accuracyMeters: 12),
      .reliable
    )
    XCTAssertEqual(
      RouteAssistantCore.gpsQuality(accuracyMeters: 40),
      .limited
    )
    XCTAssertEqual(
      RouteAssistantCore.gpsQuality(accuracyMeters: 100),
      .weak
    )
    XCTAssertEqual(
      RouteAssistantCore.gpsQuality(accuracyMeters: nil),
      .unavailable
    )
  }

  func testOverviewIndicesAreBoundedAndStartAtCurrentStep() {
    let steps = (0..<6).map { index in
      RouteStep(instruction: "Krok \(index)", distanceMeters: 20)
    }

    XCTAssertEqual(
      RouteAssistantCore.overviewStepIndices(
        currentStepIndex: 2,
        steps: steps,
        maximumSteps: 3
      ),
      [2, 3, 4]
    )
    XCTAssertEqual(
      RouteAssistantCore.overviewStepIndices(
        currentStepIndex: 100,
        steps: steps,
        maximumSteps: 2
      ),
      [5]
    )
  }

  func testOverviewPrioritizesUpcomingDecisionPoints() {
    let steps = [
      RouteStep(instruction: "Idź prosto", distanceMeters: 100),
      RouteStep(instruction: "Idź prosto", distanceMeters: 100),
      RouteStep(instruction: "Idź prosto", distanceMeters: 100),
      RouteStep(instruction: "Idź prosto", distanceMeters: 100),
      RouteStep(
        instruction: "Skręć w prawo w Lipową",
        distanceMeters: 80,
        maneuverType: "turn",
        maneuverModifier: "right"
      ),
      RouteStep(instruction: "Idź prosto", distanceMeters: 100),
      RouteStep(
        instruction: "Przejście dla pieszych",
        distanceMeters: 60,
        kind: .pedestrianCrossing
      )
    ]

    XCTAssertEqual(
      RouteAssistantCore.overviewStepIndices(
        currentStepIndex: 2,
        steps: steps,
        maximumSteps: 3
      ),
      [2, 4, 6]
    )
  }
}
