"""Bridge between the Qt interface and the shared PDF engine.

The engine is the same module the macOS app drives over a subprocess. Here it
is imported and run on a worker thread instead, because a PyInstaller bundle
cannot spawn itself as a subprocess.
"""

from __future__ import annotations

import os
import sys
import traceback
from pathlib import Path

from PySide6.QtCore import QObject, QRunnable, QThreadPool, QTimer, Signal, Slot


def _locate_engine():
    """Find riftpdf_engine whether running from source or from a bundle."""
    candidates = []
    if getattr(sys, "_MEIPASS", None):                 # PyInstaller
        candidates.append(Path(sys._MEIPASS) / "engine")
    here = Path(__file__).resolve()
    candidates.append(here.parents[2] / "engine")      # repo/qt/riftpdf_qt -> repo/engine
    candidates.append(here.parents[1] / "engine")
    for path in candidates:
        if (path / "riftpdf_engine.py").exists():
            if str(path) not in sys.path:
                sys.path.insert(0, str(path))
            break
    import riftpdf_engine
    return riftpdf_engine


engine = _locate_engine()
EngineError = engine.EngineError


class JobSignals(QObject):
    progress = Signal(float, str)
    finished = Signal(dict)
    failed = Signal(str, str)


class Job(QRunnable):
    """One engine command, run off the UI thread."""

    def __init__(self, command: str, payload: dict):
        super().__init__()
        self.command = command
        self.payload = payload
        self.signals = JobSignals()

    @Slot()
    def run(self):
        try:
            result = engine.run_command(
                self.command, self.payload,
                on_progress=lambda value, message: self.signals.progress.emit(value, message))
            self.signals.finished.emit(result or {})
        except EngineError as exc:
            self.signals.failed.emit(str(exc), "")
        except Exception as exc:                       # pragma: no cover - safety net
            self.signals.failed.emit(str(exc), traceback.format_exc())


# QThreadPool deletes a QRunnable as soon as run() returns. That would destroy
# the signals object before its queued emission reaches the UI thread, so the
# work would finish silently and the window would never update. Hold a
# reference until the job has actually reported back.
_active: set[Job] = set()


def submit(command: str, payload: dict, on_progress=None, on_done=None, on_error=None) -> Job:
    job = Job(command, payload)
    job.setAutoDelete(False)
    _active.add(job)

    if on_progress:
        job.signals.progress.connect(on_progress)
    if on_done:
        job.signals.finished.connect(on_done)
    if on_error:
        job.signals.failed.connect(on_error)

    def release(*_):
        # Drop the reference on the next turn of the event loop: discarding it
        # inside the emission could free the emitter mid-signal.
        QTimer.singleShot(0, lambda: _active.discard(job))

    job.signals.finished.connect(release)
    job.signals.failed.connect(release)

    QThreadPool.globalInstance().start(job)
    return job


def capabilities() -> dict:
    try:
        return engine.selftest()
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


def ocr_backend() -> str | None:
    """Which OCR engine this machine can actually use.

    The engine decides; asking it keeps one answer rather than two that can
    drift apart.
    """
    caps = capabilities()
    if caps.get("tesseract"):
        return "tesseract"
    if caps.get("windowsocr"):
        return "windows"
    return None
