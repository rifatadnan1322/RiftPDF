"""RiftPDF for Windows and Linux — the Qt interface over the shared engine."""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

from PySide6.QtCore import QTimer, Qt, QSize
from PySide6.QtGui import QAction, QIcon, QKeySequence, QPixmap
from PySide6.QtWidgets import (QApplication, QFileDialog, QHBoxLayout, QInputDialog,
                               QLabel, QLineEdit, QMainWindow, QMessageBox,
                               QProgressBar, QPushButton, QSplitter, QStatusBar,
                               QTextEdit, QToolBar, QVBoxLayout, QWidget, QDialog,
                               QDialogButtonBox)

from . import engine_bridge as bridge
from .reading import ReadingView
from .theme import BRAND, STYLESHEET
from .tools import TOOLS, ToolDialog, build_payload
from .viewer import DocumentView, SearchBar

APP_NAME = "RiftPDF"
# One source of truth: the installer and the About box both read this, so a
# release cannot go out claiming two different versions of itself.
APP_VERSION = "1.1.0"


class ReportDialog(QDialog):
    """Shows what a read-only tool found."""

    def __init__(self, title: str, lines: list[str], parent=None):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.resize(560, 460)
        layout = QVBoxLayout(self)
        body = QTextEdit()
        body.setReadOnly(True)
        body.setHtml("".join(lines))
        layout.addWidget(body)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        buttons.accepted.connect(self.accept)
        layout.addWidget(buttons)


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(APP_NAME)
        self.resize(1180, 800)

        self.view = DocumentView()
        self.view.pageChanged.connect(self._page_changed)

        self.search = SearchBar(self.view.view)

        side = QWidget()
        side_layout = QVBoxLayout(side)
        side_layout.setContentsMargins(0, 0, 0, 0)
        side_layout.setSpacing(0)
        side_layout.addWidget(self.search)
        side_layout.addWidget(self.view.thumbnails)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        splitter.addWidget(side)
        splitter.addWidget(self.view)
        splitter.setStretchFactor(1, 1)
        splitter.setSizes([230, 950])
        self.setCentralWidget(splitter)

        self._build_toolbar()
        self._build_menus()

        self.progress = QProgressBar()
        self.progress.setMaximumWidth(190)
        self.progress.setVisible(False)
        self.status_label = QLabel("Open a PDF to begin")
        bar = QStatusBar()
        bar.addWidget(self.status_label, 1)
        bar.addPermanentWidget(self.progress)
        self.setStatusBar(bar)

        self._report_capabilities()

    # -- chrome ----------------------------------------------------------

    def _act(self, text: str, slot, shortcut: str = "", tip: str = "") -> QAction:
        action = QAction(text, self)
        if shortcut:
            action.setShortcut(QKeySequence(shortcut))
        action.setToolTip(tip or text)
        action.triggered.connect(slot)
        return action

    def _build_toolbar(self):
        bar = QToolBar("Main")
        bar.setMovable(False)
        bar.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextOnly)
        self.addToolBar(bar)

        bar.addAction(self._act("Open", self.open_file, "Ctrl+O"))
        bar.addAction(self._act("Save As", self.save_as, "Ctrl+Shift+S"))
        bar.addSeparator()
        bar.addAction(self._act("Previous", lambda: self.step(-1), "Ctrl+Left"))
        bar.addAction(self._act("Next", lambda: self.step(1), "Ctrl+Right"))
        bar.addSeparator()
        bar.addAction(self._act("Zoom Out", lambda: self.view.zoom_by(1 / 1.2), "Ctrl+-"))
        bar.addAction(self._act("Fit Width", self.view.fit_width))
        bar.addAction(self._act("Zoom In", lambda: self.view.zoom_by(1.2), "Ctrl+="))
        bar.addSeparator()
        bar.addAction(self._act("Read Out Loud", self.reading_view, "Ctrl+Shift+L"))
        bar.addSeparator()
        bar.addAction(self._act("Compress", lambda: self.run_tool("compress_target"),
                                "Ctrl+Shift+K"))
        bar.addAction(self._act("OCR", lambda: self.run_tool("ocr")))

    def _build_menus(self):
        menubar = self.menuBar()

        file_menu = menubar.addMenu("&File")
        file_menu.addAction(self._act("Open…", self.open_file, "Ctrl+O"))
        file_menu.addAction(self._act("Save As…", self.save_as, "Ctrl+Shift+S"))
        file_menu.addSeparator()
        for key in ("merge", "images_to_pdf", "office_to_pdf", "split"):
            file_menu.addAction(self._tool_action(key))
        file_menu.addSeparator()
        export = file_menu.addMenu("Export")
        for key in ("pdf_to_word", "tables_to_excel", "pdf_to_text",
                    "pdf_to_images", "extract_images"):
            export.addAction(self._tool_action(key))
        file_menu.addSeparator()
        file_menu.addAction(self._act("Quit", self.close, "Ctrl+Q"))

        view_menu = menubar.addMenu("&View")
        view_menu.addAction(self._act("Reading View", self.reading_view, "Ctrl+Alt+R"))
        view_menu.addAction(self._act("Find", lambda: self.search.field.setFocus(), "Ctrl+F"))
        view_menu.addAction(self._act("Find Next", self.search.next_result, "Ctrl+G"))
        view_menu.addSeparator()
        view_menu.addAction(self._act("Fit Page", self.view.fit_page))
        view_menu.addAction(self._act("Fit Width", self.view.fit_width))

        tools_menu = menubar.addMenu("&Tools")
        groups = [
            ("Size", ["compress", "compress_target", "audit_space", "linearize"]),
            ("Content", ["watermark", "page_numbers", "header_footer", "add_text", "ocr"]),
            ("Privacy", ["redact_search", "metadata_strip", "sanitize",
                         "encrypt", "decrypt"]),
            ("Repair", ["flatten", "repair"]),
            ("Accessibility", ["accessibility_check"]),
            ("Document", ["info"]),
        ]
        for title, keys in groups:
            section = tools_menu.addMenu(title)
            for key in keys:
                section.addAction(self._tool_action(key))

        help_menu = menubar.addMenu("&Help")
        help_menu.addAction(self._act("About RiftPDF", self.about))

    def _tool_action(self, key: str) -> QAction:
        tool = TOOLS[key]
        return self._act(tool.title + "…", lambda checked=False, k=key: self.run_tool(k))

    # -- documents -------------------------------------------------------

    def open_file(self):
        path, _ = QFileDialog.getOpenFileName(self, "Open a PDF", "", "PDF files (*.pdf)")
        if path:
            self.load(path)

    def load(self, path: str):
        error = self.view.load(path)
        if error == "password":
            password, ok = QInputDialog.getText(
                self, "Password required",
                f"{Path(path).name} is protected.\nEnter the password to open it:",
                QLineEdit.EchoMode.Password)
            if not ok:
                return
            error = self.view.load(path, password)
        if error:
            QMessageBox.warning(self, "Could not open", error)
            return
        self.setWindowTitle(f"{Path(path).name} — {APP_NAME}")
        self._page_changed(0, self.view.page_count)

    def save_as(self):
        if not self.view.path:
            return
        target, _ = QFileDialog.getSaveFileName(
            self, "Save a copy", str(self.view.path.with_name(self.view.path.stem + " copy.pdf")),
            "PDF files (*.pdf)")
        if target:
            import shutil
            shutil.copyfile(self.view.path, target)
            self.status_label.setText(f"Saved {Path(target).name}")

    def step(self, delta: int):
        if self.view.page_count:
            self.view.go_to_page(
                max(0, min(self.view.page_count - 1, self.view.current_page + delta)))

    def _page_changed(self, index: int, total: int):
        if total:
            size = ""
            if self.view.path and self.view.path.exists():
                size = f" · {self.view.path.stat().st_size / 1_048_576:.1f} MB"
            self.status_label.setText(f"Page {index + 1} of {total}{size}")

    # -- running tools ---------------------------------------------------

    def run_tool(self, key: str):
        tool = TOOLS[key]
        if tool.needs_document and not self.view.path:
            QMessageBox.information(self, tool.title, "Open a PDF first.")
            return

        dialog = ToolDialog(tool, self, self.view.path)
        if tool.fields and dialog.exec() != QDialog.DialogCode.Accepted:
            return
        values = dialog.values() if tool.fields else {}

        source = str(self.view.path) if self.view.path else None
        output = None
        if tool.output == "saveas":
            suggested = ""
            if self.view.path:
                suggested = str(self.view.path.with_suffix("." + tool.extension))
            elif values.get("inputs"):
                suggested = str(Path(values["inputs"][0]).with_suffix(".pdf"))
            output, _ = QFileDialog.getSaveFileName(
                self, "Save as", suggested, f"*.{tool.extension}")
            if not output:
                return
        elif tool.output == "folder":
            output = QFileDialog.getExistingDirectory(self, "Choose a destination folder")
            if not output:
                return
        elif tool.output == "replace":
            suggested = str(self.view.path.with_name(
                f"{self.view.path.stem} {tool.title.lower()}.pdf")) if self.view.path else ""
            output, _ = QFileDialog.getSaveFileName(
                self, "Save the result as", suggested, "PDF files (*.pdf)")
            if not output:
                return

        payload = build_payload(tool, values, source, output)
        self._start(tool, payload)

    def _start(self, tool, payload: dict):
        self.progress.setVisible(True)
        self.progress.setRange(0, 100)
        self.progress.setValue(0)
        self.status_label.setText(f"{tool.title}…")
        self.setEnabled(True)

        def on_progress(value: float, message: str):
            self.progress.setValue(int(value * 100))
            if message:
                self.status_label.setText(message)

        def on_done(result: dict):
            self.progress.setVisible(False)
            self._finished(tool, result)

        def on_error(message: str, detail: str):
            self.progress.setVisible(False)
            self.status_label.setText("Ready")
            box = QMessageBox(self)
            box.setIcon(QMessageBox.Icon.Warning)
            box.setWindowTitle(tool.title)
            box.setText(message)
            if detail:
                box.setDetailedText(detail)
            box.exec()

        bridge.submit(tool.command, payload, on_progress, on_done, on_error)

    def _finished(self, tool, result: dict):
        if tool.output == "report":
            self._show_report(tool, result)
            self.status_label.setText("Ready")
            return

        summary = self._summarise(tool, result)
        self.status_label.setText(summary)

        produced = result.get("output") or result.get("outputDir")
        if produced and str(produced).lower().endswith(".pdf") and Path(produced).exists():
            answer = QMessageBox.question(
                self, tool.title, f"{summary}\n\nOpen the result now?",
                QMessageBox.StandardButton.Open | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.Open)
            if answer == QMessageBox.StandardButton.Open:
                self.load(produced)
        elif produced:
            QMessageBox.information(self, tool.title, f"{summary}\n\n{produced}")

    def _summarise(self, tool, r: dict) -> str:
        if "beforeHuman" in r:
            text = f"{r['beforeHuman']} → {r['afterHuman']}"
            if r.get("targetHuman"):
                text += (f", under your {r['targetHuman']} target"
                         if r.get("hitTarget") else
                         f" — could not reach {r['targetHuman']}")
            if r.get("settings"):
                text += f" ({r['settings']})"
            return text
        if "pagesRecognised" in r:
            return (f"Recognised {r['pagesRecognised']} page(s), "
                    f"{r['characters']} characters of text added")
        if "removed" in r:
            return "Removed: " + "; ".join(r["removed"])
        if "tables" in r:
            return f"{r['tables']} table(s) exported across {r['sheets']} sheet(s)"
        if "files" in r:
            return f"{len(r['files'])} file(s) written"
        if "occurrences" in r:
            return f"{r['occurrences']} occurrence(s) redacted"
        if "pagesStamped" in r:
            return f"{r['pagesStamped']} page(s) stamped"
        if "pagesNumbered" in r:
            return f"{r['pagesNumbered']} page(s) numbered"
        if "pageCount" in r:
            return f"{r['pageCount']} pages"
        return "Done"

    def _show_report(self, tool, r: dict):
        lines: list[str] = []
        if tool.key == "info":
            lines.append(f"<h3>{Path(self.view.path).name}</h3>")
            lines.append(f"<p>{r.get('pageCount')} pages · {r.get('fileSizeHuman')}"
                         f" · {r.get('imageCount')} images</p>")
            meta = r.get("metadata") or {}
            rows = "".join(f"<tr><td><b>{k}</b></td><td>{v}</td></tr>"
                           for k, v in meta.items() if v)
            if rows:
                lines.append(f"<table cellpadding='4'>{rows}</table>")
            fonts = r.get("fonts") or []
            if fonts:
                lines.append("<h4>Fonts</h4><ul>" + "".join(
                    f"<li>{f['name']} — {f['type']}"
                    f"{'' if f['embedded'] else ' (not embedded)'}</li>" for f in fonts) + "</ul>")
        elif tool.key == "audit_space":
            lines.append(f"<h3>Total {r.get('totalHuman')}</h3><table cellpadding='5'>")
            for row in r.get("categories", []):
                lines.append(f"<tr><td>{row['category']}</td>"
                             f"<td align='right'>{row['human']}</td>"
                             f"<td align='right'>{row['percent']}%</td></tr>")
            lines.append("</table>")
        elif tool.key == "accessibility_check":
            score = r.get("score", 0)
            colour = "#2E9E5B" if score >= 80 else "#C88A2E" if score >= 50 else BRAND
            lines.append(f"<h3 style='color:{colour}'>Score {score} of 100</h3>")
            lines.append(f"<p>{r.get('errors', 0)} errors, {r.get('warnings', 0)} warnings</p>")
            for issue in r.get("issues", []):
                mark = "✕" if issue["severity"] == "error" else "!"
                fixable = "" if issue["fixable"] else \
                    " <i>(cannot be fixed automatically)</i>"
                lines.append(f"<p><b>{mark} {issue['title']}</b>{fixable}<br>"
                             f"<span style='color:#66666E'>{issue['detail']}</span></p>")
        ReportDialog(tool.title, lines, self).exec()

    # -- reading ---------------------------------------------------------

    def reading_view(self):
        if not self.view.path:
            QMessageBox.information(self, "Reading View", "Open a PDF first.")
            return
        self.status_label.setText("Preparing the text…")
        self.progress.setVisible(True)

        def done(result: dict):
            self.progress.setVisible(False)
            blocks = [b for page in result.get("pages", []) for b in page.get("blocks", [])]
            if not blocks:
                QMessageBox.information(
                    self, "Reading View",
                    "No readable text here. If this is a scan, run Tools ▸ Content ▸ "
                    "Recognise Text first.")
                return
            self.status_label.setText("Ready")
            ReadingView(blocks, self).exec()

        def failed(message: str, detail: str):
            self.progress.setVisible(False)
            QMessageBox.warning(self, "Reading View", message)

        bridge.submit("reading_text", {"input": str(self.view.path), "pages": "all"},
                      None, done, failed)

    # -- misc ------------------------------------------------------------

    def _report_capabilities(self):
        caps = bridge.capabilities()
        bits = [f"MuPDF {caps.get('pymupdf', '?')}", f"pikepdf {caps.get('pikepdf', '?')}"]
        if caps.get("ghostscript"):
            bits.append("Ghostscript")
        if caps.get("qpdf"):
            bits.append("qpdf")
        if caps.get("tesseract"):
            bits.append("Tesseract OCR")
        elif caps.get("windowsocr"):
            bits.append("Windows OCR")
        else:
            bits.append("no OCR engine")
        if caps.get("libreoffice"):
            bits.append("LibreOffice")
        elif caps.get("officecom"):
            bits.append("Microsoft Office")
        else:
            bits.append("no Office converter")
        self.statusBar().showMessage(" · ".join(bits), 8000)

    def about(self):
        caps = bridge.capabilities()
        QMessageBox.about(
            self, f"About {APP_NAME}",
            f"<h3>{APP_NAME} {APP_VERSION}</h3>"
            "<p>Everything you need to do to a PDF, on your own machine. "
            "Nothing is uploaded anywhere.</p>"
            f"<p style='color:#66666E'>MuPDF {caps.get('pymupdf')} · "
            f"pikepdf {caps.get('pikepdf')}<br>"
            f"OCR: {_ocr_description(caps)}<br>"
            f"Word to PDF: {_office_description(caps)}</p>")


