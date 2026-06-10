#!/usr/bin/env bash
# Build a pure-Krypton objk GUI app (.app bundle). No Obj-C source.
#   ./scripts/build-objk-app.sh examples/objk/brain.ks kryide
set -e
cd "$(dirname "$0")/.."
SRC="${1:-examples/objk/brain.ks}"
NAME="${2:-brain}"
ROOT="$PWD"
FE="$ROOT/compiler/macos_arm64/kcc-arm64"
HOST="$ROOT/compiler/macos_arm64/macho_host"

# 1. ensure the macho codegen host is built from the current backend
if [ ! -x "$HOST" ] || [ compiler/macos_arm64/macho_arm64_self.k -nt "$HOST" ]; then
  echo "==> building macho_host from macho_arm64_self.k"
  kcc --native compiler/macos_arm64/macho_arm64_self.k -o "$HOST"
fi

echo "==> compiling $SRC (dev stdlib via KRYPTON_ROOT)"
KRYPTON_ROOT="$ROOT" "$FE" "$SRC" > "/tmp/$NAME.kir"
"$HOST" --ir "/tmp/$NAME.kir" "/tmp/$NAME.bin" >/dev/null

APP="$ROOT/dist/$NAME.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "/tmp/$NAME.bin" "$APP/Contents/MacOS/$NAME"
chmod +x "$APP/Contents/MacOS/$NAME"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>org.krypton-lang.$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>$NAME</string>
  <key>NSDocumentsFolderUsageDescription</key><string>$NAME edits files in your Documents.</string>
</dict></plist>
PLIST
# bundle icon if present (examples/objk/<name>.icns)
if [ -f "$ROOT/examples/objk/$NAME.icns" ]; then
  mkdir -p "$APP/Contents/Resources"
  cp "$ROOT/examples/objk/$NAME.icns" "$APP/Contents/Resources/$NAME.icns"
fi
codesign -s - -f "$APP/Contents/MacOS/$NAME" >/dev/null 2>&1 || true
echo "==> built $APP (pure Krypton, no Obj-C source)"
