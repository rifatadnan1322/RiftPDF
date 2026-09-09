#!/usr/bin/env python3
"""Report what RiftPDF can do on this machine, and prove compression works.

    python tools/selfcheck.py

Builds its own test document, so nothing needs to be supplied. Prints a block
that can be pasted back verbatim when something is not behaving.
"""

import os
import platform
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "engine"))


def line(label, value):
    print(f"  {label:<22} {value}")


def main() -> int:
    print("\nRiftPDF self-check")
    print("=" * 58)
    line("platform", f"{platform.system()} {platform.release()} ({platform.machine()})")
    line("python", sys.version.split()[0])

    try:
        import riftpdf_engine as engine
    except Exception as exc:
        print(f"\n  ENGINE IMPORT FAILED: {exc}")
        print("  Dependencies are probably not installed. Run setup_windows.ps1.")
        return 1

    try:
        import PySide6
        line("PySide6", PySide6.__version__)
    except Exception:
        line("PySide6", "MISSING — the interface will not start")

    caps = engine.selftest()
    print("\n  Libraries")
    line("pymupdf", caps.get("pymupdf"))
    line("pikepdf", caps.get("pikepdf"))
    print("\n  Optional external tools")
    for tool, needed_for in (("ghostscript", "extra compression"),
                             ("qpdf", "web optimisation"),
                             ("tesseract", "OCR"),
                             ("libreoffice", "Word to PDF")):
        state = "yes" if caps.get(tool) else "no"
        line(tool, f"{state:<5} ({needed_for})")

    print()
    print("  Built in, nothing to install")
    windows_ocr = bool(caps.get("windowsocr"))
    line("Windows OCR", f"{'yes' if windows_ocr else 'no':<5} (OCR without Tesseract)")

    # --- prove compression actually works -------------------------------
    print("\n  Compression test")
    import pymupdf
    from PIL import Image

    work = Path(tempfile.mkdtemp(prefix="riftpdf-check-"))
    source = work / "test.pdf"

    # a photographic page, which is what compression has to handle
    import random
    random.seed(7)
    image = Image.new("RGB", (1600, 1200))
    pixels = image.load()
    for y in range(0, 1200, 4):
        for x in range(0, 1600, 4):
            colour = (random.randint(60, 220), random.randint(60, 220), random.randint(60, 220))
            for dy in range(4):
                for dx in range(4):
                    pixels[x + dx, y + dy] = colour
    photo = work / "photo.png"
    image.save(photo)

    doc = pymupdf.open()
    page = doc.new_page(width=612, height=792)
    page.insert_text((72, 90), "RiftPDF self-check", fontname="hebo", fontsize=20)
    page.insert_image(pymupdf.Rect(72, 120, 540, 471), filename=str(photo))
    doc.save(str(source), deflate=True)
    doc.close()

    before = source.stat().st_size
    line("test document", f"{before:,} bytes")

    out = work / "compressed.pdf"
    try:
        result = engine.run_command("compress_target", {
            "input": str(source), "output": str(out), "targetBytes": 120_000})
    except Exception as exc:
        print(f"\n  COMPRESSION FAILED: {exc}")
        return 1

    after = out.stat().st_size
    check = pymupdf.open(str(out))
    pix = check[0].get_pixmap(dpi=40)
    ink = sum(1 for i in range(0, len(pix.samples), 3) if pix.samples[i] < 240)
    check.close()

    line("target", "120,000 bytes")
    line("result", f"{after:,} bytes  ({result['ratio']}% smaller)")
    line("reached target", "yes" if result["hitTarget"] else "NO")
    line("page still renders", "yes" if ink > 500 else "NO — CONTENT LOST")
    if result.get("imageError"):
        line("image error", result["imageError"])

    healthy = result["hitTarget"] and ink > 500 and after < before * 0.6

    # --- prove OCR actually works ---------------------------------------
    have_ocr = bool(caps.get("tesseract") or windows_ocr)
    ocr_healthy = True
    if have_ocr:
        print()
        print("  OCR test")
        # A page that is purely an image, which is what OCR exists to handle.
        built = pymupdf.open()
        drawn = built.new_page(width=612, height=792)
        drawn.insert_text((72, 130), "Searchable Document", fontname="hebo", fontsize=26)
        drawn.insert_text((72, 180), "The quick brown fox jumps over the lazy dog.",
                          fontname="helv", fontsize=14)
        raster = drawn.get_pixmap(dpi=200)
        built.close()

        scan = pymupdf.open()
        scan_page = scan.new_page(width=612, height=792)
        scan_page.insert_image(pymupdf.Rect(0, 0, 612, 792), pixmap=raster)
        scan_path = work / "scan.pdf"
        scan.save(str(scan_path))
        scan.close()

        searchable = work / "scan_ocr.pdf"
        try:
            ocr = engine.run_command("ocr", {"input": str(scan_path),
                                             "output": str(searchable)})
            done = pymupdf.open(str(searchable))
            recovered = done[0].get_text("text").strip()
            hits = done[0].search_for("quick")
            done.close()
            line("recogniser", ocr.get("engine", "?"))
            line("text recovered", f"{len(recovered)} characters")
            line("word is findable", "yes" if hits else "NO")
            if ocr.get("note"):
                line("note", ocr["note"])
            ocr_healthy = bool(hits) and len(recovered) > 20
        except Exception as exc:
            line("OCR FAILED", str(exc))
            ocr_healthy = False
    else:
        print()
        print("  OCR test               skipped, no recogniser on this machine")

    working = "compression and OCR are working" if have_ocr else "compression is working"
    print()
    print("=" * 58)
    print(f"  RESULT: {working}" if healthy and ocr_healthy
          else "  RESULT: SOMETHING IS WRONG - paste this block back")
    print()
    return 0 if (healthy and ocr_healthy) else 1


if __name__ == "__main__":
    sys.exit(main())
