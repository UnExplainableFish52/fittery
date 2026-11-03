# Fittery Privacy Policy

Last updated: October 29, 2026

Fittery is developed by **TheIdealDev52 (Saksham Sharma)**. Its Android package is `com.fittery.tid52`.

For privacy questions or support, contact **sharma@saksham.info.np**.

Fittery reads battery measurements and basic device information to display status, estimate health and remaining time, record local history, and deliver battery and temperature alerts.

Optional dashboard network activity reads Android's device-wide traffic counters and current connection information only while Dashboard is visible. Wi-Fi names are shown only when available without extra sensitive permissions. Network readings and names are not saved or uploaded, and Fittery does not perform internet speed tests. Device specifications are read on demand.

Battery samples, session records, preferences, and the selected alarm-tone reference are stored on the device. Fittery does not upload this information, create accounts, run analytics, show advertisements, or include tracking SDKs. The release app does not request Internet permission, and Android cloud backup is disabled.

Notifications and an optional foreground service make background monitoring visible. Users control alert thresholds, alarm sound, monitoring, and lock-screen visibility. The system alarm picker provides the chosen tone; audio is not uploaded.

Monitor mode saves three-second battery measurements for both charging and discharging in the app's private database. Each monitor recording keeps its original data; graphs are generated when viewed. Completed recordings expire 30 days after creation by default, with no count limit. Active recordings are protected. The "Keep recordings until I delete them" setting disables automatic deletion. Cleanup runs when recording or viewing history, so deletion can occur later if the app is not running. "Clear all recordings" removes all local recordings and the legacy telemetry cache. Uninstalling the app removes its private data. The legacy dashboard telemetry cache is separate and retains its existing short-term limits.

Any developer-website or privacy-policy links open the user's browser. The browser and destination website operate under their own privacy policies.

Battery readings depend on device firmware. Health percentages and time remaining are labeled estimates, not independent measurements of battery degradation.

Public policy: https://saksham.info.np/fittery-privacy.html

The app uses this public policy URL by default. `PRIVACY_POLICY_URL` can override it at build time. `DEVELOPER_WEBSITE_URL` configures the optional developer-website link separately.
