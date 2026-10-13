# OpenFrame — marca

![Prancha da marca](board/openframe-board.png)

## Conceito

**Um quadro de vídeo aberto pela agulha da timeline.** A moldura arredondada é o vídeo (o *frame*). O playhead
ciano atravessa a moldura, e ela se abre exatamente onde ele passa. O nome *OpenFrame* fica num sinal só e evoca
a ação central do app, que é parar num instante e editar. Não usa tesoura, rolo de filme nem botão de play.

O wordmark não usa fonte de terceiros: as letras foram desenhadas para a marca, com hastes retas e bojos em retângulo
arredondado (o mesmo desenho do quadro). No lockup horizontal, a caixa-alta tem exatamente a altura do quadro do símbolo.

Os conceitos explorados (A, Playhead Frame, que foi o escolhido; B, Clip F; C, Open Corner) estão em `concepts/`.

## Paleta

| Nome | HEX | RGB | Uso |
|---|---|---|---|
| Playhead Cyan | `#00C2CC` | 0 194 204 | Agulha / destaque (igual ao `Theme.accent`) |
| Deep Cyan | `#00838A` | 0 131 138 | Agulha sobre fundo claro (contraste 4,5:1 com branco) |
| Night | `#17171C` | 23 23 28 | Fundo principal, texto sobre claro |
| Panel | `#212126` | 33 33 38 | Superfícies |
| Paper | `#F4F5F7` | 244 245 247 | Quadro e texto sobre escuro, fundo claro |

A versão principal é a **colorida sobre fundo escuro**: quadro Paper e agulha Playhead Cyan.

## Arquivos

```
symbol/     openframe-symbol-{variante}.svg          símbolo (grade 256)
            openframe-symbol-small-{variante}.svg    corte para ≤ 32 px (traços e folgas maiores)
wordmark/   openframe-wordmark-{variante}.svg
lockup/     openframe-lockup-horizontal-{variante}.svg
            openframe-lockup-stacked-{variante}.svg
png/        PNGs prontos do símbolo (512) e do lockup (1600 px)
appicon/    openframe-appicon.svg (+ -small.svg)     arte do ícone, 1024 com corpo squircle de 824
            png/openframe-appicon-{16,32,64,128,256,512,1024}.png
            AppIcon.iconset/  ·  AppIcon.icns
board/      openframe-board.html / .png              prancha: testes de 16 px, uma cor e invertida
concepts/   conceitos da exploração
source/     build.py (gera todos os SVGs) · render.sh (PNGs, iconset e .icns)
```

As variantes são `color-on-dark`, `color-on-light`, `mono-black`, `mono-white` e `mono-cyan`.

## Uso

- **Área de proteção:** em volta de toda a marca, deixe pelo menos a largura da cabeça da agulha (≈ ⅛ da altura do símbolo).
- **Tamanho mínimo:** símbolo com 16 px, usando o corte `small` em 32 px ou menos. Lockup horizontal com 96 px de largura.
- **Uma cor:** use `mono-black` em fundo claro e `mono-white` em fundo escuro ou foto. Em fundo ciano, use `mono-black`.
- **Não faça:** trocar as cores entre quadro e agulha, fechar a folga em volta da agulha, girar, aplicar sombra ou
  contorno, reescrever “OpenFrame” com outra fonte ou colocar a agulha ciano sobre fundo claro sem trocar para Deep Cyan.

## Ícone do app (macOS)

O ícone segue a grade da Apple: canvas de 1024, corpo squircle (cantos contínuos) de 824 × 824 centrado, com margem
de 100 px e sombra suave dentro da margem. Os tamanhos 16 e 32 vêm do corte simplificado. Para integrar, copie
`appicon/AppIcon.icns` para `Contents/Resources/` do bundle e defina `CFBundleIconFile = AppIcon` no `Info.plist`.
Também dá para usar o `AppIcon.iconset` num asset catalog.

## Regenerar

```sh
python3 assets/brand/source/build.py   # só os SVGs
zsh assets/brand/source/render.sh      # SVGs + PNGs + iconset + .icns (Chrome, sips, iconutil)
```

---
Antes de registrar a marca, faça uma busca profissional de anterioridade, porque esta prancha não garante que o
desenho esteja livre para registro.
