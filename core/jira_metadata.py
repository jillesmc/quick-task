"""
Estruturas de dados e funções de parsing para metadata do Jira (projetos, issue types, fields).
Usado pela descoberta e configuração de metadata (Issue #25). Sem dependência de PySide6.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class JiraFieldType(Enum):
    """Tipos de campos do Jira (para UI e serialização)."""

    STRING = "string"
    NUMBER = "number"
    DATE = "date"
    DATETIME = "datetime"
    OPTION = "option"
    ARRAY = "array"
    USER = "user"
    PRIORITY = "priority"
    STATUS = "status"
    RESOLUTION = "resolution"
    PROJECT = "project"
    ISSUETYPE = "issuetype"
    EPIC = "epic"
    PARENT = "parent"
    ANY = "any"


@dataclass
class JiraProject:
    """Projeto do Jira."""

    id: str
    key: str
    name: str
    project_type_key: str
    avatar_url: str
    description: str
    lead: str


@dataclass
class JiraIssueType:
    """Tipo de issue do Jira."""

    id: str
    name: str
    description: str
    icon_url: str
    subtask: bool
    hierarchy_level: int


@dataclass
class JiraFieldMetadata:
    """Metadata de um campo (createmeta ou /field)."""

    id: str
    key: str
    name: str
    field_type: JiraFieldType
    custom: bool
    required: bool
    has_default_value: bool
    default_value: Optional[Any]
    allowed_values: List[Dict[str, Any]]
    schema_type: str = ""
    schema_system: Optional[str] = None
    schema_custom: Optional[str] = None
    schema_raw: Optional[Dict[str, Any]] = (
        None  # full schema from GET /field (for real_type)
    )


def schema_to_real_type(schema: Optional[Dict[str, Any]]) -> str:
    """
    Mapeia schema da API (GET /rest/api/3/field) para o rótulo de tipo real do Jira.

    Ex.: "Select List (single choice)", "Assets objects", "Text", etc.
    """
    if not schema or not isinstance(schema, dict):
        return "Unknown"
    stype = (schema.get("type") or "").strip()
    custom = (schema.get("custom") or "") or ""
    custom_str = str(custom).lower()
    items = schema.get("items")
    items_str = str(items).lower() if items is not None else ""
    system = (schema.get("system") or "").strip()

    # Select List (single choice): type option + custom select
    if stype == "option" and "customfieldtypes:select" in custom_str:
        return "Select List (single choice)"

    # Select List (multiple choices): type array, items option, custom multiselect
    if stype == "array" and items_str == "option" and "multiselect" in custom_str:
        return "Select List (multiple choices)"

    # Assets objects: array + items cmdb-object-field + custom cmdb
    if (
        stype == "array"
        and "cmdb-object-field" in items_str
        and "cmdb-object-cftype" in custom_str
    ):
        return "Assets objects"

    # System fields
    if system:
        system_labels = {
            "summary": "Summary",
            "description": "Description",
            "priority": "Priority",
            "status": "Status",
            "resolution": "Resolution",
            "issuetype": "Issue Type",
            "project": "Project",
            "parent": "Parent",
        }
        if system in system_labels:
            return system_labels[system]

    # Generic type labels
    type_labels = {
        "string": "Text",
        "number": "Number",
        "date": "Date",
        "datetime": "Date Time",
        "user": "User",
        "option": "Option",
        "array": "Array",
        "priority": "Priority",
    }
    if stype in type_labels:
        return type_labels[stype]

    # Custom text fields etc.
    if "textfield" in custom_str or (stype == "string" and custom_str):
        return "Text"
    if "textarea" in custom_str:
        return "Paragraph"
    if "datepicker" in custom_str:
        return "Date Picker"
    if "datetime" in custom_str:
        return "Date Time"
    if "multicheckboxes" in custom_str:
        return "Multi-Checkboxes"
    if "radio" in custom_str or "cascadingselect" in custom_str:
        return "Select List (single choice)"  # fallback

    return "Unknown"


def _infer_field_type(schema: Optional[Dict[str, Any]]) -> JiraFieldType:
    """Infere JiraFieldType a partir do schema da API."""
    if not schema:
        return JiraFieldType.ANY
    stype = schema.get("type") or ""
    system = schema.get("system") or ""
    custom = schema.get("custom") or ""

    if system:
        m = {
            "priority": JiraFieldType.PRIORITY,
            "status": JiraFieldType.STATUS,
            "resolution": JiraFieldType.RESOLUTION,
            "issuetype": JiraFieldType.ISSUETYPE,
            "project": JiraFieldType.PROJECT,
            "parent": JiraFieldType.PARENT,
        }
        if system in m:
            return m[system]

    if custom and "epic" in str(custom).lower():
        return JiraFieldType.EPIC

    type_map = {
        "string": JiraFieldType.STRING,
        "number": JiraFieldType.NUMBER,
        "date": JiraFieldType.DATE,
        "datetime": JiraFieldType.DATETIME,
        "option": JiraFieldType.OPTION,
        "array": JiraFieldType.ARRAY,
        "user": JiraFieldType.USER,
        "priority": JiraFieldType.PRIORITY,
    }
    return type_map.get(stype, JiraFieldType.ANY)


def parse_projects_response(data: Any) -> List[JiraProject]:
    """
    Parse da resposta GET /rest/api/3/project (ou GET /rest/api/3/project/search paginado).

    Args:
        data: Lista de dicts (cada um um projeto) ou dict com chave "values" (lista).

    Returns:
        Lista de JiraProject. Retorna lista vazia se data for vazia ou inválida.
    """
    if isinstance(data, dict) and "values" in data and isinstance(data["values"], list):
        data = data["values"]
    if not data or not isinstance(data, list):
        return []
    result = []
    for item in data:
        if not isinstance(item, dict):
            continue
        lead = ""
        if item.get("lead") and isinstance(item["lead"], dict):
            lead = item["lead"].get("displayName") or ""
        avatar_url = ""
        if item.get("avatarUrls") and isinstance(item["avatarUrls"], dict):
            avatar_url = item["avatarUrls"].get("48x48") or ""
        name = item.get("name") or item.get("projectName") or ""
        result.append(
            JiraProject(
                id=str(item.get("id", "") or "").strip(),
                key=str(item.get("key", "") or "").strip(),
                name=str(name).strip() if name is not None else "",
                project_type_key=str(item.get("projectTypeKey", "") or "").strip(),
                avatar_url=avatar_url,
                description=str(item.get("description", "") or "").strip(),
                lead=lead,
            )
        )
    return result


def parse_issue_types_response(data: List[Dict[str, Any]]) -> List[JiraIssueType]:
    """
    Parse da resposta GET /rest/api/3/issuetype/project?projectId=X.

    Args:
        data: Lista de issue types.

    Returns:
        Lista de JiraIssueType.
    """
    if not data or not isinstance(data, list):
        return []
    result = []
    for item in data:
        if not isinstance(item, dict):
            continue
        result.append(
            JiraIssueType(
                id=str(item.get("id", "")),
                name=str(item.get("name", "")),
                description=str(item.get("description", "")),
                icon_url=str(item.get("iconUrl", "")),
                subtask=bool(item.get("subtask", False)),
                hierarchy_level=int(item.get("hierarchyLevel", 0)),
            )
        )
    return result


def parse_createmeta_fields(fields_dict: Dict[str, Any]) -> List[JiraFieldMetadata]:
    """
    Parse do dict 'fields' dentro de projects[].issuetypes[] do createmeta.

    Args:
        fields_dict: Dict keyed by field id, cada valor é o metadata do campo.

    Returns:
        Lista de JiraFieldMetadata.
    """
    if not fields_dict or not isinstance(fields_dict, dict):
        return []
    result = []
    for field_id, raw in fields_dict.items():
        if not isinstance(raw, dict):
            continue
        schema = raw.get("schema") or {}
        field_type = _infer_field_type(schema)
        key = str(raw.get("fieldId", field_id))
        allowed = raw.get("allowedValues") or []
        if not isinstance(allowed, list):
            allowed = []
        # allowedValues: lista de dicts com id, name (e possivelmente value)
        allowed_list = []
        for av in allowed:
            if isinstance(av, dict):
                allowed_list.append(
                    {
                        "id": str(av.get("id", "")),
                        "name": str(av.get("name", av.get("value", ""))),
                        "value": str(av.get("value", av.get("name", ""))),
                    }
                )

        # Custom field: top-level 'custom' or schema has 'custom'/'customId'
        is_custom = bool(raw.get("custom", False)) or bool(
            schema.get("custom") or schema.get("customId")
        )
        result.append(
            JiraFieldMetadata(
                id=str(raw.get("fieldId", field_id)),
                key=key,
                name=str(raw.get("name", "")),
                field_type=field_type,
                custom=is_custom,
                required=bool(raw.get("required", False)),
                has_default_value=bool(raw.get("hasDefaultValue", False)),
                default_value=raw.get("defaultValue"),
                allowed_values=allowed_list,
                schema_type=str(schema.get("type", "")),
                schema_system=schema.get("system"),
                schema_custom=schema.get("custom"),
            )
        )
    return result


def parse_field_list_response(data: List[Dict[str, Any]]) -> List[JiraFieldMetadata]:
    """
    Parse da resposta GET /rest/api/3/field (lista de campos da instância).

    Args:
        data: Lista de dicts (cada um um campo).

    Returns:
        Lista de JiraFieldMetadata (sem required/default/allowedValues; apenas id, name, key, custom, schema).
    """
    if not data or not isinstance(data, list):
        return []
    result = []
    for item in data:
        if not isinstance(item, dict):
            continue
        schema = item.get("schema") or {}
        field_type = _infer_field_type(schema)
        fid = str(item.get("id", ""))
        result.append(
            JiraFieldMetadata(
                id=fid,
                key=str(item.get("key", fid)),
                name=str(item.get("name", "")),
                field_type=field_type,
                custom=bool(item.get("custom", False)),
                required=False,
                has_default_value=False,
                default_value=None,
                allowed_values=[],
                schema_type=str(schema.get("type", "")),
                schema_system=schema.get("system"),
                schema_custom=schema.get("custom"),
                schema_raw=dict(schema) if schema else None,
            )
        )
    return result


def project_to_dict(project: JiraProject) -> Dict[str, Any]:
    """Converte JiraProject para dict (QML/JSON). Garante chaves str para QML."""
    return {
        "id": (project.id or "").strip() if project.id else "",
        "key": (project.key or "").strip() if project.key else "",
        "name": (project.name or "").strip() if project.name else "",
        "project_type_key": (
            (project.project_type_key or "").strip() if project.project_type_key else ""
        ),
        "avatar_url": project.avatar_url or "",
        "description": (
            (project.description or "").strip() if project.description else ""
        ),
        "lead": (project.lead or "").strip() if project.lead else "",
    }


def issue_type_to_dict(issue_type: JiraIssueType) -> Dict[str, Any]:
    """Converte JiraIssueType para dict (QML/JSON)."""
    return {
        "id": issue_type.id,
        "name": issue_type.name,
        "description": issue_type.description,
        "icon_url": issue_type.icon_url,
        "subtask": issue_type.subtask,
        "hierarchy_level": issue_type.hierarchy_level,
    }


def field_metadata_to_dict(field_meta: JiraFieldMetadata) -> Dict[str, Any]:
    """Converte JiraFieldMetadata para dict (QML/JSON)."""
    return {
        "id": field_meta.id,
        "key": field_meta.key,
        "name": field_meta.name,
        "field_type": field_meta.field_type.value,
        "custom": field_meta.custom,
        "required": field_meta.required,
        "has_default_value": field_meta.has_default_value,
        "default_value": field_meta.default_value,
        "allowed_values": list(field_meta.allowed_values),
        "schema_type": field_meta.schema_type,
    }
