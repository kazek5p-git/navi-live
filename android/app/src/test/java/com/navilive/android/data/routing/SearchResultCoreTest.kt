package com.navilive.android.data.routing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SearchResultCoreTest {

    @Test
    fun pkpSearchExcludesBusAndTramStops() {
        assertEquals(
            SearchPlaceKind.RailStation,
            SearchResultCore.kindFromNominatim("railway", "station"),
        )
        assertEquals(
            SearchPlaceKind.BusStop,
            SearchResultCore.kindFromNominatim("highway", "bus_stop"),
        )
        assertEquals(
            SearchPlaceKind.TramStop,
            SearchResultCore.kindFromNominatim("railway", "tram_stop"),
        )
        assertTrue(
            SearchResultCore.shouldKeepForRailQuery(
                kind = SearchPlaceKind.RailStation,
                wantsTransitStop = false,
            ),
        )
        assertFalse(
            SearchResultCore.shouldKeepForRailQuery(
                kind = SearchPlaceKind.BusStop,
                wantsTransitStop = false,
            ),
        )
        assertFalse(
            SearchResultCore.shouldKeepForRailQuery(
                kind = SearchPlaceKind.TramStop,
                wantsTransitStop = false,
            ),
        )
    }

    @Test
    fun explicitTransitQueryCanStillReturnTransitStops() {
        assertTrue(
            SearchResultCore.shouldKeepForRailQuery(
                kind = SearchPlaceKind.BusStop,
                wantsTransitStop = true,
            ),
        )
    }

    @Test
    fun namedLocalCategoryRequiresMatchingNameTerms() {
        assertTrue(SearchResultCore.localNameMatches("zabka wschodnia", listOf("zabka")))
        assertFalse(SearchResultCore.localNameMatches("biedronka", listOf("zabka")))
        assertTrue(SearchResultCore.localNameMatches("sklep", emptyList()))
    }

    @Test
    fun nearestCandidateWinsWhenSearchScoresAreComparable() {
        val nearest = SearchRankingValues(
            score = 1_000,
            distanceMeters = 180,
            importance = 0.1,
            isNearbyCandidate = true,
        )
        val farther = SearchRankingValues(
            score = 1_350,
            distanceMeters = 1_200,
            importance = 0.9,
            isNearbyCandidate = true,
        )

        val ordered = listOf(farther, nearest).sortedWith(Comparator(SearchResultCore::compareForDisplay))

        assertEquals(nearest, ordered.first())
    }

    @Test
    fun clearlyBetterTextMatchStillWinsOverDistance() {
        val exactFarther = SearchRankingValues(
            score = 2_000,
            distanceMeters = 1_200,
            importance = 0.1,
            isNearbyCandidate = true,
        )
        val weakNearbyMatch = SearchRankingValues(
            score = 900,
            distanceMeters = 180,
            importance = 0.9,
            isNearbyCandidate = true,
        )

        assertTrue(SearchResultCore.compareForDisplay(exactFarther, weakNearbyMatch) < 0)
    }

    @Test
    fun addressFallbackKeepsStreetWithoutInventingHouseNumber() {
        assertEquals(
            "Wschodnia, Łódź",
            AddressFormattingCore.normalizeFallbackAddress("Wschodnia, Łódź"),
        )
        assertEquals(
            "Współrzędne: 51.760000, 19.460000",
            AddressFormattingCore.ensureAddress(
                address = "Żabka",
                placeName = "Żabka",
                fallback = "Współrzędne: 51.760000, 19.460000",
            ),
        )
        assertEquals(
            "Wschodnia, Łódź",
            AddressFormattingCore.ensureAddress(
                address = "Wschodnia, Łódź",
                placeName = "Żabka",
                fallback = "Współrzędne: 51.760000, 19.460000",
            ),
        )
    }
}
