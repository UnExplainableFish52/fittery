# Fittery onboarding artwork

Generated with the built-in image generation tool for this project. The current revision uses larger, brighter portrait illustrations inspired by the supplied `Glowing Eco Battery Shield-1.png` reference. Headlines, colored keywords, feature labels, progress indicators, checkboxes and buttons remain native Flutter widgets. The welcome flow deliberately uses short labels instead of explanatory paragraphs.

## Production assets

| Asset | File | Dimensions | Bytes |
| --- | --- | --- | ---: |
| Welcome Battery | `assets/onboarding/welcome.webp` | 819 x 1024 | 183,198 |
| Features | `assets/onboarding/features.webp` | 819 x 1024 | 242,898 |
| Free Forever | `assets/onboarding/forever.webp` | 819 x 1024 | 222,782 |
| Minimalist Setup | `assets/onboarding/setup.webp` | 819 x 1024 | 207,550 |

All four retain alpha transparency. The runtime bundle is **856,428 bytes** (approximately 836 KiB, under 1 MiB). Current originals are kept separately in `design/onboarding/source/v2/{welcome,features,forever,setup}.png`. The first revision's originals remain in `design/onboarding/source/`. Source directories are not declared as Flutter assets.

Regenerate the optimized assets using `python tools/optimize_onboarding_art.py`. Pillow is a development-only dependency. The script prefers `source/v2`, resizes its portrait artwork with Lanczos to a maximum side of 1024, encodes lossy WebP at quality 82 with transparency, and checks dimensions and alpha preservation. If v2 is absent, it supports the original square sources at 640 pixels. Flutter displays only the active illustration and caps decoding at 1024 pixels. The larger assets preserve detail in the enlarged hero area. No runtime image-generation API, external font, additional package, blur filter or continuous illustration animation is required.

## Current prompts

See [v2 prompts and reference](v2-prompts.md). The v2 art gives the illustration most of the screen, while native colored keywords carry the copy. The buttons, Skip path, timer behavior and saved preferences are unchanged.

## Archived version 1 prompts

Each asset used this common prompt, followed by its subject prompt below, with `transparent_background=true`. No reference image was used.

> Use case: stylized-concept. Asset type: an illustration asset for a premium minimalist Android battery app onboarding, not a screen mockup. Create a single centered dimensional illustration on a truly transparent background, square composition, generous transparent margins. Art direction: polished glass-like objects, soft translucent dark teal glass, luminous mint green #35D0BD, cyan, restrained electric blue and lavender rim lights, friendly sophisticated shapes, soft studio lighting, delicate glow and a few tiny floating light particles. Keep a clean readable silhouette at 240 pixels wide; main object occupies about 75 percent of the frame. Coordinated materials, lighting, scale and palette for a four-illustration family. No text, no lettering, no numbers, no statistics, no branding, no buttons, no border, no environment or background panel. Do not draw a phone screenshot.

### Welcome Battery

> Subject: a large upright futuristic luminous battery, gently tilted in perspective, glass body and three luminous mint energy cells, a cyan-green energy trail orbiting it and a subtle protective halo/shield arc, with one tiny glass notification bell floating nearby. Reassuring, premium and approachable. Avoid dense circuitry, cables and excessive particles.

### Features

> Subject: an elegant upright luminous glass battery at the center, with a small balanced constellation of six floating translucent symbols: bell, thermometer, lightning/current zigzag, simple voltage bolt, minimal line chart without axes or numbers, and a stack of history cards without writing. Clear visual hierarchy and comfortable separation, sophisticated dimensional icon composition.

### Free Forever

> Subject: a large elegant glowing dimensional infinity loop of translucent mint and lavender glass flowing around a small upright luminous battery in the center. Uplifting, serene and open composition conveying lasting accessibility. Purple-green lighting and only a few floating gentle points of light. The infinity shape must be immediately recognizable.

### Minimalist Setup

> Subject: a compact floating glass mobile interface panel, upright in gentle three-quarter perspective, featuring a mint battery icon, three rounded configuration sliders without text or numbers, a small floating gear symbol, and two small orderly translucent control tiles. Clean, simple, organized, lots of breathing room; no fake statistics, no lettering and no buttons. Coordinated mint, cyan and lavender highlights.
