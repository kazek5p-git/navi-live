import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        Toggle(
          L10n.text("settings.toggle.show_tutorial", table: .settings),
          isOn: Binding(
            get: { model.settings.showTutorialOnLaunch },
            set: model.updateShowTutorialOnLaunch
          )
        )
      } header: {
        Text(L10n.text("settings.section.tutorial", table: .settings))
      }

      Section {
        Toggle(
          L10n.text("settings.toggle.vibration", table: .settings),
          isOn: Binding(
            get: { model.settings.vibrationEnabled },
            set: model.updateVibrationEnabled
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
      } header: {
        Text(L10n.text("settings.section.guidance", table: .settings))
      } footer: {
        Text(L10n.text("settings.guidance.cadence.footer", table: .settings))
      }

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
      } header: {
        Text(L10n.text("settings.section.speech", table: .settings))
      } footer: {
        Text(L10n.text("settings.speech.footer", table: .settings))
      }

      Section {
        Button {
          model.openHelpPrivacy()
        } label: {
          Label(L10n.text("settings.action.help_privacy", table: .settings), systemImage: "questionmark.circle")
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.text("settings.updates.title", table: .settings))
            .font(.headline)
          Text(L10n.text("settings.updates.message", table: .settings))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
      } header: {
        Text(L10n.text("settings.section.support", table: .settings))
      }

      Section {
        LabeledContent(L10n.text("settings.about.version", table: .settings), value: model.appVersionLabel)
        LabeledContent(L10n.text("settings.about.build", table: .settings), value: model.appBuildLabel)
      } header: {
        Text(L10n.text("settings.section.about", table: .settings))
      }
    }
    .navigationTitle(L10n.text("settings.title", table: .settings))
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

  private func announcementCadenceLabel(_ mode: AnnouncementCadenceMode) -> String {
    switch mode {
    case .distance:
      return L10n.text("settings.guidance.cadence.distance", table: .settings)
    case .time:
      return L10n.text("settings.guidance.cadence.time", table: .settings)
    }
  }
}

#Preview {
  NavigationStack {
    SettingsView(model: AppModel())
  }
}
