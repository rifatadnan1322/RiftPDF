"""Every engine operation, described once and rendered as a dialog.

Writing forty hand-built dialogs would be forty places for bugs, so each tool
declares its fields and how to turn them into an engine payload.
"""

from __future__ import annotations

import os
import tempfile
from dataclasses import dataclass, field as dc_field
from pathlib import Path

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (QCheckBox, QComboBox, QDialog, QDialogButtonBox,
                               QDoubleSpinBox, QFileDialog, QFormLayout, QHBoxLayout,
                               QLabel, QLineEdit, QPlainTextEdit, QPushButton,
                               QSpinBox, QVBoxLayout, QWidget)

PDF = "PDF files (*.pdf)"


@dataclass
class Field:
    key: str
    label: str
    kind: str = "text"          # text | int | float | choice | bool | pages | files | multiline
    default: object = ""
    choices: list = dc_field(default_factory=list)
    minimum: float = 0
    maximum: float = 100000
    hint: str = ""
    depends_on: str = ""        # only shown when this other bool field is on


@dataclass
class Tool:
    key: str
    title: str
    command: str
    subtitle: str = ""
    fields: list = dc_field(default_factory=list)
    output: str = "replace"     # replace | saveas | folder | report | none
    extension: str = "pdf"
    needs_document: bool = True
    confirm: str = "Apply"


TOOLS: dict[str, Tool] = {}


def register(tool: Tool):
    TOOLS[tool.key] = tool
    return tool


# --- size -------------------------------------------------------------------

register(Tool("compress", "Shrink File Size", "compress",
              "Downsample images, subset fonts, rebuild the file.",
              [Field("preset", "Quality", "choice", "balanced",
                     [("Light — barely visible", "light"),
                      ("Balanced", "balanced"),
                      ("Aggressive", "aggressive"),
                      ("Maximum", "extreme")]),
               Field("grayscale", "Convert images to greyscale", "bool", False),
               Field("removeMetadata", "Remove metadata as well", "bool", False)],
              confirm="Compress"))

register(Tool("compress_target", "Compress to a Size", "compress_target",
              "Name the size you need; RiftPDF finds settings that reach it.",
              [Field("targetValue", "Get it under", "float", 500, minimum=1, maximum=100000),
               Field("targetUnit", "Unit", "choice", "KB", [("KB", "KB"), ("MB", "MB")]),
               Field("allowGrayscale", "Allow greyscale if colour will not fit", "bool", True)],
              confirm="Compress"))

register(Tool("audit_space", "Where the Space Goes", "audit_space",
              "What images, fonts and metadata each cost.", [], output="report"))

# --- convert ----------------------------------------------------------------

register(Tool("pdf_to_word", "Export to Word", "pdf_to_word",
              "Rebuilds the layout as a .docx.",
              [Field("pages", "Pages", "pages", "all", hint="all, or 1-3,7")],
              output="saveas", extension="docx", confirm="Export"))

register(Tool("tables_to_excel", "Tables to Excel", "tables_to_excel",
              "Finds ruled tables and writes a spreadsheet.",
              [Field("pages", "Pages", "pages", "all"),
               Field("includeUnruled", "Also guess at tables without borders", "bool", False,
                     hint="Off by default: on prose this invents tables that are not there.")],
              output="saveas", extension="xlsx", confirm="Export"))

register(Tool("pdf_to_text", "Export as Text", "pdf_to_text",
              "Plain text, in reading order.",
              [Field("pages", "Pages", "pages", "all"),
               Field("pageBreaks", "Separate pages with rules", "bool", True)],
              output="saveas", extension="txt", confirm="Export"))

register(Tool("pdf_to_images", "Export as Images", "pdf_to_images",
              "One image per page.",
              [Field("pages", "Pages", "pages", "all"),
               Field("dpi", "Resolution (dpi)", "int", 200, minimum=36, maximum=900),
               Field("format", "Format", "choice", "png",
                     [("PNG", "png"), ("JPEG", "jpg")])],
              output="folder", confirm="Export"))

