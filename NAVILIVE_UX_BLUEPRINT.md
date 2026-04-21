# Navi Live UX Blueprint

Blueprint interfejsu i przepływów dla `Navi Live`, oparty na odzyskanych materiałach `Nav by ViaOpta`

Data: 2026-04-07

## 1. Cel

Ten dokument przekłada materiały z archiwum App Store, stron ViaOpta i analizę starej aplikacji na docelowy UX dla `Navi Live`.

To nie jest wierna kopia dawnego UI.
To jest nowy interfejs, który zachowuje najważniejsze cechy starego produktu:

- bardzo niski koszt poznawczy
- duże i czytelne cele dotykowe
- jedna dominująca czynność na ekranie
- mapa jako warstwa pomocnicza
- pierwszeństwo dla głosu, haptics i dostępności

## 2. Co przenosimy z ViaOpta

### Z iOS App Store `2022`

- ekran `Route Summary` z jedną decyzją główną: uruchom trasę
- ekran ustawienia kierunku z wielką strzałką i bardzo małą liczbą elementów
- ekran bieżącej pozycji z wyszukiwarką na górze i ulubionymi na dole
- prosty, biało-niebieski kontrast i duże przyciski

### Z dawnych stron ViaOpta `2016-2020`

- myślenie ekranami: `Home`, `Junctions`, `Details`, `Route Summary`, `Directions`, `Maps`, `Locations`
- nacisk na `Universal design & voice commands`
- nacisk na `Favorites` i `Junctions`
- mapa wspiera orientację, ale nie przejmuje interfejsu

## 3. Zasady interfejsu

### 3.1 Zasady główne

- każdy ekran ma jedną dominującą akcję
- liczba akcji pierwszego poziomu na ekranie nie powinna przekraczać `3`
- ekran musi być zrozumiały po samym odczycie czytnikiem ekranu
- ekran nie może wymagać patrzenia na mapę, żeby użytkownik wiedział co zrobić dalej
- jeżeli jakaś informacja jest krytyczna dla ruchu, musi istnieć jako:
  - tekst
  - komunikat głosowy
  - opcjonalnie haptic

### 3.2 Zasady wizualne

- tło jasne, wysokokontrastowe
- kolor akcji głównej: niebieski
- kolor ostrzeżeń: bursztynowy lub czerwony tylko dla stanów wyjątkowych
- duże przyciski o wysokości co najmniej `56dp`
- duże odstępy między celami dotykowymi
- mapa częściowo widoczna, ale nie może konkurować z treścią

### 3.3 Zasady dla czytników ekranu

- najpierw status ekranu, potem najważniejsza decyzja, potem akcje pomocnicze
- elementy dekoracyjne mają być ukryte dla TalkBack i VoiceOver
- kolejność fokusu ma zgadzać się z naturalnym flow zadania
- nie używać gestów wymaganych do wykonania podstawowej akcji

## 4. Architektura ekranów MVP

MVP powinno mieć `8` głównych ekranów:

1. `Start`
2. `Search`
3. `Place Details`
4. `Route Summary`
5. `Heading Align`
6. `Active Navigation`
7. `Current Position`
8. `Favorites`

Do tego dochodzą ekrany pomocnicze:

- `Onboarding`
- `Permissions`
- `Settings`
- `Route Recalculation Sheet`
- `Arrival`
- `Error / GPS weak`

## 5. Główne przepływy

### 5.1 Szybka trasa

`Start` -> `Search` -> `Place Details` -> `Route Summary` -> `Heading Align` -> `Active Navigation`

### 5.2 Trasa do ulubionego

`Start` -> `Favorites` -> `Route Summary` -> `Heading Align` -> `Active Navigation`

### 5.3 Gdzie jestem

`Start` -> `Current Position`

### 5.4 Zgubienie trasy

`Active Navigation` -> `Route Recalculation Sheet` -> powrót do `Active Navigation`

## 6. Ekrany docelowe

### 6.1 Start

Cel:
- dać użytkownikowi trzy najważniejsze drogi wejścia bez chaosu

Akcja główna:
- `Dokąd chcesz iść?`

