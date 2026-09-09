# The Windows app — state of play

Written 10 September 2026, from a session running on macOS. Everything below
about Windows was reported by the person at that machine, not observed
directly. Anything marked unverified genuinely is.

## Confirmed working on Windows

Built on Windows 10 (19045), Python 3.12.10, PyInstaller 6.22.2:

```
py -3.12 -> Python 3.12.10
engine: pymupdf 1.28.2, pikepdf 10.13.0.post1, platform win32
ghostscript false, qpdf false, tesseract false, libreoffice false
dist\RiftPDF\RiftPDF.exe built successfully
```

The interface itself was run on macOS through the same Qt code: window opens
at 1180x800, document renders, thumbnails, search, toolbar and status bar all
present.

## Not yet verified on Windows

Nobody has confirmed these on the actual machine. Do not describe them as
working until someone has.

- **The .exe actually opening.** It built; whether it launches is unconfirmed.
- **Compression numbers.** `tools/selfcheck.py` proves it in one command, and
  matters more here than anywhere: Windows has no Ghostscript, and Ghostscript
  silently did 100% of the compression until 9 September. This machine is the
  first real test of that fix in the condition it was broken in.
- **Read Out Loud.** Qt's text-to-speech should reach Windows SAPI voices.
- **Bundled engine resolution.** `engine_bridge._locate_engine` looks in
  `sys._MEIPASS/engine`, and the build passes `--add-data ...;engine`. Correct
  in principle, unconfirmed in a frozen build.

## Known missing on Windows

- **OCR** needs Tesseract, which Windows does not ship. Windows 10 and 11 have
  a built-in OCR engine (`Windows.Media.Ocr`, reachable through the `winsdk`
  package) that would need nothing installed. Not implemented.
- **Word to PDF** needs LibreOffice. macOS falls back to AppKit's typesetter;
  Windows has no equivalent. Microsoft Word via COM would work where Office is
  installed. Not implemented.

Both degrade honestly: the engine reports the capability as absent rather than
failing at the point of use.

## Testing without being able to see the machine

```powershell
.\.venv\Scripts\python.exe tools\selfcheck.py     # capabilities + compression proof
$env:RIFTPDF_QT_SNAPSHOT="C:\Temp\window.png"     # the app photographs itself
.\.venv\Scripts\python.exe qt\main.py some.pdf
```

The snapshot hook is the reliable way to check an interface on a machine you
cannot watch. A widget can always grab itself, so it needs no permissions.

## Rebuilding

```powershell
git pull
powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1
```

The setup script does not trust that `python` exists: on Windows that name is
usually Microsoft's Store stub, which prints "Python was not found" instead of
failing like a missing command. It asks the `py` launcher first and verifies a
version comes back.
