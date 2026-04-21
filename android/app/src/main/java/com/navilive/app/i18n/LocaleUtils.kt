package com.navilive.app.i18n

import android.content.res.Configuration
import android.os.Build
import java.util.Locale

fun currentAppLocale(configuration: Configuration): Locale {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        configuration.locales[0] ?: Locale.getDefault()
    } else {
        @Suppress("DEPRECATION")
        configuration.locale ?: Locale.getDefault()
    }
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
