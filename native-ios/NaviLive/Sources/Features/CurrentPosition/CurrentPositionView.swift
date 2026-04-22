import SwiftUI

struct CurrentPositionView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    List {
      Section {
        StatusCard(
          title: L10n.text("current.title", table: .home),
          message: model.currentLocationDescription.isEmpty
            ? L10n.text("home.location.waiting", table: .home)
            : model.currentLocationDescription,
          tone: model.hasLocationPermission ? .success : .warning
        )
      }

      Section {
        LabeledContent(
          L10n.text("current.label.accuracy", table: .home),
          AppFormatters.accuracy(model.locationService.latestFix?.accuracyMeters)
        )
      } header: {
        Text(L10n.text("current.section.details", table: .home))
      }

      Section {
        PrimaryActionButton(
          title: L10n.text("current.action.save_favorite", table: .home),
          systemImage: "star"
        ) {
          Task { await model.saveCurrentLocationAsFavorite() }
        }

        SecondaryActionButton(
          title: L10n.text("current.action.refresh", table: .home),
          systemImage: "arrow.clockwise"
        ) {
          Task { await model.loadCurrentAddress() }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(L10n.text("current.title", table: .home))
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    CurrentPositionView(model: AppModel())
  }
}
