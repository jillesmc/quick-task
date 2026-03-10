"""
Testes para core/jira_metadata.py (parsing de respostas da API Jira).
TDD: fixtures baseadas na documentação Jira REST API v3; testes escritos antes da implementação.
"""

import pytest

from core.jira_metadata import (
    JiraProject,
    JiraIssueType,
    JiraFieldMetadata,
    JiraFieldType,
    parse_projects_response,
    parse_issue_types_response,
    parse_createmeta_fields,
    parse_field_list_response,
    schema_to_real_type,
    build_issue_type_to_workflow_from_schemes,
    build_statuses_by_issue_type,
    build_workflow_details_by_id,
)

# --- Fixtures: respostas da API (estrutura real/documentada) ---


@pytest.fixture
def fixture_projects_response():
    """GET /rest/api/3/project - lista de projetos."""
    return [
        {
            "id": "10001",
            "key": "QTASK",
            "name": "Quick Task Development",
            "projectTypeKey": "software",
            "avatarUrls": {"48x48": "https://example.com/avatar.png"},
            "description": "Project for quick tasks",
            "lead": {"displayName": "John Doe", "accountId": "abc"},
        },
        {
            "id": "10002",
            "key": "PROJ2",
            "name": "Another Project",
            "projectTypeKey": "business",
            "avatarUrls": {"48x48": ""},
        },
    ]


@pytest.fixture
def fixture_projects_empty():
    """Resposta vazia (lista vazia)."""
    return []


@pytest.fixture
def fixture_projects_minimal():
    """Projeto com campos opcionais ausentes."""
    return [{"id": "1", "key": "X", "name": "Minimal"}]


@pytest.fixture
def fixture_issuetype_project_response():
    """GET /rest/api/3/issuetype/project?projectId=X - issue types do projeto."""
    return [
        {
            "id": "10001",
            "name": "Epic",
            "description": "Big feature",
            "iconUrl": "https://example.com/epic.png",
            "subtask": False,
            "hierarchyLevel": 1,
        },
        {
            "id": "10002",
            "name": "Task",
            "subtask": False,
            "hierarchyLevel": 0,
        },
    ]


@pytest.fixture
def fixture_issuetype_empty():
    return []


@pytest.fixture
def fixture_createmeta_response():
    """GET /rest/api/3/issue/createmeta?projectKeys=X&issuetypeIds=Y&expand=projects.issuetypes.fields."""
    return {
        "projects": [
            {
                "id": "10001",
                "key": "QTASK",
                "name": "Quick Task",
                "issuetypes": [
                    {
                        "id": "10002",
                        "name": "Task",
                        "fields": {
                            "summary": {
                                "fieldId": "summary",
                                "name": "Summary",
                                "required": True,
                                "hasDefaultValue": False,
                                "schema": {"type": "string", "system": "summary"},
                                "operations": ["set"],
                            },
                            "priority": {
                                "fieldId": "priority",
                                "name": "Priority",
                                "required": False,
                                "hasDefaultValue": True,
                                "defaultValue": {"id": "3", "name": "Medium"},
                                "schema": {"type": "priority", "system": "priority"},
                                "allowedValues": [
                                    {"id": "1", "name": "Highest"},
                                    {"id": "3", "name": "Medium"},
                                ],
                                "operations": ["set"],
                            },
                            "customfield_10016": {
                                "fieldId": "customfield_10016",
                                "name": "Story Points",
                                "required": False,
                                "hasDefaultValue": False,
                                "schema": {
                                    "type": "number",
                                    "custom": "com.atlassian.jira.plugin.system.customfieldtypes:float",
                                    "customId": 10016,
                                },
                                "operations": ["set"],
                            },
                        },
                    }
                ],
            }
        ]
    }


@pytest.fixture
def fixture_createmeta_empty_projects():
    return {"projects": []}


