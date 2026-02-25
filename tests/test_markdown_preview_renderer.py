"""
Testes para src.services.markdown_preview_renderer (MarkdownPreviewRenderer).
"""

from unittest.mock import patch

import pytest

from src.services.markdown_preview_renderer import MarkdownPreviewRenderer


@pytest.fixture
def renderer(qtbot):
    """Fixture para MarkdownPreviewRenderer (qtbot garante QApplication existir)."""
    return MarkdownPreviewRenderer()


def test_render_empty_string_returns_nenhum_conteudo(renderer):
    """render com string vazia retorna HTML com 'Nenhum conteúdo'."""
    assert renderer.render("") == "<p><em>Nenhum conteúdo</em></p>"


def test_render_whitespace_only_returns_nenhum_conteudo(renderer):
    """render com apenas espaços retorna HTML com 'Nenhum conteúdo'."""
    assert renderer.render("   \n\t  ") == "<p><em>Nenhum conteúdo</em></p>"


def test_render_simple_markdown_h1_returns_h1_tag(renderer):
    """render '# Hello' retorna h1."""
    result = renderer.render("# Hello")
    assert "<h1>" in result
    assert "Hello" in result
    assert "</h1>" in result


def test_render_bold_returns_strong(renderer):
    """render '**bold**' retorna strong/bold."""
    result = renderer.render("**bold**")
    assert "<strong>" in result or "<b>" in result
    assert "bold" in result


def test_render_pending_image_returns_imagem_pendente(renderer):
    """render '![alt](pending:xxx)' retorna [Imagem pendente] (placeholder substituído)."""
    result = renderer.render("![alt](pending:xxx)")
    assert "[Imagem pendente]" in result
    assert "pending:" not in result


def test_render_jira_attachment_image_returns_placeholder(renderer):
    """render '![screenshot](.../attachment/content/12345)' retorna placeholder para fetch assíncrono."""
    md = "![screenshot](https://example.atlassian.net/rest/api/3/attachment/content/12345)"
    result = renderer.render(md)
    assert "<img" not in result or "attachment/content" not in result
    assert "[Imagem:" in result
    assert "12345" in result
    assert "data-jira-img=" in result


def test_render_jira_attachment_with_width_preserves_data_width(renderer):
    """render '![alt](url){: width=\"250\" }' retorna placeholder com data-width para displayWidth."""
    md = '![screenshot](https://example.atlassian.net/rest/api/3/attachment/content/12345){: width="250" }'
    result = renderer.render(md)
    assert "data-jira-img=" in result
    assert 'data-width="250"' in result


def test_render_valid_markdown_with_code_block(renderer):
    """render markdown válido com code block."""
    md = "```python\nx = 1\n```"
    result = renderer.render(md)
    assert "<pre>" in result or "<code>" in result
    # codehilite adiciona spans; "x" e "1" estão no output
    assert "x" in result and "1" in result


def test_render_invalid_input_returns_error_html_red(renderer):
    """render quando conversão levanta exceção retorna HTML de erro em vermelho."""
    with patch.object(
        renderer, "_get_converter", side_effect=RuntimeError("mock error")
    ):
        result = renderer.render("# test")
    assert 'style="color: red;"' in result
    assert "Erro ao renderizar:" in result
