# Installing RiftPDF on Windows

Download `RiftPDF-<version>-Setup.exe` from the
[releases page](https://github.com/rifatadnan1322/RiftPDF/releases) and run it.

No administrator password is needed. The installer puts RiftPDF in your own
Programs folder by default; if you want it available to everyone on the machine,
choose that on the first page and Windows will ask for permission then.

## Windows will warn you, and here is why

RiftPDF is not code signed. A signing certificate costs a few hundred pounds a
year, and this is free software, so the money is not spent. The consequence is
that Windows SmartScreen shows a blue box the first time anyone runs the
installer:

> **Windows protected your PC**
> Microsoft Defender SmartScreen prevented an unrecognised app from starting.

To continue: click **More info**, then **Run anyway**.

That warning is about *reputation*, not about anything found in the file.
SmartScreen flags any installer it has not seen enough times before, signed or
not. It stops appearing as more people download a given release.

If you would rather verify the file than trust that paragraph, every release
publishes a SHA-256 checksum. Compare it against your download:

```powershell
Get-FileHash .\RiftPDF-1.1.0-Setup.exe -Algorithm SHA256
```

The value it prints should match `SHA256SUMS.txt` on the release page exactly.

## What gets installed

Everything lives in one folder and nothing is scattered elsewhere:

- The application and its bundled Python engine.
- A Start Menu shortcut. A desktop shortcut only if you tick that box.
- An "Open with" entry for PDF files, only if you tick that box.

RiftPDF does **not** make itself your default PDF reader. Windows 10 and 11
reserve that choice for you, in Settings > Apps > Default apps, and an installer
that tries to take it anyway is one you should be suspicious of.

Uninstall from Settings > Apps, or from the Start Menu shortcut. It removes the
folder and its registry entries and leaves nothing behind.

## What it can do on your machine

RiftPDF adapts to what Windows already provides, and needs nothing fetched:

| Feature | Needs | On a stock Windows 10/11 machine |
| --- | --- | --- |
| Compression | nothing | works |
| OCR (searchable scans) | nothing | works, via the recogniser built into Windows |
| Word/Excel to PDF | Microsoft Office **or** LibreOffice | works if either is installed |
| Read Out Loud | nothing | works, using Windows voices |

To see what your own machine reports, run this from the install folder:

```powershell
Start-Process .\RiftPDF.exe -ArgumentList "--command","selftest" -Wait -NoNewWindow
```

OCR languages are limited to the packs Windows has. Add more under
Settings > Time & language > Language & region.

## Running it without installing

The release also carries a portable zip. Unpack it anywhere and run
`RiftPDF.exe`. Nothing is written outside that folder, so it works from a USB
stick, and removing the folder removes the program.

## Nothing leaves your computer

Every operation runs locally. There is no account, no upload, and no telemetry.
That is also why OCR uses the recogniser built into Windows rather than a cloud
service.
