# Navi Live TestFlight UI Checklist

Use this after a successful upload finishes in GitHub Actions and the build starts processing in App Store Connect.

## Processing

1. Open the latest successful signed workflow run.
2. Confirm the upload run is green.
3. Open App Store Connect and wait until the new build finishes processing.

## TestFlight Information

1. Open `Apps -> Navi Live -> TestFlight`.
2. Paste `Beta App Description` from [AppStoreConnect-UI-Copy-Pack.md](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/AppStoreConnect-UI-Copy-Pack.md).
3. Paste `What to Test` from [AppStoreConnect-UI-Copy-Pack.md](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/AppStoreConnect-UI-Copy-Pack.md).
4. Fill `Feedback Email` with a real monitored address.
5. Fill `Marketing URL` if it is empty.
6. Save changes.

## Beta App Review Information

1. Fill contact first name.
2. Fill contact last name.
3. Fill contact email.
4. Fill contact phone number.
5. Confirm login is not required.
6. Paste `Beta App Review Notes` from [AppStoreConnect-UI-Copy-Pack.md](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/AppStoreConnect-UI-Copy-Pack.md).
7. Save changes.

## Build Assignment

1. Create or open the tester group.
2. Add the newest processed build to the group.
3. For external testing, submit the build for TestFlight review if required.
4. After approval, enable distribution to the selected group.

## App Information

1. Open `App Information`.
2. Confirm `Name` is `Navi Live`.
3. Confirm categories match the chosen setup.
4. Re-check the age rating questionnaire.
5. Re-check export compliance answers if Apple asks again.

## Privacy

1. Confirm the privacy answers in [App-Privacy-draft.md](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/App-Privacy-draft.md) still match the current app behavior.
2. Publish a stable public privacy policy page before App Store release.
3. Use the text from [Privacy-Policy-Text.md](/C:/Users/Kazek/Desktop/Tymczasowe/navilive/native-ios/AppStoreConnect/Privacy-Policy-Text.md) as the source.

## After Distribution

1. Install the distributed TestFlight build on at least one real device.
2. Confirm onboarding, permissions, search, route summary, active navigation, and settings.
3. Confirm the build visible to testers matches the expected version and build number.
