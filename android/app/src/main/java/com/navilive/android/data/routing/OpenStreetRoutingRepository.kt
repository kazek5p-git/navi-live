package com.navilive.android.data.routing

import android.content.Context
import androidx.annotation.StringRes
import com.navilive.android.R
import com.navilive.android.model.GeoPoint
import com.navilive.android.model.Place
import com.navilive.android.model.RouteStep
import com.navilive.android.model.RouteSummary
import com.navilive.android.model.SharedProductRules
import com.navilive.android.ui.NavigationScenarioCore
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

    private enum class PlaceKind {
        Shop,
        ParcelLocker,
        RailStation,
        BusStop,
        TramStop,
        Other,
    }

    private data class SearchIntent(
        val normalizedQuery: String,
        val tokens: List<String>,
        val nameSearchTerms: List<String>,
        val wantsShop: Boolean,
        val wantsParcelLocker: Boolean,
        val wantsRailStation: Boolean,
    ) {
        val wantsAnyCategory: Boolean = wantsShop || wantsParcelLocker || wantsRailStation
    }

    private val appContext = context.applicationContext

    private val shopQueryTerms = setOf(
        "sklep",
        "sklepy",
        "sklepu",
        "market",
        "supermarket",
        "spozywczy",
        "spożywczy",
        "grocery",
        "store",
    )
    private val parcelLockerQueryTerms = setOf(
        "paczkomat",
        "paczkomaty",
        "paczka",
        "parcel",
        "locker",
        "inpost",
    )
    private val railStationQueryTerms = setOf(
        "pkp",
        "kolej",
        "kolejowa",
        "kolejowy",
        "stacja",
        "dworzec",
        "pociag",
        "pociąg",
        "train",
        "railway",
        "station",
    )
    private val categoryQueryTerms = shopQueryTerms + parcelLockerQueryTerms + railStationQueryTerms

    suspend fun searchPlaces(query: String, currentPoint: GeoPoint?): List<Place> {
        if (query.isBlank()) {
            return emptyList()
        }
        return withContext(Dispatchers.IO) {
            val intent = searchIntent(query)
            val combined = linkedMapOf<String, SearchCandidate>()
            if (currentPoint != null) {
                runCatching {
                    queryLocalPoiCandidates(
                        query = query,
                        currentPoint = currentPoint,
                        intent = intent,
                    )
                }.getOrDefault(emptyList()).forEach { candidate ->
                    combined[candidate.place.id] = candidate
                }
            }
            val nearby = querySearchCandidates(
                query = query,
                currentPoint = currentPoint,
                nearbyOnly = true,
                intent = intent,
            )
            nearby.forEach { candidate ->
                val existing = combined[candidate.place.id]
                if (existing == null || isBetterSearchCandidate(candidate, existing)) {
                    combined[candidate.place.id] = candidate
                }
            }
            val includeGlobalFallback =
                combined.size < SharedProductRules.Search.includeGlobalFallbackIfFewerThan
            if (includeGlobalFallback) {
                querySearchCandidates(
                    query = query,
                    currentPoint = currentPoint,
                    nearbyOnly = false,
                    intent = intent,
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
            val etaMinutes = NavigationScenarioCore.routeEtaMinutes(
                distanceMeters = distance,
                providerDurationSeconds = duration,
            )

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

    private fun candidateName(item: JSONObject, fallback: String, kind: PlaceKind): String {
        val explicitName = item.optString("name").ifBlank {
            item.optJSONObject("namedetails")
                ?.optString("name")
                .orEmpty()
        }
        val baseName = explicitName.ifBlank {
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
        return labelForKind(baseName, kind)
    }

    private fun queryLocalPoiCandidates(
        query: String,
        currentPoint: GeoPoint,
        intent: SearchIntent,
    ): List<SearchCandidate> {
        val endpoints = buildOverpassEndpoints(currentPoint, intent)
        if (endpoints.isEmpty()) return emptyList()
        var response: String? = null
        for (endpoint in endpoints) {
            response = runCatching { requestText(endpoint) }.getOrNull()
            if (response != null) break
        }
        response ?: return emptyList()
        val elements = JSONObject(response).optJSONArray("elements") ?: return emptyList()
        val candidates = mutableListOf<SearchCandidate>()
        for (index in 0 until elements.length()) {
            val item = elements.optJSONObject(index) ?: continue
            val tags = item.optJSONObject("tags")?.toStringMap().orEmpty()
            val point = overpassPoint(item) ?: continue
            val distance = haversineMeters(currentPoint, point).roundToInt()
            if (distance > SharedProductRules.Search.localPoiRadiusMeters) continue
            val kind = overpassKind(tags)
            if (!shouldKeepLocalPoi(tags, kind, intent)) continue
            val name = overpassName(tags, kind)
            val address = overpassAddress(tags, name)
            val place = Place(
                id = "overpass_${item.optString("type")}_${item.optLong("id")}",
                name = labelForKind(name, kind),
                address = address,
                walkDistanceMeters = distance,
                walkEtaMinutes = if (distance > 0) {
                    NavigationScenarioCore.distanceBasedEtaMinutes(distance)
                } else {
                    0
                },
                point = point,
                phone = tags["phone"] ?: tags["contact:phone"],
                website = tags["website"] ?: tags["contact:website"],
            )
            candidates += SearchCandidate(
                place = place,
                score = searchScore(place, query, currentPoint) +
                    SharedProductRules.Search.localPoiScore +
                    categoryAffinityScore(intent, kind),
                distanceMeters = distance,
                importance = 0.0,
                isNearbyCandidate = true,
            )
        }
        return candidates
    }

    private fun buildOverpassEndpoints(currentPoint: GeoPoint, intent: SearchIntent): List<String> {
        val selectors = mutableListOf<String>()
        val radius = SharedProductRules.Search.localPoiRadiusMeters
        val lat = formatCoordinate(currentPoint.latitude)
        val lon = formatCoordinate(currentPoint.longitude)
        val nameRegex = overpassNameRegex(intent)
        if (nameRegex != null) {
            selectors += overpassSelectors(radius, lat, lon, "[\"name\"~\"$nameRegex\",i]")
        }
        if (intent.wantsShop) {
            selectors += overpassSelectors(radius, lat, lon, "[\"shop\"]")
        }
        if (intent.wantsParcelLocker) {
            selectors += overpassSelectors(radius, lat, lon, "[\"amenity\"=\"parcel_locker\"]")
        }
        if (intent.wantsRailStation) {
            selectors += overpassSelectors(radius, lat, lon, "[\"railway\"~\"^(station|halt)$\"]")
            selectors += overpassSelectors(radius, lat, lon, "[\"public_transport\"=\"station\"]")
        }
        if (selectors.isEmpty()) return emptyList()

        val query = buildString {
            append("[out:json][timeout:")
            append(SharedProductRules.Search.overpassTimeoutSeconds)
            append("];")
            append("(")
            selectors.forEach(::append)
            append(");out center ")
            append(SharedProductRules.Search.localPoiLimit)
            append(";")
        }
        val encodedQuery = URLEncoder.encode(query, Charsets.UTF_8.name())
        return listOf(
            "https://overpass.kumi.systems/api/interpreter?data=$encodedQuery",
            "https://overpass-api.de/api/interpreter?data=$encodedQuery",
        )
    }

    private fun overpassSelectors(radius: Int, lat: String, lon: String, filter: String): List<String> {
        val around = "(around:$radius,$lat,$lon)"
        return listOf(
            "node$around$filter;",
            "way$around$filter;",
            "relation$around$filter;",
        )
    }

    private fun overpassNameRegex(intent: SearchIntent): String? {
        val terms = intent.nameSearchTerms.ifEmpty { intent.tokens }
            .filter { it.length >= 2 }
            .take(4)
        if (terms.isEmpty()) return null
        return terms.joinToString(".*") { overpassRegexTerm(it) }
    }

    private fun overpassRegexTerm(term: String): String {
        return when (term) {
            "zabka" -> "[zż]abka"
            else -> Regex.escape(term)
        }
    }

    private fun overpassPoint(item: JSONObject): GeoPoint? {
        val latitude = item.optDouble("lat", Double.NaN)
        val longitude = item.optDouble("lon", Double.NaN)
        if (!latitude.isNaN() && !longitude.isNaN()) {
            return GeoPoint(latitude, longitude)
        }
        val center = item.optJSONObject("center") ?: return null
        val centerLatitude = center.optDouble("lat", Double.NaN)
        val centerLongitude = center.optDouble("lon", Double.NaN)
        return if (!centerLatitude.isNaN() && !centerLongitude.isNaN()) {
            GeoPoint(centerLatitude, centerLongitude)
        } else {
            null
        }
    }

    private fun overpassName(tags: Map<String, String>, kind: PlaceKind): String {
        val name = tags["name"]?.trim().orEmpty()
        if (name.isNotBlank()) return name
        return when (kind) {
            PlaceKind.Shop -> string(R.string.search_type_unnamed_shop)
            PlaceKind.ParcelLocker -> string(R.string.search_type_unnamed_parcel_locker)
            PlaceKind.RailStation -> string(R.string.search_type_unnamed_rail_station)
            PlaceKind.BusStop -> string(R.string.search_type_unnamed_bus_stop)
            PlaceKind.TramStop -> string(R.string.search_type_unnamed_tram_stop)
            PlaceKind.Other -> string(R.string.generic_unknown_place)
        }
    }

    private fun overpassAddress(tags: Map<String, String>, fallback: String): String {
        val street = tags["addr:street"].orEmpty()
        val houseNumber = tags["addr:housenumber"].orEmpty()
        val locality = tags["addr:city"] ?: tags["addr:town"] ?: tags["addr:village"] ?: tags["addr:suburb"]
        val streetPart = when {
            street.isNotBlank() && houseNumber.isNotBlank() -> "$street $houseNumber"
            street.isNotBlank() -> street
            houseNumber.isNotBlank() -> houseNumber
            else -> ""
        }
        return listOf(streetPart, locality.orEmpty())
            .filter { it.isNotBlank() }
            .joinToString(", ")
            .ifBlank { fallback }
    }

    private fun shouldKeepLocalPoi(tags: Map<String, String>, kind: PlaceKind, intent: SearchIntent): Boolean {
        if (intent.wantsShop && kind == PlaceKind.Shop) return true
        if (intent.wantsParcelLocker && kind == PlaceKind.ParcelLocker) return true
        if (intent.wantsRailStation && (kind == PlaceKind.RailStation || kind == PlaceKind.BusStop || kind == PlaceKind.TramStop)) {
            return true
        }
        val normalizedName = normalizeForSearch(tags["name"].orEmpty())
        return intent.nameSearchTerms.all { normalizedName.contains(it) }
    }

    private fun overpassKind(tags: Map<String, String>): PlaceKind {
        val shop = tags["shop"].orEmpty()
        val amenity = tags["amenity"].orEmpty()
        val railway = tags["railway"].orEmpty()
        val publicTransport = tags["public_transport"].orEmpty()
        return when {
            shop.isNotBlank() -> PlaceKind.Shop
            amenity == "parcel_locker" -> PlaceKind.ParcelLocker
            railway == "station" || railway == "halt" -> PlaceKind.RailStation
            tags["station"] == "railway" || tags["train"] == "yes" && publicTransport == "station" -> PlaceKind.RailStation
            tags["highway"] == "bus_stop" || tags["bus"] == "yes" && publicTransport == "platform" -> PlaceKind.BusStop
            railway == "tram_stop" || tags["tram"] == "yes" && publicTransport == "platform" -> PlaceKind.TramStop
            else -> PlaceKind.Other
        }
    }

    private fun querySearchCandidates(
        query: String,
        currentPoint: GeoPoint?,
        nearbyOnly: Boolean,
        intent: SearchIntent,
    ): List<SearchCandidate> {
        val endpoint = buildSearchEndpoint(
            query = query,
            currentPoint = currentPoint,
            nearbyOnly = nearbyOnly,
        )
        val response = requestText(endpoint)
        val array = JSONArray(response)
        val candidates = mutableListOf<SearchCandidate>()
        val radiusKm = if (nearbyOnly) {
            SharedProductRules.Search.nearbyRadiusKm
        } else {
            SharedProductRules.Search.globalRadiusKm
        }
        val maxDistanceMeters = currentPoint?.let { (radiusKm * 1000).roundToInt() }
        for (index in 0 until array.length()) {
            val item = array.getJSONObject(index)
            val latitude = item.optString("lat").toDoubleOrNull() ?: continue
            val longitude = item.optString("lon").toDoubleOrNull() ?: continue
            val displayName = item.optString("display_name").ifBlank { string(R.string.generic_unknown_place) }
            val address = formatAddress(item.optJSONObject("address"), displayName)
            val kind = nominatimKind(item)
            val label = candidateName(item, displayName, kind)
            val point = GeoPoint(latitude, longitude)
            val distance = if (currentPoint == null) {
                0
            } else {
                haversineMeters(currentPoint, point).roundToInt()
            }
            if (maxDistanceMeters != null && distance > maxDistanceMeters) {
                continue
            }
            val etaMinutes = if (distance <= 0) {
                0
            } else {
                NavigationScenarioCore.distanceBasedEtaMinutes(distance)
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
                    categoryAffinityScore(intent, kind) +
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

    private fun searchIntent(query: String): SearchIntent {
        val normalized = normalizeForSearch(query)
        val tokens = normalized.split(' ').filter { it.isNotBlank() }
        val wantsShop = tokens.any { it in shopQueryTerms }
        val wantsParcelLocker = tokens.any { it in parcelLockerQueryTerms }
        val wantsRailStation = tokens.any { it in railStationQueryTerms }
        val nameSearchTerms = tokens.filterNot { it in categoryQueryTerms }
        return SearchIntent(
            normalizedQuery = normalized,
            tokens = tokens,
            nameSearchTerms = nameSearchTerms,
            wantsShop = wantsShop,
            wantsParcelLocker = wantsParcelLocker,
            wantsRailStation = wantsRailStation,
        )
    }

    private fun nominatimKind(item: JSONObject): PlaceKind {
        val category = item.optString("category")
        val type = item.optString("type")
        return when {
            category == "shop" -> PlaceKind.Shop
            category == "amenity" && type == "parcel_locker" -> PlaceKind.ParcelLocker
            category == "railway" && (type == "station" || type == "halt") -> PlaceKind.RailStation
            category == "public_transport" && type == "station" -> PlaceKind.RailStation
            category == "highway" && type == "bus_stop" -> PlaceKind.BusStop
            category == "public_transport" && type == "platform" -> PlaceKind.BusStop
            category == "railway" && type == "tram_stop" -> PlaceKind.TramStop
            else -> PlaceKind.Other
        }
    }

    private fun categoryAffinityScore(intent: SearchIntent, kind: PlaceKind): Int {
        var score = 0
        if (intent.wantsShop && kind == PlaceKind.Shop) {
            score += SharedProductRules.Search.categoryMatchScore
        }
        if (intent.wantsParcelLocker && kind == PlaceKind.ParcelLocker) {
            score += SharedProductRules.Search.categoryMatchScore
        }
        if (intent.wantsRailStation) {
            when (kind) {
                PlaceKind.RailStation -> score += SharedProductRules.Search.railQueryStationScore
                PlaceKind.BusStop -> score -= SharedProductRules.Search.railQueryBusStopPenalty
                PlaceKind.TramStop -> score -= SharedProductRules.Search.railQueryBusStopPenalty / 2
                else -> Unit
            }
        }
        return score
    }

    private fun labelForKind(name: String, kind: PlaceKind): String {
        val trimmed = name.trim()
        return when (kind) {
            PlaceKind.RailStation -> string(R.string.search_type_rail_station, trimmed)
            PlaceKind.BusStop -> string(R.string.search_type_bus_stop, trimmed)
            PlaceKind.TramStop -> string(R.string.search_type_tram_stop, trimmed)
            PlaceKind.ParcelLocker -> {
                if (normalizeForSearch(trimmed).contains("paczkomat") || normalizeForSearch(trimmed).contains("parcel locker")) {
                    trimmed
                } else {
                    string(R.string.search_type_parcel_locker, trimmed)
                }
            }
            else -> trimmed
        }
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
