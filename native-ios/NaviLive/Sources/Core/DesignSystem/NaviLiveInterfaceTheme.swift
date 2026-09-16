import SwiftUI
import UIKit

struct NaviLiveThemePalette {
  let background: Color
  let surface: Color
  let primary: Color
  let secondary: Color
  let accent: Color
  let outline: Color

  fileprivate let backgroundUIColor: UIColor
  fileprivate let surfaceUIColor: UIColor
  fileprivate let primaryUIColor: UIColor
  fileprivate let secondaryUIColor: UIColor
  fileprivate let accentUIColor: UIColor
  fileprivate let outlineUIColor: UIColor

  init(
    background: UIColor,
    surface: UIColor,
    primary: UIColor,
    secondary: UIColor,
    accent: UIColor,
    outline: UIColor
  ) {
    backgroundUIColor = background
    surfaceUIColor = surface
    primaryUIColor = primary
    secondaryUIColor = secondary
    accentUIColor = accent
    outlineUIColor = outline
    self.background = Color(uiColor: background)
    self.surface = Color(uiColor: surface)
    self.primary = Color(uiColor: primary)
    self.secondary = Color(uiColor: secondary)
    self.accent = Color(uiColor: accent)
    self.outline = Color(uiColor: outline)
  }
}

extension InterfaceTheme {
  func preferredColorScheme(customColors: InterfaceThemeColors) -> ColorScheme? {
    switch self {
    case .system:
      return nil
    case .light:
      return .light
    case .dark, .highContrast:
      return .dark
    case .custom:
      let background = NaviLiveThemeColorSupport.color(
        hex: customColors.backgroundHex,
        fallback: .white
      )
      return NaviLiveThemeColorSupport.isDark(background) ? .dark : .light
    }
  }

  func palette(customColors: InterfaceThemeColors) -> NaviLiveThemePalette {
    switch self {
    case .system:
      return NaviLiveThemePalette(
        background: .systemGroupedBackground,
        surface: .secondarySystemGroupedBackground,
        primary: .label,
        secondary: .secondaryLabel,
        accent: .systemBlue,
        outline: .separator
      )
    case .light:
      return NaviLiveThemePalette(
        background: NaviLiveThemeColorSupport.color(hex: "#F5F9FF", fallback: .systemGroupedBackground),
        surface: NaviLiveThemeColorSupport.color(hex: "#FFFFFF", fallback: .secondarySystemGroupedBackground),
        primary: NaviLiveThemeColorSupport.color(hex: "#101418", fallback: .label),
        secondary: NaviLiveThemeColorSupport.color(hex: "#40464E", fallback: .secondaryLabel),
        accent: NaviLiveThemeColorSupport.color(hex: "#065EA8", fallback: .systemBlue),
        outline: NaviLiveThemeColorSupport.color(hex: "#9AA8B8", fallback: .separator)
      )
    case .dark:
      return NaviLiveThemePalette(
        background: NaviLiveThemeColorSupport.color(hex: "#111418", fallback: .black),
        surface: NaviLiveThemeColorSupport.color(hex: "#1B2026", fallback: .secondarySystemBackground),
        primary: NaviLiveThemeColorSupport.color(hex: "#E1E2E5", fallback: .white),
        secondary: NaviLiveThemeColorSupport.color(hex: "#C1C7D0", fallback: .lightGray),
        accent: NaviLiveThemeColorSupport.color(hex: "#8EC5FF", fallback: .systemBlue),
        outline: NaviLiveThemeColorSupport.color(hex: "#737B86", fallback: .gray)
      )
    case .highContrast:
      return NaviLiveThemePalette(
        background: .black,
        surface: .black,
        primary: .white,
        secondary: .white,
        accent: NaviLiveThemeColorSupport.color(hex: "#FFD600", fallback: .yellow),
        outline: NaviLiveThemeColorSupport.color(hex: "#FFD600", fallback: .yellow)
      )
    case .custom:
      let background = NaviLiveThemeColorSupport.color(
        hex: customColors.backgroundHex,
        fallback: NaviLiveThemeColorSupport.color(hex: "#F5F9FF", fallback: .systemGroupedBackground)
      )
      let surface = NaviLiveThemeColorSupport.color(
        hex: customColors.surfaceHex,
        fallback: NaviLiveThemeColorSupport.color(hex: "#FFFFFF", fallback: .secondarySystemGroupedBackground)
      )
      let primary = NaviLiveThemeColorSupport.color(
        hex: customColors.primaryTextHex,
        fallback: NaviLiveThemeColorSupport.color(hex: "#101418", fallback: .label)
      )
      let secondary = NaviLiveThemeColorSupport.color(
        hex: customColors.secondaryTextHex,
        fallback: NaviLiveThemeColorSupport.color(hex: "#40464E", fallback: .secondaryLabel)
      )
      return NaviLiveThemePalette(
        background: background,
        surface: surface,
        primary: NaviLiveThemeColorSupport.accessibleTextColor(primary, on: [background, surface]),
        secondary: NaviLiveThemeColorSupport.accessibleTextColor(secondary, on: [surface, background]),
        accent: NaviLiveThemeColorSupport.color(
          hex: customColors.accentHex,
          fallback: NaviLiveThemeColorSupport.color(hex: "#065EA8", fallback: .systemBlue)
        ),
        outline: NaviLiveThemeColorSupport.color(
          hex: customColors.outlineHex,
          fallback: NaviLiveThemeColorSupport.color(hex: "#9AA8B8", fallback: .separator)
        )
      )
    }
  }
}

