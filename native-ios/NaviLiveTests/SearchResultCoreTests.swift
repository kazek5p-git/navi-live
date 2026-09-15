import XCTest
@testable import NaviLive

final class SearchResultCoreTests: XCTestCase {
  func testClassifiesTransitAndLocalPlaceKinds() {
    XCTAssertEqual(
      SearchResultCore.kindFromNominatim(category: "railway", type: "station"),
      .railStation
    )
    XCTAssertEqual(
      SearchResultCore.kindFromNominatim(category: "highway", type: "bus_stop"),
      .busStop
    )
    XCTAssertEqual(
      SearchResultCore.kindFromNominatim(category: "railway", type: "tram_stop"),
      .tramStop
    )
    XCTAssertEqual(
      SearchResultCore.kindFromNominatim(category: "shop", type: "supermarket"),
      .shop
    )
  }

  func testRailQueryDoesNotKeepAClassifiedBusStop() {
    XCTAssertTrue(
      SearchResultCore.shouldKeepForRailQuery(kind: .railStation, wantsTransitStop: false)
    )
    XCTAssertTrue(
      SearchResultCore.shouldKeepForRailQuery(kind: .other, wantsTransitStop: false)
    )
    XCTAssertFalse(
      SearchResultCore.shouldKeepForRailQuery(kind: .busStop, wantsTransitStop: false)
    )
    XCTAssertTrue(
      SearchResultCore.shouldKeepForRailQuery(kind: .busStop, wantsTransitStop: true)
    )
  }

  func testNamedLocalCategoryRequiresMatchingNameTerms() {
    XCTAssertTrue(
      SearchResultCore.localNameMatches(
        normalizedName: "zabka wschodnia",
        nameSearchTerms: ["zabka"]
      )
    )
    XCTAssertFalse(
      SearchResultCore.localNameMatches(
        normalizedName: "biedronka",
        nameSearchTerms: ["zabka"]
      )
    )
    XCTAssertTrue(
      SearchResultCore.localNameMatches(
        normalizedName: "sklep",
        nameSearchTerms: []
      )
    )
  }

  func testNearbyCandidateWinsWhenTextScoresAreComparable() {
    let nearby = SearchRankingValues(
      score: 600,
      distanceMeters: 220,
      importance: 0.2,
      isNearbyCandidate: true
    )
    let distant = SearchRankingValues(
      score: 850,
      distanceMeters: 4_000,
      importance: 0.9,
      isNearbyCandidate: false
    )

    XCTAssertTrue(SearchResultCore.compareForDisplay(nearby, distant))
    XCTAssertFalse(SearchResultCore.compareForDisplay(distant, nearby))
  }

  func testBetterDuplicatePrefersNearbySourceBeforeImportance() {
    let nearby = SearchRankingValues(
      score: 600,
      distanceMeters: 300,
      importance: 0.1,
      isNearbyCandidate: true
    )
    let global = SearchRankingValues(
      score: 600,
      distanceMeters: 1_000,
      importance: 0.9,
      isNearbyCandidate: false
    )

    XCTAssertTrue(SearchResultCore.isBetterDuplicate(nearby, global))
    XCTAssertFalse(SearchResultCore.isBetterDuplicate(global, nearby))
  }

  func testAddressFormattingBuildsStreetNumberAndLocality() {
    let address = AddressFormattingCore.formatAddress(
      [
        "road": "Wschodnia",
        "house_number": "12",
        "city": "Łódź"
      ],
      fallback: "12, Wschodnia, Łódź"
    )

    XCTAssertEqual(address, "Wschodnia 12, Łódź")
  }

  func testUnhelpfulPlaceNameIsReplacedByCoordinateFallback() {
    XCTAssertTrue(
      AddressFormattingCore.isUnhelpfulAddress(
        "Żabka: Żabka",
        placeName: "Żabka: Żabka"
      )
    )
    XCTAssertEqual(
      AddressFormattingCore.ensureAddress(
        "Żabka",
        placeName: "Żabka",
        fallback: "Wschodnia 12, Łódź"
      ),
      "Wschodnia 12, Łódź"
    )
    XCTAssertEqual(
      AddressFormattingCore.ensureAddress(
        "Wschodnia 12, Łódź",
        placeName: "Żabka",
        fallback: "współrzędne"
      ),
      "Wschodnia 12, Łódź"
    )
  }
}
