# Security

## Reporting a problem

If you find a security problem in RiftPDF, please report it privately rather
than in a public issue: on this repository, open the **Security** tab and choose
**Report a vulnerability**. If that button is not there, open an ordinary issue
saying only that you have a security report, with no details, and you will be
contacted.

Useful things to include: the RiftPDF version, the operating system, and a file
or the steps that show the problem. A PDF that crashes the app or makes it do
something it should not is exactly the kind of report wanted here.

Fixes go into the next release. Only the latest release is supported.

## What RiftPDF does and does not do

- It makes **no network connections**. There is no account, no telemetry, no
  update check and no cloud OCR. Documents never leave the machine.
- It does not run JavaScript embedded in PDFs.
- Redaction deletes the underlying text and image bytes; it does not draw a box
  over them.

## How to know a download is genuine

Every package on the [releases page](../../releases) is built by GitHub Actions
from the source in this repository — never on anyone's own computer — and each
release publishes SHA-256 checksums. Releases after 1.1.0 also carry a signed
build attestation, so you can prove a file was built by this repository from a
specific commit. [docs/INSTALL.md](docs/INSTALL.md#checking-a-download-is-genuine)
shows how.

The packages are not yet code signed, which is why Windows and macOS warn on
first launch. The [code signing policy](README.md#code-signing-policy) explains
where that stands.
