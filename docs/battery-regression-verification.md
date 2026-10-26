# Battery reading regression verification

Verified fix: Fittery 0.4.1+9, ARM64 Android versionCode 2009,
package `com.fittery.tid52`.

## Device evidence collected on 2026-10-26

The connected Android 15 phone reported 86%, charging, AC power in
`dumpsys battery`. The previous candidate (build 2008) initially logged 56%,
Discharging, unplugged, while its independent capacity property was 86%.

Broadcast history for that startup showed multiple initial sticky battery
deliveries: old snapshots addressed to another package and a current global
snapshot (sequence 11814, level 86, charging, AC power). The old guard could
accept the stale registration return and then reject the current initial
callback as a duplicate.

When a later live broadcast arrived, build 2008 accepted 86% Charging.
Repeated refresh logs then showed cachedLevel=86 while queriedLevel=56;
the refresh guard correctly retained the live reading. Startup acceptance
needed the additional fix.

## Current change and automated evidence

- Ignore battery intents addressed to another package, including query seeds.
- Receiver registration returns can only seed an empty snapshot.
- Compare Android's optional battery broadcast sequence to accept newer
  callbacks and reject older or duplicate updates.
- Without that metadata, permit an actual initial receiver callback to restore
  state after observation paused; a newly accepted live update cancels that
  fallback. Alarm-side initial callbacks cannot use this fallback.
- Keep the separate reading sequence guard in Flutter for delayed method replies.

Before installation, the complete Android suite passed (49 tests), the Flutter
suite passed (20 tests), static analysis reported no issues, and the ARM64
release APK built successfully. New startup, package-filtering, and missed-update
tests failed against build 2008's source before the fixes and pass now.

`adb install -r` succeeded. Package inspection confirmed version 0.4.1,
versionCode 2009, and both Fittery packages remain installed. No app data was
cleared and the old `com.fittery.fittery` fallback was not updated.

## Device confirmation

On 2026-10-26, after being asked to open build 2009 and compare the main screen
and monitoring notification against Android's battery percentage and charging
status immediately at startup, the user confirmed: "yes it matches good job".

This confirms the requested device check for the installed fix. Automated
regression coverage additionally verifies stale refresh responses, initial
callback ordering, and resuming after missed updates. The agent did not operate
the phone UI; installation and read-only diagnostics were performed through adb.
