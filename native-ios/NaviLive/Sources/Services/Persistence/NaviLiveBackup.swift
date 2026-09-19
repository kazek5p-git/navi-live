import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum NaviLiveBackupError: LocalizedError, Equatable {
  case emptyFile
  case invalidFile
  case noContent
  case newerSchema
  case unsupportedApp

  var errorDescription: String? {
    switch self {
    case .emptyFile:
      return "Wybrany plik backupu jest pusty."
    case .invalidFile:
      return "Wybrany plik nie jest prawidłowym backupem Navi Live."
    case .noContent:
      return "Wybrany backup nie zawiera danych do przywrócenia."
    case .newerSchema:
      return "Ten backup został utworzony w nowszej wersji Navi Live."
    case .unsupportedApp:
      return "Ten plik nie jest backupem Navi Live."
    }
  }
}

struct NaviLiveBackupPlace: Codable, Equatable {
  var id: String
  var name: String
  var address: String
  var walkDistanceMeters: Int
  var walkEtaMinutes: Int
  var point: GeoPoint?
  var phone: String?
  var website: String?
  var savedAtMs: Int64?
  var savedAccuracyMeters: Double?

  init(place: Place) {
    id = place.id
    name = place.name
    address = place.address
    walkDistanceMeters = place.walkDistanceMeters
    walkEtaMinutes = place.walkEtaMinutes
    point = place.point
    phone = place.phone
    website = place.website
    savedAtMs = place.savedAt.map { Int64(($0.timeIntervalSince1970 * 1_000).rounded()) }
    savedAccuracyMeters = place.savedAccuracyMeters
  }

  func place() -> Place {
    Place(
      id: id,
      name: name,
      address: address,
      walkDistanceMeters: max(0, walkDistanceMeters),
      walkEtaMinutes: max(0, walkEtaMinutes),
      point: point,
      phone: phone,
      website: website,
      savedAt: savedAtMs.map { Date(timeIntervalSince1970: Double($0) / 1_000) },
      savedAccuracyMeters: savedAccuracyMeters
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case address
    case walkDistanceMeters
    case walkEtaMinutes
    case point
    case phone
    case website
    case savedAtMs
    case savedAt
    case savedAccuracyMeters
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
    walkDistanceMeters = try container.decodeIfPresent(Int.self, forKey: .walkDistanceMeters) ?? 0
    walkEtaMinutes = try container.decodeIfPresent(Int.self, forKey: .walkEtaMinutes) ?? 0
    point = try container.decodeIfPresent(GeoPoint.self, forKey: .point)
    phone = try container.decodeIfPresent(String.self, forKey: .phone)
    website = try container.decodeIfPresent(String.self, forKey: .website)
    savedAtMs = try container.decodeIfPresent(Int64.self, forKey: .savedAtMs)
    if savedAtMs == nil, let legacyDate = try container.decodeIfPresent(Double.self, forKey: .savedAt) {
      savedAtMs = Int64((legacyDate * 1_000).rounded())
    }
    savedAccuracyMeters = try container.decodeIfPresent(Double.self, forKey: .savedAccuracyMeters)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(address, forKey: .address)
    try container.encode(walkDistanceMeters, forKey: .walkDistanceMeters)
    try container.encode(walkEtaMinutes, forKey: .walkEtaMinutes)
    try container.encodeIfPresent(point, forKey: .point)
    try container.encodeIfPresent(phone, forKey: .phone)
    try container.encodeIfPresent(website, forKey: .website)
    try container.encodeIfPresent(savedAtMs, forKey: .savedAtMs)
    try container.encodeIfPresent(savedAccuracyMeters, forKey: .savedAccuracyMeters)
  }
}

struct NaviLiveBackupThemeColors: Codable, Equatable {
  var backgroundHex: String?
  var surfaceHex: String?
  var primaryTextHex: String?
  var secondaryTextHex: String?
  var accentHex: String?
  var outlineHex: String?

  init(colors: InterfaceThemeColors) {
    backgroundHex = colors.backgroundHex
    surfaceHex = colors.surfaceHex
    primaryTextHex = colors.primaryTextHex
    secondaryTextHex = colors.secondaryTextHex
    accentHex = colors.accentHex
    outlineHex = colors.outlineHex
  }

