package com.navilive.android.data.preferences

import com.navilive.android.model.AnnouncementCadenceMode
import com.navilive.android.model.InterfaceTheme
import com.navilive.android.model.InterfaceThemeColors
import com.navilive.android.model.NearbyPoiCacheMode
import com.navilive.android.model.Place
import com.navilive.android.model.RouteSummary
import com.navilive.android.model.SettingsState
import com.navilive.android.model.ShakeStrength
import com.navilive.android.model.SharedProductRules
import com.navilive.android.model.SoundCueTheme
import com.navilive.android.model.SpeechOutputMode
import com.navilive.android.model.UpdateChannel
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal enum class NaviLiveBackupErrorReason {
    EmptyFile,
    InvalidFile,
    NoContent,
    NewerSchema,
    UnsupportedApp,
}

internal class NaviLiveBackupException(
    val reason: NaviLiveBackupErrorReason,
    cause: Throwable? = null,
) : IllegalArgumentException(reason.name, cause)

internal data class NaviLiveBackupRoute(
    val placeId: String?,
    val place: Place?,
    val summary: RouteSummary?,
)

internal data class NaviLiveBackupThemeColors(
    val backgroundHex: String? = null,
    val surfaceHex: String? = null,
    val primaryTextHex: String? = null,
    val secondaryTextHex: String? = null,
    val accentHex: String? = null,
    val outlineHex: String? = null,
) {
    fun mergeInto(current: InterfaceThemeColors): InterfaceThemeColors = current.copy(
        backgroundHex = backgroundHex ?: current.backgroundHex,
        surfaceHex = surfaceHex ?: current.surfaceHex,
        primaryTextHex = primaryTextHex ?: current.primaryTextHex,
        secondaryTextHex = secondaryTextHex ?: current.secondaryTextHex,
        accentHex = accentHex ?: current.accentHex,
        outlineHex = outlineHex ?: current.outlineHex,
    )

    companion object {
        fun from(colors: InterfaceThemeColors): NaviLiveBackupThemeColors = NaviLiveBackupThemeColors(
            backgroundHex = colors.backgroundHex,
            surfaceHex = colors.surfaceHex,
            primaryTextHex = colors.primaryTextHex,
            secondaryTextHex = colors.secondaryTextHex,
            accentHex = colors.accentHex,
            outlineHex = colors.outlineHex,
        )
    }
}

