package com.navilive.android.data.routing

import com.navilive.android.model.RouteStep
import com.navilive.android.model.RouteStepKind
import com.navilive.android.model.SharedProductRules
import java.text.Normalizer
import java.util.Locale
import kotlin.math.abs

/** Intencje obsługiwane lokalnie przez inteligentnego asystenta trasy. */
internal enum class RouteAssistantIntent {
    CurrentInstruction,
    RepeatInstruction,
    CurrentLocation,
    NextInstruction,
    RouteOverview,
    Progress,
    RouteStatus,
    RouteQuality,
    PedestrianCrossing,
    Help,
}

internal enum class RouteAssistantGpsQuality {
    Reliable,
    Limited,
    Weak,
    Unavailable,
}

/** Wynik lokalnego rozpoznania pytania wraz z zabezpieczeniem przed zgadywaniem. */
internal data class RouteAssistantMatch(
    val intent: RouteAssistantIntent,
    val confidence: Int,
    val isAmbiguous: Boolean,
) {
    val isConfident: Boolean
        get() = confidence >= 60 && !isAmbiguous
}

internal object RouteAssistantCore {

    const val CurrentInstructionToken = "route_assistant_current"
    const val RepeatInstructionToken = "route_assistant_repeat"
    const val CurrentLocationToken = "route_assistant_location"
    const val NextInstructionToken = "route_assistant_next"
    const val RouteOverviewToken = "route_assistant_overview"
    const val ProgressToken = "route_assistant_progress"
    const val RouteStatusToken = "route_assistant_status"
    const val RouteQualityToken = "route_assistant_quality"
    const val PedestrianCrossingToken = "route_assistant_crossing"

    private data class PhraseGroup(
        val intent: RouteAssistantIntent,
        val phrases: List<String>,
    )

    private data class SemanticSignal(
        val expression: String,
        val weight: Int,
    )

