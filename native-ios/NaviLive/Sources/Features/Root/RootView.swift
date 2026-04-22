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
            HeadingAlignView(model: model, placeID: placeID)
          case .activeNavigation(let placeID):
            ActiveNavigationView(model: model, placeID: placeID)
          case .arrival(let placeID):
            ArrivalView(model: model, placeID: placeID)
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

#Preview {
  RootView()
}
