const developerName = 'TheIdealDev52';
const developerCredit = 'Saksham Sharma';
const supportEmail = 'sharma@saksham.info.np';
const privacyPolicyUrl = String.fromEnvironment(
  'PRIVACY_POLICY_URL',
  defaultValue: 'https://saksham.info.np/fittery-privacy.html',
);
const developerWebsiteUrl = String.fromEnvironment('DEVELOPER_WEBSITE_URL');

const privacyPolicyText = '''Fittery privacy policy

Developer: TheIdealDev52 (Saksham Sharma)
Contact: sharma@saksham.info.np
Last updated: October 29, 2026

Fittery reads battery measurements and basic device information to display battery status, estimate health and remaining time, record history, and deliver alerts.

Optional dashboard network activity reads Android's device-wide traffic counters and current connection information. It runs only while Dashboard is visible. Wi-Fi names appear only when Android makes them available without extra sensitive permissions. Network readings and names are not saved or uploaded. No internet speed tests are performed.

Battery samples, session records, preferences, and the selected alarm-tone reference are stored on your device. Fittery does not upload this information, create accounts, run analytics, display ads, or include tracking SDKs. The release app does not request Internet permission.

Notifications and the optional foreground service keep monitoring visible. You control alert settings and lock-screen visibility. The system alarm picker provides the tone you select; Fittery does not upload audio.

Monitor mode saves three-second battery measurements for both charging and discharging in the app's private database. Each monitor recording keeps its original data; graphs are generated when viewed. Completed recordings expire 30 days after creation by default, with no count limit. Active recordings are protected. The "Keep recordings until I delete them" setting disables automatic deletion. Cleanup runs when recording or viewing history, so deletion can occur later if the app is not running. "Clear all recordings" removes all local recordings and the legacy telemetry cache. Uninstalling the app removes its private data. The legacy dashboard telemetry cache is separate and retains its existing short-term limits.

Website and privacy links, when configured, open your browser. The browser and destination website operate under their own privacy policies.

Battery readings depend on the device firmware. Health and time remaining are labeled estimates, not independent measurements of battery degradation.''';
