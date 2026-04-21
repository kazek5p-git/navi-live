package com.navilive.android.data.routing

import android.content.Context
import androidx.annotation.StringRes
import com.navilive.android.R
import com.navilive.android.model.GeoPoint
import com.navilive.android.model.Place
import com.navilive.android.model.RouteStep
import com.navilive.android.model.RouteSummary
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

class OpenStreetRoutingRepository(
    context: Context,
) {

    private val appContext = context.applicationContext

    suspend fun searchPlaces(query: String, currentPoint: GeoPoint?): List<Place> {
        if (query.isBlank()) {
            return emptyList()
        }
        return withContext(Dispatchers.IO) {
            val encoded = URLEncoder.encode(query, Charsets.UTF_8.name())
            val endpoint =
                "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=8&q=$encoded"
            val response = requestText(endpoint)
            val array = JSONArray(response)
            val places = mutableListOf<Place>()
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                val latitude = item.optString("lat").toDoubleOrNull() ?: continue
                val longitude = item.optString("lon").toDoubleOrNull() ?: continue
                val displayName = item.optString("display_name").ifBlank { string(R.string.generic_unknown_place) }
                val firstLabel = displayName.substringBefore(",").ifBlank { displayName }
                val distance = if (currentPoint == null) {
                    0
                } else {
                    haversineMeters(currentPoint, GeoPoint(latitude, longitude)).roundToInt()
                }
                val etaMinutes = if (distance <= 0) 0 else (distance / 75.0).roundToInt().coerceAtLeast(1)
                places += Place(
                    id = "nominatim_${latitude}_$longitude",
                    name = firstLabel,
                    address = displayName,
                    walkDistanceMeters = distance,
                    walkEtaMinutes = etaMinutes,
                    point = GeoPoint(latitude, longitude),
                )
            }
            places
        }
    }

    suspend fun buildWalkingRoute(from: GeoPoint, to: GeoPoint): RouteSummary {
        return withContext(Dispatchers.IO) {
            val url =
                "https://router.project-osrm.org/route/v1/foot/" +
                    "${from.longitude},${from.latitude};${to.longitude},${to.latitude}" +
                    "?overview=full&steps=true&alternatives=false&geometries=geojson"
            val response = requestText(url)
            val root = JSONObject(response)
            val routes = root.optJSONArray("routes")
            if (routes == null || routes.length() == 0) {
                throw IllegalStateException("Routing service returned no routes.")
            }
            val route = routes.getJSONObject(0)
            val distance = route.optDouble("distance", 0.0).roundToInt()
            val duration = route.optDouble("duration", 0.0)
            val etaMinutes = (duration / 60.0).roundToInt().coerceAtLeast(1)

            val steps = route
                .optJSONArray("legs")
                ?.optJSONObject(0)
                ?.optJSONArray("steps")
            val parsedSteps = parseSteps(steps)
            val pathPoints = parsePath(route.optJSONObject("geometry"))

            val currentInstruction = stepInstruction(steps, 0)
            val nextInstruction = stepInstruction(steps, 1)

            RouteSummary(
                distanceMeters = distance,
                etaMinutes = etaMinutes,
                modeLabel = string(R.string.generic_route_mode_walk),
                currentInstruction = currentInstruction,
                nextInstruction = nextInstruction,
                steps = parsedSteps,
                pathPoints = pathPoints,
            )
        }
    }

    suspend fun reverseGeocode(point: GeoPoint): String = withContext(Dispatchers.IO) {
        val endpoint =
            "https://nominatim.openstreetmap.org/reverse?format=jsonv2" +
                "&lat=${point.latitude}&lon=${point.longitude}&zoom=18&addressdetails=1"
        val response = requestText(endpoint)
        val root = JSONObject(response)
        root.optString("display_name").ifBlank {
            val lat = "%.5f".format(point.latitude)
            val lon = "%.5f".format(point.longitude)
            string(R.string.format_coordinates_label, lat, lon)
        }
    }

    private fun stepInstruction(steps: JSONArray?, index: Int): String {
        if (steps == null || steps.length() <= index) return string(R.string.generic_follow_route_guidance)
        val step = steps.optJSONObject(index) ?: return string(R.string.generic_follow_route_guidance)
        return instructionForStep(step)
    }

    private fun parseSteps(steps: JSONArray?): List<RouteStep> {
        if (steps == null || steps.length() == 0) {
            return listOf(RouteStep(instruction = string(R.string.generic_follow_route_guidance), distanceMeters = 0))
        }
        val parsed = mutableListOf<RouteStep>()
        for (index in 0 until steps.length()) {
            val step = steps.optJSONObject(index) ?: continue
            val maneuver = step.optJSONObject("maneuver")
            val location = maneuver?.optJSONArray("location")
            val maneuverPoint = if (location != null && location.length() >= 2) {
                GeoPoint(
                    latitude = location.optDouble(1),
                    longitude = location.optDouble(0),
                )
            } else {
                null
            }
            parsed += RouteStep(
                instruction = instructionForStep(step),
                distanceMeters = step.optDouble("distance", 0.0).roundToInt(),
                maneuverPoint = maneuverPoint,
            )
        }
        return parsed.ifEmpty {
            listOf(RouteStep(instruction = string(R.string.generic_follow_route_guidance), distanceMeters = 0))
        }
    }

    private fun parsePath(geometry: JSONObject?): List<GeoPoint> {
        val coordinates = geometry?.optJSONArray("coordinates") ?: return emptyList()
        val points = ArrayList<GeoPoint>(coordinates.length())
        for (index in 0 until coordinates.length()) {
            val coordinate = coordinates.optJSONArray(index) ?: continue
            if (coordinate.length() < 2) continue
            points += GeoPoint(
                latitude = coordinate.optDouble(1),
                longitude = coordinate.optDouble(0),
            )
        }
        return points
    }

    private fun instructionForStep(step: JSONObject): String {
        val maneuver = step.optJSONObject("maneuver")
        val maneuverType = maneuver?.optString("type").orEmpty()
        val modifier = maneuver?.optString("modifier").orEmpty()
        val roadName = step.optString("name").ifBlank { string(R.string.generic_next_segment) }
        return when (maneuverType) {
            "depart" -> string(R.string.route_step_depart, roadName)
            "turn" -> {
                val localizedModifier = routeModifier(modifier)
                if (localizedModifier.isBlank()) {
                    string(R.string.route_step_turn_generic, roadName)
                } else {
                    string(R.string.route_step_turn_with_modifier, localizedModifier, roadName)
                }
            }
            "arrive" -> string(R.string.generic_arriving_destination)
            "new name", "continue" -> string(R.string.route_step_continue, roadName)
            else -> string(R.string.route_step_proceed_toward, roadName)
        }
    }

    private fun routeModifier(modifier: String): String {
        return when (modifier.lowercase()) {
            "left" -> string(R.string.route_modifier_left)
            "right" -> string(R.string.route_modifier_right)
            "slight left" -> string(R.string.route_modifier_slight_left)
            "slight right" -> string(R.string.route_modifier_slight_right)
            "sharp left" -> string(R.string.route_modifier_sharp_left)
            "sharp right" -> string(R.string.route_modifier_sharp_right)
            "straight" -> string(R.string.route_modifier_straight)
            "uturn" -> string(R.string.route_modifier_uturn)
            else -> modifier
        }
    }

    private fun string(@StringRes resId: Int, vararg args: Any): String = appContext.getString(resId, *args)

    private fun requestText(rawUrl: String): String {
        val connection = (URL(rawUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 12_000
            readTimeout = 12_000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("User-Agent", "navi-live/0.1 (accessibility-navigation-prototype)")
        }
        return try {
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val payload = stream.bufferedReader().use { it.readText() }
            if (status !in 200..299) {
                throw IllegalStateException("HTTP $status: $payload")
            }
            payload
        } finally {
            connection.disconnect()
        }
    }

    private fun haversineMeters(a: GeoPoint, b: GeoPoint): Double {
        val earthRadius = 6_371_000.0
        val lat1 = Math.toRadians(a.latitude)
        val lon1 = Math.toRadians(a.longitude)
        val lat2 = Math.toRadians(b.latitude)
        val lon2 = Math.toRadians(b.longitude)
        val dLat = lat2 - lat1
        val dLon = lon2 - lon1
        val h = sin(dLat / 2).pow(2.0) + cos(lat1) * cos(lat2) * sin(dLon / 2).pow(2.0)
        return 2 * earthRadius * asin(sqrt(h))
    }
}
