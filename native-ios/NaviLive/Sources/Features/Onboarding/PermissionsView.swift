import SwiftUI

struct PermissionsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    NavigationStack {
      List {
        Section {
          StatusCard(
            title: L10n.text("permissions.status.title", table: .onboarding),
            message: L10n.text("permissions.status.message", table: .onboarding),
            tone: .warning
          )
        }

        Section {
          PrimaryActionButton(
            title: L10n.text("permissions.action.allow", table: .onboarding),
            systemImage: "location.fill"
          ) {
            model.requestLocationPermission()
          }

          SecondaryActionButton(
            title: L10n.text("permissions.action.later", table: .onboarding),
            systemImage: "clock"
          ) {
            model.continueWithoutPermission()
          }
        } footer: {
          Text(L10n.text("permissions.footer", table: .onboarding))
        }
      }
      .navigationTitle(L10n.text("permissions.title", table: .onboarding))
      .navigationBarTitleDisplayMode(.inline)
      .accessibilityElement(children: .contain)
    }
  }
}

#Preview {
  PermissionsView(model: AppModel())
}
