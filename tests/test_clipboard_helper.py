"""
Testes para src.utils.clipboard_helper (ClipboardHelper.copyFileToTemp).
"""

import tempfile
from pathlib import Path

import pytest

from src.utils.clipboard_helper import ClipboardHelper


@pytest.fixture
def clipboard_helper(qtbot):
    """Fixture para ClipboardHelper (qtbot garante QApplication existir)."""
    return ClipboardHelper()


def test_copy_file_to_temp_returns_temp_path(clipboard_helper, tmp_path):
    """copyFileToTemp copia o arquivo e retorna path do temp."""
    source = tmp_path / "orig.png"
    source.write_bytes(b"\x89PNG\r\n\x1a\nfake-png-content")
    result = clipboard_helper.copyFileToTemp(str(source))
    assert result != ""
    assert result != str(source)
    assert Path(result).exists()
    assert Path(result).read_bytes() == source.read_bytes()


def test_copy_file_to_temp_empty_path_returns_empty(clipboard_helper):
    """copyFileToTemp com path vazio retorna string vazia."""
    assert clipboard_helper.copyFileToTemp("") == ""
    assert clipboard_helper.copyFileToTemp("   ") == ""


def test_copy_file_to_temp_nonexistent_returns_empty(clipboard_helper, tmp_path):
    """copyFileToTemp com arquivo inexistente retorna string vazia."""
    assert clipboard_helper.copyFileToTemp(str(tmp_path / "naoexiste.png")) == ""


def test_set_text_copies_to_clipboard(clipboard_helper):
    """setText copia texto para a área de transferência."""
    from PySide6.QtGui import QGuiApplication

    text = "git clone -b feature/test https://github.com/o/r.git"
    clipboard_helper.setText(text)
    clipboard = QGuiApplication.clipboard()
    assert clipboard is not None
    assert clipboard.text() == text


def test_set_text_empty_does_nothing(clipboard_helper):
    """setText com string vazia não altera clipboard."""
    from PySide6.QtGui import QGuiApplication

    clipboard_helper.setText("original")
    clipboard_helper.setText("")
    assert QGuiApplication.clipboard().text() == "original"
