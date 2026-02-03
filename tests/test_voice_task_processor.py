"""Testes para VoiceTaskProcessor (lógica pura, sem deps de áudio/Ollama)."""

import pytest

from src.services.voice_task_processor import VoiceTaskProcessor

TIPO_VALUES = [
    "Novas iniciativas/Novas funcionalidades/Melhorias funcionais",
    "Bugs/Incidentes/Retrabalho Técnico",
    "Suporte Dúvidas/Suporte uso incorreto",
]


@pytest.fixture
def processor():
    return VoiceTaskProcessor()


def test_process_transcription_heuristic_summary(processor):
    """Summary é extraído (primeira frase ou primeiras palavras)."""
    text = "Criar uma tarefa para corrigir o bug de autenticação. Os usuários não conseguem fazer login."
    out = processor.process_transcription(text, TIPO_VALUES)
    assert "summary" in out
    assert len(out["summary"]) <= 120
    assert "bug" in out["summary"].lower() or "autenticação" in out["summary"].lower()


def test_process_transcription_heuristic_tipo_bug(processor):
    """Palavra 'bug' leva a tipo Bugs/Incidentes."""
    text = "Tem um bug no login que precisa ser corrigido."
    out = processor.process_transcription(text, TIPO_VALUES)
    assert out["tipo_atividade"] in TIPO_VALUES
    assert "Bugs" in out["tipo_atividade"] or "Incidente" in out["tipo_atividade"]


def test_process_transcription_heuristic_tipo_feature(processor):
    """Palavras de feature levam a tipo Novas funcionalidades."""
    text = "Adicionar nova funcionalidade de exportar relatório em PDF."
    out = processor.process_transcription(text, TIPO_VALUES)
    assert out["tipo_atividade"] in TIPO_VALUES


def test_process_transcription_description_is_transcription(processor):
    """Description contém a transcrição no fallback heurístico."""
    text = "Descrição completa da tarefa aqui."
    out = processor.process_transcription(text, TIPO_VALUES)
    assert out["description"] == text
    assert out["utilizacaoIA"] in ("Sim", "Não")


def test_process_transcription_empty_uses_defaults(processor):
    """Transcrição vazia ainda retorna estrutura válida."""
    out = processor.process_transcription("", TIPO_VALUES)
    assert "summary" in out
    assert "description" in out
    assert out["tipo_atividade"] == TIPO_VALUES[0]
    assert out["utilizacaoIA"] in ("Sim", "Não")


def test_process_transcription_tipo_validated_against_list(processor):
    """tipo_atividade é sempre um dos valores da lista."""
    out = processor.process_transcription("Qualquer texto aqui.", TIPO_VALUES)
    assert out["tipo_atividade"] in TIPO_VALUES
