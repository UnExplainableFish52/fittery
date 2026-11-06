# Background Alerts and Monitor Mode — v1.2.0

Background Alerts is separately opt-in. It watches Android battery broadcasts for percentage, temperature, status and power connection changes, reusing existing thresholds, alarm sounds, latches and snooze behavior. Alert-only operation does not poll battery statistics, discover hardware, or record history. Broadcast delivery controls latency; no exact deadline is promised.

Monitor Mode retains its existing sampling, statistics, recording and alarms. Either capability keeps the single specialUse foreground service active. Stopping one leaves the other running; enabling alerts does not enable monitoring. Both off stops the service. The quiet alert-only channel updates at mode transitions, not on a recurring timer. Notification dismissal does not clear consent or stop alerts. Platform dismissal rules apply; Active apps Stop and force-stop are different from dismissing a notification.

Both saved choices recover after supported boot-after-unlock and package-update events; failed starts are caught and retried on app launch. OEM restrictions can still prevent operation. No Accessibility, exact-alarm, overlay permissions or continuous wake locks are added.

Device verification: enable alerts with Monitor Mode off; cross a charge threshold outside the UI; check a temperature alarm and repeated snooze; dismiss the status notification; swipe the task away; reboot and unlock; test all four mode combinations and each Stop action. Compare battery use in a release build. Keep force-stop limitations distinct from task dismissal.

## Existing Monitor Mode details

# Background monitoring and temperature reminders

Monitoring is opt-in during first setup or through Dashboard / Settings. Both controls manage the same recording-and-alert service. The saved choice survives closing the screen, process recreation, phone restart after unlock, and app updates. Stop monitoring clears that choice. Force stop and OEM restrictions can prevent recovery; opening the app retries a saved request. The toggle does not grant Android permissions or manufacturer autostart access.

Temperature reminder interval defaults to 5 minutes and accepts whole minutes from 1 to 30. Snooze silences current alarms; an active temperature warning schedules reevaluation after the interval. If still at or above the limit, it alerts again. Cooling below limit minus 2 degrees clears the episode; reheating can trigger immediately. Plug changes do not reset snooze. Changing the interval affects the next snooze; changing the threshold or disabling alerts cancels it. Process recreation preserves the deadline; reboot discards it and evaluates current temperature. Delivery may be delayed by device sleep, and no exact-alarm or permanent wake-lock permission is used.

## Play Console submission

Update the foreground-service declaration under App content for specialUse. Explain continuous user-enabled battery recording and threshold alerts, why interruption breaks them, and provide a reviewer-accessible video showing opt-in, ongoing notification, background alert, temperature snooze and stop. Existing draft: play-store-release.md. There is no claim that the declaration is submitted or approved. RECEIVE_BOOT_COMPLETED is a normal permission; this implementation adds no full-screen or exact-alarm permission. Users configure battery optimization and OEM autostart themselves.

References:
- https://support.google.com/googleplay/android-developer/answer/13392821
- https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
- https://developer.android.com/training/monitoring-device-state/doze-standby

## Focused input review

Numeric thresholds already use digit filtering and bounded native checks. Native individual and bulk settings updates now enforce allowed keys, boolean types, enum values, finite whole numbers and ranges before saving. Tone metadata is limited to defined fields and supported URI schemes. Recording names are trimmed, limited to 1-80 characters and stored using ContentValues and bound selection arguments, never executable SQL. Audio selection uses Android document-picker content URIs and verifies readability and playback. External links require HTTPS and a host. These checks do not constitute a comprehensive security audit or a guarantee of no vulnerabilities.

## Phone verification (user runs the app)

- Accept / decline setup; check Settings and Dashboard controls and ongoing notification agree.
- Test denial and later grant of notification access; check battery restriction guidance.
- Enable monitoring, close / swipe away the app, and lock for 15-30 minutes. Test under normal and unrestricted battery settings.
- Restart and unlock; confirm monitoring returns. Stop through notification, restart, and confirm it stays off.
- Test a reachable charge / low-battery threshold. Never heat a phone to test temperature; use simulated readings in native tests.
- Verify temperature snooze expiry, cooling and reheating, and repeated snoozes with simulated readings.
- Check narrow screens and larger text; measure device battery cost separately. No automated result establishes OEM reliability or Play approval.