internal data class NaviLiveBackupSettings(
    val languageCode: String? = null,
    val interfaceTheme: String? = null,
    val customInterfaceThemeColors: NaviLiveBackupThemeColors? = null,
    val showTutorialOnLaunch: Boolean? = null,
    val vibrationEnabled: Boolean? = null,
    val shakeGestureEnabled: Boolean? = null,
    val shakeStrength: String? = null,
    val headphoneButtonRepeatEnabled: Boolean? = null,
    val soundCuesEnabled: Boolean? = null,
    val soundCueVolumePercent: Int? = null,
    val soundCueTheme: String? = null,
    val autoRecalculate: Boolean? = null,
    val junctionAlerts: Boolean? = null,
    val pedestrianCrossingAlerts: Boolean? = null,
    val turnByTurnAnnouncements: Boolean? = null,
    val announcementCadenceMode: String? = null,
    val searchRadiusKilometers: Int? = null,
    val searchResultLimit: Int? = null,
    val nearbyPOICacheMode: String? = null,
    val nearbyPOICacheRadiusKilometers: Int? = null,
    val updateChannel: String? = null,
    val speechMode: String? = null,
    val selectedSpeechVoicePlatform: String? = null,
    val selectedSpeechVoiceIdentifier: String? = null,
    val speechRatePercent: Int? = null,
    val speechVolumePercent: Int? = null,
    internal val presentKeys: Set<String> = emptySet(),
) {
    fun mergeInto(current: SettingsState): SettingsState {
        var result = current

        if (isPresent("languageCode", "language")) {
            languageCode?.let { result = result.copy(language = it) }
        }
        if (isPresent("interfaceTheme")) {
            result = result.copy(interfaceTheme = decodeInterfaceTheme(interfaceTheme, result.interfaceTheme))
        }
        if (isPresent("customInterfaceThemeColors")) {
            customInterfaceThemeColors?.let {
                result = result.copy(customThemeColors = it.mergeInto(result.customThemeColors))
            }
        }
        if (isPresent("showTutorialOnLaunch", "showTutorialOnStartup")) {
            showTutorialOnLaunch?.let { result = result.copy(showTutorialOnStartup = it) }
        }
        if (isPresent("vibrationEnabled")) {
            vibrationEnabled?.let { result = result.copy(vibrationEnabled = it) }
        }
        if (isPresent("shakeGestureEnabled")) {
            shakeGestureEnabled?.let { result = result.copy(shakeGestureEnabled = it) }
        }
        if (isPresent("shakeStrength")) {
            result = result.copy(shakeStrength = decodeShakeStrength(shakeStrength, result.shakeStrength))
        }
        if (isPresent("headphoneButtonRepeatEnabled")) {
            headphoneButtonRepeatEnabled?.let { result = result.copy(headphoneButtonRepeatEnabled = it) }
        }
        if (isPresent("soundCuesEnabled")) {
            soundCuesEnabled?.let { result = result.copy(soundCuesEnabled = it) }
        }
        if (isPresent("soundCueVolumePercent")) {
            soundCueVolumePercent?.let {
                result = result.copy(soundCueVolumePercent = it.coerceIn(0, 100))
            }
        }
        if (isPresent("soundCueTheme")) {
            result = result.copy(soundCueTheme = decodeSoundCueTheme(soundCueTheme, result.soundCueTheme))
        }
        if (isPresent("autoRecalculate")) {
            autoRecalculate?.let { result = result.copy(autoRecalculate = it) }
        }
        if (isPresent("junctionAlerts")) {
            junctionAlerts?.let { result = result.copy(junctionAlerts = it) }
        }
        if (isPresent("pedestrianCrossingAlerts")) {
            pedestrianCrossingAlerts?.let { result = result.copy(pedestrianCrossingAlerts = it) }
        }
        if (isPresent("turnByTurnAnnouncements")) {
            turnByTurnAnnouncements?.let { result = result.copy(turnByTurnAnnouncements = it) }
        }
        if (isPresent("announcementCadenceMode")) {
            result = result.copy(
                announcementCadenceMode = decodeAnnouncementCadenceMode(
                    announcementCadenceMode,
                    result.announcementCadenceMode,
                ),
            )
        }
        if (isPresent("searchRadiusKilometers")) {
            searchRadiusKilometers?.let {
                result = result.copy(
                    searchRadiusKm = it.coerceIn(
                        SharedProductRules.Search.minimumRadiusKm,
                        SharedProductRules.Search.maximumRadiusKm,
                    ),
                )
            }
        }
        if (isPresent("searchResultLimit")) {
            searchResultLimit?.let {
                result = result.copy(
                    searchResultLimit = it.coerceIn(
                        SharedProductRules.Search.minimumResultLimit,
                        SharedProductRules.Search.maximumResultLimit,
                    ),
                )
            }
        }
        if (isPresent("nearbyPOICacheMode")) {
            result = result.copy(
                nearbyPoiCacheMode = decodeNearbyPoiCacheMode(nearbyPOICacheMode, result.nearbyPoiCacheMode),
            )
        }
        if (isPresent("nearbyPOICacheRadiusKilometers")) {
            nearbyPOICacheRadiusKilometers?.let {
                result = result.copy(
                    nearbyPoiCacheRadiusKm = it.coerceIn(
                        SharedProductRules.Search.minimumRadiusKm,
                        5,
                    ),
                )
            }
        }
        if (isPresent("updateChannel")) {
            updateChannel?.let { value ->
                result = result.copy(
                    updateChannel = when (value.lowercase(Locale.ROOT)) {
                        "stable" -> UpdateChannel.Stable
                        "beta", "test" -> UpdateChannel.Beta
                        else -> result.updateChannel
                    },
                )
            }
        }
        if (isPresent("speechMode")) {
            result = result.copy(
                speechOutputMode = decodeSpeechOutputMode(speechMode, result.speechOutputMode),
            )
        }

        val hasVoiceValue = isPresent("selectedSpeechVoiceIdentifier", "selectedSystemTtsEnginePackage")
        if (hasVoiceValue || isPresent("selectedSpeechVoicePlatform")) {
            val platform = selectedSpeechVoicePlatform?.replace("_", "")?.lowercase(Locale.ROOT)
            if (platform == null || platform == "android") {
                if (hasVoiceValue) {
                    result = result.copy(selectedSystemTtsEnginePackage = selectedSpeechVoiceIdentifier)
                }
            } else if (isPresent("selectedSpeechVoicePlatform")) {
                // Identyfikator głosu z iOS nie jest nazwą pakietu silnika Androida.
                result = result.copy(selectedSystemTtsEnginePackage = null)
            }
        }
        if (isPresent("speechRatePercent")) {
            speechRatePercent?.let {
                result = result.copy(speechRatePercent = it.coerceIn(50, 200))
            }
        }
        if (isPresent("speechVolumePercent")) {
            speechVolumePercent?.let {
                result = result.copy(speechVolumePercent = it.coerceIn(0, 100))
            }
        }

        return result
    }

    private fun isPresent(vararg keys: String): Boolean = keys.any(presentKeys::contains)

    private fun decodeInterfaceTheme(value: String?, fallback: InterfaceTheme): InterfaceTheme {
        return when (value?.replace("_", "")?.lowercase(Locale.ROOT)) {
            "system" -> InterfaceTheme.System
            "light" -> InterfaceTheme.Light
            "dark" -> InterfaceTheme.Dark
            "highcontrast" -> InterfaceTheme.HighContrast
            "custom" -> InterfaceTheme.Custom
            else -> fallback
        }
    }

    private fun decodeShakeStrength(value: String?, fallback: ShakeStrength): ShakeStrength {
        return ShakeStrength.entries.firstOrNull { it.storageValue == value } ?: fallback
    }

    private fun decodeSoundCueTheme(value: String?, fallback: SoundCueTheme): SoundCueTheme {
        return SoundCueTheme.entries.firstOrNull { it.storageValue == value } ?: fallback
    }

    private fun decodeAnnouncementCadenceMode(
        value: String?,
        fallback: AnnouncementCadenceMode,
    ): AnnouncementCadenceMode {
        return AnnouncementCadenceMode.entries.firstOrNull { it.storageValue == value } ?: fallback
    }

    private fun decodeNearbyPoiCacheMode(value: String?, fallback: NearbyPoiCacheMode): NearbyPoiCacheMode {
        return when (value?.replace("_", "")?.lowercase(Locale.ROOT)) {
            "enabled" -> NearbyPoiCacheMode.Enabled
            "wifionly" -> NearbyPoiCacheMode.WifiOnly
            "disabled" -> NearbyPoiCacheMode.Disabled
            else -> fallback
        }
    }

    private fun decodeSpeechOutputMode(value: String?, fallback: SpeechOutputMode): SpeechOutputMode {
        return when (value?.replace("_", "")?.lowercase(Locale.ROOT)) {
            "system", "speechsynthesizer" -> SpeechOutputMode.System
            "screenreader", "voiceover" -> SpeechOutputMode.ScreenReader
            else -> fallback
        }
    }

    companion object {
        fun from(settings: SettingsState): NaviLiveBackupSettings = NaviLiveBackupSettings(
            languageCode = settings.language,
            interfaceTheme = settings.interfaceTheme.storageValue,
            customInterfaceThemeColors = NaviLiveBackupThemeColors.from(settings.customThemeColors),
            showTutorialOnLaunch = settings.showTutorialOnStartup,
            vibrationEnabled = settings.vibrationEnabled,
            shakeGestureEnabled = settings.shakeGestureEnabled,
            shakeStrength = settings.shakeStrength.storageValue,
            headphoneButtonRepeatEnabled = settings.headphoneButtonRepeatEnabled,
            soundCuesEnabled = settings.soundCuesEnabled,
            soundCueVolumePercent = settings.soundCueVolumePercent.coerceIn(0, 100),
            soundCueTheme = settings.soundCueTheme.storageValue,
            autoRecalculate = settings.autoRecalculate,
            junctionAlerts = settings.junctionAlerts,
            pedestrianCrossingAlerts = settings.pedestrianCrossingAlerts,
            turnByTurnAnnouncements = settings.turnByTurnAnnouncements,
            announcementCadenceMode = settings.announcementCadenceMode.storageValue,
            searchRadiusKilometers = settings.searchRadiusKm,
            searchResultLimit = settings.searchResultLimit,
            nearbyPOICacheMode = settings.nearbyPoiCacheMode.storageValue,
            nearbyPOICacheRadiusKilometers = settings.nearbyPoiCacheRadiusKm,
            updateChannel = settings.updateChannel.storageValue,
            speechMode = settings.speechOutputMode.storageValue,
            selectedSpeechVoicePlatform = "android",
            selectedSpeechVoiceIdentifier = settings.selectedSystemTtsEnginePackage,
            speechRatePercent = settings.speechRatePercent.coerceIn(50, 200),
            speechVolumePercent = settings.speechVolumePercent.coerceIn(0, 100),
            presentKeys = setOf(
                "languageCode",
                "interfaceTheme",
                "customInterfaceThemeColors",
                "showTutorialOnLaunch",
                "vibrationEnabled",
                "shakeGestureEnabled",
                "shakeStrength",
                "headphoneButtonRepeatEnabled",
                "soundCuesEnabled",
                "soundCueVolumePercent",
                "soundCueTheme",
                "autoRecalculate",
                "junctionAlerts",
                "pedestrianCrossingAlerts",
                "turnByTurnAnnouncements",
                "announcementCadenceMode",
                "searchRadiusKilometers",
                "searchResultLimit",
                "nearbyPOICacheMode",
                "nearbyPOICacheRadiusKilometers",
                "updateChannel",
                "speechMode",
                "selectedSpeechVoicePlatform",
                "selectedSpeechVoiceIdentifier",
                "speechRatePercent",
                "speechVolumePercent",
            ),
        )
    }
}

