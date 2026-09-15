package com.navilive.android.data.routing

import com.navilive.android.model.SharedProductRules
import kotlin.math.abs

/** Kategorie używane do filtrowania i porządkowania wyników wyszukiwania. */
internal enum class SearchPlaceKind {
    Shop,
    ParcelLocker,
    RailStation,
    BusStop,
    TramStop,
    Other,
}

internal data class SearchRankingValues(
    val score: Int,
    val distanceMeters: Int,
    val importance: Double,
    val isNearbyCandidate: Boolean,
)

/** Czyste reguły wyszukiwania współdzielone przez adapter i testy jednostkowe. */
internal object SearchResultCore {

    fun kindFromNominatim(category: String, type: String): SearchPlaceKind {
        return when {
            category == "shop" -> SearchPlaceKind.Shop
            category == "amenity" && type == "parcel_locker" -> SearchPlaceKind.ParcelLocker
            category == "railway" && type in setOf("station", "halt") -> SearchPlaceKind.RailStation
            category == "public_transport" && type == "station" -> SearchPlaceKind.RailStation
            category == "highway" && type == "bus_stop" -> SearchPlaceKind.BusStop
            category == "public_transport" && type in setOf("platform", "stop_position") -> SearchPlaceKind.BusStop
            category == "railway" && type == "tram_stop" -> SearchPlaceKind.TramStop
            else -> SearchPlaceKind.Other
        }
    }

    /** PKP nie powinno zamieniać się w przystanek autobusowy lub tramwajowy. */
    fun shouldKeepForRailQuery(kind: SearchPlaceKind, wantsTransitStop: Boolean): Boolean {
        return wantsTransitStop || kind == SearchPlaceKind.RailStation || kind == SearchPlaceKind.Other
    }

    fun localNameMatches(normalizedName: String, nameSearchTerms: List<String>): Boolean {
        return nameSearchTerms.isEmpty() || nameSearchTerms.all { normalizedName.contains(it) }
    }

    /** Porównuje kandydatów w kolejności prezentowania na liście. */
    fun compareForDisplay(left: SearchRankingValues, right: SearchRankingValues): Int {
        val leftDistance = sortableDistance(left.distanceMeters)
        val rightDistance = sortableDistance(right.distanceMeters)
        val scoreDifference = left.score - right.score
        if (abs(scoreDifference) <= SharedProductRules.Search.nearbyBonus && leftDistance != rightDistance) {
            return leftDistance.compareTo(rightDistance)
        }
        if (scoreDifference != 0) return -scoreDifference
        if (left.isNearbyCandidate != right.isNearbyCandidate) {
            return if (left.isNearbyCandidate) -1 else 1
        }
        if (leftDistance != rightDistance) return leftDistance.compareTo(rightDistance)
        return -left.importance.compareTo(right.importance)
    }

    /** Wybiera lepszą wersję tego samego punktu zwróconą przez inne źródło. */
    fun isBetterDuplicate(left: SearchRankingValues, right: SearchRankingValues): Boolean {
        return when {
            left.score != right.score -> left.score > right.score
            left.isNearbyCandidate != right.isNearbyCandidate -> left.isNearbyCandidate
            left.distanceMeters != right.distanceMeters -> {
                sortableDistance(left.distanceMeters) < sortableDistance(right.distanceMeters)
            }
            else -> left.importance > right.importance
        }
    }

    private fun sortableDistance(distanceMeters: Int): Int {
        return if (distanceMeters > 0) distanceMeters else Int.MAX_VALUE
    }
}
