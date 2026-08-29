package com.navilive.android.data.routing

import java.text.Normalizer
import java.util.Locale

/** Normalizuje tekst wyszukiwania, zachowując litery wszystkich alfabetów Unicode. */
internal object SearchTextCore {
    private val combiningMarks = "\\p{M}+".toRegex()
    private val nonLettersOrDigits = "[^\\p{L}\\p{N}]+".toRegex()
    private val repeatedWhitespace = "\\s+".toRegex()

    fun normalize(value: String): String {
        return Normalizer.normalize(value, Normalizer.Form.NFD)
            .lowercase(Locale.ROOT)
            .replace(combiningMarks, "")
            .replace(nonLettersOrDigits, " ")
            .replace(repeatedWhitespace, " ")
            .trim()
    }
}
