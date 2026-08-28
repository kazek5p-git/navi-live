import AVFoundation
import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        NavigationLink {
          GuidanceSettingsDetailView(model: model)
        } label: {
          SettingsGroupRow(
            title: L10n.text("settings.section.guidance", table: .settings),
            systemImage: "figure.walk"
          )
        }

        NavigationLink {
          LocalSearchSettingsDetailView(model: model)
        } label: {
          SettingsGroupRow(
            title: L10n.text("settings.section.local_search", table: .settings),
            systemImage: "magnifyingglass.circle"
          )
        }

        NavigationLink {
          SoundSettingsDetailView(model: model)
        } label: {
          SettingsGroupRow(
            title: L10n.text("settings.section.sounds", table: .settings),
            systemImage: "speaker.wave.3"
          )
        }

        NavigationLink {
          SpeechSettingsDetailView(model: model)
        } label: {
          SettingsGroupRow(
            title: L10n.text("settings.section.speech", table: .settings),
            systemImage: "speaker.wave.2"
          )
        }

        NavigationLink {
          WhatsNewView(model: model)
        } label: {
          SettingsGroupRow(
            title: L10n.text("settings.whats_new.title", table: .settings),
            systemImage: "sparkles"
          )
        }

        NavigationLink {
          AppSettingsDetailView(model: model)
        } label: {
          SettingsGroupRow(
            title: L10n.text("settings.group.app_updates", table: .settings),
            systemImage: "gearshape"
          )
        }

        NavigationLink {
          HelpPrivacyView()
        } label: {
          SettingsGroupRow(
            title: L10n.text("help.title", table: .settings),
            systemImage: "questionmark.circle"
          )
        }
      }
    }
    .navigationTitle(L10n.text("settings.title", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct WhatsNewView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        LabeledContent(
          L10n.text("settings.whats_new.version", table: .settings),
          value: model.appVersionLabel
        )
        Text(L10n.text("settings.whats_new.intro", table: .settings))
          .foregroundStyle(.secondary)
      }

      Section {
        WhatsNewItem(key: "settings.whats_new.guidance")
        WhatsNewItem(key: "settings.whats_new.search")
        WhatsNewItem(key: "settings.whats_new.accessibility")
        WhatsNewItem(key: "settings.whats_new.location")
      }
    }
    .navigationTitle(L10n.text("settings.whats_new.title", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct WhatsNewItem: View {
  let key: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Text("•")
        .foregroundStyle(Color.accentColor)
        .accessibilityHidden(true)
      Text(L10n.text(key, table: .settings))
    }
    .accessibilityElement(children: .combine)
  }
}

private struct SettingsGroupRow: View {
  let title: String
  let systemImage: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(Color.accentColor)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}