  func mergeInto(_ current: InterfaceThemeColors) -> InterfaceThemeColors {
    InterfaceThemeColors(
      backgroundHex: backgroundHex ?? current.backgroundHex,
      surfaceHex: surfaceHex ?? current.surfaceHex,
      primaryTextHex: primaryTextHex ?? current.primaryTextHex,
      secondaryTextHex: secondaryTextHex ?? current.secondaryTextHex,
      accentHex: accentHex ?? current.accentHex,
      outlineHex: outlineHex ?? current.outlineHex
    )
  }
}

struct NaviLiveBackupSettings: Codable, Equatable {
  var languageCode: String?
  var interfaceTheme: String?
  var customInterfaceThemeColors: NaviLiveBackupThemeColors?
  var showTutorialOnLaunch: Bool?
  var vibrationEnabled: Bool?
  var shakeGestureEnabled: Bool?
  var shakeStrength: String?
  var headphoneButtonRepeatEnabled: Bool?
  var soundCuesEnabled: Bool?
  var soundCueVolumePercent: Int?
  var soundCueTheme: String?
  var autoRecalculate: Bool?
  var junctionAlerts: Bool?
  var pedestrianCrossingAlerts: Bool?
  var turnByTurnAnnouncements: Bool?
  var announcementCadenceMode: String?
  var searchRadiusKilometers: Int?
  var searchResultLimit: Int?
  var nearbyPOICacheMode: String?
  var nearbyPOICacheRadiusKilometers: Int?
  var updateChannel: String?
  var speechMode: String?
  var selectedSpeechVoicePlatform: String?
  var selectedSpeechVoiceIdentifier: String?
  var speechRatePercent: Int?
  var speechVolumePercent: Int?
  private var presentKeys: Set<String> = []

