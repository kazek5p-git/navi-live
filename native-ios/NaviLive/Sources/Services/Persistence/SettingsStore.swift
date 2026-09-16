import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
  @Published private(set) var snapshot: PersistedSnapshot

  private let defaults: UserDefaults
  private let key = "navi_live.ios.snapshot"
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: key),
       let decoded = try? decoder.decode(PersistedSnapshot.self, from: data) {
      snapshot = decoded
    } else {
      snapshot = PersistedSnapshot()
    }
  }

  func updateSettings(_ transform: (inout AppSettings) -> Void) {
    transform(&snapshot.settings)
    save()
  }

  func setFavorites(_ favorites: [Place]) {
    snapshot.favorites = favorites
    save()
  }

  func setLastRoute(place: Place?, summary: RouteSummary?) {
    snapshot.lastRoutePlaceID = place?.id
    snapshot.lastRoutePlace = place
    snapshot.lastRouteSummary = summary
    save()
  }

  func setOnboardingCompleted(_ completed: Bool) {
    snapshot.hasCompletedOnboarding = completed
    save()
  }

  func makeBackupData() throws -> Data {
    let payload = NaviLiveBackupCodec.makePayload(snapshot: snapshot)
    return try NaviLiveBackupCodec.encode(payload: payload)
  }

  func localRestorePointData() -> Data? {
    snapshot.localRestorePointData
  }

  func setLocalRestorePointData(_ data: Data) {
    snapshot.localRestorePointData = data
    save()
  }

  func restoreBackup(
    settings: AppSettings?,
    favorites: [Place]?,
    lastRoute: NaviLiveBackupRoute?,
    includesLastRoute: Bool,
    hasCompletedOnboarding: Bool?
  ) {
    if let settings {
      snapshot.settings = settings
    }
    if let favorites {
      snapshot.favorites = favorites
    }
    if includesLastRoute {
      snapshot.lastRoutePlaceID = lastRoute?.placeID
      snapshot.lastRoutePlace = lastRoute?.place?.place()
      snapshot.lastRouteSummary = lastRoute?.summary
    }
    if let hasCompletedOnboarding {
      snapshot.hasCompletedOnboarding = hasCompletedOnboarding
    }
    save()
  }

  private func save() {
    guard let data = try? encoder.encode(snapshot) else {
      return
    }
    defaults.set(data, forKey: key)
  }
}
