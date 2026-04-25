import SwiftUI

struct HomeView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    List {
      Section {
        StatusCard(
          title: L10n.text("home.section.location", table: .home),
          message: model.currentLocationDescription.isEmpty
            ? L10n.text("home.location.waiting", table: .home)
            : model.currentLocationDescription,
          tone: model.hasLocationPermission ? .success : .warning
        )
        .accessibilityHint(L10n.text("home.location.hint", table: .home))
      }

      Section {
        StatusCard(
          title: L10n.text("home.section.status", table: .home),
          message: model.statusMessage.isEmpty
            ? L10n.text("home.status.ready", table: .home)
            : model.statusMessage,
          tone: .info
        )
      }

      Section {
        PrimaryActionButton(
          title: L10n.text("home.action.search", table: .home),
          systemImage: "magnifyingglass"
        ) {
          model.openSearch()
        }

        SecondaryActionButton(
          title: L10n.text("home.action.current_position", table: .home),
          systemImage: "location.viewfinder"
        ) {
          model.openCurrentPosition()
        }

        SecondaryActionButton(
          title: L10n.text("home.action.favorites", table: .home),
          systemImage: "star"
        ) {
          model.openFavorites()
        }
      }

      if let lastRoutePlaceID = model.lastRoutePlaceID,
         let lastPlace = model.place(for: lastRoutePlaceID) {
        Section {
          Button {
            model.openPlaceDetails(lastPlace.id)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(lastPlace.name)
                .font(.headline)
              Text(lastPlace.address)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .accessibilityHint(L10n.text("home.resume_last_route.hint", table: .home))
        } header: {
          Text(L10n.text("home.section.last_route", table: .home))
        }
      }

      Section {
        HStack {
          Spacer()
          SecondaryActionButton(
            title: L10n.text("home.action.settings", table: .home),
            systemImage: "gearshape"
          ) {
            model.openSettings()
          }
          .frame(maxWidth: 260)
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(L10n.text("home.title", table: .home))
    .navigationBarTitleDisplayMode(.large)
    .refreshable {
      await model.loadCurrentAddress()
    }
  }
}

#Preview {
  NavigationStack {
    HomeView(model: AppModel())
  }
}
