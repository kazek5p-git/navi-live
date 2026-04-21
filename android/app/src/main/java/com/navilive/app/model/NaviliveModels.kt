package com.navilive.app.model

data class GeoPoint(
    val latitude: Double,
    val longitude: Double,
)

data class Place(
    val id: String,
    val name: String,
    val address: String,
    val walkDistanceMeters: Int,
    val walkEtaMinutes: Int,
    val point: GeoPoint? = null,
    val phone: String? = null,
    val website: String? = null,
)

data class RouteSummary(
    val distanceMeters: Int,
    val etaMinutes: Int,
    val modeLabel: String = "",
    val currentInstruction: String = "",
    val nextInstruction: String = "",
    val steps: List<RouteStep> = emptyList(),
    val pathPoints: List<GeoPoint> = emptyList(),
)

data class RouteStep(
    val instruction: String,
    val distanceMeters: Int,
    val maneuverPoint: GeoPoint? = null,
)

data class HeadingState(
    val instruction: String = "",
    val isAligned: Boolean = false,
    val arrowRotationDeg: Float = 18f,
)

data class ActiveNavigationState(
    val currentInstruction: String = "",
    val nextInstruction: String = "",
    val distanceToNextMeters: Int = 0,
    val remainingDistanceMeters: Int = 0,
    val progressLabel: String = "",
    val isPaused: Boolean = false,
    val isOffRoute: Boolean = false,
    val isRecalculating: Boolean = false,
    val offRouteDistanceMeters: Int? = null,
)

data class LocationFix(
    val point: GeoPoint,
    val accuracyMeters: Float,
    val timestampMs: Long,
)

data class LocationUiState(
    val hasPermission: Boolean = false,
    val isForegroundTracking: Boolean = false,
    val latestFix: LocationFix? = null,
)

enum class SpeechOutputMode(val storageValue: String) {
    System("system"),
    ScreenReader("screen_reader"),
    ;

    companion object {
        fun fromStorageValue(value: String?): SpeechOutputMode {
            return entries.firstOrNull { it.storageValue == value } ?: System
        }
    }
}

data class SystemTtsEngineOption(
    val packageName: String?,
    val displayName: String,
    val isDefaultChoice: Boolean = false,
)

data class SettingsState(
    val language: String = "",
    val vibrationEnabled: Boolean = true,
    val autoRecalculate: Boolean = true,
    val junctionAlerts: Boolean = true,
    val turnByTurnAnnouncements: Boolean = true,
    val speechOutputMode: SpeechOutputMode = SpeechOutputMode.System,
    val selectedSystemTtsEnginePackage: String? = null,
    val speechRatePercent: Int = 100,
    val speechVolumePercent: Int = 100,
    val isScreenReaderActive: Boolean = false,
    val activeScreenReaderName: String? = null,
    val availableSystemTtsEngines: List<SystemTtsEngineOption> = emptyList(),
    val defaultSystemTtsEngineLabel: String? = null,
    val activeSystemTtsEngineLabel: String? = null,
    val isSelectedSystemTtsEngineAvailable: Boolean = true,
)

data class DiagnosticsState(
    val eventCount: Int = 0,
    val activeSessionLabel: String = "",
    val lastEventLabel: String = "",
    val lastExportPath: String? = null,
)

data class NaviliveUiState(
    val currentLocationLabel: String = "",
    val places: List<Place> = emptyList(),
    val searchQuery: String = "",
    val searchResults: List<Place> = emptyList(),
    val favoriteIds: Set<String> = emptySet(),
    val lastRoutePlaceId: String? = null,
    val headingState: HeadingState = HeadingState(),
    val activeNavigationState: ActiveNavigationState = ActiveNavigationState(),
    val settingsState: SettingsState = SettingsState(),
    val diagnosticsState: DiagnosticsState = DiagnosticsState(),
    val statusMessage: String = "",
    val isLoadingSearch: Boolean = false,
    val isLoadingRoute: Boolean = false,
    val locationState: LocationUiState = LocationUiState(),
    val hasCompletedOnboarding: Boolean = false,
    val isPreferencesLoaded: Boolean = false,
)
