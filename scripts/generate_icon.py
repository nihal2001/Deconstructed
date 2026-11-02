#!/usr/bin/env python3
"""Draws the app icon: the score ring, pulled apart into its four parts.

Run from the repo root: python3 scripts/generate_icon.py (needs Pillow).
"""
import math

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4  # drawn large, then reduced, for smooth edges
OUTPUT = "Deconstructed/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

JET = (20, 54, 66)
ROSE = (214, 87, 128)
OLIVE = (145, 151, 42)
SEAGRASS = (81, 158, 138)
ALABASTER = (234, 230, 229)

# (start angle, sweep, colour). The sweeps are 4, 3, 2 and 1 tenths of the ring, like a
# rubric whose maximums total 10.
GAP = 6
SEGMENTS = [
    (-90, 144, ROSE),
    (54, 108, SEAGRASS),
    (162, 72, OLIVE),
    (234, 36, ALABASTER),
]


def glow(canvas, centre, radius, colour, strength):
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    x, y = centre
    ImageDraw.Draw(layer).ellipse((x - radius, y - radius, x + radius, y + radius), fill=(*colour, strength))
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius * 0.55)))


def segment(draw, centre, radius, width, start, sweep, colour):
    """An arc nudged out from the centre, so the parts stand apart."""
    middle = math.radians(start + sweep / 2)
    cx = centre + math.cos(middle) * 34 * SCALE
    cy = centre + math.sin(middle) * 34 * SCALE
    box = (cx - radius, cy - radius, cx + radius, cy + radius)
    draw.arc(box, start + GAP / 2, start + sweep - GAP / 2, fill=colour, width=width)


def main():
    size = SIZE * SCALE
    canvas = Image.new("RGBA", (size, size), (*JET, 255))
    glow(canvas, (size * 0.2, size * 0.15), size * 0.45, ROSE, 70)
    glow(canvas, (size * 0.85, size * 0.9), size * 0.5, SEAGRASS, 80)

    draw = ImageDraw.Draw(canvas)
    for start, sweep, colour in SEGMENTS:
        segment(draw, size / 2, 310 * SCALE, 120 * SCALE, start, sweep, colour)

    canvas.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(OUTPUT, optimize=True)


if __name__ == "__main__":
    main()
