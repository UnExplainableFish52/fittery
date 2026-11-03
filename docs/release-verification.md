# Release verification: 0.8.0 (15)

Checked October 27, 2026. This is a candidate for device review and internal testing; production acceptance is still pending.

The user requested the pre-1.0 version 0.8.0. Only version metadata changed after the previous 41 Flutter tests, 64 native tests, analyzer, and release-lint pass; no application logic changed in this version bump. Both the phone profile APK and signed release bundle were rebuilt and their version metadata verified.

## Automated results

| Check | Result |
| --- | --- |
| Dart formatting | 20 files checked; no formatting changes needed. |
| `flutter analyze --no-pub` | Passed; no issues. |
| `flutter test --no-pub --reporter expanded --concurrency=1` | 41 passed, including a 320 × 640 layout at 150% system text size. |
| Native `testDebugUnitTest` | 64 passed; no failures, errors, or skipped tests. |
| Android `lintRelease` | Passed with zero errors and 24 warnings; details below. |
| `flutter build appbundle --release` | Passed with the upload signing configuration. |
| JAR signature verification | `jarsigner -verify` reports `jar verified`; signer CN is Fittery Upload, not Android Debug. Self-signed upload-certificate/trust and timestamp notices are expected for this local Android upload certificate. |
| Target and release permissions | Merged release manifest reports version 0.8.0, code 15, target API 36. No Internet permission or direct battery-optimization exemption permission. Backup/transfer exclusions are configured. |
| Native alignment | BundleConfig requests `PAGE_ALIGNMENT_16K`. All four shipped 64-bit `libapp.so`/`libflutter.so` files have 65,536-byte LOAD alignment; RELRO protection does not overlap writable data. This is artifact inspection, not a 16 KB device runtime test. |
| Generated registrant | Normal release build excludes the development-only integration-test plugin. |
| Signing material | `android/key.properties` and `android/upload-keystore.jks` are ignored by Git. Backup confirmation is pending. |
| Public privacy page | HTTP 200, but live content still describes release behavior as unverified. Replacement prepared in `fittery-privacy.html`; deployment pending. |
| Phone install and launch | Profile APK installed with `adb install -r` on device 5b23fecb (23021RAAEG, Android 15/API 35). Android reports version 0.8.0/code 15; the first-install time remains October 26, 2026 at 20:07:09. Launch returned `Status: ok`, and the process remained running with no error-level AndroidRuntime/flutter/Fittery output in the immediate log check. This is a launch smoke check, not full device or performance acceptance. |
| Store artwork | Store icon is 512 × 512, 32-bit RGBA, below 1,024 KB, and pixel-identical to the original. Feature graphic is 1024 × 500, 24-bit RGB without alpha; visually inspected. Prepared under `store-assets/`, with editable SVG and alternative text. Owner approval and actual phone screenshots remain. |

Artifact: `build/app/outputs/bundle/release/app-release.aab`

Size: **42,450,308 bytes** (about 40.5 MiB). This is the bundle with all supported ABIs, not a measured Play download size.

SHA-256:

```text
4511320bc43ca077525263c4f75f1f176a3f9ec10f812f844d17f536d7113a10
```

The report applies to this exact artifact. Rebuild and refresh these values after any app changes.

## Changes from the audited working tree

- Replaced debug release signing with an upload-key configuration and a useful missing-configuration error. Created the first local upload key without printing passwords.
- Pinned target API 36 and advanced the test candidate to the user-requested 0.8.0 (15).
- Changed battery sampling cadence to use Android's elapsed clock. Recorded sample timestamps still use wall time. The previously failing one-second sampling regression now passes.
- Fixed the app-bar title overflowing at enlarged system text size and added the regression scenario.
- Replaced the direct battery-optimization exemption request with Android's battery settings and removed the special exemption permission.
- Added Android 7 notification-settings fallback and explicit backup exclusions for modern Android, with legacy backup disabled.
- Added public support contact, finalized local policy text, prepared public HTML policy and store/reviewer materials, and corrected the release build instructions for Flutter's development-plugin generation issue.

Existing application, telemetry, storage and branding changes already present in the working tree were retained and included in the candidate.

## Remaining Android lint warnings

| Count | Warning | Assessment / follow-up |
| --- | --- | --- |
| 5 | IconLauncherShape | Launcher artwork silhouette warning across legacy densities. Review the actual launcher icon during visual approval. |
| 1 | MonochromeLauncherIcon | A dedicated monochrome adaptive icon is still a polish item. |
| 1 | InlinedApi | The Wi-Fi unknown-SSID string constant is newer than the minimum SDK; it is inlined and used only to filter an unavailable name. |
| 1 | PrivateApi | The capacity fallback uses guarded PowerProfile reflection after the framework XML read. Failures return unavailable. This fallback can stop working with platform/OEM changes; it is not a guaranteed capacity source. |
| 2 | StaticFieldLeak | Singleton holders retain application context through their production factories, rather than an Activity context. This warning does not establish an Activity leak; memory behavior still needs device profiling if symptoms appear. |
| 12 | UseKtx | Kotlin convenience-extension suggestions. No functional failures reported. |
| 1 | ObsoleteSdkInt | Redundant `drawable-v21` resource qualifier inherited from the splash setup. |
| 1 | NewerVersionAvailable | A newer test-only Robolectric release is available; the verified version remains pinned. |

The only configured lint exception is PropertyEscape for Flutter's generated `android/local.properties`; Java properties accept its drive colon within a value, and Flutter rewrites the file on every build. No lint baseline or global suppression was added.

## Still required before production

- User phone screenshots and feedback; real-device startup, scrolling, thermal/battery-use and background monitoring checks.
- Install/update verification through Play, plus pre-launch stability, performance and accessibility review.
- Backup of the upload key/passwords, approval of the prepared store graphics, actual phone screenshots, final privacy-page deployment, and Console content/foreground-service declarations with a demonstration video.
- The required closed test with at least 12 continuously opted-in testers for 14 days, meaningful feedback, production-access approval, and release review.

Follow `play-store-release.md` for the sequence and device scenarios. No production-readiness claim is based solely on these automated tests.