    private val phraseGroups = listOf(
        PhraseGroup(
            RouteAssistantIntent.CurrentInstruction,
            listOf(
                CurrentInstructionToken,
                "co mam teraz",
                "co jest teraz",
                "co teraz",
                "co robić teraz",
                "co robic teraz",
                "co mam zrobić",
                "co mam zrobic",
                "gdzie mam teraz iść",
                "gdzie mam teraz isc",
                "w którą stronę",
                "w ktora strone",
                "którędy teraz",
                "ktoredy teraz",
                "jak mam iść",
                "jak mam isc",
                "jaki jest najbliższy manewr",
                "jaki jest najblizszy manewr",
                "jaki mam teraz manewr",
                "czy mam teraz skręcić",
                "czy mam teraz skrecic",
                "co mam zrobić w tej chwili",
                "co mam zrobic w tej chwili",
                "jaki mam następny ruch",
                "jaki mam nastepny ruch",
                "what now",
                "what should i do now",
                "where do i go now",
                "current instruction",
                "what do i do",
                "where should i go",
                "current direction",
                "was soll ich jetzt tun",
                "que dois je faire maintenant",
                "que hago ahora",
                "cosa devo fare ora",
                "что делать сейчас",
                "що робити зараз",
                "şimdi ne yapmalıyım",
                "ماذا أفعل الآن",
                "الان چه کار کنم",
                "今何をすればいい",
                "지금 무엇을 해야",
            ),
        ),
        PhraseGroup(
            RouteAssistantIntent.RepeatInstruction,
            listOf(
                RepeatInstructionToken,
                "powtórz",
                "powtorz",
                "powtórz instrukcję",
                "powtorz instrukcje",
                "powtórz wskazówkę",
                "powtorz wskazowke",
                "powiedz jeszcze raz",
                "jeszcze raz",
                "repeat",
                "repeat instruction",
                "repeat guidance",
                "say that again",
                "wiederholen",
                "повтори",
                "повторіть",
                "tekrar",
            ),
        ),
        PhraseGroup(
            RouteAssistantIntent.CurrentLocation,
            listOf(
                CurrentLocationToken,
                "gdzie jestem",
                "gdzie ja jestem",
                "jaki jest mój adres",
                "jaki jest moj adres",
                "jaki mam adres",
                "odczytaj moją lokalizację",
                "odczytaj moja lokalizacje",
                "pokaż moją lokalizację",
                "pokaz moja lokalizacje",
                "current location",
                "where am i",
                "my address",
                "read my location",
                "где я нахожусь",
                "моя текущая позиция",
                "де я знаходжуся",
                "موقعیت فعلی",
                "where is my location",
            ),
        ),
        PhraseGroup(
            RouteAssistantIntent.PedestrianCrossing,
            listOf(
                PedestrianCrossingToken,
                "przejście",
                "przejscie",
                "przejść przez ulicę",
                "przejsc przez ulice",
                "przez ulicę",
                "przez ulice",
                "zebra",
                "czy będzie przejście",
                "czy bedzie przejscie",
                "kiedy będzie przejście",
                "kiedy bedzie przejscie",
                "gdzie jest następne przejście",
                "gdzie jest nastepne przejscie",
                "gdzie mam przejść przez ulicę",
                "gdzie mam przejsc przez ulice",
                "crossing",
                "where is the next crossing",
                "passage piéton",
                "paso de peatones",
                "passaggio pedonale",
                "пешеходный переход",
                "пішохідний перехід",
                "yaya geçidi",
                "عبور المشاة",
                "عابر پیاده",
                "横断歩道",
                "횡단보도",
            ),
        ),
        PhraseGroup(
            RouteAssistantIntent.NextInstruction,
            listOf(
                NextInstructionToken,
                "co dalej",
                "co będzie dalej",
                "co bedzie dalej",
                "jak dalej iść",
                "jak dalej isc",
                "co potem",
                "co mam zrobić później",
                "co mam zrobic pozniej",
                "następny",
                "nastepny",
                "kolejny krok",
                "dalej",
                "następny krok",
                "nastapny krok",
                "next",
                "what comes next",
                "what is next",
                "after",
                "next step",
                "what do i do afterwards",
                "was kommt als nächstes",
                "que viene despues",
                "cosa succede dopo",
                "что дальше",
                "що далі",
                "次は何",
            ),
        ),
        PhraseGroup(
            RouteAssistantIntent.RouteOverview,
            listOf(
                RouteOverviewToken,
                "podsumuj trasę",
                "podsumuj trase",
                "plan trasy",
                "jaki jest plan",
                "przebieg trasy",
                "trasa krok po kroku",
                "wyjaśnij trasę",
                "wyjasnij trase",
                "pokaż trasę",
                "pokaz trase",
                "jak wygląda trasa",
                "jak mam iść do celu",
                "jak mam isc do celu",
                "route summary",
                "route overview",
                "summarize the route",
                "trip summary",
                "explain the route",
                "show me the route",
                "routenübersicht",
                "résumé de l itinéraire",
                "resume la ruta",
                "riassumi il percorso",
                "resumo da rota",
                "rezumatul traseului",
                "shrň trasu",
                "zhrň trasu",
                "сводка маршрута",
                "підсумуй маршрут",
            ),
        ),
        PhraseGroup(
            RouteAssistantIntent.Progress,
            listOf(
                ProgressToken,
                "ile zostało",
                "ile zostalo",
                "ile jeszcze",
                "jak daleko",
                "dystans",
                "pozostał",
                "pozostal",
                "do celu",
                "ile drogi",
                "ile czasu",
                "kiedy będę",
                "kiedy bede",
                "kiedy dotrę",
                "kiedy dotre",
                "ile minut",
                "ile metrów zostało",
                "ile metrow zostalo",
                "ile zostało do końca",
                "ile zostalo do konca",
                "jak długo jeszcze",
                "jak dlugo jeszcze",
                "remaining",
                "how far",
                "how much is left",
                "how long",
                "when will i arrive",
                "distance",
                "combien de temps",
                "cuánto falta",
                "quanto manca",
                "сколько осталось",
                "скільки залишилося",
                "ne kadar kaldı",
                "كم تبقى",
                "どのくらい残っている",
            ),
        ),
        PhraseGroup(
            RouteAssistantIntent.RouteQuality,
            listOf(
                RouteQualityToken,
                "czy trasa jest wiarygodna",
                "czy prowadzenie jest wiarygodne",
                "czy gps jest dokładny",
                "czy gps jest dokladny",
                "czy mogę ufać gps",
                "czy moge ufac gps",
                "czy mogę bezpiecznie iść",
                "czy moge bezpiecznie isc",
                "czy mogę ufać prowadzeniu",
                "czy moge ufac prowadzeniu",
                "czy lokalizacja jest dokładna",
                "czy lokalizacja jest dokladna",
                "co może być nie tak",
                "co moze byc nie tak",
                "czy widzisz problemy",
                "route confidence",
                "is the route reliable",
                "is gps accurate",
                "can i trust the route",
                "is navigation reliable",
                "est ce que le gps est précis",
                "es fiable el gps",
                "il gps è preciso",
                "насколько точен gps",
                "gps точний",
                "gps güvenilir mi",
                "هل gps دقيق",
                "gps دقیق است",
                "gps は正確",
            ),
        ),
        PhraseGroup(
            RouteAssistantIntent.RouteStatus,
            listOf(
                RouteStatusToken,
                "gps",
                "na trasie",
                "na tras",
                "pozycja",
                "pozycj",
                "czy idę dobrze",
                "czy ide dobrze",
                "czy jestem dobrze",
                "czy wszystko jest dobrze",
                "co z gps",
                "czy gps działa",
                "czy gps dziala",
                "dokładność",
                "dokladnosc",
                "czy jestem na dobrej drodze",
                "czy idę właściwą drogą",
                "czy ide wlasciwa droga",
                "czy jestem na właściwej trasie",
                "czy jestem na wlasciwej trasie",
                "status",
                "am i on route",
                "route status",
                "am i going the right way",
                "bin ich auf der route",
                "suis je sur la route",
                "estoy en la ruta",
                "sono sul percorso",
                "я на маршруте",
                "я на маршруті",
                "doğru yolda mıyım",
                "هل أنا على المسار",
                "آیا در مسیر هستم",
                "正しい道",
            ),
        ),
        PhraseGroup(
            RouteAssistantIntent.Help,
            listOf("pomoc", "help", "pytanie", "pytani", "question", "umiesz", "what can you do"),
        ),
    )