Akcje pomocnicze:
- `Gdzie jestem`
- `Ulubione`

Elementy:
- pole / duży przycisk wyszukiwania
- ostatni cel lub ostatnia trasa, jeśli istnieje
- przycisk ustawień w prawym górnym rogu

Kolejność fokusu:
1. tytuł ekranu
2. status lokalizacji
3. `Dokąd chcesz iść?`
4. `Gdzie jestem`
5. `Ulubione`
6. `Ostatnia trasa`
7. `Ustawienia`

Wireframe:

```text
+----------------------------------+
| Navi Live               Settings  |
| Lokalizacja gotowa               |
|                                  |
| [ Dokąd chcesz iść?           ]  |
|                                  |
| [ Gdzie jestem ]                 |
| [ Ulubione    ]                  |
|                                  |
| Ostatnia trasa                   |
| Dom -> Praca                     |
| [ Wznów trasę ]                  |
+----------------------------------+
```

### 6.2 Search

Cel:
- możliwie szybko znaleźć cel bez przeładowania mapą

Akcja główna:
- wpisanie lub wybranie miejsca

Akcje pomocnicze:
- `W pobliżu`
- `Wyniki`

Elementy:
- jedno duże pole wyszukiwania
- duży przycisk mikrofonu tylko jeśli speech input będzie stabilny
- lista wyników jako pełnowymiarowe wiersze
- brak miniaturowych ikon wymagających precyzji

Kolejność fokusu:
1. pole wyszukiwania
2. `W pobliżu`
3. wyniki od góry

### 6.3 Place Details

Cel:
- potwierdzić, że wybrano właściwe miejsce

Akcja główna:
- `Pokaż trasę`

Akcje pomocnicze:
- `Zapisz do ulubionych`
- `Udostępnij`

Elementy:
- nazwa
- adres
- odległość od użytkownika
- telefon / WWW jeśli istnieją
- mała mapa pomocnicza, opcjonalna

### 6.4 Route Summary

Cel:
- przedstawić trasę w jednym czytelnym podsumowaniu

Akcja główna:
- `Start trasy`

Akcje pomocnicze:
- `Pokaż wskazówki`
- `Zapisz ulubione`

Elementy:
- nazwa celu i adres
- przewidywany czas
- przewidywany dystans
- wybór trybu ruchu:
  - pieszo
  - transport publiczny później, poza MVP
- uproszczona mapa z trasą

Kolejność fokusu:
1. cel
2. czas i dystans
3. typ trasy
4. `Start trasy`
5. `Pokaż wskazówki`
6. `Zapisz ulubione`

Wireframe:

```text
+----------------------------------+
| Back               Route Summary |
|                                  |
| 46 Gray's Inn Road               |
| City of London                   |
| 5 min • 420 m                    |
|                                  |
| [ Pieszo ]                       |
|                                  |
|        mapa pomocnicza           |
|                                  |
| [ Zapisz ulubione ]              |
| [ Pokaż wskazówki ]              |
| [ Start trasy ]                  |
+----------------------------------+
```

### 6.5 Heading Align

Cel:
- ustawić użytkownika we właściwym kierunku startu

Akcja główna:
- obróć się i zacznij iść

Akcje pomocnicze:
- `Pomiń`
- `Powtórz komunikat`

Elementy:
- bardzo duża strzałka kierunku
- prosty komunikat tekstowy
- status:
  - `Obróć się lekko w lewo`
  - `Obróć się w prawo`
  - `Jesteś ustawiony prawidłowo`
- haptic po złapaniu poprawnego kierunku

Kolejność fokusu:
1. instrukcja
2. status kierunku
3. `Powtórz komunikat`
4. `Pomiń`

Wireframe:

```text
+----------------------------------+
| Ustaw kierunek                   |
|                                  |
| Skieruj telefon, aby znaleźć     |
| właściwy kierunek trasy          |
|                                  |
|             ↑                    |
|                                  |
| Obróć się lekko w lewo           |
|                                  |
| [ Powtórz komunikat ]            |
| [ Pomiń ]                        |
+----------------------------------+
```

### 6.6 Active Navigation

Cel:
- prowadzić bez konieczności patrzenia na ekran