private struct LocalSearchSettingsDetailView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        RadiusAdjustableStepperRow(
          title: L10n.text("settings.local_search.search_radius.title", table: .settings),
          value: model.settings.searchRadiusKilometers,
          range: SharedProductRules.Search.minimumRadiusKm...SharedProductRules.Search.maximumRadiusKm,
          onChange: model.updateSearchRadiusKilometers
        )

        SearchResultLimitAdjustableStepperRow(
          title: L10n.text("settings.local_search.results.title", table: .settings),
          value: model.settings.searchResultLimit,
          range: SharedProductRules.Search.minimumResultLimit...SharedProductRules.Search.maximumResultLimit,
          onChange: model.updateSearchResultLimit
        )

        Picker(
          L10n.text("settings.local_search.mode", table: .settings),
          selection: Binding(
            get: { model.settings.nearbyPOICacheMode },
            set: model.updateNearbyPOICacheMode
          )
        ) {
          ForEach(NearbyPOICacheMode.allCases, id: \.self) { mode in
            Text(modeLabel(mode)).tag(mode)
          }
        }

        RadiusAdjustableStepperRow(
          title: L10n.text("settings.local_search.cache_radius.title", table: .settings),
          value: model.settings.nearbyPOICacheRadiusKilometers,
          range: SharedProductRules.Search.minimumRadiusKm...5,
          onChange: model.updateNearbyPOICacheRadiusKilometers
        )
        .disabled(model.settings.nearbyPOICacheMode == .disabled)
      }

      Section {
        Text(statusText)
        Button(L10n.text("settings.local_search.refresh_now", table: .settings)) {
          model.refreshNearbyPOICacheNow()
        }
        .disabled(model.settings.nearbyPOICacheMode == .disabled || model.nearbyPOICacheState.isRefreshing)

        Button(role: .destructive) {
          model.clearNearbyPOICache()
        } label: {
          Text(L10n.text("settings.local_search.clear", table: .settings))
        }
        .disabled(model.nearbyPOICacheState.cachedPlaceCount == 0 || model.nearbyPOICacheState.isRefreshing)
      }
    }
    .navigationTitle(L10n.text("settings.section.local_search", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var statusText: String {
    if model.nearbyPOICacheState.isRefreshing {
      return L10n.text("settings.local_search.status.refreshing", table: .settings)
    }
    if model.nearbyPOICacheState.cachedPlaceCount > 0 {
      return L10n.text(
        "settings.local_search.status.saved",
        table: .settings,
        model.nearbyPOICacheState.cachedPlaceCount
      )
    }
    return L10n.text("settings.local_search.status.empty", table: .settings)
  }

  private func modeLabel(_ mode: NearbyPOICacheMode) -> String {
    switch mode {
    case .enabled:
      return L10n.text("settings.local_search.mode.enabled", table: .settings)
    case .wifiOnly:
      return L10n.text("settings.local_search.mode.wifi_only", table: .settings)
    case .disabled:
      return L10n.text("settings.local_search.mode.disabled", table: .settings)
    }
  }
}

private struct RadiusAdjustableStepperRow: View {
  let title: String
  let value: Int
  let range: ClosedRange<Int>
  let onChange: (Int) -> Void

  var body: some View {
    Stepper(
      value: Binding(
        get: { value },
        set: { onChange(clamp($0)) }
      ),
      in: range
    ) {
      HStack {
        Text(title)
        Spacer()
        Text(valueText)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(valueText)
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        onChange(clamp(value + 1))
      case .decrement:
        onChange(clamp(value - 1))
      @unknown default:
        break
      }
    }
  }

  private var valueText: String {
    L10n.text("settings.local_search.radius.km_value", table: .settings, value)
  }

  private func clamp(_ incoming: Int) -> Int {
    min(max(incoming, range.lowerBound), range.upperBound)
  }
}

private struct SearchResultLimitAdjustableStepperRow: View {
  let title: String
  let value: Int
  let range: ClosedRange<Int>
  let onChange: (Int) -> Void

  var body: some View {
    Stepper(
      value: Binding(
        get: { value },
        set: { onChange(clamp($0)) }
      ),
      in: range
    ) {
      HStack {
        Text(title)
        Spacer()
        Text(valueText)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(valueText)
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        onChange(clamp(value + 1))
      case .decrement:
        onChange(clamp(value - 1))
      @unknown default:
        break
      }
    }
  }

  private var valueText: String {
    L10n.text("settings.local_search.results.value", table: .settings, value)
  }

  private func clamp(_ incoming: Int) -> Int {
    min(max(incoming, range.lowerBound), range.upperBound)
  }
}

private struct GuidanceSettingsDetailView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        Toggle(
          L10n.text("settings.toggle.turn_announcements", table: .settings),
          isOn: Binding(
            get: { model.settings.turnByTurnAnnouncements },
            set: model.updateTurnByTurnAnnouncements
          )
        )

        Picker(
          L10n.text("settings.guidance.cadence", table: .settings),
          selection: Binding(
            get: { model.settings.announcementCadenceMode },
            set: model.updateAnnouncementCadenceMode
          )
        ) {
          ForEach(AnnouncementCadenceMode.allCases, id: \.self) { mode in
            Text(announcementCadenceLabel(mode)).tag(mode)
          }
        }
        .disabled(!model.settings.turnByTurnAnnouncements)

        Toggle(
          L10n.text("settings.toggle.auto_recalculate", table: .settings),
          isOn: Binding(
            get: { model.settings.autoRecalculate },
            set: model.updateAutoRecalculate
          )
        )

        Toggle(
          L10n.text("settings.toggle.junction_alerts", table: .settings),
          isOn: Binding(
            get: { model.settings.junctionAlerts },
            set: model.updateJunctionAlerts
          )
        )

        Toggle(
          L10n.text("settings.toggle.pedestrian_crossing_alerts", table: .settings),
          isOn: Binding(
            get: { model.settings.pedestrianCrossingAlerts },
            set: model.updatePedestrianCrossingAlerts
          )
        )

        Toggle(
          L10n.text("settings.toggle.vibration", table: .settings),
          isOn: Binding(
            get: { model.settings.vibrationEnabled },
            set: model.updateVibrationEnabled
          )
        )

        Toggle(
          L10n.text("settings.toggle.shake_gesture", table: .settings),
          isOn: Binding(
            get: { model.settings.shakeGestureEnabled },
            set: model.updateShakeGestureEnabled
          )
        )

        Picker(
          L10n.text("settings.shake.strength", table: .settings),
          selection: Binding(
            get: { model.settings.shakeStrength },
            set: model.updateShakeStrength
          )
        ) {
          ForEach(ShakeStrength.allCases, id: \.self) { strength in
            Text(shakeStrengthLabel(strength)).tag(strength)
          }
        }
        .disabled(!model.settings.shakeGestureEnabled)

        Toggle(
          L10n.text("settings.toggle.headphone_button_repeat", table: .settings),
          isOn: Binding(
            get: { model.settings.headphoneButtonRepeatEnabled },
            set: model.updateHeadphoneButtonRepeatEnabled
          )
        )
      }
    }
    .navigationTitle(L10n.text("settings.section.guidance", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func announcementCadenceLabel(_ mode: AnnouncementCadenceMode) -> String {
    switch mode {
    case .distance:
      return L10n.text("settings.guidance.cadence.distance", table: .settings)
    case .time:
      return L10n.text("settings.guidance.cadence.time", table: .settings)
    }
  }

  private func shakeStrengthLabel(_ strength: ShakeStrength) -> String {
    switch strength {
    case .light:
      return L10n.text("settings.shake.strength.light", table: .settings)
    case .medium:
      return L10n.text("settings.shake.strength.medium", table: .settings)
    case .strong:
      return L10n.text("settings.shake.strength.strong", table: .settings)
    }
  }
}

private struct SoundSettingsDetailView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        Toggle(
          L10n.text("settings.toggle.sound_cues", table: .settings),
          isOn: Binding(
            get: { model.settings.soundCuesEnabled },
            set: model.updateSoundCuesEnabled
          )
        )
      }

      Section {
        SoundCueThemeMenuRow(model: model)
      }

      Section {
        SpeechSliderRow(
          title: L10n.text("settings.sound_cues.volume", table: .settings),
          value: Binding(
            get: { model.settings.soundCueVolume },
            set: model.updateSoundCueVolume
          ),
          range: 0.0...1.0,
          step: 0.05
        )
        .disabled(!model.settings.soundCuesEnabled)
      }

      Section {
        ForEach(SoundCuePreviewItem.allCases) { item in
          Button {
            model.previewSoundCue(item.cue)
          } label: {
            Label {
              VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(item.titleKey, table: .settings))
                Text(L10n.text(item.messageKey, table: .settings))
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: item.systemImage)
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            Text(L10n.text("settings.sound_cue.preview.accessibility", table: .settings, L10n.text(item.titleKey, table: .settings)))
          )
          .accessibilityHint(Text(L10n.text(item.messageKey, table: .settings)))
        }
      }
    }
    .navigationTitle(L10n.text("settings.section.sounds", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct SoundCueThemeMenuRow: View {
  @ObservedObject var model: AppModel

  var body: some View {
    let title = L10n.text("settings.sound_theme.title", table: .settings)
    let selectedLabel = soundCueThemeLabel(model.settings.soundCueTheme)

    Menu {
      ForEach(SoundCueTheme.allCases, id: \.self) { theme in
        Button {
          model.updateSoundCueTheme(theme)
        } label: {
          if theme == model.settings.soundCueTheme {
            Label(soundCueThemeLabel(theme), systemImage: "checkmark")
          } else {
            Text(soundCueThemeLabel(theme))
          }
        }
      }
    } label: {
      Label {
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
          Text(selectedLabel)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: "speaker.wave.3")
      }
    }
    .disabled(!model.settings.soundCuesEnabled)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(title))
    .accessibilityValue(Text(selectedLabel))
  }
}

