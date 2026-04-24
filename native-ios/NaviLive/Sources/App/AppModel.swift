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
  @Published var headingState: HeadingState
  @Published var activeNavigationState: ActiveNavigationState
  @Published var isSearching = false
  @Published var isRouting = false
  @Published var hasCompletedOnboarding: Bool

  let locationService: LocationService

  private let settingsStore: SettingsStore
  private let navigationAPI: NavigationAPIClient
  private let announcer: VoiceOverAnnouncer
  private let liveNavigationEngine = LiveNavigationEngine()

  private var knownPlaces: [String: Place] = [:]
  private var cancellables: Set<AnyCancellable> = []
  private var isNavigationLive = false
  private var lastCountdownAnnouncementStepIndex = -1
  private var lastCountdownMilestoneMeters: Int?
  private var lastImmediateAnnouncementStepIndex = -1
  private var headingIndex = 0
  private let headingSequence = [
    HeadingState(
      instruction: L10n.text("heading.instruction.rotate_right", table: .navigation),
      isAligned: false,
      arrowRotationDegrees: 22
    ),
    HeadingState(
      instruction: L10n.text("heading.instruction.almost_aligned", table: .navigation),
      isAligned: false,
      arrowRotationDegrees: 7
    ),
    HeadingState(
      instruction: L10n.text("heading.instruction.aligned", table: .navigation),
      isAligned: true,
      arrowRotationDegrees: 0
    )
  ]

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
    favorites = snapshot.favorites
    lastRoutePlaceID = snapshot.lastRoutePlaceID
    headingState = headingSequence.first ?? HeadingState()
    activeNavigationState = ActiveNavigationState()
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
      headingIndex = 0
      headingState = headingSequence[headingIndex]
      activeNavigationState = liveNavigationEngine.loadRoute(
        destination: place,
        summary: summary,
        fix: locationService.latestFix
      )
      isNavigationLive = false
      lastCountdownAnnouncementStepIndex = -1
      lastCountdownMilestoneMeters = nil
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

  func cycleHeadingInstruction() {
    headingIndex = (headingIndex + 1) % headingSequence.count
    headingState = headingSequence[headingIndex]
  }

  func markHeadingAligned() {
    headingIndex = headingSequence.count - 1
    headingState = headingSequence[headingIndex]
    statusMessage = L10n.text("heading.status.aligned", table: .navigation)
    announceSuccess(message: L10n.text("heading.instruction.aligned", table: .navigation))
  }

  func beginActiveNavigation() {
    guard liveNavigationEngine.currentDestination != nil else { return }
    locationService.prepareForActiveNavigation()
    isNavigationLive = true
    lastCountdownAnnouncementStepIndex = -1
    lastCountdownMilestoneMeters = nil
    lastImmediateAnnouncementStepIndex = -1
    activeNavigationState.isPaused = false
    statusMessage = L10n.text("active.status.started", table: .navigation)
    announceNavigationPrompt(
      activeNavigationState.currentInstruction.isEmpty
        ? L10n.text("route.follow_default", table: .navigation)
        : activeNavigationState.currentInstruction
    )
    if let latestFix = locationService.latestFix {
      syncActiveNavigationWithLocation(latestFix)
    }
  }

  func repeatCurrentInstruction() {
    let message = activeNavigationState.currentInstruction.isEmpty
      ? L10n.text("route.follow_default", table: .navigation)
      : activeNavigationState.currentInstruction
    statusMessage = L10n.text("active.status.repeating", table: .navigation)
    announceNavigationPrompt(message)
  }

  func togglePauseNavigation() {
    activeNavigationState.isPaused.toggle()
    if activeNavigationState.isPaused {
      statusMessage = L10n.text("active.status.paused", table: .navigation)
      announceNavigationPrompt(L10n.text("active.status.paused", table: .navigation), warning: true)
    } else {
      statusMessage = L10n.text("active.status.resumed", table: .navigation)
      announceNavigationPrompt(L10n.text("active.status.resumed", table: .navigation))
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

  func stopNavigation() {
    isNavigationLive = false
    lastCountdownAnnouncementStepIndex = -1
    lastCountdownMilestoneMeters = nil
    lastImmediateAnnouncementStepIndex = -1
    locationService.finishActiveNavigation()
    announcer.stopSpeech()
    liveNavigationEngine.reset()
    headingIndex = 0
    headingState = headingSequence[headingIndex]
    activeNavigationState = ActiveNavigationState()
    selectedRouteSummary = nil
    statusMessage = L10n.text("active.status.stopped", table: .navigation)
  }

  func markArrived() {
    guard let destination = liveNavigationEngine.currentDestination else { return }
    isNavigationLive = false
    lastCountdownAnnouncementStepIndex = -1
    lastCountdownMilestoneMeters = nil
    lastImmediateAnnouncementStepIndex = -1
    locationService.finishActiveNavigation()
    activeNavigationState.isPaused = false
    activeNavigationState.isOffRoute = false
    activeNavigationState.isRecalculating = false
    statusMessage = L10n.text("active.status.arrived", table: .navigation)
    announceNavigationPrompt(L10n.text("active.spoken.arrived", table: .navigation))
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
      .sink { [weak self] fix in
        guard let self else { return }
        Task { await self.loadCurrentAddress() }
        self.syncActiveNavigationWithLocation(fix)
      }
      .store(in: &cancellables)
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
          L10n.text("active.spoken.now", table: .navigation, update.state.currentInstruction)
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

    isRouting = true
    activeNavigationState.isRecalculating = true
    statusMessage = L10n.text("active.status.recalculating", table: .navigation)
    defer {
      isRouting = false
    }

    do {
      let summary = try await navigationAPI.buildWalkingRoute(from: start, to: place)
      selectedRouteSummary = summary
      activeNavigationState = liveNavigationEngine.loadRoute(
        destination: place,
        summary: summary,
        fix: locationService.latestFix
      )
      lastCountdownAnnouncementStepIndex = -1
      lastCountdownMilestoneMeters = nil
      lastImmediateAnnouncementStepIndex = -1
      activeNavigationState.isRecalculating = false
      if autoTriggered {
        statusMessage = L10n.text("active.status.auto_recalculated", table: .navigation)
      } else {
        statusMessage = L10n.text("active.status.recalculated", table: .navigation)
      }
      announceNavigationPrompt(L10n.text("active.spoken.recalculated", table: .navigation))
    } catch {
      activeNavigationState.isRecalculating = false
      statusMessage = L10n.text("route.status.error", table: .navigation)
      announceWarning(message: L10n.text("route.status.error", table: .navigation))
    }
  }

  private func maybeAnnounceCountdownInstruction(update: LiveNavigationUpdate) -> Bool {
    guard !update.stepChanged else { return false }
    guard !update.state.isOffRoute, !update.state.isRecalculating, !update.hasArrived else { return false }
    let upcomingStepIndex = update.currentStepIndex + 1
    guard let upcomingInstruction = update.upcomingInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
          !upcomingInstruction.isEmpty else {
      return false
    }
    guard let milestoneMeters = NavigationScenarioCore.countdownMilestoneMeters(
      distanceToNext: update.state.distanceToNextMeters
    ) else {
      return false
    }

    if upcomingStepIndex != lastCountdownAnnouncementStepIndex {
      lastCountdownAnnouncementStepIndex = upcomingStepIndex
      lastCountdownMilestoneMeters = nil
    }
    if let lastMilestone = lastCountdownMilestoneMeters, milestoneMeters >= lastMilestone {
      return false
    }

    lastCountdownMilestoneMeters = milestoneMeters
    announceNavigationPrompt(
      L10n.text(
        "active.spoken.upcoming",
        table: .navigation,
        milestoneMeters,
        upcomingInstruction
      )
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
      L10n.text("active.spoken.now", table: .navigation, upcomingInstruction)
    )
    return true
  }

  private func announceNavigationPrompt(_ message: String, warning: Bool = false) {
    announcer.announceNavigation(message, settings: settings)
    if settings.vibrationEnabled {
      if warning {
        announcer.hapticWarning()
      } else {
        announcer.hapticSuccess()
      }
    }
  }

  private func announceSuccess(message: String) {
    announcer.announce(message, settings: settings)
    hapticSuccessIfEnabled()
  }

  private func announceWarning(message: String) {
    announcer.announce(message, settings: settings)
    if settings.vibrationEnabled {
      announcer.hapticWarning()
    }
  }

  private func hapticSuccessIfEnabled() {
    if settings.vibrationEnabled {
      announcer.hapticSuccess()
    }
  }
}