enum NaviLiveThemeColorSupport {
  static func color(hex: String, fallback: UIColor) -> UIColor {
    let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.count == 7, value.first == "#" else { return fallback }
    let digits = String(value.dropFirst())
    guard let number = UInt64(digits, radix: 16) else { return fallback }
    return UIColor(
      red: CGFloat((number >> 16) & 0xFF) / 255,
      green: CGFloat((number >> 8) & 0xFF) / 255,
      blue: CGFloat(number & 0xFF) / 255,
      alpha: 1
    )
  }

  static func hex(from color: UIColor) -> String {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return "#065EA8"
    }
    return String(
      format: "#%02lX%02lX%02lX",
      lround(Double(red * 255)),
      lround(Double(green * 255)),
      lround(Double(blue * 255))
    )
  }

  static func isDark(_ color: UIColor) -> Bool {
    relativeLuminance(color) < 0.5
  }

  static func accessibleTextColor(_ preferred: UIColor, on backgrounds: [UIColor]) -> UIColor {
    guard !backgrounds.isEmpty else { return preferred }
    let preferredContrast = backgrounds.map { contrastRatio(preferred, $0) }.min() ?? 0
    guard preferredContrast < 4.5 else { return preferred }

    let candidates: [UIColor] = [.black, .white]
    return candidates.max { left, right in
      let leftContrast = backgrounds.map { contrastRatio(left, $0) }.min() ?? 0
      let rightContrast = backgrounds.map { contrastRatio(right, $0) }.min() ?? 0
      return leftContrast < rightContrast
    } ?? preferred
  }

  static func contrastRatio(_ first: UIColor, _ second: UIColor) -> Double {
    let firstLuminance = relativeLuminance(first)
    let secondLuminance = relativeLuminance(second)
    let lighter = max(firstLuminance, secondLuminance)
    let darker = min(firstLuminance, secondLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  private static func relativeLuminance(_ color: UIColor) -> Double {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return 0.5
    }

    func linearize(_ channel: CGFloat) -> Double {
      let value = Double(channel)
      return value <= 0.03928
        ? value / 12.92
        : pow((value + 0.055) / 1.055, 2.4)
    }

    return (0.2126 * linearize(red)) +
      (0.7152 * linearize(green)) +
      (0.0722 * linearize(blue))
  }
}

