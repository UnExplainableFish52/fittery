# Welcome tutorial and local alarm audio

## Architecture

Fittery remains the existing Flutter app with its Kotlin battery engine and Android foreground service. Onboarding reuses the app's color scheme, typeface and Material controls, with native gradients and four decorative transparent illustrations. The dashboard, recording databases, charge calculations and monitoring service are unchanged by this integration.

`main.dart` already waits for the immediate native snapshot before the first Flutter frame. The snapshot now includes the onboarding preferences. `FitteryApp` makes one launch decision after the controller is ready: show the welcome tutorial if completion is false or automatic display is enabled; otherwise show the existing dashboard. A neutral loading surface covers any pending preference read. Finishing the tutorial changes the current route only after a successful save. Changing the preference during replay applies to future launches, without interrupting the current destination.

`OnboardingPreferences` uses the app's existing Android SharedPreferences mechanism in a separate `onboarding` store. `onboardingCompleted` defaults to false and `showOnboardingOnLaunch` defaults to true. Both are committed together on the battery engine's worker before completion is acknowledged. Tutorial completion never replaces alarm settings or touches battery history. Skip moves to the final setup page; it does not mark the tutorial complete. The final checkbox is checked initially, and saving it unchecked enables future automatic display.

Settings > View Welcome Tutorial pushes the same component from slide one, without forced reading intervals. Closing replay leaves preferences untouched; finishing returns to Settings. System back and the back control visit the previous slide; back at the first replay slide closes the tutorial.

On a launch tutorial, each new slide has a three-second nonblocking timer. Timers are local to the active slide, pause outside the resumed lifecycle, and are canceled on disposal. Returning to a previously visited slide does not wait again. Flutter restoration stores the current slide, viewed-slide mask, remaining intervals, and checkbox state for activity/process restoration. Rebuilds do not restart timers. Accessible navigation bypasses the interval, and a visible Skip path always reaches final setup immediately. Reduced-motion settings remove the short entry transition.

Existing plug-in and report prompts wait until the tutorial closes. No notification permission is requested on the welcome screen. The revised flow uses short feature labels for implemented functionality, including custom audio, and a prominent Free. Forever. / Open source. message. Introductory paragraphs, feature descriptions, and the sensor note were removed from onboarding. Detailed operating guidance remains in the existing settings and help screens. Background alarms still require the existing monitor service and notification permission.

## Local audio

Settings > Alarm tone now offers System alarm tones or Audio file. The latter uses Android's local, openable `audio/*` document picker with read access only. A worker validates playability and retains the selected document grant before saving its name and URI. Canceling or rejecting a file retains the previous choice. Switching away releases the previous custom-file grant. The existing Ringtone playback paths provide a three-second preview and whole-track looping for alarms. Missing files produce an actionable preview error and use the default system alarm for real alerts. No broad audio-library permission or new runtime dependency is added.

## File inventory for these two requests

Created application files:

- `lib/src/onboarding.dart`
- `android/app/src/main/kotlin/com/fittery/tid52/AlarmAudioFile.kt`
- `android/app/src/main/kotlin/com/fittery/tid52/OnboardingPreferences.kt`

Modified application/configuration files:

- `lib/src/app.dart`
- `lib/src/controller.dart`
- `android/app/src/main/kotlin/com/fittery/tid52/MainActivity.kt`
- `android/app/src/main/kotlin/com/fittery/tid52/BatteryEngine.kt`
- `android/app/src/main/kotlin/com/fittery/tid52/Alerts.kt`
- `pubspec.yaml`
- `README.md`

Created tests:

- `test/alarm_tone_choice_test.dart`
- `test/onboarding_test.dart`
- `android/app/src/test/kotlin/com/fittery/tid52/AlarmAudioFileTest.kt`
- `android/app/src/test/kotlin/com/fittery/tid52/OnboardingPreferencesTest.kt`

Modified tests/fixtures:

- `android/app/src/test/kotlin/com/fittery/tid52/AlertsTest.kt`
- `test/widget_test.dart`
- `test/network_test.dart`
- `test/charging_prompts_test.dart`
- `test/preview_and_graph_test.dart`
- `integration_test/current_chart_test.dart`