Akcja główna:
- kontynuuj marsz według wskazówek

Akcje pomocnicze:
- `Powtórz ostatni komunikat`
- `Pauza`
- `Zakończ`

Elementy:
- aktualny manewr
- następny manewr
- dystans do manewru
- status zejścia z trasy
- bardzo uproszczona mapa lub całkiem schowana przy trybie dostępności

Zasada:
- po wejściu na ten ekran aplikacja od razu zaczyna aktywne prowadzenie głosowe

### 6.7 Current Position

Cel:
- szybko powiedzieć użytkownikowi, gdzie jest

Akcja główna:
- `Powiedz moją lokalizację`

Akcje pomocnicze:
- `Pokaż szczegóły`
- `Zapisz to miejsce`

Elementy:
- bieżący adres
- orientacyjna okolica
- panel `Favourites` na dole jako szybkie wejście do tras
- opcjonalny gest potrząśnięcia, ale nie jako jedyny sposób

### 6.8 Favorites

Cel:
- błyskawicznie uruchomić trasę do znanych miejsc

Akcja główna:
- wybór miejsca

Akcje pomocnicze:
- `Dodaj nowe`
- `Edytuj nazwę`
- `Usuń`

Elementy:
- lista pełnoekranowych pozycji
- opcjonalne grupowanie:
  - dom
  - praca
  - zdrowie
  - inne

## 7. Ekrany pomocnicze

### 7.1 Onboarding

Maksymalnie `3` ekrany:

- czym jest `Navi Live`
- jak działa głos i wibracje
- jakie uprawnienia są potrzebne

### 7.2 Settings

Na MVP tylko rzeczy naprawdę potrzebne:

- język
- częstotliwość komunikatów
- wibracje
- automatyczne przeliczanie trasy
- komunikaty o skrzyżowaniach

### 7.3 Arrival

Po dotarciu:

- komunikat głosowy
- wibracja
- ekran z trzema akcjami:
  - `Zakończ`
  - `Wróć`
  - `Zapisz do ulubionych`

## 8. Czego nie kopiować z dawnych aplikacji mapowych

- małych ikon w narożnikach jako głównej nawigacji
- zatłoczonego paska narzędzi
- wielu równorzędnych przycisków na jednym ekranie
- mapy pełnoekranowej jako jedynego źródła prawdy
- ukrywania ważnych funkcji pod gestami

## 9. Priorytety implementacyjne

### MVP Android

1. `Start`
2. `Search`
3. `Place Details`
4. `Route Summary`
5. `Heading Align`
6. `Active Navigation`
7. `Current Position`
8. `Favorites`
9. `Settings`

### Po MVP

- `Junctions` jako osobny widok lub karta kontekstowa
- `Be My Eyes`
- waypointy
- transport publiczny
- tryb opiekuna / konfiguracji wspomaganej

## 10. Jednozdaniowa reguła projektowa

Jeżeli użytkownik niewidomy po wejściu na ekran nie wie w ciągu kilku sekund, jaka jest jedna najważniejsza akcja, to ekran jest zbyt skomplikowany.

## 11. Mapowanie materiału źródłowego na Navi Live

Ta sekcja łączy odzyskane artefakty z konkretnymi ekranami i decyzjami UX.

### 11.1 iOS App Store `2022`

Screen `01`:
- komunikat marketingowy o prowadzeniu głosowym
- wewnątrz urządzenia: `Route Summary`
- decyzja dla `Navi Live`:
  - zachować układ `cel -> czas -> typ ruchu -> mapa pomocnicza -> 3 duże akcje`

Screen `02`:
- komunikat marketingowy o ustawieniu właściwego kierunku
- wewnątrz urządzenia: ekran kalibracji kierunku
- decyzja dla `Navi Live`:
  - wielka strzałka ma być centralnym elementem
  - na ekranie nie powinno być więcej niż `2` akcje pomocnicze

Screen `03`:
- komunikat marketingowy o `Be My Eyes`
- wewnątrz urządzenia: osobny ekran wsparcia z prostym CTA
- decyzja dla `Navi Live`:
  - potraktować to jako późniejszy moduł `Pomoc na żywo`
  - nie mieszać tego z głównym flow MVP

