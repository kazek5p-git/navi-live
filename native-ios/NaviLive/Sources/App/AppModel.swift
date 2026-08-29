import Combine
import CoreLocation
import Foundation
import Network

@MainActor
final class AppModel: ObservableObject {
  enum LaunchState {
    case bootstrapping
    case onboarding
    case permissions
    case ready
  }

  @Published var launchState: LaunchState = .bootstrapping
  @Published var path: [AppRoute] = []
  @Published var searchQuery = ""
  @Published var searchResults: [Place] = []
  @Published var hasPerformedSearch = false
  @Published var currentLocationDescription = ""
  @Published var currentPositionStatusMessage = ""
  @Published var currentPositionStatusIsWarning = false
  @Published var statusMessage = ""
  @Published var settings: AppSettings
  @Published var favorites: [Place]
  @Published var lastRoutePlaceID: String?
  @Published var selectedRouteSummary: RouteSummary?
  @Published var headingState: HeadingState
  @Published var activeNavigationState: ActiveNavigationState
  @Published var isSearching = false
  @Published var isRouting = false
  @Published var hasCompletedOnboarding: Bool
  @Published var isLiveTracking = false
  @Published var nearbyPOICacheState = NearbyPOICacheState()

  let locationService: LocationService

  private let settingsStore: SettingsStore
  private let navigationAPI: NavigationAPIClient
  private let announcer: VoiceOverAnnouncer
  private let liveNavigationEngine = LiveNavigationEngine()
  private let routeIssueLogger = RouteIssueDiagnosticLogger()
  private let headphoneRemoteControlService = HeadphoneRemoteControlService()

  private var knownPlaces: [String: Place] = [:]
  private var cancellables: Set<AnyCancellable> = []
  private let pathMonitor = NWPathMonitor()
  private let pathMonitorQueue = DispatchQueue(label: "NaviLive.NearbyPOICache.Network")
  private var currentNetworkPath: NWPath?
  private var nearbyPOICacheRefreshTask: Task<Void, Never>?
  private struct QueuedSpeech {
    let message: String
    let delayAfterSound: TimeInterval
    let isNavigation: Bool
    let generation: UInt64
  }

  private var speechQueue: [QueuedSpeech] = []
  private var speechQueueTask: Task<Void, Never>?
  private var speechQueueGeneration: UInt64 = 0
  private var lastNearbyPOICacheAttemptAt: Date?
  private var lastReverseGeocodedPoint: GeoPoint?
  private var lastReverseGeocodedAt: Date?
  private var isNavigationLive = false
  private var lastCountdownAnnouncementStepIndex = -1
  private var lastCountdownMilestoneMeters: Int?
  private var lastCountdownCadenceMode: AnnouncementCadenceMode?
  private var lastImmediateAnnouncementStepIndex = -1
  private var currentHeadingDegrees: Double? = nil
  private var routeInitialBearingDegrees: Double? = nil
  private static let nearbyPOICacheFreshInterval: TimeInterval = 24 * 60 * 60
  private static let nearbyPOICacheMoveThresholdMeters: Double = 800
  private static let nearbyPOICacheAttemptThrottle: TimeInterval = 2 * 60
  private static let reverseGeocodeMoveThresholdMeters: Double = 35
  private static let reverseGeocodeThrottle: TimeInterval = 25
  private static let speechAfterSoundDelay: TimeInterval = 0.5

  convenience init() {
    self.init(
      settingsStore: SettingsStore(),
      locationService: LocationService(),
      navigationAPI: NavigationAPIClient(),
      announcer: VoiceOverAnnouncer()
    )
  }

  init(
    settingsStore: SettingsStore,
    locationService: LocationService,
    navigationAPI: NavigationAPIClient,
    announcer: VoiceOverAnnouncer
  ) {
    self.settingsStore = settingsStore
    self.locationService = locationService
    self.navigationAPI = navigationAPI
    self.announcer = announcer

    let snapshot = settingsStore.snapshot
    settings = snapshot.settings
    L10n.selectedLanguageCode = snapshot.settings.languageCode
    favorites = snapshot.favorites
    lastRoutePlaceID = snapshot.lastRoutePlaceID
    headingState = HeadingState(
      instruction: L10n.text("heading.instruction.rotate_right", table: .navigation),
      isAligned: false,
      arrowRotationDegrees: 22
    )
    activeNavigationState = ActiveNavigationState()
    hasCompletedOnboarding = snapshot.hasCompletedOnboarding
    favorites.forEach { knownPlaces[$0.id] = $0 }

    startNetworkMonitor()
    bindLocation()
    Task { await refreshNearbyPOICacheState() }
  }

