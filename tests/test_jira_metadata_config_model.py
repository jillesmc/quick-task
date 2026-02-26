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
    client.get_fields_for_issue_type.return_value = client.get_createmeta_fields_for_issue_type.return_value
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
    """DiscoveryWorker (fields) chama get_fields_for_issue_type e emite lista."""
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
    mock_jira_client_for_discovery.get_fields_for_issue_type.assert_called_once_with(
        "X", "2"
    )


def test_discovery_worker_fields_includes_real_type(mock_jira_client_for_discovery):
    """DiscoveryWorker (fields) enriquece cada campo com real_type a partir de get_fields()."""
    from core.jira_metadata import JiraFieldMetadata, JiraFieldType
    from src.models.jira_metadata_config_model import DiscoveryWorker

    # Field from createmeta (sem schema_raw)
    mock_jira_client_for_discovery.get_fields_for_issue_type.return_value = [
        JiraFieldMetadata(
            id="customfield_10002",
            key="customfield_10002",
            name="Platforms",
            field_type=JiraFieldType.ARRAY,
            custom=True,
            required=False,
            has_default_value=False,
            default_value=None,
            allowed_values=[],
            schema_type="array",
            schema_system=None,
            schema_custom="cmdb",
        ),
    ]
    mock_jira_client_for_discovery.get_createmeta_fields_for_issue_type.return_value = (
        mock_jira_client_for_discovery.get_fields_for_issue_type.return_value
    )
    # get_fields retorna campo com schema_raw para real_type = Assets objects
    mock_jira_client_for_discovery.get_fields.return_value = [
        JiraFieldMetadata(
            id="customfield_10002",
            key="customfield_10002",
            name="Platforms",
            field_type=JiraFieldType.ARRAY,
            custom=True,
            required=False,
            has_default_value=False,
            default_value=None,
            allowed_values=[],
            schema_type="array",
            schema_system=None,
            schema_custom="cmdb",
            schema_raw={
                "type": "array",
                "items": "cmdb-object-field",
                "custom": "com.atlassian.jira.plugins.cmdb:cmdb-object-cftype",
            },
        ),
    ]

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
    assert fields_list[0].get("real_type") == "Assets objects"
    mock_jira_client_for_discovery.get_fields.assert_called_once()


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


# --- EnrichmentWorker and enrichAndSave ---


@pytest.fixture
def mock_jira_client_for_enrichment():
    """JiraClient mock com get_fields (real_type) e context/defaultValue."""
    from core.jira_metadata import JiraFieldMetadata, JiraFieldType

    client = MagicMock()
    client.get_fields.return_value = [
        JiraFieldMetadata(
            id="customfield_10001",
            key="customfield_10001",
            name="Utilização de IA",
            field_type=JiraFieldType.OPTION,
            custom=True,
            required=False,
            has_default_value=False,
            default_value=None,
            allowed_values=[],
            schema_type="option",
            schema_system=None,
            schema_custom="com.atlassian.jira.plugin.system.customfieldtypes:select",
            schema_raw={
                "type": "option",
                "custom": "com.atlassian.jira.plugin.system.customfieldtypes:select",
                "customId": 10001,
            },
        ),
    ]
    client.get_field_context_mapping.return_value = [
        {"projectId": "10000", "issueTypeId": "10001", "contextId": "10100"},
    ]
    client.get_field_context_default_value.return_value = [
        {"contextId": "10100", "optionId": "10002", "type": "option.single"},
    ]
    client.get_field_context_options.return_value = [
        {"id": "10001", "value": "Sim"},
        {"id": "10002", "value": "Não"},
    ]
    return client


def test_enrichment_worker_adds_real_type_and_default_value(
    mock_jira_client_for_enrichment,
):
    """EnrichmentWorker preenche real_type e default_value nos campos."""
    from src.models.jira_metadata_config_model import EnrichmentWorker

    payload = {
        "version": "2.0",
        "selected_projects": [{"id": "10000", "key": "PROJ", "name": "Proj", "enabled": True}],
        "selected_fields": {
            "PROJ": {
                "10001": [
                    {
                        "id": "customfield_10001",
                        "key": "customfield_10001",
                        "name": "Utilização de IA",
                        "enabled": True,
                    },
                ],
            },
        },
    }
    worker = EnrichmentWorker(
        payload=payload,
        jira_client=mock_jira_client_for_enrichment,
    )
    result = []
    worker.enriched.connect(result.append)
    worker.run()

    assert len(result) == 1
    enriched = result[0]
    fields_list = enriched.get("selected_fields", {}).get("PROJ", {}).get("10001", [])
    assert len(fields_list) == 1
    field = fields_list[0]
    assert field.get("real_type") == "Select List (single choice)"
    assert field.get("default_value") == {
        "contextId": "10100",
        "optionId": "10002",
        "type": "option.single",
    }
    assert field.get("options") == [
        {"id": "10001", "value": "Sim"},
        {"id": "10002", "value": "Não"},
    ]
    mock_jira_client_for_enrichment.get_fields.assert_called_once()
    mock_jira_client_for_enrichment.get_field_context_mapping.assert_called_once()
    mock_jira_client_for_enrichment.get_field_context_default_value.assert_called_once()
    mock_jira_client_for_enrichment.get_field_context_options.assert_called_once_with(
        "customfield_10001", "10100"
    )


