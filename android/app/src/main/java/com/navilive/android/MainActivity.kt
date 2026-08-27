package com.navilive.android

import android.app.LocaleManager
import android.content.res.Configuration
import android.content.Intent
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Bundle
import android.os.LocaleList
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import com.navilive.android.i18n.AppLanguages
import com.navilive.android.ui.NaviLiveViewModel
import com.navilive.android.ui.navigation.NaviLiveNavHost
import com.navilive.android.ui.theme.NaviLiveTheme
import kotlinx.coroutines.launch
import java.util.Locale

class MainActivity : ComponentActivity() {
    private val naviLiveViewModel: NaviLiveViewModel by viewModels()
    private var headphoneMediaSession: MediaSession? = null
    private var headphoneMediaSessionEnabled = false
    private val systemLocaleAtLaunch: Locale = Locale.getDefault()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setupHeadphoneMediaSession()
        observeHeadphoneMediaSessionState()
        setContent {
            NaviLiveTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    NaviLiveNavHost(viewModel = naviLiveViewModel)
                }
            }
        }
    }

    override fun onDestroy() {
        headphoneMediaSession?.release()
        headphoneMediaSession = null
        super.onDestroy()
    }

    private fun setupHeadphoneMediaSession() {
        headphoneMediaSession = MediaSession(this, "NaviLiveGuidanceControls").apply {
            @Suppress("DEPRECATION")
            setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
            setPlaybackState(headphonePlaybackState())
            setCallback(
                object : MediaSession.Callback() {
                    override fun onPlay() {
                        handleHeadphoneGuidanceRequest()
                    }

                    override fun onPause() {
                        handleHeadphoneGuidanceRequest()
                    }

                    override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                        val event = mediaButtonIntent.mediaButtonKeyEvent()
                            ?: return super.onMediaButtonEvent(mediaButtonIntent)
                        if (event.action == KeyEvent.ACTION_UP && event.keyCode.isGuidanceMediaButton()) {
                            handleHeadphoneGuidanceRequest()
                            return true
                        }
                        return super.onMediaButtonEvent(mediaButtonIntent)
                    }
                },
            )
        }
    }

    private fun observeHeadphoneMediaSessionState() {
        lifecycleScope.launch {
            naviLiveViewModel.uiState.collect { state ->
                if (state.isPreferencesLoaded) {
                    applyAppLanguageIfNeeded(state.settingsState.language)
                }
                val shouldBeActive = state.settingsState.headphoneButtonRepeatEnabled &&
                    state.isNavigationLive &&
                    state.activeNavigationState.currentInstruction.isNotBlank()
                if (shouldBeActive != headphoneMediaSessionEnabled) {
                    headphoneMediaSessionEnabled = shouldBeActive
                    headphoneMediaSession?.isActive = shouldBeActive
                }
            }
        }
    }

    private fun applyAppLanguageIfNeeded(languageTag: String) {
        val normalized = AppLanguages.normalize(languageTag)
        if (processAppliedLanguageTag == normalized) return
        if (processAppliedLanguageTag == null && normalized.isBlank() && !hasPlatformAppLanguageOverride()) {
            processAppliedLanguageTag = normalized
            return
        }
        processAppliedLanguageTag = normalized
        if (normalized.isBlank() && Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            applyLegacyAppLanguage(systemLocaleAtLaunch)
        } else if (normalized.isNotBlank() && Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            applyLegacyAppLanguage(Locale.forLanguageTag(normalized))
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val localeManager = getSystemService(LocaleManager::class.java)
            localeManager.applicationLocales = if (normalized.isBlank()) {
                LocaleList.getEmptyLocaleList()
            } else {
                LocaleList.forLanguageTags(normalized)
            }
        }
        recreate()
    }

    private fun hasPlatformAppLanguageOverride(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        return !getSystemService(LocaleManager::class.java).applicationLocales.isEmpty
    }

    @Suppress("DEPRECATION")
    private fun applyLegacyAppLanguage(locale: Locale) {
        Locale.setDefault(locale)
        val configuration = Configuration(resources.configuration)
        configuration.setLocales(LocaleList(locale))
        resources.updateConfiguration(configuration, resources.displayMetrics)
    }

    private fun handleHeadphoneGuidanceRequest() {
        if (!headphoneMediaSessionEnabled) return
        naviLiveViewModel.onHeadphoneButtonRepeatRequested()
    }

    private fun headphonePlaybackState(): PlaybackState {
        return PlaybackState.Builder()
            .setActions(
                PlaybackState.ACTION_PLAY or
                    PlaybackState.ACTION_PAUSE or
                    PlaybackState.ACTION_PLAY_PAUSE,
            )
            .setState(PlaybackState.STATE_PAUSED, 0L, 0f)
            .build()
    }
}

private fun Intent.mediaButtonKeyEvent(): KeyEvent? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
    } else {
        @Suppress("DEPRECATION")
        getParcelableExtra(Intent.EXTRA_KEY_EVENT)
    }
}

private fun Int.isGuidanceMediaButton(): Boolean {
    return this == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE ||
        this == KeyEvent.KEYCODE_MEDIA_PLAY ||
        this == KeyEvent.KEYCODE_MEDIA_PAUSE ||
        this == KeyEvent.KEYCODE_HEADSETHOOK
}

private var processAppliedLanguageTag: String? = null
