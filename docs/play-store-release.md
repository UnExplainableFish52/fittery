# Fittery: Google Play release

Current release prepared November 6, 2026: **1.2.0 (27)**, package **com.fittery.tid52**, matching Git tag **v1.2.0**. The owner confirmed that Play version code 27 is unused. See the [comprehensive first GitHub release notes](releases/v1.2.0.md) for features, changes, checksums, and verification results.
Support/privacy contact: **sharma@saksham.info.np**.

Current signed artifacts are `build/release-ready/1.2.0-build27/Fittery-1.2.0-build27.apk` and `Fittery-1.2.0-build27.aab` in the same directory. The [1.1.1 build verification](releases/1.1.1-build26.md), [1.1.0 build verification](releases/1.1.0-build25.md), [1.0.0 build verification](releases/1.0.0-build16.md), and [0.8.0 release verification](release-verification.md) remain historical records. The local 0.9.0 candidate was superseded before upload.

## Release sequence

1. Finish the local checks and phone verification below.
2. Back up the upload key and its passwords, then upload the signed AAB to **Internal testing**. Enable Play App Signing with a Google-generated app signing key. Verify installation, notifications, and updates from Play.
3. Complete app setup, publish the final public privacy policy, add the store assets, and complete the content/permission declarations.
4. Release to **Closed testing**. This personal account was created after November 13, 2023, so at least **12 testers must remain opted in continuously for the preceding 14 days** when applying for production access. Recruit a few additional testers to allow for opt-outs. Internal testing does not satisfy this requirement.
5. Collect actual use and feedback, fix issues with increasing version codes, and review the Play pre-launch report. Keep a dated record of devices, scenarios, issues, and fixes.
6. Apply for production access with an honest account of the closed test and resulting changes. Google reviews this application; completing the minimum test does not itself grant production access.
7. After approval and successful final checks, submit the production release for review.

Testers on the internal track must opt out before joining the closed track. Choose the closed-test country availability before inviting testers and send the opt-in URL; unpublished test apps are not discoverable through normal Play search.

