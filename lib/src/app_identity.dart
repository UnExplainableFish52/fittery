const developerName = 'TheIdealDev52';
const developerCredit = 'Saksham Sharma';
const privacyPolicyUrl = String.fromEnvironment(
  'PRIVACY_POLICY_URL',
  defaultValue: 'https://saksham.info.np/fittery-privacy.html',
);
const developerWebsiteUrl = String.fromEnvironment('DEVELOPER_WEBSITE_URL');

const privacyPolicyText = '''Fittery privacy policy

Developer: TheIdealDev52 (Saksham Sharma)

Fittery reads battery measurements and basic device information to display battery status, estimate health and remaining time, record history, and deliver alerts.

Optional dashboard network activity reads Android's device-wide traffic counters and current connection information. It runs only while Dashboard is visible. Wi-Fi names appear only when Android makes them available without extra sensitive permissions. Network readings and names are not saved or uploaded. No internet speed tests are performed.

Battery samples, session records, preferences, and the selected alarm-tone reference are stored on your device. Fittery does not upload this information, create accounts, run analytics, display ads, or include tracking SDKs. The release app does not request Internet permission.

Notifications and the optional foreground service keep monitoring visible. You control alert settings and lock-screen visibility. The system alarm picker provides the tone you select; Fittery does not upload audio.

Battery history retains at most 10 sessions. Sessions expire 72 hours after they start; expired or excess sessions, their readings, and their contributions to daily totals are automatically deleted when history is read or recorded. Clear charge history removes all locally recorded chart and session data. Uninstalling the app removes its private app data. Android cloud backup is disabled for the app.

Website and privacy links, when configured, open your browser. The browser and destination website operate under their own privacy policies.

Battery readings depend on the device firmware. Health and time remaining are labeled estimates, not independent measurements of battery degradation.''';
