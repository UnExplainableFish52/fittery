# Fittery

A private Android battery monitor built with Flutter and a direct Kotlin bridge. The app has three tabs: Dashboard, History, and Settings. No ads, accounts, analytics, or remote services. Charts use the fl_chart package.

## Run

Requires Flutter 3.41 / Dart 3.11 or newer, an Android SDK with Java 17, and an Android 7.0+ device.

```sh
flutter pub get
flutter run --release
```

Use a real Android phone to check battery current, temperature, cycle count, alarms, and background behavior. Emulators often expose incomplete or simulated battery data. Native changes require a full restart, rather than hot reload.

```sh
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release --split-per-abi
```

The debug APK is generated at `build/app/outputs/flutter-apk/app-debug.apk`. Release builds have no Internet permission. Debug/profile manifests retain Flutter's development connection permission.

For most current phones, install `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. The optimized release build is the appropriate version for startup and battery-use feedback. Release builds require a private upload keystore configured through `android/key.properties`; they never fall back to debug signing. See [Play Store release preparation](docs/play-store-release.md) for signing, quality gates, device checks, and the testing tracks.

Native unit tests use Android Studio's Java runtime (the system Java version may be incompatible with the Android Gradle plugin):

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
cd android
.\gradlew.bat testDebugUnitTest
```

## Charging dashboard

Enable the optional charging dashboard in Settings, then touch the main battery display or use the outlined Fullscreen Dashboard button beside the thin Monitor Battery row while plugged in. It displays live readings and a neon charging ring, and closes using Back, the close button, or slide to dismiss. Device authentication stays in place and manual viewing respects normal screen timeout. The separate Charging dashboard on lock screen option registers Fittery as an Android system screen saver; select it in system settings to show it during idle charging. Activation follows Android/OEM rules. Both features are off by default, close when unplugged, and do not enable recording or request overlay access. See [dashboard details](docs/charging-dashboard.md) and [screen-saver setup and verification](docs/charging-screen-saver.md).

## App branding

`fittery_app_drawer_512.png` is the icon-only artwork used in the launcher and dashboard header. `fittery500x500_splash.png` contains the wordmark and is used for the native splash screen. Android 12+ uses a padded version to keep the full artwork inside the system's circular splash mask. Both light and dark system modes use the same dark splash background.

After replacing either original PNG, run `.\tools\generate_branding.ps1` in PowerShell on Windows to regenerate the Android launcher sizes, adaptive foreground, and splash asset. Rebuild and restart the app to see native branding changes.

## Architecture

- `lib/src/app.dart`: responsive dark interface, selectable telemetry plots, settings and history confirmation.
- `lib/src/controller.dart`: observable UI state and MethodChannel/EventChannel bridge.
- `lib/src/about_section.dart`: FAQ, developer credits, installed-version metadata, local privacy policy, and raw-reading diagnostics.
- `android/app/src/main/kotlin/com/fittery/tid52/`: direct BatteryManager telemetry, dynamic battery/power receiver, foreground service, SQLite history, SharedPreferences settings, and native alarms.
- Kotlin tests under `android/app/src/test` cover normalization, alert rules, health estimates, charge ETA, and SQLite persistence/migration. Robolectric is a test-only dependency and is not included in the app.

The initial screen waits only for a native sticky battery snapshot. Database access and sysfs probes run on a serial worker. While open, current is refreshed every 3 seconds; background monitoring targets a sample every 3 seconds and also responds to battery broadcasts. Android may defer timer work while the device sleeps; there are no wake locks or artificial splash delays.

Temperature graphs publish a new displayed snapshot once a minute, using their own element and repaint boundary. Routine history refreshes keep the page layout and existing graphs visible. Temperature-only Telemetry polls history once a minute; other selected saved metrics can still poll every five seconds. Explicit refreshes and graph range changes update immediately. Settings offers a monitor notification refresh interval of 1 second (default), 3 seconds, or 5 seconds. The service reads fresh telemetry for its notification on that cadence without changing the three-second recording cadence or the rolling discharge estimate. Charger/status/settings changes update the notification immediately.

Dashboard has optional Download and Upload cards, disabled by default. Native `TrafficStats` counter differences use actual monotonic elapsed time and an activity-owned one-second Handler tick. The tick and connectivity observer stop when Dashboard is hidden, a Telemetry graph is opened, the app pauses, or the option is disabled. Network events redraw only the network panels; battery sampling/history keep their original cadence. Network monitoring never starts a service, records traffic history, scans Wi-Fi, or performs an internet speed test. Aggregate readings include other applications and local traffic; the displayed connection is the default network, not an attribution of all bytes to that transport. Counter resets and connection changes start a fresh baseline.

