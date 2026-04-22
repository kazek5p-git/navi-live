package com.navilive.android.data.preferences

import android.content.Context
import android.provider.Settings
import androidx.datastore.core.DataMigration
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.navilive.android.model.UpdateChannel
import com.navilive.android.model.SpeechOutputMode
import com.navilive.android.model.SettingsState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import java.io.File
import java.io.IOException

private const val LegacyDataStoreName = "navilive_preferences"
private const val CurrentDataStoreName = "navi_live_preferences"

private val Context.legacyNaviLiveDataStore by preferencesDataStore(name = LegacyDataStoreName)

private val Context.naviLiveDataStore by preferencesDataStore(
    name = CurrentDataStoreName,
    produceMigrations = { context ->
        listOf(legacyPreferencesMigration(context))
    },
)

data class PersistedNaviLiveState(
    val favoriteIds: Set<String>,
    val lastRoutePlaceId: String?,
    val hasCompletedOnboarding: Boolean,
    val settingsState: SettingsState,
    val downloadedUpdateApkPath: String?,
    val downloadedUpdateVersionLabel: String?,
)

class NaviLivePreferencesStore(
    private val context: Context,
    private val defaultFavoriteIds: Set<String>,
    private val defaultLastRoutePlaceId: String?,
) {

    val state: Flow<PersistedNaviLiveState> = context.naviLiveDataStore.data
        .catch { error ->
            if (error is IOException) {
                emit(emptyPreferences())
            } else {
                throw error
            }
        }
        .map(::mapPreferences)

    suspend fun setFavoriteIds(favoriteIds: Set<String>) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.FavoriteIds] = favoriteIds
        }
    }

    suspend fun setLastRoutePlaceId(placeId: String?) {
        context.naviLiveDataStore.edit { prefs ->
            if (placeId.isNullOrBlank()) {
                prefs.remove(Keys.LastRoutePlaceId)
            } else {
                prefs[Keys.LastRoutePlaceId] = placeId
            }
        }
    }

    suspend fun setOnboardingCompleted(completed: Boolean) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.HasCompletedOnboarding] = completed
        }
    }

    suspend fun setLanguage(language: String) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.Language] = language
        }
    }

    suspend fun setShowTutorialOnStartup(enabled: Boolean) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.ShowTutorialOnStartup] = enabled
        }
    }

    suspend fun setVibrationEnabled(enabled: Boolean) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.VibrationEnabled] = enabled
        }
    }

    suspend fun setAutoRecalculate(enabled: Boolean) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.AutoRecalculate] = enabled
        }
    }

    suspend fun setJunctionAlerts(enabled: Boolean) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.JunctionAlerts] = enabled
        }
    }

    suspend fun setTurnByTurnAnnouncements(enabled: Boolean) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.TurnByTurnAnnouncements] = enabled
        }
    }

    suspend fun setUpdateChannel(channel: UpdateChannel) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.UpdateChannel] = channel.storageValue
        }
    }

    suspend fun setSpeechOutputMode(mode: SpeechOutputMode) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.SpeechOutputMode] = mode.storageValue
        }
    }

    suspend fun setSelectedSystemTtsEnginePackage(packageName: String?) {
        context.naviLiveDataStore.edit { prefs ->
            if (packageName.isNullOrBlank()) {
                prefs.remove(Keys.SelectedSystemTtsEnginePackage)
            } else {
                prefs[Keys.SelectedSystemTtsEnginePackage] = packageName
            }
        }
    }

    suspend fun setSpeechRatePercent(percent: Int) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.SpeechRatePercent] = percent
        }
    }

    suspend fun setSpeechVolumePercent(percent: Int) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.SpeechVolumePercent] = percent
        }
    }

    suspend fun setDownloadedUpdate(apkPath: String, versionLabel: String) {
        context.naviLiveDataStore.edit { prefs ->
            prefs[Keys.DownloadedUpdateApkPath] = apkPath
            prefs[Keys.DownloadedUpdateVersionLabel] = versionLabel
        }
    }

    suspend fun clearDownloadedUpdate() {
        context.naviLiveDataStore.edit { prefs ->
            prefs.remove(Keys.DownloadedUpdateApkPath)
            prefs.remove(Keys.DownloadedUpdateVersionLabel)
        }
    }

    private fun mapPreferences(preferences: Preferences): PersistedNaviLiveState {
        return PersistedNaviLiveState(
            favoriteIds = preferences[Keys.FavoriteIds] ?: defaultFavoriteIds,
            lastRoutePlaceId = preferences[Keys.LastRoutePlaceId] ?: defaultLastRoutePlaceId,
            hasCompletedOnboarding = preferences[Keys.HasCompletedOnboarding] ?: false,
            settingsState = SettingsState(
                language = preferences[Keys.Language] ?: SettingsState().language,
                showTutorialOnStartup = preferences[Keys.ShowTutorialOnStartup]
                    ?: SettingsState().showTutorialOnStartup,
                vibrationEnabled = preferences[Keys.VibrationEnabled] ?: SettingsState().vibrationEnabled,
                autoRecalculate = preferences[Keys.AutoRecalculate] ?: SettingsState().autoRecalculate,
                junctionAlerts = preferences[Keys.JunctionAlerts] ?: SettingsState().junctionAlerts,
                turnByTurnAnnouncements = preferences[Keys.TurnByTurnAnnouncements]
                    ?: SettingsState().turnByTurnAnnouncements,
                updateChannel = UpdateChannel.fromStorageValue(preferences[Keys.UpdateChannel]),
                speechOutputMode = SpeechOutputMode.fromStorageValue(preferences[Keys.SpeechOutputMode]),
                selectedSystemTtsEnginePackage = preferences[Keys.SelectedSystemTtsEnginePackage],
                speechRatePercent = preferences[Keys.SpeechRatePercent] ?: systemDefaultSpeechRatePercent(),
                speechVolumePercent = preferences[Keys.SpeechVolumePercent] ?: SettingsState().speechVolumePercent,
            ),
            downloadedUpdateApkPath = preferences[Keys.DownloadedUpdateApkPath],
            downloadedUpdateVersionLabel = preferences[Keys.DownloadedUpdateVersionLabel],
        )
    }

    private fun systemDefaultSpeechRatePercent(): Int {
        return runCatching {
            Settings.Secure.getInt(context.contentResolver, "tts_default_rate")
        }.getOrDefault(SettingsState().speechRatePercent).coerceIn(50, 200)
    }

    private object Keys {
        val FavoriteIds = stringSetPreferencesKey("favorite_ids")
        val LastRoutePlaceId = stringPreferencesKey("last_route_place_id")
        val HasCompletedOnboarding = booleanPreferencesKey("has_completed_onboarding")
        val Language = stringPreferencesKey("language")
        val ShowTutorialOnStartup = booleanPreferencesKey("show_tutorial_on_startup")
        val VibrationEnabled = booleanPreferencesKey("vibration_enabled")
        val AutoRecalculate = booleanPreferencesKey("auto_recalculate")
        val JunctionAlerts = booleanPreferencesKey("junction_alerts")
        val TurnByTurnAnnouncements = booleanPreferencesKey("turn_by_turn_announcements")
        val UpdateChannel = stringPreferencesKey("update_channel")
        val SpeechOutputMode = stringPreferencesKey("speech_output_mode")
        val SelectedSystemTtsEnginePackage = stringPreferencesKey("selected_system_tts_engine_package")
        val SpeechRatePercent = intPreferencesKey("speech_rate_percent")
        val SpeechVolumePercent = intPreferencesKey("speech_volume_percent")
        val DownloadedUpdateApkPath = stringPreferencesKey("downloaded_update_apk_path")
        val DownloadedUpdateVersionLabel = stringPreferencesKey("downloaded_update_version_label")
    }
}

