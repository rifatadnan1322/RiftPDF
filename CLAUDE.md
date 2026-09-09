# RiftPDF

Two applications sharing one engine. A native macOS app in Swift, and a
Qt application for Windows and Linux, both driving the same Python engine.

```
engine/riftpdf_engine.py   the engine — 40 commands, all the PDF work
Sources/RiftPDF/           macOS app (SwiftUI + PDFKit), ~7,000 lines
qt/riftpdf_qt/             Windows and Linux app (PySide6)
tools/selfcheck.py         proves compression works on this machine
```

The engine runs two ways: the macOS app spawns it as a subprocess and reads
JSON lines from stdout; the Qt app imports it and calls `run_command()` on a
worker thread, because a PyInstaller bundle cannot spawn itself.

## Running and building

```bash
# macOS
./setup.sh && ./build.sh            # installs to /Applications/RiftPDF.app
# Windows
powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1
# either
python tools/selfcheck.py           # capability report + compression proof
python qt/main.py                   # the Qt app
```

Verify an interface without a person watching — both apps photograph their
own windows, which needs no screen-recording permission:

```bash
RIFTPDF_SNAPSHOT=/tmp/a.png RIFTPDF_OPEN=/some.pdf /Applications/RiftPDF.app/Contents/MacOS/RiftPDF
RIFTPDF_QT_SNAPSHOT=/tmp/b.png python qt/main.py some.pdf
```

macOS caveat: `PDFView` draws through a `CATiledLayer`, so the page area comes
out blank in that self-snapshot even when it renders correctly. Use real
`screencapture` to check the macOS canvas. The Qt snapshot has no such problem.

## Things that cost real time to learn

**Compression depended entirely on Ghostscript, silently.** `rewrite_images`
requires `dpi_target` to be strictly less than `dpi_threshold`; both were the
same, so every call raised into an `except` whose message went to a progress
channel nobody read. Image recompression had never run. Ghostscript was doing
100% of the work — and a GUI app launched from Finder inherits a bare PATH with
no `/opt/homebrew/bin`, so the app never found it. It worked in every terminal
test and had never worked in the app. **Test with the external tools absent**:
`tools/selfcheck.py` does this.

**Ghostscript is `gswin64c.exe` on Windows.** `which("gs")` can never find it.
See `TOOL_ALIASES` and `EXTRA_TOOL_DIRS` in the engine.

**A preset that finds nothing to resample must say so.** Compression results
carry `note` and `imageError` for exactly this; a silent 0% reduction reads as
a broken app.

**PDFKit's writer inflates files** — it re-encodes images and duplicates
objects shared between pages, more than doubling a compressed scan. `PDFDoc`
therefore tracks a *backing file* whose bytes are the current content, and
saving copies those bytes rather than re-serialising. Any in-memory edit clears
it, because saving stale bytes would lose the user's markup.
`merge_annotations` transplants markup onto the engine's bytes when PDFKit has
to write. macOS only; the Qt app writes engine output directly.

**Size shown must be the size the user will get.** In-place compression does
not touch the file until save, so the status bar shows `367 KB → 138 KB` while
smaller bytes are pending. A correct backend plus an honest message still read
as failure when the number on screen was the stale one.

**The macOS app must live in `/Applications`.** macOS gates anything under
`~/Desktop` behind the Desktop-access prompt, which blocks the app from reading
its own bundled engine — the symptom is "Engine starting…" forever.

## State

macOS: complete and installed. Windows: `.exe` builds and the interface runs;
see `docs/WINDOWS.md` for what is verified and what is not.

Never claim a feature works without having run it in the configuration the user
has. Three rounds of "it works for me" on the compression bug were three rounds
of testing the wrong machine.
