#!/bin/bash
# Crea build/VOTsidian.app (versión release, firmada ad hoc) para abrir la app sin terminal.
set -euo pipefail
cd "$(dirname "$0")/.."
# Versión: VERSION=1.2 ./scripts/build-app.sh. Por defecto 1.0; el número de compilación es el nº de commits.
VERSION="${VERSION:-1.0}"
# Identificador de la app: BUNDLE_ID=com.tunombre.votsidian ./scripts/build-app.sh. Cambiarlo es como instalar otra
# app: empieza con sus propias preferencias.
BUNDLE_ID="${BUNDLE_ID:-com.votsidian.app}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/VOTsidian"
APP="build/VOTsidian.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VOTsidian"

# Icono
TMP="$(mktemp -d)"
swiftc -O scripts/make-icon.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/icon.png"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$TMP"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>VOTsidian</string>
  <key>CFBundleDisplayName</key><string>VOTsidian</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>VOTsidian</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

# Firma: SIGN_ID="Developer ID Application: ..." para firmar de verdad (y luego notarizar con notarytool).
# Sin SIGN_ID usa el primer certificado «Apple Development» válido del llavero (firma estable entre builds); si no hay, firma ad hoc.
if [ -n "${SIGN_ID:-}" ]; then
  # Firma pedida a propósito: si falla, se para. Developer ID necesita runtime endurecido y sello de tiempo para notarizar.
  OPTS=()
  case "$SIGN_ID" in "Developer ID Application"*) OPTS=(--options runtime --timestamp) ;; esac
  codesign --force ${OPTS[@]+"${OPTS[@]}"} --sign "$SIGN_ID" "$APP"
else
  SIGN_ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)
  codesign --force --sign "${SIGN_ID:--}" "$APP" >/dev/null 2>&1 || true
fi
echo "Listo: $PWD/$APP"
