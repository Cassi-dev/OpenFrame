#!/bin/zsh
# Rasteriza o ícone de app, os PNGs da marca e a prancha. Requer: Chrome (via render_png.py), sips e iconutil.
# Uso: zsh assets/brand/source/render.sh
set -euo pipefail
BRAND="${0:A:h:h}"
RENDER="${RENDER_PNG:-$HOME/.claude/skills/logo-design/scripts/render_png.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 "$BRAND/source/build.py"

# Masters 1024: arte completa e corte para tamanhos pequenos
python3 "$RENDER" "$BRAND/appicon/openframe-appicon.svg" -o "$TMP/full.png" --size 1024
python3 "$RENDER" "$BRAND/appicon/openframe-appicon-small.svg" -o "$TMP/small.png" --size 1024

PNG="$BRAND/appicon/png"
SET="$BRAND/appicon/AppIcon.iconset"
rm -rf "$PNG" "$SET"; mkdir -p "$PNG" "$SET"

for s in 16 32 64 128 256 512 1024; do
  src="$TMP/full.png"; (( s <= 32 )) && src="$TMP/small.png"
  sips -s format png -z $s $s "$src" --out "$PNG/openframe-appicon-$s.png" >/dev/null
done

cp "$PNG/openframe-appicon-16.png"   "$SET/icon_16x16.png"
cp "$PNG/openframe-appicon-32.png"   "$SET/icon_16x16@2x.png"
cp "$PNG/openframe-appicon-32.png"   "$SET/icon_32x32.png"
cp "$PNG/openframe-appicon-64.png"   "$SET/icon_32x32@2x.png"
cp "$PNG/openframe-appicon-128.png"  "$SET/icon_128x128.png"
cp "$PNG/openframe-appicon-256.png"  "$SET/icon_128x128@2x.png"
cp "$PNG/openframe-appicon-256.png"  "$SET/icon_256x256.png"
cp "$PNG/openframe-appicon-512.png"  "$SET/icon_256x256@2x.png"
cp "$PNG/openframe-appicon-512.png"  "$SET/icon_512x512.png"
cp "$PNG/openframe-appicon-1024.png" "$SET/icon_512x512@2x.png"
iconutil -c icns "$SET" -o "$BRAND/appicon/AppIcon.icns"

# PNGs de conveniência do símbolo e do lockup
mkdir -p "$BRAND/png"
for v in color-on-dark color-on-light mono-black mono-white; do
  python3 "$RENDER" "$BRAND/symbol/openframe-symbol-$v.svg" -o "$BRAND/png/openframe-symbol-$v-512.png" --size 512
  lockup="$BRAND/lockup/openframe-lockup-horizontal-$v.svg"
  h=$(python3 -c 'import re,sys; w,h=map(float,re.search(r"viewBox=\"0 0 ([\d.]+) ([\d.]+)",open(sys.argv[1]).read()).groups()); print(round(1600*h/w))' "$lockup")
  python3 "$RENDER" "$lockup" -o "$BRAND/png/openframe-lockup-horizontal-$v-1600.png" --width 1600 --height "$h"
done

# Testes de tamanho do símbolo (corte pequeno) para a prancha
mkdir -p "$BRAND/board/png"
for s in 16 32; do
  python3 "$RENDER" "$BRAND/symbol/openframe-symbol-small-color-on-dark.svg" -o "$BRAND/board/png/symbol-small-color-on-dark-$s.png" --size $s --bg "#17171C"
  python3 "$RENDER" "$BRAND/symbol/openframe-symbol-small-color-on-light.svg" -o "$BRAND/board/png/symbol-small-color-on-light-$s.png" --size $s --bg "#F4F5F7"
done

# Prancha (HTML de altura fixa gerado por board.py)
python3 "$BRAND/source/board.py"
python3 "$RENDER" "$BRAND/board/openframe-board.html" -o "$BRAND/board/openframe-board.png" --width 1600 --height "$(python3 "$BRAND/source/board.py" --height)"
echo "ok: $BRAND/appicon/AppIcon.icns"
