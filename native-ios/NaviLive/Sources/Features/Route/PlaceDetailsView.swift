import SwiftUI

struct PlaceDetailsView: View {
  @ObservedObject var model: AppModel
  let placeID: String

  var body: some View {
    Group {
      if let place = model.place(for: placeID) {
        List {
          Section {
            VStack(alignment: .leading, spacing: 8) {
              Text(place.name)
                .font(.title3)
                .fontWeight(.semibold)
              Text(place.address)
                .font(.body)
                .foregroundStyle(.secondary)
              Text(
                L10n.text(
                  "place.meta",
                  table: .home,
                  AppFormatters.distance(place.walkDistanceMeters),
                  AppFormatters.eta(minutes: place.walkEtaMinutes)
                )
              )
              .font(.footnote)
              .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
          } header: {
            Text(L10n.text("place.section.summary", table: .home))
          }

          Section {
            PrimaryActionButton(
              title: L10n.text("place.action.route", table: .home),
              systemImage: "arrow.triangle.turn.up.right.circle.fill"
            ) {
              Task {
                await model.prepareRoute(for: placeID)
                if model.selectedRouteSummary != nil {
                  model.openRouteSummary(placeID)
                }
              }
            }

            SecondaryActionButton(
              title: model.isFavorite(place)
                ? L10n.text("place.action.favorite.remove", table: .home)
                : L10n.text("place.action.favorite.add", table: .home),
              systemImage: model.isFavorite(place) ? "star.slash" : "star"
            ) {
              model.toggleFavorite(place)
            }
          } header: {
            Text(L10n.text("place.section.actions", table: .home))
          }

          if place.hasContactDetails {
            Section {
              if let phone = place.phone, !phone.isEmpty {
                Label(phone, systemImage: "phone")
              }
              if let website = place.website,
                 !website.isEmpty,
                 let websiteURL = URL(string: website) {
                Link(destination: websiteURL) {
                  Label(website, systemImage: "globe")
                }
              }
            } header: {
              Text(L10n.text("place.section.contact", table: .home))
            }
          }

          if model.isRouting {
            Section {
              HStack(spacing: 12) {
                ProgressView()
                Text(L10n.text("route.status.loading", table: .navigation))
              }
            }
          }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.text("place.title", table: .home))
        .navigationBarTitleDisplayMode(.inline)
      } else {
        UnavailableStateView(
          title: L10n.text("place.unavailable.title", table: .home),
          systemImage: "mappin.slash",
          message: L10n.text("place.unavailable.message", table: .home)
        )
      }
    }
  }
}

#Preview {
  NavigationStack {
    PlaceDetailsView(model: AppModel(), placeID: "preview")
  }
}
