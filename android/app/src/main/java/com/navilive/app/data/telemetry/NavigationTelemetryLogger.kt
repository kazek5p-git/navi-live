package com.navilive.app.data.telemetry

import android.content.Context
import androidx.annotation.StringRes
import com.navilive.app.R
import com.navilive.app.model.DiagnosticsState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.LinkedHashMap
import java.util.Locale
import java.util.UUID

private data class TelemetryEvent(
    val timestampMs: Long,
    val sessionId: String?,
    val type: String,
    val message: String,
    val attributes: Map<String, Any?>,
)

class NavigationTelemetryLogger(
    private val context: Context,
) {

    private val lock = Any()
    private val events = mutableListOf<TelemetryEvent>()
    private var activeSessionId: String? = null
    private var activeSessionLabel: String? = null
    private var lastExportPath: String? = null

    fun beginSession(destinationId: String, destinationName: String) {
        val sessionId = "nav-${System.currentTimeMillis()}-${UUID.randomUUID().toString().take(8)}"
        synchronized(lock) {
            activeSessionId = sessionId
            activeSessionLabel = destinationName
        }
        log(
            type = "session_started",
            message = "Navigation session started.",
            attributes = linkedMapOf(
                "destination_id" to destinationId,
                "destination_name" to destinationName,
            ),
        )
    }

    fun endSession(reason: String) {
        log(
            type = "session_finished",
            message = "Navigation session finished.",
            attributes = linkedMapOf("reason" to reason),
        )
        synchronized(lock) {
            activeSessionId = null
            activeSessionLabel = null
        }
    }

    fun log(
        type: String,
        message: String,
        attributes: Map<String, Any?> = emptyMap(),
    ) {
        synchronized(lock) {
            events += TelemetryEvent(
                timestampMs = System.currentTimeMillis(),
                sessionId = activeSessionId,
                type = type,
                message = message,
                attributes = LinkedHashMap(attributes),
            )
        }
    }

    fun clear() {
        synchronized(lock) {
            events.clear()
            activeSessionId = null
            activeSessionLabel = null
            lastExportPath = null
        }
    }

    fun snapshotState(): DiagnosticsState {
        synchronized(lock) {
            val lastEvent = events.lastOrNull()
            return DiagnosticsState(
                eventCount = events.size,
                activeSessionLabel = activeSessionLabel ?: string(R.string.diagnostics_no_active_session),
                lastEventLabel = lastEvent?.let(::presentEventForUi) ?: string(R.string.diagnostics_no_telemetry),
                lastExportPath = lastExportPath,
            )
        }
    }

    suspend fun exportToFile(): File = withContext(Dispatchers.IO) {
        val snapshot = synchronized(lock) {
            events.toList()
        }
        val folder = debugFolder()
        if (!folder.exists()) {
            folder.mkdirs()
        }
        val timestamp = fileTimestampFormat().format(Date())
        val file = File(folder, "navi-live-telemetry-$timestamp.jsonl")
        file.bufferedWriter().use { writer ->
            snapshot.forEach { event ->
                val payload = JSONObject()
                    .put("timestamp_ms", event.timestampMs)
                    .put("timestamp_local", exportTimestampFormat().format(Date(event.timestampMs)))
                    .put("session_id", event.sessionId)
                    .put("type", event.type)
                    .put("message", event.message)
                    .put("attributes", JSONObject(event.attributes))
                writer.appendLine(payload.toString())
            }
        }
        synchronized(lock) {
            lastExportPath = file.absolutePath
        }
        file
    }

    private fun debugFolder(): File {
        val externalBase = context.getExternalFilesDir("debug")
        val base = externalBase ?: File(context.filesDir, "debug")
        return File(base, "telemetry")
    }

    private fun fileTimestampFormat(): SimpleDateFormat {
        return SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)
    }

    private fun exportTimestampFormat(): SimpleDateFormat {
        return SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    }

    private fun presentEventForUi(event: TelemetryEvent): String {
        return when (event.type) {
            "session_started" -> string(
                R.string.diagnostics_event_session_started,
                stringAttr(event, "destination_name") ?: activeSessionLabel ?: context.getString(R.string.app_name),
            )
            "session_finished" -> when (stringAttr(event, "reason")) {
                "arrived" -> string(R.string.diagnostics_event_session_finished_arrived)
                "stopped" -> string(R.string.diagnostics_event_session_finished_stopped)
                else -> string(
                    R.string.diagnostics_event_session_finished_generic,
                    stringAttr(event, "reason") ?: event.message,
                )
            }
            "location_permission_changed" -> if (boolAttr(event, "granted") == true) {
                string(R.string.diagnostics_event_location_permission_granted)
            } else {
                string(R.string.diagnostics_event_location_permission_revoked)
            }
            "onboarding_completed" -> string(R.string.diagnostics_event_onboarding_completed)
            "favorite_toggled" -> string(R.string.diagnostics_event_favorites_updated)
            "route_requested" -> string(
                R.string.diagnostics_event_route_requested,
                stringAttr(event, "place_name") ?: stringAttr(event, "place_id") ?: context.getString(R.string.app_name),
            )
            "route_loaded" -> routeDistanceEtaLabel(
                event = event,
                fallbackRes = R.string.diagnostics_event_default,
                defaultValue = event.message,
                successRes = R.string.diagnostics_event_route_loaded,
            )
            "route_recalculated" -> routeDistanceEtaLabel(
                event = event,
                fallbackRes = R.string.diagnostics_event_default,
                defaultValue = event.message,
                successRes = R.string.diagnostics_event_route_recalculated,
            )
            "heading_aligned" -> string(R.string.diagnostics_event_heading_aligned)
            "navigation_started" -> string(R.string.diagnostics_event_navigation_started)
            "instruction_repeated" -> string(R.string.diagnostics_event_instruction_repeated)
            "navigation_paused" -> string(R.string.diagnostics_event_navigation_paused)
            "navigation_resumed" -> string(R.string.diagnostics_event_navigation_resumed)
            "route_recalculate_auto_started" -> string(R.string.diagnostics_event_auto_recalculate_started)
            "route_recalculate_manual_started" -> string(R.string.diagnostics_event_manual_recalculate_started)
            "route_recalculate_failed" -> string(R.string.diagnostics_event_recalculate_failed)
            "telemetry_export_requested" -> string(R.string.diagnostics_event_export_requested)
            "off_route_detected" -> {
                val deviation = intAttr(event, "deviation_m")
                if (deviation != null) {
                    string(R.string.diagnostics_event_off_route_detected, deviation)
                } else {
                    string(R.string.diagnostics_event_default, event.message)
                }
            }
            "step_advanced" -> {
                val stepIndex = intAttr(event, "step_index")
                val stepCount = intAttr(event, "step_count")
                if (stepIndex != null && stepCount != null) {
                    string(R.string.diagnostics_event_step_advanced, stepIndex + 1, stepCount)
                } else {
                    string(R.string.diagnostics_event_default, event.message)
                }
            }
            "tracking_state_changed" -> if (boolAttr(event, "is_tracking") == true) {
                string(R.string.diagnostics_event_tracking_started)
            } else {
                string(R.string.diagnostics_event_tracking_stopped)
            }
            "navigation_fix" -> {
                val stepIndex = intAttr(event, "step_index")
                val stepCount = intAttr(event, "step_count")
                if (stepIndex != null && stepCount != null) {
                    string(R.string.diagnostics_event_navigation_fix, stepIndex + 1, stepCount)
                } else {
                    string(R.string.diagnostics_event_default, event.message)
                }
            }
            else -> string(R.string.diagnostics_event_default, event.message)
        }
    }

    private fun routeDistanceEtaLabel(
        event: TelemetryEvent,
        @StringRes fallbackRes: Int,
        defaultValue: String,
        @StringRes successRes: Int,
    ): String {
        val distance = intAttr(event, "distance_m")
        val eta = intAttr(event, "eta_min")
        return if (distance != null && eta != null) {
            string(successRes, distance, eta)
        } else {
            string(fallbackRes, defaultValue)
        }
    }

    private fun stringAttr(event: TelemetryEvent, key: String): String? {
        return event.attributes[key] as? String
    }

    private fun boolAttr(event: TelemetryEvent, key: String): Boolean? {
        return when (val value = event.attributes[key]) {
            is Boolean -> value
            is String -> value.toBooleanStrictOrNull()
            else -> null
        }
    }

    private fun intAttr(event: TelemetryEvent, key: String): Int? {
        return when (val value = event.attributes[key]) {
            is Int -> value
            is Long -> value.toInt()
            is Float -> value.toInt()
            is Double -> value.toInt()
            is Number -> value.toInt()
            is String -> value.toIntOrNull()
            else -> null
        }
    }

    private fun string(@StringRes resId: Int, vararg args: Any): String = context.getString(resId, *args)
}