private func soundCueThemeLabel(_ theme: SoundCueTheme) -> String {
  switch theme {
  case .standard:
    return L10n.text("settings.sound_theme.standard", table: .settings)
  case .tetris:
    return L10n.text("settings.sound_theme.tetris", table: .settings)
  case .cosmic:
    return L10n.text("settings.sound_theme.cosmic", table: .settings)
  }
}

private enum SoundCuePreviewItem: CaseIterable, Identifiable {
  case countdown
  case turnNow
  case pedestrianCrossing
  case warning
  case success
  case arrival

  var id: Self { self }

  var cue: NavigationSoundCue {
    switch self {
    case .countdown:
      return .countdown
    case .turnNow:
      return .turnNow
    case .pedestrianCrossing:
      return .pedestrianCrossing
    case .warning:
      return .warning
    case .success:
      return .success
    case .arrival:
      return .arrival
    }
  }

  var titleKey: String {
    switch self {
    case .countdown:
      return "settings.sound_cue.countdown.title"
    case .turnNow:
      return "settings.sound_cue.turn_now.title"
    case .pedestrianCrossing:
      return "settings.sound_cue.pedestrian_crossing.title"
    case .warning:
      return "settings.sound_cue.warning.title"
    case .success:
      return "settings.sound_cue.success.title"
    case .arrival:
      return "settings.sound_cue.arrival.title"
    }
  }

