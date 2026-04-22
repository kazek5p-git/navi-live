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
  static func text(_ key: String, table: StringTable = .general) -> String {
    NSLocalizedString(key, tableName: table.rawValue, bundle: .main, comment: "")
  }

  static func text(_ key: String, table: StringTable = .general, _ args: CVarArg...) -> String {
    let format = text(key, table: table)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}
