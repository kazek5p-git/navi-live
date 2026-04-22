import Foundation

enum NavigationAPIError: LocalizedError {
  case invalidURL
  case noRoute
  case badResponse

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid URL."
    case .noRoute:
      return "No route found."
    case .badResponse:
      return "Unexpected server response."
    }
  }
}

struct SearchResultDTO: Decodable {
  let placeID: Int?
  let displayName: String
  let lat: String
  let lon: String
  let name: String?
  let namedetails: [String: String]?
  let address: [String: String]?
  let importance: Double?

  enum CodingKeys: String, CodingKey {
    case placeID = "place_id"
    case displayName = "display_name"
    case lat
    case lon
    case name
    case namedetails
    case address
    case importance
  }
}

struct ReverseGeocodeDTO: Decodable {
  let displayName: String
  let address: [String: String]?

  enum CodingKeys: String, CodingKey {
    case displayName = "display_name"
    case address
  }
}

struct OSRMResponse: Decodable {
  let routes: [OSRMRoute]
}

struct OSRMRoute: Decodable {
  let distance: Double
  let duration: Double
  let geometry: OSRMGeometry
  let legs: [OSRMLeg]
}

struct OSRMGeometry: Decodable {
  let coordinates: [[Double]]
}

struct OSRMLeg: Decodable {
  let steps: [OSRMStep]
}

struct OSRMStep: Decodable {
  let distance: Double
  let name: String
  let maneuver: OSRMManeuver
}

struct OSRMManeuver: Decodable {
  let instruction: String?
  let modifier: String?
  let type: String
  let location: [Double]
}

