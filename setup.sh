#!/bin/bash
# One-time setup: builds the Python the engine runs on.
set -e
cd "$(dirname "$0")/engine"

if [ "$(uname -s)" != "Darwin" ]; then
  # Linux runs the Qt app from the checkout, so an ordinary environment is
  # enough: nothing here is packaged and sent to another machine.
  PY="$(command -v python3 || true)"
  [ -z "$PY" ] && { echo "No python3 found. Install Python 3.11 or later."; exit 1; }
  echo "▸ Creating environment with $PY ($($PY --version))"
  rm -rf .venv
  "$PY" -m venv .venv
  .venv/bin/python -m pip install --upgrade pip -q
  .venv/bin/python -m pip install -q -r requirements.txt
  .venv/bin/python riftpdf_engine.py --selftest
  echo "✔ Engine ready."
  exit 0
fi

# macOS. This used to make a virtual environment from whichever python3 the
# machine had. A virtual environment is only a set of links back to that
# Python, so the app that build.sh assembled from it worked on the machine
# that built it and nowhere else: on anyone else's Mac the links pointed at
# nothing and every engine command failed. The app has to carry a whole
# Python of its own, one that does not care where it is put.
#
# These are the relocatable CPython builds from python-build-standalone,
# pinned to one release and checked against its published SHA-256 before
# anything is unpacked.
PY_VERSION="3.12.16"
PY_BUILD="20261110"
case "$(uname -m)" in
  arm64)  PY_ARCH="aarch64"; PY_SHA="2f11b8aa3726bdbd87dd9eb76568412faddf4f47e26913fa45d6a2e424972acd" ;;
  x86_64) PY_ARCH="x86_64";  PY_SHA="b78a4c479f1964ec484880bee567568266f68da102269fb93a05fe8716b45f91" ;;
  *) echo "Unsupported processor: $(uname -m)"; exit 1 ;;
esac
PY_FILE="cpython-${PY_VERSION}+${PY_BUILD}-${PY_ARCH}-apple-darwin-install_only_stripped.tar.gz"
PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PY_BUILD}/${PY_FILE}"

echo "▸ Fetching Python ${PY_VERSION} (${PY_ARCH})…"
DOWNLOAD="$(mktemp -d)"
trap 'rm -rf "$DOWNLOAD"' EXIT
curl --fail --location --silent --show-error -o "$DOWNLOAD/python.tar.gz" "$PY_URL"
ACTUAL="$(shasum -a 256 "$DOWNLOAD/python.tar.gz" | cut -d' ' -f1)"
if [ "$ACTUAL" != "$PY_SHA" ]; then
  echo "Python download does not match its published checksum — refusing to use it."
  echo "  expected $PY_SHA"
  echo "  got      $ACTUAL"
  exit 1
fi

rm -rf python .venv
tar -xzf "$DOWNLOAD/python.tar.gz"          # unpacks to ./python

echo "▸ Installing PDF libraries (this takes a minute)…"
python/bin/python3 -m pip install -q --no-warn-script-location -r requirements.txt
echo "▸ Checking…"
python/bin/python3 riftpdf_engine.py --selftest
echo "✔ Engine ready. Now run ./build.sh"
