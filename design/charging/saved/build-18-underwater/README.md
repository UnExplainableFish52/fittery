# Saved Build 18 underwater dashboard

This is the exact previous design, saved before applying the user's original logo/card artwork or adding the main battery shortcut.

- `fittery-build-18-debug.apk`: complete reinstallable Build 18 APK, kept locally and excluded from Git to avoid committing a large binary.
- `charging_dashboard.dart.txt`: previous dashboard source. The `.txt` suffix prevents Flutter from analyzing this archived copy as application code.
- `pubspec.yaml.txt`: previous version and asset registration.
- `neon_underwater_v1.webp`: previous backdrop.
- `underwater-v1.md`: design details and the image-edit prompt.
- `checksums.json`: SHA-256 hashes recorded when the backup was created.

To restore just the previous appearance, copy the archived Dart source back to `lib/src/charging_dashboard.dart` and keep `assets/charging/neon_underwater_v1.webp` registered. The new main-page shortcut can remain. To restore the complete previous app on a device, use the saved APK; Android may require a permitted downgrade or a fresh install, which can affect local data. No automatic rollback or uninstall is performed by this backup.
