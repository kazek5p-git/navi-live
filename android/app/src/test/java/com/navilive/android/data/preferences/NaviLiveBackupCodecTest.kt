package com.navilive.android.data.preferences

import com.navilive.android.model.GeoPoint
import com.navilive.android.model.InterfaceTheme
import com.navilive.android.model.InterfaceThemeColors
import com.navilive.android.model.NearbyPoiCacheMode
import com.navilive.android.model.Place
import com.navilive.android.model.RouteStep
import com.navilive.android.model.RouteStepKind
import com.navilive.android.model.RouteSummary
import com.navilive.android.model.SettingsState
import com.navilive.android.model.SoundCueTheme
import com.navilive.android.model.SpeechOutputMode
import com.navilive.android.model.UpdateChannel
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class NaviLiveBackupCodecTest {

    @Test
    fun backupRoundTripsSharedData() {
        val settings = SettingsState(
            language = "pl",
            interfaceTheme = InterfaceTheme.HighContrast,
            customThemeColors = InterfaceThemeColors(
                backgroundHex = "#101010",
                surfaceHex = "#202020",
                primaryTextHex = "#FFFFFF",
                secondaryTextHex = "#DDDDDD",
                accentHex = "#FFD600",
                outlineHex = "#FFFFFF",
            ),
            soundCueTheme = SoundCueTheme.Cosmic,
            nearbyPoiCacheMode = NearbyPoiCacheMode.WifiOnly,
            speechOutputMode = SpeechOutputMode.System,
            selectedSystemTtsEnginePackage = "com.example.tts",
            searchRadiusKm = 2,
            searchResultLimit = 10,
        )
        val favorite = Place(
            id = "favorite-1",
            name = "Sklep testowy",
            address = "Przykładowa 12, Łódź",
            walkDistanceMeters = 120,
            walkEtaMinutes = 2,
            point = GeoPoint(51.760000, 19.460000),
            savedAtMs = 123_456L,
            savedAccuracyMeters = 8.5f,
        )
        val summary = RouteSummary(
            distanceMeters = 1_250,
            etaMinutes = 17,
            modeLabel = "Pieszo",
            currentInstruction = "Skręć w prawo w Wschodnią",
            nextInstruction = "Idź prosto",
            steps = listOf(
                RouteStep(
                    instruction = "Skręć w prawo w Wschodnią",
                    distanceMeters = 80,
                    maneuverPoint = favorite.point,
                    maneuverType = "turn",
                    maneuverModifier = "right",
                    roadName = "Wschodnia",
                ),
            ),
            pathPoints = listOf(
                GeoPoint(51.759000, 19.459000),
                GeoPoint(51.760000, 19.460000),
            ),
        )

        val raw = NaviLiveBackupCodec.encode(
            settings = settings,
            favorites = listOf(favorite),
            lastRoutePlaceId = favorite.id,
            lastRoutePlace = favorite,
            lastRouteSummary = summary,
            hasCompletedOnboarding = true,
        )
        val decoded = NaviLiveBackupCodec.decode(raw)

        assertEquals(settings, decoded.settings?.mergeInto(SettingsState()))
        assertEquals(listOf(favorite), decoded.favorites)
        assertEquals(favorite, decoded.lastRoute?.place)
        assertEquals(summary, decoded.lastRoute?.summary)
        assertEquals(favorite.id, decoded.lastRoute?.placeId)
        assertTrue(decoded.includesLastRoute)
        assertEquals(true, decoded.hasCompletedOnboarding)

        val root = JSONObject(raw)
        assertEquals(1, root.getInt("schemaVersion"))
        assertEquals("Navi Live", root.getString("appName"))
        assertEquals(
            "instruction",
            root
                .getJSONObject("lastRoute")
                .getJSONObject("summary")
                .getJSONArray("steps")
                .getJSONObject(0)
                .getString("kind"),
        )
    }

    @Test
    fun decoderAcceptsIosSpeechAndThemeValues() {
        val raw = """
            {
              "schemaVersion": 1,
              "appName": "Navi Live",
              "settings": {
                "interfaceTheme": "highContrast",
                "nearbyPOICacheMode": "wifiOnly",
                "speechMode": "screenReader",
                "selectedSpeechVoicePlatform": "ios",
                "selectedSpeechVoiceIdentifier": "com.apple.voice"
              }
            }
        """.trimIndent()

        val settings = NaviLiveBackupCodec.decode(raw).settings?.mergeInto(SettingsState())

        assertEquals(InterfaceTheme.HighContrast, settings?.interfaceTheme)
        assertEquals(NearbyPoiCacheMode.WifiOnly, settings?.nearbyPoiCacheMode)
        assertEquals(SpeechOutputMode.ScreenReader, settings?.speechOutputMode)
        assertEquals(null, settings?.selectedSystemTtsEnginePackage)
    }

    @Test
    fun decoderAcceptsIosRouteStepKinds() {
        val raw = """
            {
              "schemaVersion": 1,
              "appName": "Navi Live",
              "lastRoute": {
                "placeID": "target",
                "summary": {
                  "distanceMeters": 100,
                  "etaMinutes": 2,
                  "modeLabel": "Walking",
                  "currentInstruction": "Cross the street",
                  "nextInstruction": "",
                  "steps": [
                    {"instruction": "Cross the street", "distanceMeters": 20, "kind": "pedestrianCrossing"}
                  ],
                  "pathPoints": [
                    {"latitude": 51.0, "longitude": 19.0}
                  ]
                }
              }
            }
        """.trimIndent()

        val step = NaviLiveBackupCodec.decode(raw).lastRoute?.summary?.steps?.single()

        assertEquals(RouteStepKind.PedestrianCrossing, step?.kind)
    }

    @Test
    fun partialSettingsMergeKeepsValuesMissingFromBackup() {
        val current = SettingsState(
            language = "pl",
            interfaceTheme = InterfaceTheme.Dark,
            customThemeColors = InterfaceThemeColors(
                backgroundHex = "#101010",
                surfaceHex = "#202020",
                primaryTextHex = "#FFFFFF",
                secondaryTextHex = "#DDDDDD",
                accentHex = "#00FF00",
                outlineHex = "#FFFFFF",
            ),
            updateChannel = UpdateChannel.Beta,
            selectedSystemTtsEnginePackage = "com.example.current",
            searchResultLimit = 10,
        )
        val raw = """
            {
              "schemaVersion": 1,
              "appName": "Navi Live",
              "settings": {
                "interfaceTheme": "light",
                "customInterfaceThemeColors": {"accentHex": "#FFD600"},
                "searchRadiusKilometers": 2
              }
            }
        """.trimIndent()

        val decoded = NaviLiveBackupCodec.decode(raw).settings
        val merged = requireNotNull(decoded).mergeInto(current)

        assertEquals(InterfaceTheme.Light, merged.interfaceTheme)
        assertEquals("#FFD600", merged.customThemeColors.accentHex)
        assertEquals("#101010", merged.customThemeColors.backgroundHex)
        assertEquals(2, merged.searchRadiusKm)
        assertEquals(10, merged.searchResultLimit)
        assertEquals(UpdateChannel.Beta, merged.updateChannel)
        assertEquals("com.example.current", merged.selectedSystemTtsEnginePackage)
    }

    @Test
    fun encoderRejectsBackupLargerThanMaximum() {
        val oversizedSettings = NaviLiveBackupSettings(
            languageCode = "x".repeat(NaviLiveBackupCodec.MaxBackupBytes),
            presentKeys = setOf("languageCode"),
        )
        val payload = NaviLiveBackupPayload(
            schemaVersion = NaviLiveBackupCodec.CurrentSchemaVersion,
            settings = oversizedSettings,
            favorites = null,
            lastRoute = null,
            includesLastRoute = false,
            hasCompletedOnboarding = null,
        )

        assertReasonForEncoding(NaviLiveBackupErrorReason.InvalidFile, payload)
    }

    private fun assertReasonForEncoding(
        expected: NaviLiveBackupErrorReason,
        payload: NaviLiveBackupPayload,
    ) {
        try {
            NaviLiveBackupCodec.encodePayload(payload)
            fail("Oczekiwano błędu $expected")
        } catch (error: NaviLiveBackupException) {
            assertEquals(expected, error.reason)
        }
    }

    @Test
    fun decoderRejectsInvalidBackupFilesWithoutPartialPayload() {
        assertReason(NaviLiveBackupErrorReason.EmptyFile, "")
        assertReason(NaviLiveBackupErrorReason.InvalidFile, "not-json")
        assertReason(
            NaviLiveBackupErrorReason.UnsupportedApp,
            """{"schemaVersion":1,"appName":"Other App","settings":{}}""",
        )
        assertReason(
            NaviLiveBackupErrorReason.NewerSchema,
            """{"schemaVersion":2,"appName":"Navi Live","settings":{}}""",
        )
        assertReason(
            NaviLiveBackupErrorReason.NoContent,
            """{"schemaVersion":1,"appName":"Navi Live"}""",
        )
    }

    private fun assertReason(expected: NaviLiveBackupErrorReason, raw: String) {
        try {
            NaviLiveBackupCodec.decode(raw)
            fail("Oczekiwano błędu $expected")
        } catch (error: NaviLiveBackupException) {
            assertEquals(expected, error.reason)
        }
    }
}
