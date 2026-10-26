# Fittery

A private Android battery monitor built with Flutter and a direct Kotlin bridge. The app has three tabs: Dashboard, History, and Settings. No ads, accounts, remote services, or third-party runtime packages.

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

For most current phones, install `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. The optimized release build is the appropriate version for startup and battery-use feedback. Local release builds currently use the development signing key; publishing requires a production signing configuration.

Native unit tests use Android Studio's Java runtime (the system Java version may be incompatible with the Android Gradle plugin):

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
cd android
.\gradlew.bat testDebugUnitTest
```

## Architecture

- `lib/src/app.dart`: responsive dark interface, selectable telemetry plots, settings and history confirmation.
- `lib/src/controller.dart`: observable UI state and MethodChannel/EventChannel bridge.
- `lib/src/about_section.dart`: FAQ, developer credits, installed-version metadata, local privacy policy, and raw-reading diagnostics.
- `android/app/src/main/kotlin/com/fittery/tid52/`: direct BatteryManager telemetry, dynamic battery/power receiver, foreground service, SQLite history, SharedPreferences settings, and native alarms.
- Kotlin tests under `android/app/src/test` cover normalization, alert rules, health estimates, charge ETA, and SQLite persistence/migration. Robolectric is a test-only dependency and is not included in the app.

The initial screen waits only for a native sticky battery snapshot. Database access and sysfs probes run on a serial worker. While open, current is refreshed every 3 seconds; background monitoring samples every 30 seconds and also responds to battery broadcasts. Android may defer timer work while the device sleeps; there are no wake locks or artificial splash delays.

Dashboard has optional Download and Upload cards, disabled by default. Native `TrafficStats` counter differences use actual monotonic elapsed time and an activity-owned one-second Handler tick. The tick and connectivity observer stop when Dashboard is hidden, a Telemetry graph is opened, the app pauses, or the option is disabled. Network events redraw only the network panels; battery sampling/history keep their original cadence. Network monitoring never starts a service, records traffic history, scans Wi-Fi, or performs an internet speed test. Aggregate readings include other applications and local traffic; the displayed connection is the default network, not an attribution of all bytes to that transport. Counter resets and connection changes start a fresh baseline.

Miscellaneous holds connection type, Android internet validation, metered status, available Wi-Fi name/band/frequency/link rate, and combined traffic. Only normal `ACCESS_NETWORK_STATE` and `ACCESS_WIFI_STATE` permissions are added. Restricted Wi-Fi names show a fallback without location or nearby-device prompts. Device information is read on demand on the native worker and cached until pull-to-refresh: Android/security patch, reported SoC (Android 12+), architectures, app-available CPU cores, usable/advertised RAM (advertised on Android 14+), app data-partition storage, display mode, and basic identity. Unsupported values remain unavailable. CPU frequencies and camera probing are intentionally omitted.

History records only observed battery intervals. Recording gaps create separate sessions, and charts do not connect across them or unsupported metric values. Empty days have no artificial bars; an unrecorded period has no claimed totals. At most 10 sessions are retained, including any active session. Sessions expire 72 hours after their start, and their points and per-session daily contributions are deleted together. Cleanup runs during history reads and recording, with no background cleanup timer. The History screen covers the last 3 days, including partial calendar days. Schema version 3 rebuilds legacy daily totals once from retained observations so deleted sessions cannot leave phantom totals. Detailed graphs still load only the most recent hour. History and Telemetry refresh every 5 seconds while visible; refresh timers stop when the app is backgrounded. Network readings are never stored.

Tap Voltage, Current, Wattage, or Temperature to open Telemetry. Select any combination of metrics; each uses its own vertical scale and the same recorded timestamps. Voltage/current/counter history begins with schema version 2; older records retain null fields rather than invented historical values. New session power averages are weighted by observed time; older sample averages are labeled accordingly.

## Hardware limitations

- Auto current normalization starts with Android's documented signed µA convention. Unit and polarity calibration can use sustained, consistent charge-counter progress; a single sample's magnitude or a gauge reset never changes its units. Explicit µA/mA and polarity overrides are available. Negative current can reflect net discharge while plugged in. Raw current, conversion divisor, polarity, and calibration state are visible in Diagnostics. This supersedes the original magnitude heuristic, which could cause 1,000-fold spikes below 50,000 µA.
- Wattage is net power at the battery, rather than charger input power. Dual-cell mode doubles voltage and power without doubling current or capacity.
- Health includes Android's status plus a labeled approximate percentage. It prefers full/design capacity, then a measured charging-session estimate. If those are unavailable, state of charge at least 20% and a valid charge counter can produce a rough gauge-based full-capacity estimate (`remaining mAh / level × 100`), compared with design capacity. Inconsistent or missing inputs produce no percentage; it is not an independent battery-health measurement.
- Cycle count uses Android 14's public extra or readable battery/gauge sysfs nodes. Full/design capacity use readable controller nodes without root. When design capacity is unavailable there, the app reads the manufacturer's Android power-profile resource, with a guarded platform-profile fallback. The capacity source is labeled; unsupported fields remain unavailable.
- If charge counter data supports it, at least a 20 percentage-point charging span produces a labeled full-capacity estimate. It is an estimate, rather than laboratory battery-health measurement.
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

1. Open Dashboard and send a screenshot, including Network activity and Miscellaneous. Enable network activity, use another app briefly, then return to check fresh readings and connection information.
2. Plug in, then unplug; confirm state and current/power polarity change.
3. Enable monitoring, close the app for a few minutes, then inspect the notification and History.
4. Preview the alarm and test a charging threshold close to the current level.
5. Try the unit, theme, and dual-cell controls; verify settings persist after reopening.

The preview button toggles play/stop using native playback events. Its icon resets when the sound finishes, the 3-second preview timeout is reached, or the app is backgrounded. Preview and threshold-alarm playback use separate players, so a preview timeout cannot silence a real alert.

Android references: [BatteryManager](https://developer.android.com/reference/android/os/BatteryManager), [foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types#special-use), [device power profile](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/com/android/internal/os/PowerProfile.java), [Linux power-supply units](https://www.kernel.org/doc/html/latest/power/power_supply_class.html).

## License

Fittery is licensed under the [GNU General Public License v3.0](LICENSE).