Sources: [personal-account testing](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en), [test tracks](https://support.google.com/googleplay/android-developer/answer/9845334?hl=en).

## Signing and build

Release builds use `android/key.properties` and a private upload keystore. They never fall back to the debug key. `android/key.properties.example` documents the configuration; relative keystore paths are resolved from `android/`. Both real credential files are ignored by Git.

The first local upload key was generated at `android/upload-keystore.jks`, alias `upload`. Its randomly generated store/key password is stored only in `android/key.properties`. Keep **both files** in a secure backup outside the checkout before uploading. Do not paste passwords into issues, chat, or repository files. Google Play's app signing key and this upload key serve different purposes.

For a fresh checkout, restore the private signing files from the backup. If setting up a genuinely new app rather than restoring this package, Flutter documents [creating an upload key](https://docs.flutter.dev/deployment/android#sign-the-app).

From the project root:

```powershell
flutter analyze --no-pub
flutter test --no-pub --reporter expanded --concurrency=1
flutter build appbundle --release
python tools/verify_android_bundle.py build/app/outputs/bundle/release/app-release.aab
```

Upload `build/app/outputs/bundle/release/app-release.aab`. Increase the build number in `pubspec.yaml` for each new Play upload. Keep the package ID stable. API 36 is pinned as the tested target, meeting the [current target API requirement](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en).

Native checks, after Flutter has generated the build configuration:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
Push-Location android
try {
    .\gradlew.bat testDebugUnitTest --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Native tests failed.' }
    .\gradlew.bat :app:lintRelease --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Release lint failed.' }
} finally {
    Pop-Location
}
```

Run Flutter builds and native checks sequentially: both use generated Android build files. Generate a normal release with `flutter build appbundle` before running release lint directly. Keep the default pub step for release builds: Flutter 3.41 can otherwise retain `integration_test` in the generated registrant even though release builds exclude that development plugin. This is a [documented Flutter tooling issue](https://github.com/flutter/flutter/issues/169336). Do not manually edit `GeneratedPluginRegistrant.java`.

`android/app/lint.xml` limits the PropertyEscape exception to Flutter's generated `android/local.properties`: Flutter regenerates Windows paths with valid escaped backslashes and an unescaped drive colon on each build. The check remains enabled for app-owned property files. No lint baseline or general error suppression is used.

The upload-signed APK and Play-signed installation cannot replace the current debug-signed phone installation in place. Android requires matching signatures. Preserve any wanted local history/settings before choosing to uninstall a conflicting installation; uninstalling deletes private app data. No automatic phone uninstall is part of these checks.

## Console setup and declarations

| Item | Fittery-specific preparation |
| --- | --- |
| App identity | Fittery; Android application; suggested category Tools; support email above. Confirm the final public developer identity in Console. |
| App access | No account or login; reviewers can use the app without credentials. |
| Ads | No ads. |
| Privacy policy | Use `https://saksham.info.np/fittery-privacy.html`. The page was reachable, but its current text still describes release behavior as unverified. Replace it with the prepared `docs/fittery-privacy.html` or equivalent final content before closed testing. |
| Data safety | The audited release processes readings locally and has no Internet permission, analytics, advertising, or tracking SDK. The expected response is no collection/sharing by the app. Review the form against the exact uploaded bundle and all active versions; external browser and voluntary email interactions are described separately in the policy. |
| Foreground service | Declare `specialUse` for user-enabled battery recording and threshold alerts. A clear description and demonstration video are needed; draft below. Approval is subject to Google's review. |
| Health apps | Battery health refers to the phone battery, not human health. Complete the declaration indicating no human-health features. |
| Other app-content forms | Complete the content-rating questionnaire, target-audience selection, financial-features declaration and any other forms Console presents, using the actual app behavior. Do not guess a target audience on the user's behalf. |
| Assets | Store-specific 32-bit 512 × 512 icon and opaque 24-bit 1024 × 500 feature graphic are prepared in `store-assets/`, with editable SVG and alternative text. Artwork approval and actual phone screenshots remain. Store copy is drafted in `play-store-listing.md`. |
| Native compatibility | Verify the release bundle's native libraries and 16 KB page alignment; Flutter includes native code. Record the artifact inspection result and review any Console compatibility warnings. |
| Pre-launch report | Inspect Stability, Performance, Accessibility, and Screenshots. Investigate crashes, ANRs, clipped UI, or unreadable controls before production. |

Sources: [user data and privacy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en), [foreground-service declaration](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en), [health declaration](https://support.google.com/googleplay/android-developer/answer/14738291?hl=en), [pre-launch report](https://support.google.com/googleplay/android-developer/answer/9842757?hl=en), [16 KB compatibility](https://developer.android.com/guide/practices/page-sizes).

## Foreground-service declaration draft

**Feature:** The user explicitly enables Background monitoring to keep recording battery measurements and to receive charging-target, low-battery and temperature alerts while Fittery is closed. A persistent battery-monitoring notification shows the service is running. The user can stop it in the app or through the notification. There is no automatic boot startup.

**Why immediate and continuous:** Delaying or interrupting the service can miss a charging threshold or temperature warning and create gaps in the battery history the user asked to record. This is continuous battery monitoring, rather than a deferrable upload or network synchronization. The service targets samples every 3 seconds in the background and responds to Android battery broadcasts. It takes no wake lock; device power restrictions can still defer work.

**Demonstration video:** Open Dashboard, enable monitoring, allow notifications if prompted, leave the app, show the ongoing notification, demonstrate a charging-target alert with an appropriate reachable target, use Silence, then stop monitoring through the notification. Use a real phone and provide a reviewer-accessible video URL. Do not submit a video that promises a hardware charging cutoff.

## Phone verification still required

Use the Play-installed release for final acceptance. A local `flutter run --profile` is useful for early performance feedback on the existing debug signing identity. Debug-mode responsiveness is not a release performance measurement.

| Scenario | Expected result / evidence |
| --- | --- |
| Cold start and navigation | Dashboard appears promptly with actual readings; tabs, scrolling, opening graphs and range changes stay responsive. Record phone model/Android version and any repeatable delay. |
| Visual consistency | Screenshots of Dashboard, History, Settings and Current graph in the preferred theme; also try system light mode, AMOLED mode, larger font/display size and landscape. No clipping, overlapping labels or unreachable controls. |
| Sensor transitions | Plug/unplug; state and net-current polarity update. Unavailable measurements remain unavailable. Current can be negative while plugged in if phone use exceeds incoming power. |
| Alert and permissions | Notification denial produces a useful message. Grant permission, preview a tone, trigger a reachable charge threshold, silence it, unplug/replug and check rearming. Verify silent-tone and sound-off settings. |
| Background service | Enable monitoring, leave and lock the phone for 15–30 minutes, then check notification, alert behavior and observed History. Stop via notification and verify monitoring stops. Repeat with the OEM's normal battery settings. |
| Power and memory | Compare foreground Dashboard, Current graph, background monitoring and monitoring-off behavior. Report heat, unexpected drain or sustained lag. Use profile-mode DevTools traces if feedback identifies slow frames; do not claim a battery-drain number without measurement. |
| Persistence and recovery | Change units/threshold/theme, reopen and confirm persistence. Confirm history retention, empty-state behavior, clear-history confirmation and recovery after the app is stopped. No invented records. |
| Distribution | Install from the intended Play track, confirm displayed version 1.1.1 (26), and verify the update retains preferences and history. |

Automated tests cover sensor normalization, sampling cadence, stale-response ordering, alert rules, history persistence/retention, bounded six-hour chart data, view/lifecycle cancellation, narrow screens and enlarged-text layouts. They do not establish real-device battery drain, OEM reliability, visual approval, Play policy approval, or completion of the required closed test.

## Persistent monitoring update

See [background monitoring](background-monitoring.md) for consent, boot/update recovery, temperature snooze, updated demonstration steps, and device acceptance checks. Update the existing foreground-service declaration and video to reflect these behaviors before release.


## v1.2.0+27 submission

Code 27 was confirmed unused by the owner. Local cosmic-build27/build28 folders are previous local artifacts and must not be overwritten or treated as proof of a Play upload.

Update the specialUse declaration to describe user-started battery recording and independent broadcast-driven threshold alerts. Provide a video link demonstrating: Settings introduction; Enable Background Alerts; thresholds and selected sounds; Monitor Mode OFF; leaving the UI and receiving an alarm; explicit stop; Monitor Mode ON with both controls independent. Explain that delayed or interrupted work can miss timely charging/temperature reminders. Google reviews specialUse eligibility; do not describe approval as guaranteed.

Run Flutter analysis/tests, native tests, release lint, release APK/AAB builds and tools/verify_android_bundle.py. Physical-device approval remains necessary for power use, reboot recovery and manufacturer behavior. Uploading to Play and recording/uploading the demonstration video remain owner actions.
