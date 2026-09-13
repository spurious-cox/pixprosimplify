#!/usr/bin/env python3
"""
pixpro_simplify_engine.py - analysis + reduction engine for PixProSimplify.

Two modes:
  analyze <in.svg>            -> prints 3 lines: "LABEL|epsilon|points|pct" for
                                 min / mean / max reduction, auto-estimated per
                                 shape via the error-elbow method (deviation of
                                 the reduced curve from the original, normalized
                                 by the bounding-box diagonal).
  reduce  <in.svg> <out.svg> <epsilon>

Reduction itself is delegated to ~/bin/pixpro_reduce.py (RDP on Bezier anchors,
original handles preserved, closed-loop aware).

Created by: Claude (Anthropic) for Tim McCoy
Date: 2026-07-15
Version 1.1 (2026-07-16): strip hidden elements on load. Pixelmator Pro's SVG
  export INCLUDES hidden layers (tagged visibility="hidden"), so analyze was
  counting the applet's soloed-away layers and reduce kept them in the output
  (making the reimported "layer 1" potentially the wrong layer).
"""
import sys, os, re, math
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.expanduser("~/bin"))
import pixpro_reduce as R   # parse_subpaths, rebuild, tokenize

# error thresholds as fraction of bbox diagonal (calibrated 2026-07-15 against
# the elbow of the count-vs-deviation curve, verified visually flawless).
ERR_MIN = 0.0006   # near-lossless      -> "Min reduction" (most points kept)
ERR_MAX = 0.0030   # elbow / optimum    -> "Max reduction" (fewest points, still faithful)


def strip_hidden(svg):
    """Return the SVG text with every hidden element removed (visibility=
    "hidden", display="none", or the style-attribute equivalents), pruning
    whole hidden groups. Pixelmator Pro exports hidden layers this way."""
    ET.register_namespace('', 'http://www.w3.org/2000/svg')
    ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')
    root = ET.fromstring(svg)

    def hidden(el):
        if el.get('visibility') == 'hidden' or el.get('display') == 'none':
            return True
        style = el.get('style') or ''
        return bool(re.search(r'visibility\s*:\s*hidden|display\s*:\s*none', style))

    def prune(parent):
        for child in list(parent):
            if hidden(child):
                parent.remove(child)
            else:
                prune(child)

    prune(root)
    return ET.tostring(root, encoding='unicode')


def all_paths(svg):
    return re.findall(r'<path[^>]*\sd="([^"]*)"', svg)


def flatten(d, per=4):
    """Flatten a path's cubic beziers to sample points (list of (x,y))."""
    pts = []
    for anchors in R.parse_subpaths(d):
        for a, b in zip(anchors, anchors[1:]):
            p0, p1, p2, p3 = a['p'], a['out'], b['in'], b['p']
            for i in range(per + 1):
                t = i / per
                mt = 1 - t
                x = (mt**3*p0[0] + 3*mt*mt*t*p1[0] + 3*mt*t*t*p2[0] + t**3*p3[0])
                y = (mt**3*p0[1] + 3*mt*mt*t*p1[1] + 3*mt*t*t*p2[1] + t**3*p3[1])
                pts.append((x, y))
    return pts


def bbox_diag(pts):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    if not xs:
        return 1.0
    return math.hypot(max(xs)-min(xs), max(ys)-min(ys)) or 1.0


def reduce_svg_text(svg, eps):
    def repl(m):
        d = m.group(1)
        return m.group(0).replace(d, R.rebuild(R.parse_subpaths(d), eps))
    return re.sub(r'<path[^>]*\sd="([^"]*)"', repl, svg)


def count_cmds(svg):
    return sum(len(re.findall(r'[MmLlHhVvCcSsQqTtAaZz]', d)) for d in all_paths(svg))


def _seg_d2(px, py, ax, ay, bx, by):
    """Squared distance from point (px,py) to segment (a)-(b)."""
    dx, dy = bx-ax, by-ay
    L2 = dx*dx + dy*dy
    if L2 == 0:
        return (px-ax)**2 + (py-ay)**2
    t = ((px-ax)*dx + (py-ay)*dy) / L2
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    cx, cy = ax + t*dx, ay + t*dy
    return (px-cx)**2 + (py-cy)**2


def max_error(orig_samples, reduced_svg, diag, cap=400):
    """Directed max distance from a capped subset of original samples to the
    reduced curve (nearest point-to-SEGMENT, so it's sampling-independent),
    normalized by diag."""
    segs = []
    for d in all_paths(reduced_svg):
        pts = flatten(d, per=6)
        segs += list(zip(pts, pts[1:]))
    if not segs:
        return 1.0
    step = max(1, len(orig_samples)//cap)
    worst = 0.0
    for i in range(0, len(orig_samples), step):
        px, py = orig_samples[i]
        best = min(_seg_d2(px, py, a[0], a[1], b[0], b[1]) for a, b in segs)
        if best > worst:
            worst = best
    return math.sqrt(worst) / diag


def analyze(svg):
    orig_cmds = count_cmds(svg)
    orig_samples = []
    for d in all_paths(svg):
        orig_samples += flatten(d, per=3)
    diag = bbox_diag(orig_samples)

    # sweep epsilon (in shape units) as fractions of the diagonal, log-spaced
    sweep = []
    for k in [0.00005, 0.0001, 0.0002, 0.0004, 0.0008, 0.0015,
              0.003, 0.006, 0.012, 0.025]:
        eps = k * diag
        rsvg = reduce_svg_text(svg, eps)
        sweep.append((eps, count_cmds(rsvg),
                      max_error(orig_samples, rsvg, diag)))

    def eps_for_error(target):
        chosen = sweep[0][0]
        for eps, cnt, err in sweep:
            if err <= target:
                chosen = eps
        return chosen

    eps_min = eps_for_error(ERR_MIN)
    eps_max = eps_for_error(ERR_MAX)
    if eps_max < eps_min:
        eps_max = eps_min
    eps_mean = math.sqrt(eps_min * eps_max)

    out = []
    for label, eps in [("Min reduction (highest fidelity)", eps_min),
                       ("Mean reduction (balanced)",        eps_mean),
                       ("Max reduction (optimum)",          eps_max)]:
        cnt = count_cmds(reduce_svg_text(svg, eps))
        pct = round(100 * (1 - cnt / orig_cmds)) if orig_cmds else 0
        out.append(f"{label}|{eps:.4f}|{cnt}|{pct}")
    # prepend original for reference
    print(f"Original|0|{orig_cmds}|0")
    for line in out:
        print(line)


def main():
    a = sys.argv
    if len(a) == 3 and a[1] == "analyze":
        analyze(strip_hidden(open(a[2]).read()))
    elif len(a) == 5 and a[1] == "reduce":      # reduce <in> <out> <epsilon>
        open(a[3], "w").write(
            reduce_svg_text(strip_hidden(open(a[2]).read()), float(a[4])))
    else:
        print("usage: analyze <in.svg>  |  reduce <in.svg> <out.svg> <epsilon>",
              file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
