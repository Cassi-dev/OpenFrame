#!/bin/bash
# Compila em modo release e monta build/OpenFrame.app, universal (Apple Silicon e Intel).
set -euo pipefail
cd "$(dirname "$0")/.."

# Sem Xcode, o `--arch arm64 --arch x86_64` do SwiftPM não funciona (pede o xcbuild):
# compila cada arquitetura com o próprio triple e junta com o lipo.
BINS=()
for ARCH in arm64 x86_64; do
    TRIPLE="$ARCH-apple-macosx14.0"
    swift build -c release --product OpenFrame --triple "$TRIPLE"
    BINS+=("$(swift build -c release --triple "$TRIPLE" --show-bin-path)/OpenFrame")
done

APP=build/OpenFrame.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/OpenFrame"
cp assets/brand/appicon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>OpenFrame</string>
    <key>CFBundleDisplayName</key><string>OpenFrame</string>
    <key>CFBundleIdentifier</key><string>app.openframe.editor</string>
    <key>CFBundleExecutable</key><string>OpenFrame</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Projeto OpenFrame</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>CFBundleTypeExtensions</key><array><string>openframe</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Pronto: $APP"
