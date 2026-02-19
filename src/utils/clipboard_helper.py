"""
ClipboardHelper - Expõe área de transferência (imagem) para QML.
Usado para colar imagens (Ctrl+V) em descrição e comentários.
"""

import tempfile
from pathlib import Path

from PySide6.QtCore import QObject, Slot  # type: ignore[import]
from PySide6.QtGui import QGuiApplication, QImage  # type: ignore[import]

from src.utils.debug import debug_log  # type: ignore[import]


class ClipboardHelper(QObject):
    """Helper exposto ao QML para verificar e obter imagem da área de transferência."""

    @Slot(result=bool)
    def hasClipboardImage(self) -> bool:
        """Retorna True se a área de transferência contém uma imagem."""
        debug_log("ClipboardHelper", "hasClipboardImage", "chamado")
        clipboard = QGuiApplication.clipboard()
        if clipboard is None:
            debug_log("ClipboardHelper", "hasClipboardImage", "clipboard é null")
            return False
        mime = clipboard.mimeData()
        has_image = mime.hasImage() if mime else False
        debug_log("ClipboardHelper", "hasClipboardImage", "hasImage=%s", has_image)
        return has_image

    @Slot(result=str)
    def getClipboardImageAsTempFile(self) -> str:
        """
        Obtém a imagem da área de transferência e salva em arquivo temporário.
        Retorna o caminho do arquivo (PNG) ou string vazia se não houver imagem.
        """
        debug_log("ClipboardHelper", "getClipboardImageAsTempFile", "chamado")
        if not self.hasClipboardImage():
            debug_log(
                "ClipboardHelper",
                "getClipboardImageAsTempFile",
                "sem imagem no clipboard",
            )
            return ""
        clipboard = QGuiApplication.clipboard()
        image = clipboard.image()
        if image.isNull():
            debug_log(
                "ClipboardHelper",
                "getClipboardImageAsTempFile",
                "clipboard.image() é null",
            )
            return ""
        try:
            fd = tempfile.NamedTemporaryFile(
                suffix=".png", prefix="jira_attach_", delete=False
            )
            path = Path(fd.name)
            fd.close()
            if image.save(str(path)):
                debug_log(
                    "ClipboardHelper",
                    "getClipboardImageAsTempFile",
                    "salvo em %s",
                    path,
                )
                return str(path)
            path.unlink(missing_ok=True)
            debug_log(
                "ClipboardHelper", "getClipboardImageAsTempFile", "image.save falhou"
            )
            return ""
        except OSError as e:
            debug_log(
                "ClipboardHelper", "getClipboardImageAsTempFile", "OSError: %s", e
            )
            return ""

    @Slot(str)
    def setText(self, text: str) -> None:
        """
        Copia texto para a área de transferência.
        Usado para copiar comandos Git no popover de Development.
        """
        if not text:
            return
        clipboard = QGuiApplication.clipboard()
        if clipboard:
            clipboard.setText(text.strip())

    @Slot(str, result=str)
    def copyFileToTemp(self, source_path: str) -> str:
        """
        Copia o arquivo em source_path para um arquivo temporário acessível pelo app.
        Usado no drop de arquivos na criação de issue: no Flatpak o path original
        (/home/...) pode não ser acessível depois; copiar no momento do drop garante
        que o worker consiga ler o arquivo ao enviar o anexo.
        Retorna o path do temp ou string vazia em caso de erro.
        """
        debug_log(
            "ClipboardHelper",
            "copyFileToTemp",
            "chamado source_path=%s",
            source_path or "(vazio)",
        )
        if not source_path or not source_path.strip():
            return ""
        path = Path(source_path.strip())
        if not path.exists():
            debug_log(
                "ClipboardHelper", "copyFileToTemp", "arquivo não existe: %s", path
            )
            return ""
        if not path.is_file():
            debug_log("ClipboardHelper", "copyFileToTemp", "não é arquivo: %s", path)
            return ""
        try:
            suffix = path.suffix if path.suffix else ".bin"
            fd = tempfile.NamedTemporaryFile(
                suffix=suffix, prefix="jira_drop_", delete=False
            )
            temp_path = Path(fd.name)
            fd.close()
            temp_path.write_bytes(path.read_bytes())
            debug_log("ClipboardHelper", "copyFileToTemp", "copiado para %s", temp_path)
            return str(temp_path)
        except OSError as e:
            debug_log("ClipboardHelper", "copyFileToTemp", "OSError: %s", e)
            return ""
