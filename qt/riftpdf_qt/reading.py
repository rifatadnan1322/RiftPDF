"""Reflowed reading view with Read Out Loud."""

from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtGui import QFont, QTextCursor
from PySide6.QtTextToSpeech import QTextToSpeech
from PySide6.QtWidgets import (QComboBox, QDialog, QHBoxLayout, QLabel, QPushButton,
                               QSlider, QTextEdit, QVBoxLayout, QWidget)

THEMES = {
    "Paper": ("#FCFCFD", "#1B1B1F"),
    "Sepia": ("#F8EFDD", "#3D2E1A"),
    "Night": ("#17171A", "#E0E0E4"),
    "High contrast": ("#000000", "#FFE500"),
}


class ReadingView(QDialog):
    def __init__(self, blocks: list[dict], parent=None):
        super().__init__(parent)
        self.setWindowTitle("Reading View")
        self.resize(880, 700)
        self.blocks = blocks
        self.scale = 1.0
        self._speaking_index = -1

        self.speech = QTextToSpeech(self)

        controls = QHBoxLayout()
        self.play = QPushButton("Read Out Loud")
        self.play.setDefault(True)
        self.play.clicked.connect(self.toggle)
        self.stop = QPushButton("Stop")
        self.stop.clicked.connect(self.halt)
        self.stop.setEnabled(False)

        self.voice = QComboBox()
        for voice in self.speech.availableVoices():
            self.voice.addItem(voice.name(), voice)
        self.voice.currentIndexChanged.connect(
            lambda i: self.speech.setVoice(self.voice.itemData(i)))

        self.rate = QSlider(Qt.Orientation.Horizontal)
        self.rate.setRange(-60, 80)
        self.rate.setValue(0)
        self.rate.setFixedWidth(110)
        self.rate.valueChanged.connect(lambda v: self.speech.setRate(v / 100))

        self.theme = QComboBox()
        self.theme.addItems(THEMES.keys())
        self.theme.currentTextChanged.connect(self.apply_theme)

        smaller = QPushButton("A−")
        smaller.setFixedWidth(40)
        smaller.clicked.connect(lambda: self.zoom(-0.1))
        larger = QPushButton("A+")
        larger.setFixedWidth(40)
        larger.clicked.connect(lambda: self.zoom(0.1))

        for widget in (self.play, self.stop, QLabel("Voice"), self.voice,
                       QLabel("Speed"), self.rate, QLabel("Theme"), self.theme,
                       smaller, larger):
            controls.addWidget(widget)
        controls.addStretch(1)

        self.text = QTextEdit()
        self.text.setReadOnly(True)

        layout = QVBoxLayout(self)
        layout.addLayout(controls)
        layout.addWidget(self.text)

        self.speech.stateChanged.connect(self._state_changed)
        self.apply_theme("Paper")
        self.render()

    # -- presentation ----------------------------------------------------

    def render(self):
        html = []
        for block in self.blocks:
            size = 20 if block.get("heading") else 14
            weight = "600" if block.get("heading") else "400"
            text = (block["text"].replace("&", "&amp;")
                    .replace("<", "&lt;").replace(">", "&gt;"))
            html.append(
                f'<p style="font-size:{size * self.scale:.0f}px; font-weight:{weight};'
                f' line-height:160%; margin:0 0 14px 0;">{text}</p>')
        self.text.setHtml("".join(html))

    def zoom(self, delta: float):
        self.scale = max(0.7, min(3.0, self.scale + delta))
        self.render()

    def apply_theme(self, name: str):
        background, foreground = THEMES.get(name, THEMES["Paper"])
        self.text.setStyleSheet(
            f"QTextEdit {{ background: {background}; color: {foreground};"
            f" border: none; padding: 24px 40px; }}")

    # -- speech ----------------------------------------------------------

    def toggle(self):
        if self.speech.state() == QTextToSpeech.State.Speaking:
            self.speech.pause()
            self.play.setText("Resume")
        elif self.speech.state() == QTextToSpeech.State.Paused:
            self.speech.resume()
            self.play.setText("Pause")
        else:
            self._speaking_index = -1
            self.speak_next()

    def speak_next(self):
        self._speaking_index += 1
        if self._speaking_index >= len(self.blocks):
            self._speaking_index = -1
            self.play.setText("Read Out Loud")
            self.stop.setEnabled(False)
            return
        self.play.setText("Pause")
        self.stop.setEnabled(True)
        self.speech.say(self.blocks[self._speaking_index]["text"])

    def halt(self):
        self._speaking_index = len(self.blocks)
        self.speech.stop()
        self.play.setText("Read Out Loud")
        self.stop.setEnabled(False)

    def _state_changed(self, state):
        if state == QTextToSpeech.State.Ready and 0 <= self._speaking_index < len(self.blocks):
            self.speak_next()

    def closeEvent(self, event):
        self.speech.stop()
        super().closeEvent(event)