register(Tool("extract_images", "Extract Images", "extract_images",
              "Pull out the pictures the document already contains.",
              [Field("minPixels", "Ignore anything smaller than (px)", "int", 64,
                     minimum=1, maximum=4000)],
              output="folder", confirm="Extract"))

register(Tool("office_to_pdf", "Word to PDF", "office_to_pdf",
              "Uses LibreOffice, or Microsoft Office where it is installed.",
              [Field("input", "Word document", "files", "", hint="Choose a .docx or .doc")],
              output="saveas", needs_document=False, confirm="Convert"))

register(Tool("images_to_pdf", "Images to PDF", "images_to_pdf",
              "Combine pictures into one document.",
              [Field("inputs", "Images", "files", ""),
               Field("pageSize", "Page size", "choice", "auto",
                     [("Fit each image", "auto"), ("Letter", "letter"), ("A4", "a4"),
                      ("Legal", "legal"), ("A3", "a3")]),
               Field("quality", "JPEG quality", "int", 88, minimum=30, maximum=100),
               Field("margin", "Margin (pt)", "float", 0, minimum=0, maximum=200)],
              output="saveas", needs_document=False, confirm="Create"))

# --- assemble ---------------------------------------------------------------

register(Tool("merge", "Combine PDFs", "merge",
              "Join documents into one.",
              [Field("inputs", "Documents", "files", ""),
               Field("bookmarkPerFile", "Add a bookmark for each file", "bool", True)],
              output="saveas", needs_document=False, confirm="Combine"))

register(Tool("split", "Split Document", "split",
              "Break one document into several.",
              [Field("mode", "Split", "choice", "every",
                     [("Every N pages", "every"), ("One file per page", "each")]),
               Field("every", "N", "int", 1, minimum=1, maximum=5000)],
              output="folder", confirm="Split"))

# --- content ----------------------------------------------------------------

register(Tool("watermark", "Add Watermark", "watermark",
              "Stamp text across the pages.",
              [Field("text", "Text", "text", "DRAFT"),
               Field("opacity", "Opacity", "float", 0.18, minimum=0.02, maximum=1),
               Field("rotate", "Rotation", "choice", 45,
                     [("Diagonal", 45), ("Horizontal", 0), ("Vertical", 90)]),
               Field("fontSize", "Size (0 = fit the page)", "float", 0, minimum=0, maximum=400),
               Field("pages", "Pages", "pages", "all")],
              confirm="Stamp"))

register(Tool("page_numbers", "Add Page Numbers", "page_numbers",
              "Tokens: {n} {total} {page} {filename}",
              [Field("format", "Format", "text", "{n}"),
               Field("position", "Position", "choice", "bottom-center",
                     [("Bottom centre", "bottom-center"), ("Bottom right", "bottom-right"),
                      ("Bottom left", "bottom-left"), ("Top centre", "top-center"),
                      ("Top right", "top-right"), ("Top left", "top-left")]),
               Field("startAt", "First number", "int", 1, minimum=0, maximum=100000),
               Field("fontSize", "Size (pt)", "float", 10, minimum=5, maximum=48),
               Field("margin", "Margin (pt)", "float", 32, minimum=4, maximum=200),
               Field("pages", "Pages", "pages", "all")],
              confirm="Add"))

register(Tool("header_footer", "Headers, Footers and Bates", "header_footer",
              "Tokens: {n} {total} {page} {date} {time} {filename} {bates}",
              [Field("header_left", "Header left", "text", ""),
               Field("header_center", "Header centre", "text", ""),
               Field("header_right", "Header right", "text", ""),
               Field("footer_left", "Footer left", "text", ""),
               Field("footer_center", "Footer centre", "text", "Page {n} of {total}"),
               Field("footer_right", "Footer right", "text", ""),
               Field("useBates", "Bates numbering", "bool", False),
               Field("batesPrefix", "Bates prefix", "text", "", depends_on="useBates"),
               Field("batesStart", "Bates start", "int", 1, minimum=0, maximum=10**8,
                     depends_on="useBates"),
               Field("batesDigits", "Bates digits", "int", 6, minimum=3, maximum=10,
                     depends_on="useBates"),
               Field("fontSize", "Size (pt)", "float", 9, minimum=5, maximum=48),
               Field("margin", "Margin (pt)", "float", 28, minimum=4, maximum=200),
               Field("pages", "Pages", "pages", "all")],
              confirm="Apply"))

