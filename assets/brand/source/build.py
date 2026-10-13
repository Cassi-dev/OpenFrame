#!/usr/bin/env python3
"""Gera todos os SVGs da marca OpenFrame (símbolo, wordmark, lockups e ícone de app).

Uso: python3 assets/brand/source/build.py
Toda a geometria é construída aqui (sem fontes de terceiros); os PNG/ICNS saem do
script render.sh ao lado.
"""
from pathlib import Path

BRAND = Path(__file__).resolve().parent.parent

# Paleta
CYAN = "#00C2CC"       # Playhead Cyan (destaque do app)
CYAN_DEEP = "#00838A"  # versão para fundo claro (contraste ≥ 4,5:1 sobre branco)
NIGHT = "#17171C"      # fundo do app
PANEL = "#212126"
PAPER = "#F4F5F7"      # quadro sobre fundo escuro / fundo claro


def fmt(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def P(*parts):
    return " ".join(fmt(p) if isinstance(p, (int, float)) else p for p in parts)


# ---------------------------------------------------------------- símbolo
# Grade 256. Quadro 196×136 (proporção próxima de 16:11), traço 24, cantos r36.
# A agulha (playhead) atravessa o quadro a 61 % da largura, com folga de 12 de
# cada lado: o quadro fica "aberto" exatamente onde a edição acontece.

def symbol_paths(small=False):
    if not small:
        x0, x1, y0, y1, R, s = 30, 226, 60, 196, 36, 24
        px, pw, gap = 150, 16, 12
        head_w, head_top, head_bot, tip, foot = 32, 26, 46, 56, 230
    else:  # corte para ≤ 32 px: traços mais grossos, folgas maiores
        x0, x1, y0, y1, R, s = 22, 234, 62, 194, 38, 34
        px, pw, gap = 150, 26, 18
        head_w, head_top, head_bot, tip, foot = 46, 18, 44, 56, 238
    r = R - s
    cl, cr = px - pw / 2 - gap, px + pw / 2 + gap  # bordas do corte
    left = P("M", cl, y0, "H", x0 + R, "A", R, R, 0, 0, 0, x0, y0 + R,
             "V", y1 - R, "A", R, R, 0, 0, 0, x0 + R, y1, "H", cl,
             "V", y1 - s, "H", x0 + R, "A", r, r, 0, 0, 1, x0 + s, y1 - R,
             "V", y0 + R, "A", r, r, 0, 0, 1, x0 + R, y0 + s, "H", cl, "Z")
    right = P("M", cr, y0, "H", x1 - R, "A", R, R, 0, 0, 1, x1, y0 + R,
              "V", y1 - R, "A", R, R, 0, 0, 1, x1 - R, y1, "H", cr,
              "V", y1 - s, "H", x1 - R, "A", r, r, 0, 0, 0, x1 - s, y1 - R,
              "V", y0 + R, "A", r, r, 0, 0, 0, x1 - R, y0 + s, "H", cr, "Z")
    hl, hr, sl, sr, hr6 = px - head_w / 2, px + head_w / 2, px - pw / 2, px + pw / 2, 6
    cap = pw / 2
    playhead = P("M", hl + hr6, head_top, "H", hr - hr6, "A", hr6, hr6, 0, 0, 1, hr, head_top + hr6,
                 "V", head_bot, "L", sr, tip, "V", foot - cap, "A", cap, cap, 0, 0, 1, sl, foot - cap,
                 "V", tip, "L", hl, head_bot, "V", head_top + hr6, "A", hr6, hr6, 0, 0, 1, hl + hr6, head_top, "Z")
    return P(left, right), playhead


def symbol_group(frame_fill, head_fill, small=False, transform=None):
    frame, head = symbol_paths(small)
    t = f' transform="{transform}"' if transform else ""
    return (f'<g{t}><path fill="{frame_fill}" d="{frame}"/>'
            f'<path fill="{head_fill}" d="{head}"/></g>')


# ---------------------------------------------------------------- wordmark
# Letras próprias: hastes retas, bojos em retângulo arredondado (eco do quadro).
# Altura de caixa-alta 136 = altura do quadro do símbolo; x-height 104.
CAP, XH, DESC, OV = 136, 104, 38, 0  # bojos de topo reto: sem overshoot (evita degraus nas junções)
WV, WH = 20, 18          # haste vertical / horizontal (horizontais mais finas: correção óptica)
CWV, CWH = 21, 19        # caixa-alta
RL, RC = 34, 48          # raios: minúsculas / caixa-alta


def rrect(x, y, w, h, rx, ry=None):
    ry = rx if ry is None else ry
    if rx <= 0 or ry <= 0:
        return P("M", x, y, "H", x + w, "V", y + h, "H", x, "Z")
    return P("M", x + rx, y, "H", x + w - rx, "A", rx, ry, 0, 0, 1, x + w, y + ry,
             "V", y + h - ry, "A", rx, ry, 0, 0, 1, x + w - rx, y + h,
             "H", x + rx, "A", rx, ry, 0, 0, 1, x, y + h - ry, "V", y + ry,
             "A", rx, ry, 0, 0, 1, x + rx, y, "Z")


def rect(x, y, w, h):
    return rrect(x, y, w, h, 0)


def ring(x, y, w, h, R, wv, wh):
    outer = rrect(x, y, w, h, R)
    inner = rrect(x + wv, y + wh, w - 2 * wv, h - 2 * wh, R - wv, R - wh)
    return outer + " " + inner


def glyph_O(x, B):
    return [(ring(x, B - CAP - OV, 122, CAP + 2 * OV, RC, CWV, CWH), True)], 122


def glyph_p(x, B):
    yT = B - XH
    return [(rect(x, yT, WV, XH + DESC), False),
            (ring(x, yT - OV, 94, XH + 2 * OV, RL, WV, WH), True)], 94


def glyph_e(x, B):
    W, R = 94, RL
    yT, yB, x1 = B - XH - OV, B + OV, x + W
    rix, riy = R - WV, R - WH
    yc1, yc2 = yT + 40, yT + 40 + WH         # barra do e
    yt = yB - 28                         # terminal
    dy = yt - (yB - R)
    dxo = (R * R - dy * dy) ** 0.5
    dxi = rix * (1 - (dy / riy) ** 2) ** 0.5
    body = P("M", x1, yc2, "V", yT + R, "A", R, R, 0, 0, 0, x1 - R, yT,
             "H", x + R, "A", R, R, 0, 0, 0, x, yT + R, "V", yB - R,
             "A", R, R, 0, 0, 0, x + R, yB, "H", x1 - R,
             "A", R, R, 0, 0, 0, x1 - R + dxo, yt, "H", x1 - R + dxi,
             "A", rix, riy, 0, 0, 1, x1 - R, yB - WH, "H", x + R,
             "A", rix, riy, 0, 0, 1, x + WV, yB - R, "V", yc2, "H", x1, "Z")
    eye = P("M", x + WV, yc1, "V", yT + R, "A", rix, riy, 0, 0, 1, x + R, yT + WH,
            "H", x1 - R, "A", rix, riy, 0, 0, 1, x1 - WV, yT + R, "V", yc1, "Z")
    return [(body + " " + eye, True)], W


def arch(x, B, W, R=RL):
    yT, yB, x1 = B - XH - OV, B, x + W
    rix, riy = R - WV, R - WH
    return P("M", x, yB, "V", yT + R, "A", R, R, 0, 0, 1, x + R, yT, "H", x1 - R,
             "A", R, R, 0, 0, 1, x1, yT + R, "V", yB, "H", x1 - WV, "V", yT + R,
             "A", rix, riy, 0, 0, 0, x1 - R, yT + WH, "H", x + R,
             "A", rix, riy, 0, 0, 0, x + WV, yT + R, "V", yB, "Z")


def glyph_n(x, B):
    return [(rect(x, B - XH, WV, XH), False), (arch(x, B, 90), False)], 90


def glyph_m(x, B):
    w1 = 72
    return [(rect(x, B - XH, WV, XH), False), (arch(x, B, w1), False),
            (arch(x + w1 - WV, B, w1), False)], 2 * w1 - WV


def glyph_F(x, B):
    top = B - CAP
    return [(rect(x, top, CWV, CAP), False), (rect(x, top, 78, CWH), False),
            (rect(x, top + 60, 64, CWH), False)], 78


def glyph_r(x, B):
    yT, R = B - XH, RL
    rix, riy = R - WV, R - WH
    shoulder = P("M", x, yT + R, "A", R, R, 0, 0, 1, x + R, yT - OV, "H", x + 58,
                 "V", yT - OV + WH, "H", x + R, "A", rix, riy, 0, 0, 0, x + WV, yT + R, "Z")
    return [(rect(x, yT, WV, XH), False), (shoulder, False)], 58


def glyph_a(x, B):
    W = 90
    yT = B - XH
    return [(ring(x, yT - OV, W, XH + 2 * OV, RL, WV, WH), True),
            (rect(x + W - WV, yT, WV, XH), False)], W


GLYPHS = {"O": glyph_O, "p": glyph_p, "e": glyph_e, "n": glyph_n, "F": glyph_F,
          "r": glyph_r, "a": glyph_a, "m": glyph_m}
# espaço (em unidades) antes de cada letra — espaçamento óptico ajustado à mão
SPACING = [("O", 0), ("p", 15), ("e", 12), ("n", 13), ("F", 20), ("r", 5),
           ("a", 9), ("m", 13), ("e", 12)]


def wordmark_paths(x, B):
    out, cur = [], x
    for i, (ch, gap) in enumerate(SPACING):
        cur += gap
        parts, adv = GLYPHS[ch](cur, B)
        out += parts
        cur += adv
    return out, cur - x


def paths_svg(parts, fill):
    s = []
    for d, eo in parts:
        rule = ' fill-rule="evenodd"' if eo else ""
        s.append(f'<path{rule} d="{d}"/>')
    return f'<g fill="{fill}">' + "".join(s) + "</g>"


# ---------------------------------------------------------------- saída
def svg(w, h, body, title, bg=None):
    b = f'<rect width="{fmt(w)}" height="{fmt(h)}" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {fmt(w)} {fmt(h)}" '
            f'width="{fmt(w)}" height="{fmt(h)}" role="img"><title>{title}</title>{b}{body}</svg>\n')


