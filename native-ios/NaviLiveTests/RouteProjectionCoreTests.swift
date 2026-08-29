import XCTest
@testable import NaviLive

final class RouteProjectionCoreTests: XCTestCase {
  func testProjectionNeverMovesBeforeMonotonicFloor() {
    let path = [
      GeoPoint(latitude: 51.0, longitude: 19.0),
      GeoPoint(latitude: 51.0, longitude: 19.001),
      GeoPoint(latitude: 51.001, longitude: 19.001)
    ]

    let projection = RouteProjectionCore.project(
      pathPoints: path,
      point: GeoPoint(latitude: 51.0, longitude: 19.0002),
      monotonicFloorMeters: 60
    )

    XCTAssertNotNil(projection)
    XCTAssertGreaterThanOrEqual(projection?.distanceAlongRouteMeters ?? 0, 60)
  }

  func testProjectionReturnsNilForDegeneratePath() {
    let point = GeoPoint(latitude: 51.0, longitude: 19.0)
    XCTAssertNil(RouteProjectionCore.project(pathPoints: [point, point], point: point))
  }

  func testRouteLengthUsesAllSegments() {
    let path = [
      GeoPoint(latitude: 51.0, longitude: 19.0),
      GeoPoint(latitude: 51.0, longitude: 19.001),
      GeoPoint(latitude: 51.001, longitude: 19.001)
    ]

    let length = RouteProjectionCore.routeLengthMeters(path)
    XCTAssertGreaterThan(length, 150)
    XCTAssertLessThan(length, 220)
  }

  func testProjectionRespectsTheForwardSearchWindow() {
    let path = [
      GeoPoint(latitude: 0, longitude: 0),
      GeoPoint(latitude: 0, longitude: 0.001),
      GeoPoint(latitude: 0.001, longitude: 0.001)
    ]

    let projection = RouteProjectionCore.project(
      pathPoints: path,
      point: GeoPoint(latitude: 0.0008, longitude: 0.001),
      maximumDistanceAlongRouteMeters: 50
    )

    XCTAssertNil(projection)
  }

  func testProjectionReturnsNilWhenMonotonicFloorExceedsSearchWindow() {
    let path = [
      GeoPoint(latitude: 51.0, longitude: 19.0),
      GeoPoint(latitude: 51.0, longitude: 19.001),
      GeoPoint(latitude: 51.001, longitude: 19.001)
    ]

    XCTAssertNil(
      RouteProjectionCore.project(
        pathPoints: path,
        point: GeoPoint(latitude: 51.0, longitude: 19.0002),
        maximumDistanceAlongRouteMeters: 40,
        monotonicFloorMeters: 60
      )
    )
  }

  func testMissingManeuverPointIsPlacedBetweenKnownRoutePoints() {
    let path = [
      GeoPoint(latitude: 51.0, longitude: 19.0),
      GeoPoint(latitude: 51.0, longitude: 19.001),
      GeoPoint(latitude: 51.0, longitude: 19.002)
    ]
    let routeLength = RouteProjectionCore.routeLengthMeters(path)

    let positions = RouteProjectionCore.stepDistancesAlongRoute(
      steps: [
        RouteStep(instruction: "Start", distanceMeters: 100, maneuverPoint: path[0], maneuverType: "depart"),
        RouteStep(instruction: "Brak punktu", distanceMeters: 100, maneuverType: "turn"),
        RouteStep(instruction: "Koniec", distanceMeters: 0, maneuverPoint: path[2], maneuverType: "arrive")
      ],
      pathPoints: path
    )

    XCTAssertEqual(positions[0], 0, accuracy: 1)
    XCTAssertGreaterThan(positions[1], 40)
    XCTAssertLessThan(positions[1], routeLength - 40)
    XCTAssertEqual(positions[2], routeLength, accuracy: 1)
  }

  func testProjectionKeepsRouteEndpointInsideFiniteRouteWindow() {
    let path = [
      GeoPoint(latitude: 51.0, longitude: 19.0),
      GeoPoint(latitude: 51.0, longitude: 19.001),
      GeoPoint(latitude: 51.0, longitude: 19.002)
    ]
    let routeLength = RouteProjectionCore.routeLengthMeters(path)

    let projection = RouteProjectionCore.project(
      pathPoints: path,
      point: path[2],
      maximumDistanceAlongRouteMeters: routeLength
    )

    XCTAssertEqual(projection?.distanceAlongRouteMeters ?? 0, routeLength, accuracy: 0.01)
  }

  func testMissingFinalManeuverPointUsesRouteEndInsteadOfZero() {
    let path = [
      GeoPoint(latitude: 51.0, longitude: 19.0),
      GeoPoint(latitude: 51.0, longitude: 19.001)
    ]
    let routeLength = RouteProjectionCore.routeLengthMeters(path)

    let positions = RouteProjectionCore.stepDistancesAlongRoute(
      steps: [
        RouteStep(instruction: "Start", distanceMeters: 100, maneuverPoint: path[0], maneuverType: "depart"),
        RouteStep(instruction: "Cel", distanceMeters: 0, maneuverType: "arrive")
      ],
      pathPoints: path
    )

    XCTAssertEqual(positions.last ?? 0, routeLength, accuracy: 1)
  }
}
