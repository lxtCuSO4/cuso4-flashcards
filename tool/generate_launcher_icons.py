"""Generate deterministic Android icons from the user-supplied artwork.

Run from any directory: python tool/generate_launcher_icons.py
Requires Pillow. The original file is preserved; derived assets share one framing.
Adaptive layers follow https://developer.android.com/develop/ui/compose/system/icon_design_adaptive
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageOps


ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android/app/src/main/res"
SOURCE = ROOT / "assets/branding/launcher-source.jpg"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
VIEWPORT_DP = 72
ART_DP = 64


def centered(art, canvas_size, art_size, background):
    canvas = Image.new("RGBA", (canvas_size, canvas_size), background)
    fitted = ImageOps.contain(art, (art_size, art_size), Image.Resampling.NEAREST)
    canvas.alpha_composite(fitted, ((canvas_size - fitted.width) // 2, (canvas_size - fitted.height) // 2))
    return canvas


def masked(image, circle):
    mask = Image.new("L", image.size)
    draw = ImageDraw.Draw(mask)
    box = (0, 0, image.width - 1, image.height - 1)
    if circle:
        draw.ellipse(box, fill=255)
    else:
        draw.rounded_rectangle(box, radius=image.width * 0.24, fill=255)
    result = image.copy()
    result.putalpha(mask)
    return result


def main():
    art = ImageOps.exif_transpose(Image.open(SOURCE)).convert("RGBA")
    for density, scale in DENSITIES.items():
        mipmap = RES / f"mipmap-{density}"
        drawable = RES / f"drawable-{density}"
        mipmap.mkdir(parents=True, exist_ok=True)
        drawable.mkdir(parents=True, exist_ok=True)
        # Enlarge the character while keeping room around the top/bottom.
        # Inspect the preview masks: launchers can crop outside the safe circle.
        foreground = centered(art, round(108 * scale), round(ART_DP * scale), (0, 0, 0, 0))
        foreground.save(drawable / "ic_launcher_foreground.png", optimize=True)
        legacy = centered(art, round(48 * scale), round(48 * ART_DP / VIEWPORT_DP * scale), "white")
        legacy.convert("RGB").save(mipmap / "ic_launcher.png", optimize=True)
        masked(legacy, circle=True).save(mipmap / "ic_launcher_round.png", optimize=True)

    preview_dir = ROOT / "assets/branding"
    # A small bundled asset uses the same composition as the launcher viewport.
    centered(art, 256, round(256 * ART_DP / VIEWPORT_DP), "white").save(
        preview_dir / "app-logo.png", optimize=True
    )
    # Preview the 72dp adaptive viewport, including the launcher mask.
    viewport = centered(art, 432, round(432 * ART_DP / VIEWPORT_DP), "white")
    sheet = Image.new("RGB", (1008, 552), "#e8e5f0")
    draw = ImageDraw.Draw(sheet)
    for index, circle in enumerate((True, False)):
        icon = masked(viewport, circle)
        sheet.paste(icon, (36 + index * 504, 36), icon)
        draw.text((36 + index * 504, 492), "Lunar Memory", fill="#30253d", font_size=28)
    sheet.save(preview_dir / "launcher-preview.png", optimize=True)
    print(f"Generated 5 launcher densities and adaptive layers from {art.width}x{art.height} source.")
    print(preview_dir / "launcher-preview.png")


if __name__ == "__main__":
    main()
