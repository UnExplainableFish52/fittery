# Fittery Google Play artwork

Icon updated November 6, 2026; feature graphic prepared October 27, 2026. The icon is also bundled for the dashboard and onboarding. Uploading these files in Play Console updates the store listing separately from the installed app.

| File | Upload purpose | Verified format |
| --- | --- | --- |
| `app-icon-512.png` | App icon | 512 × 512; 32-bit RGBA PNG, below the 1,024 KB limit. |
| `feature-graphic-1024x500.png` | Feature graphic | 1024 × 500; 24-bit RGB PNG with no alpha; 50,685 bytes. |
| `feature-graphic.svg` | Editable feature-graphic source | Vector artwork and text. Upload the PNG to Play Console. |

The store icon preserves every decoded pixel of `FitteryLogo_512x512.png`. The supplied original is a 24-bit PNG, so it is re-encoded with an alpha channel for Google's required 32-bit upload format. Launcher resources are generated separately by `tools/generate_branding.ps1`.

The feature graphic uses Fittery's teal palette and an illustrated battery. It contains no simulated readings, fabricated screenshots, rankings, pricing claims, or time-sensitive release text. It was visually inspected at its full upload dimensions. Visual approval is still with the app owner.

Suggested alternative text:

- **Icon:** A blue-to-mint F symbol combining a battery outline, plus sign, and pulse line on a dark background.
- **Feature graphic:** Fittery: know your battery. Live readings, local history and charging alerts, beside an illustrated battery on teal.

Regenerate these assets from the project root on Windows:

```powershell
.\tools\generate_store_assets.ps1
```

Use `.\tools\generate_store_assets.ps1 -IconOnly` to regenerate just the icon.

The script uses Windows GDI+ and Segoe UI to export the PNG. The SVG remains editable in a vector editor. Do not replace real app screenshots with this illustration.

Still needed: actual phone screenshots and the foreground-service demonstration video described in `../docs/play-store-release.md`.

Source: [Google Play preview-asset requirements](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en).
