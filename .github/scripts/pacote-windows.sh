#!/usr/bin/env bash
# Pacotes do Windows: zip portátil e instalador (Inno Setup), a partir do build.
# Roda no Git Bash da CI, depois do ilammy/msvc-dev-cmd e do install-qt-action.
#
# uso: pacote-windows.sh <pasta do build> <pasta de saída>
# Precisa de: windeployqt no PATH, FFMPEG_ROOT, VCToolsRedistDir (vcvars), 7z.
set -euo pipefail

build=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)
version=$(sed -n 's/^project(OpenFrame VERSION \([0-9.]*\).*/\1/p' "$root/qt/CMakeLists.txt")
app="$out/OpenFrame"
ffmpeg=$(cygpath -u "$FFMPEG_ROOT")

rm -rf "$out"
mkdir -p "$app/licencas"
cp "$build/src/app/OpenFrame.exe" "$app/"

# Qt (sem os plugins de mídia: o som usa só o QAudioSink, e o plugin FFmpeg do
# Qt traria uma segunda cópia do FFmpeg).
windeployqt --release --no-translations --skip-plugin-types multimedia \
    --qmldir "$root/qt/src/app/qml" "$app/OpenFrame.exe"

# FFmpeg e o runtime do Visual C++ ao lado do executável.
cp "$ffmpeg"/bin/*.dll "$app/"
crt=$(ls -d "$(cygpath -u "$VCToolsRedistDir")"/x64/Microsoft.VC14*.CRT | head -n 1)
cp "$crt"/*.dll "$app/"

# Licenças.
cp "$root/LICENSE" "$app/LICENSE.txt"
cp "$root/qt/packaging/TERCEIROS.txt" "$app/"
cp "$root/qt/packaging/licenses/LGPL-3.0.txt" "$root/qt/src/app/fonts/OFL-Inter.txt" \
    "$root/qt/src/app/fonts/LICENSE-Lucide.txt" "$app/licencas/"
[[ -f "$ffmpeg/LICENSE.txt" ]] && cp "$ffmpeg/LICENSE.txt" "$app/licencas/FFmpeg-LICENSE.txt"

# Zip portátil.
(cd "$out" && 7z a -tzip -bd "OpenFrame-$version-windows-x64-portatil.zip" OpenFrame > /dev/null)

# Instalador. Os /D… não podem virar caminhos do MSYS.
iscc="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
if [[ ! -x $iscc ]]; then
    choco install innosetup -y --no-progress > /dev/null
fi
MSYS2_ARG_CONV_EXCL='*' "$iscc" /Q "/DAppVersion=$version" "/DPayloadDir=$(cygpath -w "$app")" \
    "/DOutputDir=$(cygpath -w "$out")" "$(cygpath -w "$root/qt/packaging/windows/OpenFrame.iss")"

ls -la "$out"
