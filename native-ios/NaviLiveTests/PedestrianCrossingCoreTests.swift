import XCTest
@testable import NaviLive

final class PedestrianCrossingCoreTests: XCTestCase {
  func testRejectsCyclewayCrossingWithoutPedestrianAccess() {
    XCTAssertFalse(
      PedestrianCrossingCore.isPedestrianCrossing(
        tags: ["highway": "cycleway", "crossing": "yes"]
      )
    )
  }

  func testKeepsSharedCrossingWithExplicitPedestrianAccess() {
    XCTAssertTrue(
      PedestrianCrossingCore.isPedestrianCrossing(
        tags: ["highway": "cycleway", "crossing": "yes", "foot": "designated"]
      )
    )
  }

  func testRejectsCrossingExplicitlyClosedToPedestrians() {
    XCTAssertFalse(
      PedestrianCrossingCore.isPedestrianCrossing(
        tags: ["highway": "crossing", "foot": "no"]
      )
    )
  }

  func testRejectsCrossingMarkedAsCyclewayWithoutPedestrianAccess() {
    XCTAssertFalse(
      PedestrianCrossingCore.isPedestrianCrossing(
        tags: ["crossing:carriageway": "cycleway"]
      )
    )
  }

  func testIgnoresElementWithoutCrossingTags() {
    XCTAssertFalse(
      PedestrianCrossingCore.isPedestrianCrossing(
        tags: ["highway": "cycleway"]
      )
    )
  }
}
