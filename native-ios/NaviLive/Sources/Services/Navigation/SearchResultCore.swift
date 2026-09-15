import Foundation

enum SearchPlaceKind: Equatable {
  case shop
  case parcelLocker
  case railStation
  case busStop
  case tramStop
  case other
}

struct SearchRankingValues {
  let score: Int
  let distanceMeters: Int
  let importance: Double
  let isNearbyCandidate: Bool
}

/// Czyste reguły wyszukiwania używane przez adapter sieciowy i testy.
enum SearchResultCore {
  static func kindFromNominatim(category: String, type: String) -> SearchPlaceKind {
    if category == "shop" { return .shop }
    if category == "amenity", type == "parcel_locker" { return .parcelLocker }
    if category == "railway", ["station", "halt"].contains(type) { return .railStation }
    if category == "public_transport", type == "station" { return .railStation }
    if category == "highway", type == "bus_stop" { return .busStop }
    if category == "public_transport", ["platform", "stop_position"].contains(type) { return .busStop }
    if category == "railway", type == "tram_stop" { return .tramStop }
    return .other
  }

  /// PKP nie powinno zamieniać się w przystanek autobusowy lub tramwajowy.
  static func shouldKeepForRailQuery(kind: SearchPlaceKind, wantsTransitStop: Bool) -> Bool {
    wantsTransitStop || kind == .railStation || kind == .other
  }

  static func localNameMatches(normalizedName: String, nameSearchTerms: [String]) -> Bool {
    nameSearchTerms.isEmpty || nameSearchTerms.allSatisfy { normalizedName.contains($0) }
  }

  /// Porównuje kandydatów w kolejności prezentowania na liście.
  static func compareForDisplay(_ left: SearchRankingValues, _ right: SearchRankingValues) -> Bool {
    let leftDistance = sortableDistance(left.distanceMeters)
    let rightDistance = sortableDistance(right.distanceMeters)
    let scoreDifference = left.score - right.score
    if abs(scoreDifference) <= SharedProductRules.Search.nearbyBonus, leftDistance != rightDistance {
      return leftDistance < rightDistance
    }
    if scoreDifference != 0 { return scoreDifference > 0 }
    if left.isNearbyCandidate != right.isNearbyCandidate {
      return left.isNearbyCandidate && !right.isNearbyCandidate
    }
    if leftDistance != rightDistance { return leftDistance < rightDistance }
    return left.importance > right.importance
  }

  /// Wybiera lepszą wersję tego samego punktu zwróconą przez inne źródło.
  static func isBetterDuplicate(_ left: SearchRankingValues, _ right: SearchRankingValues) -> Bool {
    if left.score != right.score { return left.score > right.score }
    if left.isNearbyCandidate != right.isNearbyCandidate {
      return left.isNearbyCandidate && !right.isNearbyCandidate
    }
    if left.distanceMeters != right.distanceMeters {
      return sortableDistance(left.distanceMeters) < sortableDistance(right.distanceMeters)
    }
    return left.importance > right.importance
  }

  private static func sortableDistance(_ distanceMeters: Int) -> Int {
    distanceMeters > 0 ? distanceMeters : Int.max
  }
}
