"""Testes para LocalAIClient (com mock de requests)."""

import pytest

from src.services.localai_client import LocalAIClient, REQUESTS_AVAILABLE

TIPO_VALUES = [
    "Novas iniciativas/Novas funcionalidades/Melhorias funcionais",
    "Bugs/Incidentes/Retrabalho Técnico",
    "Suporte Dúvidas/Suporte uso incorreto",
]


@pytest.fixture
def client():
    return LocalAIClient(base_url="http://localhost:8080")


def test_check_connection_false_when_requests_unavailable(monkeypatch):
    """check_connection retorna False se requests não está disponível."""
    monkeypatch.setattr("src.services.localai_client.REQUESTS_AVAILABLE", False)
    c = LocalAIClient()
    assert c.check_connection() is False


def test_check_connection_true_on_200(monkeypatch):
    """check_connection retorna True quando GET /v1/models retorna 200."""
    if not REQUESTS_AVAILABLE:
        pytest.skip("requests não instalado")
    import requests

    def get_ok(*args, **kwargs):
        r = requests.Response()
        r.status_code = 200
        return r

    monkeypatch.setattr("src.services.localai_client.requests.get", get_ok)
    c = LocalAIClient()
    assert c.check_connection() is True


def test_check_connection_false_on_error(monkeypatch):
    """check_connection retorna False em exceção ou status != 200."""
    if not REQUESTS_AVAILABLE:
        pytest.skip("requests não instalado")

    def get_fail(*args, **kwargs):
        raise OSError("connection refused")

    monkeypatch.setattr("src.services.localai_client.requests.get", get_fail)
    c = LocalAIClient()
    assert c.check_connection() is False


def test_process_task_from_voice_heuristic_fallback(client, monkeypatch):
    """Quando LocalAI não responde, usa fallback heurístico."""
    if not REQUESTS_AVAILABLE:
        pytest.skip("requests não instalado")

    def post_fail(*args, **kwargs):
        raise OSError("connection refused")

    monkeypatch.setattr("src.services.localai_client.requests.post", post_fail)
    out = client.process_task_from_voice("Corrigir bug no login.", TIPO_VALUES)
    assert "summary" in out
    assert "description" in out
    assert out["tipo_atividade"] in TIPO_VALUES
    assert out["utilizacaoIA"] in ("Sim", "Não")
    assert "bug" in out["description"].lower() or "login" in out["description"].lower()


def test_process_task_from_voice_empty_transcription(client, monkeypatch):
    """Transcrição vazia retorna estrutura válida (heurística)."""
    if not REQUESTS_AVAILABLE:
        pytest.skip("requests não instalado")

    def post_fail(*args, **kwargs):
        raise OSError("connection refused")

    monkeypatch.setattr("src.services.localai_client.requests.post", post_fail)
    out = client.process_task_from_voice("", TIPO_VALUES)
    assert "summary" in out
    assert "description" in out
    assert out["tipo_atividade"] == TIPO_VALUES[0]
