"""
Serviço para renderizar Markdown em HTML compatível com Qt RichText.

Expõe MarkdownPreviewRenderer(QObject) com método render(text) para uso em QML.
O HTML gerado usa apenas tags suportadas pelo Qt (h1-h6, p, pre, code, ul, ol, li,
blockquote, a, img, strong, em, etc.).
"""

import re
from typing import Optional

import markdown
from PySide6.QtCore import QObject, Slot  # type: ignore[import]

from src.utils.debug import debug_log

# Regex para placeholders de imagem pendente: ![alt](pending:xxx)
_PENDING_IMAGE_PATTERN = re.compile(
    r"!\[[^\]]*\]\(pending:[^)]+\)",
    re.IGNORECASE,
)

# Extensões do markdown com codehilite usando noclasses para estilos inline (Qt RichText)
_MD_EXTENSIONS = [
    "fenced_code",
    "tables",
    "nl2br",
    "codehilite",
]
_MD_EXTENSION_CONFIGS = {
    "codehilite": {"noclasses": True, "pygments_style": "monokai"},
}


def _create_markdown_converter() -> markdown.Markdown:
    """Cria instância de Markdown com extensões configuradas."""
    return markdown.Markdown(
        extensions=_MD_EXTENSIONS,
        extension_configs=_MD_EXTENSION_CONFIGS,
    )


def _replace_pending_images(text: str) -> str:
    """Substitui placeholders ](pending:xxx) por [Imagem pendente]."""
    return _PENDING_IMAGE_PATTERN.sub("[Imagem pendente]", text)


class MarkdownPreviewRenderer(QObject):
    """
    QObject exposto ao QML para renderizar Markdown em HTML.

    O método render(text) converte texto Markdown em HTML compatível com
    Qt RichText (TextArea richText, etc.), usando apenas tags suportadas.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        self._md: Optional[markdown.Markdown] = None

    def _get_converter(self) -> markdown.Markdown:
        """Retorna ou cria o conversor Markdown (reutilizado para performance)."""
        if self._md is None:
            self._md = _create_markdown_converter()
        return self._md

    @Slot(str, result=str)
    def render(self, text: str) -> str:
        """
        Converte texto Markdown em HTML compatível com Qt RichText.

        Args:
            text: Texto em Markdown a ser renderizado.

        Returns:
            HTML com tags suportadas pelo Qt (h1-h6, p, pre, code, ul, ol, li,
            blockquote, a, img, strong, em, etc.). Em caso de erro, retorna HTML
            com mensagem em vermelho. Para texto vazio, retorna parágrafo com
            "Nenhum conteúdo" em itálico.
        """
        text = str(text) if text is not None else ""
        if not text or not text.strip():
            return "<p><em>Nenhum conteúdo</em></p>"

        try:
            cleaned = _replace_pending_images(text)
            converter = self._get_converter()
            converter.reset()
            html = converter.convert(cleaned)
            raw = html.strip() or "<p><em>Nenhum conteúdo</em></p>"
            # Wrapper com cor branca para legibilidade em tema escuro
            return f'<div style="color: #ffffff;">{raw}</div>'
        except Exception as e:
            debug_log(
                "MarkdownPreviewRenderer", "render", "Erro ao renderizar: %s", str(e)
            )
            return (
                f'<p style="color: red;">Erro ao renderizar: {_escape_html(str(e))}</p>'
            )


def _escape_html(s: str) -> str:
    """Escapa caracteres HTML para exibição segura em mensagens de erro."""
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )
