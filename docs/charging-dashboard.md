# Charging dashboard

The dashboard is enabled by default for new v1.2 installations. Existing installations retain their previous preference. Enable **Settings → Charging dashboard → Enable charging dashboard**, connect a charger, and touch the main battery display, use the outlined **Fullscreen Dashboard** button beside **Monitor Battery**, or use the Settings entry. Viewing it does not enable background monitoring or recording. The optional **Charging dashboard on lock screen** setting adds an Android system screen saver; see [setup and lifecycle details](charging-screen-saver.md).

## Presentation and security

The dashboard uses the existing Flutter engine and navigator. It waits until its opaque entrance transition finishes before enabling Android lock-screen visibility. Android API 27+ uses `Activity.setShowWhenLocked`; API 24–26 uses `FLAG_SHOW_WHEN_LOCKED`. Neither implementation dismisses keyguard or authenticates the user. Back, the close button, and the slide control clear the native flag before returning to ordinary app UI. When keyguard is up, native dismissal puts the task behind it. Disabling the setting or unplugging closes the view; native reading delivery also clears lock-screen visibility for those events. Activity destruction clears the flag, and a recreated activity starts without it.

The manual view has no automatic charger-triggered launch, overlay, full-screen intent, wake lock, or forced screen-on behavior. Normal Android screen timeout and power-button behavior apply. The separately enabled system screen saver follows Android's idle policy and requires selection in system settings. Lock-screen presentation depends on device behavior and requires physical-device verification. Session reminders/reports wait until the manual dashboard closes rather than opening dialogs above keyguard.

## Data and rendering

- Reuses `BatteryController` and `BatteryEngine`'s normal readings stream, normally sampled every three seconds. No additional sensor subscription or polling timer is created.
- Keeps signed, normalized net battery current. The existing current-unit and polarity settings apply; plugging in never forces the reading positive.
- Honors Fahrenheit, millivolts, and dual-cell adjustment. Labels the adjustment explicitly. Battery power is calculated from voltage and current and is identified as calculated, not a measured charger rating.
- Missing and nonfinite values display `—`; invalid percentage values do not become a false progress reading. Full and plugged-but-not-charging states remain viewable with no charging animation.
- One animation controller repaints only a small light trail on the outer ring; the percentage track, background image, and statistics stay on separate static layers. Animations stop while the app is inactive, when charging stops, on dismissal, or when reduced motion is enabled.
- Hidden network/current-chart subscriptions and the controller's periodic history refresh are suspended while the dashboard is open. Existing background recording and alarms retain their own behavior.
- Portrait phones use the user's `FitteryChargingDashboardGeminiEdition.jpg`, bundled unchanged as `assets/charging/cosmic_dashboard_v1.jpg`. The image and live overlays share a source coordinate system. On taller phones, only empty strips between sections expand to fill the viewport; the gauge stays circular and cards, lettering, and icons retain their proportions. The background reaches every edge. Percentage, status, clock, current, calculated power, temperature, estimated time, connection time, and elapsed duration occupy the artwork's blank areas. The estimate identifies its target percentage; unconfirmed connection times use `~`, and unavailable values use `—`.
- The bitmap's 57 dim gauge segments remain the uncharged track. Flutter illuminates measured segments using geometry matched to the artwork; a continuous small glint is clipped inside that fill rather than jumping between whole segments. The image is decoded at a width based on the physical display (640–1152 pixels) and isolated in a repaint boundary. Navigation does not wait on image decoding. There is no animated wallpaper, blur behind cards, image download, or extra sampling timer.
- Android hides both system bars with native immersive mode while the dashboard is visible. An edge swipe can reveal transient system controls. Focus regain reapplies fullscreen, and dismissal restores the previous system bar appearance and cutout handling. The close control respects the camera cutout without reserving a safe-area band across the entire background. The system screen saver hides both bars in its own window as well.
- Swipe up over the artwork's bottom dismissal area to close. The previous horizontal gesture, Android Back, close button, and accessible activation also dismiss. Short gestures do not close the view. The close button keeps its normal touch target outside the scaled artwork.
- Landscape, narrow windows, and larger accessibility fonts retain the existing reflowing layout with the earlier artwork. Landscape places the ring and cards alongside each other; large text can scroll the body while close/slide controls remain visible. Calculated power and dual-cell adjustments remain explicitly identified. The previous artwork is preserved; see [the original artwork notes](../design/charging/original-artwork-v1.md).

