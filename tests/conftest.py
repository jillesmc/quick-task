"""
Configuração pytest e fixtures compartilhadas
"""

import json
import sys
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, Mock
from typing import Dict, Any, Generator

# Adicionar pacotes do sistema ao path para acessar PySide2
# PySide2 está instalado via apt em /usr/lib/python3/dist-packages
if "/usr/lib/python3/dist-packages" not in sys.path:
    sys.path.insert(0, "/usr/lib/python3/dist-packages")

import pytest

# Tentar importar pytest-qt, mas tornar opcional
try:
    from pytestqt.qtbot import QtBot

    PYTEST_QT_AVAILABLE = True
except ImportError:
    PYTEST_QT_AVAILABLE = False

    # Criar mock do QtBot se não disponível
    class QtBot:
        def add_widget(self, widget):
            # Mock method: pytest-qt not available, so this is a no-op
            pass

        def wait_signal(self, signal, timeout=1000):
            # Mock method: pytest-qt not available, returns null context
            # Uses snake_case to comply with PEP-8 naming conventions
            from contextlib import nullcontext

            return nullcontext()


from config.config_manager import ConfigManager
from core.jira_client import JiraClient


@pytest.fixture
def sample_config() -> Dict[str, Any]:
    """Configuração de exemplo para testes"""
    return {
        "project": "TEST",
        "issue_type": "Task",
        "assignee": "test@example.com",
        "custom_fields": {
            "tipo_atividade": "tipo-de-atividade",
            "documentacao_anexa": "documentacao-anexa",
            "utilizacao_ia": "utilizacao-de-ia",
        },
        "tipo_atividade_values": ["Opção 1", "Opção 2", "Opção 3"],
        "status_sequence": ["TO DO", "WAITING", "IN DEVELOPMENT", "DONE"],
        "worklog_timezone": "America/Sao_Paulo",
    }


@pytest.fixture
def temp_config_file(sample_config: Dict[str, Any]) -> Generator[Path, None, None]:
    """Cria um arquivo de configuração temporário"""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(sample_config, f, indent=2)
        temp_path = Path(f.name)

    yield temp_path

    # Limpar após o teste
    if temp_path.exists():
        temp_path.unlink()


@pytest.fixture
def config_manager(temp_config_file: Path) -> ConfigManager:
    """Fixture para ConfigManager com arquivo temporário"""
    return ConfigManager(config_path=temp_config_file)


@pytest.fixture
def mock_jira_client() -> MagicMock:
    """Fixture para JiraClient mockado"""
    client = MagicMock(spec=JiraClient)
    client._acli_path = "/usr/bin/acli"
    client.transition_issue = MagicMock(return_value=True)
    client.register_worklog = MagicMock(return_value=True)
    client.create_issue = MagicMock(
        return_value={
            "issue_key": "TEST-123",
            "issue_url": "https://jira.example.com/browse/TEST-123",
        }
    )
    client._format_duration_minutes = JiraClient._format_duration_minutes
    return client


@pytest.fixture
def mock_config_manager(sample_config: Dict[str, Any]) -> MagicMock:
    """Fixture para ConfigManager mockado"""
    config = MagicMock(spec=ConfigManager)
    config.get_project = MagicMock(return_value=sample_config["project"])
    config.get_issue_type = MagicMock(return_value=sample_config["issue_type"])
    config.get_assignee = MagicMock(return_value=sample_config["assignee"])
    config.get_custom_field = MagicMock(
        side_effect=lambda x: sample_config["custom_fields"].get(x, "")
    )
    config.get_tipo_atividade_values = MagicMock(
        return_value=sample_config["tipo_atividade_values"]
    )
    config.get_status_sequence = MagicMock(
        return_value=sample_config["status_sequence"]
    )
    config.get_timezone = MagicMock(
        return_value=sample_config.get("worklog_timezone", "UTC")
    )
    return config
