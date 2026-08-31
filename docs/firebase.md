# Firebase dla Navi Live

## Zakres

Navi Live korzysta z osobnego projektu Firebase:

- projekt: `navi-live-kazek5p` (Navi Live),
- Android: `com.navilive.app`,
- iOS: `com.kazek.navilive`.

Listen SDR pozostaje w projekcie `listen-sdr-kazek5p` i nie może korzystać z tej konfiguracji.

Obecnie Firebase służy Navi Live do dystrybucji wersji testowych Androida przez App Distribution. iOS jest nadal dystrybuowany przez TestFlight. Aplikacja Navi Live nie inicjalizuje jeszcze Firebase SDK, Crashlytics ani Remote Config, więc do tego kanału nie są potrzebne pliki `google-services.json` ani `GoogleService-Info.plist` w kodzie aplikacji.

## Dystrybucja Androida

- aplikacja Firebase: `1:544314236646:android:05a4a4dca755c911aea527`,
- grupa testerów: `navi-live-android-testers` (Navi Live Android testers),
- link zaproszenia: <https://appdistribution.firebase.dev/i/9fda8206d65000d8>.

Link jest publiczny. Po dołączeniu tester otrzyma najnowszy release wysłany do tej grupy.

Publikację wykonuje skrypt [Publish-NaviLive-FirebaseAppDistribution.ps1](../scripts/Publish-NaviLive-FirebaseAppDistribution.ps1). Wymaga on uwierzytelnienia ustawionego poza repozytorium przez `FIREBASE_TOKEN` albo `GOOGLE_APPLICATION_CREDENTIALS`.

Przykład:

```powershell
.\scripts\Publish-NaviLive-FirebaseAppDistribution.ps1
```

Domyślny plik APK to `android\app\build\release-asset\navi-live.apk`. Skrypt nie przechowuje tokenów, kluczy kont usług ani danych logowania.

## iOS

Aplikacja Firebase iOS ma identyfikator `1:544314236646:ios:ba7cd67d36ebbf2eaea527`. Nie zastępuje ona TestFlight; służy wyłącznie do przyszłych usług Firebase, jeśli zostaną świadomie włączone.
