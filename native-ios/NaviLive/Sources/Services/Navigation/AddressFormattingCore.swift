import Foundation

enum AddressFormattingCore {
  static func formatAddress(_ address: [String: String]?, fallback: String) -> String {
    guard let address else { return normalizeFallbackAddress(fallback) }

    let streetName = firstNonBlank(address, keys: SharedProductRules.Address.streetPriorityKeys)
    let houseNumber = cleanAddressValue(address["house_number"])
    let streetLine: String? = {
      if !streetName.isEmpty, let houseNumber {
        return "\(streetName) \(houseNumber)"
      }
      if !streetName.isEmpty {
        return streetName
      }
      if let houseNumber {
        return streetLineFromFallback(fallback, houseNumber: houseNumber) ?? houseNumber
      }
      return streetLineFromFallback(fallback, houseNumber: nil)
    }()

    let locality = firstNonBlank(address, keys: SharedProductRules.Address.localityPriorityKeys)
    let region = firstNonBlank(address, keys: SharedProductRules.Address.regionPriorityKeys)
    let country = cleanAddressValue(address["country"])

    var orderedParts: [String] = []
    for part in [streetLine, locality, region].compactMap({ $0 }) {
      let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !orderedParts.contains(trimmed) else { continue }
      orderedParts.append(trimmed)
    }
    if orderedParts.count < SharedProductRules.Address.appendCountryIfFewerThanParts,
      let country,
      !orderedParts.contains(country)
    {
      orderedParts.append(country)
    }
    return orderedParts.isEmpty ? normalizeFallbackAddress(fallback) : orderedParts.joined(separator: ", ")
  }

  static func normalizeFallbackAddress(_ fallback: String) -> String {
    var parts = fallback.components(separatedBy: ",")
      .compactMap(cleanAddressValue)
    if parts.count >= 2, isLikelyHouseNumber(parts[0]) {
      parts[0] = "\(parts[1]) \(parts[0])"
      parts.remove(at: 1)
    } else if let first = parts.first {
      parts[0] = normalizeStreetLine(first) ?? first
    }

    var uniqueParts: [String] = []
    for part in parts where !uniqueParts.contains(part) {
      uniqueParts.append(part)
    }
    return uniqueParts.isEmpty ? fallback : uniqueParts.joined(separator: ", ")
  }

  static func isLikelyHouseNumber(_ value: String?) -> Bool {
    guard let trimmed = cleanAddressValue(value) else { return false }
    return trimmed.range(of: SharedProductRules.Address.houseNumberPattern, options: .regularExpression) != nil
  }

  private static func firstNonBlank(_ address: [String: String], keys: [String]) -> String {
    keys.compactMap { cleanAddressValue(address[$0]) }.first ?? ""
  }

  private static func cleanAddressValue(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty, trimmed.lowercased() != "null" else { return nil }
    return trimmed
  }

  private static func streetLineFromFallback(_ fallback: String, houseNumber: String?) -> String? {
    let parts = fallback.components(separatedBy: ",")
      .compactMap(cleanAddressValue)
    guard let first = parts.first else { return nil }
    let second = parts.dropFirst().first

    if let houseNumber, first == houseNumber, let second, !second.isEmpty {
      return "\(second) \(houseNumber)"
    }
    if let houseNumber, second == houseNumber {
      return "\(first) \(houseNumber)"
    }
    return normalizeStreetLine(first)
  }

  private static func normalizeStreetLine(_ value: String?) -> String? {
    guard let trimmed = cleanAddressValue(value) else { return nil }
    let pattern = SharedProductRules.Address.leadingHouseNumberStreetPattern
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return trimmed }
    let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    guard let match = regex.firstMatch(in: trimmed, range: range),
      let numberRange = Range(match.range(at: 1), in: trimmed),
      let streetRange = Range(match.range(at: 2), in: trimmed)
    else {
      return trimmed
    }
    return "\(trimmed[streetRange]) \(trimmed[numberRange])"
  }
}