Miscellaneous holds connection type, Android internet validation, metered status, available Wi-Fi name/band/frequency/link rate, and combined traffic. Only normal `ACCESS_NETWORK_STATE` and `ACCESS_WIFI_STATE` permissions are added. Restricted Wi-Fi names show a fallback without location or nearby-device prompts. Device information is read on demand on the native worker and cached until pull-to-refresh: Android/security patch, reported SoC (Android 12+), architectures, app-available CPU cores, usable/advertised RAM (advertised on Android 14+), app data-partition storage, display mode, and basic identity. Unsupported values remain unavailable. CPU frequencies and camera probing are intentionally omitted.

History lists named monitor recordings, each started by enabling monitoring and finished by stopping it. Charger changes become events and charging summaries within the same recording. Interrupted monitoring resumes the same open recording and marks a gap. Temperature, signed net power, current, voltage, battery percentage and supported charge-counter values are saved as raw measurements in `monitor.db`, independent of the legacy `battery.db` dashboard cache. Full recordings can be browsed by date, renamed, deleted and inspected across their complete time range. Graph responses preserve extrema in time buckets; range selection queries the original data at finer detail. No graph images are stored. Completed recordings expire 30 days after creation by default; active recordings are protected and Settings can disable automatic deletion. There is no recording-count cap. Cleanup runs during recording and history access. The legacy telemetry cache retains its previous 72-hour/ten-session policy and is not presented as intentional monitor recordings. Network readings are never stored.

Recording reports integrate signed current and power using observed monotonic intervals, exclude gaps over 15 seconds, clock corrections, restarts and calibration changes, and expose coverage for each metric. Charge added/used is estimated by integrating current. Time above 35 degrees C uses linear interpolation and is labeled estimated. Charging summaries under five minutes AND below five percentage points gained are hidden, while all raw measurements remain. Reaching full is a milestone; the plugged-in segment ends on disconnection or monitoring stop.

Tap Voltage, Current, Wattage, or Temperature to open Telemetry. Select any combination of metrics; each uses its own vertical scale and the same recorded timestamps. Voltage/current/counter history begins with schema version 2; older records retain null fields rather than invented historical values. New session power averages are weighted by observed time; older sample averages are labeled accordingly.

## Hardware limitations

- Auto current normalization starts with Android's documented signed µA convention. Unit and polarity calibration can use sustained, consistent charge-counter progress; a single sample's magnitude or a gauge reset never changes its units. Explicit µA/mA and polarity overrides are available. Negative current can reflect net discharge while plugged in. Raw current, conversion divisor, polarity, and calibration state are visible in Diagnostics. This supersedes the original magnitude heuristic, which could cause 1,000-fold spikes below 50,000 µA.
- Wattage is net power at the battery, rather than charger input power. Dual-cell mode doubles voltage and power without doubling current or capacity.
- Health shows Android's status and, only with matched full/design capacities from the same controller, an explicitly labeled hardware capacity estimate. It never infers health from remaining charge divided by percentage, a single partial charging session, or the old cached session estimate. Device-profile and cross-controller capacity pairs cannot establish a health ratio. Tap Health for an explanation; Diagnostics includes the controller and raw capacity pair.
- Cycle count uses Android 14's public extra or readable battery/gauge sysfs nodes. Full/design capacity use readable controller nodes without root. When design capacity is unavailable there, the app reads the manufacturer's Android power-profile resource, with a guarded platform-profile fallback. The capacity source is labeled; unsupported fields remain unavailable.
- Discharge time uses a two-minute time-weighted current window with at least 30 seconds of continuous evidence, refreshes its estimate at ten-second intervals, and smooths the predicted finish time with a 90-second time constant. Unsupported readings, source/calibration changes and observation gaps reset learning. It is an estimate at recent average use, not a promise of all-day runtime.
- Charge ETA prefers observed charge-counter or battery-level progress. After about 30 seconds of sufficiently frequent current samples, a provisional estimate can use the median recent net charging current even if the percentage is unchanged. At least 2 minutes of counter progress, or 2 percentage points of level progress, support the stronger trend estimate. Initial Android estimates are anchored to a finish time rather than displayed as an unchanging duration, and are superseded by observed rates. Non-positive net current or insufficient progress produces an explicit unavailable/slow-charging state instead of a fabricated finish time. Near-full tapering and phone use can extend any estimate.
- Alarms fire at or beyond thresholds, including skipped percentage values. The complete selected tone loops until Silence is tapped or that alert's condition resolves: unplugging for a charge-limit alert, connecting power for a low-battery alert, and cooling 2°C below the temperature limit for a thermal alert. A temporary battery receiver handles stopping an active alarm even when foreground-only recording pauses. Charge/low alerts are latched per connection session; changing a target or its enable toggle rearms that specific alert. Alerts cannot stop charging.
- Monitoring is explicitly enabled by the user and uses a visible foreground notification. No automatic boot startup is configured. Manufacturer battery restrictions can still interrupt monitoring.

