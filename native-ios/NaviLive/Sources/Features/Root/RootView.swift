import SwiftUI

struct RootView: View {
  @StateObject private var model = AppModel()
  @State private var didBootstrap = false

  var body: some View {
    Group {
      switch model.launchState {
      case .bootstrapping:
        BootstrappingView()
      case .onboarding:
        OnboardingView(model: model)
      case .permissions:
        PermissionsView(model: model)
      case .ready:
        RootNavigationView(model: model)
      }
    }
    .task {
      guard !didBootstrap else { return }
      didBootstrap = true
      await model.bootstrap()
    }
  }
}

private struct RootNavigationView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    NavigationStack(path: $model.path) {
      HomeView(model: model)
        .navigationDestination(for: AppRoute.self) { route in
          switch route {
          case .onboarding:
            OnboardingView(model: model)
          case .permissions:
            PermissionsView(model: model)
          case .search:
            SearchView(model: model)
          case .placeDetails(let placeID):
            PlaceDetailsView(model: model, placeID: placeID)
          case .routeSummary(let placeID):
            RouteSummaryView(model: model, placeID: placeID)
          case .headingAlign(let placeID):
            PlaceholderDestinationView(
              title: L10n.text("navigation.placeholder.heading_title", table: .navigation),
              message: L10n.text("navigation.placeholder.heading_message", table: .navigation),
              model: model,
              placeID: placeID
            )
          case .activeNavigation(let placeID):
            PlaceholderDestinationView(
              title: L10n.text("navigation.placeholder.active_title", table: .navigation),
              message: L10n.text("navigation.placeholder.active_message", table: .navigation),
              model: model,
              placeID: placeID
            )
          case .arrival(let placeID):
            PlaceholderDestinationView(
              title: L10n.text("navigation.placeholder.arrival_title", table: .navigation),
              message: L10n.text("navigation.placeholder.arrival_message", table: .navigation),
              model: model,
              placeID: placeID
            )
          case .currentPosition:
            CurrentPositionView(model: model)
          case .favorites:
            FavoritesView(model: model)
          case .settings:
            SettingsView(model: model)
          case .helpPrivacy:
            HelpPrivacyView()
          }
        }
    }
  }
}

private struct BootstrappingView: View {
  var body: some View {
    VStack(spacing: 20) {
      ProgressView()
        .controlSize(.large)
      Text(L10n.text("root.bootstrapping", table: .root))
        .font(.body)
        .foregroundStyle(.secondary)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
    .accessibilityElement(children: .combine)
  }
}

private struct PlaceholderDestinationView: View {
  let title: String
  let message: String
  @ObservedObject var model: AppModel
  let placeID: String

  var body: some View {
    let placeName = model.place(for: placeID)?.name ?? ""

    List {
      Section {
        StatusCard(title: title, message: message, tone: .info)
      }

      if !placeName.isEmpty {
        Section {
          Text(placeName)
            .font(.headline)
        } header: {
          Text(L10n.text("navigation.placeholder.destination", table: .navigation))
        }
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  RootView()
}
