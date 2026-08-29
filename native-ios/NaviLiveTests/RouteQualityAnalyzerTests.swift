import XCTest
@testable import NaviLive

final class RouteQualityAnalyzerTests: XCTestCase {
  func testReportsUnnamedTurn() {
    let report = RouteQualityAnalyzer.analyze(
      steps: [
        RouteStep(
          instruction: "Skręć w lewo",
          distanceMeters: 100,
          maneuverType: "turn",
          maneuverModifier: "left",
          roadName: nil
        )
      ],
      pathPoints: routePoints
    )

    XCTAssertEqual(report.unnamedTurnCount, 1)
    XCTAssertTrue(report.issues.contains(.unnamedTurn))
    XCTAssertTrue(report.hasPotentialIssues)
    XCTAssertEqual(report.level, .review)
    XCTAssertEqual(report.recommendation, .reviewBeforeStarting)
  }

  func testReportsRepeatedAdjacentInstruction() {
    let repeatedInstruction = "Skręć w prawo w Lipową"
    let report = RouteQualityAnalyzer.analyze(
      steps: [
        RouteStep(instruction: repeatedInstruction, distanceMeters: 12),
        RouteStep(instruction: repeatedInstruction, distanceMeters: 80)
      ],
      pathPoints: routePoints
    )

    XCTAssertEqual(report.repeatedInstructionCount, 1)
    XCTAssertTrue(report.issues.contains(.repeatedInstruction))
  }

  func testReportsIncompleteGeometry() {
    let report = RouteQualityAnalyzer.analyze(
      steps: [],
      pathPoints: [GeoPoint(latitude: 51.0, longitude: 19.0)]
    )

    XCTAssertTrue(report.hasIncompleteGeometry)
    XCTAssertTrue(report.issues.contains(.incompleteGeometry))
    XCTAssertEqual(report.issueCount, 1)
    XCTAssertEqual(report.qualityScore, 0)
    XCTAssertEqual(report.confidencePercent, 0)
    XCTAssertEqual(report.level, .insufficientData)
    XCTAssertEqual(report.recommendation, .waitForCompleteData)
  }

  func testReportsInvalidGeometryInsteadOfTreatingItAsReliable() {
    let report = RouteQualityAnalyzer.analyze(
      steps: [RouteStep(instruction: "Idź prosto", distanceMeters: 40)],
      pathPoints: [
        GeoPoint(latitude: 91.0, longitude: 19.0),
        GeoPoint(latitude: 51.0, longitude: 19.001)
      ]
    )

    XCTAssertTrue(report.hasIncompleteGeometry)
    XCTAssertEqual(report.level, .insufficientData)
    XCTAssertEqual(report.qualityScore, 0)
  }

  func testReportsMissingManeuverData() {
    let report = RouteQualityAnalyzer.analyze(
      steps: [
        RouteStep(
          instruction: "",
          distanceMeters: 30,
          maneuverType: "turn",
          maneuverModifier: "right",
          roadName: "Lipowa"
        )
      ],
      pathPoints: routePoints
    )

    XCTAssertEqual(report.missingManeuverDataCount, 1)
    XCTAssertTrue(report.issues.contains(.missingManeuverData))
    XCTAssertFalse(report.hasIncompleteGeometry)
    XCTAssertTrue(report.hasPotentialIssues)
  }

  func testReportsCloseOppositeManeuversAsReviewSignal() {
    let report = RouteQualityAnalyzer.analyze(
      steps: [
        RouteStep(
          instruction: "Skręć w lewo w Lipową",
          distanceMeters: 20,
          maneuverPoint: GeoPoint(latitude: 51.0, longitude: 19.0),
          maneuverType: "turn",
          maneuverModifier: "left",
          roadName: "Lipowa"
        ),
        RouteStep(
          instruction: "Skręć w prawo w Dębową",
          distanceMeters: 25,
          maneuverPoint: GeoPoint(latitude: 51.0, longitude: 19.0002),
          maneuverType: "turn",
          maneuverModifier: "right",
          roadName: "Dębowa"
        )
      ],
      pathPoints: routePoints
    )

    XCTAssertEqual(report.closeOppositeManeuverCount, 1)
    XCTAssertTrue(report.issues.contains(.closeOppositeManeuvers))
    XCTAssertTrue(report.hasPotentialIssues)
  }

  func testReportsCloseOppositeManeuversSeparatedByCrossingStep() {
    let report = RouteQualityAnalyzer.analyze(
      steps: [
        RouteStep(
          instruction: "Skręć w lewo w Lipową",
          distanceMeters: 20,
          maneuverPoint: GeoPoint(latitude: 51.0, longitude: 19.0002),
          maneuverType: "turn",
          maneuverModifier: "left",
          roadName: "Lipowa"
        ),
        RouteStep(
          instruction: "Przejście dla pieszych",
          distanceMeters: 12,
          kind: .pedestrianCrossing
        ),
        RouteStep(
          instruction: "Skręć w prawo w Dębową",
          distanceMeters: 25,
          maneuverPoint: GeoPoint(latitude: 51.0, longitude: 19.0003),
          maneuverType: "turn",
          maneuverModifier: "right",
          roadName: "Dębowa"
        )
      ],
      pathPoints: routePoints
    )

    XCTAssertEqual(report.closeOppositeManeuverCount, 1)
    XCTAssertTrue(report.issues.contains(.closeOppositeManeuvers))
  }