## App identity and public links

The package is `com.fittery.tid52` and the app name is **Fittery**. The earlier `com.fittery.fittery` prototype has separate Android settings/history and remains a fallback while the final package is verified. The developer credits are **TheIdealDev52 / Saksham Sharma**.

The live battery broadcast is the canonical charge/status snapshot. Sticky snapshots addressed to another package are ignored, including startup query results. Refresh, settings updates, and receiver registration cannot replace an existing snapshot with a cached query result. Actual receiver callbacks use Android's optional battery update sequence to accept newer initial deliveries and reject older or duplicate deliveries. Without sequence metadata, startup callbacks can confirm the initial query, and the first valid callback after foreground-only observation resumes can restore changes missed while monitoring was off. A live update arriving first prevents that callback from replacing it. Alarm-side callbacks use the same filtering and ordering. Each reading also includes an independent monotonic sequence so an older method reply cannot supersede a newer stream event in Flutter. Diagnostics exposes the Android broadcast sequence, the broadcast source, raw level/scale, and independent capacity property for comparison.

Settings shows the actual installed version/build, with FAQ above developer details. The privacy-policy dialog includes an offline copy and an Open website button for `https://saksham.info.np/fittery-privacy.html`. The local policy source is in `docs/privacy-policy.md`. Override the public policy link at build time with `PRIVACY_POLICY_URL` if needed, and configure an optional developer website with `DEVELOPER_WEBSITE_URL`; an empty value hides the corresponding external link. Opening a configured link uses the browser and does not require Internet permission in Fittery.

Explicitly selecting a charging target re-arms that alert and evaluates the current level immediately, including when already above target or when charging is paused while power remains connected. Enable the alert switch and allow notifications; the current alarm state is shown below its description.

## Device feedback to collect

Charging targets can be typed from 50–100%, with 75/80/85% quick picks. Low-battery targets support 5–50% and 10/15/20% quick picks. Temperature targets support 35–50°C and 38/40/45°C quick picks. All three editors keep the number, preset selection, and slider synchronized. You can configure a target before enabling its alert; invalid input is not saved.

Charge alerts default to on at 80%, and temperature alerts default to on at 38°C. The optional low-battery alert defaults to off. Existing saved alert choices and targets are preserved. Allow notifications for alarms; enable background monitoring to keep alerts running while Fittery is closed.

1. Open Dashboard and send a screenshot, including Network activity and Miscellaneous. Enable network activity, use another app briefly, then return to check fresh readings and connection information.
2. Plug in, then unplug; confirm state and current/power polarity change.
3. Enable monitoring, close the app for a few minutes, then inspect the notification and History.
4. Preview the alarm and test a charging threshold close to the current level.
5. Try the unit, theme, and dual-cell controls; verify settings persist after reopening.

The preview button toggles play/stop using native playback events. Its icon resets when the sound finishes, the 3-second preview timeout is reached, or the app is backgrounded. Preview and threshold-alarm playback use separate players, so a preview timeout cannot silence a real alert.

Settings > Alarm tone offers system tones and an Audio file option for locally saved music or other supported audio. The Android document picker grants persistent read access only to the chosen file; no library-wide storage permission is requested. Files are checked for playability before the selection is saved. Preview plays three seconds; real alarms loop the complete selected track until silenced or their condition resolves. If the original file is moved, deleted, or access is revoked, preview asks the user to select it again and real alarms fall back to the default system alarm. Canceling or choosing an unsupported file keeps the previous selection.

The first launch opens a four-page welcome tutorial using the current app theme. Complete it with Don't show this again checked to open Dashboard directly next time, or uncheck it to repeat the tutorial on future launches. Settings > View Welcome Tutorial replays the same screens without reading timers. See [implementation and device checks](docs/onboarding-implementation.md) and [artwork sources and prompts](design/onboarding/README.md).

Android references: [BatteryManager](https://developer.android.com/reference/android/os/BatteryManager), [foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types#special-use), [device power profile](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/com/android/internal/os/PowerProfile.java), [Linux power-supply units](https://www.kernel.org/doc/html/latest/power/power_supply_class.html).

## License

Fittery is licensed under the [GNU General Public License v3.0](LICENSE).
