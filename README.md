# RiftPDF

A PDF editor that runs entirely on your own machine — no uploads, no account,
no subscription.

There are two applications here, sharing one PDF engine:

| | macOS | Windows / Linux |
|---|---|---|
| Interface | Swift + SwiftUI + PDFKit | Python + Qt (PySide6) |
| Live markup tools | yes | not yet — see below |
| All 43 engine operations | yes | yes |
| Read out loud | AVSpeechSynthesizer | Qt TextToSpeech, Windows voices |
| OCR | Apple Vision | built into Windows, or Tesseract |
| Word to PDF | AppKit, or LibreOffice | Microsoft Office, or LibreOffice |

The engine — compression, conversion, redaction, metadata, OCR, accessibility,
everything that actually touches a PDF — is one shared Python module used by
both. The two front ends differ only in how they draw a window.

## Installing

**macOS** — download `RiftPDF-macos.zip` from
[Releases](../../releases), unzip it, and drag **RiftPDF.app** to
`/Applications`. Do not run it from the Desktop: macOS gates anything there
behind the Desktop-access prompt, which blocks the app's own bundled engine.
The first launch may need a right-click → *Open* (ad-hoc signature, not a paid
Developer ID).

**Windows** — download `RiftPDF-<version>-Setup.exe` from
[Releases](../../releases) and run it. No administrator password is needed.
SmartScreen will warn about an unsigned application: *More info* →
*Run anyway*. There is a portable zip on the same page for anyone who would
rather not install anything.

Nothing else has to be fetched. OCR uses the recogniser built into Windows 10
and 11, and Word or Excel conversion uses Microsoft Office if you have it.
Tesseract and LibreOffice are still used in preference where they are present,
but neither is required. [docs/INSTALL.md](docs/INSTALL.md) has the detail,
including how to check the download's SHA-256.

**From source (any platform)**

```bash
./setup.sh                       # builds the Python engine environment
./build.sh                       # macOS app (needs Swift)
engine/.venv/bin/python qt/main.py   # Qt app, runs on macOS, Windows and Linux
```

## What the Windows version does not have

Being straight about the difference: the macOS app's live markup — click-drag
highlighting, freehand ink, shapes, and the resize grips on placed objects — is
built directly on PDFKit. Qt has no equivalent, so it would need a
hand-written canvas with its own hit-testing, undo and annotation writing.
That is a project in itself, not a port, and it is not in this version.

The Windows app can still add text, watermarks, headers, footers, Bates
numbers, page numbers and redactions through the engine — they are applied to
the document rather than drawn by hand.

## What it does

**Viewing and editing**
- Open PDFs; several at once in tabs. Drag files onto the window.
- **Edit Text** (⌃E) — rewrite text that's already in the PDF. RiftPDF erases the
  original glyphs and re-lays your replacement with matching size and colour.
- **Add Text** (⌃T) — drop new text boxes anywhere.
- Highlight, underline, strikethrough, freehand drawing, rectangles, ellipses,
  lines, arrows, sticky notes, eraser.
- Place images and signatures — burned into the page on save, so every other
  PDF reader shows them.
- **Selection handles on everything you place.** Click an object and it gets a
  dashed outline with eight grips. Drag a corner to scale, an edge to stretch,
  the middle to move. Images keep their proportions by default (hold ⇧ to
  distort); shapes and text boxes scale freely (hold ⇧ to lock proportions). A
  live readout shows the size in points while you drag. Arrow keys nudge the
  selection, ⇧+arrows resize, ⌥+arrows move by a single point, and the inspector
  has exact W/H/X/Y fields with a proportions lock.
  Freehand ink rescales its actual strokes, not just its box.
- Full undo/redo on everything.

**Pages**
- Reorder by dragging in the sidebar, delete, duplicate, rotate, extract.
- Insert blank pages or pages from another PDF.
- Resize all pages to Letter/A4/Legal/Tabloid.
- Split into separate files by range, every N pages, or one per page.

**Shrinking files** (Tools ▸ Shrink File Size, or ⇧⌘K)

Two ways to do it:

- *Pick a quality* — four presets from Light to Maximum, plus manual control of
  image resolution, JPEG quality and greyscale conversion.
- *Pick a size* — type the size you need (500 KB, 2 MB, whatever) and RiftPDF
  finds the settings that get there. It binary-searches a quality ladder,
  running a full compression pass at each rung, and keeps the highest quality
  that still fits. Usually lands in about four passes.

Under the hood it downsamples images to what the page actually needs, subsets
fonts, and runs a Ghostscript pass, keeping whichever result is smaller.
Image-heavy documents typically drop 80–95%.

If a target is physically impossible it says so and reports the smallest it
could reach, rather than silently producing something unreadable.

Measured on a 4-page, 2.1 MB report:

| Target | Result | Settings chosen |
|---|---|---|
| 500 KB | 271.9 KB | 180 dpi, quality 80 |
| 100 KB | 86.2 KB | 96 dpi, quality 50 |
| 40 KB | 37.0 KB | 60 dpi, quality 32 |
| 6 KB | 8.7 KB — target missed, reported honestly | 30 dpi, quality 14, greyscale |