def _office_description(caps) -> str:
    """Name the converter that will actually be used."""
    if caps.get("libreoffice"):
        return "LibreOffice"
    if caps.get("officecom"):
        return "Microsoft Office, already installed"
    return "not available"


def _ocr_description(caps) -> str:
    """Name the recogniser that will actually be used, not the one that isn't."""
    if caps.get("tesseract"):
        return "Tesseract"
    if caps.get("windowsocr"):
        return "built into Windows, nothing to install"
    return "not available"


def main() -> int:
    # RIFTPDF_QT_CAPABILITIES=1 prints what this build can do and exits without
    # opening a window. A packaged .exe is otherwise very hard to interrogate:
    # the answer that matters is the one from inside the bundle, not from the
    # source tree it was built out of.
    # --command runs one engine command and exits, with no window at all.
    # It makes the app scriptable for batch work, and it is the only way to
    # exercise a packaged .exe's engine without a person clicking things.
    #
    #   RiftPDF.exe --command ocr --input in.pdf --output out.pdf
    #   RiftPDF.exe --command selftest
    #
    # Arguments are plain flags rather than a JSON string because PowerShell
    # strips the quotes out of {"input":"x"} before the program ever sees it,
    # which fails silently. A JSON payload is still accepted, inline or as
    # @payload.json, for callers that can quote it properly.
    if "--command" in sys.argv:
        import json
        at = sys.argv.index("--command")
        rest = sys.argv[at + 1:]
        if not rest:
            print("--command needs the name of a command", file=sys.stderr)
            return 2
        name, rest = rest[0], rest[1:]

        payload = {}
        if rest and rest[0].startswith("@"):
            payload = json.loads(Path(rest[0][1:]).read_text(encoding="utf-8"))
        elif rest and rest[0].lstrip().startswith("{"):
            payload = json.loads(rest[0])
        else:
            key = None
            for piece in rest:
                if piece.startswith("--"):
                    key = piece[2:]
                    payload[key] = True          # a bare flag means yes
                elif key is not None:
                    try:                          # numbers and true/false
                        payload[key] = json.loads(piece)
                    except ValueError:
                        payload[key] = piece
                    key = None

        try:
            outcome = bridge.engine.run_command(name, payload) or {}
        except Exception as exc:
            print(json.dumps({"error": str(exc)}), file=sys.stderr)
            return 1
        print(json.dumps(outcome, indent=2, default=str), file=sys.stderr)
        return 0

    wanted = os.environ.get("RIFTPDF_QT_CAPABILITIES")
    if wanted:
        import json
        report = dict(bridge.capabilities())
        report["ocrBackend"] = bridge.ocr_backend() or "none"
        text = json.dumps(report, indent=2, sort_keys=True)
        if wanted not in ("1", "true", "yes"):
            Path(wanted).write_text(text, encoding="utf-8")
        # A windowed build has no stdout to speak of, but stderr still reaches
        # whoever launched it.
        print(text, file=sys.stderr)
        return 0

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setOrganizationName("RiftPDF")
    app.setStyleSheet(STYLESHEET)

    icon_path = Path(__file__).resolve().parents[2] / "Resources" / "AppIcon.png"
    if icon_path.exists():
        app.setWindowIcon(QIcon(str(icon_path)))

    window = MainWindow()
    window.show()
    for argument in sys.argv[1:]:
        if argument.lower().endswith(".pdf") and os.path.exists(argument):
            window.load(argument)
            break

    # RIFTPDF_QT_SNAPSHOT=/path.png writes a picture of the window and exits.
    # A widget can always grab itself, so this verifies the interface on a
    # machine you cannot see — which is how the Windows build gets checked.
    snapshot = os.environ.get("RIFTPDF_QT_SNAPSHOT")
    if snapshot:
        delay = int(float(os.environ.get("RIFTPDF_QT_SNAPSHOT_DELAY", "3")) * 1000)

        def capture():
            path = Path(snapshot)
            ok = window.grab().save(str(path))
            print(f"snapshot {'written' if ok else 'FAILED'}: {path}", file=sys.stderr)
            print(f"window {window.width()}x{window.height()} visible={window.isVisible()}",
                  file=sys.stderr)
            if os.environ.get("RIFTPDF_QT_SNAPSHOT_QUIT", "1") == "1":
                app.quit()

        QTimer.singleShot(delay, capture)

    return app.exec()