  var messageKey: String {
    switch self {
    case .countdown:
      return "settings.sound_cue.countdown.message"
    case .turnNow:
      return "settings.sound_cue.turn_now.message"
    case .pedestrianCrossing:
      return "settings.sound_cue.pedestrian_crossing.message"
    case .warning:
      return "settings.sound_cue.warning.message"
    case .success:
      return "settings.sound_cue.success.message"
    case .arrival:
      return "settings.sound_cue.arrival.message"
    }
  }

  var systemImage: String {
    switch self {
    case .pedestrianCrossing:
      return "figure.walk.motion"
    case .warning:
      return "exclamationmark.triangle"
    case .arrival:
      return "checkmark.circle"
    default:
      return "speaker.wave.2"
    }
  }
}

private struct SpeechSettingsDetailView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        Picker(
          L10n.text("settings.speech.mode", table: .settings),
          selection: Binding(
            get: { model.settings.speechMode },
            set: model.updateSpeechMode
          )
        ) {
          ForEach(Self.availableSpeechModes, id: \.self) { mode in
            Text(speechModeLabel(mode)).tag(mode)
          }
        }
      }

      if model.settings.speechMode == .speechSynthesizer {
        Section {
          NavigationLink {
            SpeechVoiceSelectionView(model: model)
          } label: {
            LabeledContent(
              L10n.text("settings.speech.voice", table: .settings),
              value: SpeechVoiceCatalog.selectedVoiceLabel(
                identifier: model.settings.selectedSpeechVoiceIdentifier
              )
            )
          }
        }
      }

      Section {
        SpeechSliderRow(
          title: L10n.text("settings.speech.rate", table: .settings),
          value: Binding(
            get: { model.settings.speechRate },
            set: model.updateSpeechRate
          ),
          range: 0.4...1.6,
          step: 0.1
        )

        SpeechSliderRow(
          title: L10n.text("settings.speech.volume", table: .settings),
          value: Binding(
            get: { model.settings.speechVolume },
            set: model.updateSpeechVolume
          ),
          range: 0.1...1.0,
          step: 0.1
        )
      }

      Section {
        Button {
          model.previewSpeechSettings()
        } label: {
          Label(
            L10n.text("settings.speech.preview", table: .settings),
            systemImage: "speaker.wave.2"
          )
        }
      }
    }
    .navigationTitle(L10n.text("settings.section.speech", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
  }

  private static let availableSpeechModes: [GuidanceSpeechMode] = [.voiceOver, .speechSynthesizer]

  private func speechModeLabel(_ mode: GuidanceSpeechMode) -> String {
    switch mode {
    case .automatic:
      return L10n.text("settings.speech.mode.automatic", table: .settings)
    case .voiceOver:
      return L10n.text("settings.speech.mode.voiceover", table: .settings)
    case .speechSynthesizer:
      return L10n.text("settings.speech.mode.synthesizer", table: .settings)
    }
  }
}

private struct SpeechVoiceSelectionView: View {
  @ObservedObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var searchText = ""