Created art, tooling and documentation:

- `assets/onboarding/welcome.webp`
- `assets/onboarding/features.webp`
- `assets/onboarding/forever.webp`
- `assets/onboarding/setup.webp`
- `design/onboarding/source/welcome.png`
- `design/onboarding/source/features.png`
- `design/onboarding/source/forever.png`
- `design/onboarding/source/setup.png`
- `design/onboarding/README.md` (prompts, sources, optimization recipe and sizes)
- `tools/optimize_onboarding_art.py`
- `docs/onboarding-implementation.md`

## Device acceptance checks

1. Launch an installation that has not completed the welcome tutorial. Confirm there is no dashboard flash, all illustrations appear, each first slide has a short countdown, and Skip is available.
2. Navigate forward and back. Rotate during a countdown, then background and resume the app. Check that the timer resumes instead of resetting, visited slides do not require another wait, and all content remains scrollable with large system text.
3. Finish with Don't show this again checked. Relaunch and confirm Dashboard opens directly. Reopen Settings > View Welcome Tutorial; there should be no waiting. Finish with the checkbox unchecked and confirm the tutorial returns on a subsequent app launch.
4. Continue an existing monitor recording through the tutorial and verify that history and alarms remain intact. A charger prompt or report notification should still be usable after leaving the tutorial.
5. Choose a real local song under Alarm tone > Audio file. Check the displayed filename, three-second preview, and a real threshold alarm. Restart the app and check the same file still plays. Move/delete the original and confirm a useful preview error and default-alarm fallback. Test system tones and Silent as well.

Automated tests use simulated audio players; real speaker output, device-specific document providers, cold process death, and physical Android display performance still require on-device confirmation. No physical device UI checks are claimed by this document.

## Verification performed

- `flutter analyze --no-pub`: passed, no issues.
- `flutter test --no-pub --reporter expanded --concurrency=1`: all **71 tests passed**. Coverage includes launch routing, saved preferences, replay and cancel, system back, skip, countdown lifecycle and rebuild behavior, Flutter restoration, failed-save recovery, accessible navigation, reduced motion, light/dark themes, portrait and landscape, large text, local-audio choices/errors, and existing dashboard, graph, history and notification flows.
- Android `testDebugUnitTest` and `lintDebug` with `compileFlutterBuildDebug` excluded: passed; **94 Android tests**, zero failures or errors. File-provider grants and audio players are simulated for the local-audio tests.
- `flutter build apk --debug --no-pub`: passed. Artifact: `build/app/outputs/flutter-apk/app-debug.apk`.
- `python tools/optimize_onboarding_art.py`: passed, verified transparent 640 x 640 WebP output for all four illustrations, 274,888 bytes combined.
- `git diff --check` on modified tracked files: passed.

The connected phone was no longer available when installation was checked. The completed build has therefore not been installed or visually/speaker-tested on that phone in this task. Reconnect it for a data-preserving update, or run the app locally and use the acceptance checks above.

## Illustration-focused revision

`lib/src/onboarding.dart` now gives the hero art substantially more space, centers the headings, colors important words, and replaces prose with concise keyword badges. The feature cards use icons and labels only. The existing navigation, Skip, buttons, countdowns, lifecycle handling, restoration and preferences are preserved.

Four new coordinated portrait illustrations replace the runtime artwork. Their source files live in `design/onboarding/source/v2/`; the original sources are preserved. Runtime transparent WebP images are 819 x 1024, quality 82, 856,428 bytes combined. `tools/optimize_onboarding_art.py` now selects the current source revision and supports the larger hero display. See `design/onboarding/v2-prompts.md` for the exact prompt set.

Verification for this visual revision: all 11 onboarding tests passed, including large text, portrait/landscape, light/dark themes, navigation, saved preferences, timer lifecycle and restoration. Flutter analysis passed with no issues. Artwork conversion verified dimensions and transparency. Native monitoring and audio code were not changed by this revision.