Screen `04`:
- komunikat marketingowy o szybkim ustaleniu pozycji
- wewnątrz urządzenia: hybryda `Current Position` i `Start`
- decyzja dla `Navi Live`:
  - wyszukiwarka zostaje u góry
  - karta bieżącego adresu jest zaraz pod nią
  - `Favourites` mogą być rozwijane od dołu jako szybkie przejście do trasy

### 11.2 ViaOpta `2016`

Nazwy ekranów z atrybutów `alt` potwierdzają, że stara aplikacja myślała zadaniami, nie menu warstwowym.

Mapowanie:
- `Home` -> `Start`
- `Locations` -> `Search` i `Favorites`
- `Details` -> `Place Details`
- `Route Summary` -> `Route Summary`
- `Directions` -> `Active Navigation`
- `Maps` -> warstwa pomocnicza mapy
- `Junctions` i `Crossing details` -> późniejszy moduł `Junctions`
- `Traffic signals` -> kontekst rozszerzeń po MVP

### 11.3 ViaOpta `2019-2020`

Nowsza strona produktowa porządkuje wartość aplikacji w 4 filary:

- `Universal design & voice commands`
- `Map & directions`
- `Favorites`
- `Junctions`

Decyzja dla `Navi Live`:
- MVP musi pokryć pierwsze `3`
- `Junctions` może wejść najpierw jako lekki alert kontekstowy, a nie od razu pełny osobny ekran

## 12. Wspólne komponenty i tokeny

Te elementy powinny być współdzielone między ekranami, żeby UX był przewidywalny.

### 12.1 Komponenty bazowe

`Top bar`
- tytuł ekranu
- opcjonalny back
- maksymalnie `1` akcja po prawej stronie

`Primary action button`
- pełna szerokość
- minimalna wysokość `56dp`
- zawsze opisany czasownikiem

`Secondary action button`
- pełna szerokość lub połówka, ale nadal duży cel dotykowy
- nie więcej niż `2` na ekranie

`Status card`
- pokazuje stan lokalizacji, GPS, trasę lub ostrzeżenie
- pierwsza karta po wejściu na ekran, jeśli stan jest ważny dla zadania

`Place row`
- nazwa
- adres
- czas i dystans
- cały wiersz klikalny

`Guidance card`
- aktualny manewr
- następny manewr
- dystans do manewru

`Bottom favourites panel`
- dostępny na `Start` i `Current Position`
- otwiera szybkie trasy do zapisanych miejsc

`Warning sheet`
- używany dla `off-route`, słabego GPS lub błędów routingu
- ma jedną główną decyzję i jedną akcję pomocniczą

### 12.2 Tokeny wizualne

Kolory:
- `Primary Blue`: główna akcja i aktywny fokus
- `Surface White`: tło ekranów
- `Map Neutral`: wyciszona mapa pomocnicza
- `Success Green`: tylko dla potwierdzenia ustawienia kierunku i dotarcia
- `Warning Amber`: słaby GPS, niepewny kierunek, utrata dokładności
- `Critical Red`: tylko stany awaryjne i destrukcyjne

Typografia:
- tytuł ekranu: duży, prosty, bez ozdobników
- główna akcja: duży tekst przycisku
- status: krótki tekst pomocniczy pod tytułem lub pod kartą stanu
- komunikaty nie mogą być wielozdaniowymi blokami, jeśli da się je skrócić

Skala odstępów:
- `8dp` dla drobnych relacji
- `12dp` dla grup pokrewnych
- `16dp` jako standard sekcji
- `24dp` między głównymi blokami zadania

### 12.3 Reguły mapy

- mapa nie może zajmować całego ekranu w żadnym krytycznym przepływie MVP
- mapa ma wspierać orientację, nie zastępować tekstu i głosu
- w `Active Navigation` mapa może być:
  - bardzo mała
  - schowana
  - przełączalna w trybie dostępności

## 13. Matryca zachowań głosu, haptic i stanów

To jest warstwa, która robi realną różnicę dla użytkownika niewidomego.