@pytest.fixture
def fixture_createmeta_fields_with_asset():
    """Campos do createmeta incluindo um campo Asset (estilo customfield_24570).
    Documenta que objectType/objectTypeId/objectSchemaId podem existir no raw
    mas parse_createmeta_fields não os extrai (JiraFieldMetadata não tem esses atributos).
    """
    return {
        "summary": {
            "fieldId": "summary",
            "name": "Summary",
            "required": True,
            "hasDefaultValue": False,
            "schema": {"type": "string", "system": "summary"},
            "operations": ["set"],
        },
        "customfield_24570": {
            "fieldId": "customfield_24570",
            "name": "Quais_Plataformas_Afetadas",
            "required": False,
            "hasDefaultValue": False,
            "schema": {
                "type": "array",
                "items": "cmdb-object-field",
                "custom": "com.atlassian.jira.plugin.system.customfieldtypes:cmdb-object-cftype",
                "customId": 24570,
            },
            "operations": ["set"],
            "allowedValues": [],
            "objectType": "Plataforma Afetada",
            "objectTypeId": "441",
            "objectSchemaId": "218",
        },
    }


@pytest.fixture
def fixture_field_list_response():
    """GET /rest/api/3/field - lista de campos da instância."""
    return [
        {
            "id": "summary",
            "name": "Summary",
            "key": "summary",
            "custom": False,
            "schema": {"type": "string", "system": "summary"},
            "clauseNames": ["summary"],
        },
        {
            "id": "customfield_10016",
            "name": "Story Points",
            "custom": True,
            "schema": {
                "type": "number",
                "custom": "com.atlassian.jira.plugin.system.customfieldtypes:float",
                "customId": 10016,
            },
        },
    ]


@pytest.fixture
def fixture_field_list_empty():
    return []


# --- Testes: parse_projects_response ---


def test_parse_projects_response_full(fixture_projects_response):
    """Parse de resposta completa de projetos."""
    result = parse_projects_response(fixture_projects_response)
    assert len(result) == 2
    p0 = result[0]
    assert isinstance(p0, JiraProject)
    assert p0.id == "10001"
    assert p0.key == "QTASK"
    assert p0.name == "Quick Task Development"
    assert p0.project_type_key == "software"
    assert p0.avatar_url == "https://example.com/avatar.png"
    assert p0.description == "Project for quick tasks"
    assert p0.lead == "John Doe"

    p1 = result[1]
    assert p1.id == "10002"
    assert p1.key == "PROJ2"
    assert p1.name == "Another Project"
    assert p1.avatar_url == ""
    assert p1.description == ""
    assert p1.lead == ""


def test_parse_projects_response_empty(fixture_projects_empty):
    """Parse de lista vazia de projetos."""
    result = parse_projects_response(fixture_projects_empty)
    assert result == []


def test_parse_projects_response_minimal(fixture_projects_minimal):
    """Parse com campos opcionais ausentes (defaults)."""
    result = parse_projects_response(fixture_projects_minimal)
    assert len(result) == 1
    p = result[0]
    assert p.id == "1"
    assert p.key == "X"
    assert p.name == "Minimal"
    assert p.project_type_key == ""
    assert p.avatar_url == ""
    assert p.description == ""
    assert p.lead == ""


def test_parse_projects_response_paginated():
    """Parse aceita resposta paginada com chave 'values'."""
    data = {
        "values": [
            {
                "id": "100",
                "key": "PRJ",
                "name": "My Project",
                "projectTypeKey": "software",
            },
        ],
        "total": 1,
    }
    result = parse_projects_response(data)
    assert len(result) == 1
    assert result[0].id == "100"
    assert result[0].key == "PRJ"
    assert result[0].name == "My Project"


def test_parse_projects_response_name_fallback():
    """Parse usa projectName se name ausente (compatibilidade)."""
    data = [{"id": "1", "key": "K", "projectName": "Fallback Name"}]
    result = parse_projects_response(data)
    assert len(result) == 1
    assert result[0].name == "Fallback Name"


# --- Testes: parse_issue_types_response ---


def test_parse_issue_types_response_full(fixture_issuetype_project_response):
    """Parse de issue types por projeto."""
    result = parse_issue_types_response(fixture_issuetype_project_response)
    assert len(result) == 2
    it0 = result[0]
    assert isinstance(it0, JiraIssueType)
    assert it0.id == "10001"
    assert it0.name == "Epic"
    assert it0.description == "Big feature"
    assert it0.icon_url == "https://example.com/epic.png"
    assert it0.subtask is False
    assert it0.hierarchy_level == 1

    it1 = result[1]
    assert it1.id == "10002"
    assert it1.name == "Task"
    assert it1.description == ""
    assert it1.hierarchy_level == 0


