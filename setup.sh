#!/bin/bash
# One-time setup: builds the Python environment the engine needs.
set -e
cd "$(dirname "$0")/engine"

PY=""
for c in /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3)"; do
  if [ -x "$c" ]; then PY="$c"; break; fi
done
[ -z "$PY" ] && { echo "No python3 found. Install it with: brew install python"; exit 1; }

echo "▸ Creating environment with $PY ($($PY --version))"
rm -rf .venv
"$PY" -m venv .venv
.venv/bin/python -m pip install --upgrade pip -q
echo "▸ Installing PDF libraries (this takes a minute)…"
.venv/bin/python -m pip install -q -r requirements.txt
echo "▸ Checking…"
.venv/bin/python riftpdf_engine.py --selftest
echo "✔ Engine ready. Now run ./build.sh"
