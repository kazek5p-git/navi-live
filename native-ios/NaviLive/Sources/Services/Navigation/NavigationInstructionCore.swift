import Foundation

struct NavigationInstructionDescriptor {
  enum Strategy: String {
    case departNamed = "DepartNamed"
    case arrive = "Arrive"
    case turnNamed = "TurnNamed"
    case turnGenericNamed = "TurnGenericNamed"
    case turnBareModifier = "TurnBareModifier"
    case continueNamed = "ContinueNamed"
    case proceedTowardNamed = "ProceedTowardNamed"
  }

  let strategy: Strategy
  let roadName: String?
  let normalizedModifier: String?

  func paritySignature() -> String {
    "\(strategy.rawValue)|\(roadName ?? "-")|\(normalizedModifier ?? "-")"
  }
}

enum NavigationInstructionCore {
  static func describe(
    maneuverType: String,
    modifier: String?,
    roadName: String?
  ) -> NavigationInstructionDescriptor {
    let normalizedRoad = roadName?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfBlank
    let normalizedModifier = modifier
      .map { SharedProductRules.Instructions.normalizeModifier($0) }
      .flatMap { SharedProductRules.Instructions.supportedModifiers.contains($0) ? $0 : nil }

    switch maneuverType {
    case "depart":
      return NavigationInstructionDescriptor(strategy: .departNamed, roadName: normalizedRoad, normalizedModifier: nil)
    case "arrive":
      return NavigationInstructionDescriptor(strategy: .arrive, roadName: nil, normalizedModifier: nil)
    case "turn":
      if let normalizedRoad, let normalizedModifier {
        return NavigationInstructionDescriptor(
          strategy: .turnNamed,
          roadName: normalizedRoad,
          normalizedModifier: normalizedModifier
        )
      }
      if let normalizedRoad {
        return NavigationInstructionDescriptor(
          strategy: .turnGenericNamed,
          roadName: normalizedRoad,
          normalizedModifier: nil
        )
      }
      if let normalizedModifier {
        return NavigationInstructionDescriptor(
          strategy: .turnBareModifier,
          roadName: nil,
          normalizedModifier: normalizedModifier
        )
      }
      return NavigationInstructionDescriptor(
        strategy: .turnGenericNamed,
        roadName: nil,
        normalizedModifier: nil
      )
    case "new name", "continue":
      return NavigationInstructionDescriptor(
        strategy: .continueNamed,
        roadName: normalizedRoad,
        normalizedModifier: nil
      )
    default:
      return NavigationInstructionDescriptor(
        strategy: .proceedTowardNamed,
        roadName: normalizedRoad,
        normalizedModifier: nil
      )
    }
  }
}

private extension String {
  var nilIfBlank: String? {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
  }
}
