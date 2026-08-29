import Foundation
import XCTest
@testable import NaviLive

final class LocationFixStabilizerTests: XCTestCase {
  func testFirstFixIsAccepted() {
    let stabilizer = LocationFixStabilizer()
    let rawFix = fix(latitude: 51.0, longitude: 19.0, accuracy: 8, timestamp: 1)

    let stabilized = stabilizer.stabilize(rawFix)

    XCTAssertEqual(stabilized, rawFix)
  }

  func testSmallStationaryJitterKeepsPreviousPoint() throws {
    let stabilizer = LocationFixStabilizer()
    let first = fix(latitude: 51.0, longitude: 19.0, accuracy: 8, timestamp: 1)
    let jitter = LocationFix(
      point: first.point.movedNorth(meters: 3),
      accuracyMeters: first.accuracyMeters,
      timestamp: Date(timeIntervalSince1970: 2),
      courseDegrees: nil
    )

    _ = stabilizer.stabilize(first)
    let stabilized = try XCTUnwrap(stabilizer.stabilize(jitter))

    XCTAssertEqual(stabilized.point.latitude, first.point.latitude, accuracy: 0.0000001)
    XCTAssertEqual(stabilized.point.longitude, first.point.longitude, accuracy: 0.0000001)
    XCTAssertEqual(stabilized.timestamp, jitter.timestamp)
  }

  func testImplausibleWalkingJumpKeepsPreviousPoint() throws {
    let stabilizer = LocationFixStabilizer()
    let first = fix(latitude: 51.0, longitude: 19.0, accuracy: 5, timestamp: 1)
    let jump = LocationFix(
      point: first.point.movedNorth(meters: 80),
      accuracyMeters: first.accuracyMeters,
      timestamp: Date(timeIntervalSince1970: 2),
      courseDegrees: nil
    )

    _ = stabilizer.stabilize(first)
    let stabilized = try XCTUnwrap(stabilizer.stabilize(jump))

    XCTAssertEqual(stabilized.point.latitude, first.point.latitude, accuracy: 0.0000001)
    XCTAssertEqual(stabilized.point.longitude, first.point.longitude, accuracy: 0.0000001)
  }

  func testRealisticMovementIsSmoothed() throws {
    let stabilizer = LocationFixStabilizer()
    let first = fix(latitude: 51.0, longitude: 19.0, accuracy: 10, timestamp: 1)
    let movement = LocationFix(
      point: first.point.movedNorth(meters: 20),
      accuracyMeters: 6,
      timestamp: Date(timeIntervalSince1970: 7),
      courseDegrees: nil
    )

    _ = stabilizer.stabilize(first)
    let stabilized = try XCTUnwrap(stabilizer.stabilize(movement))

    let latitude = stabilized.point.latitude
    XCTAssertGreaterThan(latitude, first.point.latitude)
    XCTAssertLessThan(latitude, movement.point.latitude)
    XCTAssertNotEqual(latitude, movement.point.latitude, accuracy: 0.0000001)
  }

  func testStaleFixResetsStabilization() throws {
    let stabilizer = LocationFixStabilizer()
    let first = fix(latitude: 51.0, longitude: 19.0, accuracy: 5, timestamp: 1)
    let later = LocationFix(
      point: first.point.movedNorth(meters: 80),
      accuracyMeters: first.accuracyMeters,
      timestamp: Date(timeIntervalSince1970: 25),
      courseDegrees: nil
    )

    _ = stabilizer.stabilize(first)
    let stabilized = try XCTUnwrap(stabilizer.stabilize(later))

    XCTAssertEqual(stabilized.point.latitude, later.point.latitude, accuracy: 0.0000001)
    XCTAssertEqual(stabilized.point.longitude, later.point.longitude, accuracy: 0.0000001)
  }

  func testInvalidNegativeAccuracyIsRejected() {
    let stabilizer = LocationFixStabilizer()
    let invalid = fix(latitude: 51.0, longitude: 19.0, accuracy: -1, timestamp: 1)

    XCTAssertNil(stabilizer.stabilize(invalid))
  }

  private func fix(latitude: Double, longitude: Double, accuracy: Double, timestamp: TimeInterval) -> LocationFix {
    LocationFix(
      point: GeoPoint(latitude: latitude, longitude: longitude),
      accuracyMeters: accuracy,
      timestamp: Date(timeIntervalSince1970: timestamp),
      courseDegrees: nil
    )
  }
}

private extension GeoPoint {
  func movedNorth(meters: Double) -> GeoPoint {
    GeoPoint(latitude: latitude + meters / 111_320.0, longitude: longitude)
  }
}
