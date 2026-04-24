package com.navilive.android.guidance

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.media.AudioFormat
import android.media.AudioAttributes
import android.media.AudioTrack
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.tts.TextToSpeech
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import com.navilive.android.model.SpeechOutputMode
import com.navilive.android.model.SystemTtsEngineOption
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.sin

data class SpeechRuntimeStatus(
    val isScreenReaderActive: Boolean,
    val activeScreenReaderName: String? = null,
    val availableSystemTtsEngines: List<SystemTtsEngineOption> = emptyList(),
    val defaultSystemTtsEngineLabel: String? = null,
    val activeSystemTtsEngineLabel: String? = null,
)

enum class NavigationSoundCue {
    Countdown,
    TurnNow,
    Warning,
    Success,
    Arrival,
}

class GuidanceFeedbackEngine(context: Context) {
    private val appContext = context.applicationContext
    private val accessibilityManager =
        appContext.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager

    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false
    private var speechOutputMode = SpeechOutputMode.System
    private var preferredSystemTtsEnginePackage: String? = null
    private var speechRate = 1.0f
    private var speechVolume = 1.0f
    private var availableSystemTtsEngines: List<SystemTtsEngineOption> = emptyList()
    private var defaultSystemTtsEngineLabel: String? = null
    private var activeSystemTtsEngineLabel: String? = null
    private val soundExecutor = Executors.newSingleThreadExecutor()

    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val manager = appContext.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
        manager.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        appContext.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }

    init {
        recreateTextToSpeech()
    }

    fun updateSpeechPreferences(
        outputMode: SpeechOutputMode,
        systemTtsEnginePackage: String?,
        ratePercent: Int,
        volumePercent: Int,
    ) {
        speechOutputMode = outputMode
        val normalizedEnginePackage = systemTtsEnginePackage?.takeIf { it.isNotBlank() }
        val engineChanged = normalizedEnginePackage != preferredSystemTtsEnginePackage
        preferredSystemTtsEnginePackage = normalizedEnginePackage
        speechRate = (ratePercent.coerceIn(50, 200) / 100f)
        speechVolume = (volumePercent.coerceIn(0, 100) / 100f)

        if (engineChanged || textToSpeech == null) {
            recreateTextToSpeech()
        } else {
            ensureTextToSpeech()
            configureTextToSpeech()
            refreshEngineMetadata()
        }
    }

    fun snapshotSpeechRuntimeStatus(): SpeechRuntimeStatus {
        refreshEngineMetadata()
        val services = activeSpokenFeedbackServices()
        val label = services.firstOrNull()
            ?.resolveInfo
            ?.loadLabel(appContext.packageManager)
            ?.toString()
            ?.takeIf { it.isNotBlank() }
        return SpeechRuntimeStatus(
            isScreenReaderActive = services.isNotEmpty(),
            activeScreenReaderName = label,
            availableSystemTtsEngines = availableSystemTtsEngines,
            defaultSystemTtsEngineLabel = defaultSystemTtsEngineLabel,
            activeSystemTtsEngineLabel = activeSystemTtsEngineLabel,
        )
    }

    fun speak(text: String, flush: Boolean = true) {
        if (text.isBlank()) return
        if (speechOutputMode == SpeechOutputMode.ScreenReader && announceThroughScreenReader(text)) {
            return
        }
        speakThroughSystemTts(text, flush)
    }

    fun speakNavigation(text: String, flush: Boolean = true) {
        if (text.isBlank()) return
        if (speakThroughSystemTts(text, flush)) {
            return
        }
        if (speechOutputMode == SpeechOutputMode.ScreenReader) {
            announceThroughScreenReader(text)
        }
    }

    fun vibrateShort() {
        val vib = vibrator ?: return
        if (!vib.hasVibrator()) return
        vib.vibrate(VibrationEffect.createOneShot(120, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    fun vibrateDouble() {
        val vib = vibrator ?: return
        if (!vib.hasVibrator()) return
        val timings = longArrayOf(0, 90, 70, 90)
        vib.vibrate(VibrationEffect.createWaveform(timings, -1))
    }

    fun playSoundCue(cue: NavigationSoundCue) {
        soundExecutor.execute {
            playToneSequence(cue.toneSequence())
        }
    }

    fun shutdown() {
        shutdownTextToSpeech()
        soundExecutor.shutdownNow()
    }

    private fun shutdownTextToSpeech() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        ttsReady = false
    }

    private fun recreateTextToSpeech() {
        shutdownTextToSpeech()
        ensureTextToSpeech()
    }

    private fun ensureTextToSpeech() {
        if (textToSpeech != null) return
        val requestedEnginePackage = preferredSystemTtsEnginePackage
        textToSpeech = if (requestedEnginePackage == null) {
            TextToSpeech(appContext) { status ->
                handleTextToSpeechInit(status, requestedEnginePackage)
            }
        } else {
            TextToSpeech(appContext, { status ->
                handleTextToSpeechInit(status, requestedEnginePackage)
            }, requestedEnginePackage)
        }
    }

    private fun handleTextToSpeechInit(status: Int, requestedEnginePackage: String?) {
        ttsReady = status == TextToSpeech.SUCCESS
        refreshEngineMetadata(requestedEnginePackage)
        if (ttsReady) {
            configureTextToSpeech()
            return
        }
        if (requestedEnginePackage != null) {
            preferredSystemTtsEnginePackage = requestedEnginePackage
            textToSpeech?.shutdown()
            textToSpeech = null
            TextToSpeech(appContext) { fallbackStatus ->
                handleTextToSpeechInit(fallbackStatus, null)
            }.also {
                textToSpeech = it
            }
        }
    }

    private fun configureTextToSpeech() {
        val tts = textToSpeech ?: return
        if (!ttsReady) return
        tts.language = Locale.getDefault()
        tts.setSpeechRate(speechRate)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            tts.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
        }
    }

    private fun refreshEngineMetadata(requestedEnginePackage: String? = preferredSystemTtsEnginePackage) {
        val tts = textToSpeech ?: return
        val options = tts.engines
            .map { engine ->
                SystemTtsEngineOption(
                    packageName = engine.name,
                    displayName = engine.label.takeIf { it.isNotBlank() } ?: engine.name,
                )
            }
            .distinctBy { it.packageName }
            .sortedBy { it.displayName.lowercase(Locale.getDefault()) }
        availableSystemTtsEngines = options

        val defaultPackage = tts.defaultEngine?.takeIf { it.isNotBlank() }
        defaultSystemTtsEngineLabel = resolveEngineLabel(defaultPackage, options)

        val activePackage = requestedEnginePackage?.takeIf { pkg ->
            options.any { it.packageName == pkg }
        } ?: defaultPackage
        activeSystemTtsEngineLabel = resolveEngineLabel(activePackage, options) ?: defaultSystemTtsEngineLabel
    }

    private fun resolveEngineLabel(
        packageName: String?,
        options: List<SystemTtsEngineOption> = availableSystemTtsEngines,
    ): String? {
        if (packageName.isNullOrBlank()) return null
        return options.firstOrNull { it.packageName == packageName }?.displayName
    }

    private fun speakThroughSystemTts(text: String, flush: Boolean): Boolean {
        ensureTextToSpeech()
        val tts = textToSpeech ?: return false
        if (!ttsReady) return false
        configureTextToSpeech()
        val queueMode = if (flush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, speechVolume)
        }
        return tts.speak(text, queueMode, params, UUID.randomUUID().toString()) != TextToSpeech.ERROR
    }

    private fun playToneSequence(sequence: List<ToneSpec>) {
        if (sequence.isEmpty()) return
        val pcm = generatePcm(sequence)
        if (pcm.isEmpty()) return
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(SoundSampleRate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(pcm.size)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
        runCatching {
            track.write(pcm, 0, pcm.size)
            track.play()
            Thread.sleep(sequence.sumOf { it.durationMs + it.gapAfterMs }.toLong() + 80L)
        }
        track.release()
    }

    private fun generatePcm(sequence: List<ToneSpec>): ByteArray {
        val samples = mutableListOf<Short>()
        sequence.forEach { spec ->
            val toneSamples = SoundSampleRate * spec.durationMs / 1000
            for (sampleIndex in 0 until toneSamples) {
                val progress = sampleIndex.toDouble() / toneSamples.coerceAtLeast(1)
                val envelope = when {
                    progress < 0.12 -> progress / 0.12
                    progress > 0.82 -> (1.0 - progress) / 0.18
                    else -> 1.0
                }.coerceIn(0.0, 1.0)
                val value = sin(2.0 * PI * spec.frequencyHz * sampleIndex / SoundSampleRate)
                samples += (value * envelope * spec.amplitude * Short.MAX_VALUE).toInt().toShort()
            }
            repeat(SoundSampleRate * spec.gapAfterMs / 1000) {
                samples += 0
            }
        }
        val bytes = ByteArray(samples.size * 2)
        samples.forEachIndexed { index, sample ->
            val value = sample.toInt()
            bytes[index * 2] = (value and 0xFF).toByte()
            bytes[index * 2 + 1] = ((value shr 8) and 0xFF).toByte()
        }
        return bytes
    }

    @Suppress("DEPRECATION")
    private fun announceThroughScreenReader(text: String): Boolean {
        val manager = accessibilityManager ?: return false
        if (!manager.isEnabled || activeSpokenFeedbackServices().isEmpty()) return false
        return runCatching {
            val event = AccessibilityEvent.obtain(AccessibilityEvent.TYPE_ANNOUNCEMENT).apply {
                packageName = appContext.packageName
                className = GuidanceFeedbackEngine::class.java.name
                eventTime = System.currentTimeMillis()
                this.text.add(text)
                contentDescription = text
            }
            manager.sendAccessibilityEvent(event)
        }.isSuccess
    }

    private fun activeSpokenFeedbackServices(): List<AccessibilityServiceInfo> {
        val manager = accessibilityManager ?: return emptyList()
        if (!manager.isEnabled) return emptyList()
        return manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_SPOKEN)
    }

    private data class ToneSpec(
        val frequencyHz: Double,
        val durationMs: Int,
        val gapAfterMs: Int = 0,
        val amplitude: Double = 0.13,
    )

    private fun NavigationSoundCue.toneSequence(): List<ToneSpec> {
        return when (this) {
            NavigationSoundCue.Countdown -> listOf(ToneSpec(620.0, 65))
            NavigationSoundCue.TurnNow -> listOf(
                ToneSpec(720.0, 75, gapAfterMs = 22),
                ToneSpec(880.0, 85),
            )
            NavigationSoundCue.Warning -> listOf(
                ToneSpec(520.0, 80, gapAfterMs = 26, amplitude = 0.14),
                ToneSpec(420.0, 90, amplitude = 0.14),
            )
            NavigationSoundCue.Success -> listOf(
                ToneSpec(660.0, 70, gapAfterMs = 22),
                ToneSpec(880.0, 85),
            )
            NavigationSoundCue.Arrival -> listOf(
                ToneSpec(660.0, 75, gapAfterMs = 24),
                ToneSpec(830.0, 85, gapAfterMs = 24),
                ToneSpec(1040.0, 100),
            )
        }
    }

    private companion object {
        const val SoundSampleRate = 44_100
    }
}
