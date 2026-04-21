# navilive

Specyfikacja produktu i plan odbudowy inspirowany `Nav by ViaOpta`

Data: 2026-04-06

## 1. Cel dokumentu

Ten dokument opisuje, jak odtworzyć funkcjonalnie dawną aplikację `Nav by ViaOpta` pod nową nazwą `navilive`.

Kluczowe założenie:

- nie znaleziono publicznego repozytorium ze źródłami ViaOpta,
- zachował się działający artefakt Android APK oraz archiwalne opisy produktu,
- `navilive` powinno być traktowane jako clean-room rebuild, a nie rebranding starej aplikacji.

## 2. Podstawa źródłowa

### Potwierdzone źródła

- Archiwalna strona produktu ViaOpta Nav w Wayback Machine
- Archiwalne wpisy App Store z Wayback Machine z wersjami `2.0.9` i `2.2.1`
- Archiwalna nowsza strona produktu `ViaOpta-Nav.html` z lat `2019-2020`
- Wpis prasowy Novartis o premierze aplikacji
- Zachowany APK Android `com.novartis.blind`, wersja `2.2.4`
- Zachowane metadane iOS `id908435532` / `com.novartis.pharma.global.viaoptanav`
- Analiza klas, stringów, manifestu i lokalnych baz SQLite z APK

### Co uznajemy za pewne

- aplikacja była kierowana do osób niewidomych i słabowidzących,
- miała onboarding, wybór języka i akceptację regulaminu,
- obsługiwała wyszukiwanie miejsc, ulubione, waypointy, trasę pieszą i transport publiczny,
- miała aktywną nawigację z TTS, wibracjami, wykrywaniem kierunku urządzenia i automatycznym przeliczaniem trasy,
- wykorzystywała OSM do informacji o skrzyżowaniach oraz legacy API HERE do wyszukiwania i routingu,
- integrowała wyjścia do Be My Eyes i usług ridesharingowych,
- w wersjach iOS z archiwum miała bardzo prosty, wysokokontrastowy układ z dużymi przyciskami i minimalną liczbą akcji na ekranie,
- miała lokalną bazę ulubionych i lokalną bazę tekstów oraz usług taxi.

### Co jest wnioskiem z analizy

- publiczny kod nie został znaleziony,
- stara aplikacja nie nadaje się do prostego przywrócenia 1:1, bo opierała się na wygaszonych endpointach HERE,
- najbardziej praktyczna ścieżka to Android-first rebuild, a potem iOS parity.

## 3. Wizja produktu

`navilive` ma być aplikacją nawigacyjną dla osób niewidomych i słabowidzących, która:

- prowadzi głosowo od punktu A do B,
- komunikuje kierunek startu i kolejne manewry,
- ostrzega o skrzyżowaniach i zejściu z trasy,
- umożliwia szybkie znalezienie miejsca, zapisanie go i ponowne uruchomienie trasy,
- pozostaje maksymalnie prosta, przewidywalna i czytelna pod TalkBack i VoiceOver.

Priorytetem nie jest "ładna mapa", tylko:

- pewna lokalizacja,
- czytelne komunikaty głosowe,
- stabilne przeliczanie trasy,
- bardzo dobra dostępność,
- niski koszt poznawczy.

## 4. Użytkownicy

### Główna grupa

- osoby niewidome korzystające z czytników ekranu i słuchawek

### Druga grupa

- osoby słabowidzące, które potrzebują dużych kontrastów, prostego UI i wsparcia głosowego

### Trzecia grupa

- opiekunowie lub asystenci konfigurujący aplikację, język, ulubione miejsca i ustawienia alertów

## 5. Odzyskany zakres funkcjonalny ViaOpta

Poniższa lista jest oparta na APK i archiwach.

### 5.1 Onboarding

- wybór języka
- akceptacja terms and conditions
- tutorial 3-ekranowy
- komunikat o dostępnej nowej wersji

### 5.2 Struktura ekranów

Zidentyfikowane moduły:

- `Splash`
- `Control`
- `Map`
- `Search`
- `SearchActivity`
- `PlaceDetail`
- `RouteSummary`
- `RouteNavigator`
- `AddWaypoint`
- `SaveLocation`
- `Favorites`
- `Settings`
- `SettingsList`
- `TaxiServices`
- `LanguageSelect`

