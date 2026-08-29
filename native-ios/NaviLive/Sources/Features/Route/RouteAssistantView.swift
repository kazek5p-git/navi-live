import SwiftUI

struct RouteAssistantView: View {
  @ObservedObject var model: AppModel
  let placeID: String

  @State private var question = ""
  @State private var answer = ""
  @AccessibilityFocusState private var answerHasFocus: Bool

  var body: some View {
    Form {
      Section {
        Text(
          L10n.text(
            "assistant.status.message",
            table: .navigation,
            model.place(for: placeID)?.name ?? L10n.text("route.section.destination", table: .navigation)
          )
        )

        TextField(
          L10n.text("assistant.question.label", table: .navigation),
          text: $question,
          prompt: Text(L10n.text("assistant.question.placeholder", table: .navigation))
        )
        .textInputAutocapitalization(.sentences)
        .submitLabel(.send)
        .onSubmit(askQuestion)

        Button(action: askQuestion) {
          Label(
            L10n.text("assistant.ask", table: .navigation),
            systemImage: "sparkles"
          )
        }
      }

      Section {
        ForEach(quickQuestions) { quickQuestion in
          Button(quickQuestion.label) {
            ask(quickQuestion.token)
          }
        }
      } header: {
        Text(L10n.text("assistant.quick.title", table: .navigation))
      }

      if !answer.isEmpty {
        Section {
          Text(answer)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(answer))
            .accessibilityFocused($answerHasFocus)
        } header: {
          Text(L10n.text("assistant.answer.title", table: .navigation))
        }
      }

      Section {
        Text(L10n.text("assistant.privacy.message", table: .navigation))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle(L10n.text("assistant.title", table: .navigation))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var quickQuestions: [QuickQuestion] {
    [
      QuickQuestion(
        token: RouteAssistantCore.repeatInstructionToken,
        label: L10n.text("active.action.repeat", table: .navigation)
      ),
      QuickQuestion(
        token: RouteAssistantCore.currentInstructionToken,
        label: L10n.text("assistant.quick.current", table: .navigation)
      ),
      QuickQuestion(
        token: RouteAssistantCore.currentLocationToken,
        label: L10n.text("home.action.current_position", table: .home)
      ),
      QuickQuestion(
        token: RouteAssistantCore.nextInstructionToken,
        label: L10n.text("assistant.quick.next", table: .navigation)
      ),
      QuickQuestion(
        token: RouteAssistantCore.routeOverviewToken,
        label: L10n.text("assistant.quick.overview", table: .navigation)
      ),
      QuickQuestion(
        token: RouteAssistantCore.progressToken,
        label: L10n.text("assistant.quick.progress", table: .navigation)
      ),
      QuickQuestion(
        token: RouteAssistantCore.routeStatusToken,
        label: L10n.text("assistant.quick.status", table: .navigation)
      ),
      QuickQuestion(
        token: RouteAssistantCore.routeQualityToken,
        label: L10n.text("assistant.quick.quality", table: .navigation)
      ),
      QuickQuestion(
        token: RouteAssistantCore.pedestrianCrossingToken,
        label: L10n.text("assistant.quick.crossing", table: .navigation)
      )
    ]
  }

  private func askQuestion() {
    ask(question)
  }

  private func ask(_ value: String) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    question = trimmed
    answer = model.answerRouteAssistant(for: trimmed)
    DispatchQueue.main.async {
      answerHasFocus = true
    }
  }
}

private struct QuickQuestion: Identifiable {
  let token: String
  let label: String

  var id: String { token }
}

#Preview {
  NavigationStack {
    RouteAssistantView(model: AppModel(), placeID: "preview")
  }
}
