package com.navilive.android.data.routing

import com.navilive.android.model.SharedProductRules

internal object AddressFormattingCore {

    fun formatAddress(address: Map<String, String>?, fallback: String): String {
        if (address == null) return normalizeFallbackAddress(fallback)

        val streetName = firstNonBlankFromKeys(address, SharedProductRules.Address.streetPriorityKeys)
        val houseNumber = cleanAddressValue(address["house_number"])
        val streetLine = when {
            !streetName.isNullOrBlank() && !houseNumber.isNullOrBlank() -> "$streetName $houseNumber"
            !streetName.isNullOrBlank() -> streetName
            !houseNumber.isNullOrBlank() -> streetLineFromFallback(fallback, houseNumber) ?: houseNumber
            else -> streetLineFromFallback(fallback, null)
        }

        val locality = firstNonBlankFromKeys(address, SharedProductRules.Address.localityPriorityKeys)
        val region = firstNonBlankFromKeys(address, SharedProductRules.Address.regionPriorityKeys)
        val country = cleanAddressValue(address["country"])

        val parts = linkedSetOf<String>()
        listOf(streetLine, locality, region)
            .filterNotNull()
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .forEach(parts::add)
        if (
            parts.size < SharedProductRules.Address.appendCountryIfFewerThanParts &&
            !country.isNullOrBlank()
        ) {
            parts += country
        }
        return parts.joinToString(", ").ifBlank { normalizeFallbackAddress(fallback) }
    }

    fun normalizeFallbackAddress(fallback: String): String {
        val parts = fallback.split(",")
            .mapNotNull(::cleanAddressValue)
            .toMutableList()
        if (parts.size >= 2 && isLikelyHouseNumber(parts[0])) {
            parts[0] = "${parts[1]} ${parts[0]}"
            parts.removeAt(1)
        } else if (parts.isNotEmpty()) {
            parts[0] = normalizeStreetLine(parts[0]) ?: parts[0]
        }
        return parts.distinct().joinToString(", ").ifBlank { fallback }
    }

    fun isLikelyHouseNumber(value: String?): Boolean {
        val trimmed = cleanAddressValue(value) ?: return false
        return SharedProductRules.Address.houseNumberPattern.matches(trimmed)
    }

    private fun firstNonBlankFromKeys(address: Map<String, String>, keys: List<String>): String? {
        return keys.firstNotNullOfOrNull { key ->
            cleanAddressValue(address[key])
        }
    }

    private fun cleanAddressValue(value: String?): String? {
        val trimmed = value?.trim().orEmpty()
        return trimmed.takeIf {
            it.isNotBlank() && !it.equals("null", ignoreCase = true)
        }
    }

    private fun streetLineFromFallback(fallback: String, houseNumber: String?): String? {
        val parts = fallback.split(",")
            .mapNotNull(::cleanAddressValue)
        if (parts.isEmpty()) return null

        val first = parts.getOrNull(0)
        val second = parts.getOrNull(1)
        if (!houseNumber.isNullOrBlank() && first == houseNumber && !second.isNullOrBlank()) {
            return "$second $houseNumber"
        }
        if (!houseNumber.isNullOrBlank() && second == houseNumber && !first.isNullOrBlank()) {
            return "$first $houseNumber"
        }
        return normalizeStreetLine(first)
    }

    private fun normalizeStreetLine(value: String?): String? {
        val trimmed = cleanAddressValue(value) ?: return null
        val match = SharedProductRules.Address.leadingHouseNumberStreetPattern.matchEntire(trimmed)
        return if (match != null) {
            "${match.groupValues[2]} ${match.groupValues[1]}".trim()
        } else {
            trimmed
        }
    }

}