### 5.3 Wyszukiwanie i miejsca

- wyszukiwanie adresu lub miejsca
- sekcja `Around me`
- wejście `From` / `To`
- otwarcie szczegółów miejsca
- pokazanie miejsca na mapie
- kontakt z miejscem:
  - telefon
  - e-mail
  - strona WWW
- zapis do ulubionych
- udostępnianie lokalizacji

### 5.4 Ulubione i waypointy

- lokalne ulubione
- dodawanie waypointów pośrednich
- wybór waypointu z ulubionych
- usuwanie waypointów

### 5.5 Routing

- trasa piesza
- trasa transportem publicznym
- przełączanie typu transportu w podsumowaniu
- prezentacja czasu i dystansu
- pokazanie trasy na mapie
- uruchomienie aktywnej nawigacji

### 5.6 Aktywna nawigacja

- TTS turn-by-turn
- aktualny i następny manewr
- komunikat o dotarciu do celu
- pauza / wznowienie
- automatyczna pauza po utracie kontekstu
- ostrzeganie o zejściu z trasy
- automatyczne przeliczanie trasy
- wykrywanie kierunku telefonu kompasem
- wibracja, gdy użytkownik jest ustawiony we właściwym kierunku startu
- odczyt pozycji po potrząśnięciu telefonem

### 5.7 Skrzyżowania i otoczenie

- pobieranie danych OSM dla obszaru wokół użytkownika
- komunikaty o skrzyżowaniach w pobliżu

### 5.8 Ustawienia

Odzyskane ustawienia:

- język
- jednostki
- częstotliwość alertów
- dystans `Around me`
- automatyczne przeliczanie trasy
- zapowiedzi skrzyżowań
- notyfikacje o kierunku
- notyfikacje turn-by-turn
- wibracje przy manewrach

### 5.9 Integracje zewnętrzne

- Be My Eyes
- ridesharing / taxi
- deeplinki do miejsc / trasy

### 5.10 Wnioski z archiwalnego iOS UX

Z App Store i stron ViaOpta da się odzyskać nie tylko listę funkcji, ale też dość spójny język interfejsu.

- App Store z `2022-08-13` pokazuje 4 główne ekrany marketingowe:
  - `Route Summary` z adresem, czasem, wyborem typu transportu i trzema dużymi akcjami na dole
  - ekran kalibracji kierunku z wielką strzałką i komunikatem `Direct your device to find the route direction`
  - ekran integracji `Be My Eyes`
  - ekran pozycji bieżącej z wyszukiwarką, kartą adresu i dolnym panelem `Favourites`
- stara strona ViaOpta z `2016-10-06` ujawnia nazwy dodatkowych ekranów przez atrybuty `alt`:
  - `Home`
  - `Junctions`
  - `Accessibility`
  - `Details`
  - `Route Summary`
  - `Directions`
  - `Maps`
  - `Crossing details`
  - `Wheelchair accessible`
  - `Locations`
  - `route details`
  - `Traffic signals`
- nowsza strona produktu z `2019-07-22` grupuje aplikację wokół 4 komunikatów:
  - `Universal design & voice commands`
  - `Map & directions`
  - `Favorites`
  - `Junctions`
- marketing iOS był bardziej dopracowany niż Android, ale wnętrze aplikacji pozostawało celowo proste:
  - mocny biało-niebieski kontrast
  - mało ozdobników w samej aplikacji
  - duże cele dotykowe
  - jedna dominująca czynność na ekranie
  - mapa jako tło pomocnicze, nie główny nośnik informacji
- ważny sygnał projektowy dla `navilive`:
  - zachować prostotę przepływu i dużą hierarchię akcji z iOS
  - nie kopiować brandingu Novartis ani ilustracyjnej oprawy marketingowej 1:1
  - traktować mapę jako warstwę pomocniczą pod TTS, haptics i czytelne teksty

## 6. Problemy starej architektury

Z APK wynika, że ViaOpta używała:

- `HERE Places API v2`
- `HERE Routing API 7.2`
- OSM do danych skrzyżowań
- Google Maps / Google Places po stronie mapy i UI
- Firebase / Crashlytics / GTM

