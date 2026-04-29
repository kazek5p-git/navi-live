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
  let category: String?
  let type: String?

  enum CodingKeys: String, CodingKey {
    case placeID = "place_id"
    case displayName = "display_name"
    case lat
    case lon
    case name
    case namedetails
    case address
    case importance
    case category
    case type
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

struct OverpassResponseDTO: Decodable {
  let elements: [OverpassElementDTO]
}

struct OverpassElementDTO: Decodable {
  let type: String
  let id: Int64
  let lat: Double?
  let lon: Double?
  let center: OverpassCenterDTO?
  let tags: [String: String]?
}

struct OverpassCenterDTO: Decodable {
  let lat: Double
  let lon: Double
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

  private enum PlaceKind {
    case shop
    case parcelLocker
    case railStation
    case busStop
    case tramStop
    case other
  }

  private struct SearchIntent {
    let normalizedQuery: String
    let tokens: [String]
    let nameSearchTerms: [String]
    let wantsShop: Bool
    let wantsParcelLocker: Bool
    let wantsRailStation: Bool
  }

  private let session: URLSession

  private let shopQueryTerms: Set<String> = [
    "sklep", "sklepy", "sklepu", "market", "supermarket", "spozywczy", "spożywczy", "grocery", "store"
  ]
  private let parcelLockerQueryTerms: Set<String> = [
    "paczkomat", "paczkomaty", "paczka", "parcel", "locker", "inpost"
  ]
  private let railStationQueryTerms: Set<String> = [
    "pkp", "kolej", "kolejowa", "kolejowy", "stacja", "dworzec", "pociag", "pociąg", "train", "railway", "station"
  ]

  init(session: URLSession = .shared) {
    self.session = session
  }

  func searchPlaces(query: String, near location: GeoPoint?) async throws -> [Place] {
    let intent = searchIntent(for: query)
    var combinedByID: [String: SearchCandidate] = [:]

    if let location,
       let localCandidates = try? await fetchLocalPOICandidates(query: query, near: location, intent: intent) {
      localCandidates.forEach { candidate in
        combinedByID[candidate.place.id] = candidate
      }
    }

    let nearbyCandidates = try await fetchSearchCandidates(query: query, near: location, nearbyOnly: true, intent: intent)
    nearbyCandidates.forEach { candidate in
      if let existing = combinedByID[candidate.place.id] {
        if isBetterSearchCandidate(candidate, than: existing) {
          combinedByID[candidate.place.id] = candidate
        }
      } else {
        combinedByID[candidate.place.id] = candidate
      }
    }

    if combinedByID.count < SharedProductRules.Search.includeGlobalFallbackIfFewerThan {
      let globalCandidates = try await fetchSearchCandidates(query: query, near: location, nearbyOnly: false, intent: intent)
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
      .prefix(SharedProductRules.Search.resultLimit)
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
      etaMinutes: NavigationScenarioCore.routeEtaMinutes(
        distanceMeters: Int(route.distance.rounded()),
        providerDurationSeconds: route.duration
      ),
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

    let roadName = step.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let descriptor = NavigationInstructionCore.describe(
      maneuverType: step.maneuver.type,
      modifier: step.maneuver.modifier,
      roadName: roadName
    )

    switch step.maneuver.type {
    case "roundabout":
      return L10n.text("navigation.step.roundabout", table: .navigation)
    default:
      switch descriptor.strategy {
      case .departNamed:
        return L10n.text("navigation.step.depart", table: .navigation)
      case .arrive:
        return L10n.text("navigation.step.arrive", table: .navigation)
      case .turnNamed:
        return L10n.text(
          "navigation.step.turn.named",
          table: .navigation,
          descriptor.roadName ?? roadName,
          modifierText(for: descriptor.normalizedModifier)
        )
      case .turnGenericNamed:
        if let roadName = descriptor.roadName, !roadName.isEmpty {
          return L10n.text("navigation.step.turn.generic.named", table: .navigation, roadName)
        }
        return L10n.text("navigation.step.turn.default", table: .navigation)
      case .turnBareModifier:
        guard let normalizedModifier = descriptor.normalizedModifier else {
          return L10n.text("navigation.step.turn.default", table: .navigation)
        }
        return L10n.text("navigation.step.turn.\(normalizedModifier)", table: .navigation)
      case .continueNamed:
        if let roadName = descriptor.roadName, !roadName.isEmpty {
          return L10n.text("navigation.step.continue.named", table: .navigation, roadName)
        }
        return L10n.text("navigation.step.continue", table: .navigation)
      case .proceedTowardNamed:
        if let roadName = descriptor.roadName, !roadName.isEmpty {
          return L10n.text("navigation.step.continue.named", table: .navigation, roadName)
        }
        return L10n.text("navigation.step.continue", table: .navigation)
      }
    }
  }

  private func modifierText(for modifier: String?) -> String {
    let normalized = modifier.map(SharedProductRules.Instructions.normalizeModifier(_:)) ?? ""
    guard SharedProductRules.Instructions.supportedModifiers.contains(normalized) else {
      return modifier ?? ""
    }
    let key = "navigation.modifier.\(normalized)"
    let localized = L10n.text(key, table: .navigation)
    return localized == key ? normalized : localized
  }

  private func fetchLocalPOICandidates(
    query: String,
    near location: GeoPoint,
    intent: SearchIntent
  ) async throws -> [SearchCandidate] {
    let urls = buildOverpassURLs(near: location, intent: intent)
    guard !urls.isEmpty else {
      return []
    }

    var decodedResponse: OverpassResponseDTO?
    var lastError: Error?
    for url in urls {
      do {
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(SharedProductRules.Search.overpassTimeoutSeconds)
        request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")
        request.setValue(Locale.current.identifier.replacingOccurrences(of: "_", with: "-"), forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
          throw NavigationAPIError.badResponse
        }
        decodedResponse = try JSONDecoder().decode(OverpassResponseDTO.self, from: data)
        break
      } catch {
        lastError = error
      }
    }
    guard let decoded = decodedResponse else {
      throw lastError ?? NavigationAPIError.badResponse
    }
    return decoded.elements.compactMap { item -> SearchCandidate? in
      guard let point = overpassPoint(for: item) else { return nil }
      let distance = Int(location.distance(to: point).rounded())
      guard distance <= SharedProductRules.Search.localPoiRadiusMeters else { return nil }
      let tags = item.tags ?? [:]
      let kind = overpassKind(tags: tags)
      guard shouldKeepLocalPOI(tags: tags, kind: kind, intent: intent) else { return nil }
      let name = overpassName(tags: tags, kind: kind)
      let place = Place(
        id: "overpass-\(item.type)-\(item.id)",
        name: labelForKind(name, kind: kind),
        address: overpassAddress(tags: tags, fallback: name),
        walkDistanceMeters: distance,
        walkEtaMinutes: distance > 0 ? NavigationScenarioCore.distanceBasedEtaMinutes(distanceMeters: distance) : 0,
        point: point,
        phone: tags["phone"] ?? tags["contact:phone"],
        website: tags["website"] ?? tags["contact:website"]
      )
      return SearchCandidate(
        place: place,
        score: searchScore(for: place, query: query, currentLocation: location) +
          SharedProductRules.Search.localPoiScore +
          categoryAffinityScore(intent: intent, kind: kind),
        distanceMeters: distance,
        importance: 0,
        isNearbyCandidate: true
      )
    }
  }

  private func buildOverpassURLs(near location: GeoPoint, intent: SearchIntent) -> [URL] {
    var selectors: [String] = []
    let radius = SharedProductRules.Search.localPoiRadiusMeters
    let lat = String(format: "%.6f", location.latitude)
    let lon = String(format: "%.6f", location.longitude)

    if let nameRegex = overpassNameRegex(intent: intent) {
      selectors.append(contentsOf: overpassSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"name\"~\"\(nameRegex)\",i]"))
    }
    if intent.wantsShop {
      selectors.append(contentsOf: overpassSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"shop\"]"))
    }
    if intent.wantsParcelLocker {
      selectors.append(contentsOf: overpassSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"amenity\"=\"parcel_locker\"]"))
    }
    if intent.wantsRailStation {
      selectors.append(contentsOf: overpassSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"railway\"~\"^(station|halt)$\"]"))
      selectors.append(contentsOf: overpassSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"public_transport\"=\"station\"]"))
    }
    guard !selectors.isEmpty else { return [] }

    let overpassQuery = "[out:json][timeout:\(SharedProductRules.Search.overpassTimeoutSeconds)];(" +
      selectors.joined() +
      ");out center \(SharedProductRules.Search.localPoiLimit);"
    return [
      "https://overpass.kumi.systems/api/interpreter",
      "https://overpass-api.de/api/interpreter"
    ].compactMap { rawURL in
      guard var components = URLComponents(string: rawURL) else { return nil }
      components.queryItems = [.init(name: "data", value: overpassQuery)]
      return components.url
    }
  }

  private func overpassSelectors(radius: Int, lat: String, lon: String, filter: String) -> [String] {
    let around = "(around:\(radius),\(lat),\(lon))"
    return [
      "node\(around)\(filter);",
      "way\(around)\(filter);",
      "relation\(around)\(filter);"
    ]
  }

  private func overpassNameRegex(intent: SearchIntent) -> String? {
    let terms = (intent.nameSearchTerms.isEmpty ? intent.tokens : intent.nameSearchTerms)
      .filter { $0.count >= 2 }
      .prefix(4)
    guard !terms.isEmpty else { return nil }
    return terms.map(overpassRegexTerm(_:)).joined(separator: ".*")
  }

  private func overpassRegexTerm(_ term: String) -> String {
    switch term {
    case "zabka":
      return "[zż]abka"
    default:
      return NSRegularExpression.escapedPattern(for: term)
    }
  }

  private func overpassPoint(for item: OverpassElementDTO) -> GeoPoint? {
    if let lat = item.lat, let lon = item.lon {
      return GeoPoint(latitude: lat, longitude: lon)
    }
    if let center = item.center {
      return GeoPoint(latitude: center.lat, longitude: center.lon)
    }
    return nil
  }

  private func overpassName(tags: [String: String], kind: PlaceKind) -> String {
    if let name = tags["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return name
    }
    switch kind {
    case .shop:
      return L10n.text("search.type.unnamed_shop", table: .home)
    case .parcelLocker:
      return L10n.text("search.type.unnamed_parcel_locker", table: .home)
    case .railStation:
      return L10n.text("search.type.unnamed_rail_station", table: .home)
    case .busStop:
      return L10n.text("search.type.unnamed_bus_stop", table: .home)
    case .tramStop:
      return L10n.text("search.type.unnamed_tram_stop", table: .home)
    case .other:
      return L10n.text("search.type.unknown_place", table: .home)
    }
  }

  private func overpassAddress(tags: [String: String], fallback: String) -> String {
    let street = tags["addr:street"] ?? ""
    let houseNumber = tags["addr:housenumber"] ?? ""
    let locality = tags["addr:city"] ?? tags["addr:town"] ?? tags["addr:village"] ?? tags["addr:suburb"] ?? ""
    let streetPart: String
    if !street.isEmpty && !houseNumber.isEmpty {
      streetPart = "\(street) \(houseNumber)"
    } else if !street.isEmpty {
      streetPart = street
    } else {
      streetPart = houseNumber
    }
    let parts = [streetPart, locality].filter { !$0.isEmpty }
    return parts.isEmpty ? fallback : parts.joined(separator: ", ")
  }

  private func shouldKeepLocalPOI(tags: [String: String], kind: PlaceKind, intent: SearchIntent) -> Bool {
    if intent.wantsShop && kind == .shop { return true }
    if intent.wantsParcelLocker && kind == .parcelLocker { return true }
    if intent.wantsRailStation && (kind == .railStation || kind == .busStop || kind == .tramStop) { return true }
    let normalizedName = normalizeForSearch(tags["name"] ?? "")
    return !intent.nameSearchTerms.isEmpty && intent.nameSearchTerms.allSatisfy { normalizedName.contains($0) }
  }

  private func overpassKind(tags: [String: String]) -> PlaceKind {
    let shop = tags["shop"] ?? ""
    let amenity = tags["amenity"] ?? ""
    let railway = tags["railway"] ?? ""
    let publicTransport = tags["public_transport"] ?? ""
    if !shop.isEmpty { return .shop }
    if amenity == "parcel_locker" { return .parcelLocker }
    if railway == "station" || railway == "halt" { return .railStation }
    if tags["station"] == "railway" || (tags["train"] == "yes" && publicTransport == "station") { return .railStation }
    if tags["highway"] == "bus_stop" || (tags["bus"] == "yes" && publicTransport == "platform") { return .busStop }
    if railway == "tram_stop" || (tags["tram"] == "yes" && publicTransport == "platform") { return .tramStop }
    return .other
  }

  private func fetchSearchCandidates(
    query: String,
    near location: GeoPoint?,
    nearbyOnly: Bool,
    intent: SearchIntent
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
    let radiusKilometers = nearbyOnly
      ? SharedProductRules.Search.nearbyRadiusKm
      : SharedProductRules.Search.globalRadiusKm
    let maxDistanceMeters = location.map { _ in
      Int((radiusKilometers * 1000).rounded())
    }
    return decoded.compactMap { item -> SearchCandidate? in
      let point = GeoPoint(latitude: Double(item.lat) ?? 0, longitude: Double(item.lon) ?? 0)
      let distance = location.map { Int($0.distance(to: point).rounded()) } ?? 0
      if let maxDistanceMeters, distance > maxDistanceMeters {
        return nil
      }
      let displayName = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
      let kind = nominatimKind(for: item)
      let place = Place(
        id: "nominatim-\(item.placeID ?? Int.random(in: 1000...9999))",
        name: candidateName(for: item, fallback: displayName, kind: kind),
        address: formattedAddress(from: item.address, fallback: displayName),
        walkDistanceMeters: distance,
        walkEtaMinutes: distance > 0 ? NavigationScenarioCore.distanceBasedEtaMinutes(distanceMeters: distance) : 0,
        point: point
      )
      return SearchCandidate(
        place: place,
        score: searchScore(for: place, query: query, currentLocation: location) +
          categoryAffinityScore(intent: intent, kind: kind) +
          (nearbyOnly ? SharedProductRules.Search.nearbyBonus : 0),
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
      .init(
        name: "limit",
        value: String(nearbyOnly ? SharedProductRules.Search.nearbyLimit : SharedProductRules.Search.globalLimit)
      ),
      .init(name: "addressdetails", value: "1"),
      .init(name: "namedetails", value: "1"),
      .init(name: "dedupe", value: "1"),
      .init(name: "q", value: query)
    ]
    if let location {
      let radiusKilometers = nearbyOnly
        ? SharedProductRules.Search.nearbyRadiusKm
        : SharedProductRules.Search.globalRadiusKm
      let viewBox = searchViewBox(around: location, radiusKilometers: radiusKilometers)
      items.append(.init(name: "viewbox", value: viewBox))
      if nearbyOnly {
        items.append(.init(name: "bounded", value: "1"))
      }
    }
    components.queryItems = items
    return components.url
  }

  private func candidateName(for item: SearchResultDTO, fallback: String, kind: PlaceKind) -> String {
    if let explicitName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !explicitName.isEmpty {
      return labelForKind(explicitName, kind: kind)
    }
    if let namedName = item.namedetails?["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !namedName.isEmpty {
      return labelForKind(namedName, kind: kind)
    }
    let firstComponent = fallback.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let firstComponent, !firstComponent.isEmpty, AddressFormattingCore.isLikelyHouseNumber(firstComponent) {
      let baseName = fallback.components(separatedBy: ",")
        .compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty && !AddressFormattingCore.isLikelyHouseNumber($0) }) ?? fallback
      return labelForKind(baseName, kind: kind)
    }
    return labelForKind(firstComponent?.isEmpty == false ? firstComponent! : fallback, kind: kind)
  }

  private func searchIntent(for query: String) -> SearchIntent {
    let normalized = normalizeForSearch(query)
    let tokens = normalized.split(separator: " ").map(String.init)
    let categoryTerms = shopQueryTerms.union(parcelLockerQueryTerms).union(railStationQueryTerms)
    return SearchIntent(
      normalizedQuery: normalized,
      tokens: tokens,
      nameSearchTerms: tokens.filter { !categoryTerms.contains($0) },
      wantsShop: tokens.contains(where: { shopQueryTerms.contains($0) }),
      wantsParcelLocker: tokens.contains(where: { parcelLockerQueryTerms.contains($0) }),
      wantsRailStation: tokens.contains(where: { railStationQueryTerms.contains($0) })
    )
  }

  private func nominatimKind(for item: SearchResultDTO) -> PlaceKind {
    let category = item.category ?? ""
    let type = item.type ?? ""
    if category == "shop" { return .shop }
    if category == "amenity" && type == "parcel_locker" { return .parcelLocker }
    if category == "railway" && (type == "station" || type == "halt") { return .railStation }
    if category == "public_transport" && type == "station" { return .railStation }
    if category == "highway" && type == "bus_stop" { return .busStop }
    if category == "public_transport" && type == "platform" { return .busStop }
    if category == "railway" && type == "tram_stop" { return .tramStop }
    return .other
  }

  private func categoryAffinityScore(intent: SearchIntent, kind: PlaceKind) -> Int {
    var score = 0
    if intent.wantsShop && kind == .shop {
      score += SharedProductRules.Search.categoryMatchScore
    }
    if intent.wantsParcelLocker && kind == .parcelLocker {
      score += SharedProductRules.Search.categoryMatchScore
    }
    if intent.wantsRailStation {
      switch kind {
      case .railStation:
        score += SharedProductRules.Search.railQueryStationScore
      case .busStop:
        score -= SharedProductRules.Search.railQueryBusStopPenalty
      case .tramStop:
        score -= SharedProductRules.Search.railQueryBusStopPenalty / 2
      default:
        break
      }
    }
    return score
  }

  private func labelForKind(_ name: String, kind: PlaceKind) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    switch kind {
    case .railStation:
      return L10n.text("search.type.rail_station", table: .home, trimmed)
    case .busStop:
      return L10n.text("search.type.bus_stop", table: .home, trimmed)
    case .tramStop:
      return L10n.text("search.type.tram_stop", table: .home, trimmed)
    case .parcelLocker:
      let normalized = normalizeForSearch(trimmed)
      if normalized.contains("paczkomat") || normalized.contains("parcel locker") {
        return trimmed
      }
      return L10n.text("search.type.parcel_locker", table: .home, trimmed)
    default:
      return trimmed
    }
  }

  private func formattedAddress(from address: [String: String]?, fallback: String) -> String {
    AddressFormattingCore.formatAddress(address, fallback: fallback)
  }

  private func searchScore(for place: Place, query: String, currentLocation: GeoPoint?) -> Int {
    let normalizedQuery = normalizeForSearch(query)
    guard !normalizedQuery.isEmpty else { return 0 }

    let normalizedName = normalizeForSearch(place.name)
    let normalizedAddress = normalizeForSearch(place.address)
    let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
    let nameTokens = normalizedName.split(separator: " ").map(String.init)

    var score = 0
    if normalizedName == normalizedQuery { score += SharedProductRules.Search.exactNameScore }
    if normalizedName.hasPrefix(normalizedQuery) { score += SharedProductRules.Search.prefixNameScore }

    for token in queryTokens {
      if nameTokens.contains(token) {
        score += SharedProductRules.Search.exactTokenScore
      } else if nameTokens.contains(where: { $0.hasPrefix(token) }) {
        score += SharedProductRules.Search.prefixTokenScore
      } else if normalizedName.contains(token) {
        score += SharedProductRules.Search.containsTokenScore
      }
      if normalizedAddress.contains(token) {
        score += SharedProductRules.Search.addressTokenScore
      }
    }

    if let currentLocation, let point = place.point {
      let distance = Int(currentLocation.distance(to: point).rounded())
      if let band = SharedProductRules.Search.distanceBands.first(where: { distance <= $0.maxMeters }) {
        score += band.bonus
      }
      score -= min(
        distance / SharedProductRules.Search.distancePenaltyDivisorMeters,
        SharedProductRules.Search.distancePenaltyCap
      )
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
    let cosine = max(cos(location.latitude * .pi / 180.0), SharedProductRules.Search.viewBoxMinimumCosine)
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
