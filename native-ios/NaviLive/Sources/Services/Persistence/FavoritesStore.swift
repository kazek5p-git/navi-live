import Combine
import Foundation

@MainActor
final class FavoritesStore: ObservableObject {
  @Published private(set) var favorites: [Place]

  private let settingsStore: SettingsStore

  init(settingsStore: SettingsStore) {
    self.settingsStore = settingsStore
    favorites = settingsStore.snapshot.favorites
  }

  func refreshFromSettings() {
    favorites = settingsStore.snapshot.favorites
  }

  func contains(_ place: Place) -> Bool {
    favorites.contains(where: { $0.id == place.id })
  }

  func toggle(_ place: Place) {
    if let index = favorites.firstIndex(where: { $0.id == place.id }) {
      favorites.remove(at: index)
    } else {
      favorites.append(place)
    }
    settingsStore.setFavorites(favorites)
  }
}
