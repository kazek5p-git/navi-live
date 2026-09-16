package com.navilive.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.navilive.android.model.InterfaceTheme
import com.navilive.android.model.InterfaceThemeColors
import com.navilive.android.model.SettingsState
import kotlin.math.pow

private val LightScheme = lightColorScheme(
    primary = PrimaryBlue,
    onPrimary = OnPrimaryBlue,
    primaryContainer = PrimaryContainerBlue,
    onPrimaryContainer = OnPrimaryContainerBlue,
    secondary = SecondaryTeal,
    onSecondary = OnSecondaryTeal,
    secondaryContainer = SecondaryContainerTeal,
    onSecondaryContainer = OnSecondaryContainerTeal,
    surface = SurfaceLight,
    onSurface = OnSurfaceLight,
    surfaceVariant = SurfaceVariantLight,
    onSurfaceVariant = OnSurfaceVariantLight,
    error = ErrorRed,
    onError = OnErrorRed,
)

private val DarkScheme = darkColorScheme(
    primary = PrimaryContainerBlue,
    onPrimary = OnPrimaryContainerBlue,
    primaryContainer = PrimaryBlue,
    onPrimaryContainer = OnPrimaryBlue,
    secondary = SecondaryContainerTeal,
    onSecondary = OnSecondaryContainerTeal,
    secondaryContainer = SecondaryTeal,
    onSecondaryContainer = OnPrimaryBlue,
    surface = Color(0xFF111418),
    onSurface = Color(0xFFE1E2E5),
    surfaceVariant = Color(0xFF42474F),
    onSurfaceVariant = Color(0xFFC1C7D0),
    background = Color(0xFF111418),
    onBackground = Color(0xFFE1E2E5),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
)

@Composable
fun NaviLiveTheme(
    settings: SettingsState = SettingsState(),
    content: @Composable () -> Unit,
) {
    val systemDarkTheme = isSystemInDarkTheme()
    val darkTheme = when (settings.interfaceTheme) {
        InterfaceTheme.System -> systemDarkTheme
        InterfaceTheme.Light -> false
        InterfaceTheme.Dark,
        InterfaceTheme.HighContrast -> true
        InterfaceTheme.Custom -> {
            val customBackground = parseThemeColor(
                settings.customThemeColors.backgroundHex,
                if (systemDarkTheme) Color(0xFF111418) else SurfaceLight,
            )
            isDarkThemeColor(customBackground)
        }
    }
    val colorScheme = when (settings.interfaceTheme) {
        InterfaceTheme.HighContrast -> highContrastScheme()
        InterfaceTheme.Custom -> customScheme(settings.customThemeColors, darkTheme)
        else -> if (darkTheme) DarkScheme else LightScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AppTypography,
        content = content,
    )
}

private fun highContrastScheme() = darkColorScheme(
    primary = Color(0xFFFFD600),
    onPrimary = Color.Black,
    primaryContainer = Color(0xFFFFD600),
    onPrimaryContainer = Color.Black,
    secondary = Color(0xFF7DDBFF),
    onSecondary = Color.Black,
    secondaryContainer = Color(0xFF004D61),
    onSecondaryContainer = Color(0xFFB5EBFF),
    tertiary = Color(0xFFFF9F80),
    onTertiary = Color.Black,
    background = Color.Black,
    onBackground = Color.White,
    surface = Color.Black,
    onSurface = Color.White,
    surfaceVariant = Color(0xFF202020),
    onSurfaceVariant = Color.White,
    outline = Color(0xFFFFD600),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
)

