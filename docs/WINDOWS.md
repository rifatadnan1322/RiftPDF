# The Windows app — state of play

Updated 10 September 2026, **from the Windows machine itself**. The earlier
version of this file was written on macOS and reported secondhand; everything
below marked confirmed was run here, in the configuration a user actually has.

## Confirmed working on Windows

Windows 10 (19045), Python 3.12.10, PySide6 6.11.2, PyInstaller build:

```
engine: pymupdf 1.28.2, pikepdf 10.13.0.post1, platform win32
ghostscript false, qpdf false, tesseract false, libreoffice false
windowsocr  true
```

- **The .exe launches and renders.** `dist\RiftPDF\RiftPDF.exe` opens a
  1180x800 window, loads a document, draws the page, fills the thumbnail rail
  and reports `Page 1 of 3 · 0.2 MB` in the status bar.
- **Bundled engine resolution.** `engine_bridge` resolves the engine at import
  time, so reaching a window at all proves `sys._MEIPASS/engine` worked.
- **Compression, with no Ghostscript present.** 441,044 bytes to 38,414, a
  120,000-byte target met, page still renders. This is the first test of the
  9 September fix in the condition the bug lived in, and it passes: the
  pure-Python path carries the whole load.
- **OCR, with no Tesseract present.** Through the recogniser built into
  Windows. Run inside the packaged .exe, not just from source: a scanned page
  came back with 16 words and 148 characters, and `Acme` and `1240` are both
  findable. A page that already had real text was copied through untouched.
- **Word and Excel to PDF, with no LibreOffice present.** Through Microsoft
  Office over COM, also run inside the packaged .exe. A .docx came back as one
  page with six embedded fonts, its table and bullets intact.
- **Read Out Loud.** Qt picks the `winrt` engine and finds three Windows
  voices — David, Zira and Mark — and reaches the Speaking state on real text.
  Synthesis is confirmed; whether sound leaves the speakers is not something a
  headless check can see.
- **Redaction removes the bytes.** Not merely a black box drawn on top: after
  redacting, the target string is absent from the decompressed object streams
  while other text on the same page is still there.
- **Every command.** 42 of the engine's 43 commands were run here and all of
  them worked. The 43rd, `merge_annotations`, is macOS-only by design.

## OCR without installing anything

Windows 10 and 11 ship `Windows.Media.Ocr`, reached through the `winsdk`
package. `setup_windows.ps1` installs it; nothing else has to be fetched, and
there is nothing to pay for.

The engine picks a recogniser in `cmd_ocr`: Tesseract when it is installed,
because its accuracy is still the better of the two, and otherwise Windows.
Pass `backend` as `tesseract` or `windows` to force one.

The Windows path is better than the Tesseract path in one respect. Tesseract
rasterises every page to build its layer, so a clean vector page comes back as
a picture of itself. The Windows path keeps the original page and lays an
invisible text layer over it, so nothing is re-rendered and no quality is
lost. Word boxes come from the recogniser, and each word's type is stretched
to the width it was found at, so selecting a word selects that word.

Language packs are what limit it. `en-US` and `fr-CA` are present on this
machine. Asking for one Windows does not have raises an error naming what is
installed, rather than quietly recognising in the wrong language. More can be
added under Settings > Time & language > Language & region.

## Driving it without a window

`--command` runs one engine command and exits, opening nothing. It makes the
app scriptable for batch work, and it is the only way to exercise a packaged
.exe's engine without a person clicking things.

```powershell
$exe = ".\dist\RiftPDF\RiftPDF.exe"

# what this build can do, answered from inside the bundle
Start-Process $exe -ArgumentList "--command","selftest" -Wait -NoNewWindow

# OCR a scan
Start-Process $exe -ArgumentList `
  "--command","ocr","--input","in.pdf","--output","out.pdf" -Wait -NoNewWindow
```

**Use `Start-Process -Wait`, not `& $exe`.** The .exe is built `--windowed`,
so Windows treats it as a GUI program and PowerShell does not wait for it.
Called with `&` it returns immediately, the output file does not exist yet,
and the run looks like a silent failure when it is merely unfinished. This
costs ten minutes to work out every time it is forgotten.

Arguments are plain flags rather than a JSON string for a related reason:
PowerShell 5.1 strips the quotes out of `{"input":"x.pdf"}` before the program
sees it, leaving `{input:x.pdf}`, which is not JSON and fails with no useful
message. Verified, not assumed. A JSON payload is still accepted inline or as
`@payload.json` where the caller can quote it properly.

Results are printed to **stderr**, because a windowed build has no stdout
worth the name.

## Photographing the interface

```powershell
$env:RIFTPDF_QT_SNAPSHOT="C:\Temp\window.png"
.\.venv\Scripts\python.exe qt\main.py some.pdf
```

A widget can always grab itself, so this needs no screen-recording
permission. `RIFTPDF_QT_CAPABILITIES=C:\Temp\caps.json` does the same job for
capabilities without opening a window at all.

## The one command that proves the most

```powershell
.\.venv\Scripts\python.exe tools\selfcheck.py
```

It builds its own test documents and proves both compression and OCR. The two
things most likely to be quietly broken are the two things it checks.

## Known missing on Windows

- **Ghostscript and qpdf** are absent, and nothing here needs them. Compression
  reaches its target without Ghostscript, and `linearize` works without qpdf.
- **OCR languages** are limited to the packs Windows has. This machine has
  `en-US` and `fr-CA`. Asking for one that is not installed raises an error
  naming what is, rather than quietly recognising in the wrong language. More
  can be added under Settings > Time & language > Language & region.
- **LibreOffice** is absent. Office covers Word, Excel and PowerPoint over COM,
  so the only gap left is a machine with neither Office nor LibreOffice, where
  the engine reports the capability as absent rather than failing at the point
  of use.

## Rebuilding

```powershell
git pull
powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1
```

The setup script does not trust that `python` exists: on Windows that name is
usually Microsoft's Store stub, which prints "Python was not found" instead of
failing like a missing command. It asks the `py` launcher first and verifies a
version comes back.

The build must pass `--collect-all winsdk`. winsdk loads its namespaces as
separate extension modules at run time, so nothing static points at them and
PyInstaller would otherwise leave them out, taking OCR with them.
