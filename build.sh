#!/bin/bash
# Builds RiftPDF.app — a self-contained bundle with the Python engine inside.
set -e
cd "$(dirname "$0")"
ROOT="$PWD"
APP="$ROOT/RiftPDF.app"

echo "▸ Compiling…"
swift build -c release

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/RiftPDF "$APP/Contents/MacOS/RiftPDF"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -f Resources/AppMark.png ] && cp Resources/AppMark.png "$APP/Contents/Resources/AppMark.png"

echo "▸ Bundling the engine…"
mkdir -p "$APP/Contents/Resources/engine"
cp engine/riftpdf_engine.py engine/requirements.txt "$APP/Contents/Resources/engine/"
if [ -d engine/.venv ]; then
  cp -R engine/.venv "$APP/Contents/Resources/engine/.venv"
else
  echo "  ! engine/.venv missing — run ./setup.sh first"
fi

echo "▸ Signing…"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (unsigned — fine for local use)"

SIZE=$(du -sh "$APP" | cut -f1)
echo "✔ Built $APP ($SIZE)"

# Apps do not belong on the Desktop: macOS gates anything there behind the
# Desktop-access prompt, which would block RiftPDF's own bundled engine.
if [ "$1" = "--install" ] || [ -d /Applications/RiftPDF.app ]; then
  echo "▸ Installing to /Applications…"
  rm -rf /Applications/RiftPDF.app
  cp -R "$APP" /Applications/RiftPDF.app
  codesign --force --deep --sign - /Applications/RiftPDF.app 2>/dev/null || true
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f /Applications/RiftPDF.app 2>/dev/null || true
  echo "✔ Installed /Applications/RiftPDF.app"
fi
