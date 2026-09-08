"""Document view: pages, thumbnails, search."""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QSize, Qt, Signal, QTimer
from PySide6.QtGui import QIcon, QImage, QPixmap
from PySide6.QtPdf import QPdfDocument, QPdfSearchModel
from PySide6.QtPdfWidgets import QPdfView
from PySide6.QtWidgets import (QHBoxLayout, QLabel, QLineEdit, QListWidget,
                               QListWidgetItem, QVBoxLayout, QWidget)


class ThumbnailStrip(QWidget):
    """Page thumbnails down the side. Rendering is deferred so opening a large
    document does not stall the interface."""

    pageSelected = Signal(int)

    def __init__(self):
        super().__init__()
        self.document: QPdfDocument | None = None
        self._pending: list[int] = []

        self.list = QListWidget()
        self.list.setIconSize(QSize(96, 124))
        self.list.setSpacing(3)
        self.list.currentRowChanged.connect(self._row_changed)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(6, 6, 6, 6)
        layout.addWidget(self.list)

        self._timer = QTimer(self)
        self._timer.setInterval(10)
        self._timer.timeout.connect(self._render_next)

    def setDocument(self, document: QPdfDocument | None):
        self.document = document
        self.list.clear()
        self._pending = []
        if document is None:
            return
        for index in range(document.pageCount()):
            item = QListWidgetItem(f"  {index + 1}")
            item.setSizeHint(QSize(150, 132))
            self.list.addItem(item)
            self._pending.append(index)
        self._timer.start()

    def _render_next(self):
        if not self._pending or self.document is None:
            self._timer.stop()
            return
        index = self._pending.pop(0)
        size = self.document.pagePointSize(index)
        if size.width() <= 0:
            return
        scale = 96 / size.width()
        image = self.document.render(index, QSize(96, max(1, int(size.height() * scale))))
        item = self.list.item(index)
        if item is not None and not image.isNull():
            item.setIcon(QIcon(QPixmap.fromImage(image)))

    def _row_changed(self, row: int):
        if row >= 0:
            self.pageSelected.emit(row)

    def highlight(self, page: int):
        if 0 <= page < self.list.count() and self.list.currentRow() != page:
            self.list.blockSignals(True)
            self.list.setCurrentRow(page)
            self.list.blockSignals(False)


class SearchBar(QWidget):
    def __init__(self, view: QPdfView):
        super().__init__()
        self.view = view
        self.model = QPdfSearchModel()
        view.setSearchModel(self.model)

        self.field = QLineEdit()
        self.field.setPlaceholderText("Find in document")
        self.field.textChanged.connect(self._search)
        self.field.returnPressed.connect(self.next_result)

        self.count = QLabel("")
        self.count.setProperty("hint", True)

        layout = QHBoxLayout(self)
        layout.setContentsMargins(8, 6, 8, 6)
        layout.addWidget(self.field)
        layout.addWidget(self.count)
        self._index = -1

    def _search(self, text: str):
        self.model.setSearchString(text)
        self._index = -1
        QTimer.singleShot(180, self._update_count)

    def _update_count(self):
        total = self.model.rowCount()
        self.count.setText(f"{total} match{'' if total == 1 else 'es'}"
                           if self.model.searchString() else "")

    def next_result(self):
        total = self.model.rowCount()
        if not total:
            return
        self._index = (self._index + 1) % total
        link = self.model.resultAtIndex(self._index)
        self.view.pageNavigator().jump(link.page(), link.location())
        self.count.setText(f"{self._index + 1} of {total}")


class DocumentView(QWidget):
    """The reading surface plus its thumbnail strip."""

    pageChanged = Signal(int, int)
    documentChanged = Signal()

    def __init__(self):
        super().__init__()
        self.document = QPdfDocument(self)
        self.path: Path | None = None

        self.view = QPdfView()
        self.view.setDocument(self.document)
        self.view.setPageMode(QPdfView.PageMode.MultiPage)
        self.view.setZoomMode(QPdfView.ZoomMode.FitToWidth)
        self.view.setDocumentMargins(__import__("PySide6").QtCore.QMargins(12, 12, 12, 12))

        self.thumbnails = ThumbnailStrip()
        self.thumbnails.pageSelected.connect(self.go_to_page)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.view)

        self.view.pageNavigator().currentPageChanged.connect(self._page_changed)

    # -- loading ---------------------------------------------------------

    def load(self, path: str | Path, password: str | None = None) -> str | None:
        """Returns an error message, or None on success."""
        path = Path(path)
        if password:
            self.document.setPassword(password)
        status = self.document.load(str(path))
        if status == QPdfDocument.Error.IncorrectPassword:
            return "password"
        if status != QPdfDocument.Error.None_:
            return f"Could not open {path.name}. The file may be damaged."
        self.path = path
        self.thumbnails.setDocument(self.document)
        self.documentChanged.emit()
        self._page_changed(0)
        return None

    def reload(self):
        if self.path:
            page = self.view.pageNavigator().currentPage()
            self.document.load(str(self.path))
            self.thumbnails.setDocument(self.document)
            self.go_to_page(min(page, max(0, self.document.pageCount() - 1)))
            self.documentChanged.emit()

    # -- navigation ------------------------------------------------------

    def go_to_page(self, index: int):
        from PySide6.QtCore import QPointF
        self.view.pageNavigator().jump(index, QPointF(0, 0))

    def _page_changed(self, index: int):
        self.thumbnails.highlight(index)
        self.pageChanged.emit(index, self.document.pageCount())

    def zoom_by(self, factor: float):
        self.view.setZoomMode(QPdfView.ZoomMode.Custom)
        self.view.setZoomFactor(max(0.1, min(8.0, self.view.zoomFactor() * factor)))

    def fit_width(self):
        self.view.setZoomMode(QPdfView.ZoomMode.FitToWidth)

    def fit_page(self):
        self.view.setZoomMode(QPdfView.ZoomMode.FitInView)

    @property
    def page_count(self) -> int:
        return self.document.pageCount()

    @property
    def current_page(self) -> int:
        return self.view.pageNavigator().currentPage()