internal data class NaviLiveBackupPayload(
    val schemaVersion: Int,
    val settings: NaviLiveBackupSettings?,
    val favorites: List<Place>?,
    val lastRoute: NaviLiveBackupRoute?,
    val includesLastRoute: Boolean,
    val hasCompletedOnboarding: Boolean?,
) {
    val hasAnyContent: Boolean
        get() = settings != null || favorites != null || includesLastRoute || hasCompletedOnboarding != null
}

internal object NaviLiveBackupCodec {
    const val CurrentSchemaVersion = 1
    private const val AppName = "Navi Live"
    internal const val MaxBackupBytes = 5 * 1024 * 1024

    fun encode(
        settings: SettingsState,
        favorites: List<Place>,
        lastRoutePlaceId: String?,
        lastRoutePlace: Place?,
        lastRouteSummary: RouteSummary?,
        hasCompletedOnboarding: Boolean,
    ): String {
        val payload = NaviLiveBackupPayload(
            schemaVersion = CurrentSchemaVersion,
            settings = NaviLiveBackupSettings.from(settings),
            favorites = favorites,
            lastRoute = NaviLiveBackupRoute(
                placeId = lastRoutePlaceId,
                place = lastRoutePlace,
                summary = lastRouteSummary,
            ),
            includesLastRoute = true,
            hasCompletedOnboarding = hasCompletedOnboarding,
        )
        return encodePayload(payload)
    }

