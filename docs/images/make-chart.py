#!/usr/bin/env python3
"""Writes fps-light.svg and fps-dark.svg, the README's frame-rate chart (docs/performance.md's numbers).
Colors: the validated categorical slots 1 and 2 (blue, orange) for each mode's surface."""
import os

ROWS = [  # label, before (Reims 2ce3209), after (macbox build, mean of two runs)
    ("1x · 402×874", 53.5, (95.8 + 92.5) / 2),
    ("2x · 804×1748", 33.5, (67.8 + 60.5) / 2),
    ("3x · 1206×2622", 17.2, (38.5 + 39.5) / 2),
]
MODES = {
    "light": dict(surface="#fcfcfb", text="#0b0b0b", text2="#52514e", grid="#e4e3df", before="#eb6834", after="#2a78d6"),
    "dark": dict(surface="#1a1a19", text="#f0efec", text2="#c3c2b7", grid="#3a3a37", before="#d95926", after="#3987e5"),
}
W, H = 900, 370
X0, X1, MAX = 190, 840, 100          # bar area and its scale (fps)
BAR, GAP, GROUP = 22, 2, 30          # bar thickness, gap between a group's bars, space between groups
TOP = 112
FONT = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"

def x(v): return X0 + (X1 - X0) * v / MAX

def bar(y, v, color):  # 4 px rounded at the data end only, square at the baseline
    w, r = x(v) - X0, 4
    return (f'<path d="M{X0},{y} H{X0 + w - r} Q{X0 + w},{y} {X0 + w},{y + r} V{y + BAR - r} '
            f'Q{X0 + w},{y + BAR} {X0 + w - r},{y + BAR} H{X0} Z" fill="{color}"/>')

def svg(m):
    c = MODES[m]
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="{FONT}">',
         f'<rect width="{W}" height="{H}" rx="12" fill="{c["surface"]}"/>',
         f'<text x="24" y="38" font-size="19" font-weight="600" fill="{c["text"]}">iOS Simulator frame rate, Liquid Glass benchmark</text>',
         f'<text x="24" y="62" font-size="13.5" fill="{c["text2"]}">Frames per second on an Intel Arrow Lake iGPU (Core Ultra 7 265). Higher is better.</text>']
    # legend
    lx = 24
    for name, col in (("Reims vGPU as upstream shipped it (2ce3209)", c["before"]), ("macbox build", c["after"])):
        o.append(f'<rect x="{lx}" y="80" width="12" height="12" rx="3" fill="{col}"/>')
        o.append(f'<text x="{lx + 18}" y="91" font-size="13" fill="{c["text2"]}">{name}</text>')
        lx += 18 + len(name) * 7.0 + 26
    # grid and axis
    bottom = TOP + len(ROWS) * (2 * BAR + GAP) + (len(ROWS) - 1) * GROUP
    for v in (0, 20, 40, 60, 80, 100):
        o.append(f'<line x1="{x(v):.1f}" y1="{TOP - 6}" x2="{x(v):.1f}" y2="{bottom + 6}" stroke="{c["grid"]}" stroke-width="1"/>')
        o.append(f'<text x="{x(v):.1f}" y="{bottom + 24}" font-size="12" text-anchor="middle" fill="{c["text2"]}">{v}</text>')
    o.append(f'<text x="{X1}" y="{bottom + 42}" font-size="12" text-anchor="end" fill="{c["text2"]}">frames per second</text>')
    # the 60 fps target
    o.append(f'<line x1="{x(60):.1f}" y1="{TOP - 14}" x2="{x(60):.1f}" y2="{bottom + 6}" stroke="{c["text2"]}" stroke-width="1.5" stroke-dasharray="4 4"/>')
    o.append(f'<text x="{x(60) + 6:.1f}" y="{TOP - 6}" font-size="12" fill="{c["text2"]}">60 fps</text>')
    y = TOP
    for label, before, after in ROWS:
        o.append(f'<text x="{X0 - 14}" y="{y + BAR + GAP / 2 + 5}" font-size="13.5" text-anchor="end" fill="{c["text"]}">{label}</text>')
        for v, col in ((before, c["before"]), (after, c["after"])):
            o.append(bar(y, v, col))
            o.append(f'<text x="{x(v) + 8:.1f}" y="{y + BAR / 2 + 4.5}" font-size="13" fill="{c["text"]}">{v:.1f}</text>')
            y += BAR + GAP
        y += GROUP - GAP
    o.append("</svg>")
    return "\n".join(o) + "\n"

here = os.path.dirname(os.path.abspath(__file__))
for m in MODES:
    open(os.path.join(here, f"fps-{m}.svg"), "w").write(svg(m))
