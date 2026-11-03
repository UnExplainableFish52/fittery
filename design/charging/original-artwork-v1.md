# Original reference artwork - Build 19

The user requested the exact supplied Fittery logo/mascot and artwork after reviewing Build 18. Build 18 is preserved with its APK, source and assets in [the saved version](saved/build-18-underwater/README.md).

`assets/charging/underwater_reference_v1.webp` is an optimized copy of the user's `Fittery Neon Underwater Dashboard.png` (841 x 1870, 200,702 bytes, WebP quality 92). No image was generated for this revision and the original PNG is unchanged. Runtime source rectangles reuse the supplied logo and fish, four card frames/icons, source pill and slider texture. These image regions are drawn at the live widget bounds. The bitmap's fixed gauge and fixed slider thumb are never drawn; the battery fill, moving glint, values, labels and gesture control remain native Flutter widgets/painters.

The artwork provider shares a single cached decode among the regions. Region listeners are removed and retained image handles released on disposal. The previous clean underwater backdrop remains behind the live layout. No new telemetry, permissions, background service or animation controller is added.

A fullscreen shortcut next to the main Dashboard's battery display opens the charging dashboard. It follows the feature's Settings toggle and requires a connected charger. Existing Settings and monitoring entry points remain available.
