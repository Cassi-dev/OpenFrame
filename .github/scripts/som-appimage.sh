#!/usr/bin/env bash
# Prova do AppImage num Linux sem a libva: o pacote não leva o plugin de mídia do
# Qt (nem nada que dependa da libva), abre, toca e o som sai. Tira a libva do
# sistema, toca 3 s (cenário "som") num servidor PulseAudio com uma saída nula e
# mede o que chegou ao monitor dela. Usado pela CI do Linux depois dos pacotes.
#
# uso: som-appimage.sh <OpenFrame.AppImage> <pasta de saída>
# Precisa do ffmpeg no PATH (gera a mídia e mede o volume) e de sudo/apt.
set -euo pipefail

appimage=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
rm -rf "$2"
mkdir -p "$2"
out=$(cd "$2" && pwd)
work="$out/.trabalho"
mkdir -p "$work/midia" "$work/biblioteca"

# 1. O pacote: sem plugins/multimedia e sem nada que peça a libva.
(cd "$work" && "$appimage" --appimage-extract > /dev/null)
app="$work/squashfs-root"
if [[ -d $app/usr/plugins/multimedia ]]; then
    echo "::error::O AppImage leva o plugin de mídia do Qt (usr/plugins/multimedia)"
    exit 1
fi
pedem=$(find "$app" -type f \( -name '*.so*' -o -perm -u+x \) -print0 |
    xargs -0 -r sh -c 'for f; do readelf -d "$f" 2>/dev/null | grep -q "NEEDED.*libva" && echo "$f"; done' sh || true)
levam=$(find "$app" -name 'libva*.so*' || true)
if [[ -n $pedem || -n $levam ]]; then
    echo "::error::Há bibliotecas no AppImage ligadas à libva:"
    echo "$pedem" "$levam"
    exit 1
fi
echo "Pacote: sem plugin de mídia do Qt e sem libva."

# 2. O sistema: sem libva, com PulseAudio e uma tela virtual (o app usa a xcb do pacote).
sudo apt-get install -y --no-install-recommends pulseaudio pulseaudio-utils xvfb xauth > /dev/null
libva=$(dpkg-query -W -f='${Package} ${Status}\n' 'libva*' 2> /dev/null | awk '/ installed$/ { print $1 }')
if [[ -n $libva ]]; then
    # shellcheck disable=SC2086
    sudo apt-get remove -y $libva
fi
if ldconfig -p | awk '/libva/ { achou = 1 } END { exit !achou }'; then
    echo "::error::A libva continua no sistema"
    exit 1
fi
echo "Sistema: sem libva."
pulseaudio --daemonize=yes --exit-idle-time=-1 --log-target=stderr
pactl load-module module-null-sink sink_name=captura > /dev/null
pactl set-default-sink captura

# 3. Mídia: um vídeo com um tom de 440 Hz.
ffmpeg -v error -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440:sample_rate=48000 \
    -t 6 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$work/midia/1-tom.mp4"

# 4. Toca gravando o monitor da saída nula.
parec -d captura.monitor --format=s16le --rate=48000 --channels=2 > "$work/som.raw" &
gravador=$!
status=0
env OPENFRAME_SNAPSHOT_DIR="$out/capturas" OPENFRAME_LIBRARY_DIR="$work/biblioteca" \
    OPENFRAME_SNAPSHOT_MEDIA="$work/midia" OPENFRAME_SNAPSHOT_SCENARIO=som OPENFRAME_SOFTWARE=1 \
    QT_QPA_PLATFORM=xcb QT_LOGGING_RULES="qt.multimedia.plugin=true" \
    timeout 180 xvfb-run -a "$app/AppRun" > "$out/som.log" 2>&1 || status=$?
kill "$gravador" 2> /dev/null || true
wait "$gravador" 2> /dev/null || true
cat "$out/som.log"
if [[ $status -ne 0 ]] || ! grep -q '\[snapshot\] fim' "$out/som.log"; then
    echo "::error::O AppImage não chegou ao fim do cenário de som (saída $status)"
    exit 1
fi

# 5. O som: o tom tem pico perto de -18 dBFS; silêncio fica em -91 dB.
if [[ ! -s $work/som.raw ]]; then
    echo "::error::O gravador do PulseAudio não gravou nada"
    exit 1
fi
ffmpeg -v error -f s16le -ar 48000 -ac 2 -i "$work/som.raw" "$out/som.wav"
medida=$(ffmpeg -hide_banner -i "$out/som.wav" -af volumedetect -f null - 2>&1 | grep -E 'mean_volume|max_volume')
echo "$medida"
pico=$(echo "$medida" | sed -n 's/.*max_volume: \(-*[0-9.]*\) dB.*/\1/p')
if [[ -z $pico ]] || ! awk -v p="$pico" 'BEGIN { exit !(p > -40) }'; then
    echo "::error::Não saiu som do AppImage (pico ${pico:-?} dB)"
    exit 1
fi
echo "Som do AppImage: pico $pico dB."
rm -rf "$work"