  var body: some View {
    List {
      Section {
        SpeechVoiceSelectionRow(
          title: L10n.text("settings.speech.voice.default", table: .settings),
          subtitle: nil,
          isSelected: model.settings.selectedSpeechVoiceIdentifier == nil
        ) {
          model.updateSpeechVoiceIdentifier(nil)
          dismiss()
        }
      }

      Section {
        ForEach(filteredVoices, id: \.identifier) { voice in
          SpeechVoiceSelectionRow(
            title: voice.name,
            subtitle: SpeechVoiceCatalog.languageName(for: voice),
            isSelected: model.settings.selectedSpeechVoiceIdentifier == voice.identifier
          ) {
            model.updateSpeechVoiceIdentifier(voice.identifier)
            dismiss()
          }
        }
      }
    }
    .searchable(
      text: $searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: L10n.text("settings.speech.voice.search", table: .settings)
    )
    .navigationTitle(L10n.text("settings.speech.voice", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var filteredVoices: [AVSpeechSynthesisVoice] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return SpeechVoiceCatalog.voices }

    return SpeechVoiceCatalog.voices.filter { voice in
      voice.name.localizedCaseInsensitiveContains(query)
        || voice.language.localizedCaseInsensitiveContains(query)
        || SpeechVoiceCatalog.languageName(for: voice).localizedCaseInsensitiveContains(query)
    }
  }
}

private struct SpeechVoiceSelectionRow: View {
  let title: String
  let subtitle: String?
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .foregroundStyle(.primary)

          if let subtitle {
            Text(subtitle)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .accessibilityHidden(true)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityValue(Text(isSelected ? L10n.text("settings.speech.voice.selected", table: .settings) : ""))
  }
}

private enum SpeechVoiceCatalog {
  static var voices: [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices()
      .sorted {
        voiceSortKey($0).localizedCaseInsensitiveCompare(voiceSortKey($1)) == .orderedAscending
      }
  }

  static func selectedVoiceLabel(identifier: String?) -> String {
    guard let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) else {
      return L10n.text("settings.speech.voice.default", table: .settings)
    }

    return "\(voice.name), \(languageName(for: voice))"
  }

  static func languageName(for voice: AVSpeechSynthesisVoice) -> String {
    L10n.currentLocale.localizedString(forIdentifier: voice.language) ?? voice.language
  }

  private static func voiceSortKey(_ voice: AVSpeechSynthesisVoice) -> String {
    "\(languageName(for: voice)) \(voice.name)"
  }
}

private struct SpeechSliderRow: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double

  var body: some View {
    let valueText = Self.percentText(value)

    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .accessibilityHidden(true)
      Slider(value: $value, in: range, step: step)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(valueText))
      Text(valueText)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
  }

  private static func percentText(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }
}

private struct AppSettingsDetailView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        Picker(
          L10n.text("settings.language.selected", table: .settings),
          selection: Binding(
            get: { model.settings.languageCode },
            set: model.updateLanguageCode
          )
        ) {
          Text(L10n.text("settings.language.system", table: .settings))
            .tag(AppLanguage.systemLanguageCode)
          ForEach(languageOptions, id: \.self) { code in
            Text(AppLanguage.displayName(for: code, in: L10n.currentLocale))
              .tag(code)
          }
        }

        LabeledContent(
          L10n.text("settings.language.detected", table: .settings),
          value: currentLanguageLabel
        )
      }

      Section {
        LabeledContent(L10n.text("settings.about.version", table: .settings), value: model.appVersionLabel)
        LabeledContent(L10n.text("settings.about.build", table: .settings), value: model.appBuildLabel)
        Link(destination: URL(string: "https://github.com/kazek5p-git/navi-live")!) {
          Label(L10n.text("settings.app.repository", table: .settings), systemImage: "link")
        }
      }
    }
    .navigationTitle(L10n.text("settings.group.app_updates", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var currentLanguageLabel: String {
    let locale = Locale.autoupdatingCurrent
    return locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
  }

  private var languageOptions: [String] {
    AppLanguage.supportedCodes.sorted {
      AppLanguage.displayName(for: $0, in: L10n.currentLocale)
        .localizedCaseInsensitiveCompare(AppLanguage.displayName(for: $1, in: L10n.currentLocale)) == .orderedAscending
    }
  }
}

#Preview {
  NavigationStack {
    SettingsView(model: AppModel())
  }
}
