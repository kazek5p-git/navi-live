import Foundation

/// Intencje obsługiwane lokalnie przez inteligentnego asystenta trasy.
enum RouteAssistantIntent: Equatable, Hashable {
  case currentInstruction
  case repeatInstruction
  case currentLocation
  case nextInstruction
  case routeOverview
  case progress
  case routeStatus
  case routeQuality
  case pedestrianCrossing
  case help
}

enum RouteAssistantGpsQuality: Equatable {
  case reliable
  case limited
  case weak
  case unavailable
}

/// Wynik lokalnego rozpoznania pytania wraz z zabezpieczeniem przed zgadywaniem.
struct RouteAssistantMatch: Equatable {
  let intent: RouteAssistantIntent
  let confidence: Int
  let isAmbiguous: Bool

  var isConfident: Bool {
    confidence >= 60 && !isAmbiguous
  }
}

enum RouteAssistantCore {
  static let currentInstructionToken = "route_assistant_current"
  static let repeatInstructionToken = "route_assistant_repeat"
  static let currentLocationToken = "route_assistant_location"
  static let nextInstructionToken = "route_assistant_next"
  static let routeOverviewToken = "route_assistant_overview"
  static let progressToken = "route_assistant_progress"
  static let routeStatusToken = "route_assistant_status"
  static let routeQualityToken = "route_assistant_quality"
  static let pedestrianCrossingToken = "route_assistant_crossing"

  private struct PhraseGroup {
    let intent: RouteAssistantIntent
    let phrases: [String]
  }

  private struct SemanticSignal {
    let expression: String
    let weight: Int
  }

  private struct Candidate {
    let intent: RouteAssistantIntent
    let score: Int
  }

  private static let phraseGroups: [PhraseGroup] = [
    PhraseGroup(
      intent: .currentInstruction,
      phrases: [
        currentInstructionToken,
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
        "지금 무엇을 해야"
      ]
    ),
    PhraseGroup(
      intent: .repeatInstruction,
      phrases: [
        repeatInstructionToken,
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
        "tekrar"
      ]
    ),
    PhraseGroup(
      intent: .currentLocation,
      phrases: [
        currentLocationToken,
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
        "where is my location"
      ]
    ),
    PhraseGroup(
      intent: .pedestrianCrossing,
      phrases: [
        pedestrianCrossingToken,
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
        "횡단보도"
      ]
    ),
    PhraseGroup(
      intent: .nextInstruction,
      phrases: [
        nextInstructionToken,
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
        "次は何"
      ]
    ),
    PhraseGroup(
      intent: .routeOverview,
      phrases: [
        routeOverviewToken,
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
        "підсумуй маршрут"
      ]
    ),
    PhraseGroup(
      intent: .progress,
      phrases: [
        progressToken,
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
        "どのくらい残っている"
      ]
    ),
    PhraseGroup(
      intent: .routeQuality,
      phrases: [
        routeQualityToken,
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
        "gps は正確"
      ]
    ),
    PhraseGroup(
      intent: .routeStatus,
      phrases: [
        routeStatusToken,
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
        "正しい道"
      ]
    ),
    PhraseGroup(
      intent: .help,
      phrases: ["pomoc", "help", "pytanie", "pytani", "question", "umiesz", "what can you do"]
    )
  ]

