package com.navilive.app.data.location

import com.navilive.app.model.LocationFix
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
    val state: StateFlow<TrackerState> = _state.asStateFlow()

    fun setTracking(enabled: Boolean) {
        _state.update { current -> current.copy(isTracking = enabled) }
    }

    fun pushFix(fix: LocationFix) {
        _state.update { current -> current.copy(latestFix = fix) }
    }
}
