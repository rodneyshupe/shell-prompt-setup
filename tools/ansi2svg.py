#!/usr/bin/env python3
"""Turn captured prompt output (ANSI colors) into a terminal-style SVG and a plain-text version.

Used by tools/render-examples.sh; the prompts are real output, not mock-ups. Python 3, standard library only.

  ansi2svg.py --title "..." --svg out.svg --txt out.txt  name1.ans "caption 1"  name2.ans "caption 2" ...

Powerline separators (private-use glyphs U+E0B0..E0B3) are drawn as shapes in the SVG, so the image does not
depend on any font; in the plain text they become ▶ › ◀ ‹. Everything else is text at fixed cell positions.
"""
import argparse
import html
import re
import sys

CW, LH, FS = 8.4, 18, 14           # cell width, line height, font size (px); a terminal row is about 1.3 x the font size
PAD = 18
BG_PANEL = "#1e1e1e"
FG_DEFAULT = "#d4d4d4"
CAPTION = "#8b8b8b"
MONO = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'DejaVu Sans Mono', monospace"

BASE16 = ["#000000", "#cd3131", "#0dbc79", "#e5e510", "#2472c8", "#bc3fbc", "#11a8cd", "#e5e5e5",
          "#666666", "#f14c4c", "#23d18b", "#f5f543", "#3b8eea", "#d670d6", "#29b8db", "#ffffff"]
PL_PLAIN = {"": "▶", "": "›", "": "◀", "": "‹"}
SGR = re.compile(r"\x1b\[([0-9;]*)m")
WRAP = re.compile(r"%\{|%\}|\\\[|\\\]")


def color256(n):
    if n < 16:
        return BASE16[n]
    if n < 232:
        n -= 16
        r, g, b = n // 36, (n // 6) % 6, n % 6
        lv = lambda v: 0 if v == 0 else 55 + 40 * v
        return "#%02x%02x%02x" % (lv(r), lv(g), lv(b))
    v = 8 + 10 * (n - 232)
    return "#%02x%02x%02x" % (v, v, v)


def parse_line(line):
    """-> list of (char, fg, bg, bold); fg/bg None = default."""
    line = WRAP.sub("", line).replace(chr(0xa0), " ").replace(chr(0xe0a0), chr(0x2387))   # NBSP -> space, branch glyph -> ⎇
    fg = bg = None
    bold = False
    out = []
    pos = 0
    for m in SGR.finditer(line):
        for ch in line[pos:m.start()]:
            out.append((ch, fg, bg, bold))
        pos = m.end()
        p = [int(x) if x else 0 for x in m.group(1).split(";")] if m.group(1) else [0]
        i = 0
        while i < len(p):
            c = p[i]
            if c == 0:
                fg = bg = None; bold = False
            elif c == 1:
                bold = True
            elif c == 22:
                bold = False
            elif 30 <= c <= 37:
                fg = BASE16[c - 30]
            elif c == 39:
                fg = None
            elif 40 <= c <= 47:
                bg = BASE16[c - 40]
            elif c == 49:
                bg = None
            elif 90 <= c <= 97:
                fg = BASE16[c - 90 + 8]
            elif 100 <= c <= 107:
                bg = BASE16[c - 100 + 8]
            elif c in (38, 48) and i + 1 < len(p):
                if p[i + 1] == 5 and i + 2 < len(p):
                    col = color256(p[i + 2]); i += 2
                elif p[i + 1] == 2 and i + 4 < len(p):
                    col = "#%02x%02x%02x" % (p[i + 2], p[i + 3], p[i + 4]); i += 4
                else:
                    col = None
                if col:
                    if c == 38: fg = col
                    else: bg = col
            i += 1
    for ch in line[pos:]:
        out.append((ch, fg, bg, bold))
    return out


def plain(cells):
    s = "".join({chr(0xe0b6): chr(0x25d6), chr(0xe0b4): chr(0x25d7)}.get(c[0], PL_PLAIN.get(c[0], c[0])) for c in cells)
    return s.rstrip()


def runs(cells):
    """group consecutive cells with the same style -> (col, text, fg, bg, bold)"""
    res, col = [], 0
    cur = None
    for ch, fg, bg, bold in cells:
        key = (fg, bg, bold)
        if cur and cur[0] == key:
            cur[1].append(ch)
        else:
            if cur: res.append((cur[2], "".join(cur[1]), *cur[0]))
            cur = [key, [ch], col]
        col += 1
    if cur: res.append((cur[2], "".join(cur[1]), *cur[0]))
    return res


