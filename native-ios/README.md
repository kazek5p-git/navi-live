# Navi Live iOS

Native iPhone/iPad client for `Navi Live`, built with:

- `SwiftUI`
- `NavigationStack`
- system `List` / `Form` / `Button` / `Toggle` / `Picker` controls
- localized `.strings` files split by feature tables
- `XcodeGen` project generation from [project.yml](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/project.yml)

## Current state

Implemented and validated on GitHub Actions:

- onboarding
- location permission gate
- home, search, place details, route summary
- favorites, settings, help/privacy
- heading alignment
- active navigation
- off-route detection
- automatic route recalculation
- arrival screen
- simulator test workflow
- unsigned IPA workflow for Sideloadly
- signed IPA workflow
- TestFlight upload workflow

## Accessibility

The iOS UI intentionally uses native controls and standard container patterns instead of custom interaction layers.
This keeps VoiceOver focus predictable and closer to the ListenSDR approach.

Current accessibility-related decisions:

- large primary actions on each screen
- minimal action count per section
- grouped status cards with combined accessibility output
- localized announcements through `UIAccessibility` / `AVSpeechSynthesizer`
- haptics gated by user settings

## Localization layout

Strings are organized by feature:

- [General.strings](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/NaviLive/Resources/en.lproj/General.strings)
- [Root.strings](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/NaviLive/Resources/en.lproj/Root.strings)
- [Home.strings](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/NaviLive/Resources/en.lproj/Home.strings)
- [Onboarding.strings](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/NaviLive/Resources/en.lproj/Onboarding.strings)
- [Navigation.strings](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/NaviLive/Resources/en.lproj/Navigation.strings)
- [Settings.strings](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/NaviLive/Resources/en.lproj/Settings.strings)

Polish mirrors the same structure under `pl.lproj`.

## Workflows

Available GitHub Actions:

- `.github/workflows/ios-simulator-tests.yml`
- `.github/workflows/ios-unsigned-ipa.yml`
- `.github/workflows/ios-signed-testflight.yml`
- `.github/workflows/sync-xcodeproj.yml`

Publishing helper:

- [Publish-NaviLive-iOS-TestFlight.ps1](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/scripts/Publish-NaviLive-iOS-TestFlight.ps1)
- [Update-NaviLive-AppStoreConnect-Metadata.py](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/scripts/Update-NaviLive-AppStoreConnect-Metadata.py)

## Sideloadly install

Local helper:

- [Install-NaviLive-Latest.ps1](/C:/Users/Kazek/Desktop/iOS/Install-NaviLive-Latest.ps1)

This script:

1. downloads the latest successful `iOS Unsigned IPA` artifact from GitHub Actions,
2. stores it under `C:\Users\Kazek\Desktop\iOS\NaviLive\Builds\Unsigned\latest`,
3. passes it to the existing Sideloadly bridge.

## TestFlight readiness

The signed/TestFlight workflow is already configured and has been validated successfully.
Metadata and review material are stored in:

- [native-ios/AppStoreConnect/README.md](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/README.md)
- [TestFlight-beta-description.txt](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/TestFlight-beta-description.txt)
- [TestFlight-what-to-test.txt](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/TestFlight-what-to-test.txt)
- [Beta-License-Agreement.txt](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/Beta-License-Agreement.txt)
- [TestFlight-review-notes.txt](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/TestFlight-review-notes.txt)
- [TestFlight-review-notes-strict.txt](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/TestFlight-review-notes-strict.txt)
- [App-Privacy-draft.md](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/App-Privacy-draft.md)
- [Privacy-Policy-Text.md](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/Privacy-Policy-Text.md)
- [Custom-License-Agreement-Draft.txt](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/Custom-License-Agreement-Draft.txt)
- [AppStoreConnect-UI-Copy-Pack.md](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/AppStoreConnect-UI-Copy-Pack.md)
- [TestFlight-UI-Checklist.md](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/TestFlight-UI-Checklist.md)
- [Release-checklist.md](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/Release-checklist.md)

The workflow also overrides `CURRENT_PROJECT_VERSION` with the GitHub Actions run number so repeated TestFlight uploads do not reuse the same build number.

Minimum required secrets for automatic signing/upload:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_API_KEY_BASE64`
- `APPLE_TEAM_ID`
- `KEYCHAIN_PASSWORD`

Optional manual-signing secrets:

- `IOS_DIST_CERT_P12_BASE64`
- `IOS_DIST_CERT_PASSWORD`
- `IOS_PROVISION_PROFILE_BASE64`

Helper script for populating them:

- [Set-NaviLive-TestFlight-Secrets.ps1](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/scripts/Set-NaviLive-TestFlight-Secrets.ps1)

Recommended local env vars, matching the ListenSDR/TestFlight tooling:

- `EXPO_ASC_API_KEY_PATH`
- `EXPO_ASC_KEY_ID`
- `EXPO_ASC_ISSUER_ID`
- `EXPO_APPLE_TEAM_ID`

Recommended publish command:

```powershell
.\scripts\Publish-NaviLive-iOS-TestFlight.ps1
```

Optional explicit build number:

```powershell
.\scripts\Publish-NaviLive-iOS-TestFlight.ps1 -BuildNumber 1
```

Metadata sync after the upload:

```powershell
python .\scripts\Update-NaviLive-AppStoreConnect-Metadata.py --marketing-version 1.0 --build-number 1
```

## Bundle and scheme

- bundle id: `com.kazek.navilive`
- scheme: `NaviLive`
- project: `native-ios/NaviLive.xcodeproj`
