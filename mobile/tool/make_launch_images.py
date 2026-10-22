"""Cuts the native launch-screen images from the opening's own logo.

The first frame of the app's opening (lib/app/launch_splash.dart) draws the
finished logo with AkaratLogoAnimated; the launch screens must show exactly
that, centred on the lockup, so the hand-over cannot be seen. Run from mobile/:

    flutter test test/visual/launch_logo_test.dart --run-skipped
    python tool/make_launch_images.py

Reads build/launch_logo.png (the 1080-unit drawing at 4 px per unit, written
by the test). Writes:
  android  drawable-*/splash_mark.png   launch image before Android 12
           drawable-*/splash_icon.png   Android 12+ splash icon: a 288 dp canvas
                                        (no icon background), the lockup inside
                                        the 192 dp circle the system shows
  ios      LaunchImage.imageset/*.png   launch storyboard image
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")

# Must match LaunchSplash._lockupCentre, _lockupWidth and launchLogoWidth.
CENTRE = (541.75, 497.25)
LOCKUP_WIDTH = 911.5
LAUNCH_WIDTH_DP = 140.38
HALF = 480  # the crop's half side, in logo units: the lockup and its glow

src = Image.open(os.path.join(ROOT, "build", "launch_logo.png")).convert("RGBA")
box = tuple(round(v * 4) for v in (CENTRE[0] - HALF, CENTRE[1] - HALF, CENTRE[0] + HALF, CENTRE[1] + HALF))
crop = src.crop(box)
side_dp = 2 * HALF * LAUNCH_WIDTH_DP / LOCKUP_WIDTH


def sized(scale):
    side = round(side_dp * scale / 2) * 2  # even, so it centres exactly
    return crop.resize((side, side), Image.LANCZOS)


res = os.path.join(ROOT, "android", "app", "src", "main", "res")
for bucket, scale in [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]:
    folder = os.path.join(res, f"drawable-{bucket}")
    os.makedirs(folder, exist_ok=True)
    mark = sized(scale)
    mark.save(os.path.join(folder, "splash_mark.png"), optimize=True)
    canvas_side = round(288 * scale)
    canvas = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    canvas.paste(mark, ((canvas_side - mark.width) // 2, (canvas_side - mark.height) // 2), mark)
    canvas.save(os.path.join(folder, "splash_icon.png"), optimize=True)

ios = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "LaunchImage.imageset")
for suffix, scale in (("", 1), ("@2x", 2), ("@3x", 3)):
    sized(scale).save(os.path.join(ios, f"LaunchImage{suffix}.png"), optimize=True)

print(f"launch images written ({side_dp:.2f} dp square)")
