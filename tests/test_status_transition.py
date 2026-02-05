"""
Testes unitários para core/status_transition.py
"""

from datetime import datetime
from unittest.mock import MagicMock

import pytest

from core.status_transition import (
    transition_sequentially,
    WorklogConfig,
    _validate_parameters,
    _get_target_index,
    _register_worklog_if_needed,
    _transition_to_next_status,
)


def test_validate_parameters_empty_issue_key():
    """Testa validação de issue_key vazio"""
    with pytest.raises(ValueError, match="Issue key não fornecido"):
        _validate_parameters("", "DONE")


def test_validate_parameters_empty_target_status():
    """Testa validação de target_status vazio"""
    with pytest.raises(ValueError, match="Status alvo não fornecido"):
        _validate_parameters("TEST-123", "")


def test_get_target_index_success():
    """Testa encontrar índice do status na sequência"""
    sequence = ["TO DO", "IN PROGRESS", "DONE"]
    assert _get_target_index("DONE", sequence) == 2
    assert _get_target_index("IN PROGRESS", sequence) == 1
    assert _get_target_index("TO DO", sequence) == 0


def test_get_target_index_not_found():
    """Testa erro quando status não encontrado na sequência"""
    sequence = ["TO DO", "IN PROGRESS", "DONE"]
    with pytest.raises(ValueError, match="Status 'INVALID' não encontrado"):
        _get_target_index("INVALID", sequence)


def test_transition_sequentially_target_to_do(mock_jira_client):
    """Testa que não transiciona se target_status é TO DO"""
    sequence = ["TO DO", "IN PROGRESS", "DONE"]
    transition_sequentially(mock_jira_client, "TEST-123", "TO DO", sequence)
    # Não deve chamar transition_issue
    mock_jira_client.transition_issue.assert_not_called()


def test_transition_sequentially_already_at_target(mock_jira_client):
    """Testa que não transiciona se já está no status alvo (índice 0)"""
    sequence = ["TO DO", "IN PROGRESS", "DONE"]
    # Se target_index é 0, já está em TO DO
    transition_sequentially(mock_jira_client, "TEST-123", "TO DO", sequence)
    mock_jira_client.transition_issue.assert_not_called()


def test_transition_sequentially_single_transition(mock_jira_client):
    """Testa transição única bem-sucedida"""
    sequence = ["TO DO", "WAITING", "DONE"]
    transition_sequentially(mock_jira_client, "TEST-123", "WAITING", sequence)
    mock_jira_client.transition_issue.assert_called_once_with(
        "TEST-123", "WAITING", max_retries=3, retry_delay=1.5, fields=None
    )


def test_transition_sequentially_multiple_transitions(mock_jira_client):
    """Testa múltiplas transições sequenciais"""
    sequence = ["TO DO", "WAITING", "IN PROGRESS", "DONE"]
    transition_sequentially(mock_jira_client, "TEST-123", "DONE", sequence)
    # Deve transicionar: TO DO -> WAITING -> IN PROGRESS -> DONE (3 transições)
    assert mock_jira_client.transition_issue.call_count == 3
    calls = mock_jira_client.transition_issue.call_args_list
    assert calls[0][0][1] == "WAITING"
    assert calls[1][0][1] == "IN PROGRESS"
    assert calls[2][0][1] == "DONE"


def test_transition_sequentially_with_progress_callback(mock_jira_client):
    """Testa que callback de progresso é chamado"""
    sequence = ["TO DO", "WAITING", "DONE"]
    callback = MagicMock()

    transition_sequentially(
        mock_jira_client, "TEST-123", "DONE", sequence, progress_callback=callback
    )

    # Callback deve ser chamado para cada transição + final
    # De TO DO para DONE: precisa passar por WAITING primeiro, depois DONE
    assert callback.call_count >= 2
    # Verificar que foi chamado com WAITING (primeira transição)
    waitting_calls = [
        call
        for call in callback.call_args_list
        if len(call[0]) >= 1 and call[0][0] == "WAITING"
    ]
    assert len(waitting_calls) > 0, "Callback não foi chamado com WAITING"
    # Verificar que foi chamado com mensagem final
    final_calls = [
        call
        for call in callback.call_args_list
        if len(call[0]) >= 3 and call[0][2] == "Transições concluídas!"
    ]
    assert len(final_calls) > 0, "Callback não foi chamado com mensagem final"


