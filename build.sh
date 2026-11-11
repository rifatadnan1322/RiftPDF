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
# One version number for both apps: the Qt app's. The macOS app used to carry
# its own in Info.plist, and shipped as "1.0" inside a release called 1.1.0.
VERSION=$(sed -n 's/^APP_VERSION *= *"\(.*\)"/\1/p' qt/riftpdf_qt/app.py)
if [ -n "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
                          -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -f Resources/AppMark.png ] && cp Resources/AppMark.png "$APP/Contents/Resources/AppMark.png"

echo "▸ Bundling the engine…"
mkdir -p "$APP/Contents/Resources/engine"
cp engine/riftpdf_engine.py engine/requirements.txt "$APP/Contents/Resources/engine/"
if [ -d engine/python ]; then
  # A whole Python, not a virtual environment: see setup.sh for why.
  cp -R engine/python "$APP/Contents/Resources/engine/python"
  PYTHON="$APP/Contents/Resources/engine/python"
  LIB=$(find "$PYTHON/lib" -maxdepth 1 -type d -name "python3.*" | head -1)

  # Needed to build this Python and never to run it. Copying it wholesale once
  # shipped all of pip inside the app, vendored Windows .exe launchers and
  # all. Nothing here installs anything at run time, and the engine has no
  # use for a GUI toolkit, an IDE or the standard library's own test suite.
  rm -rf "$LIB"/site-packages/pip "$LIB"/site-packages/pip-*.dist-info \
         "$LIB"/site-packages/wheel "$LIB"/site-packages/wheel-*.dist-info \
         "$LIB"/ensurepip "$LIB"/idlelib "$LIB"/tkinter "$LIB"/turtledemo \
         "$LIB"/test "$LIB"/lib-dynload/_tkinter*.so \
         "$PYTHON"/lib/tcl* "$PYTHON"/lib/tk* "$PYTHON"/lib/itcl* \
         "$PYTHON"/lib/thread* "$PYTHON"/lib/libtcl* "$PYTHON"/lib/libtk* \
         "$PYTHON"/include "$PYTHON"/share
  # Only the interpreter stays in bin. The rest are launcher scripts whose
  # first line is the full path of the Python that installed them -- on the
  # machine that built the app, which is useless anywhere else and publishes
  # the builder's home folder name.
  find "$PYTHON/bin" -mindepth 1 ! -name "python" ! -name "python3" ! -name "python3.*" -delete
  rm -f "$PYTHON"/bin/python*-config

  # setuptools is deliberately left alone: some libraries still import
  # pkg_resources at run time, and a few megabytes is not worth that risk.

  # Compile everything now. The app never writes into its own bundle -- doing
  # so would break the signature that seals it -- so without this every launch
  # would recompile the lot from source. "unchecked-hash" because unzipping a
  # download resets file dates, which would otherwise make every one of these
  # look out of date.
  find "$PYTHON" -name "__pycache__" -type d -prune -exec rm -rf {} +
  "$PYTHON/bin/python3" -m compileall -q --invalidation-mode unchecked-hash "$LIB" > /dev/null || true

  # Prove the copy inside the bundle stands on its own before signing it.
  "$PYTHON/bin/python3" "$APP/Contents/Resources/engine/riftpdf_engine.py" --selftest > /dev/null \
    || { echo "  ! the bundled engine failed its self-test"; exit 1; }
else
  echo "  ! engine/python missing — run ./setup.sh first"
  exit 1
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