  // Lekki interpreter lokalny rozpoznaje sens pytania, ale nie generuje faktów.
  private static let semanticSignals: [RouteAssistantIntent: [SemanticSignal]] = [
    .currentInstruction: [
      SemanticSignal(expression: "teraz", weight: 18),
      SemanticSignal(expression: "obecnie", weight: 22),
      SemanticSignal(expression: "chwil", weight: 18),
      SemanticSignal(expression: "kierow", weight: 26),
      SemanticSignal(expression: "skrec", weight: 26),
      SemanticSignal(expression: "manewr", weight: 28),
      SemanticSignal(expression: "instrukc", weight: 26),
      SemanticSignal(expression: "ruch", weight: 20),
      SemanticSignal(expression: "now", weight: 18),
      SemanticSignal(expression: "current", weight: 18),
      SemanticSignal(expression: "сейчас", weight: 20),
      SemanticSignal(expression: "зараз", weight: 20),
      SemanticSignal(expression: "şimdi", weight: 20),
      SemanticSignal(expression: "الان", weight: 20),
      SemanticSignal(expression: "今", weight: 20),
      SemanticSignal(expression: "지금", weight: 20)
    ],
    .repeatInstruction: [
      SemanticSignal(expression: "powtorz", weight: 34),
      SemanticSignal(expression: "powtórz", weight: 34),
      SemanticSignal(expression: "ponownie", weight: 28),
      SemanticSignal(expression: "jeszcze raz", weight: 32),
      SemanticSignal(expression: "repeat", weight: 34),
      SemanticSignal(expression: "again", weight: 30),
      SemanticSignal(expression: "wiederholen", weight: 32),
      SemanticSignal(expression: "повтори", weight: 32),
      SemanticSignal(expression: "повторіть", weight: 32),
      SemanticSignal(expression: "tekrar", weight: 32)
    ],
    .currentLocation: [
      SemanticSignal(expression: "gdzie jestem", weight: 34),
      SemanticSignal(expression: "adres", weight: 30),
      SemanticSignal(expression: "lokaliz", weight: 30),
      SemanticSignal(expression: "pozyc", weight: 28),
      SemanticSignal(expression: "miejsce", weight: 24),
      SemanticSignal(expression: "current location", weight: 32),
      SemanticSignal(expression: "where am i", weight: 32),
      SemanticSignal(expression: "my address", weight: 30),
      SemanticSignal(expression: "где", weight: 24),
      SemanticSignal(expression: "位置", weight: 24)
    ],
    .nextInstruction: [
      SemanticSignal(expression: "dalej", weight: 22),
      SemanticSignal(expression: "potem", weight: 25),
      SemanticSignal(expression: "pozniej", weight: 25),
      SemanticSignal(expression: "po tym", weight: 25),
      SemanticSignal(expression: "nastep", weight: 28),
      SemanticSignal(expression: "kolejn", weight: 25),
      SemanticSignal(expression: "after", weight: 20),
      SemanticSignal(expression: "next", weight: 22),
      SemanticSignal(expression: "dopo", weight: 20),
      SemanticSignal(expression: "despues", weight: 20),
      SemanticSignal(expression: "дальше", weight: 22),
      SemanticSignal(expression: "далі", weight: 22),
      SemanticSignal(expression: "次", weight: 20)
    ],
    .routeOverview: [
      SemanticSignal(expression: "podsum", weight: 30),
      SemanticSignal(expression: "plan", weight: 25),
      SemanticSignal(expression: "przebieg", weight: 28),
      SemanticSignal(expression: "krok po kroku", weight: 32),
      SemanticSignal(expression: "cala trasa", weight: 32),
      SemanticSignal(expression: "jak wyglada", weight: 28),
      SemanticSignal(expression: "moja trasa", weight: 26),
      SemanticSignal(expression: "route", weight: 15),
      SemanticSignal(expression: "summary", weight: 24),
      SemanticSignal(expression: "trasa", weight: 15)
    ],
    .progress: [
      SemanticSignal(expression: "ile", weight: 12),
      SemanticSignal(expression: "zosta", weight: 28),
      SemanticSignal(expression: "pozosta", weight: 28),
      SemanticSignal(expression: "dystans", weight: 28),
      SemanticSignal(expression: "odleg", weight: 28),
      SemanticSignal(expression: "daleko", weight: 24),
      SemanticSignal(expression: "czas", weight: 22),
      SemanticSignal(expression: "minut", weight: 24),
      SemanticSignal(expression: "metr", weight: 20),
      SemanticSignal(expression: "dotr", weight: 28),
      SemanticSignal(expression: "remaining", weight: 24),
      SemanticSignal(expression: "distance", weight: 24),
      SemanticSignal(expression: "how far", weight: 28),
      SemanticSignal(expression: "сколько", weight: 24),
      SemanticSignal(expression: "остал", weight: 24),
      SemanticSignal(expression: "скільки", weight: 24),
      SemanticSignal(expression: "залиш", weight: 24),
      SemanticSignal(expression: "cuanto", weight: 24),
      SemanticSignal(expression: "manca", weight: 24)
    ],
    .routeQuality: [
      SemanticSignal(expression: "wiarygod", weight: 32),
      SemanticSignal(expression: "doklad", weight: 30),
      SemanticSignal(expression: "ufa", weight: 28),
      SemanticSignal(expression: "bezpiecz", weight: 25),
      SemanticSignal(expression: "stabil", weight: 25),
      SemanticSignal(expression: "precyz", weight: 25),
      SemanticSignal(expression: "reliab", weight: 28),
      SemanticSignal(expression: "accurat", weight: 28),
      SemanticSignal(expression: "precis", weight: 25),
      SemanticSignal(expression: "точн", weight: 25),
      SemanticSignal(expression: "güven", weight: 25)
    ],
    .routeStatus: [
      SemanticSignal(expression: "gps", weight: 22),
      SemanticSignal(expression: "pozyc", weight: 25),
      SemanticSignal(expression: "tras", weight: 24),
      SemanticSignal(expression: "drog", weight: 22),
      SemanticSignal(expression: "status", weight: 30),
      SemanticSignal(expression: "sygnal", weight: 20),
      SemanticSignal(expression: "jestem", weight: 16),
      SemanticSignal(expression: "on route", weight: 24),
      SemanticSignal(expression: "right way", weight: 24),
      SemanticSignal(expression: "маршрут", weight: 22),
      SemanticSignal(expression: "正しい道", weight: 22)
    ],
    .pedestrianCrossing: [
      SemanticSignal(expression: "przejsc", weight: 32),
      SemanticSignal(expression: "przejd", weight: 30),
      SemanticSignal(expression: "zebr", weight: 30),
      SemanticSignal(expression: "druga strona", weight: 28),
      SemanticSignal(expression: "cross", weight: 28),
      SemanticSignal(expression: "pedestrian", weight: 28),
      SemanticSignal(expression: "переход", weight: 28),
      SemanticSignal(expression: "пішохід", weight: 28),
      SemanticSignal(expression: "yaya", weight: 28),
      SemanticSignal(expression: "横断", weight: 28),
      SemanticSignal(expression: "횡단", weight: 28)
    ]
  ]