    // Lekki interpreter lokalny rozpoznaje sens pytania, ale nie generuje faktów.
    private val semanticSignals = mapOf(
        RouteAssistantIntent.CurrentInstruction to listOf(
            SemanticSignal("teraz", 18),
            SemanticSignal("obecnie", 22),
            SemanticSignal("chwil", 18),
            SemanticSignal("kierow", 26),
            SemanticSignal("skrec", 26),
            SemanticSignal("manewr", 28),
            SemanticSignal("instrukc", 26),
            SemanticSignal("ruch", 20),
            SemanticSignal("now", 18),
            SemanticSignal("current", 18),
            SemanticSignal("сейчас", 20),
            SemanticSignal("зараз", 20),
            SemanticSignal("şimdi", 20),
            SemanticSignal("الان", 20),
            SemanticSignal("今", 20),
            SemanticSignal("지금", 20),
        ),
        RouteAssistantIntent.RepeatInstruction to listOf(
            SemanticSignal("powtorz", 34),
            SemanticSignal("powtórz", 34),
            SemanticSignal("ponownie", 28),
            SemanticSignal("jeszcze raz", 32),
            SemanticSignal("repeat", 34),
            SemanticSignal("again", 30),
            SemanticSignal("wiederholen", 32),
            SemanticSignal("повтори", 32),
            SemanticSignal("повторіть", 32),
            SemanticSignal("tekrar", 32),
        ),
        RouteAssistantIntent.CurrentLocation to listOf(
            SemanticSignal("gdzie jestem", 34),
            SemanticSignal("adres", 30),
            SemanticSignal("lokaliz", 30),
            SemanticSignal("pozyc", 28),
            SemanticSignal("miejsce", 24),
            SemanticSignal("current location", 32),
            SemanticSignal("where am i", 32),
            SemanticSignal("my address", 30),
            SemanticSignal("где", 24),
            SemanticSignal("位置", 24),
        ),
        RouteAssistantIntent.NextInstruction to listOf(
            SemanticSignal("dalej", 22),
            SemanticSignal("potem", 25),
            SemanticSignal("pozniej", 25),
            SemanticSignal("po tym", 25),
            SemanticSignal("nastep", 28),
            SemanticSignal("kolejn", 25),
            SemanticSignal("after", 20),
            SemanticSignal("next", 22),
            SemanticSignal("dopo", 20),
            SemanticSignal("despues", 20),
            SemanticSignal("дальше", 22),
            SemanticSignal("далі", 22),
            SemanticSignal("次", 20),
        ),
        RouteAssistantIntent.RouteOverview to listOf(
            SemanticSignal("podsum", 30),
            SemanticSignal("plan", 25),
            SemanticSignal("przebieg", 28),
            SemanticSignal("krok po kroku", 32),
            SemanticSignal("cala trasa", 32),
            SemanticSignal("jak wyglada", 28),
            SemanticSignal("moja trasa", 26),
            SemanticSignal("route", 15),
            SemanticSignal("summary", 24),
            SemanticSignal("trasa", 15),
        ),
        RouteAssistantIntent.Progress to listOf(
            SemanticSignal("ile", 12),
            SemanticSignal("zosta", 28),
            SemanticSignal("pozosta", 28),
            SemanticSignal("dystans", 28),
            SemanticSignal("odleg", 28),
            SemanticSignal("daleko", 24),
            SemanticSignal("czas", 22),
            SemanticSignal("minut", 24),
            SemanticSignal("metr", 20),
            SemanticSignal("dotr", 28),
            SemanticSignal("remaining", 24),
            SemanticSignal("distance", 24),
            SemanticSignal("how far", 28),
            SemanticSignal("сколько", 24),
            SemanticSignal("остал", 24),
            SemanticSignal("скільки", 24),
            SemanticSignal("залиш", 24),
            SemanticSignal("cuanto", 24),
            SemanticSignal("manca", 24),
        ),
        RouteAssistantIntent.RouteQuality to listOf(
            SemanticSignal("wiarygod", 32),
            SemanticSignal("doklad", 30),
            SemanticSignal("ufa", 28),
            SemanticSignal("bezpiecz", 25),
            SemanticSignal("stabil", 25),
            SemanticSignal("precyz", 25),
            SemanticSignal("reliab", 28),
            SemanticSignal("accurat", 28),
            SemanticSignal("precis", 25),
            SemanticSignal("точн", 25),
            SemanticSignal("güven", 25),
        ),
        RouteAssistantIntent.RouteStatus to listOf(
            SemanticSignal("gps", 22),
            SemanticSignal("pozyc", 25),
            SemanticSignal("tras", 24),
            SemanticSignal("drog", 22),
            SemanticSignal("status", 30),
            SemanticSignal("sygnal", 20),
            SemanticSignal("jestem", 16),
            SemanticSignal("on route", 24),
            SemanticSignal("right way", 24),
            SemanticSignal("маршрут", 22),
            SemanticSignal("正しい道", 22),
        ),
        RouteAssistantIntent.PedestrianCrossing to listOf(
            SemanticSignal("przejsc", 32),
            SemanticSignal("przejd", 30),
            SemanticSignal("zebr", 30),
            SemanticSignal("druga strona", 28),
            SemanticSignal("cross", 28),
            SemanticSignal("pedestrian", 28),
            SemanticSignal("переход", 28),
            SemanticSignal("пішохід", 28),
            SemanticSignal("yaya", 28),
            SemanticSignal("横断", 28),
            SemanticSignal("횡단", 28),
        ),
    )

