# Pomocnicza lokalizacja radiowa na Androidzie

## Zakres

Androidowa wersja Navi Live nadal korzysta z GPS-u jako podstawowego źródła
pozycji. Wi-Fi i Bluetooth Low Energy są wyłącznie pomocniczym sygnałem dla
przypadków, w których GPS jest słaby. Wynik radiowy nie jest pokazywany ani
odczytywany użytkownikowi.

Skanowanie jest uruchamiane z usługi śledzenia na żywo, tylko po otrzymaniu
słabego fixa GPS. Jedno skanowanie trwa najwyżej dwie sekundy, a kolejne próby
są ograniczane czasowo. Brak uprawnień, wyłączone radio, brak internetu albo
błąd usługi nie zatrzymuje śledzenia GPS.

## Wykorzystywane dane

Skaner przekazuje do beaconDB wyłącznie:

- identyfikatory BSSID wykrytych punktów Wi-Fi i ich siłę sygnału,
- adresy wykrytych reklam iBeacon, AltBeacon lub Eddystone oraz ich siłę sygnału.

Navi Live nie wysyła nazw sieci Wi-Fi, nazw urządzeń Bluetooth, treści reklam
BLE ani tekstu wyszukiwania. beaconDB otrzymuje zestaw identyfikatorów radiowych,
ale nie otrzymuje bieżących współrzędnych GPS aplikacji.

## Zabezpieczenia przed błędną pozycją

Wynik beaconDB jest używany dopiero wtedy, gdy:

- wykryto co najmniej dwa niezależne identyfikatory radiowe,
- odpowiedź zawiera prawidłowe współrzędne i dokładność,
- dokładność oraz odległość od ostatniego GPS-u mieszczą się w limitach,
- GPS jest rzeczywiście słaby.

Korekta jest ograniczona do małego przesunięcia względem GPS-u. Pojedyncza
sieć Wi-Fi albo pojedynczy beacon nigdy nie może samodzielnie zmienić pozycji.

## Uprawnienia

Na Androidzie 12 i nowszym skanowanie beaconów wymaga uprawnień
`BLUETOOTH_SCAN` i `BLUETOOTH_CONNECT`. Skanowanie Wi-Fi korzysta z dostępu do
lokalizacji oraz, na nowszych wersjach Androida, z `NEARBY_WIFI_DEVICES`.
Uprawnienia radiowe są pomocnicze: ich odmowa nie blokuje podstawowej nawigacji
GPS.

## Usługa zewnętrzna i ograniczenia

Do zapytania używany jest eksperymentalny publiczny punkt API beaconDB:
`https://api.beacondb.net/v1/geolocate`.

Połączenie ma krótki limit czasu i krótką pamięć podręczną w pamięci procesu.
beaconDB może mieć niepełne pokrycie, zwracać brak wyniku albo podawać pozycję
o gorszej dokładności niż GPS. Funkcja nie jest traktowana jako gwarantowane
ustalenie pozycji i nie zastępuje sprawdzania otoczenia przez użytkownika.

WiGLE nie jest obecnie używany jako źródło danych. Jego wykorzystanie wymagałoby
osobnej oceny warunków usługi, limitów, konta oraz sposobu ochrony identyfikatorów
radiowych.

## Testy

Kod bez urządzenia sprawdza między innymi budowę zapytania, walidację odpowiedzi,
pamięć podręczną, odrzucenie pojedynczej obserwacji, odrzucenie odległego wyniku
i ograniczenie maksymalnej korekty względem GPS-u. Na urządzeniu trzeba dodatkowo
sprawdzić odmowę uprawnień, wyłączone Wi-Fi i Bluetooth, brak sieci oraz telefon
z dobrym GPS-em, na którym skanowanie nie powinno być uruchamiane.
