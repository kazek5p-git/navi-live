import SwiftUI

struct HelpPrivacyView: View {
  var body: some View {
    List {
      Section {
        Text(L10n.text("help.tutorial.body", table: .settings))
      } header: {
        Text(L10n.text("help.section.tutorial", table: .settings))
      }

      Section {
        Link(
          destination: URL(string: "https://github.com/kazek5p-git/navi-live/issues")!
        ) {
          Label(L10n.text("help.support.issues", table: .settings), systemImage: "bubble.left.and.bubble.right")
        }

        Link(
          destination: URL(string: "https://github.com/kazek5p-git/navi-live")!
        ) {
          Label(L10n.text("help.support.repository", table: .settings), systemImage: "link")
        }
      } header: {
        Text(L10n.text("help.section.support", table: .settings))
      }

      Section {
        Text(L10n.text("help.privacy.body", table: .settings))
      } header: {
        Text(L10n.text("help.section.privacy", table: .settings))
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(L10n.text("help.title", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    HelpPrivacyView()
  }
}