actor NavigationAPIClient {
  private struct SearchCandidate {
    let place: Place
    let score: Int
    let distanceMeters: Int
    let importance: Double
    let isNearbyCandidate: Bool
  }

  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func searchPlaces(query: String, near location: GeoPoint?) async throws -> [Place] {
    let nearbyCandidates = try await fetchSearchCandidates(query: query, near: location, nearbyOnly: true)
    var combinedByID: [String: SearchCandidate] = [:]
    nearbyCandidates.forEach { candidate in
      combinedByID[candidate.place.id] = candidate
    }

    if nearbyCandidates.count < 5 {
      let globalCandidates = try await fetchSearchCandidates(query: query, near: location, nearbyOnly: false)
      for candidate in globalCandidates {
        if let existing = combinedByID[candidate.place.id] {
          if isBetterSearchCandidate(candidate, than: existing) {
            combinedByID[candidate.place.id] = candidate
          }
        } else {
          combinedByID[candidate.place.id] = candidate
        }
      }
    }

    return combinedByID.values
      .sorted {
        if $0.score != $1.score { return $0.score > $1.score }
        if $0.isNearbyCandidate != $1.isNearbyCandidate { return $0.isNearbyCandidate && !$1.isNearbyCandidate }
        if $0.distanceMeters != $1.distanceMeters {
          let leftDistance = $0.distanceMeters > 0 ? $0.distanceMeters : Int.max
          let rightDistance = $1.distanceMeters > 0 ? $1.distanceMeters : Int.max
          return leftDistance < rightDistance
        }
        return $0.importance > $1.importance
      }
      .prefix(8)
      .map(\.place)
  }

  func reverseGeocode(point: GeoPoint) async throws -> String {
    guard var components = URLComponents(string: "https://nominatim.openstreetmap.org/reverse") else {
      throw NavigationAPIError.invalidURL
    }
    components.queryItems = [
      .init(name: "format", value: "jsonv2"),
      .init(name: "lat", value: String(point.latitude)),
      .init(name: "lon", value: String(point.longitude)),
      .init(name: "addressdetails", value: "1")
    ]
    guard let url = components.url else {
      throw NavigationAPIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")
    request.setValue(Locale.current.identifier.replacingOccurrences(of: "_", with: "-"), forHTTPHeaderField: "Accept-Language")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw NavigationAPIError.badResponse
    }
    let decoded = try JSONDecoder().decode(ReverseGeocodeDTO.self, from: data)
    return formattedAddress(from: decoded.address, fallback: decoded.displayName)
  }

  func buildWalkingRoute(from start: GeoPoint, to destination: Place) async throws -> RouteSummary {
    guard let destinationPoint = destination.point else {
      throw NavigationAPIError.noRoute
    }
    let coordinateString = "\(start.longitude),\(start.latitude);\(destinationPoint.longitude),\(destinationPoint.latitude)"
    guard let url = URL(string: "https://router.project-osrm.org/route/v1/foot/\(coordinateString)?overview=full&geometries=geojson&steps=true") else {
      throw NavigationAPIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw NavigationAPIError.badResponse
    }

    let decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)
    guard let route = decoded.routes.first else {
      throw NavigationAPIError.noRoute
    }

    let steps = route.legs.flatMap(\.steps).map { step in
      RouteStep(
        instruction: humanInstruction(for: step),
        distanceMeters: Int(step.distance.rounded()),
        maneuverPoint: step.maneuver.location.count >= 2
          ? GeoPoint(latitude: step.maneuver.location[1], longitude: step.maneuver.location[0])
          : nil
      )
    }

    let points = route.geometry.coordinates.compactMap { coordinate -> GeoPoint? in
      guard coordinate.count >= 2 else { return nil }
      return GeoPoint(latitude: coordinate[1], longitude: coordinate[0])
    }

    return RouteSummary(
      distanceMeters: Int(route.distance.rounded()),
      etaMinutes: max(1, Int((route.duration / 60.0).rounded())),
      modeLabel: L10n.text("route.mode.walking", table: .navigation),
      currentInstruction: steps.first?.instruction ?? "",
      nextInstruction: steps.dropFirst().first?.instruction ?? "",
      steps: steps,
      pathPoints: points
    )
  }

  private func humanInstruction(for step: OSRMStep) -> String {
    if let instruction = step.maneuver.instruction, !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return instruction
    }

    switch step.maneuver.type {
    case "depart":
      return L10n.text("navigation.step.depart", table: .navigation)
    case "arrive":
      return L10n.text("navigation.step.arrive", table: .navigation)
    case "turn":
      if let modifier = step.maneuver.modifier {
        return L10n.text("navigation.step.turn.\(modifier)", table: .navigation)
      }
      return L10n.text("navigation.step.turn.default", table: .navigation)
    case "roundabout":
      return L10n.text("navigation.step.roundabout", table: .navigation)
    default:
      return step.name.isEmpty ? L10n.text("navigation.step.continue", table: .navigation) : step.name
    }
  }

  private func fetchSearchCandidates(
    query: String,
    near location: GeoPoint?,
    nearbyOnly: Bool
  ) async throws -> [SearchCandidate] {
    guard let url = buildSearchURL(query: query, near: location, nearbyOnly: nearbyOnly) else {
      throw NavigationAPIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")
    request.setValue(Locale.current.identifier.replacingOccurrences(of: "_", with: "-"), forHTTPHeaderField: "Accept-Language")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw NavigationAPIError.badResponse
    }

    let decoded = try JSONDecoder().decode([SearchResultDTO].self, from: data)
    return decoded.map { item in
      let point = GeoPoint(latitude: Double(item.lat) ?? 0, longitude: Double(item.lon) ?? 0)
      let distance = location.map { Int($0.distance(to: point).rounded()) } ?? 0
      let displayName = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
      let place = Place(
        id: "nominatim-\(item.placeID ?? Int.random(in: 1000...9999))",
        name: candidateName(for: item, fallback: displayName),
        address: formattedAddress(from: item.address, fallback: displayName),
        walkDistanceMeters: distance,
        walkEtaMinutes: max(1, Int((Double(distance) / 78.0).rounded())),
        point: point
      )
      return SearchCandidate(
        place: place,
        score: searchScore(for: place, query: query, currentLocation: location) + (nearbyOnly ? 420 : 0),
        distanceMeters: distance,
        importance: item.importance ?? 0,
        isNearbyCandidate: nearbyOnly
      )
    }
  }

  private func buildSearchURL(query: String, near location: GeoPoint?, nearbyOnly: Bool) -> URL? {
    guard var components = URLComponents(string: "https://nominatim.openstreetmap.org/search") else {
      return nil
    }
    var items: [URLQueryItem] = [
      .init(name: "format", value: "jsonv2"),
      .init(name: "limit", value: nearbyOnly ? "10" : "16"),
      .init(name: "addressdetails", value: "1"),
      .init(name: "namedetails", value: "1"),
      .init(name: "dedupe", value: "1"),
      .init(name: "q", value: query)
    ]
    if let location {
      let radiusKilometers = nearbyOnly ? 25.0 : 120.0
      let viewBox = searchViewBox(around: location, radiusKilometers: radiusKilometers)
      items.append(.init(name: "viewbox", value: viewBox))
      if nearbyOnly {
        items.append(.init(name: "bounded", value: "1"))
      }
    }
    components.queryItems = items
    return components.url
  }

  private func candidateName(for item: SearchResultDTO, fallback: String) -> String {
    if let explicitName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !explicitName.isEmpty {
      return explicitName
    }
    if let namedName = item.namedetails?["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !namedName.isEmpty {
      return namedName
    }
    let firstComponent = fallback.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (firstComponent?.isEmpty == false ? firstComponent! : fallback)
  }

  private func formattedAddress(from address: [String: String]?, fallback: String) -> String {
    guard let address else { return fallback }

    let streetName = firstNonBlank(
      address["road"],
      address["pedestrian"],
      address["footway"],
      address["path"],
      address["cycleway"],
      address["residential"]
    )
    let streetLine = [streetName, address["house_number"]]
      .compactMap { value -> String? in
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
          return nil
        }
        return trimmed
      }
      .joined(separator: " ")

    let locality = firstNonBlank(
      address["suburb"],
      address["neighbourhood"],
      address["quarter"],
      address["city_district"],
      address["village"],
      address["town"],
      address["city"],
      address["hamlet"],
      address["municipality"]
    )
    let region = firstNonBlank(
      address["county"],
      address["state"],
      address["region"]
    )
    let country = address["country"]?.trimmingCharacters(in: .whitespacesAndNewlines)

    var orderedParts: [String] = []
    for part in [streetLine, locality, region, country].compactMap({ $0 }) {
      let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !orderedParts.contains(trimmed) else { continue }
      orderedParts.append(trimmed)
    }
    return orderedParts.isEmpty ? fallback : orderedParts.joined(separator: ", ")
  }

  private func firstNonBlank(_ values: String?...) -> String {
    values
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first(where: { !$0.isEmpty }) ?? ""
  }

  private func searchScore(for place: Place, query: String, currentLocation: GeoPoint?) -> Int {
    let normalizedQuery = normalizeForSearch(query)
    guard !normalizedQuery.isEmpty else { return 0 }

    let normalizedName = normalizeForSearch(place.name)
    let normalizedAddress = normalizeForSearch(place.address)
    let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
    let nameTokens = normalizedName.split(separator: " ").map(String.init)

    var score = 0
    if normalizedName == normalizedQuery { score += 600 }
    if normalizedName.hasPrefix(normalizedQuery) { score += 320 }

    for token in queryTokens {
      if nameTokens.contains(token) {
        score += 220
      } else if nameTokens.contains(where: { $0.hasPrefix(token) }) {
        score += 180
      } else if normalizedName.contains(token) {
        score += 140
      }
      if normalizedAddress.contains(token) {
        score += 60
      }
    }

    if let currentLocation, let point = place.point {
      let distance = Int(currentLocation.distance(to: point).rounded())
      switch distance {
      case ...500: score += 700
      case ...2_000: score += 550
      case ...10_000: score += 350
      case ...50_000: score += 120
      default: break
      }
      score -= min(distance / 5_000, 120)
    }

    return score
  }

  private func isBetterSearchCandidate(_ candidate: SearchCandidate, than existing: SearchCandidate) -> Bool {
    if candidate.score != existing.score { return candidate.score > existing.score }
    if candidate.isNearbyCandidate != existing.isNearbyCandidate { return candidate.isNearbyCandidate && !existing.isNearbyCandidate }
    if candidate.distanceMeters != existing.distanceMeters {
      let candidateDistance = candidate.distanceMeters > 0 ? candidate.distanceMeters : Int.max
      let existingDistance = existing.distanceMeters > 0 ? existing.distanceMeters : Int.max
      return candidateDistance < existingDistance
    }
    return candidate.importance > existing.importance
  }

  private func searchViewBox(around location: GeoPoint, radiusKilometers: Double) -> String {
    let latDelta = radiusKilometers / 111.32
    let cosine = max(cos(location.latitude * .pi / 180.0), 0.2)
    let lonDelta = radiusKilometers / (111.32 * cosine)
    let left = location.longitude - lonDelta
    let right = location.longitude + lonDelta
    let top = location.latitude + latDelta
    let bottom = location.latitude - latDelta
    return String(format: "%.6f,%.6f,%.6f,%.6f", left, top, right, bottom)
  }

  private func normalizeForSearch(_ value: String) -> String {
    value
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
