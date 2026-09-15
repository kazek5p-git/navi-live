package com.navilive.android.data.preferences

import com.navilive.android.model.GeoPoint
import com.navilive.android.model.Place
import com.navilive.android.model.RouteStep
import com.navilive.android.model.RouteStepKind
import com.navilive.android.model.RouteSummary
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class NavigationPersistenceCodecTest {

    @Test
    fun placeRoundTripsWithPointAndOptionalFields() {
        val place = Place(
            id = "favorite-1",
            name = "Sklep Ruterek i GSM",
            address = "Wschodnia 12, Łódź",
            walkDistanceMeters = 0,
            walkEtaMinutes = 0,
            point = GeoPoint(51.760000, 19.460000),
            phone = "+48 123 456 789",
            website = "https://example.invalid",
            savedAtMs = 123_456L,
            savedAccuracyMeters = 8.5f,
        )

        val decoded = NavigationPersistenceCodec.decodePlace(
            NavigationPersistenceCodec.encodePlace(place),
        )

        assertEquals(place, decoded)
    }

    @Test
    fun routeSummaryRoundTripsAllNavigationData() {
        val summary = RouteSummary(
            distanceMeters = 1_250,
            etaMinutes = 17,
            modeLabel = "Pieszo",
            currentInstruction = "Skręć w prawo w Wschodnią",
            nextInstruction = "Idź prosto",
            steps = listOf(
                RouteStep(
                    instruction = "Skręć w prawo w Wschodnią",
                    distanceMeters = 80,
                    maneuverPoint = GeoPoint(51.760000, 19.460000),
                    maneuverType = "turn",
                    maneuverModifier = "right",
                    roadName = "Wschodnia",
                ),
                RouteStep(
                    instruction = "Przejście dla pieszych",
                    distanceMeters = 25,
                    kind = RouteStepKind.PedestrianCrossing,
                    maneuverType = "street_crossing",
                ),
            ),
            pathPoints = listOf(
                GeoPoint(51.759000, 19.459000),
                GeoPoint(51.760000, 19.460000),
            ),
        )

        val decoded = NavigationPersistenceCodec.decodeRouteSummary(
            NavigationPersistenceCodec.encodeRouteSummary(summary),
        )

        assertEquals(summary, decoded)
    }

    @Test
    fun legacyPlaceCoordinatesAreStillReadable() {
        val decoded = NavigationPersistenceCodec.decodePlace(
            JSONObject(
                """
                {
                  "id": "legacy-1",
                  "name": "Stary punkt",
                  "address": "Wschodnia, Łódź",
                  "latitude": 51.76,
                  "longitude": 19.46
                }
                """.trimIndent(),
            ),
        )

        assertNotNull(decoded)
        assertEquals(GeoPoint(51.76, 19.46), decoded?.point)
    }

    @Test
    fun malformedAndIncompleteValuesAreIgnoredSafely() {
        assertEquals(emptyList<Place>(), NavigationPersistenceCodec.decodePlaces("not-json"))
        assertNull(
            NavigationPersistenceCodec.decodePlace(
                JSONObject().put("id", "only-id"),
            ),
        )
    }
}
