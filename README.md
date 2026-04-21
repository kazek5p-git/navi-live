# navilive

`navilive` is an accessibility-first walking navigation project focused on blind and low-vision users.

Project structure:

- `android/` - Android application source
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

`android\app\build\release-asset\navilive.apk`

GitHub release publish:

```powershell
.\scripts\publish-github-release.ps1
```
