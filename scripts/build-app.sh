#!/usr/bin/env bash
# Compila la GUI e assembla Stampede.app, senza bisogno di Xcode completo.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/Stampede.app"
VERSION="0.2.0"

# shellcheck source=prepare-build.sh
source "$ROOT/scripts/prepare-build.sh"
prepare_build "$ROOT"

echo "Compilo la GUI…"
swift build -c release --product StampedeApp

BINARY="$ROOT/.build/release/StampedeApp"
[ -x "$BINARY" ] || { echo "Compilazione fallita." >&2; exit 1; }

echo "Assemblo il bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Stampede"

# L'icona è generata da codice, così non c'è un binario opaco versionato nel repo.
ICONSET="$(mktemp -d)/Stampede.iconset"
swift "$ROOT/scripts/make-icon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Stampede.icns"
rm -rf "$(dirname "$ICONSET")"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Stampede</string>
    <key>CFBundleIdentifier</key><string>it.lumika.stampede</string>
    <key>CFBundleName</key><string>Stampede</string>
    <key>CFBundleDisplayName</key><string>Stampede</string>
    <key>CFBundleIconFile</key><string>Stampede</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Lumika</string>
</dict>
</plist>
PLIST

# Firma ad-hoc: non serve un account sviluppatore, ma evita che macOS consideri
# il binario non firmato e lo blocchi al primo avvio.
codesign --force --deep --sign - "$APP" 2>/dev/null && echo "Firmato (ad-hoc)." \
    || echo "Firma saltata: l'app funziona lo stesso."

echo
echo "Fatto: $APP"
echo
echo "Per averlo fra le Applicazioni:"
echo "  cp -R \"$APP\" /Applications/"
echo
echo "Per aprirlo subito:"
echo "  open \"$APP\""
