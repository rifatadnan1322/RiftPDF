#!/usr/bin/env python3
"""Run every engine command against documents it builds itself.

    python tools/command_sweep.py           # all of them
    python tools/command_sweep.py --list    # just say what would run

Exits non-zero if anything fails, so continuous integration can depend on it.

This exists because the engine had 43 commands that worked on the machine they
were written on and had never been run anywhere else. Checking that by hand
finds real problems once and then rots. Checking it on every push does not.

Commands needing a tool this machine lacks are skipped and named, never failed:
a runner without Microsoft Office is not a broken build.
"""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "engine"))

import pymupdf                                    # noqa: E402
import riftpdf_engine as engine                   # noqa: E402


def build_fixtures(work: Path) -> dict:
    """Everything the sweep needs, made from nothing."""
    base = work / "base.pdf"
    doc = pymupdf.open()
    for n in range(3):
        page = doc.new_page(width=612, height=792)
        page.insert_text((72, 100), f"Chapter {n + 1}", fontname="hebo", fontsize=20)
        page.insert_text((72, 140), "Lorem ipsum dolor sit amet, consectetur adipiscing.",
                         fontname="helv", fontsize=12)
        page.insert_text((72, 160), "Contact: alice@example.com, phone 555-0100.",
                         fontname="helv", fontsize=12)
    doc.set_metadata({"title": "Sweep Fixture", "author": "tester"})
    doc.save(str(base))

    picture = work / "pic.png"
    doc[0].get_pixmap(dpi=100).save(str(picture))
    doc.close()

    form = work / "form.pdf"
    formdoc = pymupdf.open()
    page = formdoc.new_page(width=612, height=792)
    widget = pymupdf.Widget()
    widget.field_name = "fullname"
    widget.field_type = pymupdf.PDF_WIDGET_TYPE_TEXT
    widget.rect = pymupdf.Rect(72, 200, 320, 224)
    widget.field_value = ""
    page.add_widget(widget)
    formdoc.save(str(form))
    formdoc.close()

    table = work / "table.pdf"
    tabledoc = pymupdf.open()
    page = tabledoc.new_page(width=612, height=792)
    x0, y0, width, height, rows, cols = 72, 100, 140, 24, 4, 3
    for r in range(rows + 1):
        page.draw_line((x0, y0 + r * height), (x0 + cols * width, y0 + r * height))
    for c in range(cols + 1):
        page.draw_line((x0 + c * width, y0), (x0 + c * width, y0 + rows * height))
    for r in range(rows):
        for c in range(cols):
            page.insert_text((x0 + c * width + 6, y0 + r * height + 16),
                             f"r{r}c{c}", fontname="helv", fontsize=10)
    tabledoc.save(str(table))
    tabledoc.close()

    # A page that is purely an image, which is what OCR exists to handle.
    scan = work / "scan.pdf"
    drawn = pymupdf.open()
    page = drawn.new_page(width=612, height=792)
    page.insert_text((72, 130), "Searchable Document", fontname="hebo", fontsize=26)
    page.insert_text((72, 180), "The quick brown fox jumps over the lazy dog.",
                     fontname="helv", fontsize=14)
    raster = page.get_pixmap(dpi=200)
    drawn.close()
    scandoc = pymupdf.open()
    scandoc.new_page(width=612, height=792).insert_image(
        pymupdf.Rect(0, 0, 612, 792), pixmap=raster)
    scandoc.save(str(scan))
    scandoc.close()

    # RTF, so no library is needed to write an Office input.
    rtf = work / "test.rtf"
    backslash = chr(92)
    rtf.write_text("{" + backslash + "rtf1" + backslash + "ansi "
                   + "RiftPDF sweep." + backslash + "par}", encoding="utf-8")

    return {"base": base, "pic": picture, "form": form,
            "table": table, "scan": scan, "rtf": rtf}


