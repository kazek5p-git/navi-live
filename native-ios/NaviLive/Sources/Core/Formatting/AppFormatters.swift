import Foundation

enum AppFormatters {
  static func distance(_ meters: Int) -> String {
    if meters >= 1000 {
      return String(format: "%.1f km", locale: Locale.current, Double(meters) / 1000.0)
    }
    return "\(meters) m"
  }

  static func eta(minutes: Int) -> String {
    if minutes <= 1 {
      return L10n.text("formatter.minute.one")
    }
    return L10n.text("formatter.minute.other", minutes)
  }

  static func accuracy(_ meters: Double?) -> String {
    guard let meters else {
      return L10n.text("formatter.accuracy.unknown")
    }
    return L10n.text("formatter.accuracy.value", Int(meters.rounded()))
  }
}