private fun legacyPreferencesMigration(context: Context): DataMigration<Preferences> {
    return object : DataMigration<Preferences> {
        override suspend fun shouldMigrate(currentData: Preferences): Boolean {
            return currentData.asMap().isEmpty() && context.dataStoreFile(LegacyDataStoreName).exists()
        }

        override suspend fun migrate(currentData: Preferences): Preferences {
            val legacyPreferences = context.legacyNaviLiveDataStore.data.first()
            if (legacyPreferences.asMap().isEmpty()) {
                return currentData
            }

            val migrated = mutablePreferencesOf()
            migrated.copyAllFrom(currentData)
            migrated.copyAllFrom(legacyPreferences)
            return migrated
        }

        override suspend fun cleanUp() {
            context.dataStoreFile(LegacyDataStoreName).delete()
        }
    }
}

private fun MutablePreferences.copyAllFrom(source: Preferences) {
    source.asMap().forEach { (key, value) ->
        when (value) {
            is Boolean -> this[key as Preferences.Key<Boolean>] = value
            is Double -> this[key as Preferences.Key<Double>] = value
            is Float -> this[key as Preferences.Key<Float>] = value
            is Int -> this[key as Preferences.Key<Int>] = value
            is Long -> this[key as Preferences.Key<Long>] = value
            is String -> this[key as Preferences.Key<String>] = value
            is Set<*> -> {
                @Suppress("UNCHECKED_CAST")
                this[key as Preferences.Key<Set<String>>] = value.filterIsInstance<String>().toSet()
            }
        }
    }
}

private fun Context.dataStoreFile(storeName: String): File {
    return File(filesDir, "datastore/$storeName.preferences_pb")
}