def cases(fixtures: dict, work: Path) -> list:
    """Every command, with a payload that is actually valid for it."""
    base = str(fixtures["base"])
    out = lambda name: str(work / f"out_{name}.pdf")

    # A real span to rewrite, and a real word to redact.
    doc = pymupdf.open(base)
    heading = list(doc[0].search_for("Chapter 1")[0])
    email = list(doc[0].search_for("alice@example.com")[0])
    doc.close()

    return [
        ("info", {"input": base}, None),
        ("selftest", {}, None),
        ("audit_space", {"input": base}, None),
        ("metadata_set", {"input": base, "output": out("meta"),
                          "metadata": {"title": "New"}}, None),
        ("metadata_strip", {"input": base, "output": out("nometa")}, None),
        ("sanitize", {"input": base, "output": out("san")}, None),
        ("repair", {"input": base, "output": out("rep")}, None),
        ("linearize", {"input": base, "output": out("lin")}, None),
        ("compress", {"input": base, "output": out("comp"), "preset": "balanced"}, None),
        ("compress_target", {"input": base, "output": out("ct"),
                             "targetBytes": 120_000}, None),
        ("split", {"input": base, "outputDir": str(work / "split"),
                   "mode": "every", "every": 1}, None),
        ("merge", {"inputs": [base, base], "output": out("merged")}, None),
        ("page_ops", {"input": base, "output": out("rot"),
                      "operations": [{"op": "rotate", "pages": "1", "degrees": 90}]}, None),
        ("encrypt", {"input": base, "output": out("enc"),
                     "userPassword": "pw123"}, None),
        ("decrypt", {"input": out("enc"), "output": out("dec"),
                     "password": "pw123"}, None),
        ("watermark", {"input": base, "output": out("wm"),
                       "kind": "text", "text": "DRAFT"}, None),
        ("page_numbers", {"input": base, "output": out("pn")}, None),
        ("header_footer", {"input": base, "output": out("hf"),
                           "header": {"left": "ACME", "center": "", "right": "{page}"},
                           "footer": {"left": "", "center": "confidential", "right": ""}},
         None),
        ("add_text", {"input": base, "output": out("at"),
                      "items": [{"page": 0, "rect": [100, 300, 400, 340],
                                 "text": "Added by add_text", "size": 14}]}, None),
        ("bookmarks_set", {"input": base, "output": out("bm"),
                           "bookmarks": [{"level": 1, "title": "One", "page": 1}]}, None),
        ("flatten", {"input": base, "output": out("flat")}, None),
        ("pdf_to_text", {"input": base, "output": str(work / "text.txt")}, None),
        ("reading_text", {"input": base}, None),
        ("pdf_to_images", {"input": base, "outputDir": str(work / "imgs"),
                           "dpi": 72}, None),
        ("extract_images", {"input": base, "outputDir": str(work / "exi")}, None),
        ("images_to_pdf", {"inputs": [str(fixtures["pic"])], "output": out("i2p")}, None),
        ("place_images", {"input": base, "output": out("pi"),
                          "items": [{"page": 0, "path": str(fixtures["pic"]),
                                     "rect": [72, 400, 300, 550]}]}, None),
        ("compare", {"inputA": base, "inputB": base}, None),
        ("accessibility_check", {"input": base}, None),
        ("accessibility_fix", {"input": base, "output": out("a11y"),
                               "title": "T", "language": "en"}, None),
        ("form_fields", {"input": str(fixtures["form"])}, None),
        ("form_fill", {"input": str(fixtures["form"]), "output": out("filled"),
                       "values": [{"name": "fullname", "value": "Alice"}]}, None),
        ("redact", {"input": base, "output": out("redacted"),
                    "areas": [{"page": 0, "rect": email}]}, None),
        ("redact_search", {"input": base, "output": out("rs"),
                           "terms": ["alice@example.com"]}, None),
        ("tables_to_excel", {"input": str(fixtures["table"]),
                             "output": str(work / "tables.xlsx")}, None),
        ("pdf_to_word", {"input": base, "output": str(work / "doc.docx")}, None),
        ("text_spans", {"input": base, "text": "Chapter",
                        "bbox": [72, 80, 300, 110], "page": 0}, None),
        ("text_edit", {"input": base, "output": out("te"),
                       "edits": [{"page": 0, "bbox": heading,
                                  "text": "Section One"}]}, None),
        ("ocr_layer", {"input": base, "output": out("ol"),
                       "words": [{"page": 0, "rect": [72, 300, 200, 316],
                                  "text": "welded"}]}, None),
        ("attachments", {"input": base, "output": out("att"), "action": "add",
                         "files": [str(fixtures["pic"])], "outputDir": str(work)}, None),
        ("ocr", {"input": str(fixtures["scan"]), "output": out("ocr")},
         "an OCR recogniser"),
        ("office_to_pdf", {"input": str(fixtures["rtf"]),
                           "output": out("office")}, "Office or LibreOffice"),
    ]


