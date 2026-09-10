# Third-party notices

RiftPDF is distributed under the GNU Affero General Public License v3.0. That
choice is not arbitrary — it follows from what the engine is built on, and this
file records why, along with what every bundled component is licensed under.

Licences below were read from the installed package metadata rather than from
memory. Nothing here is legal advice; it is a record of what ships.

## Why AGPL-3.0

**PyMuPDF**, which does essentially all of the PDF work, is dual-licensed:
GNU AGPL-3.0, or a paid commercial licence from Artifex. RiftPDF uses the
free option, and the AGPL is a strong copyleft licence, so a distributed work
built on it has to be AGPL-3.0 as well. Permissive licences such as MIT or
Apache-2.0 are therefore not available to this project while it depends on
PyMuPDF under the AGPL.

The practical effect lines up with the goal of the project. Anyone may use,
study, modify and redistribute RiftPDF at no cost. Nobody may take it
closed-source and sell it.

**PySide6** is offered under LGPL-3.0, GPL-2.0 or GPL-3.0; RiftPDF relies on
the LGPL-3.0 option, which AGPL-3.0 is compatible with. The Windows build
bundles the Qt libraries with PyInstaller. The corresponding source for
RiftPDF is at the repository below, and Qt's own source is available from the
Qt Project.

## Bundled components

| Component | Version | Licence |
| --- | --- | --- |
| PyMuPDF | 1.28.2 | AGPL-3.0, or Artifex commercial |
| PySide6 / PySide6-Essentials / PySide6-Addons | 6.11.2 | LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only |
| shiboken6 | 6.11.2 | LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only |
| pikepdf | 10.13.0.post1 | MPL-2.0 |
| Pillow | 12.3.0 | MIT-CMU |
| numpy | 2.5.3 | BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0 |
| lxml | 6.1.3 | BSD-3-Clause |
| opencv-python-headless | 5.0.0.93 | Apache-2.0 |
| fonttools | 4.64.0 | MIT |
| pdf2docx | 0.5.13 | MIT |
| python-docx | 1.2.0 | MIT |
| openpyxl | 3.1.5 | MIT |
| et_xmlfile | 2.0.0 | MIT |
| fire | 0.7.1 | Apache-2.0 |
| termcolor | 3.3.0 | MIT |
| typing_extensions | 4.16.0 | PSF-2.0 |
| winsdk | 1.0.0b10 | MIT |
| pywin32-ctypes | 0.2.3 | BSD-3-Clause |

## Components used but not bundled

These are found on the machine at run time if they are there, and are neither
shipped nor required:

- **Microsoft Office**, driven over COM for Word, Excel and PowerPoint
  conversion. Whatever licence the user already holds.
- **Windows.Media.Ocr**, part of Windows itself, used for OCR.
- **Ghostscript** (AGPL-3.0 or commercial), **qpdf** (Apache-2.0),
  **Tesseract** (Apache-2.0) and **LibreOffice** (MPL-2.0) are used in
  preference where installed. None is required.

## Source

https://github.com/rifatadnan1322/RiftPDF
