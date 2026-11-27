"""Rebuild MuseFleet's original vector-derived opaque app icon. Requires Pillow."""
from pathlib import Path
import json
from math import hypot
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    size = 1024
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    stops = [(0, (59, 52, 121)), (.53, (24, 23, 45)), (1, (12, 16, 29))]
    for y in range(size):
        for x in range(size):
            t = min(1, hypot(x / size - .18, y / size - .1) / 1.15)
            left, right = (stops[0], stops[1]) if t <= .53 else (stops[1], stops[2])
            alpha = (t - left[0]) / (right[0] - left[0])
            pixels[x, y] = tuple(round(a + (b - a) * alpha) for a, b in zip(left[1], right[1]))
    mask = Image.new("L", (size * 3, size * 3))
    draw = ImageDraw.Draw(mask)
    points = [(194, 708), (329, 300), (339, 288), (356, 297), (514, 491), (672, 297), (688, 288),
              (699, 300), (834, 708), (699, 708), (635, 499), (514, 643), (393, 499), (329, 708)]
    draw.polygon([(x * 3, y * 3) for x, y in points], fill=255)
    mask = mask.resize((size, size), Image.Resampling.LANCZOS)
    sail = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(sail)
    for y in range(size):
        t = max(0, min(1, (y - 280) / 440))
        draw.line([(0, y), (size, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip((245, 240, 255), (174, 162, 255))))
    image.paste(sail, (0, 0), mask)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((430, 730, 598, 758), radius=14, fill=(195, 182, 255))
    draw.ellipse((754, 226, 822, 294), fill=(185, 245, 229))
    image.save(OUT / "AppIcon.png")
    manifest = {"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                "info": {"author": "xcode", "version": 1}}
    (OUT / "Contents.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    with Image.open(OUT / "AppIcon.png") as result:
        assert result.size == (1024, 1024) and result.mode == "RGB", "App icon must be opaque 1024px RGB"
    print("App icon generated and checked: 1024x1024, RGB, no alpha")


if __name__ == "__main__":
    main()
