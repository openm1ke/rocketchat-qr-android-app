#!/usr/bin/env python3
"""Export native launcher resources from the approved School 21 vector artwork.

Normal export needs Pillow. --trace additionally needs OpenCV and NumPy, and is
only used when adopting a new approved raster design. App builds need none of
these tools: all native resources are checked in.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / "assets/branding"
ARTWORK = BRANDING / "school21-artwork.svg"
BACKGROUND = "#111318"
LIME = "#8df86b"
ANDROID_ART_DP = 46.5
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
SVG_NS = "http://www.w3.org/2000/svg"


def number(value):
    return f"{value:.4f}".rstrip("0").rstrip(".") or "0"


def path_data(loops, scale=1.0, offset_x=0.0, offset_y=0.0):
    return " ".join(
        " ".join(
            ("M" if i == 0 else "L")
            + number(x * scale + offset_x) + "," + number(y * scale + offset_y)
            for i, (x, y) in enumerate(loop)
        ) + "Z"
        for _, loop in loops
    )


def trace_approved_raster(source):
    """Vectorize the two foreground colors; never reuse the rejected cutout."""
    import cv2
    import numpy as np

    pixels = np.asarray(Image.open(source).convert("RGB")).astype(int)
    red, green, blue = (pixels[:, :, i] for i in range(3))
    lime_mask = ((green > 170) & (green-red > 35) & (green-blue > 70)).astype("uint8") * 255
    x, y, width, height = cv2.boundingRect(lime_mask)
    white_mask = np.zeros(lime_mask.shape, dtype="uint8")
    white_mask[y:y+height, x:x+width] = (
        (pixels[y:y+height, x:x+width].min(axis=2) > 190).astype("uint8") * 255
    )
    extent = max(width, height)
    pad_x, pad_y = (extent-width)/2, (extent-height)/2
    layers = []
    for color, mask in ((LIME, lime_mask), ("#ffffff", white_mask)):
        contours, hierarchy = cv2.findContours(mask, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)
        loops = []
        for index, contour in enumerate(contours):
            if abs(cv2.contourArea(contour)) < 20:
                continue
            depth, parent = 0, hierarchy[0][index][3]
            while parent >= 0:
                depth += 1
                parent = hierarchy[0][parent][3]
            points = cv2.approxPolyDP(contour, 1.3, True).reshape(-1, 2)
            loops.append((depth, [(float(px-x+pad_x), float(py-y+pad_y)) for px, py in points]))
        layers.append((color, sorted(loops, key=lambda item: item[0])))
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    svg = [f'<svg xmlns="{SVG_NS}" viewBox="0 0 {extent} {extent}">',
           '<title>School 21 approved launcher artwork</title>',
           f'<desc>Vectorized from approved raster. Source SHA-256: {digest}</desc>']
    svg.extend(f'<path fill="{color}" fill-rule="evenodd" d="{path_data(loops)}"/>'
               for color, loops in layers)
    svg.append("</svg>")
    ARTWORK.write_text("\n".join(svg) + "\n", encoding="utf-8")


def read_artwork():
    root = ET.parse(ARTWORK).getroot()
    extent = float(root.attrib["viewBox"].split()[2])
    layers = []
    for path in root.iter(f"{{{SVG_NS}}}path"):
        loops = []
        # Canonical paths contain only straight M/L/Z segments. Use containment
        # to determine hole depth; SVG itself uses the equivalent even-odd rule.
        for segment in path.attrib["d"].split("Z"):
            values = [float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", segment)]
            if values:
                loops.append(list(zip(values[::2], values[1::2])))
        layers.append((path.attrib["fill"], loops))
    return extent, layers


def inside(point, polygon):
    x, y = point
    result = False
    previous = polygon[-1]
    for current in polygon:
        x1, y1 = previous
        x2, y2 = current
        if (y1 > y) != (y2 > y) and x < (x2-x1)*(y-y1)/(y2-y1)+x1:
            result = not result
        previous = current
    return result


def nested_loops(loops):
    return sorted(
        ((sum(inside(loop[0], other) for other in loops if other is not loop), loop)
         for loop in loops), key=lambda item: item[0]
    )


def render(size, artwork_size, background=None, tint=None):
    extent, layers = read_artwork()
    image = Image.new("RGBA", (size, size), background or (0, 0, 0, 0))
    scale, offset = artwork_size/extent, (size-artwork_size)/2
    supersample = 4
    for color, loops in layers:
        mask = Image.new("L", (size*supersample, size*supersample))
        draw = ImageDraw.Draw(mask)
        for depth, loop in nested_loops(loops):
            points = [((px*scale+offset)*supersample, (py*scale+offset)*supersample)
                      for px, py in loop]
            draw.polygon(points, fill=255 if depth % 2 == 0 else 0)
        mask = mask.resize((size, size), Image.Resampling.LANCZOS)
        layer = Image.new("RGBA", (size, size), tint or color)
        layer.putalpha(mask)
        image = Image.alpha_composite(image, layer)
    return image


def shaped(image, shape):
    size = image.width
    mask = Image.new("L", (size*4, size*4))
    draw = ImageDraw.Draw(mask)
    if shape == "circle":
        draw.ellipse((0, 0, size*4-1, size*4-1), fill=255)
    else:
        draw.rounded_rectangle((0, 0, size*4-1, size*4-1), radius=size*4*0.22, fill=255)
    image = image.copy()
    image.putalpha(mask.resize((size, size), Image.Resampling.LANCZOS))
    return image


def adaptive_preview(size, shape="circle", themed=False):
    # Android exposes the central 72dp of the 108dp layer. Its 18dp overscan
    # belongs to the platform; never bake an icon mask into these layers.
    full = render(864, ANDROID_ART_DP*8,
                  background="#e5d8f5" if themed else BACKGROUND,
                  tint="#36234a" if themed else None)
    visible = full.crop((144, 144, 720, 720)).resize((size, size), Image.Resampling.LANCZOS)
    return shaped(visible, shape)


def vector_xml(monochrome=False):
    extent, layers = read_artwork()
    scale = ANDROID_ART_DP/extent
    offset = (108-ANDROID_ART_DP)/2
    result = ['<?xml version="1.0" encoding="utf-8"?>',
              '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
              '    android:width="108dp" android:height="108dp"',
              '    android:viewportWidth="108" android:viewportHeight="108">']
    for color, loops in layers:
        data = path_data([(0, loop) for loop in loops], scale, offset, offset)
        result.append(f'    <path android:fillColor="{"#ffffff" if monochrome else color}" '
                      f'android:fillType="evenOdd" android:pathData="{data}" />')
    result.append("</vector>")
    return "\n".join(result) + "\n"


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def android_icons(resource_root, legacy_webp=False):
    adaptive = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
'''
    for name in ("ic_launcher", "ic_launcher_round"):
        write(resource_root / f"mipmap-anydpi-v26/{name}.xml", adaptive)
    write(resource_root / "drawable/ic_launcher_foreground.xml", vector_xml())
    write(resource_root / "drawable/ic_launcher_monochrome.xml", vector_xml(monochrome=True))
    write(resource_root / "values/ic_launcher_colors.xml",
          '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
          f'    <color name="ic_launcher_background">{BACKGROUND}</color>\n</resources>\n')
    # Replace the old Android Studio grid resource when it is present, too.
    old_background = resource_root / "drawable/ic_launcher_background.xml"
    if old_background.exists():
        write(old_background, '<?xml version="1.0" encoding="utf-8"?>\n'
              '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">\n'
              '    <solid android:color="@color/ic_launcher_background" />\n</shape>\n')
    for density, size in DENSITIES.items():
        folder = resource_root / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        normal = shaped(render(size*4, size*4*0.75, BACKGROUND), "rounded")
        rounded = adaptive_preview(size*4, "circle")
        for name, image in (("ic_launcher", normal), ("ic_launcher_round", rounded)):
            image = image.resize((size, size), Image.Resampling.LANCZOS)
            if legacy_webp:
                image.save(folder / f"{name}.webp", lossless=True)
            else:
                image.save(folder / f"{name}.png", optimize=True)


def preview(master):
    board = Image.new("RGB", (1680, 980), "#f1f2f5")
    draw = ImageDraw.Draw(board)
    def font(size, bold=False):
        candidates = [f'/System/Library/Fonts/Supplemental/Arial{" Bold" if bold else ""}.ttf',
                      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']
        for candidate in candidates:
            if Path(candidate).exists():
                return ImageFont.truetype(candidate, size)
        return ImageFont.load_default(size=size)
    draw.text((70, 52), "Campus Pass / School 21", fill=BACKGROUND, font=font(42, True))
    items = [("Android / round", adaptive_preview(280)),
             ("Android / rounded", adaptive_preview(280, "rounded")),
             ("iOS", shaped(master.resize((280, 280), Image.Resampling.LANCZOS), "rounded")),
             ("Android / themed", adaptive_preview(280, themed=True))]
    for i, (label, icon) in enumerate(items):
        x = 70+i*400
        board.paste(icon, (x, 170), icon)
        draw.text((x, 480), label, fill=BACKGROUND, font=font(24, True))
        for j, size in enumerate((48, 72, 96)):
            mini = (shaped(master.resize((size, size), Image.Resampling.LANCZOS), "rounded")
                    if i == 2 else adaptive_preview(size, "rounded" if i == 1 else "circle", i == 3))
            left, top = x+j*102, 630+(96-size)//2
            board.paste(mini, (left, top), mini)
            draw.text((left, 758), str(size)+" px", fill="#555c6b", font=font(19))
    draw.text((70, 870), "21 + SCHOOL", fill=BACKGROUND, font=font(28, True))
    board.save(BRANDING / "app-icons-preview.png", optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace", type=Path, help="Adopt a newly approved raster source")
    args = parser.parse_args()
    BRANDING.mkdir(parents=True, exist_ok=True)
    if args.trace:
        trace_approved_raster(args.trace.resolve())
    extent, layers = read_artwork()
    max_radius = max(math.hypot(x-extent/2, y-extent/2) for _, loops in layers for loop in loops
                     for x, y in loop) * ANDROID_ART_DP/extent
    assert max_radius < 33, "Artwork must fit the Android 66dp safe-zone circle"
    master = render(1024, 768, BACKGROUND).convert("RGB")
    master.save(BRANDING / "app-icon-1024.png", optimize=True)
    master.resize((512, 512), Image.Resampling.LANCZOS).save(BRANDING / "play-store-icon-512.png", optimize=True)
    render(1024, 768).save(BRANDING / "app-icon-foreground.png", optimize=True)
    paths = "\n".join(
        f'<path fill="{color}" fill-rule="evenodd" d="{path_data([(0, loop) for loop in loops])}"/>'
        for color, loops in layers
    )
    write(BRANDING / "app-icon.svg",
          f'<svg xmlns="{SVG_NS}" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
          '<title>Campus Pass — School 21</title>\n'
          f'<rect width="1024" height="1024" fill="{BACKGROUND}"/>\n'
          f'<g transform="translate(128 128) scale({number(768/extent)})">\n{paths}\n</g>\n</svg>\n')
    android_icons(ROOT / "flutter_client/android/app/src/main/res")
    android_icons(ROOT / "app/src/main/res", legacy_webp=True)
    ios = ROOT / "flutter_client/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((ios / "Contents.json").read_text())
    expected_ios = {}
    for image in contents["images"]:
        points = float(image["size"].split("x")[0])
        scale = float(image["scale"].removesuffix("x"))
        size = round(points*scale)
        expected_ios[image["filename"]] = size
        master.resize((size, size), Image.Resampling.LANCZOS).save(ios / image["filename"], optimize=True)
    for filename, size in expected_ios.items():
        with Image.open(ios / filename) as icon:
            assert icon.size == (size, size) and icon.mode == "RGB", filename
    for base, extension in (("flutter_client/android/app/src/main/res", "png"), ("app/src/main/res", "webp")):
        for density, size in DENSITIES.items():
            for name in ("ic_launcher", "ic_launcher_round"):
                with Image.open(ROOT / base / f"mipmap-{density}/{name}.{extension}") as icon:
                    assert icon.size == (size, size)
        for path in (ROOT / base).rglob("ic_launcher*.xml"):
            ET.parse(path)
    preview(master)
    report = {"artwork": str(ARTWORK.relative_to(ROOT)),
              "artwork_sha256": hashlib.sha256(ARTWORK.read_bytes()).hexdigest(),
              "android_layer_dp": 108, "android_artwork_dp": ANDROID_ART_DP,
              "android_max_foreground_radius_dp": round(max_radius, 4),
              "android_safe_zone_radius_dp": 33, "android_densities": DENSITIES,
              "ios_sizes": expected_ios,
              "checks": {"adaptive_safe_zone": True, "ios_dimensions_and_opaque_rgb": True,
                         "android_dimensions": True, "android_xml_parses": True}}
    write(BRANDING / "icon-resources.json", json.dumps(report, indent=2)+"\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
