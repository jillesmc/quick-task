"""
Testes adicionais para src/jira_service.py

Focam em:
- uso correto de timezone vindo do ConfigManager ao registrar worklog
- mapeamento de dados em getIssueDetails()
"""

from datetime import datetime
from unittest.mock import patch

import pytest

from src.jira_service import JiraService


@pytest.fixture
def jira_service_with_mocks(mock_jira_client, mock_config_manager):
    """
    Instância de JiraService com JiraClient e ConfigManager mockados.
    Reaproveita fixtures de conftest (mock_jira_client, mock_config_manager).
    """
    with (
        patch("src.jira_service.JiraClient", return_value=mock_jira_client),
        patch("src.jira_service.ConfigManager", return_value=mock_config_manager),
    ):
        service = JiraService()
        return service


def test_register_worklog_uses_config_timezone(
    jira_service_with_mocks, mock_jira_client, mock_config_manager
):
    """
    registerWorklogToIssue deve usar sempre o timezone vindo do ConfigManager,
    ignorando o timezone passado pela UI.
    """
    mock_config_manager.get_timezone.return_value = "America/Sao_Paulo"

    result = jira_service_with_mocks.registerWorklogToIssue(
        issueKey="TEST-123",
        worklogDuracao=60,
        worklogInicio="2024-01-01 10:00:00",
        worklogTimezone="UTC",  # deve ser ignorado
        comment="Comentário qualquer",
    )

    assert result is True
    call_args = mock_jira_client.register_worklog.call_args
    kwargs = call_args[1]
    assert kwargs["issue_key"] == "TEST-123"
    assert kwargs["timezone"] == "America/Sao_Paulo"


def test_register_worklog_invalid_datetime_emits_error(jira_service_with_mocks, qtbot):
    """
    registerWorklogToIssue deve falhar e emitir erro em caso de datetime inválido.
    """
    with qtbot.wait_signal(jira_service_with_mocks.errorOccurred, timeout=1000):
        result = jira_service_with_mocks.registerWorklogToIssue(
            issueKey="TEST-123",
            worklogDuracao=60,
            worklogInicio="data invalida",
            worklogTimezone="UTC",
            comment="Teste",
        )

        assert result is False


def test_get_issue_details_maps_fields_and_uppercases_status(
    jira_service_with_mocks, mock_jira_client
):
    """
    getIssueDetails deve mapear corretamente os campos principais e
    converter o status para UPPERCASE.
    """
    mock_jira_client.get_issue_details.return_value = {
        "key": "PLATFORM-123",
        "fields": {
            "summary": "Test summary",
            "description": "Test description",
            "status": {"name": "In Development"},
            # parent
            "parent": {
                "key": "PLATFORM-1",
                "fields": {"summary": "Epic summary"},
            },
        },
    }

    details = jira_service_with_mocks.getIssueDetails("PLATFORM-123")

    assert details["key"] == "PLATFORM-123"
    assert details["summary"] == "Test summary"
    assert details["description"] == "Test description"
    # status deve ser uppercased
    assert details["status"] == "IN DEVELOPMENT"
    assert details["parentKey"] == "PLATFORM-1"
    assert details["parentSummary"] == "Epic summary"

