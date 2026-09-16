package com.navilive.android.model

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import com.navilive.android.ui.theme.bestReadableThemeText
import com.navilive.android.ui.theme.themeContrastRatio

class InterfaceThemeTest {

    @Test
    fun storageValuesRoundTripAndUnknownValuesUseSystemTheme() {
        InterfaceTheme.entries.forEach { theme ->
            assertEquals(theme, InterfaceTheme.fromStorageValue(theme.storageValue))
        }

        assertEquals(InterfaceTheme.System, InterfaceTheme.fromStorageValue(null))
        assertEquals(InterfaceTheme.System, InterfaceTheme.fromStorageValue("not-a-theme"))
    }

    @Test
    fun customColorsHaveAccessibleDefaultsAndRemainCopyable() {
        val defaults = InterfaceThemeColors()

        assertEquals("#F5F9FF", defaults.backgroundHex)
        assertEquals("#FFFFFF", defaults.surfaceHex)
        assertEquals("#101418", defaults.primaryTextHex)
        assertEquals("#065EA8", defaults.accentHex)
        assertEquals("#9AA8B8", defaults.outlineHex)
        assertEquals("#C0C0C0", defaults.copy(outlineHex = "#C0C0C0").outlineHex)
    }

    @Test
    fun generatedThemeTextMeetsNormalTextContrastAgainstAnyBackground() {
        listOf(
            Color.Black,
            Color.White,
            Color(0xFF777777),
            Color(0xFF065EA8),
            Color(0xFFFFD600),
        ).forEach { background ->
            val text = bestReadableThemeText(background)
            assertTrue(themeContrastRatio(text, background) >= 4.5)
        }
    }
}