    fun encodePayload(payload: NaviLiveBackupPayload): String {
        if (!payload.hasAnyContent) {
            throw NaviLiveBackupException(NaviLiveBackupErrorReason.NoContent)
        }

        val root = JSONObject()
            .put("schemaVersion", payload.schemaVersion)
            .put("appName", AppName)
            .put("createdAtISO8601", currentTimestamp())

        payload.settings?.let { root.put("settings", encodeSettings(it)) }
        payload.favorites?.let { places ->
            root.put(
                "favorites",
                JSONArray().apply {
                    places.forEach { put(encodePlace(it)) }
                },
            )
        }
        if (payload.includesLastRoute) {
            root.put("lastRoute", encodeLastRoute(payload.lastRoute))
        }
        payload.hasCompletedOnboarding?.let { root.put("hasCompletedOnboarding", it) }

        val encoded = root.toString(2)
        if (encoded.toByteArray(Charsets.UTF_8).size > MaxBackupBytes) {
            throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
        }
        return encoded
    }

    fun decode(raw: String): NaviLiveBackupPayload {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            throw NaviLiveBackupException(NaviLiveBackupErrorReason.EmptyFile)
        }
        if (trimmed.toByteArray(Charsets.UTF_8).size > MaxBackupBytes) {
            throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
        }

