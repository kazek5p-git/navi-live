import SwiftUI
import UIKit

private let naviLiveSupportBaseURL = URL(string: "https://paypal.me/KazimierzParzych")!

struct HelpPrivacyView: View {
  var body: some View {
    List {
      Section {
        Text(L10n.text("help.tutorial.body", table: .settings))
      } header: {
        Text(L10n.text("help.section.tutorial", table: .settings))
      }

      Section {
        VisualAssistanceCard()
      } header: {
        Text(L10n.text("help.section.visual_assistance", table: .settings))
      }

      Section {
        SupportDevelopmentCard()
      } header: {
        Text(L10n.text("settings.support.section", table: .settings))
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

private struct VisualAssistanceCard: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.text("help.visual_assistance.body", table: .settings))
        .font(.footnote)
        .foregroundStyle(.secondary)

      Button {
        VisualAssistanceLauncher.openBeMyEyes()
      } label: {
        Label(
          L10n.text("help.visual_assistance.open", table: .settings),
          systemImage: "eye"
        )
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
    }
  }
}
private struct SupportDevelopmentCard: View {
  @Environment(\.openURL) private var openURL

  @State private var customAmountInput = ""
  @State private var localStatusMessage: String?

  private let quickAmounts = [5, 10, 20, 50]
  private let amountColumns = [
    GridItem(.adaptive(minimum: 96), spacing: 12)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(L10n.text("settings.support.body", table: .settings))
        .font(.footnote)
        .foregroundStyle(.secondary)

      Text(L10n.text("support.amounts.description", table: .settings))
        .font(.footnote)
        .foregroundStyle(.secondary)

      LazyVGrid(columns: amountColumns, alignment: .leading, spacing: 12) {
        ForEach(quickAmounts, id: \.self) { amount in
          Button {
            openSupportAmount("\(amount)")
          } label: {
            Text(String(format: L10n.text("support.amount.button_format", table: .settings), amount))
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text(L10n.text("support.amount.custom.title", table: .settings))
          .font(.subheadline.weight(.semibold))

        TextField(
          L10n.text("support.amount.custom.placeholder", table: .settings),
          text: $customAmountInput
        )
        .keyboardType(.decimalPad)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)

        Button {
          openCustomAmount()
        } label: {
          Text(L10n.text("support.amount.custom.button", table: .settings))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }

      Button {
        openSupportBaseURL()
      } label: {
        Text(L10n.text("support.amount.other_currency.button", table: .settings))
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)

      Button {
        UIPasteboard.general.string = naviLiveSupportBaseURL.absoluteString
        localStatusMessage = L10n.text("support.amount.copy_success", table: .settings)
      } label: {
        Text(L10n.text("support.amount.copy_link", table: .settings))
      }
      .buttonStyle(.bordered)

      if let localStatusMessage, !localStatusMessage.isEmpty {
        Text(localStatusMessage)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func openSupportAmount(_ amount: String) {
    guard let url = supportURL(forNormalizedAmount: amount) else { return }
    localStatusMessage = nil
    openURL(url)
  }

  private func openCustomAmount() {
    guard let normalizedAmount = normalizedCustomAmount() else {
      localStatusMessage = L10n.text("support.amount.custom.invalid", table: .settings)
      return
    }

    openSupportAmount(normalizedAmount)
  }

  private func openSupportBaseURL() {
    localStatusMessage = nil
    openURL(naviLiveSupportBaseURL)
  }

  private func normalizedCustomAmount() -> String? {
    let trimmed = customAmountInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let replaced = trimmed.replacingOccurrences(of: ",", with: ".")
    let allowedCharacters = CharacterSet(charactersIn: "0123456789.")
    guard replaced.unicodeScalars.allSatisfy(allowedCharacters.contains) else { return nil }
    guard replaced.filter({ $0 == "." }).count <= 1 else { return nil }

    let decimalNumber = NSDecimalNumber(string: replaced, locale: Locale(identifier: "en_US_POSIX"))
    guard decimalNumber != .notANumber,
          decimalNumber.compare(NSDecimalNumber.zero) == .orderedDescending else {
      return nil
    }

    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2

    return formatter.string(from: decimalNumber)
  }

  private func supportURL(forNormalizedAmount amount: String) -> URL? {
    URL(string: "\(naviLiveSupportBaseURL.absoluteString)/\(amount)PLN")
  }
}

#Preview {
  NavigationStack {
    HelpPrivacyView()
  }
}