def test_parse_issue_types_response_empty(fixture_issuetype_empty):
    """Parse de lista vazia de issue types."""
    result = parse_issue_types_response(fixture_issuetype_empty)
    assert result == []


# --- Testes: parse_createmeta_fields ---


def test_parse_createmeta_fields_full(fixture_createmeta_response):
    """Parse de campos do createmeta para um projeto e issue type."""
    projects = fixture_createmeta_response["projects"]
    project = projects[0]
    issuetype = project["issuetypes"][0]
    fields_dict = issuetype["fields"]

    result = parse_createmeta_fields(fields_dict)
    assert len(result) == 3

    summary = next(f for f in result if f.key == "summary")
    assert isinstance(summary, JiraFieldMetadata)
    assert summary.id == "summary"
    assert summary.name == "Summary"
    assert summary.required is True
    assert summary.field_type == JiraFieldType.STRING

    priority = next(f for f in result if f.key == "priority")
    assert priority.required is False
    assert priority.has_default_value is True
    assert priority.default_value is not None
    assert len(priority.allowed_values) == 2
    assert priority.field_type == JiraFieldType.PRIORITY

    custom = next(f for f in result if f.key == "customfield_10016")
    assert custom.custom is True
    assert custom.field_type == JiraFieldType.NUMBER


def test_parse_createmeta_fields_empty():
    """Parse de dict vazio de campos."""
    result = parse_createmeta_fields({})
    assert result == []


def test_parse_createmeta_fields_optional_absent():
    """Campo com allowedValues e defaultValue ausentes."""
    fields = {
        "summary": {
            "fieldId": "summary",
            "name": "Summary",
            "required": True,
            "schema": {"type": "string"},
        }
    }
    result = parse_createmeta_fields(fields)
    assert len(result) == 1
    assert result[0].allowed_values == []
    assert result[0].default_value is None
    assert result[0].has_default_value is False


def test_parse_createmeta_fields_asset_extracts_object_type_when_present(
    fixture_createmeta_fields_with_asset,
):
    """parse_createmeta_fields extrai objectType/objectTypeId/objectSchemaId do raw quando presentes."""
    result = parse_createmeta_fields(fixture_createmeta_fields_with_asset)
    asset_field = next(f for f in result if f.key == "customfield_24570")
    assert asset_field.name == "Quais_Plataformas_Afetadas"
    assert asset_field.field_type == JiraFieldType.ARRAY
    assert asset_field.object_type == "Plataforma Afetada"
    assert asset_field.object_type_id == "441"
    assert asset_field.object_schema_id == "218"


def test_parse_createmeta_fields_asset_without_object_type_keeps_none():
    """Quando o raw não tem objectType/objectTypeId, o campo parseado tem None e o dict não inclui as chaves."""
    from core.jira_metadata import field_metadata_to_dict

    fields = {
        "customfield_24569": {
            "fieldId": "customfield_24569",
            "name": "Qual_tipo_de_valor",
            "required": False,
            "schema": {
                "type": "array",
                "items": "cmdb-object-field",
                "custom": "com.atlassian.jira.plugin.system.customfieldtypes:cmdb-object-cftype",
                "customId": 24569,
            },
        },
    }
    result = parse_createmeta_fields(fields)
    assert len(result) == 1
    assert result[0].object_type is None
    assert result[0].object_type_id is None
    assert result[0].object_schema_id is None
    d = field_metadata_to_dict(result[0])
    assert "object_type" not in d
    assert "object_type_id" not in d
    assert "object_schema_id" not in d


def test_field_metadata_to_dict_does_not_include_asset_object_type_when_none():
    """field_metadata_to_dict não inclui object_type/object_type_id quando são None (campo sem API)."""
    from core.jira_metadata import field_metadata_to_dict

    f = JiraFieldMetadata(
        id="customfield_24570",
        key="customfield_24570",
        name="Quais_Plataformas_Afetadas",
        field_type=JiraFieldType.ARRAY,
        custom=True,
        required=False,
        has_default_value=False,
        default_value=None,
        allowed_values=[],
        schema_type="array",
        schema_custom="com.atlassian.jira.plugin.system.customfieldtypes:cmdb-object-cftype",
    )
    d = field_metadata_to_dict(f)
    assert "object_type" not in d
    assert "object_type_id" not in d
    assert "filter_scope_aql" not in d
    assert d["id"] == "customfield_24570"
    assert d["name"] == "Quais_Plataformas_Afetadas"


