#!/usr/bin/env bash
# Confere o pacote extraído: o whisper/ggml com as variantes de CPU e o plugin de
# TLS no lugar, e o app do pacote baixando por HTTPS (HEAD no servidor do modelo)
# e transcrevendo uma fala de verdade com uma variante carregada de dentro do
# pacote (cenário "pacote"). Usado pela CI depois dos pacotes.
#
# uso: conferir-pacote.sh <pasta dos pacotes> <pasta de saída>
# Precisa de OPENFRAME_MODELS_DIR com um modelo (a CI tem o base). No Linux,
# extrai o AppImage e usa o Xvfb; no Windows, usa a pasta do zip.
set -euo pipefail

pacotes=$(cd "$1" && pwd)
rm -rf "$2"
mkdir -p "$2"
out=$(cd "$2" && pwd)
root=$(cd "$(dirname "$0")/../.." && pwd)
work="$out/.trabalho"
mkdir -p "$work/midia" "$work/biblioteca"
cp "$root/qt/tests/fixtures/fala/frase.wav" "$work/midia/"
falhas=0
falta() {
    echo "::error::Falta no pacote: $1"
    falhas=1
}

if [[ "${RUNNER_OS:-$(uname -s)}" == Windows* || "$(uname -s)" == MINGW* ]]; then
    app="$pacotes/OpenFrame"
    for f in whisper.dll ggml.dll ggml-base.dll tls/qschannelbackend.dll; do
        [[ -f "$app/$f" ]] || falta "$f"
    done
    variantes=(x64 sse42 sandybridge haswell skylakex cannonlake cascadelake icelake alderlake)
    for v in "${variantes[@]}"; do
        [[ -f "$app/ggml-cpu-$v.dll" ]] || falta "ggml-cpu-$v.dll"
    done
    executar=("$app/OpenFrame.exe")
    esperado="${pacotes##*/}/OpenFrame/ggml-cpu-"
    plataforma=(QT_QPA_PLATFORM=windows OPENFRAME_SOFTWARE=1)
else
    appimage=$(ls "$pacotes"/*.AppImage | head -n 1)
    (cd "$work" && "$appimage" --appimage-extract > /dev/null)
    app="$work/squashfs-root"
    for f in usr/lib/libwhisper.so.1 usr/lib/libggml.so.0 usr/lib/libggml-base.so.0 \
        usr/plugins/tls/libqopensslbackend.so; do
        [[ -f "$app/$f" ]] || falta "$f"
    done
    variantes=(x64 sse42 sandybridge ivybridge piledriver haswell skylakex cannonlake cascadelake icelake cooperlake
        zen4 alderlake sapphirerapids)
    for v in "${variantes[@]}"; do
        f="$app/usr/lib/openframe/libggml-cpu-$v.so"
        if [[ ! -f $f ]]; then
            falta "usr/lib/openframe/libggml-cpu-$v.so"
        elif LD_LIBRARY_PATH="$app/usr/lib" ldd "$f" | grep -q 'not found'; then
            echo "::error::Dependência não encontrada em libggml-cpu-$v.so:"
            LD_LIBRARY_PATH="$app/usr/lib" ldd "$f" | grep 'not found'
            falhas=1
        fi
    done
    sudo apt-get install -y --no-install-recommends xvfb xauth > /dev/null
    executar=(xvfb-run -a "$app/AppRun")
    esperado="squashfs-root/usr/lib/openframe/libggml-cpu-"
    plataforma=(QT_QPA_PLATFORM=xcb OPENFRAME_SOFTWARE=1)
fi
echo "Arquivos do whisper/ggml e do TLS: $([[ $falhas -eq 0 ]] && echo completos || echo incompletos)."

# O app do pacote: HTTPS e transcrição. OPENFRAME_WHISPER_LOG mostra de onde a variante veio.
status=0
env "${plataforma[@]}" OPENFRAME_SNAPSHOT_DIR="$out/capturas" OPENFRAME_LIBRARY_DIR="$work/biblioteca" \
    OPENFRAME_SNAPSHOT_MEDIA="$work/midia" OPENFRAME_SNAPSHOT_SCENARIO=pacote OPENFRAME_WHISPER_LOG=1 \
    timeout 400 "${executar[@]}" > "$out/pacote.log" 2>&1 || status=$?
grep -E '^\[snapshot\]|load_backend' "$out/pacote.log" || true
if [[ $status -ne 0 ]] || ! grep -q '\[snapshot\] fim' "$out/pacote.log"; then
    echo "::error::O app do pacote não passou no cenário 'pacote' (saída $status)"
    falhas=1
fi
# A variante tem de vir do pacote, não da pasta do build (que o executável também conhece).
carregada=$(grep -o 'loaded CPU backend from .*' "$out/pacote.log" | head -n 1 || true)
if [[ -z $carregada ]]; then
    echo "::error::Nenhuma variante de CPU do ggml foi carregada"
    falhas=1
elif [[ $(printf '%s' "$carregada" | tr '\\' '/') != *"$esperado"* ]]; then
    echo "::error::A variante veio de fora do pacote: $carregada"
    falhas=1
fi

# Tamanhos.
echo "Tamanhos:"
for f in "$pacotes"/*.zip "$pacotes"/*.exe "$pacotes"/*.AppImage; do
    if [[ -f $f ]]; then echo "  ${f##*/}: $(du -k "$f" | awk '{ printf "%.1f", $1 / 1024 }') MB"; fi
done
if [[ -d $app ]]; then
    ggml=$(find "$app" \( -iname '*ggml*' -o -iname '*whisper*' \) -type f -exec du -k {} + | awk '{ s += $1 } END { print s }')
    echo "  whisper/ggml no pacote: $((ggml / 1024)) MB"
fi
rm -rf "$work"
exit $falhas
