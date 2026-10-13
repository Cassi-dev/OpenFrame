#!/usr/bin/env python3
"""Gera todos os SVGs da marca OpenFrame (símbolo Quatro Quadros, wordmark, lockups e ícone de app).

Uso: python3 assets/brand/source/build.py
A geometria do símbolo é construída aqui. A wordmark vem de `wordmark.json` (contornos da Inter Display
SemiBold, gerados por wordmark.py), então este script não precisa da fonte. Os PNG/ICNS e a prancha saem
do render.sh ao lado.
"""
import json
from pathlib import Path

BRAND = Path(__file__).resolve().parent.parent
WORDMARK = json.loads((BRAND / "source" / "wordmark.json").read_text())

# Paleta
CYAN = "#00C2CC"       # Playhead Cyan (destaque do app)
CYAN_DEEP = "#00838A"  # versão para fundo claro (contraste ≥ 4,5:1 sobre branco)
NIGHT = "#17171C"      # fundo do app
PANEL = "#212126"
PAPER = "#F4F5F7"      # forma e texto sobre fundo escuro / fundo claro

VARIANTS = {
    # nome: (cor dos quadros e do texto, cor do quadro aceso)
    "color-on-dark": (PAPER, CYAN),
    "color-on-light": (NIGHT, CYAN_DEEP),
    "mono-black": ("#000000", "#000000"),
    "mono-white": ("#FFFFFF", "#FFFFFF"),
    "mono-cyan": (CYAN, CYAN),
}


def fmt(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def P(*parts):
    return " ".join(fmt(p) if isinstance(p, (int, float)) else p for p in parts)


# ---------------------------------------------------------------- símbolo
# Grade 256. Quatro quadros 2:1 em cata-vento em volta de um quadro vazio central: uma íris quadrada.
# Lado externo S, vão central h, folga g entre as peças. Cada quadro tem o canto de fora com raio
# grande (ro) e os outros com raio pequeno (ri). O quadro de cima é o aceso (ciano), como na
# interface: ciano é só o que está ativo. Mesma geometria em Theme.swift (LogoMark).

def rrect4(x, y, w, h, tl, tr, br, bl):
    """Retângulo com um raio por canto (sentido horário a partir do topo esquerdo)."""
    return P("M", x + tl, y, "H", x + w - tr, "A", tr, tr, 0, 0, 1, x + w, y + tr,
             "V", y + h - br, "A", br, br, 0, 0, 1, x + w - br, y + h,
             "H", x + bl, "A", bl, bl, 0, 0, 1, x, y + h - bl, "V", y + tl,
             "A", tl, tl, 0, 0, 1, x + tl, y, "Z")


def symbol_rects(small=False):
    """[(x, y, w, h, (tl, tr, br, bl))] em ordem: topo (aceso), direita, base, esquerda."""
    # corte para ≤ 32 px: peças maiores e folgas mais largas
    S, h, g, ro, ri = (204, 60, 12, 30, 8) if not small else (220, 56, 22, 30, 6)
    c, a, b = 128, S / 2, h / 2
    pieces = [(-a, -a, b, -b, 0), (b, -a, a, b, 1), (-b, b, a, a, 2), (-a, -b, -b, a, 3)]
    out = []
    for x0, y0, x1, y1, outer in pieces:
        x0, y0, x1, y1 = x0 + g / 2, y0 + g / 2, x1 - g / 2, y1 - g / 2
        radii = tuple(ro if k == outer else ri for k in range(4))
        out.append((c + x0, c + y0, x1 - x0, y1 - y0, radii))
    return out


def symbol_group(main, lit, small=False, transform=None):
    t = f' transform="{transform}"' if transform else ""
    paths = [f'<path fill="{lit if i == 0 else main}" d="{rrect4(x, y, w, h, *r)}"/>'
             for i, (x, y, w, h, r) in enumerate(symbol_rects(small))]
    return f"<g{t}>" + "".join(paths) + "</g>"


def symbol_box(small=False):
    rects = symbol_rects(small)
    return (min(r[0] for r in rects), min(r[1] for r in rects),
            max(r[0] + r[2] for r in rects), max(r[1] + r[3] for r in rects))


# ---------------------------------------------------------------- wordmark
# "OpenFrame" em Inter Display SemiBold, tracking −10/1000 em, em contornos.
def word_group(fill, x, baseline, cap):
    """Wordmark com a tinta começando em x e a linha de base em `baseline`; caixa-alta = cap."""
    s = cap / WORDMARK["cap"]
    return (f'<g transform="translate({fmt(x - WORDMARK["ink"][0] * s)} {fmt(baseline)}) scale({fmt(s)})">'
            f'<path fill="{fill}" d="{WORDMARK["d"]}"/></g>')


def word_width(cap):
    return (WORDMARK["ink"][2] - WORDMARK["ink"][0]) * cap / WORDMARK["cap"]


def descender(cap):
    return WORDMARK["ink"][3] * cap / WORDMARK["cap"]


# ---------------------------------------------------------------- saída
def svg(w, h, body, title="OpenFrame", bg=None):
    b = f'<rect width="{fmt(w)}" height="{fmt(h)}" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {fmt(w)} {fmt(h)}" '
            f'width="{fmt(w)}" height="{fmt(h)}" role="img"><title>{title}</title>{b}{body}</svg>\n')


def write(rel, text):
    p = BRAND / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