    /** Rozpoznaje pytanie bez sieci, z oceną pewności i wykrywaniem konfliktu intencji. */
    fun matchFor(query: String): RouteAssistantMatch {
        val normalized = normalize(query)
        if (normalized.isBlank()) {
            return RouteAssistantMatch(RouteAssistantIntent.Help, confidence = 0, isAmbiguous = false)
        }

        val candidates = phraseGroups.mapNotNull { group ->
            val phraseScore = group.phrases.maxOfOrNull { phraseScore(normalized, it) } ?: 0
            val score = maxOf(phraseScore, semanticScore(normalized, group.intent))
            if (score == 0) null else group.intent to score
        }.sortedByDescending { it.second }
        val best = candidates.firstOrNull()
            ?: return RouteAssistantMatch(RouteAssistantIntent.Help, confidence = 0, isAmbiguous = false)
        val second = candidates.getOrNull(1)
        val ambiguousByCloseScores = second != null && best.second >= 70 && second.second >= best.second - 8
        val ambiguousCompound = second != null &&
            best.second >= 60 &&
            second.second >= 60 &&
            isCompoundQuery(normalized)
        return RouteAssistantMatch(
            intent = if (ambiguousByCloseScores || ambiguousCompound) {
                RouteAssistantIntent.Help
            } else {
                best.first
            },
            confidence = best.second,
            isAmbiguous = ambiguousByCloseScores || ambiguousCompound,
        )
    }