  /// Rozpoznaje pytanie bez sieci, z oceną pewności i wykrywaniem konfliktu intencji.
  static func match(for query: String) -> RouteAssistantMatch {
    let normalized = normalize(query)
    guard !normalized.isEmpty else {
      return RouteAssistantMatch(intent: .help, confidence: 0, isAmbiguous: false)
    }

    let candidates = phraseGroups.compactMap { group -> Candidate? in
      let phraseScores = group.phrases.map({ Self.phraseScore(normalized, phrase: $0) })
      let bestPhraseScore = phraseScores.max() ?? 0
      let score = max(bestPhraseScore, semanticScore(normalized, intent: group.intent))
      guard score > 0 else {
        return nil
      }
      return Candidate(intent: group.intent, score: score)
    }.sorted { $0.score > $1.score }

    guard let best = candidates.first else {
      return RouteAssistantMatch(intent: .help, confidence: 0, isAmbiguous: false)
    }
    let second = candidates.dropFirst().first
    let ambiguousByCloseScores = second.map { best.score >= 70 && $0.score >= best.score - 8 } ?? false
    let ambiguousCompound = second.map {
      best.score >= 60 && $0.score >= 60 && isCompoundQuery(normalized)
    } ?? false
    let isAmbiguous = ambiguousByCloseScores || ambiguousCompound
    return RouteAssistantMatch(
      intent: isAmbiguous ? .help : best.intent,
      confidence: best.score,
      isAmbiguous: isAmbiguous
    )
  }

  static func intent(for query: String) -> RouteAssistantIntent {
    match(for: query).intent
  }

  /// Odpowiedzi dynamiczne nie mogą korzystać z pozycji starszej niż próg asystenta.
  static func requiresFreshLocation(for intent: RouteAssistantIntent) -> Bool {
    switch intent {
    case .currentLocation, .nextInstruction, .progress, .pedestrianCrossing:
      return true
    default:
      return false
    }
  }

  static func nextStepIndex(currentStepIndex: Int, steps: [RouteStep]) -> Int? {
    let start = max(currentStepIndex + 1, 0)
    return steps.indices.first { $0 >= start }
  }

  static func overviewStepIndices(
    currentStepIndex: Int,
    steps: [RouteStep],
    maximumSteps: Int = 4
  ) -> [Int] {
    guard !steps.isEmpty, maximumSteps > 0 else { return [] }
    let start = min(max(currentStepIndex, 0), steps.count - 1)
    let remainingIndices = Array(start..<steps.count)
    let prioritized = [start] + remainingIndices.filter {
      $0 != start && isDecisionPoint(steps[$0])
    }
    return (prioritized + remainingIndices.filter { !prioritized.contains($0) })
      .prefix(maximumSteps)
      .map { $0 }
  }