def test_transition_sequentially_transition_fails(mock_jira_client):
    """Testa que falha na transição lança RuntimeError"""
    sequence = ["TO DO", "WAITING", "DONE"]
    mock_jira_client.transition_issue.return_value = False

    with pytest.raises(RuntimeError, match="Não foi possível transicionar"):
        transition_sequentially(mock_jira_client, "TEST-123", "WAITING", sequence)


def test_transition_sequentially_with_worklog(mock_jira_client):
    """Worklog é registrado ao atingir IN DEVELOPMENT durante a sequência."""
    sequence = ["TO DO", "WAITING", "IN DEVELOPMENT", "DONE"]
    worklog = WorklogConfig(
        registrar=True,
        inicio=datetime(2024, 1, 1, 10, 0, 0),
        duracao=60,
        timezone="UTC",
    )

    result = transition_sequentially(
        mock_jira_client, "TEST-123", "IN DEVELOPMENT", sequence, worklog=worklog
    )

    assert result is True
    mock_jira_client.register_worklog.assert_called_once()


def test_transition_sequentially_worklog_not_in_development(mock_jira_client):
    """Testa que worklog não é registrado se não for IN DEVELOPMENT"""
    sequence = ["TO DO", "IN PROGRESS", "DONE"]
    worklog = WorklogConfig(
        registrar=True,
        inicio=datetime(2024, 1, 1, 10, 0, 0),
        duracao=60,
        timezone="UTC",
    )

    transition_sequentially(
        mock_jira_client, "TEST-123", "DONE", sequence, worklog=worklog
    )

    # Não deve registrar worklog pois não passou por IN DEVELOPMENT
    mock_jira_client.register_worklog.assert_not_called()


def test_transition_sequentially_worklog_missing_data(mock_jira_client):
    """Testa que worklog não é registrado sem dados"""
    sequence = ["TO DO", "IN DEVELOPMENT", "DONE"]
    worklog = WorklogConfig(
        registrar=True, inicio=None, duracao=60, timezone="UTC"  # Sem data
    )

    transition_sequentially(
        mock_jira_client, "TEST-123", "IN DEVELOPMENT", sequence, worklog=worklog
    )

    # Não deve registrar worklog sem data
    mock_jira_client.register_worklog.assert_not_called()


def test_register_worklog_if_needed_success(mock_jira_client):
    """Testa registro de worklog com sucesso"""
    worklog = WorklogConfig(
        registrar=True,
        inicio=datetime(2024, 1, 1, 10, 0, 0),
        duracao=90,
        timezone="America/Sao_Paulo",
    )
    callback = MagicMock()

    _register_worklog_if_needed(
        mock_jira_client, "TEST-123", "IN DEVELOPMENT", worklog, callback, 50
    )

    mock_jira_client.register_worklog.assert_called_once()
    callback.assert_called_once_with("IN DEVELOPMENT", 50, "Registrando worklog...")


def test_register_worklog_if_needed_failure(mock_jira_client, capsys):
    """Testa que falha ao registrar worklog não quebra a transição"""
    worklog = WorklogConfig(
        registrar=True,
        inicio=datetime(2024, 1, 1, 10, 0, 0),
        duracao=60,
        timezone="UTC",
    )
    mock_jira_client.register_worklog.return_value = False

    # Não deve lançar exceção
    _register_worklog_if_needed(
        mock_jira_client, "TEST-123", "IN DEVELOPMENT", worklog, None, 50
    )

    # Deve imprimir aviso
    captured = capsys.readouterr()
    assert "AVISO" in captured.err
