import SwiftUI

struct InterfaceThemeSettingsView: View {
  @ObservedObject var model: AppModel
  @State private var customColors: InterfaceThemeColors

  init(model: AppModel) {
    self.model = model
    _customColors = State(initialValue: model.settings.customInterfaceThemeColors)
  }

  var body: some View {
    Form {
      Section {
        Picker(
          L10n.text("settings.view.theme", table: .settings),
          selection: Binding(
            get: { model.settings.interfaceTheme },
            set: model.updateInterfaceTheme
          )
        ) {
          ForEach(InterfaceTheme.allCases, id: \.self) { theme in
            Text(themeLabel(theme)).tag(theme)
          }
        }
        .accessibilityValue(Text(themeLabel(model.settings.interfaceTheme)))

        Text(L10n.text("settings.view.accessibility_note", table: .settings))
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }

      if model.settings.interfaceTheme == .custom {
        Section {
          ThemeColorPickerRow(
            title: L10n.text("settings.view.color.background", table: .settings),
            selection: colorBinding(\.backgroundHex)
          )
          ThemeColorPickerRow(
            title: L10n.text("settings.view.color.surface", table: .settings),
            selection: colorBinding(\.surfaceHex)
          )
          ThemeColorPickerRow(
            title: L10n.text("settings.view.color.primary_text", table: .settings),
            selection: colorBinding(\.primaryTextHex)
          )
          ThemeColorPickerRow(
            title: L10n.text("settings.view.color.secondary_text", table: .settings),
            selection: colorBinding(\.secondaryTextHex)
          )
          ThemeColorPickerRow(
            title: L10n.text("settings.view.color.accent", table: .settings),
            selection: colorBinding(\.accentHex)
          )
          ThemeColorPickerRow(
            title: L10n.text("settings.view.color.outline", table: .settings),
            selection: colorBinding(\.outlineHex)
          )

          Text(L10n.text("settings.view.hex_hint", table: .settings))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

          Button(role: .destructive) {
            customColors = InterfaceThemeColors()
            model.updateCustomInterfaceThemeColors(customColors)
          } label: {
            Text(L10n.text("settings.view.reset", table: .settings))
          }
        }
      }

      Section(L10n.text("settings.view.preview", table: .settings)) {
        InterfaceThemePreview(
          theme: model.settings.interfaceTheme,
          customColors: model.settings.customInterfaceThemeColors
        )
      }
    }
    .navigationTitle(L10n.text("settings.section.view", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: model.settings.customInterfaceThemeColors) { newColors in
      if newColors != customColors {
        customColors = newColors
      }
    }
  }

  private func themeLabel(_ theme: InterfaceTheme) -> String {
    switch theme {
    case .system:
      return L10n.text("settings.view.theme.system", table: .settings)
    case .light:
      return L10n.text("settings.view.theme.light", table: .settings)
    case .dark:
      return L10n.text("settings.view.theme.dark", table: .settings)
    case .highContrast:
      return L10n.text("settings.view.theme.high_contrast", table: .settings)
    case .custom:
      return L10n.text("settings.view.theme.custom", table: .settings)
    }
  }

  private func colorBinding(
    _ keyPath: WritableKeyPath<InterfaceThemeColors, String>
  ) -> Binding<Color> {
    Binding(
      get: {
        let value = customColors[keyPath: keyPath]
        return Color(
          uiColor: NaviLiveThemeColorSupport.color(hex: value, fallback: .systemBlue)
        )
      },
      set: { newColor in
        var updated = customColors
        updated[keyPath: keyPath] = NaviLiveThemeColorSupport.hex(from: UIColor(newColor))
        customColors = updated
        model.updateCustomInterfaceThemeColors(updated)
      }
    )
  }
}

private struct ThemeColorPickerRow: View {
  let title: String
  @Binding var selection: Color

  var body: some View {
    ColorPicker(title, selection: $selection, supportsOpacity: false)
  }
}

private struct InterfaceThemePreview: View {
  let theme: InterfaceTheme
  let customColors: InterfaceThemeColors

  var body: some View {
    let palette = theme.palette(customColors: customColors)
    HStack(spacing: 12) {
      Circle()
        .fill(palette.accent)
        .frame(width: 30, height: 30)
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(palette.surface)
        .frame(height: 42)
        .overlay {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(palette.outline, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
          Text("Aa  Navi Live")
            .font(.body.weight(.semibold))
            .foregroundStyle(palette.primary)
            .padding(.horizontal, 14)
        }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
    .accessibilityHidden(true)
  }
}
