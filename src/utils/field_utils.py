"""
Utilitários para IDs de campos Jira (custom fields) e formato de Assets.
"""

from typing import Any, Dict, List

# IDs de exemplo/placeholder usados em config.json.example; não são IDs reais da API.
PLACEHOLDER_CUSTOM_FIELD_IDS = frozenset({"customfield_XXXXX", "customfield_YYYYY"})


def normalize_asset_field_value(value: Any) -> Any:
    """
    Normaliza valor de campo Asset para o formato da API Jira/Assets.
    Ref: https://support.atlassian.com/jira/kb/how-to-create-issues-with-assets-custom-field-using-jira-service-management-api/

    Formato esperado: [{"id": "{workspaceId}:{objectId}", "objectId": "{objectId}", "workspaceId": "{workspaceId}"}]
    Se value for uma lista de dicts com id/objectId/workspaceId, retorna lista com apenas essas chaves.
    Caso contrário retorna value inalterado.
    """
    if not isinstance(value, list) or not value:
        return value
    out: List[Dict[str, Any]] = []
    for item in value:
        if not isinstance(item, dict):
            out.append(item)
            continue
        wid = item.get("workspaceId")
        oid = item.get("objectId")
        gid = item.get("id")
        if wid is not None and oid is not None:
            out.append(
                {
                    "id": gid if gid is not None else f"{wid}:{oid}",
                    "objectId": str(oid),
                    "workspaceId": str(wid),
                }
            )
        else:
            out.append(item)
    return out


def is_placeholder_custom_field_id(field_id: str) -> bool:
    """
    Retorna True se field_id for um placeholder (ex.: customfield_XXXXX, customfield_YYYYY),
    ou um padrão comum de exemplo (customfield_ + só letras maiúsculas).
    Esses IDs não existem no Jira e causam HTTP 400 se enviados no payload.
    """
    if not field_id or not isinstance(field_id, str):
        return False
    fid = field_id.strip()
    if fid in PLACEHOLDER_CUSTOM_FIELD_IDS:
        return True
    # customfield_ seguido só de maiúsculas (ex.: customfield_XXXXX)
    if fid.startswith("customfield_") and len(fid) > 11:
        suffix = fid[11:]
        if suffix.isalpha() and suffix.isupper() and len(suffix) <= 20:
            return True
    return False
