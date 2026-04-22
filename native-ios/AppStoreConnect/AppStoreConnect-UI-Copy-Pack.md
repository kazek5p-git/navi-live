# Navi Live App Store Connect UI Copy Pack

This document is the practical `copy/paste` pack for the current `TestFlight` setup and the later `App Store Connect` configuration.

Use English as the primary text for review-facing fields unless you intentionally set a different primary localization in App Store Connect.

## 1. TestFlight

### Beta App Description

```text
Navi Live is a native iPhone app for walking navigation focused on blind and low-vision users. The interface is built with standard iOS controls, with strong focus on simplicity, stability, and VoiceOver usability.

The app lets users search for places, create walking routes, save favorite destinations, and follow turn-by-turn guidance. During active navigation it presents the current instruction, the next maneuver, distance to the next point, and off-route state. It supports spoken announcements, haptics, and route recalculation.

Settings include speech, vibration, tutorial, help, and privacy options. The app uses device location only for nearby search, route generation, and live navigation.
```

### What to Test

```text
Please test a real walking route from search to arrival. Focus on VoiceOver behavior, spoken guidance clarity, timing of haptics and announcements, off-route detection, route recalculation, and overall stability during a short real walk.
```

### Beta App Review Notes

```text
The app does not require login, a test account, payment, subscription, or in-app purchases. No additional hardware is required.

How to test:
1. Grant location access.
2. Open place search from the home screen.
3. Search for a real address or place and select a result.
4. Open the route summary.
5. Continue to heading alignment and start active navigation.
6. Verify spoken guidance, route state, distance to the next step, and behavior after going off route.

Notes for review:
- The app uses current device location for nearby search, walking route generation, and live navigation.
- The interface is built with native iOS controls. VoiceOver support is intentional.
- The app uses public OpenStreetMap-based geocoding and routing services. If one search or route temporarily fails, please try another destination.
- The app does not include in-app purchases, paid unlocks, advertising, or user registration.
```

### Feedback Email

Fill manually in App Store Connect.

Recommended rule:

- use a stable address you actively read
- keep the same address for internal and external testing

### Marketing URL

Recommended current value:

```text
https://github.com/kazek5p-git/navi-live
```

### Privacy Policy URL

Recommended current value:

```text
https://kazek5p-git.github.io/navi-live/privacy/
```

Source text for that page:

- [Privacy-Policy-Text.md](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/Privacy-Policy-Text.md)

## 2. App Information

### App Name

```text
Navi Live
```

### Subtitle

Recommended current subtitle:

```text
Accessible Walking Navigation
```

Alternative subtitle:

```text
VoiceOver-Friendly Walking GPS
```

### Categories

Recommended:

- Primary category: `Navigation`
- Secondary category: `Utilities`

### Content Rights

This is a legal confirmation, not a cosmetic field.

Recommended only if true:

- confirm that you have the rights or permissions required for all shipped assets, text, branding, and any third-party content your app accesses or displays under the applicable terms

### Age Rating Questionnaire

Recommended current answers based on the implemented iOS app:

- Violence: `None`
- Sexual content or nudity: `None`
- Mature or suggestive themes: `None`
- Medical or treatment content: `None`
- Gambling or contests: `None`
- Horror or fear themes: `None`
- Profanity or crude humor: `None`
- Alcohol, tobacco, or drug references: `None`
- User-generated content: `No`
- Messaging or chat: `No`
- Advertising: `No`
- In-app purchases: `No`
- Unrestricted web access: `No`

Expected result:

- likely `4+`

This still depends on Apple’s generated rating from the questionnaire.

## 3. Export Compliance

Current project state:

- `ITSAppUsesNonExemptEncryption` is already set to `false` in [project.yml](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/project.yml)

Operational note:

- this is appropriate only as long as the app uses exempt encryption forms, such as standard system HTTPS/TLS behavior
- if you later add custom cryptography, VPN behavior, secure tunnels outside standard exempt use, or third-party crypto libraries, review this again before the next submission

## 4. Internal Notes For This Build

Current proven workflow:

- signed IPA + TestFlight upload succeeded in run `24784327857`
- workflow URL:

```text
https://github.com/kazek5p-git/navi-live/actions/runs/24784327857
```

## 5. Apple Reference Links

These were the official references used for the current checklist:

- https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information
- https://developer.apple.com/testflight/
- https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
- https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation
- https://developer.apple.com/help/app-store-connect/reference/app-information/
- https://developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions/