# Box-drawing characters are drawn as lines that span the whole cell, the way a terminal draws them, so the
# strokes of two rows meet (a font glyph stops short of the cell edge and leaves a gap).
BOX = {chr(c) for c in (0x2500, 0x2502, 0x250c, 0x2510, 0x2514, 0x2518, 0x256d, 0x256e, 0x256f, 0x2570)}
CAPS = {chr(0xe0b6), chr(0xe0b4)}          # Powerline rounded caps, full cell height
HALF = {chr(0x25d6), chr(0x25d7)}       # half circles used as rounded block ends: drawn as shapes, whatever the font


def box_shape(ch, x, y, color):
    c = ord(ch)
    cx, my, r = x + CW / 2, y + LH / 2, 4.0
    top, bottom, left, right = y, y + LH, x, x + CW
    if c == 0x2500:                      # horizontal
        d = "M%.2f %.2f H%.2f" % (left, my, right)
    elif c == 0x2502:                    # vertical
        d = "M%.2f %.2f V%.2f" % (cx, top, bottom)
    elif c in (0x250c, 0x256d):          # right + down (square, rounded)
        d = ("M%.2f %.2f H%.2f V%.2f" % (right, my, cx, bottom)) if c == 0x250c else ("M%.2f %.2f H%.2f Q%.2f %.2f %.2f %.2f V%.2f" % (right, my, cx + r, cx, my, cx, my + r, bottom))
    elif c in (0x2510, 0x256e):          # left + down
        d = ("M%.2f %.2f H%.2f V%.2f" % (left, my, cx, bottom)) if c == 0x2510 else ("M%.2f %.2f H%.2f Q%.2f %.2f %.2f %.2f V%.2f" % (left, my, cx - r, cx, my, cx, my + r, bottom))
    elif c in (0x2514, 0x2570):          # right + up
        d = ("M%.2f %.2f H%.2f V%.2f" % (right, my, cx, top)) if c == 0x2514 else ("M%.2f %.2f H%.2f Q%.2f %.2f %.2f %.2f V%.2f" % (right, my, cx + r, cx, my, cx, my - r, top))
    else:                                # left + up
        d = ("M%.2f %.2f H%.2f V%.2f" % (left, my, cx, top)) if c == 0x2518 else ("M%.2f %.2f H%.2f Q%.2f %.2f %.2f %.2f V%.2f" % (left, my, cx - r, cx, my, cx, my - r, top))
    return '<path d="%s" fill="none" stroke="%s" stroke-width="1.4"/>' % (d, color)


