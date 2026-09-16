# Navi Live iOS

Native iPhone/iPad client for `Navi Live`, built with:

- `SwiftUI`
- `NavigationStack`
- system `List` / `Form` / `Button` / `Toggle` / `Picker` controls
- localized `.strings` files split by feature tables
- `XcodeGen` project generation from [project.yml](/C:/Users/Kazek/Documents/navi-live/native-ios/project.yml)

## Current state

Implemented and validated on GitHub Actions:

- onboarding
- location permission gate
- home, search, place details, route summary
- favorites, settings, help/privacy
- backup and restore of settings, favorites, custom places, last route and onboarding state
- heading alignment
- active navigation
- off-route detection
- automatic route recalculation
- stricter pedestrian crossing alerts that avoid nearby side crossings when possible
- named-street crossing wording for short route steps that cross a street instead of turning into it
- less sensitive shake-to-repeat detection with a longer cooldown
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
- active navigation includes VoiceOver rotor entries for route instructions and alerts
- route guidance announcements prefer actual maneuver steps over nearby crossing alerts

## Localization layout

Strings are organized by feature:

- [General.strings](/C:/Users/Kazek/Documents/navi-live/native-ios/NaviLive/Resources/en.lproj/General.strings)
- [Root.strings](/C:/Users/Kazek/Documents/navi-live/native-ios/NaviLive/Resources/en.lproj/Root.strings)
- [Home.strings](/C:/Users/Kazek/Documents/navi-live/native-ios/NaviLive/Resources/en.lproj/Home.strings)
- [Onboarding.strings](/C:/Users/Kazek/Documents/navi-live/native-ios/NaviLive/Resources/en.lproj/Onboarding.strings)
- [Navigation.strings](/C:/Users/Kazek/Documents/navi-live/native-ios/NaviLive/Resources/en.lproj/Navigation.strings)
- [Settings.strings](/C:/Users/Kazek/Documents/navi-live/native-ios/NaviLive/Resources/en.lproj/Settings.strings)

Supported localization folders mirror the same structure for `en`, `pl`, `ru`, `uk`, `ar`, `fa`, `tr`, `de`, `fr`, `es`, `it`, `pt`, `ro`, `cs`, `sk`, `be`, `lt`, `lv`, `et`, `hu`, `fi`, `hr`, `sr`, `el`, `bn`, `hi`, `id`, `vi`, `zh-Hans`, `ja`, `ko`, and `ckb`.

Missing iOS locale tables can be generated with `python native-ios/tools/generate_translations.py`. The generator preserves `Navi Live` and formatting placeholders such as `%@`, `%d`, and `%1$@`.

Cross-platform locale coverage can be checked with `python scripts/Validate-NaviLive-Locales.py` from the repository root.

Settings > Backup and restore provides one local restore point and native iOS JSON file export/import through `fileExporter` and `fileImporter`.
The JSON backup format is shared with Android (`schemaVersion` 1), so a backup can be moved between the two platforms.
Backup files contain settings and personal navigation data only; cached nearby places, diagnostics, downloaded updates and secrets are excluded.
Imports validate the app name, schema version, file size and data types. A partial file changes only the fields that it contains.

Russian iOS localization was updated through PR #3 from `Kostenkov-2021/Ru-iOS-localization` and merged on 2026-05-29.
The PR corrected wording in `Home.strings`, `Navigation.strings`, and `Onboarding.strings`.
Before merging localization PRs, validate that every `.strings` line keeps escaped quotes inside values, for example `\"Quoted action\"`, because unescaped quotes break iOS resource parsing.

Minimal local syntax check for a locale folder:

```powershell
@'
import pathlib, re, sys
root = pathlib.Path('native-ios/NaviLive/Resources/ru.lproj')
pattern = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$')
errors = []
for path in sorted(root.glob('*.strings')):
    for lineno, line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
        stripped = line.strip()
        if stripped and not stripped.startswith('//') and not pattern.match(line):
            errors.append(f'{path}:{lineno}: {line}')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
print('OK')
'@ | python -
```

## Workflows

Available GitHub Actions:

- `.github/workflows/ios-simulator-tests.yml`
- `.github/workflows/ios-unsigned-ipa.yml`
- `.github/workflows/ios-signed-testflight.yml`
- `.github/workflows/sync-xcodeproj.yml`