  init(settings: AppSettings) {
    languageCode = settings.languageCode
    interfaceTheme = settings.interfaceTheme.rawValue
    customInterfaceThemeColors = NaviLiveBackupThemeColors(colors: settings.customInterfaceThemeColors)
    showTutorialOnLaunch = settings.showTutorialOnLaunch
    vibrationEnabled = settings.vibrationEnabled
    shakeGestureEnabled = settings.shakeGestureEnabled
    shakeStrength = settings.shakeStrength.rawValue
    headphoneButtonRepeatEnabled = settings.headphoneButtonRepeatEnabled
    soundCuesEnabled = settings.soundCuesEnabled
    soundCueVolumePercent = Int((settings.soundCueVolume * 100).rounded())
    soundCueTheme = settings.soundCueTheme.rawValue
    autoRecalculate = settings.autoRecalculate
    junctionAlerts = settings.junctionAlerts
    pedestrianCrossingAlerts = settings.pedestrianCrossingAlerts
    turnByTurnAnnouncements = settings.turnByTurnAnnouncements
    announcementCadenceMode = settings.announcementCadenceMode.rawValue
    searchRadiusKilometers = settings.searchRadiusKilometers
    searchResultLimit = settings.searchResultLimit
    nearbyPOICacheMode = settings.nearbyPOICacheMode.rawValue
    nearbyPOICacheRadiusKilometers = settings.nearbyPOICacheRadiusKilometers
    updateChannel = nil
    speechMode = settings.speechMode == .voiceOver ? "screenReader" : "system"
    selectedSpeechVoicePlatform = "ios"
    selectedSpeechVoiceIdentifier = settings.selectedSpeechVoiceIdentifier
    speechRatePercent = Int((settings.speechRate * 100).rounded())
    speechVolumePercent = Int((settings.speechVolume * 100).rounded())
    presentKeys = Set(CodingKeys.allCases.map { $0.rawValue })
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
    interfaceTheme = try container.decodeIfPresent(String.self, forKey: .interfaceTheme)
    customInterfaceThemeColors = try container.decodeIfPresent(
      NaviLiveBackupThemeColors.self,
      forKey: .customInterfaceThemeColors
    )
    showTutorialOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .showTutorialOnLaunch)
    vibrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .vibrationEnabled)
    shakeGestureEnabled = try container.decodeIfPresent(Bool.self, forKey: .shakeGestureEnabled)
    shakeStrength = try container.decodeIfPresent(String.self, forKey: .shakeStrength)
    headphoneButtonRepeatEnabled = try container.decodeIfPresent(Bool.self, forKey: .headphoneButtonRepeatEnabled)
    soundCuesEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundCuesEnabled)
    soundCueVolumePercent = try container.decodeIfPresent(Int.self, forKey: .soundCueVolumePercent)
    soundCueTheme = try container.decodeIfPresent(String.self, forKey: .soundCueTheme)
    autoRecalculate = try container.decodeIfPresent(Bool.self, forKey: .autoRecalculate)
    junctionAlerts = try container.decodeIfPresent(Bool.self, forKey: .junctionAlerts)
    pedestrianCrossingAlerts = try container.decodeIfPresent(Bool.self, forKey: .pedestrianCrossingAlerts)
    turnByTurnAnnouncements = try container.decodeIfPresent(Bool.self, forKey: .turnByTurnAnnouncements)
    announcementCadenceMode = try container.decodeIfPresent(String.self, forKey: .announcementCadenceMode)
    searchRadiusKilometers = try container.decodeIfPresent(Int.self, forKey: .searchRadiusKilometers)
    searchResultLimit = try container.decodeIfPresent(Int.self, forKey: .searchResultLimit)
    nearbyPOICacheMode = try container.decodeIfPresent(String.self, forKey: .nearbyPOICacheMode)
    nearbyPOICacheRadiusKilometers = try container.decodeIfPresent(Int.self, forKey: .nearbyPOICacheRadiusKilometers)
    updateChannel = try container.decodeIfPresent(String.self, forKey: .updateChannel)
    speechMode = try container.decodeIfPresent(String.self, forKey: .speechMode)
    selectedSpeechVoicePlatform = try container.decodeIfPresent(String.self, forKey: .selectedSpeechVoicePlatform)
    selectedSpeechVoiceIdentifier = try container.decodeIfPresent(String.self, forKey: .selectedSpeechVoiceIdentifier)
    speechRatePercent = try container.decodeIfPresent(Int.self, forKey: .speechRatePercent)
    speechVolumePercent = try container.decodeIfPresent(Int.self, forKey: .speechVolumePercent)
    presentKeys = Set(container.allKeys.map { $0.rawValue })
  }

  func appSettings(merging current: AppSettings) -> AppSettings {
    var result = current
    if isPresent(.languageCode), let languageCode {
      result.languageCode = AppLanguage.normalize(languageCode)
    }
    if isPresent(.interfaceTheme), let interfaceTheme {
      result.interfaceTheme = Self.interfaceTheme(from: interfaceTheme, fallback: current.interfaceTheme)
    }
    if isPresent(.customInterfaceThemeColors), let customInterfaceThemeColors {
      result.customInterfaceThemeColors = customInterfaceThemeColors.mergeInto(result.customInterfaceThemeColors)
    }
    if isPresent(.showTutorialOnLaunch), let showTutorialOnLaunch {
      result.showTutorialOnLaunch = showTutorialOnLaunch
    }
    if isPresent(.vibrationEnabled), let vibrationEnabled { result.vibrationEnabled = vibrationEnabled }
    if isPresent(.shakeGestureEnabled), let shakeGestureEnabled { result.shakeGestureEnabled = shakeGestureEnabled }
    if isPresent(.shakeStrength), let shakeStrength {
      result.shakeStrength = ShakeStrength(rawValue: shakeStrength) ?? current.shakeStrength
    }
    if isPresent(.headphoneButtonRepeatEnabled), let headphoneButtonRepeatEnabled {
      result.headphoneButtonRepeatEnabled = headphoneButtonRepeatEnabled
    }
    if isPresent(.soundCuesEnabled), let soundCuesEnabled { result.soundCuesEnabled = soundCuesEnabled }
    if isPresent(.soundCueVolumePercent), let soundCueVolumePercent {
      result.soundCueVolume = min(max(Double(soundCueVolumePercent) / 100, 0), 1)
    }
    if isPresent(.soundCueTheme), let soundCueTheme {
      result.soundCueTheme = SoundCueTheme(rawValue: soundCueTheme) ?? current.soundCueTheme
    }
    if isPresent(.autoRecalculate), let autoRecalculate { result.autoRecalculate = autoRecalculate }
    if isPresent(.junctionAlerts), let junctionAlerts { result.junctionAlerts = junctionAlerts }
    if isPresent(.pedestrianCrossingAlerts), let pedestrianCrossingAlerts {
      result.pedestrianCrossingAlerts = pedestrianCrossingAlerts
    }
    if isPresent(.turnByTurnAnnouncements), let turnByTurnAnnouncements {
      result.turnByTurnAnnouncements = turnByTurnAnnouncements
    }
    if isPresent(.announcementCadenceMode), let announcementCadenceMode {
      result.announcementCadenceMode = AnnouncementCadenceMode(rawValue: announcementCadenceMode)
        ?? current.announcementCadenceMode
    }
    if isPresent(.searchRadiusKilometers), let searchRadiusKilometers {
      result.searchRadiusKilometers = min(
        max(searchRadiusKilometers, SharedProductRules.Search.minimumRadiusKm),
        SharedProductRules.Search.maximumRadiusKm
      )
    }
    if isPresent(.searchResultLimit), let searchResultLimit {
      result.searchResultLimit = min(
        max(searchResultLimit, SharedProductRules.Search.minimumResultLimit),
        SharedProductRules.Search.maximumResultLimit
      )
    }
    if isPresent(.nearbyPOICacheMode), let nearbyPOICacheMode {
      result.nearbyPOICacheMode = Self.nearbyPOICacheMode(
        from: nearbyPOICacheMode,
        fallback: current.nearbyPOICacheMode
      )
    }
    if isPresent(.nearbyPOICacheRadiusKilometers), let nearbyPOICacheRadiusKilometers {
      result.nearbyPOICacheRadiusKilometers = min(max(nearbyPOICacheRadiusKilometers, 1), 5)
    }
    if isPresent(.speechMode), let speechMode {
      switch speechMode.lowercased() {
      case "screenreader", "screen_reader", "voiceover":
        result.speechMode = .voiceOver
      case "system", "speechsynthesizer":
        result.speechMode = .speechSynthesizer
      default:
        break
      }
    }
    let hasVoiceValue = isPresent(.selectedSpeechVoiceIdentifier)
    if hasVoiceValue || isPresent(.selectedSpeechVoicePlatform) {
      if selectedSpeechVoicePlatform == nil || selectedSpeechVoicePlatform?.lowercased() == "ios" {
        if hasVoiceValue {
          result.selectedSpeechVoiceIdentifier = selectedSpeechVoiceIdentifier
        }
      } else if isPresent(.selectedSpeechVoicePlatform) {
        result.selectedSpeechVoiceIdentifier = nil
      }
    }
    if isPresent(.speechRatePercent), let speechRatePercent {
      result.speechRate = min(max(Double(speechRatePercent) / 100, 0.4), 1.6)
    }
    if isPresent(.speechVolumePercent), let speechVolumePercent {
      result.speechVolume = min(max(Double(speechVolumePercent) / 100, 0.1), 1.0)
    }
    return result
  }

  private func isPresent(_ key: CodingKeys) -> Bool {
    presentKeys.contains(key.rawValue)
  }

  private static func interfaceTheme(from rawValue: String, fallback: InterfaceTheme) -> InterfaceTheme {
    switch rawValue.replacingOccurrences(of: "_", with: "").lowercased() {
    case "system": return .system
    case "light": return .light
    case "dark": return .dark
    case "highcontrast": return .highContrast
    case "custom": return .custom
    default: return fallback
    }
  }

  private static func nearbyPOICacheMode(
    from rawValue: String,
    fallback: NearbyPOICacheMode
  ) -> NearbyPOICacheMode {
    switch rawValue.replacingOccurrences(of: "_", with: "").lowercased() {
    case "enabled": return .enabled
    case "wifionly": return .wifiOnly
    case "disabled": return .disabled
    default: return fallback
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case languageCode
    case interfaceTheme
    case customInterfaceThemeColors
    case showTutorialOnLaunch
    case vibrationEnabled
    case shakeGestureEnabled
    case shakeStrength
    case headphoneButtonRepeatEnabled
    case soundCuesEnabled
    case soundCueVolumePercent
    case soundCueTheme
    case autoRecalculate
    case junctionAlerts
    case pedestrianCrossingAlerts
    case turnByTurnAnnouncements
    case announcementCadenceMode
    case searchRadiusKilometers
    case searchResultLimit
    case nearbyPOICacheMode
    case nearbyPOICacheRadiusKilometers
    case updateChannel
    case speechMode
    case selectedSpeechVoicePlatform
    case selectedSpeechVoiceIdentifier
    case speechRatePercent
    case speechVolumePercent
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(languageCode, forKey: .languageCode)
    try container.encodeIfPresent(interfaceTheme, forKey: .interfaceTheme)
    try container.encodeIfPresent(customInterfaceThemeColors, forKey: .customInterfaceThemeColors)
    try container.encodeIfPresent(showTutorialOnLaunch, forKey: .showTutorialOnLaunch)
    try container.encodeIfPresent(vibrationEnabled, forKey: .vibrationEnabled)
    try container.encodeIfPresent(shakeGestureEnabled, forKey: .shakeGestureEnabled)
    try container.encodeIfPresent(shakeStrength, forKey: .shakeStrength)
    try container.encodeIfPresent(headphoneButtonRepeatEnabled, forKey: .headphoneButtonRepeatEnabled)
    try container.encodeIfPresent(soundCuesEnabled, forKey: .soundCuesEnabled)
    try container.encodeIfPresent(soundCueVolumePercent, forKey: .soundCueVolumePercent)
    try container.encodeIfPresent(soundCueTheme, forKey: .soundCueTheme)
    try container.encodeIfPresent(autoRecalculate, forKey: .autoRecalculate)
    try container.encodeIfPresent(junctionAlerts, forKey: .junctionAlerts)
    try container.encodeIfPresent(pedestrianCrossingAlerts, forKey: .pedestrianCrossingAlerts)
    try container.encodeIfPresent(turnByTurnAnnouncements, forKey: .turnByTurnAnnouncements)
    try container.encodeIfPresent(announcementCadenceMode, forKey: .announcementCadenceMode)
    try container.encodeIfPresent(searchRadiusKilometers, forKey: .searchRadiusKilometers)
    try container.encodeIfPresent(searchResultLimit, forKey: .searchResultLimit)
    try container.encodeIfPresent(nearbyPOICacheMode, forKey: .nearbyPOICacheMode)
    try container.encodeIfPresent(nearbyPOICacheRadiusKilometers, forKey: .nearbyPOICacheRadiusKilometers)
    try container.encodeIfPresent(updateChannel, forKey: .updateChannel)
    try container.encodeIfPresent(speechMode, forKey: .speechMode)
    try container.encodeIfPresent(selectedSpeechVoicePlatform, forKey: .selectedSpeechVoicePlatform)
    if let selectedSpeechVoiceIdentifier {
      try container.encode(selectedSpeechVoiceIdentifier, forKey: .selectedSpeechVoiceIdentifier)
    } else {
      try container.encodeNil(forKey: .selectedSpeechVoiceIdentifier)
    }
    try container.encodeIfPresent(speechRatePercent, forKey: .speechRatePercent)
    try container.encodeIfPresent(speechVolumePercent, forKey: .speechVolumePercent)
  }
}

