#!/bin/zsh
# Ícones do app para Windows e Linux, a partir da arte da marca
# (assets/brand/appicon). O ícone do macOS tem folga em volta do corpo (824 em
# 1024); aqui ela é cortada, como é costume no Windows e no Linux, deixando a
# sombra. Até 32 px usa o corte "small" (peças maiores).
# Requer: o renderizador da marca (render_png.py, via Chrome) e o ffmpeg.
# Uso: zsh qt/packaging/icons.sh
set -euo pipefail
PKG="${0:A:h}"
BRAND="$PKG/../../assets/brand/appicon"
RENDER="${RENDER_PNG:-$HOME/.claude/skills/logo-design/scripts/render_png.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 "$RENDER" "$BRAND/openframe-appicon.svg" -o "$TMP/full.png" --size 1024
python3 "$RENDER" "$BRAND/openframe-appicon-small.svg" -o "$TMP/small.png" --size 1024

# Corpo em 100…923 e sombra até 943: quadrado de 864 a partir de (80, 90).
mkdir -p "$PKG/icons"
for s in 16 24 32 48 64 128 256 512; do
  src="$TMP/full.png"; (( s <= 32 )) && src="$TMP/small.png"
  ffmpeg -v error -y -i "$src" -vf "crop=864:864:80:90,scale=${s}:${s}:flags=lanczos" "$PKG/icons/openframe-${s}.png"
done
cp "$PKG/icons/openframe-256.png" "$PKG/../src/app/icons/openframe-256.png"

# .ico do Windows com PNGs embutidos (aceito desde o Vista).
python3 - "$PKG/icons" "$PKG/windows/OpenFrame.ico" <<'EOF'
import struct, sys, pathlib
folder, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
sizes = [16, 24, 32, 48, 64, 128, 256]
images = [(folder / f"openframe-{s}.png").read_bytes() for s in sizes]
header = struct.pack("<HHH", 0, 1, len(sizes))
offset = 6 + 16 * len(sizes)
entries = b""
for s, data in zip(sizes, images):
    entries += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(data), offset)
    offset += len(data)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_bytes(header + entries + b"".join(images))
EOF
echo "ícones em $PKG/icons e $PKG/windows/OpenFrame.ico"
