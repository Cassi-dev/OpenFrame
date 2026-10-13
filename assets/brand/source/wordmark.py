#!/usr/bin/env python3
"""Converte a wordmark "OpenFrame" em contornos (paths SVG) a partir da Inter Display SemiBold.

Gera `wordmark.json` ao lado deste arquivo; o build.py lê esse JSON e não precisa da fonte.
Os arquivos da fonte não são versionados: baixe a Inter 4.1 (SIL OFL 1.1) em
https://github.com/rsms/inter/releases e aponte para a pasta `extras/ttf`.

Requer fontTools e uharfbuzz (kerning e ligaduras vêm do shaping do HarfBuzz):
    python3 -m venv .venv && .venv/bin/pip install fonttools uharfbuzz
    .venv/bin/python assets/brand/source/wordmark.py --inter-dir <Inter-4.1/extras/ttf>
"""
import argparse
import json
from pathlib import Path

import uharfbuzz as hb
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
CAP = 100.0          # altura de caixa-alta normalizada; o build.py escala a partir dela
TEXT = "OpenFrame"
FONT = "InterDisplay-SemiBold.ttf"
TRACKING = -10       # milésimos de eme


def fmt(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def shape(path, text, tracking):
    font = TTFont(path)
    upem = font["head"].unitsPerEm
    os2 = font["OS/2"]
    s = CAP / os2.sCapHeight
    glyphs = font.getGlyphSet()
    order = font.getGlyphOrder()

    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(hb.Font(hb.Face(hb.Blob.from_file_path(str(path)))), buf, {"kern": True, "liga": True})

    track = tracking / 1000 * upem
    d_parts, x = [], 0.0
    xmin = ymin = float("inf")
    xmax = ymax = float("-inf")
    glyph_runs = list(zip(buf.glyph_infos, buf.glyph_positions))
    for i, (info, pos) in enumerate(glyph_runs):
        g = glyphs[order[info.codepoint]]
        pen = SVGPathPen(glyphs, ntos=fmt)
        # y para baixo, linha de base em 0, escala para CAP
        g.draw(TransformPen(pen, (s, 0, 0, -s, (x + pos.x_offset) * s, -pos.y_offset * s)))
        d_parts.append(pen.getCommands())
        b = BoundsPen(glyphs)
        g.draw(b)
        if b.bounds:
            x0, y0, x1, y1 = b.bounds
            xmin, xmax = min(xmin, (x + x0) * s), max(xmax, (x + x1) * s)
            ymin, ymax = min(ymin, -y1 * s), max(ymax, -y0 * s)
        x += pos.x_advance + (track if i < len(glyph_runs) - 1 else 0)
    return {
        "font": f"Inter Display SemiBold 4.1 (SIL OFL 1.1), tracking {tracking}/1000 em",
        "d": " ".join(p for p in d_parts if p),
        "ink": [round(xmin, 2), round(ymin, 2), round(xmax, 2), round(ymax, 2)],
        "cap": CAP,
        "xh": round(os2.sxHeight * s, 2),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--inter-dir", type=Path, required=True, help="pasta com InterDisplay-SemiBold.ttf")
    a = ap.parse_args()
    out = HERE / "wordmark.json"
    out.write_text(json.dumps(shape(a.inter_dir / FONT, TEXT, TRACKING), indent=1) + "\n")
    print("ok:", out)


if __name__ == "__main__":
    main()
