"""Visual style — the same red the macOS app and the icon use."""

BRAND = "#C9504B"
BRAND_DARK = "#A63F3B"

STYLESHEET = f"""
QWidget {{
    background: #F2F2F4;
    color: #1B1B1F;
    font-size: 13px;
}}
QMainWindow, QDialog {{ background: #F2F2F4; }}

QToolBar {{
    background: #FBFBFD;
    border: none;
    border-bottom: 1px solid #DEDEE3;
    padding: 5px 8px;
    spacing: 3px;
}}
QToolButton {{
    background: transparent;
    border: none;
    border-radius: 6px;
    padding: 6px 8px;
}}
QToolButton:hover {{ background: #E6E6EB; }}
QToolButton:checked {{ background: {BRAND}; color: white; }}

QPushButton {{
    background: #E6E6EB;
    border: none;
    border-radius: 6px;
    padding: 6px 14px;
}}
QPushButton:hover {{ background: #DCDCE3; }}
QPushButton:default {{ background: {BRAND}; color: white; }}
QPushButton:default:hover {{ background: {BRAND_DARK}; }}
QPushButton:disabled {{ background: #ECECF0; color: #A0A0A8; }}

QLineEdit, QSpinBox, QDoubleSpinBox, QComboBox, QPlainTextEdit {{
    background: white;
    border: 1px solid #D4D4DA;
    border-radius: 6px;
    padding: 5px 8px;
    selection-background-color: {BRAND};
}}
QLineEdit:focus, QSpinBox:focus, QComboBox:focus {{ border-color: {BRAND}; }}

QListWidget {{ background: #F2F2F4; border: none; }}
QListWidget::item {{ padding: 4px; border-radius: 6px; }}
QListWidget::item:selected {{ background: rgba(201, 80, 75, 0.18); }}

QProgressBar {{
    background: #E2E2E8; border: none; border-radius: 4px;
    height: 8px; text-align: center;
}}
QProgressBar::chunk {{ background: {BRAND}; border-radius: 4px; }}

QStatusBar {{ background: #FBFBFD; border-top: 1px solid #DEDEE3; }}
QSplitter::handle {{ background: #DEDEE3; width: 1px; }}
QMenuBar, QMenu {{ background: #FBFBFD; }}
QMenu::item:selected {{ background: {BRAND}; color: white; }}
QLabel[hint="true"] {{ color: #6E6E78; font-size: 11px; }}
QLabel[heading="true"] {{ font-size: 15px; font-weight: 600; }}
"""