To oznacza kilka problemów:

- stare endpointy HERE są legacy i nie nadają się do dalszego rozwoju,
- część kluczy API była zaszyta w aplikacji,
- nie mamy wiarygodnej ścieżki prawnej do kopiowania brandingu, tekstów i assetów Novartis,
- iOS nie ma odzyskanego binarnego punktu odniesienia porównywalnego z Androidem.

## 7. Założenia dla navilive

### 7.1 Założenia produktowe

- `navilive` ma odtworzyć funkcje, nie markę ViaOpta
- UI ma być prostsze niż w klasycznych aplikacjach mapowych
- aplikacja ma działać sensownie bez patrzenia na ekran
- każdy główny ekran powinien mieć jedną dominującą akcję i maksymalnie kilka dużych przycisków
- mapa ma być wsparciem orientacji, a nie centralnym elementem poznawczym
- wersja MVP ma być Android-first
- iOS ma osiągnąć możliwie wierną funkcjonalnie zgodność po stabilizacji Androida

### 7.2 Założenia prawne

- nie kopiujemy nazwy `ViaOpta`
- nie publikujemy binarnej przeróbki starego APK
- nie używamy grafik, tekstów marketingowych i znaków towarowych Novartis
- zachowane APK traktujemy jako materiał referencyjny do interoperacyjności i analizy UX

## 8. Zakres produktu navilive

### 8.1 MVP

MVP powinno zawierać tylko to, co realnie daje wartość użytkownikowi końcowemu.

- onboarding:
  - wybór języka
  - krótki tutorial
  - ekran zgody i ostrzeżeń
- lokalizacja:
  - pozyskanie pozycji
  - foreground tracking na Androidzie
- wyszukiwanie:
  - wpisanie adresu lub nazwy miejsca
  - `Around me`
  - wyniki uporządkowane pod czytnik ekranu
- miejsca:
  - szczegóły miejsca
  - telefon / WWW jeśli dostępne
  - zapis do ulubionych
- ulubione:
  - lista
  - dodawanie / usuwanie / edycja nazwy
- routing:
  - trasa piesza
  - podsumowanie trasy
  - pokazanie trasy na mapie
- aktywna nawigacja:
  - TTS
  - wibracje
  - aktualny i następny manewr
  - ostrzeganie o zejściu z trasy
  - automatyczne przeliczanie
  - odczyt "gdzie jestem"
- ustawienia:
  - język
  - jednostki
  - częstotliwość alertów
  - auto-recalculation
  - wibracje
  - zapowiedzi skrzyżowań

### 8.2 V1.1

- waypointy pośrednie
- deeplink do współdzielonej lokalizacji
- transport publiczny
- `Around me` z kategoriami
- eksport / import ulubionych
- lepsza pauza / resume trasy

### 8.3 V2

- integracja z Be My Eyes
- lista ridesharing / taxi zainstalowanych na urządzeniu
- crowd-sourced notatki dostępności miejsca
- tryb opiekuna
- synchronizacja konta i backup w chmurze
- własny backend analityczny bez SDK reklamowych

## 9. Główne przepływy użytkownika

### 9.1 Start i szybka trasa

1. Użytkownik otwiera aplikację.
2. Aplikacja ustala pozycję i komunikuje status.
3. Użytkownik wybiera `Search`.
4. Wpisuje cel.
5. Otwiera `Route Summary`.
6. Wybiera `Start route`.
7. Otrzymuje komunikat kierunku startu i dalsze manewry.

### 9.2 Trasa do ulubionego miejsca

1. Użytkownik otwiera `Favourites`.
2. Wybiera zapisane miejsce.
3. Otwiera podsumowanie trasy.
4. Uruchamia aktywną nawigację.

### 9.3 Odczyt bieżącej lokalizacji

1. Użytkownik potrząsa urządzeniem albo uruchamia akcję `Where am I?`.
2. Aplikacja odczytuje bieżące położenie.
3. Jeśli trwa trasa, aplikacja podaje także relację do celu.

### 9.4 Zgubienie trasy

