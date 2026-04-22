import XCTest
@testable import NaviLive

final class NaviLiveScaffoldTests: XCTestCase {
  func testEnglishRootTitleExists() {
    XCTAssertEqual(L10n.text("root.title", table: .root), "Navi Live")
  }
}
