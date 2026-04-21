package com.navilive.app.data.preferences

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.navilive.app.model.SpeechOutputMode
import com.navilive.app.model.SettingsState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import java.io.IOException

private val Context.dataStore by preferencesDataStore(name = "navilive_preferences")

data class PersistedNaviliveState(
    val favoriteIds: Set<String>,
    val lastRoutePlaceId: String?,
    val hasCompletedOnboarding: Boolean,
    val settingsState: SettingsState,
    val downloadedUpdateApkPath: String?,
    val downloadedUpdateVersionLabel: String?,
)

class NavilivePreferencesStore(
    private val context: Context,
    private val defaultFavoriteIds: Set<String>,
    private val defaultLastRoutePlaceId: String?,
) {

    val state: Flow<PersistedNaviliveState> = context.dataStore.data
        .catch { error ->
            if (error is IOException) {
                emit(emptyPreferences())
            } else {
                throw error
            }
        }
        .map(::mapPreferences)

    suspend fun setFavoriteIds(favoriteIds: Set<String>) {
        context.dataStore.edit { prefs ->
            prefs[Keys.FavoriteIds] = favoriteIds
        }
    }

    suspend fun setLastRoutePlaceId(placeId: String?) {
        context.dataStore.edit { prefs ->
            if (placeId.isNullOrBlank()) {
                prefs.remove(Keys.LastRoutePlaceId)
            } else {
                prefs[Keys.LastRoutePlaceId] = placeId
            }
        }
    }

    suspend fun setOnboardingCompleted(completed: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[Keys.HasCompletedOnboarding] = completed
        }
    }

    suspend fun setLanguage(language: String) {
        context.dataStore.edit { prefs ->
            prefs[Keys.Language] = language
        }
    }

    suspend fun setVibrationEnabled(enabled: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[Keys.VibrationEnabled] = enabled
        }
    }

    suspend fun setAutoRecalculate(enabled: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[Keys.AutoRecalculate] = enabled
        }
    }

    suspend fun setJunctionAlerts(enabled: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[Keys.JunctionAlerts] = enabled
        }
    }

    suspend fun setTurnByTurnAnnouncements(enabled: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[Keys.TurnByTurnAnnouncements] = enabled
        }
    }

    suspend fun setSpeechOutputMode(mode: SpeechOutputMode) {
        context.dataStore.edit { prefs ->
            prefs[Keys.SpeechOutputMode] = mode.storageValue
        }
    }

    suspend fun setSelectedSystemTtsEnginePackage(packageName: String?) {
        context.dataStore.edit { prefs ->
            if (packageName.isNullOrBlank()) {
                prefs.remove(Keys.SelectedSystemTtsEnginePackage)
            } else {
                prefs[Keys.SelectedSystemTtsEnginePackage] = packageName
            }
        }
    }

    suspend fun setSpeechRatePercent(percent: Int) {
        context.dataStore.edit { prefs ->
            prefs[Keys.SpeechRatePercent] = percent
        }
    }

    suspend fun setSpeechVolumePercent(percent: Int) {
        context.dataStore.edit { prefs ->
            prefs[Keys.SpeechVolumePercent] = percent
        }
    }

    suspend fun setDownloadedUpdate(apkPath: String, versionLabel: String) {
        context.dataStore.edit { prefs ->
            prefs[Keys.DownloadedUpdateApkPath] = apkPath
            prefs[Keys.DownloadedUpdateVersionLabel] = versionLabel
        }
    }

    suspend fun clearDownloadedUpdate() {
        context.dataStore.edit { prefs ->
            prefs.remove(Keys.DownloadedUpdateApkPath)
            prefs.remove(Keys.DownloadedUpdateVersionLabel)
        }
    }

    private fun mapPreferences(preferences: Preferences): PersistedNaviliveState {
        return PersistedNaviliveState(
            favoriteIds = preferences[Keys.FavoriteIds] ?: defaultFavoriteIds,
            lastRoutePlaceId = preferences[Keys.LastRoutePlaceId] ?: defaultLastRoutePlaceId,
            hasCompletedOnboarding = preferences[Keys.HasCompletedOnboarding] ?: false,
            settingsState = SettingsState(
                language = preferences[Keys.Language] ?: SettingsState().language,
                vibrationEnabled = preferences[Keys.VibrationEnabled] ?: SettingsState().vibrationEnabled,
                autoRecalculate = preferences[Keys.AutoRecalculate] ?: SettingsState().autoRecalculate,
                junctionAlerts = preferences[Keys.JunctionAlerts] ?: SettingsState().junctionAlerts,
                turnByTurnAnnouncements = preferences[Keys.TurnByTurnAnnouncements]
                    ?: SettingsState().turnByTurnAnnouncements,
                speechOutputMode = SpeechOutputMode.fromStorageValue(preferences[Keys.SpeechOutputMode]),
                selectedSystemTtsEnginePackage = preferences[Keys.SelectedSystemTtsEnginePackage],
                speechRatePercent = preferences[Keys.SpeechRatePercent] ?: SettingsState().speechRatePercent,
                speechVolumePercent = preferences[Keys.SpeechVolumePercent] ?: SettingsState().speechVolumePercent,
            ),
            downloadedUpdateApkPath = preferences[Keys.DownloadedUpdateApkPath],
            downloadedUpdateVersionLabel = preferences[Keys.DownloadedUpdateVersionLabel],
        )
    }

    private object Keys {
        val FavoriteIds = stringSetPreferencesKey("favorite_ids")
        val LastRoutePlaceId = stringPreferencesKey("last_route_place_id")
        val HasCompletedOnboarding = booleanPreferencesKey("has_completed_onboarding")
        val Language = stringPreferencesKey("language")
        val VibrationEnabled = booleanPreferencesKey("vibration_enabled")
        val AutoRecalculate = booleanPreferencesKey("auto_recalculate")
        val JunctionAlerts = booleanPreferencesKey("junction_alerts")
        val TurnByTurnAnnouncements = booleanPreferencesKey("turn_by_turn_announcements")
        val SpeechOutputMode = stringPreferencesKey("speech_output_mode")
        val SelectedSystemTtsEnginePackage = stringPreferencesKey("selected_system_tts_engine_package")
        val SpeechRatePercent = intPreferencesKey("speech_rate_percent")
        val SpeechVolumePercent = intPreferencesKey("speech_volume_percent")
        val DownloadedUpdateApkPath = stringPreferencesKey("downloaded_update_apk_path")
        val DownloadedUpdateVersionLabel = stringPreferencesKey("downloaded_update_version_label")
    }
}