def test_field_metadata_to_dict_includes_asset_object_type_when_set():
    """field_metadata_to_dict inclui object_type/object_type_id/object_schema_id quando preenchidos."""
    from core.jira_metadata import field_metadata_to_dict

    f = JiraFieldMetadata(
        id="customfield_24570",
        key="customfield_24570",
        name="Quais_Plataformas_Afetadas",
        field_type=JiraFieldType.ARRAY,
        custom=True,
        required=False,
        has_default_value=False,
        default_value=None,
        allowed_values=[],
        schema_type="array",
        schema_custom="cmdb",
        object_type="Plataforma Afetada",
        object_type_id="441",
        object_schema_id="218",
    )
    d = field_metadata_to_dict(f)
    assert d["object_type"] == "Plataforma Afetada"
    assert d["object_type_id"] == "441"
    assert d["object_schema_id"] == "218"


# --- Testes: parse_field_list_response ---


def test_parse_field_list_response_full(fixture_field_list_response):
    """Parse de GET /rest/api/3/field."""
    result = parse_field_list_response(fixture_field_list_response)
    assert len(result) == 2
    s = result[0]
    assert isinstance(s, JiraFieldMetadata)
    assert s.id == "summary"
    assert s.name == "Summary"
    assert s.custom is False
    assert s.key == "summary"

    c = result[1]
    assert c.id == "customfield_10016"
    assert c.custom is True


def test_parse_field_list_response_empty(fixture_field_list_empty):
    """Parse de lista vazia de campos."""
    result = parse_field_list_response(fixture_field_list_empty)
    assert result == []


# --- Testes: serialização para QML/JSON ---


def test_project_to_dict():
    """JiraProject pode ser convertido para dict (QML/JSON)."""
    from core.jira_metadata import project_to_dict

    p = JiraProject(
        id="1",
        key="X",
        name="Test",
        project_type_key="software",
        avatar_url="",
        description="",
        lead="Lead",
    )
    d = project_to_dict(p)
    assert d["id"] == "1"
    assert d["key"] == "X"
    assert d["name"] == "Test"
    assert d["lead"] == "Lead"


def test_project_to_dict_empty_strings():
    """project_to_dict garante strings para QML (nunca None)."""
    from core.jira_metadata import project_to_dict

    p = JiraProject(
        id="",
        key="K",
        name="",
        project_type_key="",
        avatar_url="",
        description="",
        lead="",
    )
    d = project_to_dict(p)
    assert d["id"] == ""
    assert d["name"] == ""
    assert all(
        isinstance(d[k], str)
        for k in (
            "id",
            "key",
            "name",
            "project_type_key",
            "avatar_url",
            "description",
            "lead",
        )
    )


def test_issue_type_to_dict():
    """JiraIssueType pode ser convertido para dict."""
    from core.jira_metadata import issue_type_to_dict

    it = JiraIssueType(
        id="2",
        name="Task",
        description="",
        icon_url="",
        subtask=False,
        hierarchy_level=0,
    )
    d = issue_type_to_dict(it)
    assert d["id"] == "2"
    assert d["name"] == "Task"
    assert d["hierarchy_level"] == 0


def test_field_metadata_to_dict():
    """JiraFieldMetadata pode ser convertido para dict (com allowed_values)."""
    from core.jira_metadata import field_metadata_to_dict

    f = JiraFieldMetadata(
        id="priority",
        key="priority",
        name="Priority",
        field_type=JiraFieldType.PRIORITY,
        custom=False,
        required=True,
        has_default_value=True,
        default_value={"id": "3", "name": "Medium"},
        allowed_values=[{"id": "1", "name": "High"}, {"id": "3", "name": "Medium"}],
        schema_type="priority",
    )
    d = field_metadata_to_dict(f)
    assert d["id"] == "priority"
    assert d["name"] == "Priority"
    assert d["required"] is True
    assert len(d["allowed_values"]) == 2