struct NaviLiveBackupRoute: Codable, Equatable {
  var placeID: String?
  var place: NaviLiveBackupPlace?
  var summary: RouteSummary?
}

struct NaviLiveBackupPayload: Codable, Equatable {
  static let currentSchemaVersion = 1

  var schemaVersion: Int = currentSchemaVersion
  var appName: String = "Navi Live"
  var createdAtISO8601: String?
  var settings: NaviLiveBackupSettings?
  var favorites: [NaviLiveBackupPlace]?
  var lastRoute: NaviLiveBackupRoute?
  var hasCompletedOnboarding: Bool?

  var hasAnyContent: Bool {
    settings != nil || favorites != nil || lastRoute != nil || hasCompletedOnboarding != nil
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case appName
    case createdAtISO8601
    case settings
    case favorites
    case lastRoute
    case hasCompletedOnboarding
  }

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? "Navi Live"
    createdAtISO8601 = try container.decodeIfPresent(String.self, forKey: .createdAtISO8601)
    settings = try container.decodeIfPresent(NaviLiveBackupSettings.self, forKey: .settings)
    favorites = try container.decodeIfPresent([NaviLiveBackupPlace].self, forKey: .favorites)
    lastRoute = try container.decodeIfPresent(NaviLiveBackupRoute.self, forKey: .lastRoute)
    hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
  }
}

