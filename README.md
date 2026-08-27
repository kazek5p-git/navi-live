# Navi Live

`Navi Live` is an accessibility-first walking navigation project focused on blind and low-vision users.

Project structure:

- `android/` - Android application source
- `native-ios/` - native iOS application source, App Store Connect material, and iOS publishing docs
- `shared/` - shared product rules used to generate platform-specific constants for Android and iOS
  - `shared/test-fixtures/` also holds parity fixtures consumed by Android and iOS tests
- `NAVILIVE_SPEC.md` - product and architecture specification
- `NAVILIVE_UX_BLUEPRINT.md` - UX blueprint reconstructed from archived ViaOpta materials
- `NAVILIVE_ANDROID_BACKLOG.md` - current Android implementation backlog
- `screens/` - supporting reference images and archived screen material
- `docs/lokalizacja-radiowa-android.md` - opis pomocniczego skanowania Wi-Fi/BLE na Androidzie

Quick start:

```powershell
cd android
.\gradlew.bat assembleDebug
```

APK output:

`android\app\build\outputs\apk\debug\app-debug.apk`

Staged release asset:

`android\app\build\release-asset\navi-live.apk`

GitHub release publish:

```powershell
.\scripts\publish-github-release.ps1
```

iOS TestFlight publish:

```powershell
.\scripts\Publish-NaviLive-iOS-TestFlight.ps1
```

Technical note:

- Android namespace and source packages now use `com.navilive.android`.
- `applicationId` intentionally remains `com.navilive.app` so existing installs continue to receive in-place updates.
- Shared product tuning now starts in `shared/product-rules.json` and is generated into native Android/iOS code.
- Shared parity fixtures now live in `shared/test-fixtures/navigation-parity-fixtures.json` and are exercised by both Android and iOS unit tests.
- Shared cross-platform parity now also covers navigation scenario decisions such as countdown milestones, immediate turn timing, step advance, off-route detection, and auto-recalculation cooldown behavior.
- Walking guidance now uses a small lead distance before maneuvers, a less aggressive off-route threshold, and faster Android location updates to reduce late turn announcements.
- Pedestrian crossing alerts are filtered more strictly so side crossings and nearby cycle-path crossings are less likely to replace actual turn instructions.
- Active navigation on Android exposes the route step list so screen reader users can review current and upcoming instructions during guidance.
- Shake-to-repeat now requires a stronger motion spike and a longer cooldown to reduce accidental repeats from a phone carried in a pocket.
