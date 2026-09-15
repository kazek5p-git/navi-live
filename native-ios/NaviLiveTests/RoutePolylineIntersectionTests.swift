import XCTest
@testable import NaviLive

final class RoutePolylineIntersectionTests: XCTestCase {
  func testFindsARealCrossingAndPreservesRouteDistance() throws {
    let route = [
      GeoPoint(latitude: 51.000000, longitude: 19.000000),
      GeoPoint(latitude: 51.000000, longitude: 19.001000)
    ]
    let crossingStreet = [
      GeoPoint(latitude: 50.999500, longitude: 19.000500),
      GeoPoint(latitude: 51.000500, longitude: 19.000500)
    ]

    let intersections = RouteProjectionCore.polylineIntersections(
      routePoints: route,
      otherPoints: crossingStreet
    )

    let intersection = try XCTUnwrap(intersections.first)
    XCTAssertEqual(intersections.count, 1)
    XCTAssertEqual(intersection.routeSegmentIndex, 0)
    XCTAssertEqual(intersection.otherSegmentIndex, 0)
    XCTAssertEqual(intersection.point.latitude, 51.0, accuracy: 0.00001)
    XCTAssertEqual(intersection.point.longitude, 19.0005, accuracy: 0.00001)
    XCTAssertEqual(
      intersection.distanceAlongRouteMeters,
      route[0].distance(to: route[1]) / 2,
      accuracy: 1
    )
    XCTAssertEqual(intersection.crossingAngleDegrees, 90, accuracy: 0.5)
  }

  func testIgnoresParallelPathBesideTheRoute() {
    let route = [
      GeoPoint(latitude: 51.000000, longitude: 19.000000),
      GeoPoint(latitude: 51.000000, longitude: 19.001000)
    ]
    let parallelCycleway = [
      GeoPoint(latitude: 51.000020, longitude: 19.000000),
      GeoPoint(latitude: 51.000020, longitude: 19.001000)
    ]

    XCTAssertTrue(
      RouteProjectionCore.polylineIntersections(
        routePoints: route,
        otherPoints: parallelCycleway
      ).isEmpty
    )
  }

  func testShallowStreetCrossingIsNotMeaningfulForJunctionAlert() throws {
    let route = [
      GeoPoint(latitude: 51.000000, longitude: 19.000000),
      GeoPoint(latitude: 51.000000, longitude: 19.001000)
    ]
    let shallowStreet = [
      GeoPoint(latitude: 50.999500, longitude: 19.000000),
      GeoPoint(latitude: 51.000500, longitude: 19.001500)
    ]

    let intersection = try XCTUnwrap(
      RouteProjectionCore.polylineIntersections(
        routePoints: route,
        otherPoints: shallowStreet
      ).first
    )

    XCTAssertFalse(
      NavigationScenarioCore.isMeaningfulCrossing(
        crossingAngleDegrees: intersection.crossingAngleDegrees,
        minimumBearingDifferenceDegrees: 55
      )
    )
  }

  func testDeduplicatesCrossingReportedOnAdjacentRouteSegments() {
    let route = [
      GeoPoint(latitude: 51.000000, longitude: 19.000000),
      GeoPoint(latitude: 51.000000, longitude: 19.000500),
      GeoPoint(latitude: 51.000000, longitude: 19.001000)
    ]
    let crossingStreet = [
      GeoPoint(latitude: 50.999500, longitude: 19.000500),
      GeoPoint(latitude: 51.000500, longitude: 19.000500)
    ]

    let intersections = RouteProjectionCore.polylineIntersections(
      routePoints: route,
      otherPoints: crossingStreet,
      endpointToleranceMeters: 2
    )

    XCTAssertEqual(intersections.count, 1)
  }

  func testRejectsNegativeEndpointTolerance() {
    let route = [
      GeoPoint(latitude: 51.000000, longitude: 19.000000),
      GeoPoint(latitude: 51.000000, longitude: 19.001000)
    ]
    let crossingStreet = [
      GeoPoint(latitude: 50.999500, longitude: 19.000500),
      GeoPoint(latitude: 51.000500, longitude: 19.000500)
    ]

    XCTAssertTrue(
      RouteProjectionCore.polylineIntersections(
        routePoints: route,
        otherPoints: crossingStreet,
        endpointToleranceMeters: -1
      ).isEmpty
    )
  }
}