def skip_reason(command: str, caps: dict) -> str | None:
    """Why a command cannot run here, if it cannot. Absence is not failure."""
    if command == "ocr" and not (caps.get("tesseract") or caps.get("windowsocr")):
        return "no OCR recogniser on this machine"
    if command == "office_to_pdf" and not (caps.get("libreoffice") or caps.get("officecom")):
        return "no Office or LibreOffice on this machine"
    return None


SECRET = b"alice@example.com"
CONTROL = b"Lorem ipsum"


def check_redaction(work: Path) -> tuple[bool, str]:
    """Redaction has to remove the bytes, not draw a box over them.

    Two traps here, both of which produce a test that passes while the feature
    is broken. Searching the raw file proves nothing, because the streams are
    deflated and nothing is findable either way -- so read the decompressed
    content. And the fixture has the same text on all three pages while `redact`
    was asked to clear one rectangle on page one, so scanning the whole document
    finds the untouched copies and reports a failure that is not real. Check the
    page that was actually redacted.

    The control string guards the probe itself: if text that was NOT redacted
    has also vanished, the probe is blind and its verdict is worthless.
    """
    doc = pymupdf.open(str(work / "out_redacted.pdf"))
    page_one = doc[0].read_contents() or b""
    doc.close()
    if CONTROL not in page_one:
        return False, "control text missing, so the probe cannot see content at all"
    if SECRET in page_one:
        return False, "REDACTED TEXT IS STILL IN THE FILE"

    # redact_search covers every page, so the whole document must be clean.
    everywhere = pymupdf.open(str(work / "out_rs.pdf"))
    blob = bytearray()
    for number in range(everywhere.page_count):
        blob += everywhere[number].read_contents() or b""
    everywhere.close()
    if SECRET in blob:
        return False, "redact_search left the term on some page"
    return True, "gone from page one, and from every page via redact_search"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="name the commands and stop")
    arguments = parser.parse_args()

    caps = engine.selftest()
    work = Path(tempfile.mkdtemp(prefix="riftpdf-sweep-"))
    try:
        fixtures = build_fixtures(work)
        plan = cases(fixtures, work)

        if arguments.list:
            for name, _, _ in plan:
                print(name)
            return 0

        print(f"\nRiftPDF command sweep  ({len(plan)} commands)")
        print("=" * 62)

        passed, skipped, failed = [], [], []
        for name, payload, _needs in plan:
            reason = skip_reason(name, caps)
            if reason:
                skipped.append((name, reason))
                print(f"  {name:<22} skipped, {reason}")
                continue
            try:
                engine.run_command(name, payload)
                passed.append(name)
                print(f"  {name:<22} ok")
            except Exception as exc:
                failed.append((name, str(exc).splitlines()[0][:100]))
                print(f"  {name:<22} FAILED  {str(exc).splitlines()[0][:100]}")

        # Behaviour, not just absence of an exception.
        print("-" * 62)
        checks = []
        if "redact" in passed:
            checks.append(("redaction removes data",) + check_redaction(work))
        for label, ok, detail in checks:
            print(f"  {label:<22} {'ok' if ok else 'FAILED'}  {detail}")
            if not ok:
                failed.append((label, detail))

        print("=" * 62)
        print(f"  {len(passed)} passed, {len(skipped)} skipped, {len(failed)} failed")
        if failed:
            print("\n  FAILURES:")
            for name, detail in failed:
                print(f"    {name}: {detail}")
        print()
        return 1 if failed else 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