# --- schema_to_real_type ---


def test_schema_to_real_type_select_list_single():
    """Select List (single choice): type option + custom select."""
    schema = {
        "type": "option",
        "custom": "com.atlassian.jira.plugin.system.customfieldtypes:select",
        "customId": 10001,
    }
    assert schema_to_real_type(schema) == "Select List (single choice)"


def test_schema_to_real_type_select_list_multiple():
    """Select List (multiple choices): array + items option + multiselect."""
    schema = {
        "type": "array",
        "items": "option",
        "custom": "com.atlassian.jira.plugin.system.customfieldtypes:multiselect",
        "customId": 10002,
    }
    assert schema_to_real_type(schema) == "Select List (multiple choices)"


def test_schema_to_real_type_assets_objects():
    """Assets objects: array + items cmdb-object-field + custom cmdb."""
    schema = {
        "type": "array",
        "items": "cmdb-object-field",
        "custom": "com.atlassian.jira.plugins.cmdb:cmdb-object-cftype",
        "customId": 10003,
    }
    assert schema_to_real_type(schema) == "Assets objects"


def test_schema_to_real_type_string_text():
    """Plain string schema maps to Text."""
    assert schema_to_real_type({"type": "string"}) == "Text"


def test_schema_to_real_type_system_priority():
    """System priority maps to Priority."""
    assert schema_to_real_type({"type": "priority", "system": "priority"}) == "Priority"


def test_schema_to_real_type_system_summary():
    """System summary maps to Summary."""
    assert schema_to_real_type({"type": "string", "system": "summary"}) == "Summary"


def test_schema_to_real_type_number():
    """Number type maps to Number."""
    assert schema_to_real_type({"type": "number"}) == "Number"


def test_schema_to_real_type_date():
    """Date type maps to Date."""
    assert schema_to_real_type({"type": "date"}) == "Date"


def test_schema_to_real_type_empty_unknown():
    """Empty or None schema returns Unknown."""
    assert schema_to_real_type(None) == "Unknown"
    assert schema_to_real_type({}) == "Unknown"


def test_schema_to_real_type_option_generic():
    """Generic option without select custom returns Option."""
    assert schema_to_real_type({"type": "option", "custom": "other:thing"}) == "Option"


def test_schema_to_real_type_array_generic():
    """Generic array without multiselect/cmdb returns Array."""
    assert schema_to_real_type({"type": "array", "items": "string"}) == "Array"


# --- Workflow / status / transitions parsers ---


def test_build_issue_type_to_workflow_from_schemes():
    """build_issue_type_to_workflow_from_schemes extrai issueTypeId -> workflow id/name."""
    schemes = [
        {
            "workflowsForIssueTypes": [
                {
                    "issueTypeIds": ["10001", "10002"],
                    "workflow": {"id": "wf-1", "name": "Dev Workflow"},
                },
                {
                    "issueTypeIds": ["10003"],
                    "workflow": {"id": "wf-2", "name": "Bug Workflow"},
                },
            ],
        },
    ]
    result = build_issue_type_to_workflow_from_schemes(schemes)
    assert result["10001"] == {"workflowId": "wf-1", "workflowName": "Dev Workflow"}
    assert result["10002"] == {"workflowId": "wf-1", "workflowName": "Dev Workflow"}
    assert result["10003"] == {"workflowId": "wf-2", "workflowName": "Bug Workflow"}


def test_build_issue_type_to_workflow_from_schemes_empty():
    """build_issue_type_to_workflow_from_schemes retorna {} para lista vazia."""
    assert build_issue_type_to_workflow_from_schemes([]) == {}
    assert build_issue_type_to_workflow_from_schemes(None) == {}


def test_build_statuses_by_issue_type():
    """build_statuses_by_issue_type normaliza resposta project/statuses."""
    raw = [
        {
            "id": "10001",
            "name": "Task",
            "statuses": [
                {
                    "id": "1",
                    "name": "To Do",
                    "statusCategory": {"key": "new", "name": "To Do"},
                },
                {"id": "2", "name": "Done", "statusCategory": {"key": "done"}},
            ],
        },
    ]
    result = build_statuses_by_issue_type(raw)
    assert "10001" in result
    assert len(result["10001"]) == 2
    assert result["10001"][0]["id"] == "1" and result["10001"][0]["name"] == "To Do"
    assert result["10001"][0].get("category") == "new"
    assert result["10001"][0].get("categoryName") == "To Do"
    assert result["10001"][1].get("category") == "done"
    assert "categoryName" not in result["10001"][1]  # sem name no payload


