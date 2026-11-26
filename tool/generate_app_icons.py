#!/usr/bin/env python3
"""Generates every launcher icon of both platforms and both environments from two masters (Issue #139).

The masters are the only icon artwork to edit:

    assets/branding/app-icon-production.png    production (full colour)
    assets/branding/app-icon-staging.png       staging (black and white)

Each must be a 1024x1024 PNG. Transparency is allowed: the icon is composited onto an opaque white
square, because iOS rejects an icon with an alpha channel and the Android launcher icon is a square
JPEG. Nothing else is changed (no scaling, no margin, no recolouring).

    python3 tool/generate_app_icons.py

Outputs (committed; the build only selects them, see docs/BUILD_CONFIGURATION.md, Launcher icons):
    iOS      ios/Runner/Assets.xcassets/AppIcon.appiconset/<size>.png            production (RGB, no alpha)
             ios/Runner/Assets.xcassets/AppIcon-Staging.appiconset/<size>.png    staging
    Android  android/app/src/production/res/mipmap-<density>/ic_launcher.jpg     production (legacy square icon)
             android/app/src/staging/res/mipmap-<density>/ic_launcher.jpg        staging

The Android icons are JPEG: AAPT2 stores JPEG files unchanged, so the launcher icon inside a built APK
can be compared byte for byte with the file in this repository (tool/verify_artifact.sh).
Needs Pillow; it is a developer tool, no build or CI job runs it.
"""
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: pip install Pillow")

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ENVIRONMENTS = {
    "production": {
        "master": "assets/branding/app-icon-production.png",
        "ios": "ios/Runner/Assets.xcassets/AppIcon.appiconset",
        "android": "android/app/src/production/res",
    },
    "staging": {
        "master": "assets/branding/app-icon-staging.png",
        "ios": "ios/Runner/Assets.xcassets/AppIcon-Staging.appiconset",
        "android": "android/app/src/staging/res",
    },
}

# The files named by the iOS Contents.json (same set for both environments).
IOS_SIZES = [29, 40, 57, 58, 60, 80, 87, 114, 120, 180, 1024]
# Legacy launcher icon: density folder -> pixels (48 dp at 1x ... 4x).
ANDROID_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def load_master(rel):
    path = os.path.join(ROOT, rel)
    if not os.path.isfile(path):
        sys.exit("%s is missing" % rel)
    img = Image.open(path)
    if img.format != "PNG" or img.size != (1024, 1024):
        sys.exit("%s must be a 1024x1024 PNG (found %s %dx%d)" % (rel, img.format, img.width, img.height))
    rgba = img.convert("RGBA")
    flat = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
    flat.alpha_composite(rgba)
    return flat.convert("RGB")


def generate(env, cfg):
    master = load_master(cfg["master"])
    ios = os.path.join(ROOT, cfg["ios"])
    if not os.path.isfile(os.path.join(ios, "Contents.json")):
        sys.exit("%s/Contents.json is missing" % cfg["ios"])
    for px in IOS_SIZES:
        img = master if px == 1024 else master.resize((px, px), Image.LANCZOS)
        img.save(os.path.join(ios, "%d.png" % px), "PNG", optimize=True)
    for density, px in ANDROID_SIZES.items():
        out = os.path.join(ROOT, cfg["android"], "mipmap-" + density)
        os.makedirs(out, exist_ok=True)
        master.resize((px, px), Image.LANCZOS).save(os.path.join(out, "ic_launcher.jpg"), "JPEG", quality=95, subsampling=0)
    print("%-10s %d iOS + %d Android icons from %s" % (env, len(IOS_SIZES), len(ANDROID_SIZES), cfg["master"]))


if __name__ == "__main__":
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    for env, cfg in ENVIRONMENTS.items():
        generate(env, cfg)
