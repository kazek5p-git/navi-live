import Foundation

enum StringTable: String {
  case general = "General"
  case root = "Root"
  case home = "Home"
  case navigation = "Navigation"
  case onboarding = "Onboarding"
  case settings = "Settings"
}

enum L10n {
  static var selectedLanguageCode = ""

  static var currentLocale: Locale {
    AppLanguage.locale(for: selectedLanguageCode)
  }

  static var acceptLanguageTag: String {
    AppLanguage.acceptLanguageTag(for: selectedLanguageCode)
  }

  static func text(_ key: String, table: StringTable = .general) -> String {
    let selectedBundle = AppLanguage.bundle(for: selectedLanguageCode)
    let localized = selectedBundle.localizedString(
      forKey: key,
      value: nil,
      table: table.rawValue
    )
    guard localized == key else { return localized }

    // Nowe elementy mogą być jeszcze nieobecne w starszym pliku językowym.
    return AppLanguage.bundle(for: "en").localizedString(
      forKey: key,
      value: key,
      table: table.rawValue
    )
  }

  static func text(_ key: String, table: StringTable = .general, _ args: CVarArg...) -> String {
    let format = text(key, table: table)
    return String(format: format, locale: currentLocale, arguments: args)
  }
}

enum AppLanguage {
  static let systemLanguageCode = ""

  static let supportedCodes = [
    "en",
    "pl",
    "ru",
    "uk",
    "ar",
    "fa",
    "tr",
    "de",
    "fr",
    "es",
    "it",
    "pt",
    "ro",
    "cs",
    "sk",
    "be",
    "lt",
    "lv",
    "et",
    "hu",
    "fi",
    "hr",
    "sr",
    "el",
    "bn",
    "hi",
    "id",
    "vi",
    "zh-Hans",
    "ja",
    "ko",
    "ckb"
  ]

  static func normalize(_ code: String?) -> String {
    let trimmed = code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return systemLanguageCode }
    return supportedCodes.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? systemLanguageCode
  }

  static func bundle(for code: String) -> Bundle {
    let normalized = normalize(code)
    guard !normalized.isEmpty,
          let path = Bundle.main.path(forResource: normalized, ofType: "lproj"),
          let bundle = Bundle(path: path) else {
      return .main
    }
    return bundle
  }

  static func locale(for code: String) -> Locale {
    let normalized = normalize(code)
    guard !normalized.isEmpty else { return .autoupdatingCurrent }
    return Locale(identifier: normalized.replacingOccurrences(of: "-", with: "_"))
  }

  static func acceptLanguageTag(for code: String) -> String {
    let normalized = normalize(code)
    if normalized.isEmpty {
      return Locale.autoupdatingCurrent.identifier.replacingOccurrences(of: "_", with: "-")
    }
    return normalized
  }

  static func displayName(for code: String, in displayLocale: Locale = L10n.currentLocale) -> String {
    let normalized = normalize(code)
    guard !normalized.isEmpty else { return "" }
    return displayLocale.localizedString(forIdentifier: normalized) ?? normalized
  }
}
