# Navi Live iOS Release Checklist

## Before upload

1. Confirm the latest iOS code is pushed to `main`.
2. Confirm `native-ios` builds cleanly in CI.
3. Confirm the signed workflow secrets are still present in GitHub.
4. Review `TestFlight-beta-description.txt` and `TestFlight-what-to-test.txt`.
5. Review `TestFlight-review-notes.txt` and `TestFlight-review-notes-strict.txt`.
6. Re-check `App-Privacy-draft.md` against the current app behavior.

## Workflow

1. Run `.\scripts\Publish-NaviLive-iOS-TestFlight.ps1`.
2. Wait for workflow `iOS Signed IPA + TestFlight`.
3. If upload succeeds, confirm the run URL and artifact path.

## After upload

1. Open App Store Connect.
2. Verify the new build appears in TestFlight processing.
3. Paste the current tester notes from `TestFlight-what-to-test.txt`.
4. Paste review notes if App Review requests extra information.
5. Confirm external tester groups before distributing the build.