        val root = try {
            JSONObject(trimmed)
        } catch (error: Exception) {
            throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile, error)
        }

        val schemaVersion = readSchemaVersion(root)
        if (schemaVersion > CurrentSchemaVersion) {
            throw NaviLiveBackupException(NaviLiveBackupErrorReason.NewerSchema)
        }
        if (schemaVersion < 1) {
            throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
        }

        val appName = optionalString(root, "appName")
        if (appName != null && !appName.equals(AppName, ignoreCase = true)) {
            throw NaviLiveBackupException(NaviLiveBackupErrorReason.UnsupportedApp)
        }

        val settings = if (root.has("settings")) {
            val value = root.optJSONObject("settings")
                ?: throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
            decodeSettings(value)
        } else {
            null
        }

        val favorites = if (root.has("favorites")) {
            val array = root.optJSONArray("favorites")
                ?: throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
            buildList<Place> {
                for (index in 0 until array.length()) {
                    val placeObject = array.optJSONObject(index)
                    if (placeObject == null) {
                        throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
                    }
                    val place = NavigationPersistenceCodec.decodePlace(placeObject)
                    if (place == null) {
                        throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
                    }
                    add(place)
                }
            }
        } else {
            null
        }

        val includesLastRoute = root.has("lastRoute")
        val lastRoute = if (includesLastRoute) {
            val routeObject = root.optJSONObject("lastRoute")
                ?: throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
            decodeLastRoute(routeObject)
        } else {
            null
        }

        val hasCompletedOnboarding = if (root.has("hasCompletedOnboarding")) {
            optionalBoolean(root, "hasCompletedOnboarding")
                ?: throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
        } else {
            null
        }

        val payload = NaviLiveBackupPayload(
            schemaVersion = schemaVersion,
            settings = settings,
            favorites = favorites,
            lastRoute = lastRoute,
            includesLastRoute = includesLastRoute,
            hasCompletedOnboarding = hasCompletedOnboarding,
        )
        if (!payload.hasAnyContent) {
            throw NaviLiveBackupException(NaviLiveBackupErrorReason.NoContent)
        }
        return payload
    }

    private fun encodeSettings(settings: NaviLiveBackupSettings): JSONObject {
        return JSONObject()
            .put("languageCode", settings.languageCode)
            .put("interfaceTheme", settings.interfaceTheme?.toCanonicalInterfaceTheme() ?: JSONObject.NULL)
            .put(
                "customInterfaceThemeColors",
                settings.customInterfaceThemeColors?.let { colors ->
                    JSONObject()
                        .put("backgroundHex", colors.backgroundHex ?: JSONObject.NULL)
                        .put("surfaceHex", colors.surfaceHex ?: JSONObject.NULL)
                        .put("primaryTextHex", colors.primaryTextHex ?: JSONObject.NULL)
                        .put("secondaryTextHex", colors.secondaryTextHex ?: JSONObject.NULL)
                        .put("accentHex", colors.accentHex ?: JSONObject.NULL)
                        .put("outlineHex", colors.outlineHex ?: JSONObject.NULL)
                } ?: JSONObject.NULL,
            )
            .put("showTutorialOnLaunch", settings.showTutorialOnLaunch ?: JSONObject.NULL)
            .put("vibrationEnabled", settings.vibrationEnabled ?: JSONObject.NULL)
            .put("shakeGestureEnabled", settings.shakeGestureEnabled ?: JSONObject.NULL)
            .put("shakeStrength", settings.shakeStrength ?: JSONObject.NULL)
            .put("headphoneButtonRepeatEnabled", settings.headphoneButtonRepeatEnabled ?: JSONObject.NULL)
            .put("soundCuesEnabled", settings.soundCuesEnabled ?: JSONObject.NULL)
            .put("soundCueVolumePercent", settings.soundCueVolumePercent ?: JSONObject.NULL)
            .put("soundCueTheme", settings.soundCueTheme ?: JSONObject.NULL)
            .put("autoRecalculate", settings.autoRecalculate ?: JSONObject.NULL)
            .put("junctionAlerts", settings.junctionAlerts ?: JSONObject.NULL)
            .put("pedestrianCrossingAlerts", settings.pedestrianCrossingAlerts ?: JSONObject.NULL)
            .put("turnByTurnAnnouncements", settings.turnByTurnAnnouncements ?: JSONObject.NULL)
            .put("announcementCadenceMode", settings.announcementCadenceMode ?: JSONObject.NULL)
            .put("searchRadiusKilometers", settings.searchRadiusKilometers ?: JSONObject.NULL)
            .put("searchResultLimit", settings.searchResultLimit ?: JSONObject.NULL)
            .put("nearbyPOICacheMode", settings.nearbyPOICacheMode?.toCanonicalNearbyPoiCacheMode() ?: JSONObject.NULL)
            .put("nearbyPOICacheRadiusKilometers", settings.nearbyPOICacheRadiusKilometers ?: JSONObject.NULL)
            .put("updateChannel", settings.updateChannel ?: JSONObject.NULL)
            .put("speechMode", settings.speechMode?.toCanonicalSpeechMode() ?: JSONObject.NULL)
            .put("selectedSpeechVoicePlatform", settings.selectedSpeechVoicePlatform ?: JSONObject.NULL)
            .put("selectedSpeechVoiceIdentifier", settings.selectedSpeechVoiceIdentifier ?: JSONObject.NULL)
            .put("speechRatePercent", settings.speechRatePercent ?: JSONObject.NULL)
            .put("speechVolumePercent", settings.speechVolumePercent ?: JSONObject.NULL)
    }

    private fun decodeSettings(value: JSONObject): NaviLiveBackupSettings {
        val colors = if (value.has("customInterfaceThemeColors") && !value.isNull("customInterfaceThemeColors")) {
            value.optJSONObject("customInterfaceThemeColors")
                ?: throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
        } else {
            null
        }
        val speechPlatform = optionalString(value, "selectedSpeechVoicePlatform")
        val selectedVoice = optionalString(value, "selectedSpeechVoiceIdentifier")
            ?: optionalString(value, "selectedSystemTtsEnginePackage")

        return NaviLiveBackupSettings(
            languageCode = optionalString(value, "languageCode")
                ?: optionalString(value, "language"),
            interfaceTheme = optionalString(value, "interfaceTheme"),
            customInterfaceThemeColors = colors?.let {
                NaviLiveBackupThemeColors(
                    backgroundHex = optionalString(it, "backgroundHex"),
                    surfaceHex = optionalString(it, "surfaceHex"),
                    primaryTextHex = optionalString(it, "primaryTextHex"),
                    secondaryTextHex = optionalString(it, "secondaryTextHex"),
                    accentHex = optionalString(it, "accentHex"),
                    outlineHex = optionalString(it, "outlineHex"),
                )
            },
            showTutorialOnLaunch = optionalBoolean(value, "showTutorialOnLaunch")
                ?: optionalBoolean(value, "showTutorialOnStartup"),
            vibrationEnabled = optionalBoolean(value, "vibrationEnabled"),
            shakeGestureEnabled = optionalBoolean(value, "shakeGestureEnabled"),
            shakeStrength = optionalString(value, "shakeStrength"),
            headphoneButtonRepeatEnabled = optionalBoolean(value, "headphoneButtonRepeatEnabled"),
            soundCuesEnabled = optionalBoolean(value, "soundCuesEnabled"),
            soundCueVolumePercent = optionalInt(value, "soundCueVolumePercent"),
            soundCueTheme = optionalString(value, "soundCueTheme"),
            autoRecalculate = optionalBoolean(value, "autoRecalculate"),
            junctionAlerts = optionalBoolean(value, "junctionAlerts"),
            pedestrianCrossingAlerts = optionalBoolean(value, "pedestrianCrossingAlerts"),
            turnByTurnAnnouncements = optionalBoolean(value, "turnByTurnAnnouncements"),
            announcementCadenceMode = optionalString(value, "announcementCadenceMode"),
            searchRadiusKilometers = optionalInt(value, "searchRadiusKilometers"),
            searchResultLimit = optionalInt(value, "searchResultLimit"),
            nearbyPOICacheMode = optionalString(value, "nearbyPOICacheMode"),
            nearbyPOICacheRadiusKilometers = optionalInt(value, "nearbyPOICacheRadiusKilometers"),
            updateChannel = optionalString(value, "updateChannel"),
            speechMode = optionalString(value, "speechMode"),
            selectedSpeechVoicePlatform = speechPlatform,
            selectedSpeechVoiceIdentifier = selectedVoice,
            speechRatePercent = optionalInt(value, "speechRatePercent"),
            speechVolumePercent = optionalInt(value, "speechVolumePercent"),
            presentKeys = collectKeys(value),
        )
    }

    private fun encodeLastRoute(route: NaviLiveBackupRoute?): JSONObject {
        return JSONObject()
            .put("placeID", route?.placeId ?: JSONObject.NULL)
            .put("place", route?.place?.let(::encodePlace) ?: JSONObject.NULL)
            .put(
                "summary",
                route?.summary?.let { JSONObject(NavigationPersistenceCodec.encodeRouteSummary(it)) }
                    ?: JSONObject.NULL,
            )
    }

    private fun decodeLastRoute(value: JSONObject): NaviLiveBackupRoute {
        val place = if (value.has("place") && !value.isNull("place")) {
            NavigationPersistenceCodec.decodePlace(value.optJSONObject("place"))
                ?: throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
        } else {
            null
        }
        val summary = if (value.has("summary") && !value.isNull("summary")) {
            val summaryObject = value.optJSONObject("summary")
                ?: throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
            NavigationPersistenceCodec.decodeRouteSummary(summaryObject.toString())
                ?: throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
        } else {
            null
        }
        return NaviLiveBackupRoute(
            placeId = optionalString(value, "placeID") ?: optionalString(value, "placeId"),
            place = place,
            summary = summary,
        )
    }

    private fun encodePlace(place: Place): JSONObject = NavigationPersistenceCodec.encodePlace(place)

    private fun readSchemaVersion(root: JSONObject): Int {
        val raw = root.opt("schemaVersion")
        val number = raw as? Number
            ?: throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
        val value = number.toDouble()
        if (!value.isFinite() || value % 1.0 != 0.0) {
            throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
        }
        return value.toInt()
    }

    private fun optionalString(value: JSONObject?, key: String): String? {
        if (value == null || !value.has(key) || value.isNull(key)) return null
        return value.opt(key) as? String
            ?: throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
    }

    private fun optionalBoolean(value: JSONObject?, key: String): Boolean? {
        if (value == null || !value.has(key) || value.isNull(key)) return null
        return value.opt(key) as? Boolean
            ?: throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
    }

    private fun optionalInt(value: JSONObject?, key: String): Int? {
        if (value == null || !value.has(key) || value.isNull(key)) return null
        val number = value.opt(key) as? Number
            ?: throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
        val doubleValue = number.toDouble()
        if (!doubleValue.isFinite() || doubleValue % 1.0 != 0.0) {
            throw NaviLiveBackupException(NaviLiveBackupErrorReason.InvalidFile)
        }
        return doubleValue.toInt()
    }

    private fun String.toCanonicalInterfaceTheme(): String = when (this) {
        "high_contrast", "highContrast" -> "highContrast"
        else -> this
    }

    private fun String.toCanonicalNearbyPoiCacheMode(): String = when (this) {
        "wifi_only", "wifiOnly" -> "wifiOnly"
        else -> this
    }

    private fun String.toCanonicalSpeechMode(): String = when (this) {
        "screen_reader", "screenReader" -> "screenReader"
        else -> "system"
    }

    private fun collectKeys(value: JSONObject): Set<String> {
        val keys = mutableSetOf<String>()
        val iterator = value.keys()
        while (iterator.hasNext()) {
            keys += iterator.next()
        }
        return keys
    }

    private fun currentTimestamp(): String = SimpleDateFormat(
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
        Locale.US,
    ).format(Date())
}
