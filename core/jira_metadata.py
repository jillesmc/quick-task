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


# --- Workflow / status / transitions (for jira_metadata.json workflow_metadata) ---


def get_default_workflow_from_schemes(
    schemes: List[Dict[str, Any]],
) -> Dict[str, str]:
    """
    Extrai o defaultWorkflow do primeiro scheme que tiver (POST workflowscheme/read).
    Issue types não listados em workflowsForIssueTypes usam esse workflow.
    Retorna {"workflowId": str, "workflowName": str} ou {} se nenhum scheme tiver defaultWorkflow.
    """
    for scheme in schemes or []:
        default = scheme.get("defaultWorkflow")
        if not isinstance(default, dict):
            continue
        w_id = (default.get("id") or "").strip()
        w_name = (default.get("name") or "").strip()
        if w_id or w_name:
            return {"workflowId": w_id, "workflowName": w_name}
    return {}


def build_issue_type_to_workflow_from_schemes(
    schemes: List[Dict[str, Any]],
) -> Dict[str, Dict[str, str]]:
    """
    Extrai mapeamento issueTypeId -> { workflowId, workflowName } da resposta
    POST /rest/api/3/workflowscheme/read (lista de schemes).
    Cada scheme pode ter workflowsForIssueTypes: [ { issueTypeIds: [], workflow: { id, name } } ].
    Retorna dict: issuetype_id -> { "workflowId": str, "workflowName": str }.
    """
    # Log quantidade de schemes recebidos (diagnóstico workflow_metadata)
    try:
        from src.utils.debug import debug_log
    except Exception:

        def debug_log(*_a, **_k):
            return

    debug_log(
        "JiraMetadata",
        "build_issue_type_to_workflow_from_schemes",
        "schemes.len=%d",
        len(schemes or []),
    )

    result: Dict[str, Dict[str, str]] = {}
    for scheme in schemes or []:
        for item in scheme.get("workflowsForIssueTypes") or []:
            w = item.get("workflow")
            if not w or not isinstance(w, dict):
                continue
            w_id = (w.get("id") or "").strip()
            w_name = (w.get("name") or "").strip()
            if not w_id and not w_name:
                continue
            for it_id in item.get("issueTypeIds") or []:
                sid = str(it_id).strip()
                if sid and sid not in result:
                    result[sid] = {"workflowId": w_id, "workflowName": w_name}
    debug_log(
        "JiraMetadata",
        "build_issue_type_to_workflow_from_schemes",
        "mapped_issue_types=%s",
        sorted(result.keys()),
    )
    return result


def build_statuses_by_issue_type(
    project_statuses: List[Dict[str, Any]],
) -> Dict[str, List[Dict[str, Any]]]:
    """
    Normaliza resposta GET /rest/api/3/project/{id}/statuses (lista por issue type).
    Cada item: { id, name, statuses: [ { id, name, statusCategory?, ... } ] }.
    Retorna dict: issuetype_id -> [ { id, name, category?, categoryName? } ].
    category = statusCategory.key, categoryName = statusCategory.name.
    """
    try:
        from src.utils.debug import debug_log
    except Exception:

        def debug_log(*_a, **_k):
            return

    result: Dict[str, List[Dict[str, Any]]] = {}
    for item in project_statuses or []:
        it_id = str(item.get("id") or "").strip()
        statuses_raw = item.get("statuses")
        if not isinstance(statuses_raw, list):
            continue
        out = []
        for s in statuses_raw:
            if not isinstance(s, dict):
                continue
            rec = {
                "id": str(s.get("id") or "").strip(),
                "name": (s.get("name") or "").strip(),
            }
            cat = s.get("statusCategory")
            if isinstance(cat, dict):
                if cat.get("key"):
                    rec["category"] = str(cat.get("key", "")).strip()
                if cat.get("name"):
                    rec["categoryName"] = str(cat.get("name", "")).strip()
            out.append(rec)
        if it_id:
            result[it_id] = out
    # Log resumo: quantos issue types, e info do primeiro status normalizado
    issuetypes = sorted(result.keys())
    first_it = issuetypes[0] if issuetypes else ""
    first_statuses = result.get(first_it) or []
    first_status = first_statuses[0] if first_statuses else {}
    debug_log(
        "JiraMetadata",
        "build_statuses_by_issue_type",
        "project_statuses.len=%d issuetypes.len=%d first_issuetype=%s first_status.id=%s first_status.category=%s",
        len(project_statuses or []),
        len(issuetypes),
        first_it,
        str(first_status.get("id") or "") if isinstance(first_status, dict) else "",
        (
            str(first_status.get("category") or "")
            if isinstance(first_status, dict)
            else ""
        ),
    )
    return result


