#!/usr/bin/env python3
"""Entry point for RiftPDF on Windows and Linux."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from riftpdf_qt.app import main

if __name__ == "__main__":
    sys.exit(main())