Publishing helper:

- [Publish-NaviLive-iOS-TestFlight.ps1](/C:/Users/Kazek/Documents/navi-live/scripts/Publish-NaviLive-iOS-TestFlight.ps1)
- [Update-NaviLive-AppStoreConnect-Metadata.py](/C:/Users/Kazek/Documents/navi-live/scripts/Update-NaviLive-AppStoreConnect-Metadata.py)

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

- [native-ios/AppStoreConnect/README.md](/C:/Users/Kazek/Documents/navi-live/native-ios/AppStoreConnect/README.md)
- [TestFlight-beta-description.txt](/C:/Users/Kazek/Documents/navi-live/native-ios/AppStoreConnect/TestFlight-beta-description.txt)
- [TestFlight-what-to-test.txt](/C:/Users/Kazek/Documents/navi-live/native-ios/AppStoreConnect/TestFlight-what-to-test.txt)
- [Beta-License-Agreement.txt](/C:/Users/Kazek/Documents/navi-live/native-ios/AppStoreConnect/Beta-License-Agreement.txt)
- [TestFlight-review-notes.txt](/C:/Users/Kazek/Documents/navi-live/native-ios/AppStoreConnect/TestFlight-review-notes.txt)
- [TestFlight-review-notes-strict.txt](/C:/Users/Kazek/Documents/navi-live/native-ios/AppStoreConnect/TestFlight-review-notes-strict.txt)
- [App-Privacy-draft.md](/C:/Users/Kazek/Documents/navi-live/native-ios/AppStoreConnect/App-Privacy-draft.md)
- [Privacy-Policy-Text.md](/C:/Users/Kazek/Documents/navi-live/native-ios/AppStoreConnect/Privacy-Policy-Text.md)
- [Custom-License-Agreement-Draft.txt](/C:/Users/Kazek/Documents/navi-live/native-ios/AppStoreConnect/Custom-License-Agreement-Draft.txt)
- [AppStoreConnect-UI-Copy-Pack.md](/C:/Users/Kazek/Documents/navi-live/native-ios/AppStoreConnect/AppStoreConnect-UI-Copy-Pack.md)
- [TestFlight-UI-Checklist.md](/C:/Users/Kazek/Documents/navi-live/native-ios/AppStoreConnect/TestFlight-UI-Checklist.md)
- [Release-checklist.md](/C:/Users/Kazek/Documents/navi-live/native-ios/AppStoreConnect/Release-checklist.md)

The workflow uses the explicit `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` stored in [project.yml](/C:/Users/Kazek/Documents/navi-live/native-ios/project.yml), matching the `ListenSDR` release model. You can still override the build number manually for exceptional cases.

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

- [Set-NaviLive-TestFlight-Secrets.ps1](/C:/Users/Kazek/Documents/navi-live/scripts/Set-NaviLive-TestFlight-Secrets.ps1)

Recommended local env vars, matching the ListenSDR/TestFlight tooling:

- `EXPO_ASC_API_KEY_PATH`
- `EXPO_ASC_KEY_ID`
- `EXPO_ASC_ISSUER_ID`
- `EXPO_APPLE_TEAM_ID`

Recommended publish command:

```powershell
.\scripts\Publish-NaviLive-iOS-TestFlight.ps1
```

For this workspace, the preferred final upload step is the GUI launcher:

```text
C:\Users\Kazek\Desktop\skrypty_ios\NaviLive TestFlight GUI.lnk
```

The expected flow is:

1. prepare metadata and `What to Test`,
2. confirm `project.yml` and `project.pbxproj` use the same version/build,
3. run a clean iOS build check,
4. only then launch the GUI shortcut as the final upload step.

Optional explicit build number:

```powershell
.\scripts\Publish-NaviLive-iOS-TestFlight.ps1 -BuildNumber 10
```

Metadata sync after the upload:

```powershell
python .\scripts\Update-NaviLive-AppStoreConnect-Metadata.py --marketing-version 1.0.1 --build-number 10
```

## Bundle and scheme

- bundle id: `com.kazek.navilive`
- scheme: `NaviLive`
- project: `native-ios/NaviLive.xcodeproj`
