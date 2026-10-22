"""Generates the launcher icons from the brand mark.

Source: ../assets/akarat-mark.png (the website's own mark). Run from mobile/:

    python tool/gen_native_assets.py

Writes:
  android  mipmap-*/ic_launcher.png            legacy icons
           mipmap-*/ic_launcher_foreground.png  adaptive-icon foreground
  ios      AppIcon.appiconset/*.png             every size in Contents.json,
                                                 opaque (App Store rejects alpha)

The launch screens are not made here: they show the opening's own logo and
come from tool/make_launch_images.py.
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
MARK = os.path.join(ROOT, "..", "assets", "akarat-mark.png")
TILE = (23, 23, 15, 255)  # #17170F, the dark tile behind the mark on the website's icons

mark = Image.open(MARK).convert("RGBA")
mark = mark.crop(mark.getbbox())


def fit(img, box_w, box_h):
    w, h = img.size
    s = min(box_w / w, box_h / h)
    return img.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)


def composed(size, mark_frac, bg):
    canvas = Image.new("RGBA", (size, size), bg)
    m = fit(mark, size * mark_frac, size * mark_frac)
    canvas.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
    return canvas


res = os.path.join(ROOT, "android", "app", "src", "main", "res")
densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
for name, k in densities.items():
    folder = os.path.join(res, f"mipmap-{name}")
    os.makedirs(folder, exist_ok=True)
    composed(round(48 * k), 0.62, TILE).save(os.path.join(folder, "ic_launcher.png"))
    # Adaptive icon: 108 dp canvas, content inside the 66 dp safe zone.
    composed(round(108 * k), 0.40, (0, 0, 0, 0)).save(os.path.join(folder, "ic_launcher_foreground.png"))

ios = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets")
appicon = os.path.join(ios, "AppIcon.appiconset")
contents = json.load(open(os.path.join(appicon, "Contents.json")))
for img in contents["images"]:
    if "filename" not in img:
        continue
    pts = float(img["size"].split("x")[0])
    scale = int(img["scale"].rstrip("x"))
    px = round(pts * scale)
    composed(px, 0.62, TILE).convert("RGB").save(os.path.join(appicon, img["filename"]))


print("native assets written", file=sys.stderr)
