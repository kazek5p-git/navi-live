import SwiftUI

struct StatusCard: View {
  enum Tone {
    case info
    case success
    case warning

    var tint: Color {
      switch self {
      case .info:
        return .blue
      case .success:
        return .green
      case .warning:
        return .orange
      }
    }
  }

  let title: String
  let message: String
  let tone: Tone

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: "circle.fill")
        .font(.headline)
        .foregroundStyle(tone.tint)
      Text(message)
        .font(.body)
        .foregroundStyle(.primary)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(tone.tint.opacity(0.12))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(tone.tint.opacity(0.25), lineWidth: 1)
    )
    .accessibilityElement(children: .combine)
  }
}
