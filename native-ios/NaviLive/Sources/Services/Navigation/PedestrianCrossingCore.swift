import Foundation

/// Odróżnia przejścia piesze od jawnie rowerowych elementów OSM.
enum PedestrianCrossingCore {
  private static let allowedFootValues: Set<String> = ["yes", "designated", "official", "permissive"]
  private static let deniedValues: Set<String> = ["no", "false", "use_sidepath"]

  static func isPedestrianCrossing(tags: [String: String]) -> Bool {
    guard !tags.isEmpty else { return false }

    func value(_ key: String) -> String? {
      guard let raw = tags[key] else { return nil }
      let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return normalized.isEmpty ? nil : normalized
    }

    let foot = value("foot")
    let crossingFoot = value("crossing:foot")
    if deniedValues.contains(foot ?? "") || deniedValues.contains(crossingFoot ?? "") {
      return false
    }

    let crossing = value("crossing")
    if deniedValues.contains(crossing ?? "") {
      return false
    }

    let explicitPedestrianAccess = allowedFootValues.contains(foot ?? "") ||
      allowedFootValues.contains(crossingFoot ?? "")
    if value("highway") == "cycleway" && !explicitPedestrianAccess {
      return false
    }
    if crossing == "cycleway" && !explicitPedestrianAccess {
      return false
    }

    let crossingCarriageway = value("crossing:carriageway")
    if crossingCarriageway == "cycleway" && !explicitPedestrianAccess {
      return false
    }
    return value("highway") == "crossing" ||
      value("footway") == "crossing" ||
      crossing != nil ||
      (crossingCarriageway != nil && !deniedValues.contains(crossingCarriageway ?? ""))
  }
}
