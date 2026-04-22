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

  func setLastRoutePlaceID(_ placeID: String?) {
    snapshot.lastRoutePlaceID = placeID
    save()
  }

  func setOnboardingCompleted(_ completed: Bool) {
    snapshot.hasCompletedOnboarding = completed
    save()
  }

  private func save() {
    guard let data = try? encoder.encode(snapshot) else {
      return
    }
    defaults.set(data, forKey: key)
  }
}
