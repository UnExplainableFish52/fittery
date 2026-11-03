# Per-alert sounds - Build 22

Settings starts with **Alert sounds**. Charging limit, Battery temperature, and Low battery each have a preview button and their own selection sheet: Default voice, System alarm tones, Choose audio file, and Silent. Alarm sound is the shared enable switch. Alert thresholds and background monitoring still control when alerts trigger.

| Alert | Original recording | Bundled resource |
| --- | --- | --- |
| Charging limit | `ChargingLimitReachedNotif.mp3` | `raw/charging_limit_reached.mp3` |
| Battery temperature | `BatteryGettingHot.mp3` | `raw/battery_temperature_limit.mp3` |
| Low battery | `LowBatteryWarning.mp3` | `raw/low_battery_warning.mp3` |

The resource copies are byte-for-byte identical to the originals; no leveling, conversion, or generated voice is applied. The unused `Full_Capacity.mp3` was removed at the owner's request. Existing explicit shared custom/system/Silent selections are preserved for all three alerts on upgrade; reset an individual alert to Default voice to use its dedicated recording. Previously implicit system defaults become the new bundled voices.

Local files use Android's `ACTION_OPEN_DOCUMENT` audio picker and a persistent read-only URI grant. The app requests no music-library/storage permission. A worker validates playback before saving a replacement. Cancel/error retains the previous choice. A grant is released only after no alert references that file. Deleted/moved/unavailable files produce an actionable preview error; an actual alarm falls back to that alert's bundled recording.

Previews play once and stop at completion, at 30 seconds, when stopped/switched, when the app leaves the foreground, or when a real alert begins. Actual alarms retain full-clip looping and existing Silence/condition-resolution behavior. One player serves active alarms: temperature takes priority, then low battery, then charge limit. Silent alerts retain notifications and do not suppress other audible active alerts. No extra service or background polling is introduced. The optional DreamService screen saver is retained.

Device verification: preview all three voices and confirm alarm volume; choose different local files for each alert; cancel and choose unsupported files; relaunch/reboot to confirm persistence; restore Default voice and test Silent; test alarms while monitoring with the screen off and verify Silence/recovery; remove a chosen file to check fallback. Confirm Android's screen-saver setup/Preview while charging separately. OEM playback and idle behavior require physical-device feedback.

Automated verification: clean Flutter analysis, 105 passing Flutter tests, 112 passing Android unit tests, Android lint with zero errors (26 warnings, including a new optional KTX style suggestion), debug APK and ARM64 release APK builds. APK resource hashes were checked against the original MP3s. Build 22 was installed on the connected phone with data preserved and its version confirmed. Sound quality and screen-saver activation still need the owner's device feedback.

References: [Android document picker and persistent access](https://developer.android.com/training/data-storage/shared/documents-files#persist-permissions), [Ringtone playback/looping](https://developer.android.com/reference/android/media/Ringtone).