private struct NaviLiveThemeEnvironmentKey: EnvironmentKey {
  static let defaultValue = InterfaceTheme.system.palette(customColors: .init())
}

extension EnvironmentValues {
  var naviLiveThemePalette: NaviLiveThemePalette {
    get { self[NaviLiveThemeEnvironmentKey.self] }
    set { self[NaviLiveThemeEnvironmentKey.self] = newValue }
  }
}

extension View {
  func naviLiveInterfaceTheme(
    _ theme: InterfaceTheme,
    customColors: InterfaceThemeColors
  ) -> some View {
    modifier(NaviLiveInterfaceThemeModifier(theme: theme, customColors: customColors))
  }
}

private struct NaviLiveInterfaceThemeModifier: ViewModifier {
  let theme: InterfaceTheme
  let customColors: InterfaceThemeColors

  func body(content: Content) -> some View {
    let palette = theme.palette(customColors: customColors)
    content
      .environment(\.naviLiveThemePalette, palette)
      .tint(palette.accent)
      .foregroundStyle(palette.primary)
      .background(palette.background.ignoresSafeArea())
      .preferredColorScheme(theme.preferredColorScheme(customColors: customColors))
      .onAppear {
        NaviLiveUIKitAppearance.apply(theme: theme, palette: palette)
      }
      .onChange(of: theme) { newTheme in
        NaviLiveUIKitAppearance.apply(
          theme: newTheme,
          palette: newTheme.palette(customColors: customColors)
        )
      }
      .onChange(of: customColors) { newColors in
        NaviLiveUIKitAppearance.apply(
          theme: theme,
          palette: theme.palette(customColors: newColors)
        )
      }
  }
}

enum NaviLiveUIKitAppearance {
  static func apply(theme: InterfaceTheme, palette: NaviLiveThemePalette) {
    let isSystem = theme == .system
    UIView.appearance().tintColor = isSystem ? nil : palette.accentUIColor
    UINavigationBar.appearance().tintColor = isSystem ? nil : palette.accentUIColor
    UINavigationBar.appearance().barTintColor = isSystem ? nil : palette.surfaceUIColor
    UITableView.appearance().backgroundColor = isSystem ? nil : palette.backgroundUIColor
    UITableViewCell.appearance().backgroundColor = isSystem ? nil : palette.surfaceUIColor
    UISwitch.appearance().onTintColor = isSystem ? nil : palette.accentUIColor
    UIProgressView.appearance().progressTintColor = isSystem ? nil : palette.accentUIColor

    if #available(iOS 13.0, *) {
      let navigationAppearance = UINavigationBarAppearance()
      if isSystem {
        navigationAppearance.configureWithDefaultBackground()
      } else {
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = palette.surfaceUIColor
        navigationAppearance.titleTextAttributes = [.foregroundColor: palette.primaryUIColor]
        navigationAppearance.largeTitleTextAttributes = [.foregroundColor: palette.primaryUIColor]
      }
      UINavigationBar.appearance().standardAppearance = navigationAppearance
      if #available(iOS 15.0, *) {
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
      }
    }

    applyToVisibleWindows(theme: theme, palette: palette)
  }

  private static func applyToVisibleWindows(theme: InterfaceTheme, palette: NaviLiveThemePalette) {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .filter { !$0.isHidden }

    for window in windows {
      window.tintColor = theme == .system ? nil : palette.accentUIColor
      window.overrideUserInterfaceStyle = theme.userInterfaceStyle(for: palette)
      window.backgroundColor = palette.backgroundUIColor
    }
  }
}

private extension InterfaceTheme {
  func userInterfaceStyle(for palette: NaviLiveThemePalette) -> UIUserInterfaceStyle {
    switch self {
    case .system:
      return .unspecified
    case .light:
      return .light
    case .dark, .highContrast:
      return .dark
    case .custom:
      return NaviLiveThemeColorSupport.isDark(palette.backgroundUIColor) ? .dark : .light
    }
  }
}
