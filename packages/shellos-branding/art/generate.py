#!/usr/bin/env python3
"""Generate ShellOS artwork as SVG.

The mark is a golden logarithmic spiral, r = a * phi^(2*theta/pi), which is
the curve a nautilus shell approximates, with radial septa between
successive whorls standing in for the shell's chambers.

Usage: generate.py OUTDIR
Writes logo.svg, logo-mono.svg, wallpaper.svg, plymouth-logo.svg.
"""
import math
import sys
from pathlib import Path

PHI = (1 + 5 ** 0.5) / 2
ACCENT = "#2EC4B6"
ACCENT_DEEP = "#1A7F76"
BG_TOP = "#0B1416"
BG_BOTTOM = "#050809"
FG = "#E6F4F2"


def radius(theta, a):
    return a * PHI ** (2 * theta / math.pi)


def point(theta, a, cx, cy):
    r = radius(theta, a)
    return cx + r * math.cos(theta), cy - r * math.sin(theta)


def spiral_path(cx, cy, a, t0, t1, steps=480):
    pts = [point(t0 + (t1 - t0) * i / steps, a, cx, cy) for i in range(steps + 1)]
    return "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in pts)


def septa(cx, cy, a, t0, t1, every=math.pi / 4):
    """Radial chamber walls between whorl theta and whorl theta - 2pi."""
    lines = []
    t = t1
    while t - 2 * math.pi >= t0:
        x1, y1 = point(t, a, cx, cy)
        x2, y2 = point(t - 2 * math.pi, a, cx, cy)
        lines.append(f"M{x1:.2f},{y1:.2f} L{x2:.2f},{y2:.2f}")
        t -= every
    return " ".join(lines)


def mark(cx, cy, size, stroke, colour, septa_colour, septa_opacity):
    """Spiral scaled and centred so its bounding box is `size` wide/high."""
    t0, t1 = -3 * math.pi, 2.25 * math.pi
    pts = [point(t0 + (t1 - t0) * i / 960, 1, 0, 0) for i in range(961)]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    a = size / max(max(xs) - min(xs), max(ys) - min(ys))
    cx -= a * (max(xs) + min(xs)) / 2
    cy -= a * (max(ys) + min(ys)) / 2
    return (
        f'<path d="{septa(cx, cy, a, t0 + 2 * math.pi, t1)}" fill="none" '
        f'stroke="{septa_colour}" stroke-opacity="{septa_opacity}" '
        f'stroke-width="{stroke * 0.55:.2f}" stroke-linecap="round"/>\n'
        f'<path d="{spiral_path(cx, cy, a, t0, t1)}" fill="none" '
        f'stroke="{colour}" stroke-width="{stroke:.2f}" '
        f'stroke-linecap="round" stroke-linejoin="round"/>\n'
    )


def svg(w, h, body, defs=""):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}">\n<defs>{defs}</defs>\n{body}</svg>\n'
    )


def main(out):
    out.mkdir(parents=True, exist_ok=True)

    grad = (
        f'<linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{ACCENT}"/>'
        f'<stop offset="1" stop-color="{ACCENT_DEEP}"/></linearGradient>'
    )
    (out / "logo.svg").write_text(
        svg(512, 512, mark(256, 256, 420, 24, "url(#g)", ACCENT, 0.55), grad)
    )
    (out / "logo-mono.svg").write_text(
        svg(512, 512, mark(256, 256, 420, 24, FG, FG, 0.5))
    )
    (out / "plymouth-logo.svg").write_text(
        svg(256, 256, mark(128, 128, 200, 10, ACCENT, ACCENT, 0.45))
    )

    w, h = 3840, 2160
    bg = (
        f'<linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">'
        f'<stop offset="0" stop-color="{BG_TOP}"/>'
        f'<stop offset="1" stop-color="{BG_BOTTOM}"/></linearGradient>'
        f'<radialGradient id="glow" cx="0.68" cy="0.55" r="0.45">'
        f'<stop offset="0" stop-color="{ACCENT}" stop-opacity="0.10"/>'
        f'<stop offset="1" stop-color="{ACCENT}" stop-opacity="0"/></radialGradient>'
    )
    body = (
        f'<rect width="{w}" height="{h}" fill="url(#bg)"/>\n'
        f'<rect width="{w}" height="{h}" fill="url(#glow)"/>\n'
        f'<g opacity="0.16">{mark(w * 0.68, h * 0.55, h * 0.95, 8, ACCENT, ACCENT, 0.6)}</g>\n'
    )
    (out / "wallpaper.svg").write_text(svg(w, h, body, bg))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(Path(sys.argv[1]))
