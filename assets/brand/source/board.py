#!/usr/bin/env python3
"""Gera a prancha da marca (board/openframe-board.html). O render.sh tira o PNG pelo Chrome.

Uso: python3 assets/brand/source/board.py            # escreve o HTML
     python3 assets/brand/source/board.py --height   # só imprime a altura da página (para o screenshot)
"""
import sys
from pathlib import Path

BRAND = Path(__file__).resolve().parent.parent

CSS = """
:root{--night:#17171C;--panel:#212126;--paper:#F4F5F7;--cyan:#00C2CC;--deep:#00838A;--mute:#8A8A96}
*{box-sizing:border-box;margin:0;padding:0}
body{width:1600px;background:var(--night);color:var(--paper);font:15px/1.5 "Helvetica Neue",Arial,sans-serif}
section{padding:0 64px;overflow:hidden}
h2{font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:var(--mute);font-weight:600;margin-bottom:18px}
.row{display:flex;gap:24px}
.card{border-radius:20px;flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;position:relative}
.card small{font-size:12px;letter-spacing:.06em;opacity:.6}
.dark{background:var(--panel)}.black{background:#000}.light{background:var(--paper);color:#17171C}
.white{background:#fff;color:#17171C}.cyanbg{background:var(--cyan);color:#17171C}
.hero{display:grid;grid-template-columns:380px 1fr;gap:56px;align-items:center;background:var(--panel);border-radius:28px;padding:44px;height:100%}
.hero p{color:#C8C8D0;font-size:18px;max-width:820px;margin-top:28px}
.hero b{color:var(--cyan);font-weight:600}
.sw{flex:1;border-radius:18px;padding:20px;height:140px;display:flex;flex-direction:column;justify-content:flex-end;font-size:13px}
.sw b{font-size:15px}
.ladder{display:flex;align-items:flex-end;gap:28px}
.ladder figure{display:flex;flex-direction:column;align-items:center;gap:8px;font-size:11px;color:var(--mute)}
.pix{image-rendering:pixelated}
.menubar{background:#2A2A30;border-radius:10px;height:28px;padding:0 14px;display:flex;align-items:center;gap:16px;font-size:13px;color:#ddd;width:100%}
.dock{background:rgba(255,255,255,.14);border-radius:22px;padding:10px 14px;display:flex;gap:10px;align-items:flex-end}
.dock span{width:64px;height:64px;border-radius:15px;background:#3a3a44;display:block}
.note{color:var(--mute);font-size:13px}
"""


