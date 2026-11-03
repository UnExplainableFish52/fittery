"""Encode generated charging artwork for the app; originals remain untouched."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
with Image.open(ROOT / "design/charging/teal-waves-v1-generated.png") as image:
    image.convert("RGB").save(ROOT / "assets/charging/teal_waves_v1.webp", quality=88, method=6)
with Image.open(ROOT / "FitteryScreenSaverProposal.png") as image:
    image.convert("RGB").save(ROOT / "assets/charging/proposal_brand_source_v1.webp", lossless=True, method=6)
    points = [(x, y) for y in range(min(205, image.height)) for x in range(image.width)
              if image.getpixel((x, y))[1] > 145 or image.getpixel((x, y))[2] > 180]
    print("Proposal size:", image.size)
    print("Brand bounds:", (min(x for x, _ in points), min(y for _, y in points),
                            max(x for x, _ in points), max(y for _, y in points)))
for name in ("teal_waves_v1.webp", "proposal_brand_source_v1.webp"):
    print(name, (ROOT / "assets/charging" / name).stat().st_size, "bytes")

core = ROOT / "design/charging/teal-core-v2-generated.png"
if core.exists():
    with Image.open(core) as image:
        image = image.convert("RGB")
        image.thumbnail((512, 512), Image.Resampling.LANCZOS)
        image.save(ROOT / "assets/charging/teal_core_v2.webp", quality=88, method=6)
    print("teal_core_v2.webp", (ROOT / "assets/charging/teal_core_v2.webp").stat().st_size, "bytes")
