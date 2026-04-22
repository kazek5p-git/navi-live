import SwiftUI

struct HeadingAlignView: View {
  @ObservedObject var model: AppModel
  let placeID: String

  var body: some View {
    let place = model.place(for: placeID)
    let statusMessage = model.headingState.isAligned
      ? L10n.text("heading.status.aligned", table: .navigation)
      : L10n.text("heading.status.aligning", table: .navigation)

    List {
      Section {
        StatusCard(
          title: L10n.text("heading.title", table: .navigation),
          message: model.headingState.isAligned ? statusMessage : model.headingState.instruction,
          tone: model.headingState.isAligned ? .success : .info
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
          Text(L10n.text("heading.destination", table: .navigation))
        }
      }

      Section {
        HStack {
          Spacer()
          Image(systemName: "location.north.line.fill")
            .font(.system(size: 68, weight: .semibold))
            .foregroundStyle(.blue)
            .rotationEffect(.degrees(model.headingState.arrowRotationDegrees))
            .padding(.vertical, 16)
            .accessibilityHidden(true)
          Spacer()
        }
      }

      Section {
        PrimaryActionButton(
          title: L10n.text("heading.action.check", table: .navigation),
          systemImage: "scope"
        ) {
          model.cycleHeadingInstruction()
        }

        PrimaryActionButton(
          title: L10n.text("heading.action.start", table: .navigation),
          systemImage: "figure.walk"
        ) {
          model.beginActiveNavigation()
          model.openActiveNavigation(placeID)
        }
        .disabled(!model.headingState.isAligned)

        SecondaryActionButton(
          title: L10n.text("heading.action.skip", table: .navigation),
          systemImage: "forward.end"
        ) {
          model.beginActiveNavigation()
          model.openActiveNavigation(placeID)
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(L10n.text("heading.title", table: .navigation))
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    HeadingAlignView(model: AppModel(), placeID: "preview")
  }
}
