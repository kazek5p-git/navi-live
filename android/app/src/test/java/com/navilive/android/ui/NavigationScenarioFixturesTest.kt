package com.navilive.android.ui

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.absolutePathString

class NavigationScenarioFixturesTest {

    @Test
    fun thresholdCalculationsMatchSharedFixtures() {
        val thresholds = loadScenarioCases().getJSONArray("thresholds")
        for (index in 0 until thresholds.length()) {
            val entry = thresholds.getJSONObject(index)
            val accuracyMeters = entry.getDouble("accuracyMeters").toFloat()
            assertEquals(
                entry.getString("name"),
                entry.getDouble("expectedManeuverAdvance"),
                NavigationScenarioCore.maneuverAdvanceThresholdMeters(accuracyMeters),
                0.0001,
            )
            assertEquals(
                entry.getString("name"),
                entry.getInt("expectedOffRoute"),
                NavigationScenarioCore.offRouteThresholdMeters(accuracyMeters),
            )
            assertEquals(
                entry.getString("name"),
                entry.getInt("expectedImmediate"),
                NavigationScenarioCore.immediateAnnouncementThresholdMeters(accuracyMeters),
            )
        }
    }

    @Test
    fun countdownMilestonesMatchSharedFixtures() {
        val countdowns = loadScenarioCases().getJSONArray("countdowns")
        for (index in 0 until countdowns.length()) {
            val entry = countdowns.getJSONObject(index)
            val expected = if (entry.isNull("expectedMilestone")) null else entry.getInt("expectedMilestone")
            assertEquals(
                entry.getString("name"),
                expected,
                NavigationScenarioCore.countdownMilestoneMeters(entry.getInt("distanceToNextMeters")),
            )
        }
    }

    @Test
    fun advanceDecisionsMatchSharedFixtures() {
        val cases = loadScenarioCases().getJSONArray("advanceDecisions")
        for (index in 0 until cases.length()) {
            val entry = cases.getJSONObject(index)
            assertEquals(
                entry.getString("name"),
                entry.getBoolean("expectedAdvance"),
                NavigationScenarioCore.shouldAdvanceStep(
                    distanceToManeuverMeters = entry.getDouble("distanceToManeuverMeters"),
                    accuracyMeters = entry.getDouble("accuracyMeters").toFloat(),
                ),
            )
        }
    }

    @Test
    fun offRouteDecisionsMatchSharedFixtures() {
        val cases = loadScenarioCases().getJSONArray("offRouteDecisions")
        for (index in 0 until cases.length()) {
            val entry = cases.getJSONObject(index)
            val deviation = if (entry.isNull("deviationMeters")) null else entry.getInt("deviationMeters")
            assertEquals(
                entry.getString("name"),
                entry.getBoolean("expectedOffRoute"),
                NavigationScenarioCore.shouldTriggerOffRoute(
                    deviationMeters = deviation,
                    accuracyMeters = entry.getDouble("accuracyMeters").toFloat(),
                ),
            )
        }
    }

    @Test
    fun autoRecalculateDecisionsMatchSharedFixtures() {
        val cases = loadScenarioCases().getJSONArray("autoRecalculate")
        for (index in 0 until cases.length()) {
            val entry = cases.getJSONObject(index)
            assertEquals(
                entry.getString("name"),
                entry.getBoolean("expectedAllowed"),
                NavigationScenarioCore.shouldAllowAutoRecalculate(
                    isRouteRecalculating = entry.getBoolean("isRouteRecalculating"),
                    elapsedSinceLastRecalculateMs = entry.getLong("elapsedMs"),
                ),
            )
        }
    }

    private fun loadScenarioCases() = loadFixtures().getJSONObject("scenarioCases")

    private fun loadFixtures(): JSONObject {
        val fixturePath = locateFixtureFile()
        return JSONObject(String(Files.readAllBytes(fixturePath)))
    }

    private fun locateFixtureFile(): Path {
        var current = Path.of("").toAbsolutePath()
        while (current != null) {
            val candidate = current.resolve("shared").resolve("test-fixtures").resolve("navigation-parity-fixtures.json")
            if (Files.exists(candidate)) {
                return candidate
            }
            current = current.parent
        }
        error("Could not locate shared fixture file from ${Path.of("").toAbsolutePath().absolutePathString()}")
    }
}
