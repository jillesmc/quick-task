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
from src.atlassian_service import AtlassianService, JiraWorker


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
