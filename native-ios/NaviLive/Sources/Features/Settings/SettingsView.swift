import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        Text(L10n.text("settings.root.message", table: .settings))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        NavigationLink {
          GuidanceSettingsDetailView(model: model)
        } label: {
          SettingsGroupRow(
            title: L10n.text("settings.section.guidance", table: .settings),
            summary: L10n.text("settings.group.guidance.summary", table: .settings),
            systemImage: "figure.walk"
          )
        }

        NavigationLink {
          SpeechSettingsDetailView(model: model)
        } label: {
          SettingsGroupRow(
            title: L10n.text("settings.section.speech", table: .settings),
            summary: L10n.text("settings.group.speech.summary", table: .settings),
            systemImage: "speaker.wave.2"
          )
        }

        NavigationLink {
          AppSettingsDetailView(model: model)
        } label: {
          SettingsGroupRow(
            title: L10n.text("settings.group.app_updates", table: .settings),
            summary: L10n.text("settings.group.app_updates.summary", table: .settings),
            systemImage: "gearshape"
          )
        }

        NavigationLink {
          HelpPrivacyView()
        } label: {
          SettingsGroupRow(
            title: L10n.text("help.title", table: .settings),
            summary: L10n.text("settings.group.help_privacy.summary", table: .settings),
            systemImage: "questionmark.circle"
          )
        }
      }
    }
    .navigationTitle(L10n.text("settings.title", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct SettingsGroupRow: View {
  let title: String
  let summary: String
  let systemImage: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(Color.accentColor)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
        Text(summary)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
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
          L10n.text("settings.toggle.vibration", table: .settings),
          isOn: Binding(
            get: { model.settings.vibrationEnabled },
            set: model.updateVibrationEnabled
          )
        )

        Toggle(
          L10n.text("settings.toggle.sound_cues", table: .settings),
          isOn: Binding(
            get: { model.settings.soundCuesEnabled },
            set: model.updateSoundCuesEnabled
          )
        )

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
      } footer: {
        Text(L10n.text("settings.guidance.cadence.footer", table: .settings))
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
      } header: {
        Text(L10n.text("settings.sound_cues.tutorial.title", table: .settings))
      } footer: {
        Text(L10n.text("settings.sound_cues.tutorial.message", table: .settings))
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
}

private enum SoundCuePreviewItem: CaseIterable, Identifiable {
  case countdown
  case turnNow
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
          ForEach(GuidanceSpeechMode.allCases, id: \.self) { mode in
            Text(speechModeLabel(mode)).tag(mode)
          }
        }
      } footer: {
        Text(L10n.text("settings.speech.footer", table: .settings))
      }

      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text(L10n.text("settings.speech.rate", table: .settings))
          Slider(
            value: Binding(
              get: { model.settings.speechRate },
              set: model.updateSpeechRate
            ),
            in: 0.4...1.6,
            step: 0.1
          )
          Text(String(format: "%.1f", model.settings.speechRate))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text(L10n.text("settings.speech.volume", table: .settings))
          Slider(
            value: Binding(
              get: { model.settings.speechVolume },
              set: model.updateSpeechVolume
            ),
            in: 0.1...1.0,
            step: 0.1
          )
          Text(String(format: "%.1f", model.settings.speechVolume))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle(L10n.text("settings.section.speech", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
  }

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

private struct AppSettingsDetailView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        LabeledContent(
          L10n.text("settings.language.detected", table: .settings),
          value: currentLanguageLabel
        )
        Text(L10n.text("settings.language.detected_message", table: .settings))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.text("settings.updates.title", table: .settings))
            .font(.headline)
          Text(L10n.text("settings.updates.message", table: .settings))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
      }

      Section {
        LabeledContent(L10n.text("settings.about.version", table: .settings), value: model.appVersionLabel)
        LabeledContent(L10n.text("settings.about.build", table: .settings), value: model.appBuildLabel)
      }
    }
    .navigationTitle(L10n.text("settings.group.app_updates", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var currentLanguageLabel: String {
    let locale = Locale.autoupdatingCurrent
    return locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
  }
}

#Preview {
  NavigationStack {
    SettingsView(model: AppModel())
  }
}
