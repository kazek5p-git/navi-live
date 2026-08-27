package com.navilive.android.i18n

import android.content.res.Configuration
import java.util.Locale

fun currentAppLocale(configuration: Configuration): Locale {
    return configuration.locales[0] ?: Locale.getDefault()
}

fun localizedLanguageDisplayName(configuration: Configuration): String {
    val locale = currentAppLocale(configuration)
    val displayName = locale.getDisplayLanguage(locale).ifBlank { locale.displayLanguage }
    return displayName.replaceFirstChar { char ->
        if (char.isLowerCase()) {
            char.titlecase(locale)
        } else {
            char.toString()
        }
    }
}