register(Tool("add_text", "Add Text", "add_text",
              "Place a block of text on a page.",
              [Field("page", "Page number", "int", 1, minimum=1, maximum=100000),
               Field("text", "Text", "multiline", ""),
               Field("x", "From left (pt)", "float", 72, minimum=0, maximum=5000),
               Field("y", "From top (pt)", "float", 72, minimum=0, maximum=5000),
               Field("width", "Width (pt)", "float", 400, minimum=20, maximum=5000),
               Field("height", "Height (pt)", "float", 120, minimum=10, maximum=5000),
               Field("size", "Font size", "float", 12, minimum=4, maximum=200),
               Field("align", "Alignment", "choice", "left",
                     [("Left", "left"), ("Centre", "center"), ("Right", "right"),
                      ("Justified", "justify")])],
              confirm="Add"))

# --- privacy ----------------------------------------------------------------

register(Tool("redact_search", "Redact by Search", "redact_search",
              "Finds each occurrence and removes it from the file, not just covers it.",
              [Field("terms", "Terms (one per line)", "multiline", "")],
              confirm="Redact"))

register(Tool("metadata_strip", "Remove Metadata", "metadata_strip",
              "Clears the document information, XMP and the trailer identifier.",
              [Field("removeAnnotationAuthors", "Also clear names on annotations", "bool", True),
               Field("removeAttachments", "Remove embedded files", "bool", False)],
              confirm="Remove"))

register(Tool("sanitize", "Remove Active Content", "sanitize",
              "Strips JavaScript, launch actions and embedded files.", [],
              confirm="Sanitise"))

register(Tool("encrypt", "Protect with a Password", "encrypt",
              "AES-256. Keep the password safe — it cannot be recovered.",
              [Field("userPassword", "Password to open", "text", ""),
               Field("ownerPassword", "Password to change permissions", "text", ""),
               Field("allowPrinting", "Allow printing", "bool", True),
               Field("allowCopying", "Allow copying text", "bool", True)],
              confirm="Protect"))

register(Tool("decrypt", "Remove Password", "decrypt",
              "You must know the current password.",
              [Field("password", "Current password", "text", "")],
              confirm="Remove"))

# --- repair and accessibility ----------------------------------------------

register(Tool("flatten", "Flatten Markup", "flatten",
              "Bakes annotations into the page so they cannot be edited.", [],
              confirm="Flatten"))

register(Tool("linearize", "Optimise for Web", "linearize",
              "Reorders the file so the first page shows before the rest downloads.", [],
              confirm="Optimise"))

register(Tool("repair", "Repair Document", "repair",
              "Rebuilds a damaged file structure.", [], confirm="Repair"))

register(Tool("ocr", "Recognise Text (OCR)", "ocr",
              "Adds a searchable text layer to scanned pages. Pages that already "
              "have real text are left alone.",
              [Field("pages", "Pages", "pages", "all"),
               Field("language", "Language", "choice", "eng",
                     [("English", "eng"), ("French", "fra"), ("German", "deu"),
                      ("Spanish", "spa"), ("Italian", "ita"), ("Portuguese", "por"),
                      ("Bengali", "ben"), ("Hindi", "hin"), ("Arabic", "ara"),
                      ("Chinese (simplified)", "chi_sim"), ("Japanese", "jpn")]),
               Field("dpi", "Scan resolution (dpi)", "int", 300, minimum=150, maximum=600),
               Field("force", "Re-read pages that already have text", "bool", False)],
              confirm="Recognise"))

register(Tool("accessibility_check", "Accessibility Check", "accessibility_check",
              "Audits title, language, tagging, scans and alt text.", [], output="report"))

