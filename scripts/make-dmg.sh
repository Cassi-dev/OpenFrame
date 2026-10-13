#!/bin/bash
# Gera o instalador build/OpenFrame-<versão>.dmg: o app ao lado de um atalho para
# Aplicativos, para instalar arrastando. Use --skip-build para reaproveitar o
# build/OpenFrame.app já montado.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "${1:-}" == "--skip-build" ]] || ./scripts/make-app.sh

APP=build/OpenFrame.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/OpenFrame-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/OpenFrame.app"
ln -s /Applications "$STAGE/Aplicativos"
cp assets/brand/appicon/AppIcon.icns "$STAGE/.VolumeIcon.icns"
cat > "$STAGE/Leia-me.txt" <<TXT
OpenFrame $VERSION

Instalação: arraste o OpenFrame para a pasta Aplicativos.

Primeira abertura: o app não é notarizado pela Apple. Se o macOS disser que não
pode verificá-lo, abra Ajustes do Sistema > Privacidade e Segurança e clique em
"Abrir Mesmo Assim" (ou clique no app com o botão direito > Abrir).

Requer macOS 14 ou superior, Apple Silicon ou Intel.
TXT

# Imagem gravável para ligar o ícone do volume; depois, comprimida e só leitura.
RW="$STAGE.rw.dmg"
rm -f "$RW" "$DMG"
hdiutil create -quiet -volname "OpenFrame $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDRW "$RW"
MOUNT=$(hdiutil attach -nobrowse -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\// {print $NF}')
SetFile -a C "$MOUNT"
hdiutil detach -quiet "$MOUNT"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW"

echo "Pronto: $DMG ($(du -h "$DMG" | cut -f1))"