def test_enrichment_worker_assets_sets_placeholders(mock_jira_client_for_enrichment):
    """EnrichmentWorker define object_schema e filter_scope_aql como None para Assets."""
    from core.jira_metadata import JiraFieldMetadata, JiraFieldType
    from src.models.jira_metadata_config_model import EnrichmentWorker

    mock_jira_client_for_enrichment.get_fields.return_value = [
        JiraFieldMetadata(
            id="customfield_10002",
            key="customfield_10002",
            name="Platforms",
            field_type=JiraFieldType.ARRAY,
            custom=True,
            required=False,
            has_default_value=False,
            default_value=None,
            allowed_values=[],
            schema_type="array",
            schema_system=None,
            schema_custom="com.atlassian.jira.plugins.cmdb:cmdb-object-cftype",
            schema_raw={
                "type": "array",
                "items": "cmdb-object-field",
                "custom": "com.atlassian.jira.plugins.cmdb:cmdb-object-cftype",
            },
        ),
    ]
    payload = {
        "version": "2.0",
        "selected_projects": [{"id": "10000", "key": "P", "name": "P", "enabled": True}],
        "selected_fields": {"P": {"10001": [{"id": "customfield_10002", "key": "customfield_10002", "name": "Platforms", "enabled": True}]}},
    }
    worker = EnrichmentWorker(
        payload=payload,
        jira_client=mock_jira_client_for_enrichment,
    )
    result = []
    worker.enriched.connect(result.append)
    worker.run()

    fields_list = result[0].get("selected_fields", {}).get("P", {}).get("10001", [])
    assert len(fields_list) == 1
    assert fields_list[0].get("real_type") == "Assets objects"
    assert fields_list[0].get("object_schema") is None
    assert fields_list[0].get("filter_scope_aql") is None
    # Resiliência: não chamar defaultValue para Assets (evita 400)
    mock_jira_client_for_enrichment.get_field_context_default_value.assert_not_called()


def test_enrichment_worker_assets_does_not_overwrite_when_already_set(
    mock_jira_client_for_enrichment,
):
    """EnrichmentWorker não sobrescreve object_schema/filter_scope_aql quando já definidos (ex.: wizard step 4)."""
    from core.jira_metadata import JiraFieldMetadata, JiraFieldType
    from src.models.jira_metadata_config_model import EnrichmentWorker

    mock_jira_client_for_enrichment.get_fields.return_value = [
        JiraFieldMetadata(
            id="customfield_10002",
            key="customfield_10002",
            name="Platforms",
            field_type=JiraFieldType.ARRAY,
            custom=True,
            required=False,
            has_default_value=False,
            default_value=None,
            allowed_values=[],
            schema_type="array",
            schema_system=None,
            schema_custom="cmdb",
            schema_raw={
                "type": "array",
                "items": "cmdb-object-field",
                "custom": "com.atlassian.jira.plugins.cmdb:cmdb-object-cftype",
            },
        ),
    ]
    payload = {
        "version": "2.0",
        "selected_projects": [{"id": "10000", "key": "P", "name": "P", "enabled": True}],
        "selected_fields": {
            "P": {
                "10001": [
                    {
                        "id": "customfield_10002",
                        "key": "customfield_10002",
                        "name": "Platforms",
                        "enabled": True,
                        "object_schema": "Plataforma",
                        "object_schema_id": "13",
                        "object_type": "Plataforma Afetada",
                        "object_type_id": "122",
                        "filter_scope_aql": 'objectType = "Plataforma Afetada"',
                        "field_can_store_multiple_objects": True,
                    },
                ],
            },
        },
    }
    worker = EnrichmentWorker(
        payload=payload,
        jira_client=mock_jira_client_for_enrichment,
    )
    result = []
    worker.enriched.connect(result.append)
    worker.run()

    fields_list = result[0].get("selected_fields", {}).get("P", {}).get("10001", [])
    assert len(fields_list) == 1
    assert fields_list[0].get("real_type") == "Assets objects"
    assert fields_list[0].get("object_schema") == "Plataforma"
    assert fields_list[0].get("filter_scope_aql") == 'objectType = "Plataforma Afetada"'
    assert fields_list[0].get("object_schema_id") == "13"
    assert fields_list[0].get("object_type") == "Plataforma Afetada"


def test_enrich_and_save_without_client_emits_error(config_manager):
    """enrichAndSave sem jira_client emite discoveryError e saveFinished(False)."""
    from PySide6.QtCore import QCoreApplication
    from src.models.jira_metadata_config_model import JiraMetadataConfigModel

    app = QCoreApplication.instance() or QCoreApplication([])
    model = JiraMetadataConfigModel(jira_client=None, config_manager=config_manager)
    errors = []
    finished = []
    model.discoveryError.connect(errors.append)
    model.saveFinished.connect(finished.append)

    model.enrichAndSave({"version": "2.0", "selected_projects": []})

    assert len(errors) == 1
    assert len(finished) == 1
    assert finished[0] is False


def test_enrich_and_save_without_config_emits_error():
    """enrichAndSave sem config_manager emite discoveryError e saveFinished(False)."""
    from PySide6.QtCore import QCoreApplication
    from src.models.jira_metadata_config_model import JiraMetadataConfigModel

    app = QCoreApplication.instance() or QCoreApplication([])
    model = JiraMetadataConfigModel(
        jira_client=MagicMock(),
        config_manager=MagicMock(),
    )
    model._config_manager = None  # force no config so enrichAndSave hits that branch
    errors = []
    finished = []
    model.discoveryError.connect(errors.append)
    model.saveFinished.connect(finished.append)

    model.enrichAndSave({"version": "2.0"})

    assert len(errors) == 1
    assert len(finished) == 1
    assert finished[0] is False
