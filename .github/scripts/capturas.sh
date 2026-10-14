#!/usr/bin/env bash
# Capturas offscreen do app (tela inicial, editor com mídia, projeto completo e
# arrastes), para conferir o visual sem tela. Usado pela CI; roda também no Mac.
#
# uso: capturas.sh <executável do OpenFrame> <pasta de saída>
# Precisa do ffmpeg no PATH (gera a mídia de teste).
set -euo pipefail

# No Windows (Git Bash) o app recebe caminhos nativos (C:/...).
nativo() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi
}

app=$1
rm -rf "$2"
mkdir -p "$2"
out=$(nativo "$(cd "$2" && pwd)")
root=$(nativo "$(cd "$(dirname "$0")/../.." && pwd)")
work="$out/.trabalho"
mkdir -p "$work/midia" "$work/biblioteca" "$work/biblioteca-completo"

# Mídia de teste: dois vídeos com som, uma foto e uma música.
(
    cd "$work/midia"
    ffmpeg -v error -f lavfi -i testsrc2=size=1280x720:rate=30 -f lavfi -i sine=frequency=440:sample_rate=48000 \
        -t 6 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest 1-praia.mp4
    ffmpeg -v error -f lavfi -i mandelbrot=size=1280x720:rate=30 -f lavfi -i sine=frequency=660:sample_rate=48000 \
        -t 4 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest 2-cidade.mov
    ffmpeg -v error -f lavfi -i smptehdbars=size=1280x720 -frames:v 1 3-foto.png
    ffmpeg -v error -f lavfi -i "sine=frequency=220:sample_rate=48000,volume='0.3+0.7*abs(sin(t*3))':eval=frame" \
        -t 10 -c:a libmp3lame 4-musica.mp3
)

# Roda um cenário com limite de tempo; falha se o app não chegar ao fim.
# uso: cenario <nome> <limite em s> [VAR=valor...] -- [argumentos do app]
cenario() {
    local nome=$1 limite=$2
    shift 2
    local vars=()
    while [[ $# -gt 0 && $1 != -- ]]; do
        vars+=("$1")
        shift
    done
    [[ ${1:-} == -- ]] && shift
    local pasta="$out/$nome" log="$out/$nome.log"
    mkdir -p "$pasta"
    echo "== $nome"
    env QT_QPA_PLATFORM=offscreen OPENFRAME_SNAPSHOT_DIR="$pasta" ${vars[@]+"${vars[@]}"} "$app" "$@" >"$log" 2>&1 &
    local pid=$!
    (sleep "$limite" && kill "$pid") >/dev/null 2>&1 &
    local vigia=$!
    local status=0
    wait "$pid" || status=$?
    kill "$vigia" >/dev/null 2>&1 || true
    cat "$log"
    local capturas
    capturas=$(find "$pasta" -name '*.png' | wc -l | tr -d ' ')
    echo "-- $nome: saída $status, $capturas capturas"
    if [[ $status -ne 0 ]] || ! grep -q '\[snapshot\] fim' "$log" || [[ $capturas -eq 0 ]]; then
        echo "::error::Cenário de captura '$nome' falhou (saída $status, $capturas capturas)"
        return 1
    fi
}

falhas=0
cenario inicio 120 OPENFRAME_LIBRARY_DIR="$work/biblioteca-completo" || falhas=1
cenario midia 400 OPENFRAME_LIBRARY_DIR="$work/biblioteca" OPENFRAME_SNAPSHOT_MEDIA="$work/midia" || falhas=1
cenario completo 120 OPENFRAME_LIBRARY_DIR="$work/biblioteca-completo" -- \
    --open "$root/qt/tests/fixtures/completo.openframe" || falhas=1

# Arrastes no projeto criado pelo cenário com mídia.
projeto=$(find "$work/biblioteca" -name '*.openframe' | head -n 1)
if [[ -n $projeto ]]; then
    cenario arraste 120 OPENFRAME_LIBRARY_DIR="$work/biblioteca-completo" OPENFRAME_SNAPSHOT_SCENARIO=arraste -- \
        --open "$projeto" || falhas=1
else
    echo "::error::O cenário com mídia não deixou projeto na biblioteca"
    falhas=1
fi

rm -rf "$work"
exit $falhas