**Converting**
- PDF → Word (.docx), preserving layout, tables and styles.
- PDF → plain text, or page images (PNG/JPEG/TIFF at any resolution).
- Word/RTF/ODT/HTML/text → PDF.
- Images → PDF, with page size, fit and margin control.
- Combine any number of PDFs, with a bookmark per source file.
- Extract every embedded image.

**Privacy and security**
- **Redaction that actually removes data** — the underlying text and image bytes
  are deleted, not covered with a black box. Drag over areas, or redact every
  occurrence of a search term.
- Remove metadata: document info, XMP, annotation author names, the trailer ID.
- Strip active content: JavaScript, launch actions, embedded files.
- AES-256 encryption with per-capability permissions.

**Accessibility**
- **Read Out Loud** (⇧⌘L) — 180 on-device voices, adjustable speed, skip by
  paragraph. The reading view highlights each passage as it is spoken.
- **Reading view** (⌥⌘R) — the document reflowed into a single readable column
  with adjustable text size, line spacing, and Paper / Sepia / Night / High
  contrast themes. Useful for long documents, essential for low vision.
- **Display modes** — Night (inverted), Sepia, Greyscale and High contrast
  applied to the live page through Core Image, so text stays sharp rather than
  being covered by a tinted overlay.
- **Accessibility Check** (⇧⌘A) — audits the same things Acrobat's checker does:
  document title, language, tagging, DisplayDocTitle, screen-reader permissions,
  scanned pages with no text, images without alt text, tiny text, unlabelled
  form fields. Scores out of 100 and fixes what it honestly can in one click.
- VoiceOver labels throughout, and full keyboard navigation.

A note on tagging: RiftPDF sets the title, language and viewer hints, but it
will not fabricate a structure tree. Guessed structure is worse than none — it
makes a document *claim* to be accessible when it isn't. The checker says so
plainly instead of quietly inflating the score.

**Acrobat-style extras**
- **Headers, footers and Bates numbering** — six independent fields (left,
  centre, right × header, footer) with `{n} {total} {page} {date} {time}
  {filename} {bates}` tokens. Bates numbering takes a prefix, start number and
  digit count, for legal filings.
- **Tables to Excel** — finds ruled tables and writes a real .xlsx, one sheet
  per table, headers bolded and columns sized. Whitespace-aligned tables are
  opt-in, because guessing at them turns ordinary prose into nonsense.
- **Where the Space Goes** — Acrobat's "audit space usage": what images, fonts,
  content streams and metadata each cost, as a share of the file.
- **Batch processing** (⇧⌘B) — run compress, remove metadata, sanitise, OCR,
  flatten, optimise, or convert to Word/text across many files at once.
  Originals are never touched.

**Other**
- OCR using Apple's on-device Vision framework — adds an invisible, searchable
  text layer to scans. Nothing leaves the machine.
- Watermarks (text or image), page numbers with custom formats.
- Fill and flatten form fields; manage attachments and bookmarks.
- Compare two PDFs word by word.
- Repair damaged files; optimise for fast web view.

## Making it your default PDF reader

Open **RiftPDF ▸ Settings and Engine Status…** (⌘,) and click **Make Default**,
or use the prompt on the welcome screen. macOS shows its own confirmation.

This cannot be done from a script: macOS 13 and later ignore
`LSSetDefaultRoleHandlerForContentType` from outside the app, precisely so that
software cannot quietly seize file associations. The request has to come from
RiftPDF itself, and you have to approve it.

## What this does not do that Acrobat Pro does

Being straight about the gaps:

- **Certified digital signatures** — signing with a PKI certificate, timestamp
  authorities, signature validation. RiftPDF places signature *images*, which is
  a different thing.
- **Automatic tagging** — see the note above.
- **PDF/A and PDF/X conversion, and preflight** — no standards-compliance
  conversion or printing preflight.
- **Portfolios**, Adobe cloud storage, shared review workflows.
- **JavaScript-driven forms** — RiftPDF fills and flattens form fields but does
  not run form scripts.

## Optional extra

Word conversion uses macOS's own typesetter, which handles text, styles and
images well. For pixel-exact fidelity on complex Word layouts:

```
brew install --cask libreoffice
```

RiftPDF detects it automatically and switches to it.

## How it's built

- **UI** — SwiftUI + PDFKit, the same rendering engine Preview uses.
- **Engine** — Python (PyMuPDF, pikepdf, pdf2docx, Pillow) bundled inside the
  app at `Contents/Resources/engine`, driven over a JSON-lines protocol so long
  jobs report live progress.
- **OCR** — Apple Vision.

## Rebuilding

```
./setup.sh     # once, builds the Python environment
./build.sh     # compiles and assembles RiftPDF.app
```

Requires Swift (Xcode Command Line Tools) and Python 3.11+.

## Licence

RiftPDF is free software under the **GNU Affero General Public License v3.0**.
Use it, study it, change it, pass it on — but anything you distribute that is
built from it has to stay free in the same way.

That is not only a preference. PyMuPDF, which does nearly all of the PDF work,
is dual-licensed AGPL-3.0 or commercial, and RiftPDF uses the free option, so
the AGPL follows. [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) lists every
bundled component and its licence.
