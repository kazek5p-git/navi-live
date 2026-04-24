import Foundation
import XCTest
@testable import NaviLive

final class NavigationParityFixturesTests: XCTestCase {
  func testAddressFormattingMatchesSharedFixtures() throws {
    let fixtures = try SharedParityFixtureLoader.load()
    for entry in fixtures.addressCases {
      let actual = AddressFormattingCore.formatAddress(entry.address, fallback: entry.fallback)
      XCTAssertEqual(actual, entry.expected, entry.name)
    }
  }

  func testInstructionDescriptorsMatchSharedFixtures() throws {
    let fixtures = try SharedParityFixtureLoader.load()
    for entry in fixtures.instructionCases {
      let descriptor = NavigationInstructionCore.describe(
        maneuverType: entry.maneuverType,
        modifier: entry.modifier,
        roadName: entry.roadName
      )
      XCTAssertEqual(descriptor.paritySignature(), entry.expectedParity, entry.name)
    }
  }
}

private enum SharedParityFixtureLoader {
  struct Fixtures: Decodable {
    let addressCases: [AddressCase]
    let instructionCases: [InstructionCase]
  }

  struct AddressCase: Decodable {
    let name: String
    let address: [String: String]?
    let fallback: String
    let expected: String
  }

  struct InstructionCase: Decodable {
    let name: String
    let maneuverType: String
    let modifier: String?
    let roadName: String?
    let expectedParity: String
  }

  static func load() throws -> Fixtures {
    let url = try locateFixtureURL()
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Fixtures.self, from: data)
  }

  private static func locateFixtureURL() throws -> URL {
    var current = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
    while true {
      let candidate = current
        .appendingPathComponent("shared", isDirectory: true)
        .appendingPathComponent("test-fixtures", isDirectory: true)
        .appendingPathComponent("navigation-parity-fixtures.json", isDirectory: false)
      if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
      let parent = current.deletingLastPathComponent()
      if parent.path == current.path {
        throw NSError(domain: "NavigationParityFixturesTests", code: 1, userInfo: [
          NSLocalizedDescriptionKey: "Could not locate shared parity fixtures."
        ])
      }
      current = parent
    }
  }
}
