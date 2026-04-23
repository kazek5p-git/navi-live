# Navi Live iOS Release Checklist

## Before upload

1. Confirm the latest iOS code is pushed to `main`.
2. Confirm `native-ios` builds cleanly in CI.
3. Confirm the signed workflow secrets are still present in GitHub.
4. Review `TestFlight-beta-description.txt` and `TestFlight-what-to-test.txt`.
5. Review `Beta-License-Agreement.txt`.
6. Review `TestFlight-review-notes.txt` and `TestFlight-review-notes-strict.txt`.
7. Re-check `App-Privacy-draft.md` against the current app behavior.

## Standard prep

1. Update `C:\Users\Kazek\Desktop\iOS\NaviLive\Scripts\TestFlight\what-to-test.pl.txt` and `what-to-test.en-US.txt`.
2. Sync the same text into `native-ios/AppStoreConnect/TestFlight-what-to-test.txt`.
3. Confirm `native-ios/project.yml` and `native-ios/NaviLive.xcodeproj/project.pbxproj` use the same `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
4. Run a clean iOS build on the Mac before any upload.
5. Do not start the upload unless it was explicitly requested.
6. When prep is complete and upload was requested, launch `C:\Users\Kazek\Desktop\skrypty_ios\NaviLive TestFlight GUI.lnk` as the final step.

## Workflow

1. Prepare metadata, `What to Test`, and version/build consistency first.
2. Launch `C:\Users\Kazek\Desktop\skrypty_ios\NaviLive TestFlight GUI.lnk`.
3. If the upload succeeds, confirm the run URL and artifact path.

## After upload

1. Open App Store Connect.
2. Verify the new build appears in TestFlight processing.
3. Paste the current tester notes from `TestFlight-what-to-test.txt`.
4. Paste review notes if App Review requests extra information.
5. Confirm the `Beta License Agreement` still matches the current beta scope and privacy link.
6. Confirm external tester groups before distributing the build.
