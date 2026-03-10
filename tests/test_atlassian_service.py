"""
Testes unitários para src/atlassian_service.py
"""

import sys
import os
from unittest.mock import MagicMock, patch

is_flatpak = os.path.exists("/.flatpak-info")
if not is_flatpak and "/usr/lib/python3/dist-packages" not in sys.path:
    sys.path.insert(0, "/usr/lib/python3/dist-packages")

import pytest

from tests.conftest import QtBot
from src.atlassian_service import AtlassianService, JiraWorker, UpdateWorker


@pytest.fixture
def atlassian_service(qtbot, mock_atlassian_client, mock_config_manager):
    """Fixture para AtlassianService com dependências mockadas"""
    with (
        patch(
            "src.atlassian_service.AtlassianClient", return_value=mock_atlassian_client
        ),
        patch("src.atlassian_service.ConfigManager", return_value=mock_config_manager),
    ):
        service = AtlassianService()
        return service


def test_atlassian_service_init(
    atlassian_service, mock_atlassian_client, mock_config_manager
):
    """Testa inicialização do serviço"""
    assert atlassian_service._jira_client is not None
    assert atlassian_service._config is not None


def test_atlassian_service_is_available(atlassian_service):
    """Testa verificação de disponibilidade"""
    assert atlassian_service.isAvailable() is True


def test_atlassian_service_create_issue_success(
    atlassian_service, qtbot, mock_atlassian_client
):
    """Testa criação de issue com sucesso (API espelhada ao JiraService)"""
    mock_worker = MagicMock(spec=JiraWorker)
    mock_worker.isRunning = MagicMock(return_value=False)

    with patch("src.atlassian_service.JiraWorker", return_value=mock_worker):
        result = atlassian_service.createIssue(
            summary="Test Issue",
            description="Test Description",
            tipoAtividade="Opção 1",
            statusInicial="TO DO",
            documentacaoAnexa="Não",
            utilizacaoIA="Não",
            registrarWorklog=False,
            worklogInicio="",
            worklogDuracao=0,
            worklogTimezone="UTC",
            parentEpicKey="",
            worklogComment="",
            valorEntregue="",
            plataformasAfetadas=[],
        )

        assert result is True
        assert atlassian_service._worker is not None


def test_update_worker_with_status_path_and_empty_sequence_does_not_emit_error(
    qtbot, mock_atlassian_client, mock_config_manager
):
    """UpdateWorker com status_path preenchido e sequence vazia não emite errorOccurred e chama transition_along_path."""
    mock_atlassian_client.update_issue = MagicMock(return_value=True)
    mock_atlassian_client.transition_issue = MagicMock(return_value=True)

    with patch(
        "src.atlassian_service.transition_along_path"
    ) as mock_transition_along_path:
        worker = UpdateWorker(
            jira_client=mock_atlassian_client,
            config=mock_config_manager,
            issue_key="PROJ-1",
            summary="Summary",
            description="Desc",
            status="Done",
            status_path=["In Progress", "Done"],
            status_sequence_from_workflow=None,
        )
        errors = []
        worker.errorOccurred.connect(errors.append)
        worker.run()
        assert len(errors) == 0, f"Expected no error, got: {errors}"
        mock_transition_along_path.assert_called_once()
        call_args = mock_transition_along_path.call_args
        assert call_args[0][0] is mock_atlassian_client
        assert call_args[0][1] == "PROJ-1"
        assert call_args[0][2] == ["In Progress", "Done"]


def test_update_worker_with_empty_path_and_empty_sequence_emits_error(
    qtbot, mock_atlassian_client, mock_config_manager
):
    """UpdateWorker com status_path vazio e sequence vazia emite errorOccurred com mensagem de sequência vazia."""
    mock_atlassian_client.update_issue = MagicMock(return_value=True)

    worker = UpdateWorker(
        jira_client=mock_atlassian_client,
        config=mock_config_manager,
        issue_key="PROJ-1",
        summary="Summary",
        description="Desc",
        status="Done",
        status_path=[],
        status_sequence_from_workflow=[],
    )
    errors = []
    worker.errorOccurred.connect(errors.append)
    worker.run()
    assert len(errors) == 1
    assert "Sequência de status vazia" in errors[0]
