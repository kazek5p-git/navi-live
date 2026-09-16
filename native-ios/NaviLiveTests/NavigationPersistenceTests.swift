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

  func testBackupRoundTripsSettingsFavoritesAndLastRoute() throws {
    var snapshot = PersistedSnapshot()
    snapshot.settings.languageCode = "pl"
    snapshot.settings.interfaceTheme = .highContrast
    snapshot.settings.nearbyPOICacheMode = .wifiOnly
    snapshot.settings.soundCueTheme = .cosmic
    snapshot.settings.speechMode = .speechSynthesizer
    snapshot.settings.selectedSpeechVoiceIdentifier = "com.example.voice"

    let place = Place(
      id: "favorite-1",
      name: "Sklep testowy",
      address: "Przykładowa 12, Łódź",
      walkDistanceMeters: 120,
      walkEtaMinutes: 2,
      point: GeoPoint(latitude: 51.760000, longitude: 19.460000),
      savedAt: Date(timeIntervalSince1970: 123_456),
      savedAccuracyMeters: 8.5
    )
    let summary = RouteSummary(
      distanceMeters: 1_250,
      etaMinutes: 17,
      modeLabel: "Pieszo",
      currentInstruction: "Skręć w prawo w Wschodnią",
      nextInstruction: "Idź prosto",
      steps: [
        RouteStep(
          instruction: "Skręć w prawo w Wschodnią",
          distanceMeters: 80,
          maneuverPoint: place.point,
          maneuverType: "turn",
          maneuverModifier: "right",
          roadName: "Wschodnia"
        )
      ],
      pathPoints: [
        GeoPoint(latitude: 51.759000, longitude: 19.459000),
        GeoPoint(latitude: 51.760000, longitude: 19.460000)
      ]
    )
    snapshot.favorites = [place]
    snapshot.lastRoutePlaceID = place.id
    snapshot.lastRoutePlace = place
    snapshot.lastRouteSummary = summary
    snapshot.hasCompletedOnboarding = true

    let decoded = try NaviLiveBackupCodec.decodePayload(
      try NaviLiveBackupCodec.encode(payload: NaviLiveBackupCodec.makePayload(snapshot: snapshot))
    )

    XCTAssertEqual(decoded.settings?.appSettings(merging: .init()), snapshot.settings)
    XCTAssertEqual(decoded.favorites?.map { $0.place() }, [place])
    XCTAssertEqual(decoded.lastRoute?.placeID, place.id)
    XCTAssertEqual(decoded.lastRoute?.place?.place(), place)
    XCTAssertEqual(decoded.lastRoute?.summary, summary)
    XCTAssertEqual(decoded.hasCompletedOnboarding, true)
  }

  func testBackupAcceptsAndroidStyleSpeechPlatformAndValues() throws {
    let data = Data(
      """
      {
        "schemaVersion": 1,
        "appName": "Navi Live",
        "settings": {
          "interfaceTheme": "high_contrast",
          "nearbyPOICacheMode": "wifi_only",
          "speechMode": "screen_reader",
          "selectedSpeechVoicePlatform": "android",
          "selectedSpeechVoiceIdentifier": "com.example.tts"
        }
      }
      """.utf8
    )

    let payload = try NaviLiveBackupCodec.decodePayload(data)
    let settings = try XCTUnwrap(payload.settings).appSettings(merging: .init())

    XCTAssertEqual(settings.interfaceTheme, .highContrast)
    XCTAssertEqual(settings.nearbyPOICacheMode, .wifiOnly)
    XCTAssertEqual(settings.speechMode, .voiceOver)
    XCTAssertNil(settings.selectedSpeechVoiceIdentifier)
  }

  func testPartialBackupSettingsKeepValuesMissingFromBackup() throws {
    let data = Data(
      """
      {
        "schemaVersion": 1,
        "appName": "Navi Live",
        "settings": {
          "interfaceTheme": "light",
          "customInterfaceThemeColors": {"accentHex": "#FFD600"},
          "searchRadiusKilometers": 2
        }
      }
      """.utf8
    )
    let payload = try NaviLiveBackupCodec.decodePayload(data)
    var current = AppSettings()
    current.interfaceTheme = .dark
    current.customInterfaceThemeColors = InterfaceThemeColors(
      backgroundHex: "#101010",
      surfaceHex: "#202020",
      primaryTextHex: "#FFFFFF",
      secondaryTextHex: "#DDDDDD",
      accentHex: "#00FF00",
      outlineHex: "#FFFFFF"
    )
    current.selectedSpeechVoiceIdentifier = "com.example.current"
    current.searchResultLimit = 10

    let merged = try XCTUnwrap(payload.settings).appSettings(merging: current)

    XCTAssertEqual(merged.interfaceTheme, .light)
    XCTAssertEqual(merged.customInterfaceThemeColors.accentHex, "#FFD600")
    XCTAssertEqual(merged.customInterfaceThemeColors.backgroundHex, "#101010")
    XCTAssertEqual(merged.searchRadiusKilometers, 2)
    XCTAssertEqual(merged.searchResultLimit, 10)
    XCTAssertEqual(merged.selectedSpeechVoiceIdentifier, "com.example.current")
  }

  func testBackupDecodesAndroidRouteStepKinds() throws {
    let data = Data(
      """
      {
        "schemaVersion": 1,
        "appName": "Navi Live",
        "lastRoute": {
          "placeID": "target",
          "summary": {
            "distanceMeters": 100,
            "etaMinutes": 2,
            "modeLabel": "Walking",
            "currentInstruction": "Cross the street",
            "nextInstruction": "",
            "steps": [
              {
                "instruction": "Cross the street",
                "distanceMeters": 20,
                "kind": "PedestrianCrossing"
              }
            ],
            "pathPoints": [
              {"latitude": 51.0, "longitude": 19.0}
            ]
          }
        }
      }
      """.utf8
    )

    let step = try NaviLiveBackupCodec.decodePayload(data).lastRoute?.summary?.steps.first

    XCTAssertEqual(step?.kind, .pedestrianCrossing)
  }

  @MainActor
  func testLocalRestorePointPersistsAndDocumentReadsValidatedData() throws {
    let suiteName = "NaviLiveTests.Backup.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = SettingsStore(defaults: defaults)
    let data = try store.makeBackupData()
    store.setLocalRestorePointData(data)

    let restoredStore = SettingsStore(defaults: defaults)
    XCTAssertEqual(restoredStore.localRestorePointData(), data)

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("navi-live-backup-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try data.write(to: url)
    XCTAssertEqual(try NaviLiveBackupDocument.readData(from: url), data)
  }

  @MainActor
  func testSettingsStoreRestoresBackupRoutePlaceAsNativePlace() throws {
    let suiteName = "NaviLiveTests.BackupRoute.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let place = Place(
      id: "route-place-1",
      name: "Punkt na trasie",
      address: "Testowa 8, Łódź",
      walkDistanceMeters: 0,
      walkEtaMinutes: 0,
      point: GeoPoint(latitude: 51.760000, longitude: 19.460000)
    )
    let summary = RouteSummary(
      distanceMeters: 800,
      etaMinutes: 10,
      modeLabel: "Pieszo",
      currentInstruction: "Idź prosto",
      nextInstruction: "Skręć w prawo",
      steps: [],
      pathPoints: [place.point!]
    )

    let store = SettingsStore(defaults: defaults)
    store.restoreBackup(
      settings: nil,
      favorites: nil,
      lastRoute: NaviLiveBackupRoute(
        placeID: place.id,
        place: NaviLiveBackupPlace(place: place),
        summary: summary
      ),
      includesLastRoute: true,
      hasCompletedOnboarding: nil
    )

    let restored = SettingsStore(defaults: defaults)
    XCTAssertEqual(restored.snapshot.lastRoutePlace, place)
    XCTAssertEqual(restored.snapshot.lastRoutePlaceID, place.id)
    XCTAssertEqual(restored.snapshot.lastRouteSummary, summary)
  }

  func testBackupRejectsEmptyInvalidAndNewerFiles() throws {
    assertBackupError(.emptyFile, data: Data())
    assertBackupError(.invalidFile, data: Data("not-json".utf8))
    assertBackupError(
      .newerSchema,
      data: Data(#"{"schemaVersion":2,"appName":"Navi Live","settings":{}}"#.utf8)
    )
    assertBackupError(
      .unsupportedApp,
      data: Data(#"{"schemaVersion":1,"appName":"Other App","settings":{}}"#.utf8)
    )
  }

  private func assertBackupError(
    _ expected: NaviLiveBackupError,
    data: Data,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    do {
      _ = try NaviLiveBackupCodec.decodePayload(data)
      XCTFail("Oczekiwano błędu \(expected)", file: file, line: line)
    } catch let error as NaviLiveBackupError {
      XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
      XCTFail("Oczekiwano błędu \(expected), otrzymano \(error)", file: file, line: line)
    }
  }
}
