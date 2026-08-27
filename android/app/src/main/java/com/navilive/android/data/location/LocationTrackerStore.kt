package com.navilive.android.data.location

import com.navilive.android.model.LocationFix
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

data class TrackerState(
    val latestFix: LocationFix? = null,
    val isTracking: Boolean = false,
)

object LocationTrackerStore {
    private val _state = MutableStateFlow(TrackerState())
    private val stabilizer = LocationFixStabilizer()
    private var latestGpsFix: LocationFix? = null
    private var lastAppliedRadioTimestampMs: Long = 0L
    val state: StateFlow<TrackerState> = _state.asStateFlow()

    @Synchronized
    fun setTracking(enabled: Boolean) {
        if (!enabled) {
            stabilizer.reset()
            latestGpsFix = null
            lastAppliedRadioTimestampMs = 0L
        }
        _state.update { current -> current.copy(isTracking = enabled) }
    }

    @Synchronized
    fun pushFix(fix: LocationFix) {
        latestGpsFix = fix
        val stabilizedFix = stabilizer.stabilize(fix) ?: return
        _state.update { current -> current.copy(latestFix = stabilizedFix) }
    }

    /**
     * Przyjmuje korektę radiową tylko względem ostatniego surowego GPS-u.
     * Brak GPS-u albo niezgodny wynik beaconDB nie zmienia stanu aplikacji.
     */
    @Synchronized
    fun pushRadioEstimate(estimate: RadioLocationEstimate) {
        if (estimate.timestampMs <= lastAppliedRadioTimestampMs) return
        val gpsFix = latestGpsFix ?: return
        val fusedFix = RadioLocationFusion.fuse(
            gpsFix = gpsFix,
            radioEstimate = estimate,
            nowMs = System.currentTimeMillis(),
        ) ?: return
        val stabilizedFix = stabilizer.stabilize(fusedFix) ?: return
        lastAppliedRadioTimestampMs = estimate.timestampMs
        _state.update { current -> current.copy(latestFix = stabilizedFix) }
    }
}