    fun intentFor(query: String): RouteAssistantIntent = matchFor(query).intent

    /** Odpowiedzi dynamiczne nie mogą korzystać z pozycji starszej niż próg asystenta. */
    fun requiresFreshLocation(intent: RouteAssistantIntent): Boolean {
        return when (intent) {
            RouteAssistantIntent.CurrentLocation,
            RouteAssistantIntent.NextInstruction,
            RouteAssistantIntent.Progress,
            RouteAssistantIntent.PedestrianCrossing,
            -> true
            else -> false
        }
    }

    fun nextStepIndex(currentStepIndex: Int, steps: List<RouteStep>): Int? {
        val start = (currentStepIndex + 1).coerceAtLeast(0)
        return steps.indices.firstOrNull { it >= start }
    }

    fun overviewStepIndices(
        currentStepIndex: Int,
        steps: List<RouteStep>,
        maximumSteps: Int = 4,
    ): List<Int> {
        if (steps.isEmpty() || maximumSteps <= 0) return emptyList()
        val start = currentStepIndex.coerceIn(0, steps.lastIndex)
        val remainingIndices = (start..steps.lastIndex).toList()
        val prioritized = buildList {
            add(start)
            addAll(
                remainingIndices
                    .asSequence()
                    .filter { it != start && isDecisionPoint(steps[it]) }
                    .toList(),
            )
        }
        return (prioritized + remainingIndices.filterNot { it in prioritized })
            .distinct()
            .take(maximumSteps)
    }

    fun nextPedestrianCrossingIndex(currentStepIndex: Int, steps: List<RouteStep>): Int? {
        val start = currentStepIndex.coerceAtLeast(0)
        return steps.indices.firstOrNull { index ->
            index >= start && steps[index].kind == RouteStepKind.PedestrianCrossing
        }
    }