register(Tool("info", "Document Properties", "info", "", [], output="report"))


# --- dialog -----------------------------------------------------------------

class ToolDialog(QDialog):
    def __init__(self, tool: Tool, parent=None, document_path: Path | None = None):
        super().__init__(parent)
        self.tool = tool
        self.document_path = document_path
        self.widgets: dict[str, QWidget] = {}
        self.chosen_files: dict[str, list[str]] = {}

        self.setWindowTitle(tool.title)
        self.setMinimumWidth(460)

        layout = QVBoxLayout(self)
        heading = QLabel(tool.title)
        heading.setProperty("heading", True)
        layout.addWidget(heading)
        if tool.subtitle:
            sub = QLabel(tool.subtitle)
            sub.setProperty("hint", True)
            sub.setWordWrap(True)
            layout.addWidget(sub)

        form = QFormLayout()
        form.setSpacing(9)
        for spec in tool.fields:
            widget = self._build(spec)
            self.widgets[spec.key] = widget
            row = widget
            if spec.hint:
                container = QWidget()
                box = QVBoxLayout(container)
                box.setContentsMargins(0, 0, 0, 0)
                box.setSpacing(2)
                box.addWidget(widget)
                note = QLabel(spec.hint)
                note.setProperty("hint", True)
                note.setWordWrap(True)
                box.addWidget(note)
                row = container
            form.addRow(spec.label if spec.kind != "bool" else "", row)
        layout.addLayout(form)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Cancel)
        self.ok = buttons.addButton(tool.confirm, QDialogButtonBox.ButtonRole.AcceptRole)
        self.ok.setDefault(True)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

        self._apply_dependencies()

    def _build(self, spec: Field) -> QWidget:
        if spec.kind == "bool":
            widget = QCheckBox(spec.label)
            widget.setChecked(bool(spec.default))
            widget.toggled.connect(self._apply_dependencies)
            return widget
        if spec.kind == "choice":
            widget = QComboBox()
            for label, value in spec.choices:
                widget.addItem(label, value)
            index = widget.findData(spec.default)
            widget.setCurrentIndex(max(0, index))
            return widget
        if spec.kind == "int":
            widget = QSpinBox()
            widget.setRange(int(spec.minimum), int(spec.maximum))
            widget.setValue(int(spec.default))
            return widget
        if spec.kind == "float":
            widget = QDoubleSpinBox()
            widget.setRange(spec.minimum, spec.maximum)
            widget.setDecimals(2)
            widget.setValue(float(spec.default))
            return widget
        if spec.kind == "multiline":
            widget = QPlainTextEdit()
            widget.setPlainText(str(spec.default))
            widget.setFixedHeight(90)
            return widget
        if spec.kind == "files":
            return self._file_picker(spec)
        widget = QLineEdit(str(spec.default))
        return widget

    def _file_picker(self, spec: Field) -> QWidget:
        container = QWidget()
        row = QHBoxLayout(container)
        row.setContentsMargins(0, 0, 0, 0)
        label = QLabel("Nothing chosen")
        label.setProperty("hint", True)
        button = QPushButton("Choose…")
        multiple = spec.key == "inputs"
        images = spec.key == "inputs" and self.tool.key == "images_to_pdf"

        def choose():
            if images:
                filt = "Images (*.png *.jpg *.jpeg *.tif *.tiff *.bmp *.gif *.heic *.webp)"
            elif self.tool.key == "office_to_pdf":
                filt = "Word documents (*.docx *.doc *.rtf *.odt)"
            else:
                filt = PDF
            if multiple:
                paths, _ = QFileDialog.getOpenFileNames(self, spec.label, "", filt)
            else:
                path, _ = QFileDialog.getOpenFileName(self, spec.label, "", filt)
                paths = [path] if path else []
            if paths:
                self.chosen_files[spec.key] = paths
                label.setText(f"{len(paths)} file{'' if len(paths) == 1 else 's'} chosen"
                              if multiple else Path(paths[0]).name)
                self._apply_dependencies()

        button.clicked.connect(choose)
        row.addWidget(label, 1)
        row.addWidget(button)
        container.setProperty("picker", True)
        return container

    def _apply_dependencies(self):
        for spec in self.tool.fields:
            if not spec.depends_on:
                continue
            master = self.widgets.get(spec.depends_on)
            visible = isinstance(master, QCheckBox) and master.isChecked()
            widget = self.widgets.get(spec.key)
            if widget is not None:
                widget.setEnabled(visible)
        needs_files = any(f.kind == "files" for f in self.tool.fields)
        if needs_files:
            ready = all(self.chosen_files.get(f.key)
                        for f in self.tool.fields if f.kind == "files")
            self.ok.setEnabled(bool(ready))

    # -- values ----------------------------------------------------------

    def values(self) -> dict:
        out: dict = {}
        for spec in self.tool.fields:
            widget = self.widgets[spec.key]
            if spec.kind == "bool":
                out[spec.key] = widget.isChecked()
            elif spec.kind == "choice":
                out[spec.key] = widget.currentData()
            elif spec.kind in ("int",):
                out[spec.key] = widget.value()
            elif spec.kind == "float":
                out[spec.key] = widget.value()
            elif spec.kind == "multiline":
                out[spec.key] = widget.toPlainText()
            elif spec.kind == "files":
                out[spec.key] = self.chosen_files.get(spec.key, [])
            else:
                out[spec.key] = widget.text()
        return out