enum NaviLiveBackupCodec {
  static let maxBackupBytes = 5 * 1024 * 1024

  static func makePayload(snapshot: PersistedSnapshot) -> NaviLiveBackupPayload {
    var payload = NaviLiveBackupPayload()
    payload.createdAtISO8601 = ISO8601DateFormatter().string(from: Date())
    payload.settings = NaviLiveBackupSettings(settings: snapshot.settings)
    payload.favorites = snapshot.favorites.map(NaviLiveBackupPlace.init)
    payload.lastRoute = NaviLiveBackupRoute(
      placeID: snapshot.lastRoutePlaceID ?? snapshot.lastRoutePlace?.id,
      place: snapshot.lastRoutePlace.map(NaviLiveBackupPlace.init),
      summary: snapshot.lastRouteSummary
    )
    payload.hasCompletedOnboarding = snapshot.hasCompletedOnboarding
    return payload
  }

  static func encode(payload: NaviLiveBackupPayload) throws -> Data {
    guard payload.hasAnyContent else { throw NaviLiveBackupError.noContent }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data: Data
    do {
      data = try encoder.encode(payload)
    } catch {
      throw NaviLiveBackupError.invalidFile
    }
    try validateBackupData(data)
    return data
  }

  static func decodePayload(_ data: Data) throws -> NaviLiveBackupPayload {
    try validateBackupData(data)
    let payload: NaviLiveBackupPayload
    do {
      payload = try JSONDecoder().decode(NaviLiveBackupPayload.self, from: data)
    } catch {
      throw NaviLiveBackupError.invalidFile
    }
    guard payload.schemaVersion >= 1 else { throw NaviLiveBackupError.invalidFile }
    guard payload.schemaVersion <= NaviLiveBackupPayload.currentSchemaVersion else {
      throw NaviLiveBackupError.newerSchema
    }
    guard payload.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || payload.appName.caseInsensitiveCompare("Navi Live") == .orderedSame else {
      throw NaviLiveBackupError.unsupportedApp
    }
    guard payload.hasAnyContent else { throw NaviLiveBackupError.noContent }
    return payload
  }

