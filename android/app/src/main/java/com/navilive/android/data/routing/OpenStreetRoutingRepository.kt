package com.navilive.android.data.routing

import android.content.Context
import androidx.annotation.StringRes
import com.navilive.android.R
import com.navilive.android.model.GeoPoint
import com.navilive.android.model.Place
import com.navilive.android.model.RouteStep
import com.navilive.android.model.RouteSummary
import com.navilive.android.model.SharedProductRules
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.Normalizer
import java.util.Locale
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

class OpenStreetRoutingRepository(
    context: Context,
) {

    private data class SearchCandidate(
        val place: Place,
        val score: Int,
        val distanceMeters: Int,
        val importance: Double,
        val isNearbyCandidate: Boolean,
    )

    private val appContext = context.applicationContext

    suspend fun searchPlaces(query: String, currentPoint: GeoPoint?): List<Place> {
        if (query.isBlank()) {
            return emptyList()
        }
        return withContext(Dispatchers.IO) {
            val nearby = querySearchCandidates(
                query = query,
                currentPoint = currentPoint,
                nearbyOnly = true,
            )
            val includeGlobalFallback =
                nearby.size < SharedProductRules.Search.includeGlobalFallbackIfFewerThan
            val combined = linkedMapOf<String, SearchCandidate>()
            nearby.forEach { candidate ->
                combined[candidate.place.id] = candidate
            }
            if (includeGlobalFallback) {
                querySearchCandidates(
                    query = query,
                    currentPoint = currentPoint,
                    nearbyOnly = false,
                ).forEach { candidate ->
                    val existing = combined[candidate.place.id]
                    if (existing == null || isBetterSearchCandidate(candidate, existing)) {
                        combined[candidate.place.id] = candidate
                    }
                }
            }
            combined.values
                .sortedWith(
                    compareByDescending<SearchCandidate> { it.score }
                        .thenByDescending { it.isNearbyCandidate }
                        .thenBy { if (it.distanceMeters > 0) it.distanceMeters else Int.MAX_VALUE }
                        .thenByDescending { it.importance },
                )
                .map { it.place }
                .take(SharedProductRules.Search.resultLimit)
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
        val displayName = root.optString("display_name")
        formatAddress(root.optJSONObject("address"), displayName).ifBlank {
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
        val roadName = step.optString("name").trim().ifBlank { null }
        val fallbackRoad = roadName ?: string(R.string.generic_next_segment)
        val descriptor = NavigationInstructionCore.describe(
            maneuverType = maneuverType,
            modifier = maneuver?.optString("modifier"),
            roadName = roadName,
        )
        return when (descriptor.strategy) {
            NavigationInstructionDescriptor.Strategy.DepartNamed ->
                string(R.string.route_step_depart, descriptor.roadName ?: fallbackRoad)
            NavigationInstructionDescriptor.Strategy.Arrive ->
                string(R.string.generic_arriving_destination)
            NavigationInstructionDescriptor.Strategy.TurnNamed -> {
                val localizedModifier = routeModifier(descriptor.normalizedModifier)
                string(
                    R.string.route_step_turn_with_modifier,
                    localizedModifier.ifBlank { descriptor.normalizedModifier ?: "" },
                    descriptor.roadName ?: fallbackRoad,
                )
            }
            NavigationInstructionDescriptor.Strategy.TurnGenericNamed ->
                string(R.string.route_step_turn_generic, descriptor.roadName ?: fallbackRoad)
            NavigationInstructionDescriptor.Strategy.TurnBareModifier -> {
                val localizedModifier = routeModifier(descriptor.normalizedModifier)
                if (localizedModifier.isBlank()) {
                    string(R.string.route_step_turn_generic, fallbackRoad)
                } else {
                    string(R.string.route_step_turn_with_modifier, localizedModifier, fallbackRoad)
                }
            }
            NavigationInstructionDescriptor.Strategy.ContinueNamed ->
                string(R.string.route_step_continue, descriptor.roadName ?: fallbackRoad)
            NavigationInstructionDescriptor.Strategy.ProceedTowardNamed ->
                string(R.string.route_step_proceed_toward, descriptor.roadName ?: fallbackRoad)
        }
    }

    private fun routeModifier(modifier: String?): String {
        val normalized = modifier
            ?.let(SharedProductRules.Instructions::normalizeModifier)
            .orEmpty()
        if (normalized !in SharedProductRules.Instructions.supportedModifiers) {
            return modifier.orEmpty()
        }
        return when (normalized) {
            "left" -> string(R.string.route_modifier_left)
            "right" -> string(R.string.route_modifier_right)
            "slight left" -> string(R.string.route_modifier_slight_left)
            "slight right" -> string(R.string.route_modifier_slight_right)
            "sharp left" -> string(R.string.route_modifier_sharp_left)
            "sharp right" -> string(R.string.route_modifier_sharp_right)
            "straight" -> string(R.string.route_modifier_straight)
            "uturn" -> string(R.string.route_modifier_uturn)
            else -> modifier.orEmpty()
        }
    }

    private fun candidateName(item: JSONObject, fallback: String): String {
        val explicitName = item.optString("name").ifBlank {
            item.optJSONObject("namedetails")
                ?.optString("name")
                .orEmpty()
        }
        return explicitName.ifBlank {
            val firstPart = fallback.substringBefore(",").trim()
            if (AddressFormattingCore.isLikelyHouseNumber(firstPart)) {
                fallback.split(",")
                    .map { it.trim() }
                    .firstOrNull { it.isNotBlank() && !AddressFormattingCore.isLikelyHouseNumber(it) }
                    ?: fallback
            } else {
                firstPart.ifBlank { fallback }
            }
        }
    }

    private fun querySearchCandidates(
        query: String,
        currentPoint: GeoPoint?,
        nearbyOnly: Boolean,
    ): List<SearchCandidate> {
        val endpoint = buildSearchEndpoint(
            query = query,
            currentPoint = currentPoint,
            nearbyOnly = nearbyOnly,
        )
        val response = requestText(endpoint)
        val array = JSONArray(response)
        val candidates = mutableListOf<SearchCandidate>()
        for (index in 0 until array.length()) {
            val item = array.getJSONObject(index)
            val latitude = item.optString("lat").toDoubleOrNull() ?: continue
            val longitude = item.optString("lon").toDoubleOrNull() ?: continue
            val displayName = item.optString("display_name").ifBlank { string(R.string.generic_unknown_place) }
            val address = formatAddress(item.optJSONObject("address"), displayName)
            val label = candidateName(item, displayName)
            val point = GeoPoint(latitude, longitude)
            val distance = if (currentPoint == null) {
                0
            } else {
                haversineMeters(currentPoint, point).roundToInt()
            }
            val etaMinutes = if (distance <= 0) {
                0
            } else {
                (distance / SharedProductRules.Search.walkingEtaMetersPerMinute)
                    .roundToInt()
                    .coerceAtLeast(1)
            }
            val place = Place(
                id = "nominatim_${latitude}_$longitude",
                name = label,
                address = address,
                walkDistanceMeters = distance,
                walkEtaMinutes = etaMinutes,
                point = point,
            )
            candidates += SearchCandidate(
                place = place,
                score = searchScore(place, query, currentPoint) +
                    if (nearbyOnly) SharedProductRules.Search.nearbyBonus else 0,
                distanceMeters = distance,
                importance = item.optDouble("importance", 0.0),
                isNearbyCandidate = nearbyOnly,
            )
        }
        return candidates
    }

    private fun buildSearchEndpoint(
        query: String,
        currentPoint: GeoPoint?,
        nearbyOnly: Boolean,
    ): String {
        val encoded = URLEncoder.encode(query, Charsets.UTF_8.name())
        val base = StringBuilder("https://nominatim.openstreetmap.org/search")
        base.append("?format=jsonv2")
        base.append("&limit=").append(
            if (nearbyOnly) {
                SharedProductRules.Search.nearbyLimit
            } else {
                SharedProductRules.Search.globalLimit
            },
        )
        base.append("&addressdetails=1&namedetails=1&dedupe=1")
        if (currentPoint != null) {
            val radiusKm = if (nearbyOnly) {
                SharedProductRules.Search.nearbyRadiusKm
            } else {
                SharedProductRules.Search.globalRadiusKm
            }
            val (left, top, right, bottom) = searchViewBox(currentPoint, radiusKm)
            base.append("&viewbox=")
                .append(formatCoordinate(left))
                .append(',')
                .append(formatCoordinate(top))
                .append(',')
                .append(formatCoordinate(right))
                .append(',')
                .append(formatCoordinate(bottom))
            if (nearbyOnly) {
                base.append("&bounded=1")
            }
        }
        base.append("&q=").append(encoded)
        return base.toString()
    }

    private fun searchViewBox(
        center: GeoPoint,
        radiusKm: Double,
    ): DoubleArray {
        val latDelta = radiusKm / 111.32
        val cosLatitude = cos(Math.toRadians(center.latitude)).let {
            if (it < SharedProductRules.Search.viewBoxMinimumCosine) {
                SharedProductRules.Search.viewBoxMinimumCosine
            } else {
                it
            }
        }
        val lonDelta = radiusKm / (111.32 * cosLatitude)
        val left = center.longitude - lonDelta
        val right = center.longitude + lonDelta
        val top = center.latitude + latDelta
        val bottom = center.latitude - latDelta
        return doubleArrayOf(left, top, right, bottom)
    }

    private fun formatCoordinate(value: Double): String {
        return String.format(Locale.US, "%.6f", value)
    }

    private fun formatAddress(address: JSONObject?, fallback: String): String {
        return AddressFormattingCore.formatAddress(address?.toStringMap(), fallback)
    }

    private fun JSONObject.toStringMap(): Map<String, String> {
        val mapped = linkedMapOf<String, String>()
        val iterator = keys()
        while (iterator.hasNext()) {
            val key = iterator.next()
            mapped[key] = optString(key)
        }
        return mapped
    }

    private fun searchScore(place: Place, query: String, currentPoint: GeoPoint?): Int {
        val normalizedQuery = normalizeForSearch(query)
        if (normalizedQuery.isBlank()) return 0

        val normalizedName = normalizeForSearch(place.name)
        val normalizedAddress = normalizeForSearch(place.address)
        val queryTokens = normalizedQuery.split(' ').filter { it.isNotBlank() }
        val nameTokens = normalizedName.split(' ').filter { it.isNotBlank() }

        var score = 0
        if (normalizedName == normalizedQuery) score += SharedProductRules.Search.exactNameScore
        if (normalizedName.startsWith(normalizedQuery)) {
            score += SharedProductRules.Search.prefixNameScore
        }

        queryTokens.forEach { token ->
            when {
                nameTokens.any { it == token } ->
                    score += SharedProductRules.Search.exactTokenScore
                nameTokens.any { it.startsWith(token) } ->
                    score += SharedProductRules.Search.prefixTokenScore
                normalizedName.contains(token) ->
                    score += SharedProductRules.Search.containsTokenScore
            }
            if (normalizedAddress.contains(token)) {
                score += SharedProductRules.Search.addressTokenScore
            }
        }

        if (currentPoint != null && place.point != null) {
            val distance = haversineMeters(currentPoint, place.point).roundToInt()
            score += SharedProductRules.Search.distanceBands
                .firstOrNull { distance <= it.maxMeters }
                ?.bonus
                ?: 0
            score -= (
                distance / SharedProductRules.Search.distancePenaltyDivisorMeters
                ).coerceAtMost(SharedProductRules.Search.distancePenaltyCap)
        }

        return score
    }

    private fun isBetterSearchCandidate(
        candidate: SearchCandidate,
        existing: SearchCandidate,
    ): Boolean {
        return when {
            candidate.score != existing.score -> candidate.score > existing.score
            candidate.isNearbyCandidate != existing.isNearbyCandidate -> candidate.isNearbyCandidate
            candidate.distanceMeters != existing.distanceMeters -> {
                val candidateDistance = if (candidate.distanceMeters > 0) candidate.distanceMeters else Int.MAX_VALUE
                val existingDistance = if (existing.distanceMeters > 0) existing.distanceMeters else Int.MAX_VALUE
                candidateDistance < existingDistance
            }
            else -> candidate.importance > existing.importance
        }
    }

    private fun normalizeForSearch(text: String): String {
        val normalized = Normalizer.normalize(text.lowercase(Locale.getDefault()), Normalizer.Form.NFD)
        return normalized
            .replace("\\p{Mn}+".toRegex(), "")
            .replace("[^\\p{Alnum}]+".toRegex(), " ")
            .trim()
    }

    private fun string(@StringRes resId: Int, vararg args: Any): String = appContext.getString(resId, *args)

    private fun requestText(rawUrl: String): String {
        val connection = (URL(rawUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 12_000
            readTimeout = 12_000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("User-Agent", "navi-live/0.1 (accessibility-navigation-prototype)")
            setRequestProperty("Accept-Language", Locale.getDefault().toLanguageTag())
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
