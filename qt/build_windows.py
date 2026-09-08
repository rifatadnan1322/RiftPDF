#!/usr/bin/env python3
"""Build the Windows package.

Run this on Windows (the CI workflow does it on a windows-latest runner):

    py -3.12 -m pip install -r qt/requirements.txt pyinstaller
    py -3.12 qt/build_windows.py

PyInstaller cannot cross-compile, so building this on macOS or Linux produces
a macOS or Linux binary, not a .exe.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEPARATOR = ";" if os.name == "nt" else ":"


def main() -> int:
    dist = ROOT / "dist"
    build = ROOT / "build"
    for folder in (dist, build):
        shutil.rmtree(folder, ignore_errors=True)

    icon = ROOT / "Resources" / ("AppIcon.ico" if os.name == "nt" else "AppIcon.png")

    command = [
        sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--windowed",
        "--name", "RiftPDF",
        "--distpath", str(dist),
        "--workpath", str(build),
        "--specpath", str(build),
        "--add-data", f"{ROOT / 'engine' / 'riftpdf_engine.py'}{SEPARATOR}engine",
        "--hidden-import", "pymupdf",
        "--hidden-import", "pikepdf",
        "--hidden-import", "openpyxl",
        "--hidden-import", "PIL",
        "--collect-submodules", "pdf2docx",
    ]
    if icon.exists():
        command += ["--icon", str(icon)]
    command.append(str(ROOT / "qt" / "main.py"))

    print("running:", " ".join(command))
    result = subprocess.run(command, cwd=ROOT)
    if result.returncode != 0:
        return result.returncode

    produced = dist / "RiftPDF"
    print(f"\nBuilt {produced}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