  static func validateBackupData(_ data: Data) throws {
    guard data.isEmpty == false else { throw NaviLiveBackupError.emptyFile }
    guard data.count <= maxBackupBytes else { throw NaviLiveBackupError.invalidFile }
    guard let object = try? JSONSerialization.jsonObject(with: data), object is [String: Any] else {
      throw NaviLiveBackupError.invalidFile
    }
  }
}

struct NaviLiveBackupDocument: FileDocument {
  static let defaultFilename = "Navi-Live-backup.json"
  static var readableContentTypes: [UTType] { [.json] }

  let data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw NaviLiveBackupError.invalidFile
    }
    _ = try NaviLiveBackupCodec.decodePayload(data)
    self.data = data
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    _ = try NaviLiveBackupCodec.decodePayload(data)
    return FileWrapper(regularFileWithContents: data)
  }

  static func readData(from url: URL) throws -> Data {
    let needsAccess = url.startAccessingSecurityScopedResource()
    defer {
      if needsAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }
    if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
       let fileSize = resourceValues.fileSize,
       fileSize > NaviLiveBackupCodec.maxBackupBytes {
      throw NaviLiveBackupError.invalidFile
    }
    let data = try Data(contentsOf: url)
    _ = try NaviLiveBackupCodec.decodePayload(data)
    return data
  }
}
