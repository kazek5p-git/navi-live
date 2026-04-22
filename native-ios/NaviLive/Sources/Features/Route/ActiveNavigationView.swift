import SwiftUI

struct ActiveNavigationView: View {
  @ObservedObject var model: AppModel
  let placeID: String

  var body: some View {
    let state = model.activeNavigationState
    let statusTone: StatusCard.Tone = state.isOffRoute || state.isRecalculating ? .warning : .info
    let statusText: String = {
      if state.isRecalculating {
        return L10n.text("active.status.recalculating", table: .navigation)
      }
      if state.isOffRoute {
        return L10n.text("active.status.off_route", table: .navigation)
      }
      if state.isPaused {
        return L10n.text("active.status.paused", table: .navigation)
      }
      return state.currentInstruction
    }()

    List {
      Section {
        StatusCard(
          title: L10n.text("active.section.status", table: .navigation),
          message: statusText,
          tone: statusTone
        )
      }

      Section {
        LabeledContent(
          L10n.text("active.label.current_instruction", table: .navigation),
          value: state.currentInstruction
        )
        LabeledContent(
          L10n.text("active.label.next_instruction", table: .navigation),
          value: state.nextInstruction
        )
      } header: {
        Text(L10n.text("active.section.instructions", table: .navigation))
      }

      Section {
        LabeledContent(
          L10n.text("active.label.distance_to_next", table: .navigation),
          value: AppFormatters.distance(state.distanceToNextMeters)
        )
        LabeledContent(
          L10n.text("active.label.remaining_distance", table: .navigation),
          value: AppFormatters.distance(state.remainingDistanceMeters)
        )
        LabeledContent(
          L10n.text("active.label.progress", table: .navigation),
          value: state.progressLabel
        )
        if let offRouteDistance = state.offRouteDistanceMeters {
          LabeledContent(
            L10n.text("active.status.off_route", table: .navigation),
            value: L10n.text("active.off_route_meta", table: .navigation, AppFormatters.distance(offRouteDistance))
          )
        }
      } header: {
        Text(L10n.text("active.section.progress", table: .navigation))
      }

      Section {
        PrimaryActionButton(
          title: L10n.text("active.action.repeat", table: .navigation),
          systemImage: "speaker.wave.2"
        ) {
          model.repeatCurrentInstruction()
        }

        SecondaryActionButton(
          title: state.isPaused
            ? L10n.text("active.action.resume", table: .navigation)
            : L10n.text("active.action.pause", table: .navigation),
          systemImage: state.isPaused ? "play.fill" : "pause.fill"
        ) {
          model.togglePauseNavigation()
        }

        SecondaryActionButton(
          title: L10n.text("active.action.recalculate", table: .navigation),
          systemImage: "arrow.clockwise"
        ) {
          model.recalculateRoute()
        }

        SecondaryActionButton(
          title: L10n.text("active.action.arrived", table: .navigation),
          systemImage: "checkmark.circle"
        ) {
          model.markArrived()
        }

        SecondaryActionButton(
          title: L10n.text("active.action.stop", table: .navigation),
          systemImage: "stop.circle"
        ) {
          model.stopNavigation()
        }
      } header: {
        Text(L10n.text("active.section.actions", table: .navigation))
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(L10n.text("active.title", table: .navigation))
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    ActiveNavigationView(model: AppModel(), placeID: "preview")
  }
}