  static func nextPedestrianCrossingIndex(currentStepIndex: Int, steps: [RouteStep]) -> Int? {
    let start = max(currentStepIndex, 0)
    return steps.indices.first { index in
      index >= start && steps[index].kind == .pedestrianCrossing
    }
  }

  static func gpsQuality(accuracyMeters: Double?) -> RouteAssistantGpsQuality {
    guard let accuracyMeters, accuracyMeters.isFinite, accuracyMeters >= 0 else {
      return .unavailable
    }
    if accuracyMeters <= SharedProductRules.Navigation.gpsReliableAccuracyMeters {
      return .reliable
    }
    if accuracyMeters <= SharedProductRules.Navigation.gpsWeakAccuracyMeters {
      return .limited
    }
    return .weak
  }

  /// Podsumowanie zaczyna od decyzji, a nie od przypadkowych odcinków prostych.
  private static func isDecisionPoint(_ step: RouteStep) -> Bool {
    if step.kind == .pedestrianCrossing { return true }
    if RouteStepSimplificationCore.isTurnLikeManeuver(step) { return true }
    return step.maneuverType?.lowercased() == "arrive"
  }

  private static func semanticScore(_ query: String, intent: RouteAssistantIntent) -> Int {
    let tokens = query.split(separator: " ").map(String.init)
    let matchedSignals = semanticSignals[intent, default: []].filter { signal in
      let expression = normalize(signal.expression)
      if expression.contains(" ") {
        return query.contains(expression)
      }
      return tokens.contains { tokenMatches($0, expression: expression) }
    }
    guard !matchedSignals.isEmpty else { return 0 }
    // Pojedynczy ogólny sygnał nie wystarcza do odpowiedzi bez wyraźnej frazy.
    guard matchedSignals.count >= 2 else { return 0 }
    let multipleSignalBonus = matchedSignals.count > 1 ? 8 : 0
    return min(45 + matchedSignals.reduce(0) { $0 + $1.weight } + multipleSignalBonus, 88)
  }

  private static func isCompoundQuery(_ query: String) -> Bool {
    [" i ", " oraz ", " and ", " et ", " y ", " e ", " и ", " та ", " و "]
      .contains { query.contains($0) }
  }

  private static func tokenMatches(_ token: String, expression: String) -> Bool {
    if token == expression || token.hasPrefix(expression) { return true }
    let maximumDistance: Int
    if expression.count >= 9 {
      maximumDistance = 2
    } else if expression.count >= 4 {
      maximumDistance = 1
    } else {
      maximumDistance = 0
    }
    guard abs(token.count - expression.count) <= maximumDistance else { return false }
    return editDistance(token, expression) <= maximumDistance
  }

  private static func editDistance(_ left: String, _ right: String) -> Int {
    guard left != right else { return 0 }
    guard !left.isEmpty else { return right.count }
    guard !right.isEmpty else { return left.count }

    let leftCharacters = Array(left)
    let rightCharacters = Array(right)
    var previous = Array(0...rightCharacters.count)
    for (leftIndex, leftCharacter) in leftCharacters.enumerated() {
      var current = Array(repeating: 0, count: rightCharacters.count + 1)
      current[0] = leftIndex + 1
      for (rightIndex, rightCharacter) in rightCharacters.enumerated() {
        let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
        current[rightIndex + 1] = min(
          current[rightIndex] + 1,
          previous[rightIndex + 1] + 1,
          previous[rightIndex] + substitutionCost
        )
      }
      previous = current
    }
    return previous[rightCharacters.count]
  }

  private static func phraseScore(_ query: String, phrase: String) -> Int {
    let normalizedPhrase = normalize(phrase)
    guard !normalizedPhrase.isEmpty, query.contains(normalizedPhrase) else { return 0 }
    if query == normalizedPhrase { return 100 }
    if normalizedPhrase == "powtorz" { return 82 }
    if normalizedPhrase == "do celu" { return 52 }
    if normalizedPhrase.contains(" ") {
      return min(84 + normalizedPhrase.count / 8, 96)
    }
    return normalizedPhrase.count >= 7 ? 72 : 55
  }

  private static func normalize(_ value: String) -> String {
    value
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
