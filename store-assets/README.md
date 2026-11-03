# Fittery Google Play artwork

Prepared October 27, 2026. These are listing assets for review; they do not change the installed app.

| File | Upload purpose | Verified format |
| --- | --- | --- |
| `app-icon-512.png` | App icon | 512 × 512; 32-bit RGBA PNG; 334,289 bytes, below the 1,024 KB limit. |
| `feature-graphic-1024x500.png` | Feature graphic | 1024 × 500; 24-bit RGB PNG with no alpha; 50,685 bytes. |
| `feature-graphic.svg` | Editable feature-graphic source | Vector artwork and text. Upload the PNG to Play Console. |

The store icon preserves every decoded pixel of `fittery_app_drawer_512.png`. The original is a 24-bit PNG, so it is re-encoded with an alpha channel for Google's required 32-bit upload format. The Android launcher assets and original artwork are unchanged.

The feature graphic uses Fittery's teal palette and an illustrated battery. It contains no simulated readings, fabricated screenshots, rankings, pricing claims, or time-sensitive release text. It was visually inspected at its full upload dimensions. Visual approval is still with the app owner.

Suggested alternative text:

- **Icon:** Fittery fish mascot with battery cells and lightning bolts.
- **Feature graphic:** Fittery: know your battery. Live readings, local history and charging alerts, beside an illustrated battery on teal.

Regenerate these assets from the project root on Windows:

```powershell
.\tools\generate_store_assets.ps1
```

The script uses Windows GDI+ and Segoe UI to export the PNG. The SVG remains editable in a vector editor. Do not replace real app screenshots with this illustration.

Still needed: actual phone screenshots and the foreground-service demonstration video described in `../docs/play-store-release.md`.

Source: [Google Play preview-asset requirements](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en).
