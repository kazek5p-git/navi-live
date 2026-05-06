import Foundation
import UIKit

enum VisualAssistanceLauncher {
  private static let beMyEyesSchemeURL = URL(string: "bemyeyes://")!
  private static let beMyEyesAppStoreURL = URL(string: "https://apps.apple.com/app/id905177575")!

  @MainActor
  static func openBeMyEyes() {
    UIApplication.shared.open(beMyEyesSchemeURL, options: [:]) { didOpenApp in
      guard !didOpenApp else { return }
      UIApplication.shared.open(beMyEyesAppStoreURL, options: [:])
    }
  }
}