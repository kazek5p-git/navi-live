import SwiftUI

struct ArrivalView: View {
  @ObservedObject var model: AppModel
  let placeID: String

  var body: some View {
    let place = model.place(for: placeID)

    List {
      Section {
        StatusCard(
          title: L10n.text("arrival.title", table: .navigation),
          message: L10n.text("arrival.message", table: .navigation),
          tone: .success
        )
      }

      if let place {
        Section {
          VStack(alignment: .leading, spacing: 4) {
            Text(place.name)
              .font(.headline)
            Text(place.address)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
        } header: {
          Text(L10n.text("arrival.section.destination", table: .navigation))
        }
      }

      Section {
        PrimaryActionButton(
          title: L10n.text("arrival.action.done", table: .navigation),
          systemImage: "house"
        ) {
          model.stopNavigation()
          model.path.removeAll()
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(L10n.text("arrival.title", table: .navigation))
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    ArrivalView(model: AppModel(), placeID: "preview")
  }
}
