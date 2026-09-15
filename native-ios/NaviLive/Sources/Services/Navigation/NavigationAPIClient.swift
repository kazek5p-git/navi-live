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
  let osmType: String?
  let osmID: Int64?

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
    case osmType = "osm_type"
    case osmID = "osm_id"
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
  let geometry: [OverpassGeometryPointDTO]?
}

private struct ZabkaStoreDTO: Decodable {
  let storeID: String
  let street: String
  let town: String
  let lat: Double
  let lon: Double
  let storeURL: String?

  enum CodingKeys: String, CodingKey {
    case storeID = "storeId"
    case street
    case town
    case lat
    case lon
    case storeURL = "storeUrl"
  }
}

struct OverpassCenterDTO: Decodable {
  let lat: Double
  let lon: Double
}

struct OverpassGeometryPointDTO: Decodable {
  let lat: Double
  let lon: Double
}

private struct NamedRouteWay {
  let name: String
  let highway: String?
  let geometry: [GeoPoint]
}

private struct RouteAlertCandidate {
  let point: GeoPoint
  let distanceAlongRouteMeters: Double
  let instruction: String
  let kind: RouteStepKind
  let roadName: String?
  let maneuverType: String?
}

private struct RouteProjection {
  let distanceAlongRouteMeters: Double
  let lateralDistanceMeters: Double
  let segmentBearingDegrees: Double
}

private struct SegmentProjection {
  let ratio: Double
  let lengthMeters: Double
  let lateralDistanceMeters: Double
  let bearingDegrees: Double
}

private struct RouteBoundingBox {
  let south: Double
  let west: Double
  let north: Double
  let east: Double
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
  let geometry: OSRMGeometry?
}

struct OSRMManeuver: Decodable {
  let instruction: String?
  let modifier: String?
  let type: String
  let location: [Double]
}

