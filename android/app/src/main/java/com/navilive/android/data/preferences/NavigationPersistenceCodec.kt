package com.navilive.android.data.preferences

import com.navilive.android.model.GeoPoint
import com.navilive.android.model.Place
import com.navilive.android.model.RouteStep
import com.navilive.android.model.RouteStepKind
import com.navilive.android.model.RouteSummary
import org.json.JSONArray
import org.json.JSONObject

internal object NavigationPersistenceCodec {

    fun encodePlaces(places: List<Place>): String {
        return JSONArray().apply {
            places.forEach { put(encodePlace(it)) }
        }.toString()
    }

    fun decodePlaces(json: String?): List<Place> {
        if (json.isNullOrBlank()) return emptyList()
        return runCatching {
            val array = JSONArray(json)
            buildList {
                for (index in 0 until array.length()) {
                    decodePlace(array.optJSONObject(index))?.let(::add)
                }
            }
        }.getOrDefault(emptyList())
    }

    fun encodePlace(place: Place): JSONObject {
        return JSONObject().apply {
            put("id", place.id)
            put("name", place.name)
            put("address", place.address)
            put("walkDistanceMeters", place.walkDistanceMeters)
            put("walkEtaMinutes", place.walkEtaMinutes)
            place.point?.let { put("point", encodePoint(it)) }
            place.phone?.takeIf(String::isNotBlank)?.let { put("phone", it) }
            place.website?.takeIf(String::isNotBlank)?.let { put("website", it) }
            place.savedAtMs?.let { put("savedAtMs", it) }
            place.savedAccuracyMeters?.let { put("savedAccuracyMeters", it.toDouble()) }
        }
    }

    fun decodePlace(value: JSONObject?): Place? {
        if (value == null) return null
        val id = value.optString("id").trim().takeIf(String::isNotEmpty) ?: return null
        val name = value.optString("name").trim().takeIf(String::isNotEmpty) ?: return null
        val point = value.optJSONObject("point")?.let(::decodePoint)
            ?: decodeLegacyPoint(value)
        return Place(
            id = id,
            name = name,
            address = value.optString("address").trim(),
            walkDistanceMeters = value.optInt("walkDistanceMeters", 0).coerceAtLeast(0),
            walkEtaMinutes = value.optInt("walkEtaMinutes", 0).coerceAtLeast(0),
            point = point,
            phone = value.optString("phone").trim().takeIf(String::isNotEmpty),
            website = value.optString("website").trim().takeIf(String::isNotEmpty),
            savedAtMs = value.optLong("savedAtMs", 0L).takeIf { value.has("savedAtMs") && !value.isNull("savedAtMs") },
            savedAccuracyMeters = value.optDouble("savedAccuracyMeters", Double.NaN)
                .takeIf { value.has("savedAccuracyMeters") && it.isFinite() }
                ?.toFloat(),
        )
    }

    fun encodeRouteSummary(summary: RouteSummary): String {
        return JSONObject().apply {
            put("distanceMeters", summary.distanceMeters)
            put("etaMinutes", summary.etaMinutes)
            put("modeLabel", summary.modeLabel)
            put("currentInstruction", summary.currentInstruction)
            put("nextInstruction", summary.nextInstruction)
            put("steps", JSONArray().apply {
                summary.steps.forEach { put(encodeRouteStep(it)) }
            })
            put("pathPoints", JSONArray().apply {
                summary.pathPoints.forEach { put(encodePoint(it)) }
            })
        }.toString()
    }

    fun decodeRouteSummary(json: String?): RouteSummary? {
        if (json.isNullOrBlank()) return null
        return runCatching { decodeRouteSummary(JSONObject(json)) }.getOrNull()
    }

    private fun decodeRouteSummary(value: JSONObject): RouteSummary {
        val steps = buildList {
            val array = value.optJSONArray("steps") ?: JSONArray()
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                add(decodeRouteStep(item))
            }
        }
        val pathPoints = buildList {
            val array = value.optJSONArray("pathPoints") ?: JSONArray()
            for (index in 0 until array.length()) {
                decodePoint(array.optJSONObject(index))?.let(::add)
            }
        }
        return RouteSummary(
            distanceMeters = value.optInt("distanceMeters", 0).coerceAtLeast(0),
            etaMinutes = value.optInt("etaMinutes", 0).coerceAtLeast(0),
            modeLabel = value.optString("modeLabel"),
            currentInstruction = value.optString("currentInstruction"),
            nextInstruction = value.optString("nextInstruction"),
            steps = steps,
            pathPoints = pathPoints,
        )
    }

    private fun encodeRouteStep(step: RouteStep): JSONObject {
        return JSONObject().apply {
            put("instruction", step.instruction)
            put("distanceMeters", step.distanceMeters)
            step.maneuverPoint?.let { put("maneuverPoint", encodePoint(it)) }
            put("kind", step.kind.toBackupValue())
            step.maneuverType?.let { put("maneuverType", it) }
            step.maneuverModifier?.let { put("maneuverModifier", it) }
            step.roadName?.let { put("roadName", it) }
        }
    }

    private fun decodeRouteStep(value: JSONObject): RouteStep {
        val kind = when (value.optString("kind").replace("_", "").lowercase()) {
            "pedestriancrossing" -> RouteStepKind.PedestrianCrossing
            else -> RouteStepKind.Instruction
        }
        return RouteStep(
            instruction = value.optString("instruction"),
            distanceMeters = value.optInt("distanceMeters", 0).coerceAtLeast(0),
            maneuverPoint = value.optJSONObject("maneuverPoint")?.let(::decodePoint),
            kind = kind,
            maneuverType = value.optString("maneuverType").takeIf(String::isNotEmpty),
            maneuverModifier = value.optString("maneuverModifier").takeIf(String::isNotEmpty),
            roadName = value.optString("roadName").takeIf(String::isNotEmpty),
        )
    }

    private fun RouteStepKind.toBackupValue(): String = when (this) {
        RouteStepKind.Instruction -> "instruction"
        RouteStepKind.PedestrianCrossing -> "pedestrianCrossing"
    }

    private fun encodePoint(point: GeoPoint): JSONObject {
        return JSONObject()
            .put("latitude", point.latitude)
            .put("longitude", point.longitude)
    }

    private fun decodePoint(value: JSONObject?): GeoPoint? {
        if (value == null) return null
        val latitude = value.optDouble("latitude", Double.NaN)
        val longitude = value.optDouble("longitude", Double.NaN)
        if (!latitude.isFinite() || !longitude.isFinite()) return null
        if (latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return null
        return GeoPoint(latitude = latitude, longitude = longitude)
    }

    private fun decodeLegacyPoint(value: JSONObject): GeoPoint? {
        if (!value.has("latitude") || !value.has("longitude")) return null
        return decodePoint(value)
    }
}