def test_build_statuses_by_issue_type_empty():
    """build_statuses_by_issue_type retorna {} para entrada vazia."""
    assert build_statuses_by_issue_type([]) == {}
    assert build_statuses_by_issue_type(None) == {}


def test_build_workflow_details_by_id():
    """build_workflow_details_by_id extrai statuses e transitions por workflow id."""
    resp = {
        "values": [
            {
                "id": "wf-uuid-1",
                "name": "Software",
                "statuses": [{"id": "1", "name": "To Do"}, {"id": "2", "name": "Done"}],
                "transitions": [
                    {"id": "21", "name": "Done", "to": {"id": "2", "name": "Done"}},
                ],
            },
        ],
    }
    result = build_workflow_details_by_id(resp)
    assert "wf-uuid-1" in result
    assert result["wf-uuid-1"]["workflowName"] == "Software"
    assert len(result["wf-uuid-1"]["statuses"]) == 2
    assert len(result["wf-uuid-1"]["transitions"]) == 1
    assert result["wf-uuid-1"]["transitions"][0]["to"]["name"] == "Done"


def test_build_workflow_details_by_id_values_transitions_format():
    """build_workflow_details_by_id com expand=values.transitions (statuses no topo, toStatusReference, links)."""
    resp = {
        "statuses": [
            {"id": "3", "name": "In Progress", "statusCategory": "IN_PROGRESS"},
            {"id": "10034", "name": "To Do", "statusCategory": "TODO"},
            {"id": "10077", "name": "Blocked", "statusCategory": "TODO"},
            {"id": "10003", "name": "Done", "statusCategory": "DONE"},
        ],
        "values": [
            {
                "id": "c43be6b4-bae9-4fc4-9ac4-53c2dfe1cc00",
                "name": "Platform Default Workflow v1",
                "statuses": [
                    {"statusReference": "10034"},
                    {"statusReference": "3"},
                    {"statusReference": "10077"},
                    {"statusReference": "10003"},
                ],
                "transitions": [
                    {
                        "id": "21",
                        "name": "In Progress",
                        "type": "DIRECTED",
                        "toStatusReference": "3",
                        "links": [
                            {"fromStatusReference": "10034"},
                            {"fromStatusReference": "10077"},
                        ],
                    },
                    {
                        "id": "41",
                        "name": "Done",
                        "type": "DIRECTED",
                        "toStatusReference": "10003",
                        "links": [{"fromStatusReference": "3"}],
                        "transitionScreen": {"parameters": {"screenId": "20561"}},
                    },
                ],
            },
        ],
    }
    result = build_workflow_details_by_id(resp)
    wf_id = "c43be6b4-bae9-4fc4-9ac4-53c2dfe1cc00"
    assert wf_id in result
    assert result[wf_id]["workflowName"] == "Platform Default Workflow v1"
    statuses = result[wf_id]["statuses"]
    assert len(statuses) == 4
    assert statuses[0]["id"] == "10034" and statuses[0]["name"] == "To Do"
    transitions = result[wf_id]["transitions"]
    assert len(transitions) == 2
    assert transitions[0]["id"] == "21"
    assert transitions[0]["to"] == {"id": "3", "name": "In Progress"}
    assert transitions[0]["from"] == ["10034", "10077"]
    assert transitions[0]["fromStatuses"] == [
        {"id": "10034", "name": "To Do"},
        {"id": "10077", "name": "Blocked"},
    ]
    assert transitions[0]["type"] == "directed"
    assert (
        transitions[1]["to"]["id"] == "10003" and transitions[1]["to"]["name"] == "Done"
    )
    assert transitions[1]["screen"] == {"id": "20561", "name": ""}


def test_build_workflow_details_by_id_empty():
    """build_workflow_details_by_id retorna {} quando values vazio."""
    assert build_workflow_details_by_id({}) == {}
    assert build_workflow_details_by_id({"values": []}) == {}