## Automated verification

Run `flutter analyze --no-pub`, `flutter test --no-pub`, `flutter build apk --debug --no-pub`, and Android `testDebugUnitTest lintDebug` with the configured Java runtime. Tests cover settings persistence and opt-in, connection gating, signs/units/missing values, all dismissal paths, reduced motion and lifecycle animation behavior, layout sizes, suspension of hidden telemetry, and native lock-screen flag cleanup on API 24 and 28.

## Physical-device checks

Native changes require a full app restart, not hot reload.

1. Confirm a fresh/default setting is off and the Dashboard has no dashboard entry. Enable it, restart, and confirm the saved choice remains.
2. With monitoring off, connect power and open the dashboard. Confirm monitoring remains off. Compare percentage, current, voltage, and temperature with Fittery's existing readings. Repeat with monitoring on and confirm the recording continues.
3. Test USB, AC, or wireless sources available to you. Check full and paused charging states. Negative net current must remain negative even with power connected.
4. Close using the button, Android Back, and a full slide. A short slide should return to its starting position. Reopening should work without duplicate dashboards.
5. Open the dashboard, press Power, then wake the phone. Check device-specific visibility and dismiss it. Verify the normal lock screen still requires your usual authentication; no Settings, history, or recording dialog should appear above it.
6. Let the screen time out naturally. Confirm it is not kept awake. Background and resume the app; readings should refresh and animation should pause/resume appropriately. Check rotation, large system fonts, and gesture/button navigation insets.
7. Unplug while visible and while the screen is off, then wake. The dashboard should close. Disable the feature and confirm it cannot be reopened until enabled.
8. Confirm charge and temperature alarms still fire and can be silenced with monitoring enabled. Check a completed recording/report after unplugging.
9. For performance feedback, use a profile/release build. Compare memory/frame behavior with and without the dashboard; confirm no repeating dashboard animation or extra telemetry remains after dismissal. Actual display power and OEM behavior cannot be established by widget or Robolectric tests.

## Research references

- [Android background activity launch restrictions](https://developer.android.com/guide/components/activities/background-starts): a charging event does not generally authorize a background screen launch.
- [Activity.setShowWhenLocked](https://developer.android.com/reference/android/app/Activity#setShowWhenLocked(boolean)): visibility above keyguard without requesting keyguard dismissal.
- [Android battery monitoring](https://developer.android.com/training/monitoring-device-state/battery-monitoring): battery and power broadcasts.
- [DreamService](https://developer.android.com/reference/android/service/dreams/DreamService) and [Pixel screen-saver setup](https://support.google.com/pixelphone/answer/2818748): an alternative controlled by system idle behavior, outside the selected implementation.
- [Android 14 full-screen intent restrictions](https://developer.android.com/about/versions/14/behavior-changes-14#secure-fsi): charging visuals are not a reason to repurpose calling/alarm full-screen intents.
- [Flutter CustomPainter](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html): repaint listeners can update the animation without repeating build/layout.
- [AmpereFlow's own setup documentation](https://androxus.pages.dev/ampereflow/user-guide/) describes its overlay/monitoring approach. [ChargeVibe](https://github.com/Tanjid-code/ChargeVibe) and [Dock](https://github.com/Mobinshahidi/Dock) illustrate overlay and screen-saver alternatives. No competitor design or code was copied.
