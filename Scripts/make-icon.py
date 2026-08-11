#!/usr/bin/env python3
"""Generate the macOS app icon set from a single source logo.

Usage:  python3 Scripts/make-icon.py [source.png]

Writes:
  Autoclicker/Assets.xcassets/AppIcon.appiconset/   (for the Xcode build)
  Resources/AppIcon.icns                            (for the script build)

The source should be a square PNG with transparency. Re-run this whenever
the logo changes.
"""
import json
import os
import subprocess
import sys
import tempfile

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required:  python3 -m pip install --user Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(ROOT, "Autoclicker/Assets.xcassets/AppIcon.appiconset")
ICNS_DIR = os.path.join(ROOT, "Resources")

# (point size, scale) pairs macOS asks for in an app icon set.
VARIANTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
            (256, 1), (256, 2), (512, 1), (512, 2)]


def load_square(path):
    """Load the logo and pad it to a centered square canvas."""
    img = Image.open(path).convert("RGBA")
    side = max(img.size)
    if img.size != (side, side):
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
        img = canvas
    return img


def simplified(img):
    """A version with the fine interior detail removed.

    At 16-32px the burst rays, cursor and dashed arc collapse into noise and
    the icon reads as a mushy blob. Apple ships distinct artwork per size for
    exactly this reason. Here we keep the strong silhouette — outer ring,
    cardinal tabs and inner arcs — and replace the busy middle with a clean
    navy field plus a single centered dot.
    """
    from PIL import ImageDraw
    out = img.copy()
    side = out.width
    c = side / 2

    # Sample the dark interior and the green from the artwork itself so this
    # keeps working if the logo's palette changes.
    navy = img.getpixel((int(c), int(side * 0.30)))
    green = img.getpixel((int(c), int(side * 0.115)))
    if navy[3] < 200:
        navy = (10, 26, 47, 255)
    if green[3] < 200:
        green = (77, 232, 138, 255)

    draw = ImageDraw.Draw(out)
    inner = side * 0.145          # clears the inner arcs, covers the detail
    draw.ellipse([c - inner, c - inner, c + inner, c + inner], fill=navy)
    dot = side * 0.052
    draw.ellipse([c - dot, c - dot, c + dot, c + dot], fill=green)
    return out


def render(img, px):
    """High-quality downscale to px x px."""
    return img.resize((px, px), Image.LANCZOS)


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "Resources/logo.png")
    if not os.path.exists(source):
        sys.exit(f"Source logo not found: {source}")

    img = load_square(source)
    small = simplified(img)
    # Below this pixel size the detailed artwork stops being readable.
    SIMPLIFY_AT_OR_BELOW = 32

    os.makedirs(ICONSET, exist_ok=True)
    os.makedirs(ICNS_DIR, exist_ok=True)

    images = []
    for point, scale in VARIANTS:
        px = point * scale
        name = f"icon_{point}x{point}{'@2x' if scale == 2 else ''}.png"
        source_img = small if px <= SIMPLIFY_AT_OR_BELOW else img
        render(source_img, px).save(os.path.join(ICONSET, name))
        images.append({
            "size": f"{point}x{point}",
            "idiom": "mac",
            "filename": name,
            "scale": f"{scale}x",
        })

    with open(os.path.join(ICONSET, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)

    # Build a .icns for the plain-swiftc build, which has no asset catalog.
    with tempfile.TemporaryDirectory() as tmp:
        stage = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(stage)
        for point, scale in VARIANTS:
            px = point * scale
            name = f"icon_{point}x{point}{'@2x' if scale == 2 else ''}.png"
            render(small if px <= SIMPLIFY_AT_OR_BELOW else img, px).save(
                os.path.join(stage, name))
        icns = os.path.join(ICNS_DIR, "AppIcon.icns")
        subprocess.run(["iconutil", "-c", "icns", stage, "-o", icns], check=True)

    print(f"Wrote {len(images)} images to {ICONSET}")
    print(f"Wrote {os.path.join(ICNS_DIR, 'AppIcon.icns')}")


if __name__ == "__main__":
    main()