def build_workflow_details_by_id(
    workflows_search_response: Dict[str, Any],
) -> Dict[str, Dict[str, Any]]:
    """
    Extrai de GET /rest/api/3/workflows/search (expand=values.transitions).
    Resposta: statuses (top-level, full) e values[] com id, name, statuses (refs), transitions.
    Cada transition: toStatusReference, links[].fromStatusReference, type, transitionScreen.parameters.screenId.
    Retorna dict: workflow_id -> { "workflowName", "statuses", "transitions" }.
    """
    try:
        from src.utils.debug import debug_log
    except Exception:

        def debug_log(*_a, **_k):
            return

    result: Dict[str, Dict[str, Any]] = {}
    values = workflows_search_response.get("values")
    if not isinstance(values, list):
        debug_log(
            "JiraMetadata",
            "build_workflow_details_by_id",
            "values.missing_or_not_list type=%s",
            type(values).__name__,
        )
        return result
    # statuses no topo da resposta: { id, statusReference, name, statusCategory (string) }
    top_statuses = workflows_search_response.get("statuses") or []
    global_status: Dict[str, Dict[str, str]] = {}
    for s in top_statuses if isinstance(top_statuses, list) else []:
        if not isinstance(s, dict):
            continue
        sid = str(s.get("id") or s.get("statusReference") or "").strip()
        if not sid:
            continue
        name = (s.get("name") or "").strip()
        cat = s.get("statusCategory")
        category = str(cat).lower() if cat is not None else ""
        global_status[sid] = {"name": name, "category": category}
    for w in values:
        if not isinstance(w, dict):
            continue
        w_id = str(w.get("id") or "").strip()
        w_name = (w.get("name") or "").strip()
        if not w_id:
            continue
        workflow_status = dict(global_status)
        w_statuses_raw = w.get("statuses") or []
        for s in w_statuses_raw if isinstance(w_statuses_raw, list) else []:
            if not isinstance(s, dict):
                continue
            ref = str(s.get("statusReference") or s.get("id") or "").strip()
            if not ref:
                continue
            name = (s.get("name") or "").strip()
            if name:
                workflow_status[ref] = {
                    "name": name,
                    "category": workflow_status.get(ref, {}).get("category", ""),
                }
        statuses = []
        for s in w_statuses_raw if isinstance(w_statuses_raw, list) else []:
            if not isinstance(s, dict):
                continue
            ref = str(s.get("statusReference") or s.get("id") or "").strip()
            if not ref:
                continue
            info = workflow_status.get(ref, {})
            statuses.append(
                {
                    "id": ref,
                    "name": info.get("name", ""),
                    "category": info.get("category", ""),
                }
            )
        transitions_raw = w.get("transitions") or []
        transitions = []
        for t in transitions_raw if isinstance(transitions_raw, list) else []:
            if not isinstance(t, dict):
                continue
            to_raw = t.get("toStatusReference") or t.get("to")
            if isinstance(to_raw, dict):
                to_id = str(to_raw.get("id") or "").strip()
            else:
                to_id = str(to_raw or "").strip()
            to_info = workflow_status.get(to_id, {})
            to_name = to_info.get("name", "")
            links = t.get("links") or []
            from_ids_uniq: List[str] = []
            seen: set = set()
            for link in links if isinstance(links, list) else []:
                if not isinstance(link, dict):
                    continue
                fid = str(
                    link.get("fromStatusReference") or link.get("from") or ""
                ).strip()
                if fid and fid not in seen:
                    seen.add(fid)
                    from_ids_uniq.append(fid)
            from_statuses = [
                {"id": fid, "name": workflow_status.get(fid, {}).get("name", "")}
                for fid in from_ids_uniq
            ]
            tr_type = t.get("type")
            type_str = str(tr_type).lower() if tr_type else None
            rec: Dict[str, Any] = {
                "id": str(t.get("id") or "").strip(),
                "name": (t.get("name") or "").strip(),
                "from": from_ids_uniq,
                "fromStatuses": from_statuses,
                "to": {"id": to_id, "name": to_name},
                "type": type_str,
            }
            ts = t.get("transitionScreen")
            if isinstance(ts, dict):
                params = ts.get("parameters") or {}
                screen_id = params.get("screenId")
                if screen_id is not None:
                    rec["screen"] = {
                        "id": str(screen_id).strip(),
                        "name": (ts.get("name") or "").strip(),
                    }
            transitions.append(rec)
        result[w_id] = {
            "workflowName": w_name,
            "statuses": statuses,
            "transitions": transitions,
        }
    return result
