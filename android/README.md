# Navi Live Android scaffold

This directory contains the first working Android implementation for `Navi Live`:

- Kotlin + Jetpack Compose
- Navigation Compose flow for MVP screens
- Foreground location tracking service (Fused Location)
- Runtime permission flow (location + notification)
- First-run flow with `Bootstrap -> Onboarding -> Permissions -> Start`
- Real online search and routing integration (Nominatim + OSRM)
- Reverse geocoding for a readable current address
- TTS + haptic feedback in navigation events
- Persistent favorites, settings and last route via DataStore
- Full route steps from OSRM with live step progression
- Automatic off-route detection with optional auto-recalculation
- Debug telemetry buffer with export and share from Settings
- Blueprint-aligned accessibility-first screen hierarchy
- Automatic localization from the phone language with European locale coverage
- GitHub Releases updater with automatic startup checks, in-app check, APK download and installer handoff
- One primary updater action that can run `download -> allow installs -> install` as a single flow
- Stable/beta update channels
- Version/build and latest changelog preview directly on the start screen
- Build confirmed with `assembleDebug`

## Requirements

- Windows with Android SDK installed
- JDK 17+ (current machine uses JDK 21)

## Build

From this directory:

```powershell
.\gradlew.bat assembleDebug
```

APK output:

`app\build\outputs\apk\debug\app-debug.apk`

Staged GitHub release asset:

`app\build\release-asset\navi-live.apk`

Prepare that asset directly:

```powershell
.\gradlew.bat :app:stageDebugReleaseAsset
```

## Implemented flow

`Bootstrap -> Onboarding -> Permissions -> Start -> Search -> Place Details -> Route Summary -> Heading Align -> Active Navigation -> Arrival`

Additional screens:

- `Current Position`
- `Favorites`
- `Settings`

## UX status

Current Android MVP now follows the local `NAVILIVE_UX_BLUEPRINT.md` more closely:

- large primary and secondary actions
- status cards for permission, GPS quality, active guidance and errors
- simplified route summary and heading alignment
- current position screen focused on address playback, not raw map reading
- favorites and start screen optimized for fast repeat journeys

## Integration notes

- Local seed places are intentionally empty, so the app starts without demo destinations.
- Legacy London demo IDs are removed from defaults and cleaned from saved preferences on startup.
- App UI, spoken guidance, route fallback text, notifications and share flows now use Android string resources instead of hardcoded English text.
- Android locale selection follows the system language automatically via `localeConfig`; no separate in-app language picker is required.
- The project includes generated resource sets for supported European locales under `app/src/main/res/values-*`.
- Polish (`values-pl`) was additionally reviewed and refined manually after generation.
- The translation generator is in `tools/generate_translations.py`.
- Favorites, settings, onboarding state and last route are persisted by `NavilivePreferencesStore`.
- Speech settings now support two output sources: Android system TTS or the active spoken accessibility service.
- System TTS can now target a specific installed speech engine package, or follow the Android default engine.
- The Settings screen includes a direct shortcut into Android's system TTS settings screen.
- Speech rate and relative speech volume are configurable for system TTS; when screen reader output is selected, those controls stay visible but disabled because the screen reader owns them.
- Online place search uses OpenStreetMap Nominatim (`OpenStreetRoutingRepository.searchPlaces`).
- Reverse geocoding for current address also uses Nominatim (`OpenStreetRoutingRepository.reverseGeocode`).
- Walking route summary uses OSRM public demo endpoint (`OpenStreetRoutingRepository.buildWalkingRoute`) with full step list and route geometry.
- Foreground tracking service is `LocationForegroundService`.
- Shared runtime location state is `LocationTrackerStore`.
- TTS/haptic feedback is handled by `GuidanceFeedbackEngine`.
- Live route progression, step changes and off-route logic are coordinated in `NaviliveViewModel`.
- Navigation telemetry is buffered by `NavigationTelemetryLogger` and can be exported from `Settings`.
- App updates are fetched from GitHub Releases by `GitHubUpdateRepository`.
- Navi Live now performs one silent update check on app startup after preferences finish loading.
- Stable channel follows the latest regular GitHub release; beta channel scans the full GitHub releases list and will surface prereleases when they exist.
- Downloaded update APKs are stored under app-internal `files/debug/updates` and persisted across app restarts until installed or superseded.
- Installation is handed off to the Android package installer through the app `FileProvider`.
- When the user starts an in-app `download and install` flow, Navi Live will automatically continue with APK installation after the required Android permission screen returns.
- The updater now prefers GitHub release assets named `navi-live.apk`, then falls back to older APK names when needed.
- The repository release flow is automated by `..\scripts\publish-github-release.ps1`, which builds `navi-live.apk`, updates or creates the GitHub release, removes old APK assets and uploads the new one.
