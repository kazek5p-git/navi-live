# Navi Live App Privacy Draft

This file is a working draft for the `App Privacy` section in App Store Connect.
It is not legal advice. Review it before submission.

## Current app behavior

- The app requests device location for place search, route generation, and live navigation.
- The app sends search, reverse geocoding, and routing requests to public OpenStreetMap-based services.
- Favorites, settings, tutorial state, and the last route are stored locally on the device.
- The current iOS app does not implement user accounts, analytics SDKs, ad SDKs, crash reporting SDKs, or in-app purchases.

## Draft answers to verify

### Data linked to the user

- None intentionally linked to a user account, because the app currently has no account system.

### Data collected by the developer

- Needs final verification.
- The app itself does not send data to a developer-owned backend.
- However, location and search/routing requests are sent from the device to third-party public services used for core functionality.
- Before App Store submission, decide whether Apple should treat these requests as third-party data collection that must be disclosed.

### Tracking

- No ad tracking is implemented.
- No cross-app tracking framework is used.

## Submission reminder

Before each App Store or TestFlight submission, re-check:

1. Current geocoding/routing providers.
2. Whether any telemetry, analytics, or crash reporting was added.
3. Whether privacy policy text in the app still matches real behavior.
