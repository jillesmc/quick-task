"""
Cache de opções de Jira Assets para os campos Valor entregue e Plataformas afetadas.
Carrega opções via POST /object/aql (api.atlassian.com), persiste em disco e expõe
listas por campo (objectId, label, workspaceId, id global) para a UI e para montagem
de payloads de create/update.
"""

import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from src.utils.debug import debug_log

# Aliases Jira para descoberta de customfield_
ASSET_FIELD_ALIASES = {
    "valor_entregue": ["Qual tipo de valor", "Qual_tipo_de_valor"],
    "plataformas_afetadas": ["Quais Plataformas Afetadas", "Quais_Plataformas_Afetadas"],
}


def _normalize_label(obj: Dict[str, Any]) -> str:
    """Extrai label de um objeto Asset da API (label, name ou objectKey)."""
    return (
        obj.get("label")
        or obj.get("name")
        or obj.get("objectKey")
        or str(obj.get("id", ""))
    )


def _object_to_cache_entry(obj: Dict[str, Any], workspace_id: str) -> Dict[str, Any]:
    """Converte um objeto da resposta POST /object/aql para entrada do cache."""
    oid = obj.get("id") or obj.get("objectKey") or ""
    if isinstance(oid, dict):
        oid = oid.get("id") or oid.get("objectKey") or ""
    global_id = obj.get("globalId") or (f"{workspace_id}:{oid}" if workspace_id else oid)
    return {
        "workspaceId": obj.get("workspaceId") or workspace_id,
        "objectId": str(oid),
        "id": str(global_id),
        "label": _normalize_label(obj),
    }


def _default_cache_path() -> Path:
    xdg = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
    return Path(xdg) / "jira-quick-task" / "assets-cache.json"


