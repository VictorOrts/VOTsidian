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
# Siri y Atajos: el compilador saca los valores constantes de las acciones (App Intents) y `appintentsmetadataprocessor`
# escribe con ellos Metadata.appintents, lo que lee el sistema. Xcode lo hace solo; SwiftPM no.
INTENTS="$(mktemp -d)"
echo '["AppIntent","AppEntity","TransientEntity","AppEnum","EntityQuery","AppShortcutsProvider","AppShortcutProviding","AnyResolverProviding","DynamicOptionsProvider","IntentValueQuery","AppIntentsPackage","_IntentValueRepresentable","_AssistantIntentsProvider"]' > "$INTENTS/protocols.json"
swift build -c release -Xswiftc -emit-const-values-path -Xswiftc "$INTENTS/VOTsidian.swiftconstvalues" \
  -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file -Xswiftc -Xfrontend -Xswiftc "$INTENTS/protocols.json"
BIN="$(swift build -c release --show-bin-path)/VOTsidian"
APP="build/VOTsidian.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VOTsidian"

find "$PWD/Sources/VOTsidian" -name '*.swift' > "$INTENTS/sources.txt"
echo "$INTENTS/VOTsidian.swiftconstvalues" > "$INTENTS/constvalues.txt"
xcrun appintentsmetadataprocessor --force --quiet-warnings --no-app-shortcuts-localization \
  --output "$APP/Contents/Resources" --module-name VOTsidian --binary-file "$BIN" \
  --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun --find swiftc)")")")" \
  --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" --xcode-version "$(xcodebuild -version | sed -n 's/Build version //p')" \
  --platform-family macOS --deployment-target 27.0 --target-triple "$(uname -m)-apple-macos27.0" \
  --source-file-list "$INTENTS/sources.txt" --swift-const-vals-list "$INTENTS/constvalues.txt" >/dev/null
rm -rf "$INTENTS"
[ -f "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata" ] || { echo "Falta Metadata.appintents: Siri no verá las acciones" >&2; exit 1; }

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
  <key>CFBundleDevelopmentRegion</key><string>es</string>
  <key>CFBundleDisplayName</key><string>VOTsidian</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>VOTsidian</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>VOTsidian crea un calendario propio, «VOTsidian», con tus avisos (citas, pagos, caducidades…) y lo mantiene al día. Nunca cambia tus otros calendarios.</string>
  <key>NSCalendarsUsageDescription</key><string>VOTsidian crea un calendario propio, «VOTsidian», con tus avisos (citas, pagos, caducidades…) y lo mantiene al día. Nunca cambia tus otros calendarios.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

# Modelo de frases para Siri (root.ssu.yaml y nlu/): sin él, Siri no reconoce las frases de VOTsidianShortcuts y usa su
# orden genérica (abrir la app en Inicio). Necesita el Info.plist, por eso va aquí.
NLU="$(mktemp -d)"
xcrun appintentsnltrainingprocessor --infoplist-path "$APP/Contents/Info.plist" --temp-dir-path "$NLU" \
  --bundle-id "$BUNDLE_ID" --product-path "$APP/Contents/Resources" \
  --extracted-metadata-path "$APP/Contents/Resources/Metadata.appintents" --archive-ssu-assets >/dev/null 2>&1
rm -rf "$NLU"
[ -f "$APP/Contents/Resources/Metadata.appintents/nlu/nlu.lzfse" ] || { echo "Falta el modelo de frases de Siri (nlu)" >&2; exit 1; }

# Firma: SIGN_ID="Developer ID Application: ..." para firmar de verdad (y luego notarizar con notarytool).
# Sin SIGN_ID usa el primer certificado «Apple Development» válido del llavero (firma estable entre builds); si no hay, firma ad hoc.
if [ -n "${SIGN_ID:-}" ]; then
  # Firma pedida a propósito: si falla, se para. Developer ID necesita runtime endurecido y sello de tiempo para notarizar.
  # El runtime endurecido pide declarar el acceso a Calendarios (sincronización con EventKit).
  OPTS=()
  case "$SIGN_ID" in "Developer ID Application"*) OPTS=(--options runtime --timestamp --entitlements scripts/VOTsidian.entitlements) ;; esac
  codesign --force ${OPTS[@]+"${OPTS[@]}"} --sign "$SIGN_ID" "$APP"
else
  SIGN_ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)
  codesign --force --sign "${SIGN_ID:--}" "$APP" >/dev/null 2>&1 || true
fi

# Instala en /Applications, sustituyendo la versión anterior: Siri solo abre la app desde ahí (desde build/ dice «función
# restringida»). Una sola copia registrada en LaunchServices, para que Siri y Atajos no duden entre dos. INSTALL=0 para no
# instalar; en GitHub (CI) no se instala.
if [ "${INSTALL:-1}" = "1" ] && [ -z "${CI:-}" ]; then
  DEST="/Applications/VOTsidian.app"
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  WAS_OPEN=0
  if pgrep -xq VOTsidian; then
    WAS_OPEN=1
    osascript -e 'quit app "VOTsidian"' >/dev/null 2>&1 || true
    for _ in $(seq 20); do pgrep -xq VOTsidian || break; sleep 0.5; done
  fi
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
  # Sin la copia de build/: Spotlight la indexa aunque no esté en LaunchServices, y salían dos VOTsidian al buscar.
  rm -rf "$APP"
  "$LSREGISTER" -f -R "$DEST"
  [ "$WAS_OPEN" = "1" ] && open "$DEST"
  echo "Instalada: $DEST"
else
  echo "Listo: $PWD/$APP"
fi