1. Aplikacja wykrywa opuszczenie polilinii lub sekwencji manewrów.
2. Użytkownik słyszy ostrzeżenie.
3. Aplikacja próbuje przeliczyć trasę.
4. Jeśli się nie uda, pokazuje prosty ekran błędu z akcją ponowienia.

## 10. Wymagania dostępności

To jest rdzeń produktu, nie dodatki.

- pełna obsługa TalkBack i VoiceOver
- każdy ekran musi być używalny bez mapy wizualnej
- kolejność fokusu musi odpowiadać logice zadania, nie układowi wizualnemu
- wszystkie akcje krytyczne muszą mieć jasne etykiety i hinty
- komunikaty głosowe nie mogą dublować się bez sensu z odczytem czytnika
- duże aktywne hitboxy
- wysoki kontrast
- brak ukrytych gestów bez alternatywy przyciskiem
- każda funkcja oparta o czujnik musi mieć alternatywę ekranową
- komunikaty błędu muszą mieć jedną prostą akcję główną

## 11. Wymagania niefunkcjonalne

- stabilność podczas spaceru z wygaszonym ekranem
- dobra praca w słabych warunkach sieciowych
- szybkie wznowienie po utracie fokusu aplikacji
- możliwość działania bez konta użytkownika
- oszczędne użycie baterii
- brak zależności od reklamowych SDK

## 12. Rekomendowana architektura techniczna

### 12.1 Strategia wdrożenia

Rekomendacja:

- Android first
- dopiero po stabilizacji Androida i walidacji UX budować iOS parity

Powód:

- jedyny zachowany artefakt referencyjny to Android APK,
- foreground tracking i aktywna nawigacja są prostsze do iteracji na Androidzie,
- łatwiej porównywać zachowanie z oryginałem.

### 12.2 Warstwy systemu

#### Warstwa mobilna

- Android: Kotlin + Jetpack Compose lub klasyczne View/Fragment tylko tam, gdzie łatwiej odwzorować a11y
- iOS: SwiftUI z natywną integracją CoreLocation / AVSpeechSynthesizer

#### Warstwa domenowa

- `Place`
- `Favorite`
- `Waypoint`
- `Route`
- `Maneuver`
- `IntersectionAlert`
- `NavigationSession`
- `Settings`

#### Warstwa usług

- geolokalizacja
- heading / compass
- TTS
- vibration / haptics
- routing
- places search
- intersection enrichment
- persistence
- deeplink/share

### 12.3 Dane mapowe i routing

Najbardziej praktyczna ścieżka:

- Places search / geocoding / routing:
  - nowoczesne API HERE albo inny aktywnie utrzymywany dostawca
- intersection enrichment:
  - OSM / Overpass / własny preprocessing
- rendering mapy:
  - MapLibre lub natywne Google Maps, ale mapa jest wtórna wobec trybu głosowego

#### Rekomendacja dla MVP

- wyszukiwanie i routing: komercyjny provider z dobrym walking routingiem
- skrzyżowania: OSM
- transit: dopiero po ustabilizowaniu trasy pieszej

#### Alternatywa długoterminowa

Jeśli chcemy maksymalnej niezależności:

- Photon lub Nominatim do geocodingu,
- Valhalla lub GraphHopper do tras pieszych,
- OpenTripPlanner do transportu publicznego,
- własny cache i preprocessing OSM.

Ta opcja daje większą kontrolę, ale znacząco zwiększa koszt operacyjny.

### 12.4 Persistence

- lokalna baza SQLite
- tabela ulubionych
- tabela ostatnich wyszukiwań
- tabela ustawień
- opcjonalnie lokalny cache ostatnich tras i skrzyżowań

### 12.5 Powiadomienia i TTS

- foreground service podczas aktywnej nawigacji na Androidzie
- kanał powiadomień dla nawigacji
- oddzielne poziomy komunikatów:
  - krytyczne
  - manewry
  - skrzyżowania
  - status systemu

## 13. Funkcje, które warto uprościć względem ViaOpta

- ridesharing nie powinien blokować MVP
- transport publiczny nie powinien wejść przed stabilną trasą pieszą
- nie warto odtwarzać Google Tag Manager ani starych analityk
- nie warto kopiować starej struktury ekranów 1:1, jeśli da się uprościć przepływ

