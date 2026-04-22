import Combine
import CoreLocation
import Foundation

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
  @Published var currentLocationDescription = ""
  @Published var statusMessage = ""
  @Published var settings: AppSettings
  @Published var favorites: [Place]
  @Published var lastRoutePlaceID: String?
  @Published var selectedRouteSummary: RouteSummary?
  @Published var isSearching = false
  @Published var isRouting = false
  @Published var hasCompletedOnboarding: Bool

  let locationService: LocationService

  private let settingsStore: SettingsStore
  private let navigationAPI: NavigationAPIClient
  private let announcer: VoiceOverAnnouncer

  private var knownPlaces: [String: Place] = [:]
  private var cancellables: Set<AnyCancellable> = []

  init() {
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
    favorites = snapshot.favorites
    lastRoutePlaceID = snapshot.lastRoutePlaceID
    hasCompletedOnboarding = snapshot.hasCompletedOnboarding
    favorites.forEach { knownPlaces[$0.id] = $0 }

    bindLocation()
  }

  var appVersionLabel: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
  }

  var appBuildLabel: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
  }

  var hasLocationPermission: Bool {
    locationService.hasPermission
  }

  func bootstrap() async {
    refreshLaunchState()
    if hasLocationPermission {
      locationService.startUpdates()
      await loadCurrentAddress()
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

  func saveCurrentLocationAsFavorite() async {
    guard let fix = locationService.latestFix else { return }
    let address = currentLocationDescription.isEmpty ? L10n.text("current.position.unknown", table: .home) : currentLocationDescription
    let place = Place(
      id: "current-\(Int(Date().timeIntervalSince1970))",
      name: L10n.text("current.position.saved_name", table: .home),
      address: address,
      walkDistanceMeters: 0,
      walkEtaMinutes: 0,
      point: fix.point
    )
    toggleFavorite(place)
  }

  func loadCurrentAddress() async {
    guard let fix = locationService.latestFix else {
      currentLocationDescription = L10n.text("home.location.waiting", table: .home)
      return
    }

    do {
      currentLocationDescription = try await navigationAPI.reverseGeocode(point: fix.point)
    } catch {
      currentLocationDescription = L10n.text("home.location.fallback", table: .home)
    }
  }

  func performSearch() async {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      searchResults = []
      return
    }

    isSearching = true
    defer { isSearching = false }

    do {
      let results = try await navigationAPI.searchPlaces(query: query, near: locationService.latestFix?.point)
      searchResults = results
      results.forEach { knownPlaces[$0.id] = $0 }
      statusMessage = L10n.text("search.status.results", table: .home, results.count)
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

    isRouting = true
    defer { isRouting = false }

    do {
      let summary = try await navigationAPI.buildWalkingRoute(from: start, to: place)
      selectedRouteSummary = summary
      lastRoutePlaceID = place.id
      settingsStore.setLastRoutePlaceID(place.id)
      statusMessage = L10n.text("route.status.ready", table: .navigation)
    } catch {
      selectedRouteSummary = nil
      statusMessage = L10n.text("route.status.error", table: .navigation)
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

  func openCurrentPosition() {
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

  func updateShowTutorialOnLaunch(_ enabled: Bool) {
    settings.showTutorialOnLaunch = enabled
    settingsStore.updateSettings { $0.showTutorialOnLaunch = enabled }
  }

  func updateVibrationEnabled(_ enabled: Bool) {
    settings.vibrationEnabled = enabled
    settingsStore.updateSettings { $0.vibrationEnabled = enabled }
  }

  func updateAutoRecalculate(_ enabled: Bool) {
    settings.autoRecalculate = enabled
    settingsStore.updateSettings { $0.autoRecalculate = enabled }
  }

  func updateJunctionAlerts(_ enabled: Bool) {
    settings.junctionAlerts = enabled
    settingsStore.updateSettings { $0.junctionAlerts = enabled }
  }

  func updateTurnByTurnAnnouncements(_ enabled: Bool) {
    settings.turnByTurnAnnouncements = enabled
    settingsStore.updateSettings { $0.turnByTurnAnnouncements = enabled }
  }

  func updateSpeechMode(_ mode: GuidanceSpeechMode) {
    settings.speechMode = mode
    settingsStore.updateSettings { $0.speechMode = mode }
    announcer.announce(L10n.text("settings.speech_mode.updated", table: .settings), settings: settings)
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
      .sink { [weak self] _ in
        guard let self else { return }
        Task { await self.loadCurrentAddress() }
      }
      .store(in: &cancellables)
  }
}