def sections():
    icon = "../appicon/png/openframe-appicon-{}.png"
    sym = "../symbol/openframe-symbol-{}.svg"
    small = "../symbol/openframe-symbol-small-{}.svg"
    lock = "../lockup/openframe-lockup-{}-{}.svg"
    out = []

    out.append((520, f"""
<div class="hero">
  <img src="{icon.format(1024)}" width="380" height="380" alt="Ícone do app OpenFrame">
  <div>
    <img src="{lock.format('horizontal', 'color-on-dark')}" style="width:760px" alt="OpenFrame">
    <p>Quatro quadros em cata-vento <b>abrem um quadro vazio no centro</b>, como uma íris quadrada: o quadro aberto
    do nome OpenFrame. Só um dos quatro está aceso em ciano, a mesma regra da interface, onde o ciano marca só o que
    está ativo. A wordmark é a Inter Display SemiBold (SIL OFL 1.1) com tracking −10, convertida em contornos.</p>
  </div>
</div>"""))

    swatches = [("Playhead Cyan", "#00C2CC", "0 194 204 · quadro aceso, destaque", "#00C2CC", "#17171C"),
                ("Deep Cyan", "#00838A", "0 131 138 · quadro aceso sobre claro", "#00838A", "#F4F5F7"),
                ("Night", "#17171C", "23 23 28 · fundo do app, texto sobre claro", "#17171C", "#F4F5F7"),
                ("Panel", "#212126", "33 33 38 · superfícies", "#212126", "#F4F5F7"),
                ("Paper", "#F4F5F7", "244 245 247 · quadros e texto sobre escuro", "#F4F5F7", "#17171C")]
    sw = "".join(f'<div class="sw" style="background:{bg};color:{fg};box-shadow:inset 0 0 0 1px #2C2C34">'
                 f'<b>{n}</b>{h} · {d}</div>' for n, h, d, bg, fg in swatches)
    out.append((200, f'<h2>Paleta</h2><div class="row">{sw}</div>'))

    ladder = "".join(f'<figure><img src="{icon.format(s)}" width="{s}" height="{s}">{s}</figure>'
                     for s in (16, 32, 64, 128, 256))
    pix = (f'<figure><img class="pix" src="{icon.format(16)}" width="128" height="128">16 px ×8</figure>'
           f'<figure><img class="pix" src="{icon.format(32)}" width="128" height="128">32 px ×4</figure>'
           f'<figure><img class="pix" src="png/symbol-small-color-on-dark-16.png" width="128" height="128">símbolo 16 ×8</figure>'
           f'<figure><img class="pix" src="png/symbol-small-color-on-light-16.png" width="128" height="128">sobre claro ×8</figure>')
    out.append((400, f"""<h2>Ícone do app em pixels reais (16 e 32 usam o corte simplificado)</h2>
<div class="row" style="height:330px">
  <div class="card dark" style="flex:1.3;justify-content:flex-end;padding-bottom:28px"><div class="ladder">{ladder}</div></div>
  <div class="card dark"><div class="ladder" style="flex-wrap:wrap;justify-content:center;gap:20px">{pix}</div></div>
</div>"""))

    out.append((220, f"""<h2>Em uso</h2>
<div class="row" style="height:150px">
  <div class="card dark" style="padding:0 28px"><div class="menubar"><img src="{small.format('mono-white')}" width="16">
    <b>OpenFrame</b><span>Arquivo</span><span>Editar</span><span>Clipe</span><span>Exportar</span></div>
    <small>símbolo 16 px (corte pequeno, uma cor) na barra de menus</small></div>
  <div class="card" style="background:linear-gradient(135deg,#3B4256,#6A4A5E)"><div class="dock"><span></span><span></span>
    <img src="{icon.format(128)}" width="64" height="64"><span></span></div><small style="color:#fff">Dock, 64 pt</small></div>
</div>"""))

    def scale(variant, bg):
        figs = "".join(f'<figure><img src="{(small if s <= 32 else sym).format(variant)}" width="{s}" height="{s}">{s}</figure>'
                       for s in (16, 24, 32, 48, 96, 180))
        return f'<div class="card {bg}" style="justify-content:flex-end;padding-bottom:24px"><div class="ladder">{figs}</div></div>'
    out.append((340, f'<h2>Símbolo: escala (arte completa ≥ 48 px · corte pequeno ≤ 32 px)</h2>'
                     f'<div class="row" style="height:270px">{scale("color-on-dark", "dark")}{scale("color-on-light", "white")}</div>'))

    mono = [("mono-black", "white", "preto"), ("mono-white", "black", "branco"),
            ("mono-cyan", "dark", "ciano"), ("mono-black", "cyanbg", "preto sobre ciano")]
    cards = "".join(f'<div class="card {bg}"><img src="{sym.format(v)}" width="120"><small>{lbl}</small></div>'
                    for v, bg, lbl in mono)
    out.append((290, f'<h2>Uma cor</h2><div class="row" style="height:220px">{cards}</div>'))

    def lk(v, bg, lbl):
        return f'<div class="card {bg}"><img src="{lock.format("horizontal", v)}" style="width:560px"><small>{lbl}</small></div>'
    out.append((520, f"""<h2>Lockup horizontal: fundo escuro × fundo claro</h2>
<div class="row" style="height:210px">{lk('color-on-dark', 'dark', 'colorida · fundo escuro (principal)')}{lk('color-on-light', 'light', 'colorida · fundo claro')}</div>
<div class="row" style="height:210px;margin-top:24px">{lk('mono-white', 'black', 'monocromática branca')}{lk('mono-black', 'white', 'monocromática preta')}</div>"""))

    out.append((420, f"""<h2>Lockup empilhado e wordmark</h2>
<div class="row" style="height:330px">
  <div class="card dark"><img src="{lock.format('stacked', 'color-on-dark')}" style="height:260px"></div>
  <div class="card light"><img src="{lock.format('stacked', 'color-on-light')}" style="height:260px"></div>
  <div class="card dark" style="flex:1.4"><img src="../wordmark/openframe-wordmark-color-on-dark.svg" style="width:440px">
    <small>wordmark sozinha · Inter Display SemiBold, tracking −10</small></div>
</div>"""))

    out.append((90, '<p class="note">Área de proteção: a altura de um quadro (≈ ¼ do símbolo) em volta de toda a marca. '
                    'Tamanho mínimo: símbolo com 16 px (corte pequeno em 32 px ou menos); lockup horizontal com 120 px '
                    'de largura. Não troque o quadro aceso de posição, não acenda mais de um quadro e não feche o vão '
                    'do centro.</p>'))
    return out


def main():
    secs = sections()
    top, gap = 64, 48
    height = top + sum(h for h, _ in secs) + gap * (len(secs) - 1) + 40
    if "--height" in sys.argv:
        print(height)
        return
    body = "".join(f'<section style="height:{h}px;margin-top:{top if i == 0 else gap}px">{html}</section>'
                   for i, (h, html) in enumerate(secs))
    page = (f'<!doctype html>\n<html lang="pt-BR"><head><meta charset="utf-8"><title>OpenFrame — marca</title>'
            f"<style>{CSS}</style></head><body>{body}</body></html>\n")
    (BRAND / "board" / "openframe-board.html").write_text(page)
    print("ok:", BRAND / "board" / "openframe-board.html", height)


if __name__ == "__main__":
    main()