def build_payload(tool: Tool, values: dict, input_path: str | None,
                  output_path: str | None) -> dict:
    """Turn dialog values into what the engine expects."""
    payload: dict = {}
    if input_path:
        payload["input"] = input_path
    if output_path:
        if tool.output == "folder":
            payload["outputDir"] = output_path
        else:
            payload["output"] = output_path

    key = tool.key
    if key == "compress_target":
        unit = values.get("targetUnit", "KB")
        payload["targetBytes"] = int(values["targetValue"] * (1048576 if unit == "MB" else 1024))
        payload["allowGrayscale"] = values.get("allowGrayscale", True)
        return payload

    if key == "header_footer":
        payload.update({
            "header": {"left": values["header_left"], "center": values["header_center"],
                       "right": values["header_right"]},
            "footer": {"left": values["footer_left"], "center": values["footer_center"],
                       "right": values["footer_right"]},
            "fontSize": values["fontSize"], "margin": values["margin"],
            "pages": values["pages"],
            "batesPrefix": values["batesPrefix"] if values.get("useBates") else "",
            "batesStart": values["batesStart"], "batesDigits": values["batesDigits"],
        })
        from datetime import datetime
        now = datetime.now()
        payload["date"] = now.strftime("%d %b %Y")
        payload["time"] = now.strftime("%H:%M")
        return payload

    if key == "redact_search":
        payload["terms"] = [line.strip() for line in values["terms"].splitlines() if line.strip()]
        return payload

    if key == "add_text":
        x, y = values["x"], values["y"]
        payload["items"] = [{
            "page": int(values["page"]) - 1,
            "text": values["text"],
            "rect": [x, y, x + values["width"], y + values["height"]],
            "size": values["size"], "align": values["align"],
        }]
        return payload

    if key == "encrypt":
        payload.update({
            "userPassword": values["userPassword"],
            "ownerPassword": values["ownerPassword"] or values["userPassword"],
            "allowPrinting": values["allowPrinting"],
            "allowCopying": values["allowCopying"],
        })
        return payload

    if key in ("merge", "images_to_pdf"):
        payload["inputs"] = values["inputs"]
        payload.pop("input", None)
        for extra in ("bookmarkPerFile", "pageSize", "quality", "margin"):
            if extra in values:
                payload[extra] = values[extra]
        return payload

    if key == "office_to_pdf":
        payload["input"] = values["input"][0] if values.get("input") else input_path
        return payload

    payload.update({k: v for k, v in values.items()
                    if k not in ("targetValue", "targetUnit")})
    return payload
