#!/usr/bin/env python3
"""Turn a built dist\\RiftPDF into things a person can actually download.

    py -3.12 packaging/build_installer.py            # installer + zip + hashes
    py -3.12 packaging/build_installer.py --app      # rebuild the .exe first

Produces, in dist/:
    RiftPDF-<version>-Setup.exe      the installer
    RiftPDF-<version>-portable.zip   unpack and run, nothing written outside it
    SHA256SUMS.txt                   so a download can be checked

The installer is deliberately unsigned; see docs/INSTALL.md for why, and for
what a person should expect SmartScreen to say.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
PAYLOAD = DIST / "RiftPDF"

# Inno Setup does not put itself on PATH, and this machine keeps its programs
# on D:, so look rather than assume.
ISCC_CANDIDATES = [
    Path(r"D:\Programs\InnoSetup\ISCC.exe"),
    Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"),
    Path(r"C:\Program Files\Inno Setup 6\ISCC.exe"),
]


def find_iscc() -> Path | None:
    found = shutil.which("ISCC")
    if found:
        return Path(found)
    for candidate in ISCC_CANDIDATES:
        if candidate.exists():
            return candidate
    return None


def read_version() -> str:
    """Take the version from the app itself, not from a second copy of it."""
    source = (ROOT / "qt" / "riftpdf_qt" / "app.py").read_text(encoding="utf-8")
    match = re.search(r'^APP_VERSION\s*=\s*"([^"]+)"', source, re.M)
    if not match:
        raise SystemExit("APP_VERSION not found in qt/riftpdf_qt/app.py")
    return match.group(1)


def build_app() -> None:
    print("building the application...")
    outcome = subprocess.run([sys.executable, str(ROOT / "qt" / "build_windows.py")],
                             cwd=ROOT)
    if outcome.returncode != 0:
        raise SystemExit("the application build failed")


def build_installer(version: str) -> Path:
    iscc = find_iscc()
    if iscc is None:
        raise SystemExit(
            "Inno Setup was not found. Install it with:\n"
            "    winget install --id JRSoftware.InnoSetup --source winget")

    script = ROOT / "packaging" / "riftpdf.iss"
    print(f"compiling the installer with {iscc}...")
    outcome = subprocess.run(
        [str(iscc), f"/DAppVersion={version}", str(script)],
        cwd=script.parent, capture_output=True, text=True)
    if outcome.returncode != 0:
        sys.stderr.write(outcome.stdout[-3000:])
        sys.stderr.write(outcome.stderr[-3000:])
        raise SystemExit("the installer failed to compile")

    produced = DIST / f"RiftPDF-{version}-Setup.exe"
    if not produced.exists():
        raise SystemExit(f"expected {produced}, which is not there")
    return produced


def build_portable(version: str) -> Path:
    """A zip that runs where it is unpacked, for people who distrust installers."""
    target = DIST / f"RiftPDF-{version}-portable.zip"
    if target.exists():
        target.unlink()
    print("packing the portable zip...")
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(PAYLOAD.rglob("*")):
            if path.is_file():
                archive.write(path, Path("RiftPDF") / path.relative_to(PAYLOAD))
        archive.write(ROOT / "docs" / "INSTALL.md", "RiftPDF/INSTALL.md")
        archive.write(ROOT / "README.md", "RiftPDF/README.md")
        # AGPL-3.0 requires the licence to travel with the program.
        for name in ("LICENSE", "THIRD-PARTY-NOTICES.md"):
            if (ROOT / name).exists():
                archive.write(ROOT / name, f"RiftPDF/{name}")
    return target


def write_checksums(files: list[Path]) -> Path:
    """Publish hashes, because an unsigned download should still be checkable."""
    lines = []
    for path in files:
        digest = hashlib.sha256()
        with open(path, "rb") as handle:
            for chunk in iter(lambda: handle.read(1 << 20), b""):
                digest.update(chunk)
        lines.append(f"{digest.hexdigest()}  {path.name}")
    target = DIST / "SHA256SUMS.txt"
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return target


def human(path: Path) -> str:
    size = path.stat().st_size
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", action="store_true",
                        help="rebuild dist/RiftPDF before packaging it")
    arguments = parser.parse_args()

    if arguments.app:
        build_app()
    if not (PAYLOAD / "RiftPDF.exe").exists():
        raise SystemExit(f"{PAYLOAD} is not built. Run with --app, or run "
                         f"qt/build_windows.py first.")

    version = read_version()
    print(f"packaging RiftPDF {version}")
    installer = build_installer(version)
    portable = build_portable(version)
    sums = write_checksums([installer, portable])

    print("\nready to publish:")
    for path in (installer, portable, sums):
        print(f"   {path.name:<36} {human(path)}")
    print("\nUnsigned by design. docs/INSTALL.md explains the SmartScreen "
          "warning that people will see.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