VARIANTS = {
    # nome: (cor do quadro / texto, cor da agulha)
    "color-on-dark": (PAPER, CYAN),
    "color-on-light": (NIGHT, CYAN_DEEP),
    "mono-black": ("#000000", "#000000"),
    "mono-white": ("#FFFFFF", "#FFFFFF"),
    "mono-cyan": (CYAN, CYAN),
}


def write(rel, text):
    p = BRAND / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def main():
    for name, (a, b) in VARIANTS.items():
        write(f"symbol/openframe-symbol-{name}.svg",
              svg(256, 256, symbol_group(a, b), "OpenFrame"))
        write(f"symbol/openframe-symbol-small-{name}.svg",
              svg(256, 256, symbol_group(a, b, small=True), "OpenFrame"))

        # wordmark sozinho
        parts, ww = wordmark_paths(24, 24 + CAP)
        write(f"wordmark/openframe-wordmark-{name}.svg",
              svg(ww + 48, CAP + DESC + 2 * 24, paths_svg(parts, a), "OpenFrame"))

        # lockup horizontal: caixa-alta alinhada ao topo/base do quadro
        parts, ww = wordmark_paths(226 + 62, 196)
        W = 226 + 62 + ww + 30
        write(f"lockup/openframe-lockup-horizontal-{name}.svg",
              svg(W, 256, symbol_group(a, b) + paths_svg(parts, a), "OpenFrame"))

        # lockup empilhado: símbolo em cima, wordmark centralizado embaixo
        sc = 0.62
        _, ww = wordmark_paths(0, 0)
        Wst = max(ww * sc, 256) + 80
        sym_t = f"translate({fmt((Wst - 256) / 2)} 10)"
        parts, _ = wordmark_paths(0, 0)
        word = (f'<g transform="translate({fmt((Wst - ww * sc) / 2)} {fmt(266 + CAP * sc)}) scale({sc})">'
                + paths_svg(parts, a) + "</g>")
        Hst = 266 + (CAP + DESC) * sc + 30
        write(f"lockup/openframe-lockup-stacked-{name}.svg",
              svg(Wst, Hst, symbol_group(a, b, transform=sym_t) + word, "OpenFrame"))

    # ---------------- ícone de app macOS (grade 1024, corpo 824, squircle contínuo)
    for small in (False, True):
        write(f"appicon/openframe-appicon{'-small' if small else ''}.svg", app_icon(small))


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
    body = squircle(100, 100, 824, 824, 185.4)
    scale = 3.3 if small else 2.9
    cx, cy = 512, 506  # centro óptico um pouco acima do geométrico
    t = f"translate({fmt(cx - 128 * scale)} {fmt(cy - 128 * scale)}) scale({scale})"
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
        "<title>OpenFrame</title><defs>"
        '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#2C2C34"/><stop offset="1" stop-color="#121216"/></linearGradient>'
        '<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity=".22"/>'
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


if __name__ == "__main__":
    main()