private fun customScheme(
    colors: InterfaceThemeColors,
    darkTheme: Boolean,
): androidx.compose.material3.ColorScheme {
    val background = parseThemeColor(colors.backgroundHex, if (darkTheme) Color(0xFF111418) else SurfaceLight)
    val surface = parseThemeColor(colors.surfaceHex, if (darkTheme) Color(0xFF1B2026) else Color.White)
    val primaryText = parseThemeColor(colors.primaryTextHex, if (darkTheme) Color.White else OnSurfaceLight)
    val secondaryText = parseThemeColor(colors.secondaryTextHex, if (darkTheme) Color(0xFFC1C7D0) else OnSurfaceVariantLight)
    val accent = parseThemeColor(colors.accentHex, PrimaryBlue)
    val outline = parseThemeColor(colors.outlineHex, SurfaceVariantLight)
    val primaryContainer = mix(accent, background, firstWeight = 0.18f)
    val secondary = mix(accent, surface, firstWeight = 0.60f)
    val secondaryContainer = mix(accent, surface, firstWeight = 0.16f)

    val arguments = SchemeArguments(
        primary = accent,
        onPrimary = bestReadableThemeText(accent),
        primaryContainer = primaryContainer,
        onPrimaryContainer = bestReadableThemeText(primaryContainer),
        secondary = secondary,
        onSecondary = bestReadableThemeText(secondary),
        secondaryContainer = secondaryContainer,
        onSecondaryContainer = bestReadableThemeText(secondaryContainer),
        background = background,
        onBackground = primaryText,
        surface = surface,
        onSurface = primaryText,
        surfaceVariant = mix(surface, background, firstWeight = 0.50f),
        onSurfaceVariant = secondaryText,
        outline = outline,
    )
    return if (darkTheme) {
        darkColorScheme(
            primary = arguments.primary,
            onPrimary = arguments.onPrimary,
            primaryContainer = arguments.primaryContainer,
            onPrimaryContainer = arguments.onPrimaryContainer,
            secondary = arguments.secondary,
            onSecondary = arguments.onSecondary,
            secondaryContainer = arguments.secondaryContainer,
            onSecondaryContainer = arguments.onSecondaryContainer,
            background = arguments.background,
            onBackground = arguments.onBackground,
            surface = arguments.surface,
            onSurface = arguments.onSurface,
            surfaceVariant = arguments.surfaceVariant,
            onSurfaceVariant = arguments.onSurfaceVariant,
            outline = arguments.outline,
            error = Color(0xFFFFB4AB),
            onError = Color(0xFF690005),
        )
    } else {
        lightColorScheme(
            primary = arguments.primary,
            onPrimary = arguments.onPrimary,
            primaryContainer = arguments.primaryContainer,
            onPrimaryContainer = arguments.onPrimaryContainer,
            secondary = arguments.secondary,
            onSecondary = arguments.onSecondary,
            secondaryContainer = arguments.secondaryContainer,
            onSecondaryContainer = arguments.onSecondaryContainer,
            background = arguments.background,
            onBackground = arguments.onBackground,
            surface = arguments.surface,
            onSurface = arguments.onSurface,
            surfaceVariant = arguments.surfaceVariant,
            onSurfaceVariant = arguments.onSurfaceVariant,
            outline = arguments.outline,
            error = ErrorRed,
            onError = OnErrorRed,
        )
    }
}

private data class SchemeArguments(
    val primary: Color,
    val onPrimary: Color,
    val primaryContainer: Color,
    val onPrimaryContainer: Color,
    val secondary: Color,
    val onSecondary: Color,
    val secondaryContainer: Color,
    val onSecondaryContainer: Color,
    val background: Color,
    val onBackground: Color,
    val surface: Color,
    val onSurface: Color,
    val surfaceVariant: Color,
    val onSurfaceVariant: Color,
    val outline: Color,
)

private fun parseThemeColor(value: String, fallback: Color): Color {
    return runCatching {
        Color(android.graphics.Color.parseColor(value.trim()))
    }.getOrDefault(fallback)
}

private fun isDarkThemeColor(color: Color): Boolean {
    return relativeThemeLuminance(color) < 0.5
}

internal fun bestReadableThemeText(background: Color): Color {
    val blackContrast = themeContrastRatio(Color.Black, background)
    val whiteContrast = themeContrastRatio(Color.White, background)
    return if (blackContrast >= whiteContrast) Color.Black else Color.White
}

internal fun themeContrastRatio(first: Color, second: Color): Double {
    val firstLuminance = relativeThemeLuminance(first)
    val secondLuminance = relativeThemeLuminance(second)
    val lighter = maxOf(firstLuminance, secondLuminance)
    val darker = minOf(firstLuminance, secondLuminance)
    return (lighter + 0.05) / (darker + 0.05)
}

private fun relativeThemeLuminance(color: Color): Double {
    fun linearize(channel: Float): Double {
        val value = channel.toDouble()
        return if (value <= 0.03928) {
            value / 12.92
        } else {
            ((value + 0.055) / 1.055).pow(2.4)
        }
    }

    return (0.2126 * linearize(color.red)) +
        (0.7152 * linearize(color.green)) +
        (0.0722 * linearize(color.blue))
}

private fun mix(first: Color, second: Color, firstWeight: Float): Color {
    val weight = firstWeight.coerceIn(0f, 1f)
    return Color(
        red = first.red * weight + second.red * (1f - weight),
        green = first.green * weight + second.green * (1f - weight),
        blue = first.blue * weight + second.blue * (1f - weight),
        alpha = 1f,
    )
}