### 13.1 Start

Voice:
- po wejściu opcjonalnie odczytaj stan lokalizacji tylko jeśli się zmienił

Haptic:
- delikatne potwierdzenie naciśnięcia przycisków

Stany:
- lokalizacja gotowa
- lokalizacja w trakcie
- brak zgody na lokalizację

### 13.2 Search

Voice:
- nie czytać całej listy automatycznie
- czytać wyniki normalnym fokusem czytnika ekranu

Haptic:
- brak specjalnych wzorców poza standardowym potwierdzeniem

Stany:
- pusty
- ładowanie
- brak wyników
- błąd sieci

### 13.3 Place Details

Voice:
- po wejściu krótko: nazwa, adres, czas dojścia

Haptic:
- delikatne potwierdzenie dodania do ulubionych

Stany:
- komplet danych
- brak telefonu / WWW
- brak pewności lokalizacji miejsca

### 13.4 Route Summary

Voice:
- po wejściu: cel, czas i dystans
- przy zmianie typu ruchu: nowy czas i dystans

Haptic:
- lekkie potwierdzenie `Start trasy`

Stany:
- trasa gotowa
- trasa niepewna
- brak trasy

### 13.5 Heading Align

Voice:
- komunikat kierunkowy w prostym języku:
  - `obróć się lekko w lewo`
  - `obróć się w prawo`
  - `jesteś ustawiony prawidłowo`

Haptic:
- pojedyncze krótkie impulsy przy poprawie ustawienia
- wyraźny podwójny impuls przy poprawnym ustawieniu

Stany:
- brak pewnego headingu
- korekta w toku
- gotowe do startu

### 13.6 Active Navigation

Voice:
- aktualny manewr
- następny manewr
- zejście z trasy
- ponowne przeliczenie
- dotarcie

Haptic:
- lekki impuls przy standardowym manewrze
- mocniejszy wzorzec przy zejściu z trasy
- krótki sukces przy dotarciu

Stany:
- normalna nawigacja
- pauza
- off-route
- słaby GPS
- dotarcie

### 13.7 Current Position

Voice:
- główna akcja zawsze musi odczytać adres i orientacyjny kontekst
- potrząśnięcie może to powtórzyć, ale nie może być jedyną metodą

Haptic:
- jedno potwierdzenie po poprawnym odczycie lokalizacji

Stany:
- lokalizacja dokładna
- lokalizacja przybliżona
- brak sygnału

### 13.8 Favorites

Voice:
- nazwa miejsca, adres i orientacyjny czas dojścia

Haptic:
- lekkie potwierdzenie dodania, edycji i usunięcia

Stany:
- lista pełna
- pusta lista
- edycja

## 14. Stany krytyczne, które muszą mieć własny UX

Nie wolno ich zostawić jako przypadkowych toastów albo drobnego tekstu.

`GPS weak`
- osobny status card lub sheet
- prosty komunikat co zrobić:
  - poczekaj chwilę
  - wyjdź na otwartą przestrzeń
  - spróbuj ponownie

`Off-route`
- komunikat głosowy
- wyraźny haptic
- jedna główna decyzja:
  - `Przelicz trasę`

`No route found`
- komunikat bez żargonu technicznego
- akcje:
  - `Spróbuj ponownie`
  - `Wróć`

`Permission blocked`
- jednoznaczne wyjaśnienie po co potrzebna lokalizacja
- prosty przycisk przejścia do ustawień systemowych

## 15. Minimalny kontrakt implementacyjny dla Android MVP

To jest skrót tego, co implementacja powinna umieć, żeby nie rozjechać się z blueprintem.

- każdy ekran ma wyraźnie zdefiniowaną akcję główną
- każdy ekran ma poprawną kolejność fokusu dla TalkBack
- wszystkie krytyczne informacje o ruchu istnieją jako tekst i voice
- `Heading Align` działa bez patrzenia na ekran
- `Current Position` pozwala odczytać adres bez analizowania mapy
- `Route Summary` nie wymaga przewijania, żeby uruchomić trasę na typowym telefonie
- `Active Navigation` pozostaje czytelne również przy schowanej mapie
