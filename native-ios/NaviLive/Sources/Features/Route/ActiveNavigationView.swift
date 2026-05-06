import SwiftUI

struct ActiveNavigationView: View {
  @ObservedObject var model: AppModel
  let placeID: String

  var body: some View {
    let state = model.activeNavigationState
    let routeEntries = routeStepEntries(state: state)
    let alertEntries = alertRotorEntries(state: state, routeEntries: routeEntries)
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
        .accessibilityAction(named: Text(L10n.text("active.action.repeat", table: .navigation))) {
          model.repeatCurrentInstruction()
        }
        .accessibilityAction(named: Text(L10n.text("active.action.previous_instruction", table: .navigation))) {
          model.announcePreviousInstruction()
        }
        .accessibilityAction(named: Text(L10n.text("active.action.next_instruction", table: .navigation))) {
          model.announceNextInstruction()
        }
        .accessibilityAction(
          named: Text(
            state.isPaused
              ? L10n.text("active.action.resume", table: .navigation)
              : L10n.text("active.action.pause", table: .navigation)
          )
        ) {
          model.togglePauseNavigation()
        }
        .accessibilityAction(named: Text(L10n.text("active.action.recalculate", table: .navigation))) {
          model.recalculateRoute()
        }
        .accessibilityAction(named: Text(L10n.text("active.action.report_problem", table: .navigation))) {
          model.reportRouteProblem()
        }
        .accessibilityAction(named: Text(L10n.text("active.action.visual_assistance", table: .navigation))) {
          VisualAssistanceLauncher.openBeMyEyes()
        }
        .accessibilityAction(named: Text(L10n.text("active.action.show_route_summary", table: .navigation))) {
          model.openRouteSummary(placeID)
        }
        .accessibilityAction(named: Text(L10n.text("active.action.stop", table: .navigation))) {
          model.stopNavigation()
        }
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

      if !alertEntries.isEmpty {
        Section {
          ForEach(alertEntries) { entry in
            ActiveNavigationRotorRow(entry: entry)
          }
        } header: {
          Text(L10n.text("active.section.alerts", table: .navigation))
        }
      }

      if !routeEntries.isEmpty {
        Section {
          ForEach(routeEntries) { entry in
            ActiveNavigationRotorRow(entry: entry)
          }
        } header: {
          Text(L10n.text("active.section.route_plan", table: .navigation))
        }
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
          title: L10n.text("active.action.report_problem", table: .navigation),
          systemImage: "exclamationmark.bubble"
        ) {
          model.reportRouteProblem()
        }

        SecondaryActionButton(
          title: L10n.text("active.action.visual_assistance", table: .navigation),
          systemImage: "eye"
        ) {
          VisualAssistanceLauncher.openBeMyEyes()
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
    .accessibilityRotor(
      Text(L10n.text("active.rotor.instructions", table: .navigation)),
      entries: routeEntries,
      entryLabel: \.rotorLabel
    )
    .accessibilityRotor(
      Text(L10n.text("active.rotor.alerts", table: .navigation)),
      entries: alertEntries,
      entryLabel: \.rotorLabel
    )
    .navigationTitle(L10n.text("active.title", table: .navigation))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func routeStepEntries(state: ActiveNavigationState) -> [ActiveNavigationRotorEntry] {
    let steps = model.selectedRouteSummary?.steps ?? []
    guard !steps.isEmpty else {
      return fallbackRouteEntries(state: state)
    }

    let currentIndex = min(max(state.currentStepIndex, 0), steps.count - 1)
    return steps.enumerated().map { index, step in
      let stepTitle = L10n.text(
        "active.route_step.title",
        table: .navigation,
        index + 1,
        steps.count
      )
      let title = index == currentIndex
        ? L10n.text(
            "active.route_step.current_format",
            table: .navigation,
            stepTitle
          )
        : stepTitle
      let distance = step.distanceMeters > 0 ? AppFormatters.distance(step.distanceMeters) : ""
      let value = [step.instruction, distance]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: ", ")

      return ActiveNavigationRotorEntry(
        id: "route-step-\(index)-\(step.id.uuidString)",
        title: title,
        value: value,
        rotorLabel: "\(title), \(step.instruction)",
        systemImage: step.kind == .pedestrianCrossing ? "figure.walk.motion" : "arrow.turn.up.right",
        kind: step.kind
      )
    }
  }

  private func fallbackRouteEntries(state: ActiveNavigationState) -> [ActiveNavigationRotorEntry] {
    var entries: [ActiveNavigationRotorEntry] = []
    if !state.currentInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      entries.append(
        ActiveNavigationRotorEntry(
          id: "route-current-instruction",
          title: L10n.text("active.label.current_instruction", table: .navigation),
          value: state.currentInstruction,
          rotorLabel: state.currentInstruction,
          systemImage: "location.north.line",
          kind: .instruction
        )
      )
    }
    if !state.nextInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      entries.append(
        ActiveNavigationRotorEntry(
          id: "route-next-instruction",
          title: L10n.text("active.label.next_instruction", table: .navigation),
          value: state.nextInstruction,
          rotorLabel: state.nextInstruction,
          systemImage: "arrow.turn.up.right",
          kind: .instruction
        )
      )
    }
    return entries
  }

  private func alertRotorEntries(
    state: ActiveNavigationState,
    routeEntries: [ActiveNavigationRotorEntry]
  ) -> [ActiveNavigationRotorEntry] {
    var entries: [ActiveNavigationRotorEntry] = []
    if state.isOffRoute {
      let value = state.offRouteDistanceMeters.map {
        L10n.text("active.off_route_meta", table: .navigation, AppFormatters.distance($0))
      } ?? ""
      entries.append(
        ActiveNavigationRotorEntry(
          id: "active-alert-off-route",
          title: L10n.text("active.status.off_route", table: .navigation),
          value: value,
          rotorLabel: [L10n.text("active.status.off_route", table: .navigation), value]
            .filter { !$0.isEmpty }
            .joined(separator: ", "),
          systemImage: "exclamationmark.triangle",
          kind: .instruction
        )
      )
    }
    if state.isRecalculating {
      entries.append(
        ActiveNavigationRotorEntry(
          id: "active-alert-recalculating",
          title: L10n.text("active.status.recalculating", table: .navigation),
          value: "",
          rotorLabel: L10n.text("active.status.recalculating", table: .navigation),
          systemImage: "arrow.clockwise",
          kind: .instruction
        )
      )
    }
    entries.append(contentsOf: routeEntries.filter { $0.kind == .pedestrianCrossing })
    return entries
  }
}

private struct ActiveNavigationRotorEntry: Identifiable, Hashable {
  let id: String
  let title: String
  let value: String
  let rotorLabel: String
  let systemImage: String
  let kind: RouteStepKind
}

private struct ActiveNavigationRotorRow: View {
  let entry: ActiveNavigationRotorEntry

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: entry.systemImage)
        .frame(width: 24)
        .foregroundStyle(entry.kind == .pedestrianCrossing ? .orange : Color.accentColor)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(entry.title)
          .font(.body.weight(.semibold))
        if !entry.value.isEmpty {
          Text(entry.value)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .id(entry.id)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(entry.title))
    .accessibilityValue(Text(entry.value))
  }
}

#Preview {
  NavigationStack {
    ActiveNavigationView(model: AppModel(), placeID: "preview")
  }
}