# Lockup horizontal: símbolo com 200 de altura de tinta, caixa-alta = 44 % dele e centrada nele,
# distância símbolo–texto = 0,62 da caixa-alta. Empilhado: caixa-alta 64 sob o símbolo.
SYM_H, CAP_RATIO, GAP_RATIO, PAD = 200, 0.44, 0.62, 28


def lockup_horizontal(main, lit):
    bx0, by0, bx1, by1 = symbol_box()
    k = SYM_H / (by1 - by0)
    cap = SYM_H * CAP_RATIO
    sym = symbol_group(main, lit, transform=f"translate({fmt(PAD - bx0 * k)} {fmt(PAD - by0 * k)}) scale({fmt(k)})")
    tx = PAD + (bx1 - bx0) * k + cap * GAP_RATIO
    base = PAD + SYM_H / 2 + cap / 2
    return svg(tx + word_width(cap) + PAD, SYM_H + 2 * PAD, sym + word_group(main, tx, base, cap))


def lockup_stacked(main, lit):
    bx0, by0, bx1, by1 = symbol_box()
    k = SYM_H / (by1 - by0)
    cap, pad = 64, 32
    ww, sw = word_width(cap), (bx1 - bx0) * k
    W = max(ww, sw) + 2 * pad
    sym = symbol_group(main, lit, transform=f"translate({fmt((W - sw) / 2 - bx0 * k)} {fmt(pad - by0 * k)}) scale({fmt(k)})")
    base = pad + SYM_H + 0.75 * cap + cap
    return svg(W, base + descender(cap) + pad, sym + word_group(main, (W - ww) / 2, base, cap))


def squircle(x, y, w, h, r):
    """Retângulo de cantos contínuos (curvatura suave, como o template da Apple)."""
    X, Y = x + w, y + h
    k = [1.52866483, 1.08849323, 0.86840689, 0.63149399, 0.07491100, 0.37282392, 0.16905899]
    a, b, c, d, e, f, g = (v * r for v in k)
    return P(
        "M", x + a, y, "H", X - a,
        "C", X - b, y, X - c, y, X - d, y + e,
        "C", X - f, y + g, X - g, y + f, X - e, y + d,
        "C", X, y + c, X, y + b, X, y + a,
        "V", Y - a,
        "C", X, Y - b, X, Y - c, X - e, Y - d,
        "C", X - g, Y - f, X - f, Y - g, X - d, Y - e,
        "C", X - c, Y, X - b, Y, X - a, Y,
        "H", x + a,
        "C", x + b, Y, x + c, Y, x + d, Y - e,
        "C", x + f, Y - g, x + g, Y - f, x + e, Y - d,
        "C", x, Y - c, x, Y - b, x, Y - a,
        "V", y + a,
        "C", x, y + b, x, y + c, x + e, y + d,
        "C", x + g, y + f, x + f, y + g, x + d, y + e,
        "C", x + c, y, x + b, y, x + a, y, "Z")


def app_icon(small):
    bx0, by0, bx1, by1 = symbol_box(small)
    k = (560 if small else 500) / (bx1 - bx0)
    cx, cy = 512, 504  # centro óptico um pouco acima do geométrico
    t = f"translate({fmt(cx - (bx0 + bx1) / 2 * k)} {fmt(cy - (by0 + by1) / 2 * k)}) scale({fmt(k)})"
    body = squircle(100, 100, 824, 824, 185.4)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
        "<title>OpenFrame</title><defs>"
        '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#2A2A31"/><stop offset="1" stop-color="#111114"/></linearGradient>'
        '<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity=".20"/>'
        '<stop offset=".5" stop-color="#FFFFFF" stop-opacity=".04"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity=".08"/></linearGradient>'
        '<filter id="sh" x="-10%" y="-10%" width="120%" height="125%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="10"/><feOffset dy="10"/>'
        '<feComponentTransfer><feFuncA type="linear" slope=".3"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
        "</defs>"
        f'<path filter="url(#sh)" fill="url(#bg)" d="{body}"/>'
        f'<path fill="none" stroke="url(#rim)" stroke-width="4" d="{squircle(102, 102, 820, 820, 184.5)}"/>'
        + symbol_group(PAPER, CYAN, small=small, transform=t)
        + "</svg>\n"
    )


def main():
    for name, (main_c, lit) in VARIANTS.items():
        write(f"symbol/openframe-symbol-{name}.svg", svg(256, 256, symbol_group(main_c, lit)))
        write(f"symbol/openframe-symbol-small-{name}.svg", svg(256, 256, symbol_group(main_c, lit, small=True)))
        cap, pad = 100, 24
        write(f"wordmark/openframe-wordmark-{name}.svg",
              svg(word_width(cap) + 2 * pad, cap + descender(cap) + 2 * pad, word_group(main_c, pad, pad + cap, cap)))
        write(f"lockup/openframe-lockup-horizontal-{name}.svg", lockup_horizontal(main_c, lit))
        write(f"lockup/openframe-lockup-stacked-{name}.svg", lockup_stacked(main_c, lit))
    # ícone de app macOS (grade 1024, corpo 824, squircle contínuo); o corte small serve 16 e 32 px
    for small in (False, True):
        write(f"appicon/openframe-appicon{'-small' if small else ''}.svg", app_icon(small))


if __name__ == "__main__":
    main()