    fun gpsQuality(accuracyMeters: Float?): RouteAssistantGpsQuality {
        val accuracy = accuracyMeters?.takeIf { it.isFinite() && it >= 0f }
            ?: return RouteAssistantGpsQuality.Unavailable
        return when {
            accuracy <= SharedProductRules.Navigation.gpsReliableAccuracyMeters ->
                RouteAssistantGpsQuality.Reliable
            accuracy <= SharedProductRules.Navigation.gpsWeakAccuracyMeters ->
                RouteAssistantGpsQuality.Limited
            else -> RouteAssistantGpsQuality.Weak
        }
    }

    /** Podsumowanie zaczyna od decyzji, a nie od przypadkowych odcinków prostych. */
    private fun isDecisionPoint(step: RouteStep): Boolean {
        if (step.kind == RouteStepKind.PedestrianCrossing) return true
        if (RouteStepSimplificationCore.isTurnLikeManeuver(step)) return true
        return step.maneuverType.equals("arrive", ignoreCase = true)
    }

    private fun semanticScore(query: String, intent: RouteAssistantIntent): Int {
        val tokens = query.split(' ').filter { it.isNotBlank() }
        val matchedSignals = semanticSignals[intent].orEmpty().filter { signal ->
            val expression = normalize(signal.expression)
            if (expression.contains(' ')) {
                expression in query
            } else {
                tokens.any { token -> tokenMatches(token, expression) }
            }
        }
        // Pojedynczy ogólny sygnał nie wystarcza do odpowiedzi bez wyraźnej frazy.
        if (matchedSignals.size < 2) return 0
        val multipleSignalBonus = if (matchedSignals.size > 1) 8 else 0
        return (45 + matchedSignals.sumOf { it.weight } + multipleSignalBonus).coerceAtMost(88)
    }

    private fun isCompoundQuery(query: String): Boolean {
        return listOf(" i ", " oraz ", " and ", " et ", " y ", " e ", " и ", " та ", " و ")
            .any(query::contains)
    }

    private fun tokenMatches(token: String, expression: String): Boolean {
        if (token == expression || token.startsWith(expression)) return true
        val maximumDistance = when {
            expression.length >= 9 -> 2
            expression.length >= 4 -> 1
            else -> 0
        }
        if (abs(token.length - expression.length) > maximumDistance) return false
        return editDistance(token, expression) <= maximumDistance
    }

    private fun editDistance(left: String, right: String): Int {
        if (left == right) return 0
        if (left.isEmpty()) return right.length
        if (right.isEmpty()) return left.length

        var previous = IntArray(right.length + 1) { it }
        for (leftIndex in left.indices) {
            val current = IntArray(right.length + 1)
            current[0] = leftIndex + 1
            for (rightIndex in right.indices) {
                val substitutionCost = if (left[leftIndex] == right[rightIndex]) 0 else 1
                current[rightIndex + 1] = minOf(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + substitutionCost,
                )
            }
            previous = current
        }
        return previous[right.length]
    }

    private fun phraseScore(query: String, phrase: String): Int {
        val normalizedPhrase = normalize(phrase)
        if (normalizedPhrase.isBlank() || normalizedPhrase !in query) return 0
        return when {
            query == normalizedPhrase -> 100
            normalizedPhrase == "powtorz" -> 82
            normalizedPhrase == "do celu" -> 52
            normalizedPhrase.contains(' ') -> (84 + normalizedPhrase.length / 8).coerceAtMost(96)
            normalizedPhrase.length >= 7 -> 72
            else -> 55
        }
    }

    private fun normalize(value: String): String {
        return Normalizer.normalize(value, Normalizer.Form.NFD)
            .replace("\\p{M}+".toRegex(), "")
            .lowercase(Locale.ROOT)
            .replace("[^\\p{L}\\p{N}]+".toRegex(), " ")
            .replace("\\s+".toRegex(), " ")
            .trim()
    }
}
