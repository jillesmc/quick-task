"""
Testes para os métodos de quick transition do JiraService: cancel_issue, block_issue, unblock_issue.
"""

from unittest.mock import MagicMock, patch

import pytest

from src.jira_service import JiraService


@pytest.fixture
def service_with_mocks(mock_jira_client, mock_config_manager):
    """JiraService com JiraClient e ConfigManager mockados."""
    mock_jira_client.transition_issue = MagicMock(return_value=True)
    mock_jira_client.add_comment = MagicMock(return_value={"id": "1"})
    with (
        patch("src.jira_service.JiraClient", return_value=mock_jira_client),
        patch("src.jira_service.ConfigManager", return_value=mock_config_manager),
    ):
        return JiraService()


def test_cancel_issue_success(service_with_mocks, qtbot, mock_jira_client):
    """cancel_issue chama transition_issue(CANCELED) e add_comment com motivo; emite issueUpdated."""
    service = service_with_mocks
    result = service.cancel_issue("KEY-1", "Requisito alterado")
    assert result is True
    with qtbot.wait_signal(service.issueUpdated, timeout=2000):
        pass
    mock_jira_client.transition_issue.assert_called_once_with("KEY-1", "CANCELED")
    mock_jira_client.add_comment.assert_called_once()
    call_args = mock_jira_client.add_comment.call_args
    assert call_args[0][0] == "KEY-1"
    assert "**Issue cancelada**" in call_args[0][1]
    assert "Requisito alterado" in call_args[0][1]


def test_block_issue_success(service_with_mocks, qtbot, mock_jira_client):
    """block_issue chama transition_issue(BLOCKED) e add_comment com motivo; emite issueUpdated."""
    service = service_with_mocks
    result = service.block_issue("KEY-2", "Aguardando aprovação")
    assert result is True
    with qtbot.wait_signal(service.issueUpdated, timeout=2000):
        pass
    mock_jira_client.transition_issue.assert_called_once_with("KEY-2", "BLOCKED")
    mock_jira_client.add_comment.assert_called_once()
    call_args = mock_jira_client.add_comment.call_args
    assert call_args[0][0] == "KEY-2"
    assert "**Issue bloqueada**" in call_args[0][1]
    assert "Aguardando aprovação" in call_args[0][1]


def test_unblock_issue_success_in_progress(service_with_mocks, qtbot, mock_jira_client):
    """unblock_issue chama transition_issue(IN PROGRESS) e add_comment; emite issueUpdated."""
    service = service_with_mocks
    result = service.unblock_issue("KEY-3", "Aprovação recebida")
    assert result is True
    with qtbot.wait_signal(service.issueUpdated, timeout=2000):
        pass
    mock_jira_client.transition_issue.assert_called_once_with("KEY-3", "IN PROGRESS")
    mock_jira_client.add_comment.assert_called_once()
    call_args = mock_jira_client.add_comment.call_args
    assert call_args[0][0] == "KEY-3"
    assert "**Issue desbloqueada**" in call_args[0][1]


def test_cancel_issue_transition_unavailable_emits_error(service_with_mocks, qtbot, mock_jira_client):
    """cancel_issue emite errorOccurred quando transição para CANCELED não existe."""
    mock_jira_client.transition_issue.return_value = False
    service = service_with_mocks
    result = service.cancel_issue("KEY-5", "Motivo")
    assert result is True
    with qtbot.wait_signal(service.errorOccurred, timeout=2000):
        pass
    mock_jira_client.transition_issue.assert_called_once_with("KEY-5", "CANCELED")
    mock_jira_client.add_comment.assert_not_called()


def test_unblock_issue_transition_unavailable_emits_error(service_with_mocks, qtbot, mock_jira_client):
    """unblock_issue emite errorOccurred quando transição para IN PROGRESS não está disponível."""
    mock_jira_client.transition_issue.return_value = False
    service = service_with_mocks
    result = service.unblock_issue("KEY-6", "")
    assert result is True
    with qtbot.wait_signal(service.errorOccurred, timeout=2000):
        pass
    mock_jira_client.transition_issue.assert_called_once_with("KEY-6", "IN PROGRESS")
    mock_jira_client.add_comment.assert_not_called()