  func testReportsManeuverPointOutsideRouteGeometry() {
    let report = RouteQualityAnalyzer.analyze(
      steps: [
        RouteStep(
          instruction: "Skręć w prawo w Lipową",
          distanceMeters: 60,
          maneuverPoint: GeoPoint(latitude: 51.001, longitude: 19.0005),
          maneuverType: "turn",
          maneuverModifier: "right",
          roadName: "Lipowa"
        )
      ],
      pathPoints: routePoints
    )

    XCTAssertEqual(report.maneuverGeometryMismatchCount, 1)
    XCTAssertTrue(report.issues.contains(.maneuverGeometryMismatch))
    XCTAssertEqual(report.level, .review)
  }

  func testReportsManeuverPointsInReverseRouteOrder() {
    let report = RouteQualityAnalyzer.analyze(
      steps: [
        RouteStep(
          instruction: "Skręć w prawo w Lipową",
          distanceMeters: 60,
          maneuverPoint: GeoPoint(latitude: 51.0, longitude: 19.0008),
          maneuverType: "turn",
          maneuverModifier: "right",
          roadName: "Lipową"
        ),
        RouteStep(
          instruction: "Skręć w lewo w Dębową",
          distanceMeters: 60,
          maneuverPoint: GeoPoint(latitude: 51.0, longitude: 19.0002),
          maneuverType: "turn",
          maneuverModifier: "left",
          roadName: "Dębową"
        )
      ],
      pathPoints: routePoints
    )

    XCTAssertEqual(report.maneuverGeometryMismatchCount, 1)
    XCTAssertTrue(report.issues.contains(.maneuverGeometryMismatch))
  }

  func testDoesNotUseStepDistancesAsReplacementForManeuverGeometry() {
    let report = RouteQualityAnalyzer.analyze(
      steps: [
        RouteStep(
          instruction: "Skręć w lewo w Lipową",
          distanceMeters: 20,
          maneuverPoint: GeoPoint(latitude: 51.0, longitude: 19.0),
          maneuverType: "turn",
          maneuverModifier: "left",
          roadName: "Lipowa"
        ),
        RouteStep(
          instruction: "Skręć w prawo w Dębową",
          distanceMeters: 25,
          maneuverPoint: GeoPoint(latitude: 51.0, longitude: 19.002),
          maneuverType: "turn",
          maneuverModifier: "right",
          roadName: "Dębowa"
        )
      ],
      pathPoints: routePoints
    )

    XCTAssertEqual(report.closeOppositeManeuverCount, 0)
  }

  func testNearbyParallelReturnLegIsReportedAsGeometryOrderIssue() {
    let path = [
      GeoPoint(latitude: 51.0, longitude: 19.0),
      GeoPoint(latitude: 51.0009, longitude: 19.0),
      GeoPoint(latitude: 51.0009, longitude: 19.00015),
      GeoPoint(latitude: 51.0, longitude: 19.00015)
    ]
    let report = RouteQualityAnalyzer.analyze(
      steps: [
        RouteStep(
          instruction: "Skręć w lewo w Lipową",
          distanceMeters: 60,
          maneuverPoint: GeoPoint(latitude: 51.00045, longitude: 19.00015),
          maneuverType: "turn",
          maneuverModifier: "left",
          roadName: "Lipowa"
        ),
        RouteStep(
          instruction: "Skręć w prawo w Dębową",
          distanceMeters: 60,
          maneuverPoint: GeoPoint(latitude: 51.00045, longitude: 19.0),
          maneuverType: "turn",
          maneuverModifier: "right",
          roadName: "Dębowa"
        )
      ],
      pathPoints: path
    )

    XCTAssertEqual(report.closeOppositeManeuverCount, 0)
    XCTAssertEqual(report.maneuverGeometryMismatchCount, 1)
  }

  func testDoesNotReportHealthyRoute() {
    let report = RouteQualityAnalyzer.analyze(
      steps: [
        RouteStep(
          instruction: "Skręć w lewo w Lipową",
          distanceMeters: 100,
          maneuverPoint: GeoPoint(latitude: 51.0, longitude: 19.0),
          maneuverType: "turn",
          maneuverModifier: "left",
          roadName: "Lipowa"
        ),
        RouteStep(instruction: "Idź dalej prosto", distanceMeters: 80)
      ],
      pathPoints: routePoints
    )

    XCTAssertFalse(report.hasPotentialIssues)
    XCTAssertTrue(report.issues.isEmpty)
    XCTAssertEqual(report.issueCount, 0)
    XCTAssertEqual(report.qualityScore, 100)
    XCTAssertEqual(report.confidencePercent, 100)
    XCTAssertEqual(report.level, .good)
    XCTAssertEqual(report.recommendation, .followCurrentGuidance)
  }

  private var routePoints: [GeoPoint] {
    [
      GeoPoint(latitude: 51.0, longitude: 19.0),
      GeoPoint(latitude: 51.0, longitude: 19.001)
    ]
  }
}
