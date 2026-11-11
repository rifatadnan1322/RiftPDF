# Installing RiftPDF

- [Windows](#windows)
- [macOS](#macos)
- [Checking a download is genuine](#checking-a-download-is-genuine)

## Windows

Download `RiftPDF-<version>-Setup.exe` from the
[releases page](https://github.com/rifatadnan1322/RiftPDF/releases) and run it.

No administrator password is needed. The installer puts RiftPDF in your own
Programs folder by default; if you want it available to everyone on the machine,
choose that on the first page and Windows will ask for permission then.

### Windows will warn you, and here is why

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

If you would rather verify the file than trust that paragraph, see
[Checking a download is genuine](#checking-a-download-is-genuine) below.

### What gets installed

Everything lives in one folder and nothing is scattered elsewhere:

- The application and its bundled Python engine.
- A Start Menu shortcut. A desktop shortcut only if you tick that box.
- An "Open with" entry for PDF files, only if you tick that box.

RiftPDF does **not** make itself your default PDF reader. Windows 10 and 11
reserve that choice for you, in Settings > Apps > Default apps, and an installer
that tries to take it anyway is one you should be suspicious of.

Uninstall from Settings > Apps, or from the Start Menu shortcut. It removes the
folder and its registry entries and leaves nothing behind.

### What it can do on your machine

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

### Running it without installing

The release also carries a portable zip. Unpack it anywhere and run
`RiftPDF.exe`. Nothing is written outside that folder, so it works from a USB
stick, and removing the folder removes the program.

### Nothing leaves your computer

Every operation runs locally. There is no account, no upload, and no telemetry.
That is also why OCR uses the recogniser built into Windows rather than a cloud
service.

## macOS

RiftPDF needs macOS 14 or later. From the
[releases page](https://github.com/rifatadnan1322/RiftPDF/releases), download
the zip that matches your Mac:

- `RiftPDF-macos-apple-silicon.zip` — any Mac with an M-series chip
- `RiftPDF-macos-intel.zip` — a Mac with an Intel processor

If you are not sure which you have, choose Apple menu ▸ **About This Mac** and look at
the *Chip* or *Processor* line. The wrong one will simply refuse to open.

Unzip it, and drag **RiftPDF.app** into `/Applications`. Run it from there, not from the
Desktop or Downloads: macOS gates those folders behind a permission prompt that
stops the app reading its own bundled engine.

### macOS will refuse the first launch, and here is why

RiftPDF is not notarised. Notarisation needs a paid Apple Developer
membership, and this is free software. So the first time you open it, macOS
says it could not verify that RiftPDF is free of malware and offers only
**Done** or **Move to Trash**. Click **Done**, then:

1. Open **System Settings ▸ Privacy & Security**.
2. Scroll down to **Security**. There is a line saying RiftPDF was blocked.
3. Click **Open Anyway**, and confirm with your password or Touch ID.

That button is only there for about an hour after the blocked attempt; if it
has gone, open the app once more to bring it back. macOS remembers the choice,
so this happens once.

On macOS 14 and earlier, right-clicking the app and choosing **Open** does the
same thing in one step.

If you are comfortable in Terminal, this removes the download flag instead:

```bash
xattr -dr com.apple.quarantine /Applications/RiftPDF.app
```

Nothing else needs installing. The app carries its own PDF engine and its own
copy of Python, so every tool works on a Mac that has never had a developer
tool on it.

Either way, [check the download first](#checking-a-download-is-genuine). The
warning cannot tell you whether the file is the real one; the check can.

## Checking a download is genuine

Every package is built by GitHub Actions from the source in the repository,
and there are two ways to check that the file you have is one of them.

### Checksum

Each release has a `SHA256SUMS.txt`. Work out the checksum of your download and
compare it with the line for that file; they should match exactly.

```powershell
Get-FileHash .\RiftPDF-1.1.0-Setup.exe -Algorithm SHA256
```

```bash
shasum -a 256 ~/Downloads/RiftPDF-macos-apple-silicon.zip
```

### Build attestation

Releases after 1.1.0 go further. When a package is built, GitHub signs a
statement recording exactly which file was produced, by which workflow, from
which commit, and stores it in a public log. With the
[GitHub CLI](https://cli.github.com) installed:

```bash
gh attestation verify RiftPDF-macos-apple-silicon.zip --repo rifatadnan1322/RiftPDF
```

It passes only if that exact file was built by this repository's own workflow.
A file that was altered after the build, or built anywhere else, fails. A
checksum shows a download was not damaged or swapped on the way to you; this
shows where it came from in the first place.