class AssetsCacheService:
    """
    Serviço de cache de opções de Assets (Valor entregue, Plataformas afetadas).
    Lê/grava cache em disco e usa JiraClient para buscar objetos via POST /object/aql.
    """

    def __init__(
        self,
        jira_client: Any,
        config: Any,
        cache_path: Optional[Path] = None,
    ):
        self._client = jira_client
        self._config = config
        self._cache_path = cache_path or _default_cache_path()
        self._cache: Dict[str, Any] = {
            "valor_entregue": [],
            "plataformas_afetadas": [],
            "updated_at": None,
        }

    def _load_from_disk(self) -> bool:
        """Carrega cache do disco. Retorna True se leu com sucesso. Dados malformados são ignorados."""
        if not self._cache_path or not self._cache_path.exists():
            return False
        try:
            with open(self._cache_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            ve = data.get("valor_entregue")
            self._cache["valor_entregue"] = (
                [e for e in (ve if isinstance(ve, list) else []) if isinstance(e, dict)]
            )
            pa = data.get("plataformas_afetadas")
            self._cache["plataformas_afetadas"] = (
                [e for e in (pa if isinstance(pa, list) else []) if isinstance(e, dict)]
            )
            self._cache["updated_at"] = data.get("updated_at")
            return True
        except (json.JSONDecodeError, OSError):
            return False

    def _save_to_disk(self) -> bool:
        """Persiste cache no disco. Retorna True se salvou com sucesso."""
        if not self._cache_path:
            return False
        try:
            self._cache_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self._cache_path, "w", encoding="utf-8") as f:
                json.dump(
                    {
                        "valor_entregue": self._cache["valor_entregue"],
                        "plataformas_afetadas": self._cache["plataformas_afetadas"],
                        "updated_at": self._cache["updated_at"],
                    },
                    f,
                    indent=2,
                    ensure_ascii=False,
                )
            return True
        except (OSError, TypeError):
            return False

    def _ensure_field_ids_in_config(self) -> None:
        """Se custom_fields.valor_entregue/plataformas_afetadas estiverem vazios, descobre via API e persiste."""
        for key, aliases in ASSET_FIELD_ALIASES.items():
            if self._config.get_custom_field(key):
                continue
            for alias in aliases:
                fid = self._client.get_field_id_by_name(alias)
                if fid:
                    self._config.set_custom_field(key, fid)
                    self._config.save_config()
                    break

    def reload(self) -> Tuple[bool, str]:
        """
        Recarrega opções da API de Assets e atualiza o cache em disco.
        Retorna (success, message) para a UI. Nunca levanta exceção.
        """
        import datetime
        from datetime import timezone

        try:
            self._ensure_field_ids_in_config()
        except Exception as e:
            return False, f"Erro ao obter IDs dos campos: {e!s}"

        try:
            cloud_id = self._config.get_assets_cloud_id() if self._config else None
            if not cloud_id and self._client:
                cloud_id = self._client.get_cloud_id_from_tenant()
                if cloud_id and self._config:
                    self._config.set_assets_config(cloud_id=cloud_id)
                    self._config.save_config()
            workspace_id = self._client.get_assets_workspace_id() if self._client else None

            if not cloud_id:
                return False, "Assets: cloud_id não configurado (config.assets.cloud_id). Preencha em config.json ou use servidor *.atlassian.net para detecção automática."
            if not workspace_id:
                return False, "Assets: não foi possível obter workspaceId (Assets habilitado no Jira?)."

            debug_log(
                "AssetsCacheService",
                "reload",
                "cloud_id=%s, workspace_id=%s",
                cloud_id,
                workspace_id,
            )

            type_id_valor = (
                self._config.get_assets_object_type_id_valor_entregue()
                if self._config
                else None
            )
            type_id_plataformas = (
                self._config.get_assets_object_type_id_plataformas() if self._config else None
            )
            type_valor = (
                self._config.get_assets_object_type_valor_entregue()
                if self._config
                else None
            )
            type_plataformas = (
                self._config.get_assets_object_type_plataformas() if self._config else None
            )

            def _aql_object_type_by_id(oid: int) -> str:
                return f"objectTypeId = {oid}"

            def _aql_object_type_by_name(name: str) -> str:
                if not name or " " in name or "/" in name or '"' in name:
                    escaped = (name or "").replace('"', '\\"')
                    return f'objectType = "{escaped}"'
                return f"objectType = {name}"

            def _aql_valor() -> Optional[str]:
                if type_id_valor is not None:
                    return _aql_object_type_by_id(type_id_valor)
                if type_valor:
                    return _aql_object_type_by_name(type_valor)
                return None

            def _aql_plataformas() -> Optional[str]:
                if type_id_plataformas is not None:
                    return _aql_object_type_by_id(type_id_plataformas)
                if type_plataformas:
                    return _aql_object_type_by_name(type_plataformas)
                return None

            ql_ve = _aql_valor()
            ql_pa = _aql_plataformas()
            debug_log(
                "AssetsCacheService",
                "reload",
                "ql_ve=%s, ql_pa=%s",
                ql_ve,
                ql_pa,
            )
            if not ql_ve and not ql_pa:
                return (
                    False,
                    "Configure em config.json → assets: object_type_id_valor_entregue e/ou "
                    "object_type_id_plataformas_afetadas (ou object_type_valor_entregue / object_type_plataformas_afetadas). "
                    "Sem isso a query AQL não é montada e nenhum dado é buscado.",
                )

            all_values_ve: List[Dict[str, Any]] = []
            if ql_ve and self._client:
                start = 0
                while True:
                    result = self._client.fetch_assets_objects_aql(
                        cloud_id=cloud_id,
                        workspace_id=workspace_id,
                        ql_query=ql_ve,
                        start_at=start,
                        max_results=50,
                    )
                    vals = result.get("values") if isinstance(result.get("values"), list) else []
                    debug_log(
                        "AssetsCacheService",
                        "reload",
                        "Valor entregue API: startAt=%s, raw values count=%s, isLast=%s, result keys=%s",
                        start,
                        len(vals),
                        result.get("isLast"),
                        list(result.keys()) if isinstance(result, dict) else type(result).__name__,
                    )
                    if vals and start == 0:
                        first = vals[0]
                        debug_log(
                            "AssetsCacheService",
                            "reload",
                            "Valor entregue primeiro item keys: %s",
                            list(first.keys()) if isinstance(first, dict) else type(first).__name__,
                        )
                    for obj in vals:
                        if isinstance(obj, dict):
                            all_values_ve.append(
                                _object_to_cache_entry(obj, workspace_id or "")
                            )
                    if result.get("isLast", True) or len(vals) < 50:
                        break
                    start += 50

            debug_log(
                "AssetsCacheService",
                "reload",
                "Valor entregue após parse: %s entradas (ex.: %s)",
                len(all_values_ve),
                all_values_ve[0] if all_values_ve else None,
            )

            all_values_pa: List[Dict[str, Any]] = []
            if ql_pa and self._client:
                start = 0
                while True:
                    result = self._client.fetch_assets_objects_aql(
                        cloud_id=cloud_id,
                        workspace_id=workspace_id,
                        ql_query=ql_pa,
                        start_at=start,
                        max_results=50,
                    )
                    vals = result.get("values") if isinstance(result.get("values"), list) else []
                    debug_log(
                        "AssetsCacheService",
                        "reload",
                        "Plataformas API: startAt=%s, raw values count=%s, isLast=%s",
                        start,
                        len(vals),
                        result.get("isLast"),
                    )
                    if vals and start == 0:
                        first = vals[0]
                        debug_log(
                            "AssetsCacheService",
                            "reload",
                            "Plataformas primeiro item keys: %s",
                            list(first.keys()) if isinstance(first, dict) else type(first).__name__,
                        )
                    for obj in vals:
                        if isinstance(obj, dict):
                            all_values_pa.append(
                                _object_to_cache_entry(obj, workspace_id or "")
                            )
                    if result.get("isLast", True) or len(vals) < 50:
                        break
                    start += 50

            debug_log(
                "AssetsCacheService",
                "reload",
                "Plataformas após parse: %s entradas (ex.: %s)",
                len(all_values_pa),
                all_values_pa[0] if all_values_pa else None,
            )

            # Só sobrescrever no cache as listas que foram efetivamente buscadas
            # (evita gravar [] quando não há query AQL configurada para aquele campo)
            if ql_ve:
                self._cache["valor_entregue"] = all_values_ve
            if ql_pa:
                self._cache["plataformas_afetadas"] = all_values_pa
            self._cache["updated_at"] = (
                datetime.datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            )
            saved = self._save_to_disk()
            debug_log(
                "AssetsCacheService",
                "reload",
                "Cache em disco: valor_entregue=%s, plataformas_afetadas=%s, _save_to_disk=%s, path=%s",
                len(self._cache["valor_entregue"]),
                len(self._cache["plataformas_afetadas"]),
                saved,
                self._cache_path,
            )
            return True, "Opções de Valor entregue e Plataformas recarregadas."
        except Exception as e:
            return False, f"Erro ao recarregar Assets: {e!s}"

    def load(self) -> None:
        """Carrega cache do disco (se existir). Não chama a API."""
        self._load_from_disk()

    def get_valor_entregue_options(self) -> List[Dict[str, Any]]:
        """Retorna lista de opções para Valor entregue: [{ objectId, id, workspaceId, label }, ...]."""
        raw = self._cache.get("valor_entregue", [])
        return [e for e in (raw if isinstance(raw, list) else []) if isinstance(e, dict)]

    def get_plataformas_afetadas_options(self) -> List[Dict[str, Any]]:
        """Retorna lista de opções para Plataformas afetadas: [{ objectId, id, workspaceId, label }, ...]."""
        raw = self._cache.get("plataformas_afetadas", [])
        return [e for e in (raw if isinstance(raw, list) else []) if isinstance(e, dict)]

    def get_valor_entregue_labels(self) -> List[str]:
        """Retorna apenas os labels para Valor entregue (para exibição na UI)."""
        return [e.get("label", "") for e in self.get_valor_entregue_options()]

    def get_plataformas_afetadas_labels(self) -> List[str]:
        """Retorna apenas os labels para Plataformas afetadas (para exibição na UI)."""
        return [e.get("label", "") for e in self.get_plataformas_afetadas_options()]

    def resolve_valor_entregue_object(self, object_id: str) -> Optional[Dict[str, Any]]:
        """
        Dado um objectId (ou label) de Valor entregue, retorna o objeto completo
        { workspaceId, id, objectId } para envio na API, ou None se não encontrado.
        """
        for e in self.get_valor_entregue_options():
            if e.get("objectId") == object_id or e.get("id") == object_id:
                return {
                    "workspaceId": e.get("workspaceId"),
                    "id": e.get("id"),
                    "objectId": e.get("objectId"),
                }
            if e.get("label") == object_id:
                return {
                    "workspaceId": e.get("workspaceId"),
                    "id": e.get("id"),
                    "objectId": e.get("objectId"),
                }
        return None

    def resolve_plataformas_objects(
        self, object_ids: List[str]
    ) -> List[Dict[str, Any]]:
        """
        Dada uma lista de objectIds (ou labels) de Plataformas afetadas, retorna
        lista de objetos completos { workspaceId, id, objectId } para envio na API.
        """
        options = {e.get("objectId"): e for e in self.get_plataformas_afetadas_options()}
        options_by_label = {e.get("label"): e for e in self.get_plataformas_afetadas_options()}
        out = []
        for oid in object_ids or []:
            e = options.get(oid) or options_by_label.get(oid)
            if e:
                out.append({
                    "workspaceId": e.get("workspaceId"),
                    "id": e.get("id"),
                    "objectId": e.get("objectId"),
                })
        return out
