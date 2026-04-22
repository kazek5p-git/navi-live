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

  enum CodingKeys: String, CodingKey {
    case placeID = "place_id"
    case displayName = "display_name"
    case lat
    case lon
    case name
  }
}

struct ReverseGeocodeDTO: Decodable {
  let displayName: String

  enum CodingKeys: String, CodingKey {
    case displayName = "display_name"
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
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func searchPlaces(query: String, near location: GeoPoint?) async throws -> [Place] {
    guard var components = URLComponents(string: "https://nominatim.openstreetmap.org/search") else {
      throw NavigationAPIError.invalidURL
    }
    components.queryItems = [
      .init(name: "format", value: "jsonv2"),
      .init(name: "limit", value: "8"),
      .init(name: "q", value: query)
    ]
    if let location {
      components.queryItems?.append(.init(name: "lat", value: String(location.latitude)))
      components.queryItems?.append(.init(name: "lon", value: String(location.longitude)))
    }
    guard let url = components.url else {
      throw NavigationAPIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw NavigationAPIError.badResponse
    }

    let decoded = try JSONDecoder().decode([SearchResultDTO].self, from: data)
    return decoded.map { item in
      let point = GeoPoint(latitude: Double(item.lat) ?? 0, longitude: Double(item.lon) ?? 0)
      let distance = location.map { Int($0.distance(to: point).rounded()) } ?? 0
      return Place(
        id: "nominatim-\(item.placeID ?? Int.random(in: 1000...9999))",
        name: item.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? item.name! : item.displayName.components(separatedBy: ",").first ?? item.displayName,
        address: item.displayName,
        walkDistanceMeters: distance,
        walkEtaMinutes: max(1, Int((Double(distance) / 78.0).rounded())),
        point: point
      )
    }
  }

  func reverseGeocode(point: GeoPoint) async throws -> String {
    guard var components = URLComponents(string: "https://nominatim.openstreetmap.org/reverse") else {
      throw NavigationAPIError.invalidURL
    }
    components.queryItems = [
      .init(name: "format", value: "jsonv2"),
      .init(name: "lat", value: String(point.latitude)),
      .init(name: "lon", value: String(point.longitude))
    ]
    guard let url = components.url else {
      throw NavigationAPIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw NavigationAPIError.badResponse
    }
    let decoded = try JSONDecoder().decode(ReverseGeocodeDTO.self, from: data)
    return decoded.displayName
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
}
