"""
Testes para src/models/jira_metadata_config_model.py.
Usa mock_jira_client e config_manager; worker.run() é chamado diretamente para evitar threading.
"""

from unittest.mock import MagicMock

import pytest

from core.jira_metadata import (
    JiraProject,
    JiraIssueType,
    JiraFieldMetadata,
    JiraFieldType,
)
from config.config_manager import ConfigManager


@pytest.fixture
def mock_jira_client_for_discovery():
    """JiraClient mock com métodos de discovery."""
    client = MagicMock()
    client.get_projects.return_value = [
        JiraProject("1", "X", "Proj X", "software", "", "Desc", "Lead"),
    ]
    client.get_project_issue_types.return_value = [
        JiraIssueType("2", "Task", "", "", False, 0),
    ]
    client.get_createmeta_fields_for_issue_type.return_value = [
        JiraFieldMetadata(
            "summary",
            "summary",
            "Summary",
            JiraFieldType.STRING,
            False,
            True,
            False,
            None,
            [],
        ),
    ]
    return client


def test_discovery_worker_projects_emits_list(mock_jira_client_for_discovery):
    """DiscoveryWorker (projects) chama client.get_projects e emite lista de dicts."""
    from src.models.jira_metadata_config_model import DiscoveryWorker

    worker = DiscoveryWorker(
        kind="projects",
        jira_client=mock_jira_client_for_discovery,
        config_manager=MagicMock(),
    )
    worker.project_id = None
    worker.project_key = None
    worker.issuetype_id = None

    received = []
    worker.projectsLoaded.connect(received.append)
    worker.discoveryError.connect(lambda msg: received.append(("error", msg)))
    worker.run()

    assert len(received) == 1
    assert received[0] != ("error",)
    projects = received[0]
    assert isinstance(projects, list)
    assert len(projects) == 1
    assert projects[0]["key"] == "X"
    assert projects[0]["name"] == "Proj X"
    mock_jira_client_for_discovery.get_projects.assert_called_once()


def test_discovery_worker_issue_types_emits_list(mock_jira_client_for_discovery):
    """DiscoveryWorker (issue_types) chama get_project_issue_types e emite lista."""
    from src.models.jira_metadata_config_model import DiscoveryWorker

    worker = DiscoveryWorker(
        kind="issue_types",
        jira_client=mock_jira_client_for_discovery,
        config_manager=MagicMock(),
        project_id="1",
    )
    worker.project_key = None
    worker.issuetype_id = None

    received = []
    worker.issueTypesLoaded.connect(received.append)
    worker.run()

    assert len(received) == 1
    types_list = received[0]
    assert len(types_list) == 1
    assert types_list[0]["name"] == "Task"
    mock_jira_client_for_discovery.get_project_issue_types.assert_called_once_with("1")


def test_discovery_worker_fields_emits_list(mock_jira_client_for_discovery):
    """DiscoveryWorker (fields) chama get_createmeta_fields_for_issue_type e emite lista."""
    from src.models.jira_metadata_config_model import DiscoveryWorker

    worker = DiscoveryWorker(
        kind="fields",
        jira_client=mock_jira_client_for_discovery,
        config_manager=MagicMock(),
        project_key="X",
        issuetype_id="2",
    )

    received = []
    worker.fieldsLoaded.connect(received.append)
    worker.run()

    assert len(received) == 1
    fields_list = received[0]
    assert len(fields_list) == 1
    assert fields_list[0]["key"] == "summary"
    mock_jira_client_for_discovery.get_createmeta_fields_for_issue_type.assert_called_once_with(
        "X", "2"
    )


def test_discovery_worker_error_emits_discovery_error(mock_jira_client_for_discovery):
    """DiscoveryWorker emite discoveryError quando client levanta exceção."""
    from src.models.jira_metadata_config_model import DiscoveryWorker

    mock_jira_client_for_discovery.get_projects.side_effect = RuntimeError(
        "Network error"
    )
    worker = DiscoveryWorker(
        kind="projects",
        jira_client=mock_jira_client_for_discovery,
        config_manager=MagicMock(),
    )
    worker.project_id = None
    worker.project_key = None
    worker.issuetype_id = None

    errors = []
    worker.discoveryError.connect(errors.append)
    worker.run()

    assert len(errors) == 1
    assert "Network error" in errors[0] or "Error" in errors[0]


def test_save_configuration_calls_config_manager(config_manager):
    """saveConfiguration chama config_manager.save_jira_metadata com o dict."""
    from src.models.jira_metadata_config_model import JiraMetadataConfigModel

    model = JiraMetadataConfigModel(
        jira_client=MagicMock(),
        config_manager=config_manager,
    )
    data = {
        "version": "2.0",
        "jira_instance": "https://x.atlassian.net",
        "selected_projects": [{"key": "X", "enabled": True}],
    }
    model.saveConfiguration(data)
    path = config_manager.get_jira_metadata_path()
    assert path.exists()
    import json

    with open(path, "r", encoding="utf-8") as f:
        loaded = json.load(f)
    assert loaded["version"] == "2.0"
    assert loaded["jira_instance"] == "https://x.atlassian.net"
    if path.exists():
        path.unlink(missing_ok=True)


def test_load_configuration_returns_data(config_manager):
    """loadConfiguration carrega via config_manager e expõe em propriedade/sinal."""
    from src.models.jira_metadata_config_model import JiraMetadataConfigModel

    meta_path = config_manager.get_jira_metadata_path()
    meta_path.parent.mkdir(parents=True, exist_ok=True)
    import json

    meta_path.write_text(
        json.dumps({"version": "2.0", "selected_projects": []}),
        encoding="utf-8",
    )
    try:
        model = JiraMetadataConfigModel(
            jira_client=MagicMock(),
            config_manager=config_manager,
        )
        model.loadConfiguration()
        loaded = model.getLoadedMetadata()
        assert isinstance(loaded, dict)
        assert loaded.get("version") == "2.0"
        assert loaded.get("selected_projects") == []
    finally:
        if meta_path.exists():
            meta_path.unlink(missing_ok=True)


def test_is_available_false_when_client_none():
    """isAvailable é False quando jira_client é None."""
    from src.models.jira_metadata_config_model import JiraMetadataConfigModel

    model = JiraMetadataConfigModel(jira_client=None, config_manager=MagicMock())
    assert model.isAvailable() is False


def test_is_available_true_when_client_set():
    """isAvailable é True quando jira_client está definido."""
    from src.models.jira_metadata_config_model import JiraMetadataConfigModel

    model = JiraMetadataConfigModel(
        jira_client=MagicMock(),
        config_manager=MagicMock(),
    )
    assert model.isAvailable() is True