actor NavigationAPIClient {
  private struct SearchCandidate {
    var place: Place
    let score: Int
    let distanceMeters: Int
    let importance: Double
    let isNearbyCandidate: Bool
    let kind: SearchPlaceKind
  }

  private struct NearbyAddressCandidate {
    let address: String
    let point: GeoPoint
  }

  private struct SearchIntent {
    let normalizedQuery: String
    let tokens: [String]
    let nameSearchTerms: [String]
    let wantsShop: Bool
    let wantsParcelLocker: Bool
    let wantsRailStation: Bool
    let wantsTransitStop: Bool

    var wantsAnyCategory: Bool {
      wantsShop || wantsParcelLocker || wantsRailStation || wantsTransitStop
    }

    var isCategoryOnly: Bool {
      wantsAnyCategory && nameSearchTerms.isEmpty
    }
  }

  private let session: URLSession
  private let poiCacheStore: NearbyPOICacheStore
  private let localPOITotalTimeout: TimeInterval = 3.5
  private let localPOIRequestTimeout: TimeInterval = 1.8
  private let searchRequestTimeout: TimeInterval = 1.8
  private let poiCacheRefreshRequestTimeout: TimeInterval = 5
  private let addressLookupTimeout: TimeInterval = 5
  private let nearbyAddressLookupRadiusMeters = 80
  private let nearbyAddressLookupLimit = 220
  private let routeRequestTimeout: TimeInterval = 10
  private let routeRoadNameRequestTimeout: TimeInterval = 8
  private let crossingRequestTimeout: TimeInterval = 2
  private let crossingDuplicateProximityMeters = 3.0
  private let crossingTurnProximityMeters = 35.0
  private let crossingNodeLateralLimitMeters = 1.5
  private let routeAlertDeduplicateMeters = 18.0
  private let streetCrossingDeduplicateMeters = 25.0
  private let streetCrossingLateralLimitMeters = 4.0
  private let streetCrossingMinimumBearingDifferenceDegrees = 55.0
  private let streetCrossingRouteRoadOverlapToleranceMeters = 12.0
  private let streetCrossingManeuverType = "street_crossing"
  private let routeStartApproachThresholdMeters = 18.0
  private let minimumInferredRoadStepDistanceMeters = 45
  private let approachManeuverType = "approach"
  private let officialChainScore = 3_000
  private let poiCacheRefreshLimit = 350
  private let zabkaLocatorURL = URL(string: "https://www.zabka.pl/app/uploads/locator-store-data.json")!

  private let shopQueryTerms: Set<String> = [
    "sklep", "sklepy", "sklepu", "market", "supermarket", "spozywczy", "spożywczy", "grocery", "store"
  ]
  private let parcelLockerQueryTerms: Set<String> = [
    "paczkomat", "paczkomaty", "paczka", "parcel", "locker", "inpost"
  ]
  private let railStationQueryTerms: Set<String> = [
    "pkp", "kolej", "kolejowa", "kolejowy", "stacja", "dworzec", "pociag", "pociąg", "train", "railway", "station"
  ]
  private let transitStopQueryTerms: Set<String> = [
    "przystanek", "przystanki", "przystanku", "autobus", "autobusowy", "autobusowa", "bus", "tramwaj", "tramwajowy", "tramwajowa", "tram", "stop"
  ]
  init(session: URLSession = .shared, poiCacheStore: NearbyPOICacheStore = NearbyPOICacheStore()) {
    self.session = session
    self.poiCacheStore = poiCacheStore
  }

  func searchPlaces(
    query: String,
    near location: GeoPoint?,
    searchRadiusKilometers: Int = SharedProductRules.Search.defaultRadiusKm,
    resultLimit: Int = SharedProductRules.Search.resultLimit
  ) async throws -> [Place] {
    let normalizedSearchRadiusKilometers = min(
      max(searchRadiusKilometers, SharedProductRules.Search.minimumRadiusKm),
      SharedProductRules.Search.maximumRadiusKm
    )
    let normalizedResultLimit = min(
      max(resultLimit, SharedProductRules.Search.minimumResultLimit),
      SharedProductRules.Search.maximumResultLimit
    )
    let searchRadiusMeters = normalizedSearchRadiusKilometers * 1_000
    let intent = searchIntent(for: query)
    var combinedByID: [String: SearchCandidate] = [:]

    let initialNearbyRadius: Int? = location.map { _ in
      intent.isCategoryOnly
        ? normalizedSearchRadiusKilometers
        : SharedProductRules.Search.minimumRadiusKm
    }
    async let officialCandidates = officialZabkaCandidatesIfNeeded(
      query: query,
      location: location,
      searchRadiusMeters: searchRadiusMeters,
      intent: intent
    )
    async let cachedCandidates = cachedPOICandidatesIfNeeded(
      location: location,
      searchRadiusMeters: searchRadiusMeters,
      intent: intent,
      resultLimit: normalizedResultLimit,
      query: query
    )
    async let localCandidates = localPOICandidatesIfNeeded(
      query: query,
      location: location,
      searchRadiusMeters: searchRadiusMeters,
      intent: intent,
      resultLimit: normalizedResultLimit
    )
    async let nearbyCandidates = fetchNearbySearchCandidatesIfLocationAvailable(
      query: query,
      near: location,
      nearbyOnly: true,
      searchRadiusKilometers: initialNearbyRadius,
      intent: intent,
      resultLimit: normalizedResultLimit
    )

    let initialCandidates = await [
      officialCandidates,
      cachedCandidates,
      localCandidates,
      nearbyCandidates
    ].flatMap { $0 }
    initialCandidates.forEach { candidate in
      putSearchCandidate(&combinedByID, candidate)
    }

    if location != nil && combinedByID.count < normalizedResultLimit {
      let fallbackRadii = nearbyTextSearchRadiiKilometers(
        normalizedSearchRadiusKilometers: normalizedSearchRadiusKilometers,
        location: location,
        intent: intent
      ).filter { $0 != initialNearbyRadius }
      let fallbackCandidates = await withTaskGroup(of: [SearchCandidate].self, returning: [[SearchCandidate]].self) { group in
        for radiusKilometers in fallbackRadii {
          group.addTask { [self] in
            await self.fetchSearchCandidatesSafely(
              query: query,
              near: location,
              nearbyOnly: true,
              searchRadiusKilometers: radiusKilometers,
              intent: intent,
              resultLimit: normalizedResultLimit
            )
          }
        }
        var results: [[SearchCandidate]] = []
        for await result in group {
          results.append(result)
        }
        return results
      }
      fallbackCandidates.flatMap { $0 }.forEach { candidate in
        putSearchCandidate(&combinedByID, candidate)
      }

      if location != nil,
         combinedByID.count < normalizedResultLimit,
         intent.wantsAnyCategory,
         !intent.isCategoryOnly,
         !intent.nameSearchTerms.isEmpty {
        let simplifiedQuery = intent.nameSearchTerms.joined(separator: " ")
        if !simplifiedQuery.isEmpty && simplifiedQuery.caseInsensitiveCompare(query) != .orderedSame {
          let simplifiedCandidates = await fetchSearchCandidatesSafely(
            query: simplifiedQuery,
            near: location,
            nearbyOnly: true,
            searchRadiusKilometers: SharedProductRules.Search.minimumRadiusKm,
            intent: intent,
            resultLimit: normalizedResultLimit
          )
          simplifiedCandidates.forEach { candidate in
            putSearchCandidate(&combinedByID, candidate)
          }
        }
      }
      if location != nil && intent.isCategoryOnly {
        let expansionQueries: [String]
        if intent.wantsShop {
          expansionQueries = shopCategoryExpansionQueries()
        } else if intent.wantsParcelLocker {
          expansionQueries = parcelLockerCategoryExpansionQueries()
        } else if intent.wantsTransitStop {
          expansionQueries = transitStopCategoryExpansionQueries()
        } else {
          expansionQueries = []
        }
        let expansionCandidates = await withTaskGroup(of: [SearchCandidate].self, returning: [[SearchCandidate]].self) { group in
          for expandedQuery in expansionQueries {
            group.addTask { [self] in
              await self.fetchSearchCandidatesSafely(
                query: expandedQuery,
                near: location,
                nearbyOnly: true,
                searchRadiusKilometers: normalizedSearchRadiusKilometers,
                intent: intent,
                resultLimit: normalizedResultLimit
              )
            }
          }
          var results: [[SearchCandidate]] = []
          for await result in group {
            results.append(result)
          }
          return results
        }
        expansionCandidates.flatMap { $0 }.forEach { candidate in
          putSearchCandidate(&combinedByID, candidate)
        }
      }
    }

    if location == nil || combinedByID.isEmpty {
      let globalCandidates = await fetchSearchCandidatesSafely(
        query: query,
        near: location,
        nearbyOnly: false,
        searchRadiusKilometers: normalizedSearchRadiusKilometers,
        intent: intent,
        resultLimit: normalizedResultLimit
      )
      globalCandidates.forEach { candidate in
        putSearchCandidate(&combinedByID, candidate)
      }
    }

    let sortedCandidates = deduplicatedSearchCandidates(Array(combinedByID.values))
      .sorted(by: compareSearchCandidates(_:_:))
      .prefix(normalizedResultLimit)
      .map { $0 }
    return await enrichedSearchResultAddresses(sortedCandidates)
  }

  private func officialZabkaCandidatesIfNeeded(
    query: String,
    location: GeoPoint?,
    searchRadiusMeters: Int,
    intent: SearchIntent
  ) async -> [SearchCandidate] {
    guard let location, isZabkaQuery(intent) else { return [] }
    return await officialZabkaCandidates(
      query: query,
      near: location,
      searchRadiusMeters: searchRadiusMeters
    )
  }

  private func cachedPOICandidatesIfNeeded(
    location: GeoPoint?,
    searchRadiusMeters: Int,
    intent: SearchIntent,
    resultLimit: Int,
    query: String
  ) async -> [SearchCandidate] {
    guard let location else { return [] }
    return await cachedPOICandidates(
      query: query,
      near: location,
      searchRadiusMeters: searchRadiusMeters,
      intent: intent,
      resultLimit: resultLimit
    )
  }

  private func localPOICandidatesIfNeeded(
    query: String,
    location: GeoPoint?,
    searchRadiusMeters: Int,
    intent: SearchIntent,
    resultLimit: Int
  ) async -> [SearchCandidate] {
    guard let location else { return [] }
    return (try? await fetchLocalPOICandidates(
      query: query,
      near: location,
      searchRadiusMeters: searchRadiusMeters,
      intent: intent,
      resultLimit: resultLimit
    )) ?? []
  }

  private func fetchSearchCandidatesSafely(
    query: String,
    near location: GeoPoint?,
    nearbyOnly: Bool,
    searchRadiusKilometers: Int,
    intent: SearchIntent,
    resultLimit: Int
  ) async -> [SearchCandidate] {
    (try? await fetchSearchCandidates(
      query: query,
      near: location,
      nearbyOnly: nearbyOnly,
      searchRadiusKilometers: searchRadiusKilometers,
      intent: intent,
      resultLimit: resultLimit
    )) ?? []
  }

  private func fetchNearbySearchCandidatesIfLocationAvailable(
    query: String,
    near location: GeoPoint?,
    nearbyOnly: Bool,
    searchRadiusKilometers: Int?,
    intent: SearchIntent,
    resultLimit: Int
  ) async -> [SearchCandidate] {
    guard location != nil, let searchRadiusKilometers else { return [] }
    return await fetchSearchCandidatesSafely(
      query: query,
      near: location,
      nearbyOnly: nearbyOnly,
      searchRadiusKilometers: searchRadiusKilometers,
      intent: intent,
      resultLimit: resultLimit
    )
  }

  func nearbyPOICacheState() async -> NearbyPOICacheState {
    await poiCacheStore.metadata()
  }

  func clearNearbyPOICache() async -> NearbyPOICacheState {
    await poiCacheStore.clear()
  }

  func refreshNearbyPOICache(near location: GeoPoint, radiusKilometers: Int) async throws -> NearbyPOICacheState {
    let radiusMeters = min(max(radiusKilometers, SharedProductRules.Search.minimumRadiusKm), 5) * 1_000
    let fetchedAt = Date()
    let records = try await fetchNearbyPOICacheRecords(
      near: location,
      radiusMeters: radiusMeters,
      fetchedAt: fetchedAt
    )
    return await poiCacheStore.saveMerged(records: records, center: location, fetchedAt: fetchedAt)
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
    request.timeoutInterval = addressLookupTimeout
    request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")
    request.setValue(L10n.acceptLanguageTag, forHTTPHeaderField: "Accept-Language")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw NavigationAPIError.badResponse
    }
    let decoded = try JSONDecoder().decode(ReverseGeocodeDTO.self, from: data)
    return formattedAddress(from: decoded.address, fallback: decoded.displayName)
  }

  func buildWalkingRoute(
    from start: GeoPoint,
    to destination: Place,
    includePedestrianCrossings: Bool = true,
    includeJunctionAlerts: Bool = true
  ) async throws -> RouteSummary {
    guard let destinationPoint = destination.point else {
      throw NavigationAPIError.noRoute
    }
    let coordinateString = "\(start.longitude),\(start.latitude);\(destinationPoint.longitude),\(destinationPoint.latitude)"
    let decoded = try await fetchRouteResponse(coordinateString: coordinateString)
    guard let route = decoded.routes.first else {
      throw NavigationAPIError.noRoute
    }

    let points = route.geometry.coordinates.compactMap { coordinate -> GeoPoint? in
      guard coordinate.count >= 2 else { return nil }
      return GeoPoint(latitude: coordinate[1], longitude: coordinate[0])
    }
    async let namedRouteWaysTask = fetchNamedRouteWays(pathPoints: points)
    async let pedestrianCrossingsTask = fetchPedestrianCrossingsIfNeeded(
      pathPoints: points,
      routeLengthMeters: routeLengthMeters(pathPoints: points),
      enabled: includePedestrianCrossings
    )
    let namedRouteWays = await namedRouteWaysTask
    let pedestrianCrossings = await pedestrianCrossingsTask

    let baseSteps = route.legs.flatMap(\.steps).map { step in
      let maneuverPoint = step.maneuver.location.count >= 2
        ? GeoPoint(latitude: step.maneuver.location[1], longitude: step.maneuver.location[0])
        : nil
      let distanceMeters = Int(step.distance.rounded())
      let stepGeometry = stepGeometry(for: step)
      let inferredRoadName = shouldInferRoadName(distanceMeters: distanceMeters, stepGeometry: stepGeometry)
        ? inferredRoadName(
          for: step,
          providedStepGeometry: stepGeometry,
          maneuverPoint: maneuverPoint,
          namedRouteWays: namedRouteWays,
          maximumDistanceMeters: roadNameInferenceDistanceLimit(distanceMeters: distanceMeters)
        )
        : nil
      let explicitRoadName = step.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let roadName = explicitRoadName.isEmpty ? inferredRoadName : explicitRoadName
      return RouteStep(
        instruction: humanInstruction(for: step, inferredRoadName: roadName),
        distanceMeters: distanceMeters,
        maneuverPoint: maneuverPoint,
        maneuverType: step.maneuver.type,
        maneuverModifier: step.maneuver.modifier,
        roadName: roadName
      )
    }

    let simplifiedSteps = simplifyRouteSteps(baseSteps)
    let baseRouteSteps = routeStepsWithStartApproach(start: start, pathPoints: points, steps: simplifiedSteps)

    let steps = routeStepsAddingRouteAlerts(
      steps: baseRouteSteps,
      pathPoints: points,
      namedRouteWays: namedRouteWays,
      pedestrianCrossings: pedestrianCrossings,
      includePedestrianCrossings: includePedestrianCrossings,
      includeJunctionAlerts: includeJunctionAlerts
    )

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

  private func routeStepsWithStartApproach(
    start: GeoPoint,
    pathPoints: [GeoPoint],
    steps: [RouteStep]
  ) -> [RouteStep] {
    guard let routeStart = pathPoints.first else { return steps }
    let distanceToRouteStart = start.distance(to: routeStart)
    guard distanceToRouteStart >= routeStartApproachThresholdMeters else { return steps }
    let approachStep = RouteStep(
      instruction: L10n.text("navigation.step.reach_route_start", table: .navigation),
      distanceMeters: max(Int(distanceToRouteStart.rounded()), 1),
      maneuverPoint: routeStart,
      maneuverType: approachManeuverType
    )
    return [approachStep] + steps
  }

  private func fetchRouteResponse(coordinateString: String) async throws -> OSRMResponse {
    var firstValidResponse: OSRMResponse?
    var lastError: Error?
    for url in routeURLs(coordinateString: coordinateString) {
      do {
        var request = URLRequest(url: url)
        request.timeoutInterval = routeRequestTimeout
        request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
          throw NavigationAPIError.badResponse
        }
        let decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)
        guard !decoded.routes.isEmpty else {
          lastError = NavigationAPIError.noRoute
          continue
        }
        if firstValidResponse == nil {
          firstValidResponse = decoded
        }
        if hasNamedRouteSteps(decoded) {
          return decoded
        }
      } catch {
        lastError = error
      }
    }
    if let firstValidResponse { return firstValidResponse }
    throw lastError ?? NavigationAPIError.noRoute
  }

  private func hasNamedRouteSteps(_ response: OSRMResponse) -> Bool {
    response.routes.first?.legs
      .flatMap(\.steps)
      .contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
  }

  private func routeURLs(coordinateString: String) -> [URL] {
    let query = "?overview=full&geometries=geojson&steps=true&alternatives=false"
    return [
      "https://routing.openstreetmap.de/routed-foot/route/v1/foot/\(coordinateString)\(query)",
      "https://router.project-osrm.org/route/v1/foot/\(coordinateString)\(query)"
    ].compactMap(URL.init(string:))
  }

  private func fetchNamedRouteWays(pathPoints: [GeoPoint]) async -> [NamedRouteWay] {
    guard pathPoints.count >= 2 else { return [] }
    for url in buildNamedRouteWayURLs(pathPoints: pathPoints) {
      do {
        var request = URLRequest(url: url)
        request.timeoutInterval = routeRoadNameRequestTimeout
        request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")
        request.setValue(L10n.acceptLanguageTag, forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
          continue
        }
        let decoded = try JSONDecoder().decode(OverpassResponseDTO.self, from: data)
        let ways = decoded.elements.compactMap(namedRouteWay(from:))
        if !ways.isEmpty { return ways }
      } catch {
        continue
      }
    }
    return []
  }

  private func buildNamedRouteWayURLs(pathPoints: [GeoPoint]) -> [URL] {
    let box = routeBoundingBox(pathPoints: pathPoints, paddingMeters: 60)
    let bbox = "(\(formatCoordinate(box.south)),\(formatCoordinate(box.west))," +
      "\(formatCoordinate(box.north)),\(formatCoordinate(box.east)))"
    let query = "[out:json][timeout:\(SharedProductRules.Search.overpassTimeoutSeconds)];" +
      "way[\"highway\"][\"name\"]\(bbox);out geom;"
    return [
      "https://overpass-api.de/api/interpreter",
      "https://overpass.kumi.systems/api/interpreter",
      "https://overpass.osm.ch/api/interpreter"
    ].compactMap { rawURL in
      guard var components = URLComponents(string: rawURL) else { return nil }
      components.queryItems = [.init(name: "data", value: query)]
      return components.url
    }
  }

  private func namedRouteWay(from item: OverpassElementDTO) -> NamedRouteWay? {
    guard item.type == "way",
          let tags = item.tags,
          let name = tags["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !name.isEmpty,
          isUsefulRouteWayName(highway: tags["highway"], tags: tags) else {
      return nil
    }
    let geometry = item.geometry?.map { GeoPoint(latitude: $0.lat, longitude: $0.lon) } ?? []
    guard geometry.count >= 2 else { return nil }
    return NamedRouteWay(name: name, highway: tags["highway"], geometry: geometry)
  }

  private func isUsefulRouteWayName(highway: String?, tags: [String: String]) -> Bool {
    guard let highway, !highway.isEmpty else { return false }
    if ["platform", "corridor", "elevator", "construction", "proposed"].contains(highway) {
      return false
    }
    return tags["area"] != "yes"
  }

  private func isStreetCrossingWay(highway: String?) -> Bool {
    guard let highway else { return false }
    return [
      "primary",
      "secondary",
      "tertiary",
      "residential",
      "living_street",
      "unclassified",
      "service",
      "pedestrian"
    ].contains(highway)
  }

  private func inferredRoadName(
    for step: OSRMStep,
    providedStepGeometry: [GeoPoint]? = nil,
    maneuverPoint: GeoPoint?,
    namedRouteWays: [NamedRouteWay],
    maximumDistanceMeters: Double = 45
  ) -> String? {
    guard !namedRouteWays.isEmpty else { return nil }
    let samples = routeNameSamples(
      stepGeometry: providedStepGeometry ?? stepGeometry(for: step),
      maneuverPoint: maneuverPoint
    )
    guard !samples.isEmpty else { return nil }

    return namedRouteWays
      .compactMap { way -> (way: NamedRouteWay, score: Double)? in
        let distance = samples
          .map { routeWayDistanceMeters(way: way, point: $0) }
          .min() ?? .greatestFiniteMagnitude
        guard distance <= maximumDistanceMeters else { return nil }
        return (way, distance + routeWayPriorityPenalty(highway: way.highway))
      }
      .min(by: { $0.score < $1.score })?
      .way
      .name
  }

  private func shouldInferRoadName(distanceMeters: Int, stepGeometry: [GeoPoint]) -> Bool {
    !stepGeometry.isEmpty || distanceMeters >= minimumInferredRoadStepDistanceMeters
  }

  private func roadNameInferenceDistanceLimit(distanceMeters: Int) -> Double {
    distanceMeters < minimumInferredRoadStepDistanceMeters ? 15 : 45
  }

  private func stepGeometry(for step: OSRMStep) -> [GeoPoint] {
    step.geometry?.coordinates.compactMap { coordinate in
      guard coordinate.count >= 2 else { return nil }
      return GeoPoint(latitude: coordinate[1], longitude: coordinate[0])
    } ?? []
  }

  private func routeNameSamples(stepGeometry: [GeoPoint], maneuverPoint: GeoPoint?) -> [GeoPoint] {
    if stepGeometry.count >= 3 {
      return [stepGeometry[stepGeometry.count / 2], stepGeometry[stepGeometry.count - 1]]
    }
    if let last = stepGeometry.last { return [last] }
    return maneuverPoint.map { [$0] } ?? []
  }

  private func routeWayDistanceMeters(way: NamedRouteWay, point: GeoPoint) -> Double {
    guard way.geometry.count >= 2 else { return .greatestFiniteMagnitude }
    var minimumDistance = Double.greatestFiniteMagnitude
    for index in 0..<(way.geometry.count - 1) {
      let projection = projectOntoSegment(
        point: point,
        start: way.geometry[index],
        end: way.geometry[index + 1]
      )
      minimumDistance = min(minimumDistance, projection.lateralDistanceMeters)
    }
    return minimumDistance
  }

  private func routeWayPriorityPenalty(highway: String?) -> Double {
    switch highway {
    case "footway", "path", "steps", "cycleway", "track":
      return 8
    default:
      return 0
    }
  }

  private func humanInstruction(for step: OSRMStep, inferredRoadName: String? = nil) -> String {
    let explicitRoadName = step.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let inferredRoadName = inferredRoadName?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let roadName = explicitRoadName.isEmpty ? inferredRoadName : explicitRoadName
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
        if let roadName = descriptor.roadName, !roadName.isEmpty {
          return L10n.text("navigation.step.depart.named", table: .navigation, roadName)
        }
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

  private func simplifyRouteSteps(_ steps: [RouteStep]) -> [RouteStep] {
    guard steps.count > 2 else { return steps }
    var simplified: [RouteStep] = []
    for (index, step) in steps.enumerated() {
      let previous = simplified.last
      let next = index < steps.count - 1 ? steps[index + 1] : nil
      if shouldSuppressRouteStep(step, previous: previous, next: next, index: index, lastIndex: steps.count - 1) {
        guard var mergedPrevious = simplified.popLast() else { continue }
        mergedPrevious.distanceMeters += step.distanceMeters
        simplified.append(mergedPrevious)
      } else {
        simplified.append(step)
      }
    }
    return simplified.isEmpty ? steps : simplified
  }

  private func normalizedRouteRoadName(_ value: String?) -> String? {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    return normalized?.isEmpty == false ? normalized : nil
  }

  private func shouldSuppressRouteStep(
    _ step: RouteStep,
    previous: RouteStep?,
    next: RouteStep?,
    index: Int,
    lastIndex: Int
  ) -> Bool {
    RouteStepSimplificationCore.shouldSuppressRouteStep(
      step,
      previous: previous,
      next: next,
      index: index,
      lastIndex: lastIndex
    )
  }

  private func routeStepsAddingRouteAlerts(
    steps: [RouteStep],
    pathPoints: [GeoPoint],
    namedRouteWays: [NamedRouteWay],
    pedestrianCrossings: [RouteAlertCandidate],
    includePedestrianCrossings: Bool,
    includeJunctionAlerts: Bool
  ) -> [RouteStep] {
    guard !steps.isEmpty, pathPoints.count >= 2 else { return steps }
    let routeLength = routeLengthMeters(pathPoints: pathPoints)
    var alerts: [RouteAlertCandidate] = []
    if includePedestrianCrossings {
      alerts += pedestrianCrossings
    }
    if includeJunctionAlerts {
      alerts += routeStreetCrossings(
        pathPoints: pathPoints,
        namedRouteWays: namedRouteWays,
        routeLengthMeters: routeLength
      )
    }
    alerts = deduplicatedRouteAlerts(alerts)
    guard !alerts.isEmpty else { return steps }

    let stepDistances = stepDistancesAlongRoute(
      steps: steps,
      pathPoints: pathPoints
    )
    var augmented: [RouteStep] = [steps[0]]
    var alertIndex = 0
    var lastAlongMeters = stepDistances.first ?? 0

    for stepIndex in 1..<steps.count {
      let stepAlongMeters = stepDistances[stepIndex]
      let nextStep = steps[stepIndex]
      while alertIndex < alerts.count,
            alerts[alertIndex].distanceAlongRouteMeters < stepAlongMeters {
        let alert = alerts[alertIndex]
        let previousStep = augmented.last(where: { $0.kind == .instruction })
        let distanceFromPreviousRaw = alert.distanceAlongRouteMeters - lastAlongMeters
        let distanceToNextStep = stepAlongMeters - alert.distanceAlongRouteMeters
        let nearbyRouteRoadNames = routeRoadNamesNearAlert(
          steps: steps,
          stepDistances: stepDistances,
          alertDistanceMeters: alert.distanceAlongRouteMeters,
          nextStepIndex: stepIndex
        )
        if shouldSuppressRouteAlert(
          alert: alert,
          distanceFromPreviousMeters: distanceFromPreviousRaw,
          previousStep: previousStep,
          distanceToNextStepMeters: distanceToNextStep,
          nextStep: nextStep,
          nearbyRouteRoadNames: nearbyRouteRoadNames
        ) {
          alertIndex += 1
          continue
        }
        let distanceFromPrevious = max(Int(distanceFromPreviousRaw.rounded()), 1)
        augmented.append(
          RouteStep(
            instruction: alert.instruction,
            distanceMeters: distanceFromPrevious,
            maneuverPoint: alert.point,
            kind: alert.kind,
            maneuverType: alert.maneuverType,
            roadName: alert.roadName
          )
        )
        lastAlongMeters = alert.distanceAlongRouteMeters
        alertIndex += 1
      }
      augmented.append(steps[stepIndex])
      lastAlongMeters = max(lastAlongMeters, stepAlongMeters)
    }

    // Nie gub alertów, gdy ostatni krok routera nie ma punktu manewru
    // albo kończy się przed końcowym fragmentem geometrii.
    while alertIndex < alerts.count {
      let alert = alerts[alertIndex]
      let previousStep = augmented.last(where: { $0.kind == .instruction })
      let distanceFromPreviousRaw = alert.distanceAlongRouteMeters - lastAlongMeters
      let alertRoad = normalizedRouteRoadName(alert.roadName)
      let shouldSuppress = distanceFromPreviousRaw < crossingDuplicateProximityMeters ||
        (isNamedStreetCrossing(alert) && alertRoad != nil &&
          normalizedRouteRoadName(previousStep?.roadName) == alertRoad)
      if !shouldSuppress, distanceFromPreviousRaw > 0 {
        augmented.append(
          RouteStep(
            instruction: alert.instruction,
            distanceMeters: max(Int(distanceFromPreviousRaw.rounded()), 1),
            maneuverPoint: alert.point,
            kind: alert.kind,
            maneuverType: alert.maneuverType,
            roadName: alert.roadName
          )
        )
      }
      lastAlongMeters = max(lastAlongMeters, alert.distanceAlongRouteMeters)
      alertIndex += 1
    }
    return augmented
  }

  private func deduplicatedRouteAlerts(_ alerts: [RouteAlertCandidate]) -> [RouteAlertCandidate] {
    var deduplicated: [RouteAlertCandidate] = []
    for candidate in alerts.sorted(by: {
      if $0.distanceAlongRouteMeters != $1.distanceAlongRouteMeters {
        return $0.distanceAlongRouteMeters < $1.distanceAlongRouteMeters
      }
      return isNamedStreetCrossing($0) && !isNamedStreetCrossing($1)
    }) {
      if let existingIndex = deduplicated.firstIndex(where: {
        abs($0.distanceAlongRouteMeters - candidate.distanceAlongRouteMeters) < routeAlertDeduplicateMeters
      }) {
        if isNamedStreetCrossing(candidate), !isNamedStreetCrossing(deduplicated[existingIndex]) {
          deduplicated[existingIndex] = candidate
        }
      } else {
        deduplicated.append(candidate)
      }
    }
    return deduplicated.sorted { $0.distanceAlongRouteMeters < $1.distanceAlongRouteMeters }
  }

  private func shouldSuppressRouteAlert(
    alert: RouteAlertCandidate,
    distanceFromPreviousMeters: Double,
    previousStep: RouteStep?,
    distanceToNextStepMeters: Double,
    nextStep: RouteStep,
    nearbyRouteRoadNames: Set<String>
  ) -> Bool {
    if distanceFromPreviousMeters < crossingDuplicateProximityMeters { return true }
    if isNamedStreetCrossing(alert) {
      if let alertRoad = normalizedRouteRoadName(alert.roadName) {
        if normalizedRouteRoadName(previousStep?.roadName) == alertRoad { return true }
        if normalizedRouteRoadName(nextStep.roadName) == alertRoad { return true }
        if nearbyRouteRoadNames.contains(alertRoad) { return true }
      }
      return false
    }
    if distanceFromPreviousMeters < crossingTurnProximityMeters,
       previousStep?.isTurnLikeManeuver == true {
      return true
    }
    if distanceToNextStepMeters < crossingTurnProximityMeters,
       nextStep.isTurnLikeManeuver {
      return true
    }
    return false
  }

  private func routeRoadNamesNearAlert(
    steps: [RouteStep],
    stepDistances: [Double],
    alertDistanceMeters: Double,
    nextStepIndex: Int
  ) -> Set<String> {
    guard !steps.isEmpty, !stepDistances.isEmpty else { return [] }
    var names: Set<String> = []
    let startIndex = max(nextStepIndex - 3, 0)
    let endIndex = min(nextStepIndex + 3, steps.count - 1)
    for index in startIndex...endIndex {
      guard let roadName = normalizedRouteRoadName(steps[index].roadName),
            stepDistances.indices.contains(index) else {
        continue
      }
      let stepStart = stepDistances[index]
      let stepEnd = stepDistances.indices.contains(index + 1)
        ? stepDistances[index + 1]
        : stepStart + Double(steps[index].distanceMeters)
      let spanStart = min(stepStart, stepEnd) - streetCrossingRouteRoadOverlapToleranceMeters
      let spanEnd = max(stepStart, stepEnd) + streetCrossingRouteRoadOverlapToleranceMeters
      if alertDistanceMeters >= spanStart, alertDistanceMeters <= spanEnd {
        names.insert(roadName)
      }
    }
    return names
  }

  private func isNamedStreetCrossing(_ alert: RouteAlertCandidate) -> Bool {
    alert.maneuverType == streetCrossingManeuverType && alert.roadName?.isEmpty == false
  }

  private func fetchPedestrianCrossingsIfNeeded(
    pathPoints: [GeoPoint],
    routeLengthMeters: Double,
    enabled: Bool
  ) async -> [RouteAlertCandidate] {
    guard enabled else { return [] }
    return (try? await fetchPedestrianCrossings(
      pathPoints: pathPoints,
      routeLengthMeters: routeLengthMeters
    )) ?? []
  }

  private func fetchPedestrianCrossings(
    pathPoints: [GeoPoint],
    routeLengthMeters routeLength: Double
  ) async throws -> [RouteAlertCandidate] {
    let urls = buildPedestrianCrossingURLs(pathPoints: pathPoints)
    var decodedResponse: OverpassResponseDTO?
    var lastError: Error?
    for url in urls {
      do {
        var request = URLRequest(url: url)
        request.timeoutInterval = crossingRequestTimeout
        request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")
        request.setValue(L10n.acceptLanguageTag, forHTTPHeaderField: "Accept-Language")

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

    let candidates = decoded.elements.compactMap { item -> RouteAlertCandidate? in
      guard PedestrianCrossingCore.isPedestrianCrossing(tags: item.tags ?? [:]) else { return nil }
      guard let point = overpassPoint(for: item) else { return nil }
      let crossingGeometry = item.geometry?.map { GeoPoint(latitude: $0.lat, longitude: $0.lon) } ?? []
      let intersection: RoutePolylineIntersection?
      if crossingGeometry.count >= 2 {
        intersection = RouteProjectionCore.polylineIntersections(
          routePoints: pathPoints,
          otherPoints: crossingGeometry,
          endpointToleranceMeters: crossingNodeLateralLimitMeters
        ).first
      } else if let projection = projectOntoRoute(pathPoints: pathPoints, point: point),
                projection.lateralDistanceMeters <= crossingNodeLateralLimitMeters {
        intersection = RoutePolylineIntersection(
          point: point,
          distanceAlongRouteMeters: projection.distanceAlongRouteMeters,
          routeSegmentIndex: 0,
          otherSegmentIndex: 0,
          crossingAngleDegrees: 90
        )
      } else {
        intersection = nil
      }
      guard let intersection,
            intersection.distanceAlongRouteMeters >= 20,
            intersection.distanceAlongRouteMeters <= routeLength - 20 else {
        return nil
      }
      return RouteAlertCandidate(
        point: intersection.point,
        distanceAlongRouteMeters: intersection.distanceAlongRouteMeters,
        instruction: L10n.text("navigation.step.crossing", table: .navigation),
        kind: .pedestrianCrossing,
        roadName: nil,
        maneuverType: nil
      )
    }

    var deduplicated: [RouteAlertCandidate] = []
    for candidate in candidates.sorted(by: { $0.distanceAlongRouteMeters < $1.distanceAlongRouteMeters }) {
      if let previous = deduplicated.last,
         candidate.distanceAlongRouteMeters - previous.distanceAlongRouteMeters < 25 {
        continue
      }
      deduplicated.append(candidate)
    }
    return deduplicated
  }

  private func routeStreetCrossings(
    pathPoints: [GeoPoint],
    namedRouteWays: [NamedRouteWay],
    routeLengthMeters routeLength: Double
  ) -> [RouteAlertCandidate] {
    guard pathPoints.count >= 2, !namedRouteWays.isEmpty else { return [] }
    var candidates: [RouteAlertCandidate] = []
    for way in namedRouteWays {
      guard isStreetCrossingWay(highway: way.highway),
            let normalizedName = normalizedRouteRoadName(way.name) else {
        continue
      }
      let intersections = RouteProjectionCore.polylineIntersections(
        routePoints: pathPoints,
        otherPoints: way.geometry,
        endpointToleranceMeters: streetCrossingLateralLimitMeters
      )
      for intersection in intersections {
        guard NavigationScenarioCore.isMeaningfulCrossing(
          crossingAngleDegrees: intersection.crossingAngleDegrees,
          minimumBearingDifferenceDegrees: streetCrossingMinimumBearingDifferenceDegrees
        ) else { continue }
        guard intersection.distanceAlongRouteMeters >= 20,
              intersection.distanceAlongRouteMeters <= routeLength - 20 else { continue }
        if candidates.contains(where: {
          normalizedRouteRoadName($0.roadName) == normalizedName &&
            abs($0.distanceAlongRouteMeters - intersection.distanceAlongRouteMeters) < streetCrossingDeduplicateMeters
        }) {
          continue
        }
        candidates.append(
          RouteAlertCandidate(
            point: intersection.point,
            distanceAlongRouteMeters: intersection.distanceAlongRouteMeters,
            instruction: L10n.text("navigation.step.cross_street", table: .navigation, way.name),
            kind: .instruction,
            roadName: way.name,
            maneuverType: streetCrossingManeuverType
          )
        )
      }
    }
    return candidates.sorted { $0.distanceAlongRouteMeters < $1.distanceAlongRouteMeters }
  }

  private func buildPedestrianCrossingURLs(pathPoints: [GeoPoint]) -> [URL] {
    let box = routeBoundingBox(pathPoints: pathPoints, paddingMeters: 25)
    let bbox = "(\(formatCoordinate(box.south)),\(formatCoordinate(box.west))," +
      "\(formatCoordinate(box.north)),\(formatCoordinate(box.east)))"
    let query = "[out:json][timeout:\(SharedProductRules.Search.overpassTimeoutSeconds)];" +
      "(" +
      "node[\"highway\"=\"crossing\"]\(bbox);" +
      "node[\"crossing\"]\(bbox);" +
      "way[\"highway\"=\"crossing\"]\(bbox);" +
      "way[\"footway\"=\"crossing\"]\(bbox);" +
      "way[\"crossing\"]\(bbox);" +
      ");out geom 160;"
    return [
      "https://overpass-api.de/api/interpreter",
      "https://overpass.kumi.systems/api/interpreter",
      "https://overpass.osm.ch/api/interpreter"
    ].compactMap { rawURL in
      guard var components = URLComponents(string: rawURL) else { return nil }
      components.queryItems = [.init(name: "data", value: query)]
      return components.url
    }
  }

  private func stepDistancesAlongRoute(
    steps: [RouteStep],
    pathPoints: [GeoPoint]
  ) -> [Double] {
    RouteProjectionCore.stepDistancesAlongRoute(steps: steps, pathPoints: pathPoints)
  }

  private func routeBoundingBox(pathPoints: [GeoPoint], paddingMeters: Double) -> RouteBoundingBox {
    let minLatitude = pathPoints.map(\.latitude).min() ?? 0
    let maxLatitude = pathPoints.map(\.latitude).max() ?? 0
    let minLongitude = pathPoints.map(\.longitude).min() ?? 0
    let maxLongitude = pathPoints.map(\.longitude).max() ?? 0
    let midLatitudeRadians = ((minLatitude + maxLatitude) / 2.0) * .pi / 180.0
    let latitudePadding = paddingMeters / 111_320.0
    let longitudePadding = paddingMeters / (111_320.0 * max(cos(midLatitudeRadians), 0.2))
    return RouteBoundingBox(
      south: minLatitude - latitudePadding,
      west: minLongitude - longitudePadding,
      north: maxLatitude + latitudePadding,
      east: maxLongitude + longitudePadding
    )
  }

  private func formatCoordinate(_ value: Double) -> String {
    String(format: "%.6f", value)
  }

  private func projectOntoRoute(pathPoints: [GeoPoint], point: GeoPoint) -> RouteProjection? {
    guard pathPoints.count >= 2 else { return nil }
    var bestProjection: RouteProjection?
    var distanceBeforeSegment = 0.0

    for index in 0..<(pathPoints.count - 1) {
      let segmentProjection = projectOntoSegment(
        point: point,
        start: pathPoints[index],
        end: pathPoints[index + 1]
      )
      let projection = RouteProjection(
        distanceAlongRouteMeters: distanceBeforeSegment + segmentProjection.lengthMeters * segmentProjection.ratio,
        lateralDistanceMeters: segmentProjection.lateralDistanceMeters,
        segmentBearingDegrees: segmentProjection.bearingDegrees
      )
      if bestProjection == nil || projection.lateralDistanceMeters < bestProjection!.lateralDistanceMeters {
        bestProjection = projection
      }
      distanceBeforeSegment += segmentProjection.lengthMeters
    }
    return bestProjection
  }

  private func projectOntoSegment(point: GeoPoint, start: GeoPoint, end: GeoPoint) -> SegmentProjection {
    let latitudeReference = ((point.latitude + start.latitude + end.latitude) / 3.0) * .pi / 180.0
    let earthRadius = 6_371_000.0

    func project(_ geoPoint: GeoPoint) -> (x: Double, y: Double) {
      let x = geoPoint.longitude * .pi / 180.0 * earthRadius * cos(latitudeReference)
      let y = geoPoint.latitude * .pi / 180.0 * earthRadius
      return (x, y)
    }

    let pointProjection = project(point)
    let startProjection = project(start)
    let endProjection = project(end)
    let dx = endProjection.x - startProjection.x
    let dy = endProjection.y - startProjection.y
    let lengthSquared = dx * dx + dy * dy

    guard lengthSquared > 0 else {
      let distance = sqrt(
        pow(pointProjection.x - startProjection.x, 2) +
          pow(pointProjection.y - startProjection.y, 2)
      )
      return SegmentProjection(ratio: 0, lengthMeters: 0, lateralDistanceMeters: distance, bearingDegrees: 0)
    }

    let ratio = min(
      max(
        ((pointProjection.x - startProjection.x) * dx + (pointProjection.y - startProjection.y) * dy) / lengthSquared,
        0
      ),
      1
    )
    let closestX = startProjection.x + dx * ratio
    let closestY = startProjection.y + dy * ratio
    let lateralDistance = sqrt(
      pow(pointProjection.x - closestX, 2) + pow(pointProjection.y - closestY, 2)
    )
    return SegmentProjection(
      ratio: ratio,
      lengthMeters: sqrt(lengthSquared),
      lateralDistanceMeters: lateralDistance,
      bearingDegrees: normalizedBearingDegrees(radians: atan2(dx, dy))
    )
  }

  private func normalizedBearingDegrees(radians: Double) -> Double {
    let degrees = radians * 180.0 / .pi
    return degrees >= 0 ? degrees : degrees + 360.0
  }

  private func routeLengthMeters(pathPoints: [GeoPoint]) -> Double {
    guard pathPoints.count >= 2 else { return 0 }
    var length = 0.0
    for index in 0..<(pathPoints.count - 1) {
      length += pathPoints[index].distance(to: pathPoints[index + 1])
    }
    return length
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

  private func officialZabkaCandidates(
    query: String,
    near location: GeoPoint,
    searchRadiusMeters: Int
  ) async -> [SearchCandidate] {
    var request = URLRequest(url: zabkaLocatorURL)
    request.timeoutInterval = 4
    request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await session.data(for: request),
          let http = response as? HTTPURLResponse,
          200..<300 ~= http.statusCode,
          let stores = try? JSONDecoder().decode([ZabkaStoreDTO].self, from: data)
    else {
      return []
    }

    return stores.compactMap { store -> SearchCandidate? in
      let point = GeoPoint(latitude: store.lat, longitude: store.lon)
      let distance = Int(location.distance(to: point).rounded())
      guard distance <= searchRadiusMeters else { return nil }
      let place = Place(
        id: "zabka-official-\(store.storeID)",
        name: "\u{017B}abka",
        address: officialChainAddress(street: store.street, town: store.town),
        walkDistanceMeters: distance,
        walkEtaMinutes: distance > 0 ? NavigationScenarioCore.distanceBasedEtaMinutes(distanceMeters: distance) : 0,
        point: point,
        phone: nil,
        website: store.storeURL
      )
      return SearchCandidate(
        place: place,
        score: searchScore(for: place, query: query, currentLocation: location) + officialChainScore,
        distanceMeters: distance,
        importance: 1,
        isNearbyCandidate: true,
        kind: .shop
      )
    }
    .sorted {
      if $0.distanceMeters != $1.distanceMeters { return $0.distanceMeters < $1.distanceMeters }
      return $0.place.address < $1.place.address
    }
  }

  private func officialChainAddress(street: String, town: String) -> String {
    let cleanedStreet = titleCaseAddressPart(
      street.replacingOccurrences(
        of: "^ul\\.\\s*",
        with: "",
        options: [.regularExpression, .caseInsensitive]
      )
    )
    let cleanedTown = titleCaseAddressPart(town)
    return [cleanedStreet, cleanedTown]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
  }

  private func titleCaseAddressPart(_ value: String) -> String {
    value.split(whereSeparator: { $0.isWhitespace }).map { rawToken in
      let token = String(rawToken)
      let lowered = token.lowercased(with: Locale(identifier: "pl_PL"))
      if ["lok.", "nr", "nr.", "r.", "ul.", "al.", "pl."].contains(lowered) { return lowered }
      if token.rangeOfCharacter(from: .letters) == nil { return token }
      return lowered.prefix(1).uppercased(with: Locale(identifier: "pl_PL")) + String(lowered.dropFirst())
    }
    .joined(separator: " ")
  }

  private func fetchLocalPOICandidates(
    query: String,
    near location: GeoPoint,
    searchRadiusMeters: Int,
    intent: SearchIntent,
    resultLimit: Int
  ) async throws -> [SearchCandidate] {
    let urls = buildOverpassURLs(near: location, searchRadiusMeters: searchRadiusMeters, intent: intent)
    guard !urls.isEmpty else {
      return []
    }

    var candidatesByID: [String: SearchCandidate] = [:]
    var lastError: Error?
    let startedAt = Date()
    for url in urls {
      if Date().timeIntervalSince(startedAt) >= localPOITotalTimeout {
        break
      }
      do {
        var request = URLRequest(url: url)
        request.timeoutInterval = localPOIRequestTimeout
        request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")
        request.setValue(L10n.acceptLanguageTag, forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
          throw NavigationAPIError.badResponse
        }
        let decodedResponse = try JSONDecoder().decode(OverpassResponseDTO.self, from: data)
        for item in decodedResponse.elements {
          guard let candidate = localPOICandidate(
            item: item,
            query: query,
            location: location,
            searchRadiusMeters: searchRadiusMeters,
            intent: intent
          ) else {
            continue
          }
          if let existing = candidatesByID[candidate.place.id] {
            if isBetterSearchCandidate(candidate, than: existing) {
              candidatesByID[candidate.place.id] = candidate
            }
          } else {
            candidatesByID[candidate.place.id] = candidate
          }
        }
        if candidatesByID.count >= resultLimit {
          break
        }
      } catch {
        lastError = error
      }
    }
    if candidatesByID.isEmpty, let lastError {
      throw lastError
    }
    return Array(candidatesByID.values).sorted {
      if $0.score != $1.score { return $0.score > $1.score }
      let leftDistance = $0.distanceMeters > 0 ? $0.distanceMeters : Int.max
      let rightDistance = $1.distanceMeters > 0 ? $1.distanceMeters : Int.max
      if leftDistance != rightDistance { return leftDistance < rightDistance }
      return $0.importance > $1.importance
    }
  }

  private func localPOICandidate(
    item: OverpassElementDTO,
    query: String,
    location: GeoPoint,
    searchRadiusMeters: Int,
    intent: SearchIntent
  ) -> SearchCandidate? {
    guard let point = overpassPoint(for: item) else { return nil }
    let distance = Int(location.distance(to: point).rounded())
    guard distance <= searchRadiusMeters else { return nil }
    let tags = item.tags ?? [:]
    let kind = overpassKind(tags: tags)
    guard shouldKeepLocalPOI(tags: tags, kind: kind, intent: intent) else { return nil }
    let name = overpassName(tags: tags, kind: kind)
    let label = labelForKind(name, kind: kind)
    let place = Place(
      id: "overpass-\(item.type)-\(item.id)",
      name: label,
      address: normalizedSearchAddress(
        overpassAddress(tags: tags, fallback: coordinateAddress(point)),
        placeName: label,
        point: point
      ),
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
      isNearbyCandidate: true,
      kind: kind
    )
  }

  private func cachedPOICandidates(
    query: String,
    near location: GeoPoint,
    searchRadiusMeters: Int,
    intent: SearchIntent,
    resultLimit: Int
  ) async -> [SearchCandidate] {
    let records = await poiCacheStore.loadRecords()
    return records.compactMap { record -> SearchCandidate? in
      let distance = Int(location.distance(to: record.point).rounded())
      guard distance <= searchRadiusMeters else { return nil }
      let kind = kindFromCacheKind(record.kind)
      guard cachedPOIMatches(record: record, kind: kind, intent: intent) else { return nil }
      let place = Place(
        id: record.id,
        name: labelForKind(record.name, kind: kind),
        address: normalizedSearchAddress(
          record.address,
          placeName: labelForKind(record.name, kind: kind),
          point: record.point
        ),
        walkDistanceMeters: distance,
        walkEtaMinutes: distance > 0 ? NavigationScenarioCore.distanceBasedEtaMinutes(distanceMeters: distance) : 0,
        point: record.point,
        phone: record.phone,
        website: record.website
      )
      return SearchCandidate(
        place: place,
        score: searchScore(for: place, query: query, currentLocation: location) +
          SharedProductRules.Search.localPoiScore +
          categoryAffinityScore(intent: intent, kind: kind),
        distanceMeters: distance,
        importance: 0,
        isNearbyCandidate: true,
        kind: kind
      )
    }
    .sorted {
      if $0.score != $1.score { return $0.score > $1.score }
      let leftDistance = $0.distanceMeters > 0 ? $0.distanceMeters : Int.max
      let rightDistance = $1.distanceMeters > 0 ? $1.distanceMeters : Int.max
      if leftDistance != rightDistance { return leftDistance < rightDistance }
      return $0.importance > $1.importance
    }
    .prefix(resultLimit)
    .map { $0 }
  }

  private func fetchNearbyPOICacheRecords(
    near location: GeoPoint,
    radiusMeters: Int,
    fetchedAt: Date
  ) async throws -> [NearbyPOICacheRecord] {
    var recordsByID: [String: NearbyPOICacheRecord] = [:]
    var lastError: Error?
    for url in buildPOICacheRefreshURLs(near: location, radiusMeters: radiusMeters) {
      do {
        var request = URLRequest(url: url)
        request.timeoutInterval = poiCacheRefreshRequestTimeout
        request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")
        request.setValue(L10n.acceptLanguageTag, forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
          throw NavigationAPIError.badResponse
        }
        let decoded = try JSONDecoder().decode(OverpassResponseDTO.self, from: data)
        for item in decoded.elements {
          guard let record = nearbyPOICacheRecord(item: item, fetchedAt: fetchedAt) else { continue }
          recordsByID[record.id] = record
        }
      } catch {
        lastError = error
      }
    }
    if recordsByID.isEmpty, let lastError {
      throw lastError
    }
    return Array(recordsByID.values)
  }

  private func buildPOICacheRefreshURLs(near location: GeoPoint, radiusMeters: Int) -> [URL] {
    let lat = String(format: "%.6f", location.latitude)
    let lon = String(format: "%.6f", location.longitude)
    let nodeSelectors = poiCacheRefreshFilters().map { filter in
      "node(around:\(radiusMeters),\(lat),\(lon))\(filter);"
    }
    let areaSelectors = poiCacheRefreshFilters().flatMap { filter in
      [
        "way(around:\(radiusMeters),\(lat),\(lon))\(filter);",
        "relation(around:\(radiusMeters),\(lat),\(lon))\(filter);"
      ]
    }
    return [nodeSelectors, areaSelectors].flatMap { selectors -> [URL] in
      let query = buildPOICacheRefreshQuery(selectors: selectors)
      return [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
      "https://overpass.osm.ch/api/interpreter"
      ].compactMap { rawURL in
        guard var components = URLComponents(string: rawURL) else { return nil }
        components.queryItems = [.init(name: "data", value: query)]
        return components.url
      }
    }
  }

  private func poiCacheRefreshFilters() -> [String] {
    [
      "[\"shop\"]",
      "[\"amenity\"~\"^(parcel_locker|pharmacy|bank|atm|fuel|post_office|cafe|restaurant|fast_food|toilets)$\"]",
      "[\"railway\"~\"^(station|halt|tram_stop)$\"]",
      "[\"highway\"=\"bus_stop\"]",
      "[\"public_transport\"~\"^(platform|stop_position|station)$\"]"
    ]
  }

  private func buildPOICacheRefreshQuery(selectors: [String]) -> String {
    "[out:json][timeout:\(SharedProductRules.Search.overpassTimeoutSeconds)];(" +
      selectors.joined() +
      ");out center \(poiCacheRefreshLimit);"
  }

  private func nearbyPOICacheRecord(item: OverpassElementDTO, fetchedAt: Date) -> NearbyPOICacheRecord? {
    guard let point = overpassPoint(for: item) else { return nil }
    let tags = item.tags ?? [:]
    let kind = overpassKind(tags: tags)
    guard kind != .other else { return nil }
    let name = overpassName(tags: tags, kind: kind).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }
    let address = overpassAddress(tags: tags, fallback: coordinateAddress(point))
    var searchableParts = searchableNameParts(tags: tags)
    searchableParts.append(name)
    searchableParts.append(address)
    for key in ["shop", "amenity", "railway", "public_transport", "highway", "bus", "tram", "ref", "local_ref", "network"] {
      searchableParts.append(tags[key] ?? "")
    }
    let searchableText = normalizeForSearch(searchableParts.joined(separator: " "))
    return NearbyPOICacheRecord(
      id: "overpass-\(item.type)-\(item.id)",
      name: name,
      address: address,
      point: point,
      phone: tags["phone"] ?? tags["contact:phone"],
      website: tags["website"] ?? tags["contact:website"],
      kind: cacheKind(kind),
      searchableText: searchableText,
      fetchedAt: fetchedAt
    )
  }

  private func cachedPOIMatches(record: NearbyPOICacheRecord, kind: SearchPlaceKind, intent: SearchIntent) -> Bool {
    if intent.isCategoryOnly {
      if intent.wantsShop { return kind == .shop }
      if intent.wantsParcelLocker { return kind == .parcelLocker }
      if intent.wantsRailStation { return kind == .railStation }
      if intent.wantsTransitStop { return kind == .busStop || kind == .tramStop }
      return false
    }
    let terms = intent.nameSearchTerms.isEmpty ? intent.tokens : intent.nameSearchTerms
    guard !terms.isEmpty else { return true }
    return terms.allSatisfy { record.searchableText.contains($0) }
  }

  private func cacheKind(_ kind: SearchPlaceKind) -> String {
    switch kind {
    case .shop: return "shop"
    case .parcelLocker: return "parcel_locker"
    case .railStation: return "rail_station"
    case .busStop: return "bus_stop"
    case .tramStop: return "tram_stop"
    case .other: return "other"
    }
  }

  private func kindFromCacheKind(_ kind: String) -> SearchPlaceKind {
    switch kind {
    case "shop": return .shop
    case "parcel_locker": return .parcelLocker
    case "rail_station": return .railStation
    case "bus_stop": return .busStop
    case "tram_stop": return .tramStop
    default: return .other
    }
  }

  private func buildOverpassURLs(
    near location: GeoPoint,
    searchRadiusMeters: Int,
    intent: SearchIntent
  ) -> [URL] {
    var selectorGroups: [[String]] = []
    let lat = String(format: "%.6f", location.latitude)
    let lon = String(format: "%.6f", location.longitude)
    let nameRegex = overpassNameRegex(intent: intent)

    for radius in overpassSearchRadii(maxRadiusMeters: searchRadiusMeters) {
      var priorityNodeSelectors: [String] = []
      var priorityAreaSelectors: [String] = []
      var secondaryNodeSelectors: [String] = []
      var secondaryAreaSelectors: [String] = []
      if let nameRegex {
        priorityNodeSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"shop\"]",
          nameRegex: nameRegex,
          keys: ["name"],
          includeAreas: false
        ))
        priorityAreaSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"shop\"]",
          nameRegex: nameRegex,
          keys: ["name"],
          includeAreas: true
        ))
        secondaryNodeSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"shop\"]",
          nameRegex: nameRegex,
          keys: ["brand", "operator", "official_name", "alt_name"],
          includeAreas: false
        ))
        secondaryAreaSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"shop\"]",
          nameRegex: nameRegex,
          keys: ["brand", "operator", "official_name", "alt_name"],
          includeAreas: true
        ))
        secondaryNodeSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"amenity\"]",
          nameRegex: nameRegex,
          keys: ["name", "brand", "operator", "official_name", "alt_name"],
          includeAreas: false
        ))
        secondaryAreaSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"amenity\"]",
          nameRegex: nameRegex,
          keys: ["name", "brand", "operator", "official_name", "alt_name"],
          includeAreas: true
        ))
        secondaryNodeSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"tourism\"]",
          nameRegex: nameRegex,
          keys: ["name", "brand", "operator", "official_name", "alt_name"],
          includeAreas: false
        ))
        secondaryAreaSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"tourism\"]",
          nameRegex: nameRegex,
          keys: ["name", "brand", "operator", "official_name", "alt_name"],
          includeAreas: true
        ))
        secondaryNodeSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"leisure\"]",
          nameRegex: nameRegex,
          keys: ["name", "brand", "operator", "official_name", "alt_name"],
          includeAreas: false
        ))
        secondaryAreaSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"leisure\"]",
          nameRegex: nameRegex,
          keys: ["name", "brand", "operator", "official_name", "alt_name"],
          includeAreas: true
        ))
        secondaryNodeSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"railway\"]",
          nameRegex: nameRegex,
          keys: ["name", "brand", "operator", "official_name", "alt_name"],
          includeAreas: false
        ))
        secondaryAreaSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"railway\"]",
          nameRegex: nameRegex,
          keys: ["name", "brand", "operator", "official_name", "alt_name"],
          includeAreas: true
        ))
        secondaryNodeSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"public_transport\"]",
          nameRegex: nameRegex,
          keys: ["name", "brand", "operator", "official_name", "alt_name"],
          includeAreas: false
        ))
        secondaryAreaSelectors.append(contentsOf: overpassNameSelectors(
          radius: radius,
          lat: lat,
          lon: lon,
          baseFilter: "[\"public_transport\"]",
          nameRegex: nameRegex,
          keys: ["name", "brand", "operator", "official_name", "alt_name"],
          includeAreas: true
        ))
      }
      if intent.wantsShop && intent.isCategoryOnly {
        priorityNodeSelectors.append(contentsOf: overpassNodeSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"shop\"]"))
        priorityAreaSelectors.append(contentsOf: overpassAreaSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"shop\"]"))
      }
      if intent.wantsParcelLocker {
        priorityNodeSelectors.append(contentsOf: overpassNodeSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"amenity\"=\"parcel_locker\"]"))
        priorityAreaSelectors.append(contentsOf: overpassAreaSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"amenity\"=\"parcel_locker\"]"))
      }
      if intent.wantsRailStation {
        priorityNodeSelectors.append(contentsOf: overpassNodeSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"railway\"~\"^(station|halt)$\"]"))
        priorityNodeSelectors.append(contentsOf: overpassNodeSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"public_transport\"=\"station\"]"))
        priorityAreaSelectors.append(contentsOf: overpassAreaSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"railway\"~\"^(station|halt)$\"]"))
        priorityAreaSelectors.append(contentsOf: overpassAreaSelectors(radius: radius, lat: lat, lon: lon, filter: "[\"public_transport\"=\"station\"]"))
      }
      if intent.wantsTransitStop {
        priorityNodeSelectors.append(contentsOf: overpassTransitStopNodeSelectors(radius: radius, lat: lat, lon: lon))
        priorityAreaSelectors.append(contentsOf: overpassTransitStopAreaSelectors(radius: radius, lat: lat, lon: lon))
      }

      if !priorityNodeSelectors.isEmpty {
        selectorGroups.append(Array(Set(priorityNodeSelectors)).sorted())
      }
      if !priorityAreaSelectors.isEmpty {
        selectorGroups.append(Array(Set(priorityAreaSelectors)).sorted())
      }
      if !secondaryNodeSelectors.isEmpty {
        selectorGroups.append(Array(Set(secondaryNodeSelectors)).sorted())
      }
      if !secondaryAreaSelectors.isEmpty {
        selectorGroups.append(Array(Set(secondaryAreaSelectors)).sorted())
      }
    }
    guard !selectorGroups.isEmpty else { return [] }

    return selectorGroups.flatMap { selectors -> [URL] in
      let overpassQuery = buildOverpassQuery(selectors: selectors)
      let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
      "https://overpass.osm.ch/api/interpreter"
      ]
      return endpoints.compactMap { rawURL in
        guard var components = URLComponents(string: rawURL) else { return nil }
        components.queryItems = [.init(name: "data", value: overpassQuery)]
        return components.url
      }
    }
  }

  private func overpassSearchRadii(maxRadiusMeters: Int) -> [Int] {
    let maxRadius = max(maxRadiusMeters, 1)
    var radii: [Int] = []
    for radius in [500, 1_000, maxRadius] {
      let clamped = min(radius, maxRadius)
      if clamped > 0 && !radii.contains(clamped) {
        radii.append(clamped)
      }
    }
    return radii
  }

  private func overpassNodeSelectors(radius: Int, lat: String, lon: String, filter: String) -> [String] {
    let around = "(around:\(radius),\(lat),\(lon))"
    return [
      "node\(around)\(filter);"
    ]
  }

  private func overpassAreaSelectors(radius: Int, lat: String, lon: String, filter: String) -> [String] {
    let around = "(around:\(radius),\(lat),\(lon))"
    return [
      "way\(around)\(filter);",
      "relation\(around)\(filter);"
    ]
  }
  private func overpassTransitStopNodeSelectors(radius: Int, lat: String, lon: String) -> [String] {
    let filters = [
      "[\"highway\"=\"bus_stop\"]",
      "[\"railway\"=\"tram_stop\"]",
      "[\"public_transport\"=\"platform\"][\"bus\"=\"yes\"]",
      "[\"public_transport\"=\"platform\"][\"tram\"=\"yes\"]",
      "[\"public_transport\"=\"stop_position\"][\"bus\"=\"yes\"]",
      "[\"public_transport\"=\"stop_position\"][\"tram\"=\"yes\"]"
    ]
    return filters.flatMap { filter in
      overpassNodeSelectors(radius: radius, lat: lat, lon: lon, filter: filter)
    }
  }

  private func overpassTransitStopAreaSelectors(radius: Int, lat: String, lon: String) -> [String] {
    let filters = [
      "[\"public_transport\"=\"platform\"][\"bus\"=\"yes\"]",
      "[\"public_transport\"=\"platform\"][\"tram\"=\"yes\"]"
    ]
    return filters.flatMap { filter in
      overpassAreaSelectors(radius: radius, lat: lat, lon: lon, filter: filter)
    }
  }

  private func overpassNameSelectors(
    radius: Int,
    lat: String,
    lon: String,
    baseFilter: String,
    nameRegex: String,
    keys: [String],
    includeAreas: Bool
  ) -> [String] {
    keys.flatMap { key in
      let filter = "\(baseFilter)[\"\(key)\"~\"\(nameRegex)\",i]"
      if includeAreas {
        return overpassAreaSelectors(radius: radius, lat: lat, lon: lon, filter: filter)
      }
      return overpassNodeSelectors(radius: radius, lat: lat, lon: lon, filter: filter)
    }
  }

  private func buildOverpassQuery(selectors: [String]) -> String {
    "[out:json][timeout:\(SharedProductRules.Search.overpassTimeoutSeconds)];(" +
      selectors.joined() +
      ");out center \(SharedProductRules.Search.localPoiLimit);"
  }

  private func overpassNameRegex(intent: SearchIntent) -> String? {
    if intent.isCategoryOnly { return nil }
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
    let geometry = item.geometry?.map { GeoPoint(latitude: $0.lat, longitude: $0.lon) } ?? []
    return geometry.isEmpty ? nil : geometry[geometry.count / 2]
  }

  private func overpassName(tags: [String: String], kind: SearchPlaceKind) -> String {
    if let name = searchableNameParts(tags: tags).first(where: { !$0.isEmpty }) {
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
    let unit = tags["addr:unit"] ?? tags["addr:door"] ?? tags["addr:flats"] ?? ""
    let locality = tags["addr:city"] ?? tags["addr:town"] ?? tags["addr:village"] ?? tags["addr:suburb"] ?? ""
    let houseNumberWithUnit = !houseNumber.isEmpty && !unit.isEmpty ? "\(houseNumber)/\(unit)" : houseNumber
    let streetPart: String
    if !street.isEmpty && !houseNumberWithUnit.isEmpty {
      streetPart = "\(street) \(houseNumberWithUnit)"
    } else if !street.isEmpty {
      streetPart = street
    } else {
      streetPart = houseNumberWithUnit
    }
    let parts = [streetPart, locality].filter { !$0.isEmpty }
    return parts.isEmpty ? fallback : parts.joined(separator: ", ")
  }

  private func shouldKeepLocalPOI(tags: [String: String], kind: SearchPlaceKind, intent: SearchIntent) -> Bool {
    let normalizedName = normalizeForSearch(searchableNameParts(tags: tags).joined(separator: " "))
    if intent.wantsShop && kind == .shop {
      return SearchResultCore.localNameMatches(
        normalizedName: normalizedName,
        nameSearchTerms: intent.nameSearchTerms
      )
    }
    if intent.wantsParcelLocker && kind == .parcelLocker {
      return SearchResultCore.localNameMatches(
        normalizedName: normalizedName,
        nameSearchTerms: intent.nameSearchTerms
      )
    }
    if intent.wantsRailStation && !intent.wantsTransitStop {
      guard kind == .railStation else { return false }
      return SearchResultCore.localNameMatches(
        normalizedName: normalizedName,
        nameSearchTerms: intent.nameSearchTerms
      )
    }
    if intent.wantsTransitStop && (kind == .busStop || kind == .tramStop) {
      return SearchResultCore.localNameMatches(
        normalizedName: normalizedName,
        nameSearchTerms: intent.nameSearchTerms
      )
    }
    return SearchResultCore.localNameMatches(
      normalizedName: normalizedName,
      nameSearchTerms: intent.nameSearchTerms
    )
  }

  private func searchableNameParts(tags: [String: String]) -> [String] {
    ["name", "brand", "operator", "official_name", "alt_name", "short_name", "ref", "local_ref", "network"].map { key in
      tags[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
  }

  private func overpassKind(tags: [String: String]) -> SearchPlaceKind {
    let shop = tags["shop"] ?? ""
    let amenity = tags["amenity"] ?? ""
    let railway = tags["railway"] ?? ""
    let publicTransport = tags["public_transport"] ?? ""
    if !shop.isEmpty { return .shop }
    if amenity == "parcel_locker" { return .parcelLocker }
    if railway == "station" || railway == "halt" { return .railStation }
    if tags["station"] == "railway" || (tags["train"] == "yes" && publicTransport == "station") { return .railStation }
    if tags["highway"] == "bus_stop" || (tags["bus"] == "yes" && (publicTransport == "platform" || publicTransport == "stop_position")) { return .busStop }
    if railway == "tram_stop" || (tags["tram"] == "yes" && (publicTransport == "platform" || publicTransport == "stop_position")) { return .tramStop }
    return .other
  }

  private func fetchSearchCandidates(
    query: String,
    near location: GeoPoint?,
    nearbyOnly: Bool,
    searchRadiusKilometers: Int,
    intent: SearchIntent,
    resultLimit: Int
  ) async throws -> [SearchCandidate] {
    guard let url = buildSearchURL(
      query: query,
      near: location,
      nearbyOnly: nearbyOnly,
      searchRadiusKilometers: searchRadiusKilometers,
      resultLimit: resultLimit
    ) else {
      throw NavigationAPIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = searchRequestTimeout
    request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")
    request.setValue(L10n.acceptLanguageTag, forHTTPHeaderField: "Accept-Language")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw NavigationAPIError.badResponse
    }

    let decoded = try JSONDecoder().decode([SearchResultDTO].self, from: data)
    let maxDistanceMeters = location.map { _ in
      searchRadiusKilometers * 1_000
    }
    return decoded.compactMap { item -> SearchCandidate? in
      guard let latitude = Double(item.lat),
            let longitude = Double(item.lon),
            latitude.isFinite,
            longitude.isFinite,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude) else {
        return nil
      }
      let point = GeoPoint(latitude: latitude, longitude: longitude)
      let distance = location.map { Int($0.distance(to: point).rounded()) } ?? 0
      if let maxDistanceMeters, distance > maxDistanceMeters {
        return nil
      }
      let displayName = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
      let kind = nominatimKind(for: item)
      if intent.wantsRailStation &&
          !SearchResultCore.shouldKeepForRailQuery(
            kind: kind,
            wantsTransitStop: intent.wantsTransitStop
          ) {
        return nil
      }
      let label = candidateName(for: item, fallback: displayName, kind: kind)
      let rawAddress = formattedAddress(
        from: item.address,
        fallback: fallbackSearchAddress(point: point, displayName: displayName, placeName: label)
      )
      let place = Place(
        id: nominatimPlaceID(for: item, point: point),
        name: label,
        address: normalizedSearchAddress(
          removeDuplicatedAddressPrefix(rawAddress, placeName: label),
          placeName: label,
          point: point
        ),
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
        isNearbyCandidate: nearbyOnly,
        kind: kind
      )
    }
  }

  private func buildSearchURL(
    query: String,
    near location: GeoPoint?,
    nearbyOnly: Bool,
    searchRadiusKilometers: Int,
    resultLimit: Int
  ) -> URL? {
    guard var components = URLComponents(string: "https://nominatim.openstreetmap.org/search") else {
      return nil
    }
    let requestLimit = min(
      max(nearbyOnly ? SharedProductRules.Search.nearbyLimit : SharedProductRules.Search.globalLimit, resultLimit),
      SharedProductRules.Search.maximumResultLimit
    )
    var items: [URLQueryItem] = [
      .init(name: "format", value: "jsonv2"),
      .init(name: "limit", value: String(requestLimit)),
      .init(name: "addressdetails", value: "1"),
      .init(name: "namedetails", value: "1"),
      .init(name: "dedupe", value: "1"),
      .init(name: "q", value: query)
    ]
    if let location {
      let radiusKilometers = Double(searchRadiusKilometers)
      let viewBox = searchViewBox(around: location, radiusKilometers: radiusKilometers)
      items.append(.init(name: "viewbox", value: viewBox))
      items.append(.init(name: "bounded", value: "1"))
    }
    components.queryItems = items
    return components.url
  }

  private func candidateName(for item: SearchResultDTO, fallback: String, kind: SearchPlaceKind) -> String {
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

  private func putSearchCandidate(_ combined: inout [String: SearchCandidate], _ candidate: SearchCandidate) {
    if let existing = combined[candidate.place.id] {
      if isBetterSearchCandidate(candidate, than: existing) {
        combined[candidate.place.id] = candidate
      }
    } else {
      combined[candidate.place.id] = candidate
    }
  }

  private func nearbyTextSearchRadiiKilometers(
    normalizedSearchRadiusKilometers: Int,
    location: GeoPoint?,
    intent: SearchIntent
  ) -> [Int] {
    if location == nil || intent.isCategoryOnly {
      return [normalizedSearchRadiusKilometers]
    }
    return Array(Set([SharedProductRules.Search.minimumRadiusKm, normalizedSearchRadiusKilometers])).sorted()
  }

  private func deduplicatedSearchCandidates(_ candidates: [SearchCandidate]) -> [SearchCandidate] {
    var unique: [SearchCandidate] = []
    for candidate in candidates.sorted(by: compareSearchCandidates(_:_:)) {
      if let duplicateIndex = unique.firstIndex(where: { areDuplicateSearchPlaces(candidate.place, $0.place) }) {
        if isBetterSearchCandidate(candidate, than: unique[duplicateIndex]) {
          unique[duplicateIndex] = candidate
        }
      } else {
        unique.append(candidate)
      }
    }
    return unique
  }

  private func areDuplicateSearchPlaces(_ left: Place, _ right: Place) -> Bool {
    guard normalizeForSearch(left.name) == normalizeForSearch(right.name) else { return false }
    let distanceBetweenPlaces: Int
    if let leftPoint = left.point, let rightPoint = right.point {
      distanceBetweenPlaces = Int(leftPoint.distance(to: rightPoint).rounded())
    } else {
      distanceBetweenPlaces = abs(left.walkDistanceMeters - right.walkDistanceMeters)
    }
    guard distanceBetweenPlaces <= 35 else { return false }
    let leftAddress = normalizeForSearch(left.address)
    let rightAddress = normalizeForSearch(right.address)
    return leftAddress.isEmpty || rightAddress.isEmpty || leftAddress == rightAddress
  }

  private func enrichedSearchResultAddresses(_ candidates: [SearchCandidate]) async -> [Place] {
    let lookupIDs = Array(Set(candidates.compactMap { candidate -> String? in
      guard needsSearchAddressEnrichment(candidate.place) else { return nil }
      return osmLookupID(fromPlaceID: candidate.place.id)
    }))
    let lookedUpAddresses = lookupIDs.isEmpty ? [:] : ((try? await lookupAddressesByOSMIDs(lookupIDs)) ?? [:])

    let candidatesAfterLookup = candidates.map { candidate -> SearchCandidate in
      guard let lookupID = osmLookupID(fromPlaceID: candidate.place.id),
            let address = lookedUpAddresses[lookupID],
            !isUnhelpfulSearchAddress(address, placeName: candidate.place.name)
      else {
        return candidate
      }
      var enriched = candidate
      enriched.place.address = address
      return enriched
    }

    let placesNeedingNearbyAddress = candidatesAfterLookup.filter(needsNearbyAddressEnrichment(_:)).map(\.place)
    guard !placesNeedingNearbyAddress.isEmpty else {
      return candidatesAfterLookup.map { normalizedSearchPlace($0.place) }
    }
    let nearbyAddresses = await lookupNearbyAddressCandidates(for: placesNeedingNearbyAddress)
    guard !nearbyAddresses.isEmpty else {
      return candidatesAfterLookup.map { normalizedSearchPlace($0.place) }
    }

    return candidatesAfterLookup.map { candidate in
      guard let nearbyAddress = nearestNearbyAddress(for: candidate.place, in: nearbyAddresses) else {
        return normalizedSearchPlace(candidate.place)
      }
      var enriched = candidate.place
      enriched.address = normalizedSearchAddress(
        nearbyAddress.address,
        placeName: enriched.name,
        point: enriched.point ?? nearbyAddress.point
      )
      return normalizedSearchPlace(enriched)
    }
  }

  private func normalizedSearchPlace(_ place: Place) -> Place {
    guard let point = place.point else { return place }
    var normalized = place
    normalized.address = normalizedSearchAddress(
      place.address,
      placeName: place.name,
      point: point
    )
    return normalized
  }

  private func needsSearchAddressEnrichment(_ place: Place) -> Bool {
    isUnhelpfulSearchAddress(place.address, placeName: place.name) || !hasPreciseStreetNumber(place.address)
  }

  private func needsNearbyAddressEnrichment(_ candidate: SearchCandidate) -> Bool {
    candidate.kind == .shop && candidate.place.point != nil && needsSearchAddressEnrichment(candidate.place)
  }

  private func lookupNearbyAddressCandidates(for places: [Place]) async -> [NearbyAddressCandidate] {
    guard let query = nearbyAddressLookupQuery(for: places.compactMap(\.point)),
          let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    else {
      return []
    }
    let endpoints = [
      "https://overpass-api.de/api/interpreter?data=\(encodedQuery)",
      "https://overpass.kumi.systems/api/interpreter?data=\(encodedQuery)"
    ]
    for endpoint in endpoints {
      guard let url = URL(string: endpoint) else { continue }
      var request = URLRequest(url: url)
      request.timeoutInterval = addressLookupTimeout
      request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")
      request.setValue(L10n.acceptLanguageTag, forHTTPHeaderField: "Accept-Language")
      guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse,
            200..<300 ~= http.statusCode,
            let decoded = try? JSONDecoder().decode(OverpassResponseDTO.self, from: data)
      else {
        continue
      }
      let parsed = decoded.elements.compactMap(nearbyAddressCandidate(from:))
      if !parsed.isEmpty { return parsed }
    }
    return []
  }

  private func nearbyAddressLookupQuery(for points: [GeoPoint]) -> String? {
    guard !points.isEmpty else { return nil }
    var query = "[out:json][timeout:\(SharedProductRules.Search.overpassTimeoutSeconds)];("
    for point in points {
      let lat = formatCoordinate(point.latitude)
      let lon = formatCoordinate(point.longitude)
      query += "node(around:\(nearbyAddressLookupRadiusMeters),\(lat),\(lon))[\"addr:housenumber\"];"
      query += "way(around:\(nearbyAddressLookupRadiusMeters),\(lat),\(lon))[\"addr:housenumber\"];"
      query += "relation(around:\(nearbyAddressLookupRadiusMeters),\(lat),\(lon))[\"addr:housenumber\"];"
    }
    query += ");out center \(nearbyAddressLookupLimit);"
    return query
  }

  private func nearbyAddressCandidate(from item: OverpassElementDTO) -> NearbyAddressCandidate? {
    guard let tags = item.tags, let point = overpassPoint(for: item) else { return nil }
    let address = overpassAddress(tags: tags, fallback: "")
    guard !address.isEmpty, hasPreciseStreetNumber(address) else { return nil }
    return NearbyAddressCandidate(address: address, point: point)
  }

  private func nearestNearbyAddress(for place: Place, in addresses: [NearbyAddressCandidate]) -> NearbyAddressCandidate? {
    guard let point = place.point else { return nil }
    let nearest = addresses.min { left, right in
      point.distance(to: left.point) < point.distance(to: right.point)
    }
    guard let nearest, point.distance(to: nearest.point) <= Double(nearbyAddressLookupRadiusMeters) else {
      return nil
    }
    return nearest
  }

  private func lookupAddressesByOSMIDs(_ lookupIDs: [String]) async throws -> [String: String] {
    guard var components = URLComponents(string: "https://nominatim.openstreetmap.org/lookup") else {
      throw NavigationAPIError.invalidURL
    }
    components.queryItems = [
      .init(name: "format", value: "jsonv2"),
      .init(name: "addressdetails", value: "1"),
      .init(name: "namedetails", value: "1"),
      .init(name: "osm_ids", value: lookupIDs.joined(separator: ","))
    ]
    guard let url = components.url else {
      throw NavigationAPIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = addressLookupTimeout
    request.setValue("NaviLive/0.1 (iOS native client)", forHTTPHeaderField: "User-Agent")
    request.setValue(L10n.acceptLanguageTag, forHTTPHeaderField: "Accept-Language")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw NavigationAPIError.badResponse
    }
    let decoded = try JSONDecoder().decode([SearchResultDTO].self, from: data)
    var addresses: [String: String] = [:]
    for item in decoded {
      guard let lookupID = osmLookupID(fromNominatimResult: item) else { continue }
      let address = formattedAddress(from: item.address, fallback: item.displayName)
      guard !address.isEmpty else { continue }
      addresses[lookupID] = address
    }
    return addresses
  }

  private func osmLookupID(fromPlaceID placeID: String) -> String? {
    let normalizedID = placeID.replacingOccurrences(of: "_", with: "-")
    let parts = normalizedID.split(separator: "-")
    guard parts.count == 3,
          (parts[0] == "overpass" || parts[0] == "nominatim"),
          Int64(parts[2]) != nil else { return nil }
    let prefix: String
    switch parts[1] {
    case "node": prefix = "N"
    case "way": prefix = "W"
    case "relation": prefix = "R"
    default: return nil
    }
    return "\(prefix)\(parts[2])"
  }

  private func osmLookupID(fromNominatimResult item: SearchResultDTO) -> String? {
    guard let osmType = item.osmType?.lowercased(), let osmID = item.osmID else { return nil }
    let prefix: String
    switch osmType {
    case "node": prefix = "N"
    case "way": prefix = "W"
    case "relation": prefix = "R"
    default: return nil
    }
    return "\(prefix)\(osmID)"
  }

  private func isUnhelpfulSearchAddress(_ address: String, placeName: String) -> Bool {
    AddressFormattingCore.isUnhelpfulAddress(address, placeName: placeName)
  }

  private func hasPreciseStreetNumber(_ address: String) -> Bool {
    let streetLine = address.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
    guard !streetLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/"))
    return streetLine.components(separatedBy: separators).contains { part in
      let token = part.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()"))
      return token.range(of: SharedProductRules.Address.houseNumberPattern, options: .regularExpression) != nil
    }
  }

  private func searchIntent(for query: String) -> SearchIntent {
    let normalized = normalizeForSearch(query)
    let tokens = normalized.split(separator: " ").map(String.init)
    let categoryTerms = shopQueryTerms.union(parcelLockerQueryTerms).union(railStationQueryTerms).union(transitStopQueryTerms)
    return SearchIntent(
      normalizedQuery: normalized,
      tokens: tokens,
      nameSearchTerms: tokens.filter { !categoryTerms.contains($0) },
      wantsShop: tokens.contains(where: { shopQueryTerms.contains($0) }),
      wantsParcelLocker: tokens.contains(where: { parcelLockerQueryTerms.contains($0) }),
      wantsRailStation: tokens.contains(where: { railStationQueryTerms.contains($0) }),
      wantsTransitStop: tokens.contains(where: { transitStopQueryTerms.contains($0) })
    )
  }

  private func isZabkaQuery(_ intent: SearchIntent) -> Bool {
    intent.tokens.contains { token in
      token == "zabka" || token == "zabki" || token == "zabke"
    }
  }

  private func shopCategoryExpansionQueries() -> [String] {
    ["zabka", "biedronka", "lidl", "supermarket", "market"]
  }

  private func parcelLockerCategoryExpansionQueries() -> [String] {
    ["inpost", "orlen paczka", "dpd pickup"]
  }

  private func transitStopCategoryExpansionQueries() -> [String] {
    ["przystanek", "przystanek autobusowy", "przystanek tramwajowy", "bus stop", "tram stop"]
  }

  private func nominatimKind(for item: SearchResultDTO) -> SearchPlaceKind {
    SearchResultCore.kindFromNominatim(
      category: item.category ?? "",
      type: item.type ?? ""
    )
  }

  private func categoryAffinityScore(intent: SearchIntent, kind: SearchPlaceKind) -> Int {
    var score = 0
    if intent.wantsShop && kind == .shop {
      score += SharedProductRules.Search.categoryMatchScore
    }
    if intent.wantsParcelLocker && kind == .parcelLocker {
      score += SharedProductRules.Search.categoryMatchScore
    }
    if intent.wantsTransitStop && (kind == .busStop || kind == .tramStop) {
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

  private func labelForKind(_ name: String, kind: SearchPlaceKind) -> String {
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

  private func coordinateAddress(_ point: GeoPoint) -> String {
    let label = L10n.text("place.label.coordinates", table: .home)
    return "\(label): \(formatCoordinate(point.latitude)), \(formatCoordinate(point.longitude))"
  }

  private func fallbackSearchAddress(point: GeoPoint, displayName: String, placeName: String) -> String {
    let parts = displayName
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let normalizedName = normalizeForSearch(placeName)
    let usefulParts = parts.enumerated().compactMap { index, part -> String? in
      if index == 0 && normalizeForSearch(part) == normalizedName { return nil }
      return part
    }
    return usefulParts.isEmpty ? coordinateAddress(point) : usefulParts.joined(separator: ", ")
  }

  private func normalizedSearchAddress(_ address: String, placeName: String, point: GeoPoint) -> String {
    AddressFormattingCore.ensureAddress(
      address,
      placeName: placeName,
      fallback: coordinateAddress(point)
    )
  }

  private func nominatimPlaceID(for item: SearchResultDTO, point: GeoPoint) -> String {
    if let osmType = item.osmType?.lowercased(),
       ["node", "way", "relation"].contains(osmType),
       let osmID = item.osmID,
       osmID > 0 {
      return "nominatim-\(osmType)-\(osmID)"
    }
    if let placeID = item.placeID {
      return "nominatim-place-\(placeID)"
    }
    return "nominatim-coordinate-\(formatCoordinate(point.latitude))-\(formatCoordinate(point.longitude))"
  }

  private func removeDuplicatedAddressPrefix(_ address: String, placeName: String) -> String {
    let parts = address
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard parts.count > 1 else { return address }
    let firstPart = normalizeForSearch(parts[0])
    let normalizedName = normalizeForSearch(placeName)
    let nameTail = placeName.split(separator: ":", maxSplits: 1).last.map(String.init) ?? placeName
    let normalizedNameTail = normalizeForSearch(nameTail)
    if firstPart == normalizedName || firstPart == normalizedNameTail {
      return parts.dropFirst().joined(separator: ", ")
    }
    return address
  }

  private func isHouseNumberSearchToken(_ token: String) -> Bool {
    token.contains { $0.isNumber }
  }

  private func matchesAddressQueryToken(_ token: String, normalizedText: String, normalizedTokens: [String]) -> Bool {
    if isHouseNumberSearchToken(token) {
      return normalizedTokens.contains(token)
    }
    return normalizedText.contains(token)
  }

  private func searchScore(for place: Place, query: String, currentLocation: GeoPoint?) -> Int {
    let normalizedQuery = normalizeForSearch(query)
    guard !normalizedQuery.isEmpty else { return 0 }

    let normalizedName = normalizeForSearch(place.name)
    let normalizedAddress = normalizeForSearch(place.address)
    let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
    let nameTokens = normalizedName.split(separator: " ").map(String.init)
    let combinedAddressText = [normalizedName, normalizedAddress]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    let combinedAddressTokens = combinedAddressText.split(separator: " ").map(String.init)
    let exactAddressQuery = queryTokens.contains(where: isHouseNumberSearchToken)

    var score = 0
    if exactAddressQuery {
      if queryTokens.allSatisfy({ matchesAddressQueryToken($0, normalizedText: combinedAddressText, normalizedTokens: combinedAddressTokens) }) {
        score += SharedProductRules.Search.exactNameScore + SharedProductRules.Search.nearbyBonus
      } else {
        score -= SharedProductRules.Search.nearbyBonus
      }
    }
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
    SearchResultCore.isBetterDuplicate(
      SearchRankingValues(
        score: candidate.score,
        distanceMeters: candidate.distanceMeters,
        importance: candidate.importance,
        isNearbyCandidate: candidate.isNearbyCandidate
      ),
      SearchRankingValues(
        score: existing.score,
        distanceMeters: existing.distanceMeters,
        importance: existing.importance,
        isNearbyCandidate: existing.isNearbyCandidate
      )
    )
  }

  private func compareSearchCandidates(_ left: SearchCandidate, _ right: SearchCandidate) -> Bool {
    SearchResultCore.compareForDisplay(
      SearchRankingValues(
        score: left.score,
        distanceMeters: left.distanceMeters,
        importance: left.importance,
        isNearbyCandidate: left.isNearbyCandidate
      ),
      SearchRankingValues(
        score: right.score,
        distanceMeters: right.distanceMeters,
        importance: right.importance,
        isNearbyCandidate: right.isNearbyCandidate
      )
    )
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
private extension RouteStep {
  var isTurnLikeManeuver: Bool {
    RouteStepSimplificationCore.isTurnLikeManeuver(self)
  }
}