  var appVersionLabel: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
  }

  var appBuildLabel: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
  }

  var appLocale: Locale {
    L10n.currentLocale
  }

  var hasLocationPermission: Bool {
    locationService.hasPermission
  }

  func bootstrap() async {
    refreshLaunchState()
    if hasLocationPermission {
      locationService.startUpdates()
      await loadCurrentAddress(force: true)
    } else {
      currentLocationDescription = L10n.text("home.location.unavailable", table: .home)
    }
    if statusMessage.isEmpty {
      statusMessage = L10n.text("home.status.ready", table: .home)
    }
  }

  func refreshLaunchState() {
    if !hasCompletedOnboarding && settings.showTutorialOnLaunch {
      launchState = .onboarding
    } else if !hasLocationPermission {
      launchState = .permissions
    } else {
      launchState = .ready
    }
  }

  func completeOnboarding() {
    hasCompletedOnboarding = true
    settingsStore.setOnboardingCompleted(true)
    refreshLaunchState()
  }

  func requestLocationPermission() {
    locationService.requestPermission()
  }

  func toggleLiveTracking() {
    guard hasLocationPermission else {
      requestLocationPermission()
      return
    }

    if locationService.isUpdating {
      locationService.stopUpdates()
      isLiveTracking = false
      playLiveTrackingToggleSound(starting: false)
      let stoppedMessage = L10n.text("home.location.tracking_stopped", table: .home)
      currentLocationDescription = stoppedMessage
      statusMessage = L10n.text("home.status.live_tracking_stopped", table: .home)
    } else {
      locationService.startUpdates()
      isLiveTracking = true
      playLiveTrackingToggleSound(starting: true)
      currentLocationDescription = L10n.text("home.location.waiting", table: .home)
      statusMessage = L10n.text("home.status.live_tracking_started", table: .home)
      Task { await loadCurrentAddress() }
    }
  }

  func continueWithoutPermission() {
    launchState = .ready
    statusMessage = L10n.text("home.status.location_later", table: .home)
  }

  func place(for id: String) -> Place? {
    knownPlaces[id]
  }

  func isFavorite(_ place: Place) -> Bool {
    favorites.contains(where: { $0.id == place.id })
  }

  func toggleFavorite(_ place: Place) {
    if let index = favorites.firstIndex(where: { $0.id == place.id }) {
      favorites.remove(at: index)
      statusMessage = L10n.text("favorites.status.removed", table: .home)
    } else {
      favorites.append(place)
      statusMessage = L10n.text("favorites.status.saved", table: .home)
    }
    knownPlaces[place.id] = place
    settingsStore.setFavorites(favorites)
  }

  func saveCurrentLocationAsFavorite(named customName: String) async {
    let savedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !savedName.isEmpty else {
      let message = L10n.text("current.position.name_required", table: .home)
      statusMessage = message
      currentPositionStatusMessage = message
      currentPositionStatusIsWarning = true
      announceWarning(message: message)
      return
    }
    guard let fix = locationService.latestFix else {
      let message = L10n.text("current.position.save_unavailable", table: .home)
      statusMessage = message
      currentPositionStatusMessage = message
      currentPositionStatusIsWarning = true
      announceWarning(message: message)
      return
    }
    let address = await currentAddressForFavorite(fix: fix)
    if let existingIndex = favorites.firstIndex(where: { isSameSavedCurrentPosition($0, savedName: savedName, address: address, point: fix.point) }) {
      favorites[existingIndex].address = address
      if favorites[existingIndex].point == nil {
        favorites[existingIndex].point = fix.point
      }
      favorites[existingIndex].savedAt = Date()
      favorites[existingIndex].savedAccuracyMeters = fix.accuracyMeters
      knownPlaces[favorites[existingIndex].id] = favorites[existingIndex]
      settingsStore.setFavorites(favorites)
      let message = L10n.text("current.position.already_saved_named", table: .home, savedName)
      statusMessage = message
      currentPositionStatusMessage = message
      currentPositionStatusIsWarning = false
      announceSuccess(message: message)
      return
    }
    let place = Place(
      id: "current-\(Int(Date().timeIntervalSince1970 * 1000))",
      name: savedName,
      address: address,
      walkDistanceMeters: 0,
      walkEtaMinutes: 0,
      point: fix.point,
      savedAt: Date(),
      savedAccuracyMeters: fix.accuracyMeters
    )
    favorites.append(place)
    knownPlaces[place.id] = place
    settingsStore.setFavorites(favorites)
    let message = L10n.text("current.position.saved_named", table: .home, savedName)
    statusMessage = message
    currentPositionStatusMessage = message
    currentPositionStatusIsWarning = false
    announceSuccess(message: message)
  }

  private func isSameSavedCurrentPosition(
    _ favorite: Place,
    savedName: String,
    address: String,
    point: GeoPoint
  ) -> Bool {
    guard favorite.name == savedName else { return false }
    if let favoritePoint = favorite.point, favoritePoint.distance(to: point) <= 25 {
      return true
    }
    return !address.isEmpty && favorite.address == address
  }

  private func currentAddressForFavorite(fix: LocationFix) async -> String {
    do {
      let address = try await navigationAPI.reverseGeocode(point: fix.point).trimmingCharacters(in: .whitespacesAndNewlines)
      if !address.isEmpty {
        return address
      }
    } catch {
      // Fall back to the last visible address when live reverse geocoding is unavailable.
    }
    let visibleAddress = currentLocationDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    if !visibleAddress.isEmpty,
       visibleAddress != L10n.text("home.location.waiting", table: .home),
       visibleAddress != L10n.text("home.location.fallback", table: .home) {
      return visibleAddress
    }
    return L10n.text("current.position.unknown", table: .home)
  }

  func loadCurrentAddress(force: Bool = false) async {
    guard locationService.isUpdating else {
      currentLocationDescription = L10n.text("home.location.tracking_stopped", table: .home)
      return
    }

    guard let fix = locationService.latestFix else {
      currentLocationDescription = L10n.text("home.location.waiting", table: .home)
      return
    }

    let now = Date()
    let movedEnough = lastReverseGeocodedPoint.map {
      $0.distance(to: fix.point) >= Self.reverseGeocodeMoveThresholdMeters
    } ?? true
    let staleEnough = lastReverseGeocodedAt.map {
      now.timeIntervalSince($0) >= Self.reverseGeocodeThrottle
    } ?? true
    guard force || movedEnough || staleEnough else { return }
    lastReverseGeocodedPoint = fix.point
    lastReverseGeocodedAt = now

    do {
      let address = try await navigationAPI.reverseGeocode(point: fix.point)
      guard locationService.isUpdating else {
        currentLocationDescription = L10n.text("home.location.tracking_stopped", table: .home)
        return
      }
      guard locationService.latestFix == fix else { return }
      currentLocationDescription = address
    } catch {
      guard locationService.isUpdating else {
        currentLocationDescription = L10n.text("home.location.tracking_stopped", table: .home)
        return
      }
      guard locationService.latestFix == fix else { return }
      currentLocationDescription = L10n.text("home.location.fallback", table: .home)
    }
  }

  func performSearch() async {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      searchResults = []
      hasPerformedSearch = false
      return
    }

    hasPerformedSearch = true
    isSearching = true
    defer { isSearching = false }

    do {
      let results = try await navigationAPI.searchPlaces(
        query: query,
        near: locationService.latestFix?.point,
        searchRadiusKilometers: settings.searchRadiusKilometers,
        resultLimit: settings.searchResultLimit
      )
      searchResults = results
      results.forEach { knownPlaces[$0.id] = $0 }
      statusMessage = results.isEmpty
        ? L10n.text("search.status.no_results", table: .home)
        : L10n.text("search.status.results", table: .home, results.count)
    } catch {
      searchResults = []
      statusMessage = L10n.text("search.status.error", table: .home)
    }
  }

  func prepareRoute(for placeID: String) async {
    guard let place = place(for: placeID), let start = locationService.latestFix?.point else {
      statusMessage = L10n.text("route.status.location_required", table: .navigation)
      return
    }

    resetSpeechQueue(stopCurrentSpeech: true)
    isRouting = true
    defer { isRouting = false }

    do {
      let summary = try await navigationAPI.buildWalkingRoute(
        from: start,
        to: place,
        includePedestrianCrossings: settings.pedestrianCrossingAlerts,
        includeJunctionAlerts: settings.junctionAlerts
      )
      selectedRouteSummary = summary
      lastRoutePlaceID = place.id
      settingsStore.setLastRoutePlaceID(place.id)
      routeInitialBearingDegrees = RouteProjectionCore.initialBearingDegrees(pathPoints: summary.pathPoints)
      headingState = headingStateFor(currentHeadingDegrees)
      activeNavigationState = liveNavigationEngine.loadRoute(
        destination: place,
        summary: summary,
        fix: locationService.latestFix
      )
      isNavigationLive = false
      resetCountdownAnnouncementState()
      lastImmediateAnnouncementStepIndex = -1
      statusMessage = L10n.text("route.status.ready", table: .navigation)
      announceSuccess(message: L10n.text("route.status.ready", table: .navigation))
    } catch {
      selectedRouteSummary = nil
      activeNavigationState = ActiveNavigationState()
      statusMessage = L10n.text("route.status.error", table: .navigation)
      announceWarning(message: L10n.text("route.status.error", table: .navigation))
    }
  }

  func updateHeading(_ degrees: Double?) {
    currentHeadingDegrees = degrees?.isFinite == true ? degrees : nil
    headingState = headingStateFor(currentHeadingDegrees)
  }

  func cycleHeadingInstruction() {
    updateHeading(currentHeadingDegrees)
  }

  func markHeadingAligned() {
    guard headingState.isAligned else { return }
    statusMessage = L10n.text("heading.status.aligned", table: .navigation)
    announceSuccess(message: L10n.text("heading.instruction.aligned", table: .navigation))
  }

  private func headingStateFor(_ headingDegrees: Double?) -> HeadingState {
    guard let headingDegrees,
          let routeBearing = routeInitialBearingDegrees,
          let alignment = NavigationScenarioCore.headingAlignment(
            currentHeadingDegrees: headingDegrees,
            routeBearingDegrees: routeBearing
          ) else {
      return HeadingState(
        instruction: L10n.text("heading.instruction.rotate_right", table: .navigation),
        isAligned: false,
        arrowRotationDegrees: 22
      )
    }

    let instruction: String
    if alignment.isAligned {
      instruction = L10n.text("heading.instruction.aligned", table: .navigation)
    } else if alignment.signedDeltaDegrees >= 0 {
      instruction = L10n.text("heading.instruction.rotate_right", table: .navigation)
    } else {
      instruction = L10n.text("heading.instruction.rotate_left", table: .navigation)
    }
    return HeadingState(
      instruction: instruction,
      isAligned: alignment.isAligned,
      arrowRotationDegrees: alignment.signedDeltaDegrees
    )
  }

  func beginActiveNavigation() {
    guard liveNavigationEngine.currentDestination != nil else { return }
    locationService.prepareForActiveNavigation()
    isNavigationLive = true
    updateHeadphoneRemoteControl()
    resetCountdownAnnouncementState()
    lastImmediateAnnouncementStepIndex = -1
    activeNavigationState.isPaused = false
    statusMessage = L10n.text("active.status.started", table: .navigation)
    announceNavigationPrompt(
      activeNavigationState.currentInstruction.isEmpty
        ? L10n.text("route.follow_default", table: .navigation)
        : activeNavigationState.currentInstruction,
      cue: .success
    )
    if let latestFix = locationService.latestFix {
      syncActiveNavigationWithLocation(latestFix)
    }
  }

  func repeatCurrentInstruction() {
    let message = navigationRepeatMessage()
    statusMessage = L10n.text("active.status.repeating", table: .navigation)
    announceNavigationPrompt(message)
  }

  /// Tworzy lokalną odpowiedź na podstawie aktualnego stanu prowadzenia.
  func answerRouteAssistant(for query: String) -> String {
    let steps = selectedRouteSummary?.steps ?? []
    guard !steps.isEmpty || liveNavigationEngine.currentDestination != nil else {
      let answer = L10n.text("assistant.no_active_route", table: .navigation)
      announceRouteAssistantAnswer(answer)
      return answer
    }

    guard !steps.isEmpty else {
      let answer = L10n.text("assistant.no_route_steps", table: .navigation)
      announceRouteAssistantAnswer(answer)
      return answer
    }

    let match = RouteAssistantCore.match(for: query)
    guard match.isConfident else {
      let answer = L10n.text("assistant.help", table: .navigation)
      announceRouteAssistantAnswer(answer)
      return answer
    }

    let currentIndex = min(max(activeNavigationState.currentStepIndex, 0), steps.count - 1)
    let hasLiveLocation = hasFreshLiveLocation()
    if RouteAssistantCore.requiresFreshLocation(for: match.intent) && !hasLiveLocation {
      let answer = L10n.text("assistant.gps.unavailable", table: .navigation)
      announceRouteAssistantAnswer(answer)
      return answer
    }
    let answer: String
    switch match.intent {
    case .currentInstruction:
      if !hasLiveLocation {
        answer = L10n.text("assistant.gps.unavailable", table: .navigation)
      } else {
        let instruction = steps[currentIndex].instruction.isEmpty
          ? L10n.text("route.follow_default", table: .navigation)
          : steps[currentIndex].instruction
        answer = L10n.text(
          "assistant.answer.current",
          table: .navigation,
          instruction,
          AppFormatters.distance(activeNavigationState.distanceToNextMeters)
        )
      }
    case .repeatInstruction:
      answer = navigationRepeatMessage()
    case .currentLocation:
      if !hasLiveLocation {
        answer = L10n.text("assistant.gps.unavailable", table: .navigation)
      } else {
        let location = currentLocationDescription
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let address = location.isEmpty
          ? L10n.text("current.position.unknown", table: .home)
          : location
        let title = L10n.text("current.title", table: .home)
        let accuracy = AppFormatters.accuracy(locationService.latestFix?.accuracyMeters)
        answer = "\(title): \(address). \(accuracy)"
      }
    case .nextInstruction:
      guard let nextIndex = RouteAssistantCore.nextStepIndex(currentStepIndex: currentIndex, steps: steps) else {
        answer = L10n.text("assistant.no_next_step", table: .navigation)
        break
      }
      let nextStep = steps[nextIndex]
      let distance = nextIndex == currentIndex + 1
        ? activeNavigationState.distanceToNextMeters
        : nextStep.distanceMeters
      answer = L10n.text(
        "assistant.answer.next",
        table: .navigation,
        nextStep.instruction,
        AppFormatters.distance(distance)
      )
    case .routeOverview:
      let overview = RouteAssistantCore.overviewStepIndices(
        currentStepIndex: currentIndex,
        steps: steps
      ).enumerated().map { position, index in
        let step = steps[index]
        return L10n.text(
          "assistant.answer.overview.item",
          table: .navigation,
          position + 1,
          step.instruction,
          AppFormatters.distance(step.distanceMeters)
        )
      }.joined(separator: " ")
      answer = L10n.text("assistant.answer.overview", table: .navigation, overview)
    case .progress:
      answer = L10n.text(
        "assistant.answer.progress",
        table: .navigation,
        AppFormatters.distance(activeNavigationState.remainingDistanceMeters),
        activeNavigationState.progressLabel
      )
    case .routeStatus:
      if !hasLiveLocation {
        answer = L10n.text("assistant.gps.unavailable", table: .navigation)
      } else if activeNavigationState.isRecalculating {
        let accuracy = AppFormatters.accuracy(locationService.latestFix?.accuracyMeters)
        answer = L10n.text("assistant.status.recalculating", table: .navigation, accuracy)
      } else if activeNavigationState.isOffRoute {
        let accuracy = AppFormatters.accuracy(locationService.latestFix?.accuracyMeters)
        answer = L10n.text("assistant.status.off_route", table: .navigation, accuracy)
      } else if activeNavigationState.isPaused {
        let accuracy = AppFormatters.accuracy(locationService.latestFix?.accuracyMeters)
        answer = L10n.text("assistant.status.paused", table: .navigation, accuracy)
      } else {
        let accuracy = AppFormatters.accuracy(locationService.latestFix?.accuracyMeters)
        answer = L10n.text("assistant.status.on_route", table: .navigation, accuracy)
      }
    case .routeQuality:
      answer = routeQualityAssistantAnswer(
        hasLiveLocation: hasLiveLocation,
        steps: steps,
        pathPoints: selectedRouteSummary?.pathPoints ?? []
      )
    case .pedestrianCrossing:
      guard let crossingIndex = RouteAssistantCore.nextPedestrianCrossingIndex(
        currentStepIndex: currentIndex,
        steps: steps
      ) else {
        answer = L10n.text("assistant.no_crossing", table: .navigation)
        break
      }
      let crossing = steps[crossingIndex]
      let distance = crossingIndex == currentIndex + 1
        ? activeNavigationState.distanceToNextMeters
        : crossing.distanceMeters
      answer = L10n.text(
        "assistant.answer.crossing",
        table: .navigation,
        crossing.instruction,
        AppFormatters.distance(distance)
      )
    case .help:
      answer = L10n.text("assistant.help", table: .navigation)
    }

    announceRouteAssistantAnswer(answer)
    return answer
  }

  private func announceRouteAssistantAnswer(_ answer: String) {
    statusMessage = answer
    resetSpeechQueue(stopCurrentSpeech: true)
    announcer.announceNavigation(answer, settings: settings)
  }

  private func routeQualityAssistantAnswer(
    hasLiveLocation: Bool,
    steps: [RouteStep],
    pathPoints: [GeoPoint]
  ) -> String {
    let report = RouteQualityAnalyzer.analyze(steps: steps, pathPoints: pathPoints)
    let routeAnswer: String
    if report.recommendation != .followCurrentGuidance {
      let details = report.issues.compactMap { issue -> String? in
        switch issue {
        case .unnamedTurn:
          return L10n.text(
            "assistant.quality.issue.unnamed_turns",
            table: .navigation,
            report.unnamedTurnCount
          )
        case .repeatedInstruction:
          return L10n.text(
            "assistant.quality.issue.repeated_instruction",
            table: .navigation,
            report.repeatedInstructionCount
          )
        case .missingManeuverData:
          return L10n.text(
            "assistant.quality.issue.missing_maneuver",
            table: .navigation,
            report.missingManeuverDataCount
          )
        case .closeOppositeManeuvers:
          return L10n.text(
            "assistant.quality.issue.close_opposite",
            table: .navigation,
            report.closeOppositeManeuverCount
          )
        case .maneuverGeometryMismatch:
          return L10n.text("assistant.quality.issue.geometry", table: .navigation)
        case .incompleteGeometry:
          return L10n.text("assistant.quality.issue.geometry", table: .navigation)
        }
      }.joined(separator: " ")
      routeAnswer = [
        L10n.text("assistant.quality.route.review", table: .navigation),
        details
      ].filter { !$0.isEmpty }.joined(separator: " ")
    } else {
      routeAnswer = L10n.text("assistant.quality.route.consistent", table: .navigation)
    }
    let accuracy = AppFormatters.accuracy(locationService.latestFix?.accuracyMeters)
    let gpsAnswer: String
    if !hasLiveLocation {
      gpsAnswer = L10n.text("assistant.quality.unavailable", table: .navigation)
    } else if activeNavigationState.isRecalculating {
      gpsAnswer = L10n.text("assistant.quality.recalculating", table: .navigation, accuracy)
    } else if activeNavigationState.isOffRoute {
      gpsAnswer = L10n.text("assistant.quality.off_route", table: .navigation, accuracy)
    } else if activeNavigationState.isPaused {
      gpsAnswer = L10n.text("assistant.quality.paused", table: .navigation)
    } else {
      switch RouteAssistantCore.gpsQuality(accuracyMeters: locationService.latestFix?.accuracyMeters) {
      case .reliable:
        gpsAnswer = L10n.text("assistant.quality.reliable", table: .navigation, accuracy)
      case .limited:
        gpsAnswer = L10n.text("assistant.quality.limited", table: .navigation, accuracy)
      case .weak:
        gpsAnswer = L10n.text("assistant.quality.weak", table: .navigation, accuracy)
      case .unavailable:
        gpsAnswer = L10n.text("assistant.quality.unavailable", table: .navigation)
      }
    }
    return "\(gpsAnswer) \(routeAnswer)"
  }

  private func hasFreshLiveLocation() -> Bool {
    guard locationService.isUpdating, let fix = locationService.latestFix else {
      return false
    }
    return NavigationScenarioCore.isFreshLocation(
      timestamp: fix.timestamp,
      now: Date()
    )
  }

  private func navigationRepeatMessage() -> String {
    let steps = selectedRouteSummary?.steps ?? []
    let fallback = activeNavigationState.currentInstruction
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !steps.isEmpty else {
      return fallback.isEmpty ? L10n.text("route.follow_default", table: .navigation) : fallback
    }

    let currentStepIndex = min(max(activeNavigationState.currentStepIndex, 0), steps.count - 1)
    let firstInstruction = steps[currentStepIndex].instruction
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedFirstInstruction = firstInstruction.isEmpty ? fallback : firstInstruction
    let firstMessage = L10n.text("active.spoken.now", table: .navigation, normalizedFirstInstruction)

    let followingStepIndex = currentStepIndex + 1
    guard steps.indices.contains(followingStepIndex) else {
      return firstMessage
    }
    let followingStep = steps[followingStepIndex]
    let followingInstruction = followingStep.instruction
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !followingInstruction.isEmpty else {
      return firstMessage
    }
    let followingMessage = L10n.text(
      "active.spoken.repeat.following_distance",
      table: .navigation,
      max(0, followingStep.distanceMeters),
      followingInstruction
    )
    return L10n.text("active.spoken.repeat.plan", table: .navigation, firstMessage, followingMessage)
  }

  private func formattedNavigationInstruction(distanceMeters: Int, instruction: String) -> String {
    let normalizedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedInstruction.isEmpty else {
      return L10n.text("route.follow_default", table: .navigation)
    }
    if distanceMeters <= 0 {
      return L10n.text("active.spoken.now", table: .navigation, normalizedInstruction)
    }
    return L10n.text("active.spoken.upcoming.distance", table: .navigation, distanceMeters, normalizedInstruction)
  }

  func reportRouteProblem() {
    let steps = selectedRouteSummary?.steps ?? []
    let currentStepIndex = activeNavigationState.currentStepIndex
    let destination = liveNavigationEngine.currentDestination
    let fix = locationService.latestFix
    let snapshot = RouteIssueDiagnosticSnapshot(
      createdAt: Date(),
      appVersion: appVersionLabel,
      appBuild: appBuildLabel,
      destinationID: destination?.id,
      destinationName: destination?.name,
      currentStepIndex: currentStepIndex,
      stepCount: steps.count,
      currentInstruction: activeNavigationState.currentInstruction,
      nextInstruction: activeNavigationState.nextInstruction,
      distanceToNextMeters: activeNavigationState.distanceToNextMeters,
      remainingDistanceMeters: activeNavigationState.remainingDistanceMeters,
      isPaused: activeNavigationState.isPaused,
      isOffRoute: activeNavigationState.isOffRoute,
      isRecalculating: activeNavigationState.isRecalculating,
      offRouteDistanceMeters: activeNavigationState.offRouteDistanceMeters,
      accuracyMeters: fix?.accuracyMeters,
      currentStep: diagnosticStepSnapshot(steps.indices.contains(currentStepIndex) ? steps[currentStepIndex] : nil),
      nextStep: diagnosticStepSnapshot(steps.indices.contains(currentStepIndex + 1) ? steps[currentStepIndex + 1] : nil)
    )

    Task {
      do {
        try await routeIssueLogger.append(snapshot)
        let message = L10n.text("active.status.problem_report_saved", table: .navigation)
        statusMessage = message
        announcer.announce(message, settings: settings)
      } catch {
        let message = L10n.text("active.status.problem_report_failed", table: .navigation)
        statusMessage = message
        announcer.announce(message, settings: settings)
      }
    }
  }

  func announcePreviousInstruction() {
    announceRouteInstruction(
      offset: -1,
      spokenKey: "active.spoken.previous_instruction",
      unavailableKey: "active.status.no_previous_instruction"
    )
  }

  func announceNextInstruction() {
    announceRouteInstruction(
      offset: 1,
      spokenKey: "active.spoken.next_instruction",
      unavailableKey: "active.status.no_next_instruction"
    )
  }

  func togglePauseNavigation() {
    activeNavigationState.isPaused.toggle()
    if activeNavigationState.isPaused {
      statusMessage = L10n.text("active.status.paused", table: .navigation)
      announceNavigationPrompt(L10n.text("active.status.paused", table: .navigation), warning: true)
    } else {
      statusMessage = L10n.text("active.status.resumed", table: .navigation)
      announceNavigationPrompt(L10n.text("active.status.resumed", table: .navigation), cue: .success)
      if let latestFix = locationService.latestFix {
        syncActiveNavigationWithLocation(latestFix)
      }
    }
  }

  func recalculateRoute() {
    Task {
      await recalculateRoute(autoTriggered: false)
    }
  }

  private func diagnosticStepSnapshot(_ step: RouteStep?) -> RouteIssueStepSnapshot? {
    guard let step else { return nil }
    return RouteIssueStepSnapshot(
      instruction: step.instruction,
      distanceMeters: step.distanceMeters,
      kind: step.kind.rawValue,
      maneuverType: step.maneuverType,
      maneuverModifier: step.maneuverModifier,
      roadName: step.roadName
    )
  }

  private func announceRouteInstruction(offset: Int, spokenKey: String, unavailableKey: String) {
    let steps = selectedRouteSummary?.steps ?? []
    let targetIndex = activeNavigationState.currentStepIndex + offset
    guard steps.indices.contains(targetIndex) else {
      let message = L10n.text(unavailableKey, table: .navigation)
      statusMessage = message
      announceNavigationPrompt(message, warning: true)
      return
    }

    let instruction = steps[targetIndex].instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !instruction.isEmpty else { return }
    let message = L10n.text(spokenKey, table: .navigation, instruction)
    statusMessage = message
    announceNavigationPrompt(message)
  }

  func stopNavigation() {
    isNavigationLive = false
    updateHeadphoneRemoteControl()
    resetCountdownAnnouncementState()
    lastImmediateAnnouncementStepIndex = -1
    locationService.finishActiveNavigation()
    resetSpeechQueue(stopCurrentSpeech: true)
    liveNavigationEngine.reset()
    routeInitialBearingDegrees = nil
    headingState = headingStateFor(currentHeadingDegrees)
    activeNavigationState = ActiveNavigationState()
    selectedRouteSummary = nil
    statusMessage = L10n.text("active.status.stopped", table: .navigation)
  }

  func markArrived() {
    guard let destination = liveNavigationEngine.currentDestination else { return }
    isNavigationLive = false
    updateHeadphoneRemoteControl()
    resetCountdownAnnouncementState()
    lastImmediateAnnouncementStepIndex = -1
    locationService.finishActiveNavigation()
    resetSpeechQueue(stopCurrentSpeech: true)
    routeInitialBearingDegrees = nil
    activeNavigationState.isPaused = false
    activeNavigationState.isOffRoute = false
    activeNavigationState.isRecalculating = false
    statusMessage = L10n.text("active.status.arrived", table: .navigation)
    announceNavigationPrompt(L10n.text("active.spoken.arrived", table: .navigation), cue: .arrival)
    if path.last != .arrival(placeID: destination.id) {
      path.append(.arrival(placeID: destination.id))
    }
  }

  func openSearch() {
    path.append(.search)
  }

  func openPlaceDetails(_ placeID: String) {
    path.append(.placeDetails(placeID: placeID))
  }

  func openRouteSummary(_ placeID: String) {
    path.append(.routeSummary(placeID: placeID))
  }

  func openHeadingAlign(_ placeID: String) {
    path.append(.headingAlign(placeID: placeID))
  }

  func openActiveNavigation(_ placeID: String) {
    path.append(.activeNavigation(placeID: placeID))
  }

  func openRouteAssistant(_ placeID: String) {
    path.append(.routeAssistant(placeID: placeID))
  }

  func openCurrentPosition() {
    currentPositionStatusMessage = ""
    currentPositionStatusIsWarning = false
    path.append(.currentPosition)
  }

  func openFavorites() {
    path.append(.favorites)
  }

  func openSettings() {
    path.append(.settings)
  }

  func openHelpPrivacy() {
    path.append(.helpPrivacy)
  }

  func updateLanguageCode(_ code: String) {
    let normalized = AppLanguage.normalize(code)
    guard normalized != settings.languageCode else { return }
    settings.languageCode = normalized
    L10n.selectedLanguageCode = normalized
    settingsStore.updateSettings { $0.languageCode = normalized }
    headingState = headingStateFor(currentHeadingDegrees)
    statusMessage = L10n.text("settings.language.updated", table: .settings)
  }

  func updateShowTutorialOnLaunch(_ enabled: Bool) {
    settings.showTutorialOnLaunch = enabled
    settingsStore.updateSettings { $0.showTutorialOnLaunch = enabled }
  }

  func updateVibrationEnabled(_ enabled: Bool) {
    settings.vibrationEnabled = enabled
    settingsStore.updateSettings { $0.vibrationEnabled = enabled }
  }

  func updateShakeGestureEnabled(_ enabled: Bool) {
    settings.shakeGestureEnabled = enabled
    settingsStore.updateSettings { $0.shakeGestureEnabled = enabled }
  }

  func updateShakeStrength(_ strength: ShakeStrength) {
    settings.shakeStrength = strength
    settingsStore.updateSettings { $0.shakeStrength = strength }
  }

  func updateHeadphoneButtonRepeatEnabled(_ enabled: Bool) {
    settings.headphoneButtonRepeatEnabled = enabled
    settingsStore.updateSettings { $0.headphoneButtonRepeatEnabled = enabled }
    updateHeadphoneRemoteControl()
  }

  func onShakeGestureDetected() {
    guard settings.shakeGestureEnabled else { return }
    guard selectedRouteSummary != nil || !activeNavigationState.currentInstruction.isEmpty else { return }
    repeatCurrentInstruction()
  }

  func updateSoundCuesEnabled(_ enabled: Bool) {
    settings.soundCuesEnabled = enabled
    settingsStore.updateSettings { $0.soundCuesEnabled = enabled }
  }

  func updateSoundCueVolume(_ value: Double) {
    let normalized = min(max(value, 0.0), 1.0)
    settings.soundCueVolume = normalized
    settingsStore.updateSettings { $0.soundCueVolume = normalized }
  }

  func updateSoundCueTheme(_ theme: SoundCueTheme) {
    settings.soundCueTheme = theme
    settingsStore.updateSettings { $0.soundCueTheme = theme }
  }

  func previewSoundCue(_ cue: NavigationSoundCue) {
    announcer.playSoundCue(cue, volume: settings.soundCueVolume, theme: settings.soundCueTheme)
  }

  func previewSpeechSettings() {
    announcer.previewSynthesizer(
      L10n.text("settings.speech.preview.sample", table: .settings),
      settings: settings
    )
  }

  func updateAutoRecalculate(_ enabled: Bool) {
    settings.autoRecalculate = enabled
    settingsStore.updateSettings { $0.autoRecalculate = enabled }
  }

  func updateJunctionAlerts(_ enabled: Bool) {
    settings.junctionAlerts = enabled
    settingsStore.updateSettings { $0.junctionAlerts = enabled }
  }

  func updatePedestrianCrossingAlerts(_ enabled: Bool) {
    settings.pedestrianCrossingAlerts = enabled
    settingsStore.updateSettings { $0.pedestrianCrossingAlerts = enabled }
  }

  func updateTurnByTurnAnnouncements(_ enabled: Bool) {
    settings.turnByTurnAnnouncements = enabled
    settingsStore.updateSettings { $0.turnByTurnAnnouncements = enabled }
  }

  func updateAnnouncementCadenceMode(_ mode: AnnouncementCadenceMode) {
    settings.announcementCadenceMode = mode
    settingsStore.updateSettings { $0.announcementCadenceMode = mode }
    resetCountdownAnnouncementState()
  }

  func updateSearchRadiusKilometers(_ value: Int) {
    let normalized = min(
      max(value, SharedProductRules.Search.minimumRadiusKm),
      SharedProductRules.Search.maximumRadiusKm
    )
    settings.searchRadiusKilometers = normalized
    settingsStore.updateSettings { $0.searchRadiusKilometers = normalized }
  }

  func updateSearchResultLimit(_ value: Int) {
    let normalized = min(
      max(value, SharedProductRules.Search.minimumResultLimit),
      SharedProductRules.Search.maximumResultLimit
    )
    settings.searchResultLimit = normalized
    settingsStore.updateSettings { $0.searchResultLimit = normalized }
  }

  func updateNearbyPOICacheMode(_ mode: NearbyPOICacheMode) {
    settings.nearbyPOICacheMode = mode
    settingsStore.updateSettings { $0.nearbyPOICacheMode = mode }
    if mode != .disabled {
      refreshNearbyPOICacheNow()
    }
  }

  func updateNearbyPOICacheRadiusKilometers(_ value: Int) {
    let normalized = min(max(value, SharedProductRules.Search.minimumRadiusKm), 5)
    settings.nearbyPOICacheRadiusKilometers = normalized
    settingsStore.updateSettings { $0.nearbyPOICacheRadiusKilometers = normalized }
    refreshNearbyPOICacheNow()
  }

  func refreshNearbyPOICacheNow() {
    guard let fix = locationService.latestFix else {
      statusMessage = L10n.text("settings.local_search.status.waiting_location", table: .settings)
      return
    }
    maybeRefreshNearbyPOICache(fix: fix, force: true)
  }

  func clearNearbyPOICache() {
    Task {
      nearbyPOICacheState = await navigationAPI.clearNearbyPOICache()
      statusMessage = L10n.text("settings.local_search.status.cleared", table: .settings)
    }
  }

  func updateSpeechMode(_ mode: GuidanceSpeechMode) {
    let normalizedMode: GuidanceSpeechMode = mode == .automatic ? .voiceOver : mode
    settings.speechMode = normalizedMode
    settingsStore.updateSettings { $0.speechMode = normalizedMode }
    announcer.announce(L10n.text("settings.speech_mode.updated", table: .settings), settings: settings)
  }

  func updateSpeechVoiceIdentifier(_ identifier: String?) {
    let normalized = identifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : identifier
    settings.selectedSpeechVoiceIdentifier = normalized
    settingsStore.updateSettings { $0.selectedSpeechVoiceIdentifier = normalized }
  }

  func updateSpeechRate(_ value: Double) {
    settings.speechRate = value
    settingsStore.updateSettings { $0.speechRate = value }
  }

  func updateSpeechVolume(_ value: Double) {
    settings.speechVolume = value
    settingsStore.updateSettings { $0.speechVolume = value }
  }

  private func bindLocation() {
    locationService.$authorizationStatus
      .sink { [weak self] _ in
        guard let self else { return }
        self.refreshLaunchState()
        if self.hasLocationPermission {
          self.locationService.startUpdates()
        }
      }
      .store(in: &cancellables)

    locationService.$latestFix
      .compactMap { $0 }
      .sink { [weak self] fix in
        guard let self else { return }
        if self.locationService.isUpdating {
          Task { await self.loadCurrentAddress() }
          self.maybeRefreshNearbyPOICache(fix: fix)
        }
        self.syncActiveNavigationWithLocation(fix)
      }
      .store(in: &cancellables)

    locationService.$isUpdating
      .removeDuplicates()
      .sink { [weak self] isUpdating in
        guard let self else { return }
        self.isLiveTracking = isUpdating
        if !isUpdating {
          self.lastReverseGeocodedPoint = nil
          self.lastReverseGeocodedAt = nil
          self.currentLocationDescription = L10n.text("home.location.tracking_stopped", table: .home)
        }
      }
      .store(in: &cancellables)

    locationService.$headingDegrees
      .sink { [weak self] heading in
        self?.updateHeading(heading)
      }
      .store(in: &cancellables)
  }

  private func startNetworkMonitor() {
    pathMonitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        self?.currentNetworkPath = path
      }
    }
    pathMonitor.start(queue: pathMonitorQueue)
  }

  private func refreshNearbyPOICacheState() async {
    nearbyPOICacheState = await navigationAPI.nearbyPOICacheState()
  }

  private func maybeRefreshNearbyPOICache(fix: LocationFix, force: Bool = false) {
    guard canRefreshNearbyPOICache(mode: settings.nearbyPOICacheMode) else {
      if force && settings.nearbyPOICacheMode == .wifiOnly {
        statusMessage = L10n.text("settings.local_search.status.waiting_wifi", table: .settings)
      }
      return
    }
    if nearbyPOICacheRefreshTask != nil { return }
    let now = Date()
    if !force,
       let lastAttempt = lastNearbyPOICacheAttemptAt,
       now.timeIntervalSince(lastAttempt) < Self.nearbyPOICacheAttemptThrottle {
      return
    }
    if !force && !shouldRefreshNearbyPOICache(fix: fix, now: now) {
      return
    }
    lastNearbyPOICacheAttemptAt = now
    nearbyPOICacheState.isRefreshing = true
    statusMessage = L10n.text("settings.local_search.status.refreshing", table: .settings)

    nearbyPOICacheRefreshTask = Task { [weak self] in
      guard let self else { return }
      do {
        let refreshed = try await navigationAPI.refreshNearbyPOICache(
          near: fix.point,
          radiusKilometers: settings.nearbyPOICacheRadiusKilometers
        )
        nearbyPOICacheState = NearbyPOICacheState(
          cachedPlaceCount: refreshed.cachedPlaceCount,
          lastUpdatedAt: refreshed.lastUpdatedAt,
          lastCenter: refreshed.lastCenter
        )
        statusMessage = L10n.text("settings.local_search.status.updated", table: .settings, refreshed.cachedPlaceCount)
      } catch {
        nearbyPOICacheState.isRefreshing = false
        if force {
          statusMessage = L10n.text("settings.local_search.status.failed", table: .settings)
        }
      }
      nearbyPOICacheRefreshTask = nil
    }
  }

  private func shouldRefreshNearbyPOICache(fix: LocationFix, now: Date) -> Bool {
    guard let lastUpdatedAt = nearbyPOICacheState.lastUpdatedAt else { return true }
    if now.timeIntervalSince(lastUpdatedAt) > Self.nearbyPOICacheFreshInterval { return true }
    guard let lastCenter = nearbyPOICacheState.lastCenter else { return true }
    return fix.point.distance(to: lastCenter) >= Self.nearbyPOICacheMoveThresholdMeters
  }

  private func canRefreshNearbyPOICache(mode: NearbyPOICacheMode) -> Bool {
    switch mode {
    case .enabled:
      return true
    case .disabled:
      return false
    case .wifiOnly:
      guard let currentNetworkPath else { return false }
      return currentNetworkPath.status == .satisfied && !currentNetworkPath.isExpensive
    }
  }

  private func updateHeadphoneRemoteControl() {
    headphoneRemoteControlService.update(
      isEnabled: settings.headphoneButtonRepeatEnabled,
      isNavigationActive: isNavigationLive
    ) { [weak self] in
      Task { @MainActor in
        self?.repeatCurrentInstruction()
      }
    }
  }

  private func syncActiveNavigationWithLocation(_ fix: LocationFix) {
    guard isNavigationLive, !activeNavigationState.isPaused else { return }
    guard let update = liveNavigationEngine.update(
      fix: fix,
      previous: activeNavigationState,
      autoRecalculateEnabled: settings.autoRecalculate
    ) else {
      return
    }

    activeNavigationState = update.state
    if update.stepChanged && settings.turnByTurnAnnouncements {
      if update.currentStepIndex != lastImmediateAnnouncementStepIndex {
        announceNavigationPrompt(
          L10n.text("active.spoken.now", table: .navigation, update.state.currentInstruction),
          cue: soundCue(for: update.currentStepKind, defaultCue: .turnNow)
        )
        lastImmediateAnnouncementStepIndex = update.currentStepIndex
      }
    } else if settings.turnByTurnAnnouncements {
      let announcedCountdown = maybeAnnounceCountdownInstruction(update: update)
      if !announcedCountdown {
        _ = maybeAnnounceImmediateInstruction(update: update, fix: fix)
      }
    }
    if update.offRouteTriggered {
      statusMessage = L10n.text("active.status.off_route", table: .navigation)
      announceNavigationPrompt(L10n.text("active.spoken.off_route", table: .navigation), warning: true)
    } else if update.state.isOffRoute {
      statusMessage = L10n.text("active.status.off_route", table: .navigation)
    } else if update.state.isRecalculating {
      statusMessage = L10n.text("active.status.recalculating", table: .navigation)
    } else if update.stepChanged {
      statusMessage = update.state.currentInstruction
    }

    if update.shouldAutoRecalculate {
      Task { await recalculateRoute(autoTriggered: true) }
    } else if update.hasArrived {
      markArrived()
    }
  }

  private func recalculateRoute(autoTriggered: Bool) async {
    guard let placeID = lastRoutePlaceID,
          let place = place(for: placeID),
          let start = locationService.latestFix?.point else {
      statusMessage = L10n.text("route.status.cannot_recalculate", table: .navigation)
      return
    }

    resetSpeechQueue(stopCurrentSpeech: true)
    isRouting = true
    activeNavigationState.isRecalculating = true
    statusMessage = L10n.text("active.status.recalculating", table: .navigation)
    defer {
      isRouting = false
    }

    do {
      let summary = try await navigationAPI.buildWalkingRoute(
        from: start,
        to: place,
        includePedestrianCrossings: settings.pedestrianCrossingAlerts,
        includeJunctionAlerts: settings.junctionAlerts
      )
      selectedRouteSummary = summary
      activeNavigationState = liveNavigationEngine.loadRoute(
        destination: place,
        summary: summary,
        fix: locationService.latestFix
      )
      resetCountdownAnnouncementState()
      lastImmediateAnnouncementStepIndex = -1
      activeNavigationState.isRecalculating = false
      if autoTriggered {
        statusMessage = L10n.text("active.status.auto_recalculated", table: .navigation)
      } else {
        statusMessage = L10n.text("active.status.recalculated", table: .navigation)
      }
      announceNavigationPrompt(L10n.text("active.spoken.recalculated", table: .navigation), cue: .success)
    } catch {
      activeNavigationState.isRecalculating = false
      statusMessage = L10n.text("route.status.error", table: .navigation)
      announceWarning(message: L10n.text("route.status.error", table: .navigation))
    }
  }

  private func maybeAnnounceCountdownInstruction(update: LiveNavigationUpdate) -> Bool {
    guard !update.stepChanged else { return false }
    guard !update.state.isOffRoute, !update.state.isRecalculating, !update.hasArrived else { return false }
    let cadenceMode = settings.announcementCadenceMode
    let upcomingStepIndex = update.currentStepIndex + 1
    guard let upcomingInstruction = update.upcomingInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
          !upcomingInstruction.isEmpty else {
      return false
    }
    let milestoneValue: Int?
    switch cadenceMode {
    case .distance:
      milestoneValue = NavigationScenarioCore.countdownMilestoneMeters(
        distanceToNext: update.state.distanceToNextMeters
      )
    case .time:
      milestoneValue = NavigationScenarioCore.countdownMilestoneSeconds(
        secondsToNext: NavigationScenarioCore.estimatedSecondsToManeuver(
          distanceToNextMeters: update.state.distanceToNextMeters
        )
      )
    }
    guard let milestoneValue else {
      return false
    }
    if update.upcomingStepKind == .pedestrianCrossing {
      guard cadenceMode == .distance, milestoneValue <= 20 else { return false }
    }

    if upcomingStepIndex != lastCountdownAnnouncementStepIndex || cadenceMode != lastCountdownCadenceMode {
      lastCountdownAnnouncementStepIndex = upcomingStepIndex
      lastCountdownMilestoneMeters = nil
      lastCountdownCadenceMode = cadenceMode
    }
    if let lastMilestone = lastCountdownMilestoneMeters, milestoneValue >= lastMilestone {
      return false
    }

    lastCountdownMilestoneMeters = milestoneValue
    let message: String
    switch cadenceMode {
    case .distance:
      message = L10n.text(
        "active.spoken.upcoming.distance",
        table: .navigation,
        milestoneValue,
        upcomingInstruction
      )
    case .time:
      message = L10n.text(
        "active.spoken.upcoming.time",
        table: .navigation,
        milestoneValue,
        upcomingInstruction
      )
    }
    announceNavigationPrompt(
      message,
      cue: soundCue(for: update.upcomingStepKind, defaultCue: .countdown)
    )
    return true
  }

  private func maybeAnnounceImmediateInstruction(update: LiveNavigationUpdate, fix: LocationFix) -> Bool {
    guard !update.stepChanged else { return false }
    guard !update.state.isOffRoute, !update.state.isRecalculating, !update.hasArrived else { return false }
    let upcomingStepIndex = update.currentStepIndex + 1
    guard upcomingStepIndex != lastImmediateAnnouncementStepIndex else { return false }
    guard let upcomingInstruction = update.upcomingInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
          !upcomingInstruction.isEmpty else {
      return false
    }
    let threshold = NavigationScenarioCore.immediateAnnouncementThresholdMeters(
      accuracyMeters: fix.accuracyMeters
    )
    guard update.state.distanceToNextMeters > 0, update.state.distanceToNextMeters <= threshold else {
      return false
    }

    lastImmediateAnnouncementStepIndex = upcomingStepIndex
    announceNavigationPrompt(
      L10n.text("active.spoken.now", table: .navigation, upcomingInstruction),
      cue: soundCue(for: update.upcomingStepKind, defaultCue: .turnNow)
    )
    return true
  }

  private func announceNavigationPrompt(
    _ message: String,
    cue: NavigationSoundCue? = nil,
    warning: Bool = false
  ) {
    let effectiveCue = cue ?? (warning ? .warning : nil)
    let speechDelay = effectiveCue.map { playSoundCueIfEnabled($0) } ?? 0.0
    announceNavigationSpeech(message, delayAfterSound: speechDelay)
    if settings.vibrationEnabled {
      if warning {
        announcer.hapticWarning()
      } else {
        announcer.hapticSuccess()
      }
    }
  }

  private func announceSuccess(message: String) {
    let speechDelay = playSoundCueIfEnabled(.success)
    announceSpeech(message, delayAfterSound: speechDelay)
    hapticSuccessIfEnabled()
  }

  private func announceWarning(message: String) {
    let speechDelay = playSoundCueIfEnabled(.warning)
    announceSpeech(message, delayAfterSound: speechDelay)
    if settings.vibrationEnabled {
      announcer.hapticWarning()
    }
  }

  private func announceNavigationSpeech(_ message: String, delayAfterSound: TimeInterval) {
    enqueueSpeech(message, delayAfterSound: delayAfterSound, isNavigation: true)
  }

  private func announceSpeech(_ message: String, delayAfterSound: TimeInterval) {
    enqueueSpeech(message, delayAfterSound: delayAfterSound, isNavigation: false)
  }

  private func enqueueSpeech(
    _ message: String,
    delayAfterSound: TimeInterval,
    isNavigation: Bool
  ) {
    guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    speechQueue.append(
      QueuedSpeech(
        message: message,
        delayAfterSound: max(delayAfterSound, 0),
        isNavigation: isNavigation,
        generation: speechQueueGeneration
      )
    )
    startSpeechQueueIfNeeded()
  }

  private func startSpeechQueueIfNeeded() {
    guard speechQueueTask == nil else { return }
    speechQueueTask = Task { [weak self] in
      await self?.runSpeechQueue()
    }
  }

  private func runSpeechQueue() async {
    while !speechQueue.isEmpty {
      let queued = speechQueue.removeFirst()
      if queued.delayAfterSound > 0 {
        do {
          try await Task.sleep(nanoseconds: UInt64(queued.delayAfterSound * 1_000_000_000))
        } catch {
          return
        }
      }
      guard !Task.isCancelled, queued.generation == speechQueueGeneration else { continue }
      if queued.isNavigation {
        announcer.announceNavigation(queued.message, settings: settings)
      } else {
        announcer.announce(queued.message, settings: settings)
      }
    }
    speechQueueTask = nil
  }

  private func resetSpeechQueue(stopCurrentSpeech: Bool) {
    speechQueueGeneration &+= 1
    speechQueue.removeAll()
    speechQueueTask?.cancel()
    speechQueueTask = nil
    if stopCurrentSpeech {
      announcer.stopSpeech()
    }
  }

  private func hapticSuccessIfEnabled() {
    if settings.vibrationEnabled {
      announcer.hapticSuccess()
    }
  }

  private func playLiveTrackingToggleSound(starting: Bool) {
    _ = playSoundCueIfEnabled(starting ? .success : .warning)
  }

  private func playSoundCueIfEnabled(_ cue: NavigationSoundCue) -> TimeInterval {
    guard settings.soundCuesEnabled else { return 0.0 }
    let queuedStartDelay = announcer.playSoundCue(cue, volume: settings.soundCueVolume, theme: settings.soundCueTheme)
    return queuedStartDelay + Self.speechAfterSoundDelay
  }

  private func soundCue(for stepKind: RouteStepKind?, defaultCue: NavigationSoundCue) -> NavigationSoundCue {
    switch stepKind {
    case .pedestrianCrossing:
      return .pedestrianCrossing
    case .instruction, .none:
      return defaultCue
    }
  }

  private func resetCountdownAnnouncementState() {
    lastCountdownAnnouncementStepIndex = -1
    lastCountdownMilestoneMeters = nil
    lastCountdownCadenceMode = nil
  }
}
