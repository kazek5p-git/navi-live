# Navi Live

`Navi Live` is an accessibility-first walking navigation project focused on blind and low-vision users.

Project structure:

- `android/` - Android application source
- `native-ios/` - native iOS application source, App Store Connect material, and iOS publishing docs
- `shared/` - shared product rules used to generate platform-specific constants for Android and iOS
- `NAVILIVE_SPEC.md` - product and architecture specification
- `NAVILIVE_UX_BLUEPRINT.md` - UX blueprint reconstructed from archived ViaOpta materials
- `NAVILIVE_ANDROID_BACKLOG.md` - current Android implementation backlog
- `screens/` - supporting reference images and archived screen material

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
