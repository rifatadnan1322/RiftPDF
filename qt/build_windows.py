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


# The interface is Qt Widgets throughout and loads no QML, but PySide6's
# PyInstaller hook collects Qt Quick and Qml anyway — about 12 MB of DLLs that
# are never opened. --exclude-module cannot remove them, because the hook
# collects them as binaries rather than as importable modules, so they are
# deleted after the build instead.
#
# Verified rather than assumed: with these five removed the app still starts,
# renders a document, draws its thumbnails and runs its tools. Qt PDF ships a
# QML module alongside the widget one, so that was worth checking rather than
# reasoning about.
UNUSED_QT_BINARIES = [
    "Qt6Qml.dll",
    "Qt6QmlMeta.dll",
    "Qt6QmlModels.dll",
    "Qt6QmlWorkerScript.dll",
    "Qt6Quick.dll",
]


def prune_unused_qt(produced: Path) -> None:
    freed = 0
    for name in UNUSED_QT_BINARIES:
        library = produced / "_internal" / "PySide6" / name
        if library.exists():
            freed += library.stat().st_size
            library.unlink()
    if freed:
        print(f"pruned {freed / 1048576:.1f} MB of Qt modules the app never loads")


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
    if os.name == "nt":
        # winsdk loads its namespaces as separate extension modules at run
        # time, so nothing static points at them and PyInstaller would leave
        # them out — taking Windows OCR with them.
        command += ["--collect-all", "winsdk"]
    if icon.exists():
        command += ["--icon", str(icon)]
    command.append(str(ROOT / "qt" / "main.py"))

    print("running:", " ".join(command))
    result = subprocess.run(command, cwd=ROOT)
    if result.returncode != 0:
        return result.returncode

    produced = dist / "RiftPDF"
    prune_unused_qt(produced)
    print(f"\nBuilt {produced}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
