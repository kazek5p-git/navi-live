# navilive Android Backlog

Stan na: 2026-04-20

Ten backlog zakłada obecny MVP Android po wdrożeniu blueprintu UX, zielonym `assembleDebug`, trwałym `DataStore` i flow `Onboarding -> Permissions -> Start`.

## 1. Najwyższy priorytet

- Zastąpić publiczne endpointy demo `Nominatim` i `OSRM` własnym lub stabilniejszym providerem produkcyjnym.
- Dodać trwały cache ostatniej trasy i pełnych kroków nawigacyjnych, nie tylko ostatniej destynacji i ustawień.
- Dopracować politykę progów dla `step advance` i `off-route` po testach terenowych na realnym urządzeniu.
- Przejrzeć eksporty telemetry i na ich podstawie dobrać progi osobno dla `good GPS` i `weak GPS`.

## 2. Guidance i nawigacja

- Zamienić uproszczony `Heading Align` na realne dane kompasu / headingu.
- Rozszerzyć live guidance o automatyczne zakończenie trasy przy dojściu do celu.
- Oprzeć progres kroków nie tylko o punkty manewrów, ale także o przebieg segmentów i kierunek ruchu.
- Dodać cache ostatniej trasy i ostatnich instrukcji dla lepszej odporności na chwilowy brak sieci.

## 3. Dostępność

- Przejść po wszystkich ekranach z TalkBack i sprawdzić realną kolejność fokusu na urządzeniu.
- Dodać testowe checklisty accessibility dla `Start`, `Route Summary`, `Heading Align` i `Active Navigation`.
- Ograniczyć wszelkie dekoracyjne elementy mapy do pełnego `semantics = invisibleToUser`, jeśli zaczną przeszkadzać czytnikowi.

## 4. Dane lokalizacji

- Ograniczyć częstotliwość reverse geocodingu dodatkowymi progami czasu i dystansu po testach terenowych.
- Dodać fallback dla reverse geocodingu offline lub cache ostatnio rozpoznanych adresów.
- Rozróżniać bardziej precyzyjnie `coarse`, `fine`, `no fix` i `stale fix`.

## 5. Produkt po MVP

- Moduł `Junctions` jako kontekstowe alerty i potem osobny widok.
- `Be My Eyes` lub inny moduł wsparcia na żywo.
- Waypointy pośrednie.
- Transport publiczny.
- Tryb opiekuna / konfiguracji wspomaganej.

## 6. Techniczne porządki

- Dodać testy jednostkowe dla `OpenStreetRoutingRepository` i `NaviliveViewModel`.
- Wydzielić wspólne komponenty UI do osobnych plików zamiast trzymać wszystko w `Screens.kt`.
- Wprowadzić string resources dla tekstów ekranowych zamiast hardcoded strings w Kotlinie.
- Dodać flavor `demo` i `prod`, jeśli pojawi się własny backend lub własne klucze.
