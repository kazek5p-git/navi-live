import Foundation
import UIKit
import XCTest
@testable import NaviLive

final class NavigationPersistenceTests: XCTestCase {
  func testPlaceRoundTripsWithSavedLocationAndOptionalFields() throws {
    let place = Place(
      id: "favorite-1",
      name: "Sklep Ruterek i GSM",
      address: "Wschodnia 12, Łódź",
      walkDistanceMeters: 0,
      walkEtaMinutes: 0,
      point: GeoPoint(latitude: 51.760000, longitude: 19.460000),
      phone: "+48 123 456 789",
      website: "https://example.invalid",
      savedAt: Date(timeIntervalSince1970: 123_456),
      savedAccuracyMeters: 8.5
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Place.self, from: encoder.encode(place))

    XCTAssertEqual(decoded, place)
  }

  func testRouteSummaryRoundTripsAllNavigationData() throws {
    let summary = RouteSummary(
      distanceMeters: 1_250,
      etaMinutes: 17,
      modeLabel: "Pieszo",
      currentInstruction: "Skręć w prawo w Wschodnią",
      nextInstruction: "Idź prosto",
      steps: [
        RouteStep(
          id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          instruction: "Skręć w prawo w Wschodnią",
          distanceMeters: 80,
          maneuverPoint: GeoPoint(latitude: 51.760000, longitude: 19.460000),
          maneuverType: "turn",
          maneuverModifier: "right",
          roadName: "Wschodnia"
        ),
        RouteStep(
          id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
          instruction: "Przejście dla pieszych",
          distanceMeters: 25,
          kind: .pedestrianCrossing,
          maneuverType: "street_crossing"
        )
      ],
      pathPoints: [
        GeoPoint(latitude: 51.759000, longitude: 19.459000),
        GeoPoint(latitude: 51.760000, longitude: 19.460000)
      ]
    )

    let data = try JSONEncoder().encode(summary)
    let decoded = try JSONDecoder().decode(RouteSummary.self, from: data)

    XCTAssertEqual(decoded, summary)
  }

  @MainActor
  func testSettingsStoreRestoresFavoritesAndLastRouteAfterRecreation() throws {
    let suiteName = "NaviLiveTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let place = Place(
      id: "saved-1",
      name: "Punkt testowy",
      address: "Lipowa 4, Łódź",
      walkDistanceMeters: 0,
      walkEtaMinutes: 0,
      point: GeoPoint(latitude: 51.760000, longitude: 19.460000),
      savedAt: Date(timeIntervalSince1970: 20),
      savedAccuracyMeters: 9
    )
    let summary = RouteSummary(
      distanceMeters: 500,
      etaMinutes: 7,
      modeLabel: "Pieszo",
      currentInstruction: "Idź prosto",
      nextInstruction: "Skręć w lewo",
      steps: [],
      pathPoints: [place.point!]
    )

    let store = SettingsStore(defaults: defaults)
    store.setFavorites([place])
    store.setLastRoute(place: place, summary: summary)

    let restored = SettingsStore(defaults: defaults)
    XCTAssertEqual(restored.snapshot.favorites, [place])
    XCTAssertEqual(restored.snapshot.lastRoutePlace, place)
    XCTAssertEqual(restored.snapshot.lastRoutePlaceID, place.id)
    XCTAssertEqual(restored.snapshot.lastRouteSummary, summary)
  }

  @MainActor
  func testSettingsStorePersistsInterfaceThemeAndCustomColors() throws {
    let suiteName = "NaviLiveTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = SettingsStore(defaults: defaults)
    store.updateSettings {
      $0.interfaceTheme = .custom
      $0.customInterfaceThemeColors = InterfaceThemeColors(
        backgroundHex: "#101010",
        surfaceHex: "#202020",
        primaryTextHex: "#FFFFFF",
        secondaryTextHex: "#DDDDDD",
        accentHex: "#FFD600",
        outlineHex: "#FFFFFF"
      )
    }

    let restored = SettingsStore(defaults: defaults)
    XCTAssertEqual(restored.snapshot.settings.interfaceTheme, .custom)
    XCTAssertEqual(restored.snapshot.settings.customInterfaceThemeColors.accentHex, "#FFD600")
  }

  func testOlderSettingsDefaultToSystemInterfaceTheme() throws {
    let data = try JSONSerialization.data(
      withJSONObject: [
        "settings": ["languageCode": "pl"]
      ]
    )

    let snapshot = try JSONDecoder().decode(PersistedSnapshot.self, from: data)
    XCTAssertEqual(snapshot.settings.interfaceTheme, .system)
    XCTAssertEqual(snapshot.settings.customInterfaceThemeColors.backgroundHex, "#F5F9FF")
  }

  func testCustomThemeChoosesReadableTextWhenSelectedColorHasInsufficientContrast() {
    let background = UIColor(red: 0.47, green: 0.47, blue: 0.47, alpha: 1)
    let preferred = UIColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1)
    let text = NaviLiveThemeColorSupport.accessibleTextColor(preferred, on: [background])

    XCTAssertGreaterThanOrEqual(
      NaviLiveThemeColorSupport.contrastRatio(text, background),
      4.5
    )
  }
}
