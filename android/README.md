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
- Backup and restore of settings, favorites, custom places, last route and onboarding state
- Full route steps from OSRM with live step progression
- Automatic off-route detection with optional auto-recalculation
- Stricter pedestrian crossing filtering so nearby side crossings do not take priority over real maneuvers
- Active route step list during live guidance for quick review with TalkBack or another screen reader
- Reduced accidental shake-to-repeat triggers with stronger thresholds and a longer cooldown
- Debug telemetry buffer with export and share from Settings
- Blueprint-aligned accessibility-first screen hierarchy
- Automatic localization from the phone language with configured multilingual locale coverage
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
- Requested app locales are configured for `en`, `pl`, `ru`, `uk`, `ar`, `fa`, `tr`, `de`, `fr`, `es`, `it`, `pt`, `ro`, `cs`, `sk`, `be`, `lt`, `lv`, `et`, `hu`, `fi`, `hr`, `sr`, `el`, `bn`, `hi`, `id`, `vi`, `zh-Hans`, `ja`, `ko`, and `ckb`.
- Android translations can be updated with `python android/tools/generate_translations.py`; the generator maps Android BCP-47 resource folders for `id`, `zh-Hans`, and `ckb`.
- Cross-platform locale coverage can be checked with `python scripts/Validate-NaviLive-Locales.py` from the repository root.
- The project includes generated resource sets for supported European locales under `app/src/main/res/values-*`.
- Polish (`values-pl`) was additionally reviewed and refined manually after generation.
- The translation generator is in `tools/generate_translations.py`.
- Favorites, settings, onboarding state and last route are persisted by `NaviLivePreferencesStore`.
- Speech settings now support two output sources: Android system TTS or the active spoken accessibility service.
- System TTS can now target a specific installed speech engine package, or follow the Android default engine.
- The Settings screen includes a direct shortcut into Android's system TTS settings screen.
- Speech rate and relative speech volume are configurable for system TTS; when screen reader output is selected, those controls stay visible but disabled because the screen reader owns them.
- Online place search uses OpenStreetMap Nominatim (`OpenStreetRoutingRepository.searchPlaces`).
- Reverse geocoding for current address also uses Nominatim (`OpenStreetRoutingRepository.reverseGeocode`).
- Walking route summary uses OSRM public demo endpoint (`OpenStreetRoutingRepository.buildWalkingRoute`) with full step list and route geometry.
- Very short turn-like route steps that look like crossing a named street are announced as crossing that street instead of turning into it.
- Pedestrian crossings are fetched from Overpass with geometry and are kept only when they sit very close to the walking route and align with the route direction.
- Foreground tracking service is `LocationForegroundService`.
- Shared runtime location state is `LocationTrackerStore`.
- TTS/haptic feedback is handled by `GuidanceFeedbackEngine`.
- Live route progression, step changes and off-route logic are coordinated in `NaviLiveViewModel`.
- Navigation telemetry is buffered by `NavigationTelemetryLogger` and can be exported from `Settings`.
- App updates are fetched from GitHub Releases by `GitHubUpdateRepository`.
- Navi Live now performs one silent update check on app startup after preferences finish loading.
- Stable channel follows the latest regular GitHub release; beta channel scans the full GitHub releases list and will surface prereleases when they exist.
- Stable update checks now fall back to the full release list if GitHub's `latest` endpoint cannot provide a usable APK release.
- Downloaded update APKs are stored under app-internal `files/debug/updates` and persisted across app restarts until installed or superseded.
- Installation is handed off to the Android package installer through the app `FileProvider`.
- When the user starts an in-app `download and install` flow, Navi Live will automatically continue with APK installation after the required Android permission screen returns.
- The updater now prefers GitHub release assets named `navi-live.apk`, then falls back to older APK names when needed.
- The repository release flow is automated by `..\scripts\publish-github-release.ps1`, which builds `navi-live.apk`, updates or creates the GitHub release, removes old APK assets and uploads the new one.
- Android source packages and the Gradle `namespace` now use `com.navilive.android`.
- `applicationId` intentionally stays `com.navilive.app`, so current users keep the existing install, updater path and app data during upgrades.
- Preferences now migrate automatically from the legacy `navilive_preferences` DataStore file into the current `navi_live_preferences` store on first launch after upgrade.
- Settings > Backup and restore provides one local restore point and a JSON file export/import flow through the Android system document picker.
- The JSON backup format is shared with iOS (`schemaVersion` 1), so a backup can be moved between the two platforms.
- Backup files contain settings and personal navigation data only; cached nearby places, diagnostics, downloaded APKs and secrets are excluded.
- Imports validate the app name, schema version, file size and data types. A partial file changes only the fields that it contains.