def draw_line(cells, y):
    """-> svg fragments for one prompt line whose top is at y"""
    frag = []
    # backgrounds first
    for col, text, fg, bg, bold in runs(cells):
        if bg:
            frag.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%d" fill="%s"/>' % (PAD + col * CW, y, len(text) * CW, LH, bg))
    for col, text, fg, bg, bold in runs(cells):
        x = PAD + col * CW
        # split the run at Powerline glyphs: shapes for those, text for the rest
        i = 0
        while i < len(text):
            ch = text[i]
            if ch in CAPS:
                gx = x + i * CW
                if ch == chr(0xe0b6):               # left cap: half ellipse, flat edge on the right, full height
                    d = "M%.2f %.2f A%.2f %.2f 0 0 0 %.2f %.2f Z" % (gx + CW, y, CW, LH / 2, gx + CW, y + LH)
                else:                               # right cap
                    d = "M%.2f %.2f A%.2f %.2f 0 0 1 %.2f %.2f Z" % (gx, y, CW, LH / 2, gx, y + LH)
                frag.append('<path d="%s" fill="%s"/>' % (d, fg or FG_DEFAULT))
                i += 1
                continue
            if ch in HALF:
                gx, rad = x + i * CW, (LH - 4) / 2
                if ch == chr(0x25d6):               # left half disc, flat edge on the right
                    d = "M%.2f %.2f A%.2f %.2f 0 0 0 %.2f %.2f Z" % (gx + CW, y + 2, rad, rad, gx + CW, y + LH - 2)
                else:                               # right half disc, flat edge on the left
                    d = "M%.2f %.2f A%.2f %.2f 0 0 1 %.2f %.2f Z" % (gx, y + 2, rad, rad, gx, y + LH - 2)
                frag.append('<path d="%s" fill="%s"/>' % (d, fg or FG_DEFAULT))
                i += 1
                continue
            if ch in BOX:
                frag.append(box_shape(ch, x + i * CW, y, fg or FG_DEFAULT))
                i += 1
                continue
            if ch in PL_PLAIN:
                gx = x + i * CW
                color = fg or FG_DEFAULT
                if ch == "":
                    frag.append('<polygon points="%.2f,%.2f %.2f,%.2f %.2f,%.2f" fill="%s"/>' % (gx, y, gx + CW, y + LH / 2, gx, y + LH, color))
                elif ch == "":
                    frag.append('<polygon points="%.2f,%.2f %.2f,%.2f %.2f,%.2f" fill="%s"/>' % (gx + CW, y, gx, y + LH / 2, gx + CW, y + LH, color))
                elif ch == "":
                    frag.append('<polyline points="%.2f,%.2f %.2f,%.2f %.2f,%.2f" fill="none" stroke="%s" stroke-width="1.2"/>' % (gx, y, gx + CW, y + LH / 2, gx, y + LH, color))
                else:
                    frag.append('<polyline points="%.2f,%.2f %.2f,%.2f %.2f,%.2f" fill="none" stroke="%s" stroke-width="1.2"/>' % (gx + CW, y, gx, y + LH / 2, gx + CW, y + LH, color))
                i += 1
                continue
            j = i
            while j < len(text) and text[j] not in PL_PLAIN and text[j] not in BOX and text[j] not in HALF and text[j] not in CAPS:
                j += 1
            seg = text[i:j]
            if seg.strip():
                frag.append('<text x="%.2f" y="%.2f" fill="%s"%s textLength="%.2f" lengthAdjust="spacingAndGlyphs" xml:space="preserve">%s</text>'
                            % (x + i * CW, y + LH - 5, fg or FG_DEFAULT, ' font-weight="700"' if bold else "", len(seg) * CW, html.escape(seg)))
            i = j
    return frag


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--title", default="")
    ap.add_argument("--svg", required=True)
    ap.add_argument("--txt", required=True)
    ap.add_argument("pairs", nargs="+", help="file.ans 'caption' ...")
    a = ap.parse_args()
    if len(a.pairs) % 2:
        sys.exit("need pairs of: file caption")

    blocks = []
    for f, cap in zip(a.pairs[0::2], a.pairs[1::2]):
        raw = open(f, encoding="utf-8").read().replace("\r", "")
        lines = [l for l in raw.split("\n") if l.strip() != ""]
        blocks.append((cap, [parse_line(l) for l in lines]))

    # wide enough for the longest prompt line and for the captions (12px sans text is about 0.75 of a terminal cell per character)
    cols = max(max(len(l) for _, ls in blocks for l in ls), max(int(len(cap) * 0.75) for cap, _ in blocks)) + 4
    width = PAD * 2 + cols * CW
    y = 44                                    # below the title bar
    body, txt = [], []
    for cap, ls in blocks:
        body.append('<text x="%d" y="%d" fill="%s" font-family="-apple-system, \'Segoe UI\', Helvetica, Arial, sans-serif" font-size="12">%s</text>' % (PAD, y + 12, CAPTION, html.escape(cap)))
        txt.append("# " + cap)
        y += 22
        for l in ls:
            body.extend(draw_line(l, y))
            txt.append(plain(l))
            y += LH
        # a cursor after the last line, like a real terminal
        last = ls[-1]
        body.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%d" fill="%s" opacity="0.8"/>' % (PAD + (len(last) + 1) * CW, y - LH + 3, CW, LH - 6, FG_DEFAULT))
        txt.append("")
        y += 14
    height = y + 4

    head = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" role="img" aria-label="%s">\n'
            '<rect width="100%%" height="100%%" rx="9" fill="%s"/>\n'
            '<rect width="100%%" height="28" rx="9" fill="#2d2d2d"/><rect y="14" width="100%%" height="14" fill="#2d2d2d"/>\n'
            '<circle cx="18" cy="14" r="5.5" fill="#ff5f56"/><circle cx="37" cy="14" r="5.5" fill="#ffbd2e"/><circle cx="56" cy="14" r="5.5" fill="#27c93f"/>\n'
            '<text x="%d" y="18" fill="#9d9d9d" text-anchor="middle" font-family="-apple-system, \'Segoe UI\', Helvetica, Arial, sans-serif" font-size="12">%s</text>\n'
            '<g font-family="%s" font-size="%d">\n') % (width, height, width, height, html.escape(a.title), BG_PANEL, width // 2, html.escape(a.title), MONO, FS)
    open(a.svg, "w", encoding="utf-8").write(head + "\n".join(body) + "\n</g>\n</svg>\n")
    open(a.txt, "w", encoding="utf-8").write("\n".join(txt).rstrip() + "\n")


if __name__ == "__main__":
    main()
