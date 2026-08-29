package com.navilive.android.data.routing

import com.navilive.android.model.RouteStep
import com.navilive.android.model.RouteStepKind
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RouteAssistantCoreTest {

    @Test
    fun searchNormalizationPreservesNonLatinLettersAndNumbers() {
        assertEquals("магазин 24", SearchTextCore.normalize("МАГАЗИН №24"))
        assertEquals("مخبز ۱۲", SearchTextCore.normalize("مَخْبَز ۱۲"))
        assertEquals("東京駅", SearchTextCore.normalize("東京駅"))
    }

    @Test
    fun classifiesPolishOverviewQuestion() {
        assertEquals(
            RouteAssistantIntent.RouteOverview,
            RouteAssistantCore.intentFor("Podsumuj trasę"),
        )
    }

    @Test
    fun classifiesCurrentInstructionWithDiacritics() {
        assertEquals(
            RouteAssistantIntent.CurrentInstruction,
            RouteAssistantCore.intentFor("Co mam teraz zrobić?"),
        )
    }

    @Test
    fun classifiesCurrentLocationQuestion() {
        assertEquals(
            RouteAssistantIntent.CurrentLocation,
            RouteAssistantCore.intentFor("Gdzie jestem?"),
        )
        assertEquals(
            RouteAssistantIntent.CurrentLocation,
            RouteAssistantCore.intentFor("Jaki mam adres?"),
        )
    }

    @Test
    fun classifiesNaturalShortCurrentInstructionQuestion() {
        assertEquals(
            RouteAssistantIntent.CurrentInstruction,
            RouteAssistantCore.intentFor("Co teraz?"),
        )
    }

    @Test
    fun classifiesRepeatCommandWithoutGuessingAnotherIntent() {
        assertEquals(
            RouteAssistantIntent.RepeatInstruction,
            RouteAssistantCore.intentFor("Powtórz"),
        )
        assertFalse(
            RouteAssistantCore.requiresFreshLocation(RouteAssistantIntent.RepeatInstruction),
        )
    }

    @Test
    fun classifiesNaturalCurrentInstructionWithExtraContext() {
        assertEquals(
            RouteAssistantIntent.CurrentInstruction,
            RouteAssistantCore.intentFor("Powiedz proszę, w którą stronę mam się teraz kierować?"),
        )
    }

    @Test
    fun classifiesNaturalCurrentInstructionWithInsertedVerb() {
        assertEquals(
            RouteAssistantIntent.CurrentInstruction,
            RouteAssistantCore.intentFor("Co jest teraz, mam skręcić czy iść prosto?"),
        )
    }

    @Test
    fun classifiesNaturalNextInstructionWithDifferentWordOrder() {
        assertEquals(
            RouteAssistantIntent.NextInstruction,
            RouteAssistantCore.intentFor("Jak dalej iść?"),
        )
    }

    @Test
    fun classifiesNaturalRouteConcernQuestion() {
        assertEquals(
            RouteAssistantIntent.RouteQuality,
            RouteAssistantCore.intentFor("Co może być nie tak z tą trasą?"),
        )
    }

    @Test
    fun classifiesNaturalCrossingQuestion() {
        assertEquals(
            RouteAssistantIntent.PedestrianCrossing,
            RouteAssistantCore.intentFor("Czy będzie przejście przede mną?"),
        )
    }

    @Test
    fun classifiesNaturalCrossingQuestionWithInsertedWords() {
        assertEquals(
            RouteAssistantIntent.PedestrianCrossing,
            RouteAssistantCore.intentFor("Czy muszę teraz przejść przez ulicę?"),
        )
    }

    @Test
    fun classifiesNextCrossingWithNaturalWordOrder() {
        assertEquals(
            RouteAssistantIntent.PedestrianCrossing,
            RouteAssistantCore.intentFor("Gdzie jest następne przejście?"),
        )
    }

    @Test
    fun quickQuestionTokenIsIndependentFromDisplayedLanguage() {
        assertEquals(
            RouteAssistantIntent.RouteQuality,
            RouteAssistantCore.intentFor(RouteAssistantCore.RouteQualityToken),
        )
    }

    @Test
    fun onlyDynamicAnswersRequireFreshLocation() {
        assertTrue(RouteAssistantCore.requiresFreshLocation(RouteAssistantIntent.NextInstruction))
        assertTrue(RouteAssistantCore.requiresFreshLocation(RouteAssistantIntent.Progress))
        assertTrue(RouteAssistantCore.requiresFreshLocation(RouteAssistantIntent.PedestrianCrossing))
        assertTrue(RouteAssistantCore.requiresFreshLocation(RouteAssistantIntent.CurrentLocation))
        assertFalse(RouteAssistantCore.requiresFreshLocation(RouteAssistantIntent.RouteOverview))
        assertFalse(RouteAssistantCore.requiresFreshLocation(RouteAssistantIntent.RouteQuality))
    }

    @Test
    fun classifiesRouteQualityQuestionBeforeGenericGpsStatus() {
        assertEquals(
            RouteAssistantIntent.RouteQuality,
            RouteAssistantCore.intentFor("Czy GPS jest dokładny?"),
        )
    }

    @Test
    fun classifiesNextCrossingBeforeGenericNextInstruction() {
        assertEquals(
            RouteAssistantIntent.PedestrianCrossing,
            RouteAssistantCore.intentFor("Gdzie jest następne przejście?"),
        )
    }

    @Test
    fun classifiesNaturalProgressQuestion() {
        assertEquals(
            RouteAssistantIntent.Progress,
            RouteAssistantCore.intentFor("Kiedy dotrę do celu i ile minut zostało?"),
        )
    }

    @Test
    fun classifiesNaturalNextInstructionQuestion() {
        assertEquals(
            RouteAssistantIntent.NextInstruction,
            RouteAssistantCore.intentFor("Po tym skręcie co będzie dalej?"),
        )
    }

    @Test
    fun classifiesNaturalOverviewQuestionWithInsertedWords() {
        assertEquals(
            RouteAssistantIntent.RouteOverview,
            RouteAssistantCore.intentFor("Jak wygląda cała moja trasa do celu?"),
        )
    }

    @Test
    fun classifiesNaturalStatusQuestionWithInsertedWords() {
        assertEquals(
            RouteAssistantIntent.RouteStatus,
            RouteAssistantCore.intentFor("Czy jestem nadal na właściwej trasie?"),
        )
    }

    @Test
    fun classifiesNaturalRouteExplanationAsOverview() {
        assertEquals(
            RouteAssistantIntent.RouteOverview,
            RouteAssistantCore.intentFor("Wyjaśnij trasę krok po kroku"),
        )
    }

    @Test
    fun rejectsUnknownQuestionInsteadOfGuessing() {
        val match = RouteAssistantCore.matchFor("Opowiedz mi coś niezwiązanego z trasą")

        assertEquals(RouteAssistantIntent.Help, match.intent)
        assertEquals(false, match.isConfident)
        assertEquals(0, match.confidence)
    }

    @Test
    fun doesNotUseEditDistanceForVeryShortSemanticWords() {
        val match = RouteAssistantCore.matchFor("Nie opowiadaj o ile")

        assertEquals(RouteAssistantIntent.Help, match.intent)
        assertFalse(match.isConfident)
    }

    @Test
    fun flagsQuestionContainingTwoStrongIntentsAsAmbiguous() {
        val match = RouteAssistantCore.matchFor("Co dalej i czy GPS jest dokładny?")

        assertEquals(RouteAssistantIntent.Help, match.intent)
        assertEquals(true, match.isAmbiguous)
        assertEquals(false, match.isConfident)
    }

    @Test
    fun gpsQualityUsesExplicitAccuracyBands() {
        assertEquals(
            RouteAssistantGpsQuality.Reliable,
            RouteAssistantCore.gpsQuality(12f),
        )
        assertEquals(
            RouteAssistantGpsQuality.Limited,
            RouteAssistantCore.gpsQuality(40f),
        )
        assertEquals(
            RouteAssistantGpsQuality.Weak,
            RouteAssistantCore.gpsQuality(100f),
        )
        assertEquals(
            RouteAssistantGpsQuality.Unavailable,
            RouteAssistantCore.gpsQuality(null),
        )
    }

    @Test
    fun overviewIndicesAreBoundedAndStartAtCurrentStep() {
        val steps = (0..5).map { index ->
            RouteStep(instruction = "Krok $index", distanceMeters = 20)
        }

        assertEquals(
            listOf(2, 3, 4),
            RouteAssistantCore.overviewStepIndices(
                currentStepIndex = 2,
                steps = steps,
                maximumSteps = 3,
            ),
        )
        assertEquals(
            listOf(5),
            RouteAssistantCore.overviewStepIndices(
                currentStepIndex = 100,
                steps = steps,
                maximumSteps = 2,
            ),
        )
    }

    @Test
    fun overviewPrioritizesUpcomingDecisionPoints() {
        val steps = listOf(
            RouteStep(instruction = "Idź prosto", distanceMeters = 100),
            RouteStep(instruction = "Idź prosto", distanceMeters = 100),
            RouteStep(instruction = "Idź prosto", distanceMeters = 100),
            RouteStep(instruction = "Idź prosto", distanceMeters = 100),
            RouteStep(
                instruction = "Skręć w prawo w Lipową",
                distanceMeters = 80,
                maneuverType = "turn",
                maneuverModifier = "right",
            ),
            RouteStep(instruction = "Idź prosto", distanceMeters = 100),
            RouteStep(
                instruction = "Przejście dla pieszych",
                distanceMeters = 60,
                kind = RouteStepKind.PedestrianCrossing,
            ),
        )

        assertEquals(
            listOf(2, 4, 6),
            RouteAssistantCore.overviewStepIndices(
                currentStepIndex = 2,
                steps = steps,
                maximumSteps = 3,
            ),
        )
    }
}
