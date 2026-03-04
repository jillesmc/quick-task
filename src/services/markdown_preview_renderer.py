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

from src.utils.debug import debug_log, is_debug_enabled

# Regex para placeholders de imagem pendente: ![alt](pending:xxx)
_PENDING_IMAGE_PATTERN = re.compile(
    r"!\[[^\]]*\]\(pending:[^)]+\)",
    re.IGNORECASE,
)

# Regex para <img> com src de attachment Jira (exige auth; Qt falha ao carregar)
_JIRA_ATTACHMENT_IMG = re.compile(
    r'<img[^>]+src="([^"]*attachment/content/\d+[^"]*)"[^>]*/?>',
    re.IGNORECASE,
)
# Regex para <a href="...attachment/content/..."> (markdown [alt](url) sem !)
_JIRA_ATTACHMENT_LINK = re.compile(
    r'<a[^>]+href="([^"]*attachment/content/\d+[^"]*)"[^>]*>([^<]*)</a>',
    re.IGNORECASE,
)
# Regex para extrair width de atributo: width="250" ou width=250
_JIRA_IMG_WIDTH = re.compile(r'\bwidth=["\']?(\d+)["\']?', re.IGNORECASE)

# Extensões do markdown com codehilite usando noclasses para estilos inline (Qt RichText)
_MD_EXTENSIONS = [
    "fenced_code",
    "tables",
    "nl2br",
    "codehilite",
    "attr_list",
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


def _replace_jira_attachment_imgs(html: str) -> str:
    """
    Substitui <img src="...attachment/content/..."> por placeholder para fetch assíncrono.
    URLs de attachment Jira exigem auth; o QML chama fetchAttachmentDataUrl e substitui
    o placeholder por <img src="data:..."> quando attachmentDataUrlReady for emitido.
    Preserva width quando presente (attr_list); fallback: busca width no contexto pai.
    """

    def _replacer(match: re.Match) -> str:
        full = match.group(0)
        src = match.group(1)
        alt_match = re.search(r'alt="([^"]*)"', full)
        filename = (alt_match.group(1) or "").strip() or "imagem"
        width_match = _JIRA_IMG_WIDTH.search(full)
        width_val = width_match.group(1) if width_match else ""
        if not width_val:
            ctx_start = max(0, match.start() - 150)
            ctx = html[ctx_start : match.end()]
            ctx_width = _JIRA_IMG_WIDTH.search(ctx)
            if ctx_width:
                width_val = ctx_width.group(1)
        # Escapar URL e filename para atributos HTML
        src_escaped = src.replace("&", "&amp;").replace('"', "&quot;")
        fn_escaped = _escape_html(filename)
        width_attr = f' data-width="{width_val}"' if width_val else ""
        return (
            f'<span data-jira-img="{src_escaped}" data-filename="{fn_escaped}"{width_attr}>'
            f"[Imagem: {fn_escaped}]</span>"
        )

    return _JIRA_ATTACHMENT_IMG.sub(_replacer, html)


def _replace_jira_attachment_links(html: str) -> str:
    """
    Substitui <a href="...attachment/content/..."> por placeholder de imagem.
    Markdown [alt](url) sem ! produz link; tratamos como imagem para exibição.
    """

    def _replacer(match: re.Match) -> str:
        href = match.group(1)
        alt = (match.group(2) or "").strip() or "imagem"
        src_escaped = href.replace("&", "&amp;").replace('"', "&quot;")
        fn_escaped = _escape_html(alt)
        return (
            f'<span data-jira-img="{src_escaped}" data-filename="{fn_escaped}">'
            f"[Imagem: {fn_escaped}]</span>"
        )

    return _JIRA_ATTACHMENT_LINK.sub(_replacer, html)


# Qt RichText: -qt-list-indent por nível (1=raiz, 2=sublista, ...) para indentação e •/◦.
_UL_OL_OPEN = re.compile(r"<(ul|ol)(?:\s[^>]*)?>")
_UL_OL_CLOSE = re.compile(r"</(ul|ol)>")


def _add_qt_list_indent(html: str) -> str:
    """
    Adiciona -qt-list-indent a cada <ul> e <ol> conforme o nível de aninhamento
    (1 = lista raiz, 2 = sublista, 3 = sub-sublista, ...) para o Qt desenhar
    indentação e marcadores distintos (• vs ◦) no preview (Text.RichText).
    """
    # Coletar todas as tags <ul>/<ol> e </ul>/</ol> em ordem
    events: list[tuple[int, int, str, bool, str]] = (
        []
    )  # (start, end, raw, is_open, tag)
    for m in _UL_OL_OPEN.finditer(html):
        events.append((m.start(), m.end(), m.group(0), True, m.group(1)))
    for m in _UL_OL_CLOSE.finditer(html):
        events.append((m.start(), m.end(), m.group(0), False, m.group(1)))
    events.sort(key=lambda x: x[0])

    result: list[str] = []
    pos = 0
    depth = 0
    for start, end, raw, is_open, tag in events:
        result.append(html[pos:start])
        if is_open:
            if "style=" in raw and "-qt-list-indent" in raw:
                result.append(raw)
            else:
                depth += 1
                result.append(f'<{tag} style="-qt-list-indent: {depth}">')
            pos = end
        else:
            result.append(raw)
            depth = max(0, depth - 1)
            pos = end
    result.append(html[pos:])
    return "".join(result)


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
            # Listas: Qt RichText precisa de -qt-list-indent para indentar ul/ol no preview
            raw = _add_qt_list_indent(raw)
            if is_debug_enabled() and (
                "<ul>" in raw or "<ol>" in raw or "<ul " in raw or "<ol " in raw
            ):
                debug_log(
                    "MarkdownPreviewRenderer",
                    "render",
                    "HTML com listas (ul/ol), len=%d",
                    len(raw),
                )
            # Substituir img de attachment Jira por placeholder (Qt falha ao carregar sem auth)
            raw = _replace_jira_attachment_imgs(raw)
            # Substituir links [alt](url) sem ! para attachment/content por placeholder de imagem
            raw = _replace_jira_attachment_links(raw)
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
