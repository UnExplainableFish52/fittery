"""Build the runtime WebP illustrations from the separate generated PNG sources."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
output = root / "assets" / "onboarding"
output.mkdir(parents=True, exist_ok=True)
total = 0
revision = root / "design" / "onboarding" / "source" / "v2"
source_root = revision if revision.is_dir() else revision.parent
max_side = 1024 if source_root == revision else 640
for name in ("welcome", "features", "forever", "setup"):
    source = source_root / f"{name}.png"
    with Image.open(source) as original:
        image = original.convert("RGBA")
        if image.getchannel("A").getextrema()[0] == 255:
            raise ValueError(f"{name}: expected a transparent illustration")
        image.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
        destination = output / f"{name}.webp"
        image.save(destination, "WEBP", quality=82, method=6)
        with Image.open(destination) as verified:
            assert verified.size == image.size
            assert verified.mode == "RGBA"
        size = destination.stat().st_size
        total += size
        print(f"{name}: {image.width}x{image.height}, {size:,} bytes")
print(f"Runtime artwork total: {total:,} bytes")