## 14. Ryzyka

### Produktowe

- zbyt duża ambicja w pierwszej wersji
- nadmierne skupienie na mapie zamiast na audio UX

### Techniczne

- niedokładny heading na niektórych urządzeniach
- agresywne ograniczenia baterii i background execution
- jakość routingu pieszego zależna od providera
- różnice między Androidem i iOS w TTS i background location

### Prawne

- ryzyko zbyt dosłownego kopiowania treści lub assetów ViaOpta
- ryzyko publikowania zaszytych starych kluczy lub endpointów z APK

## 15. Kryteria sukcesu MVP

- użytkownik potrafi znaleźć miejsce i uruchomić trasę bez patrzenia na ekran
- aktywna nawigacja poprawnie prowadzi po trasie pieszej
- aplikacja potrafi ostrzec o zejściu z trasy i ją przeliczyć
- ulubione działają lokalnie i stabilnie
- najważniejsze ekrany przechodzą test TalkBack
- aplikacja utrzymuje sesję aktywnej nawigacji przez typowy spacer miejski

## 16. Proponowany plan realizacji

### Faza 0: research hardening

- spisać dokładne feature parity z APK
- przygotować własne copy i własne nazewnictwo ekranów
- wybrać providera routingu

### Faza 1: Android core

- skeleton app
- lokalizacja
- wyszukiwanie
- szczegóły miejsca
- ulubione
- route summary

### Faza 2: Android navigation

- aktywna nawigacja
- TTS
- heading
- haptics
- route recalculation
- intersection alerts

### Faza 3: testy użytkowe

- testy z TalkBack
- testy terenowe
- korekty copy i kolejności fokusu

### Faza 4: iOS parity

- odtworzenie stabilnego zakresu Android MVP

### Faza 5: rozszerzenia

- waypointy
- public transport
- Be My Eyes
- ridesharing

## 17. Decyzje do podjęcia przed startem kodowania

- czy idziemy Android first, czy od razu dwa systemy
- który provider odpowiada za routing i search w MVP
- czy transport publiczny jest w MVP czy dopiero po wersji 1.0
- czy integracja Be My Eyes ma wejść od razu
- czy aplikacja ma być całkiem offline-friendly, czy tylko online-first z cache

## 18. Rekomendacja końcowa

Najbardziej realistyczny plan dla `navilive`:

- etap 1: wierne funkcjonalnie odtworzenie Android MVP,
- etap 2: testy dostępności i spacery terenowe,
- etap 3: dopiero potem iOS oraz funkcje dodatkowe.

Nie próbujemy "wskrzesić starej ViaOpta" binarnie.
Budujemy nowy produkt, który zachowuje jej najważniejszą wartość:

- prostą,
- głosową,
- dostępnościową,
- pewną nawigację dla osób z dysfunkcją wzroku.

## 19. Źródła internetowe

- Wayback: https://web.archive.org/web/20161006181702/http://viaopta-apps.com:80/ViaOptaNav.html
- Wayback App Store `2022-08-13`: https://web.archive.org/web/20220813203717/https://apps.apple.com/us/app/nav-by-viaopta/id908435532
- Wayback App Store `2020-10-29`: https://web.archive.org/web/20201029040923/https://apps.apple.com/us/app/nav-by-viaopta/id908435532
- Wayback ViaOpta `2019-07-22`: https://web.archive.org/web/20190722142202/https://www.viaopta-apps.com/ViaOpta-Nav.html
- Novartis media release: https://www.novartis.com/news/media-releases/novartis-pharmaceuticals-launches-first-app-visually-impaired-people-use-apple-watch-and-other-smart-watches
- APKFab: https://apkfab.com/viaopta-nav/com.novartis.blind
- Uptodown: https://viaopta-nav.en.uptodown.com/android/download
- AppPure iOS metadata: https://iphone.apkpure.com/app/viaopta-nav/com.novartis.pharma.global.viaoptanav
- OSM Wiki note: https://wiki.openstreetmap.org/wiki/Nav_by_Viaopta
- HERE blog on migration from legacy services: https://www.here.com/learn/blog/upgrade-to-the-new-set-of-here-location-services-now-available-on-here-platform
