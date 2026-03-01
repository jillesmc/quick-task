"""
Modelo para descoberta e configuração de metadata do Jira (projetos, issue types, fields).
Expõe slots e sinais para o wizard de configuração (Issue #25).
"""

import copy
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

from PySide6.QtCore import QObject, Property, Signal, Slot, QThread  # type: ignore[import]

ROOT_DIR = Path(__file__).parent.parent.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from core import jira_metadata as _jira_meta

try:
    from src.utils.debug import debug_log
except ImportError:

    def debug_log(*a, **k):
        pass


def _field_id_variants(field_id: str, key: Optional[str] = None) -> List[str]:
    """Retorna variantes do field id para lookup (id, key, customfield_<id>)."""
    ids = []
    if field_id:
        ids.append(str(field_id).strip())
    if key and key not in ids:
        ids.append(str(key).strip())
    fid = (field_id or "").strip()
    if fid.isdigit() and f"customfield_{fid}" not in ids:
        ids.append(f"customfield_{fid}")
    return ids


class EnrichmentWorker(QThread):
    """
    Worker que enriquece o payload de metadata com real_type, default_value e
    (quando aplicável) object_schema/filter_scope_aql para Assets.
    """

    enriched = Signal(dict)
    enrichmentError = Signal(str)

    def __init__(
        self,
        payload: Dict[str, Any],
        jira_client: Any,
        parent=None,
    ):
        super().__init__(parent)
        self._payload = payload
        self._jira_client = jira_client

    def run(self):
        try:
            enriched = self._enrich_payload()
            self.enriched.emit(enriched)
        except Exception as e:
            self.enrichmentError.emit(str(e))

    def _enrich_payload(self) -> Dict[str, Any]:
        payload = copy.deepcopy(self._payload)
        client = self._jira_client
        if not client:
            return payload

        # Map project key -> project id (context API uses projectId)
        project_key_to_id: Dict[str, str] = {}
        for p in payload.get("selected_projects") or []:
            if isinstance(p, dict) and p.get("key") and p.get("id"):
                project_key_to_id[str(p["key"])] = str(p["id"])

        # All fields for real_type lookup (cache)
        try:
            all_fields = client.get_fields()
        except Exception:
            all_fields = []
        field_id_to_meta: Dict[str, Any] = {}
        for f in all_fields:
            if f.id:
                field_id_to_meta[f.id] = f
            if f.key and f.key not in field_id_to_meta:
                field_id_to_meta[f.key] = f

        selected_fields = payload.get("selected_fields") or {}
        for project_key, by_issuetype in selected_fields.items():
            if not isinstance(by_issuetype, dict):
                continue
            project_id = project_key_to_id.get(project_key)
            for issuetype_id, field_list in by_issuetype.items():
                if not isinstance(field_list, list):
                    continue
                for field_obj in field_list:
                    if not isinstance(field_obj, dict):
                        continue
                    self._enrich_one_field(
                        field_obj,
                        project_id,
                        issuetype_id,
                        client,
                        field_id_to_meta,
                    )

        return payload

    def _enrich_one_field(
        self,
        field_obj: Dict[str, Any],
        project_id: Optional[str],
        issuetype_id: str,
        client: Any,
        field_id_to_meta: Dict[str, Any],
    ) -> None:
        field_id = (field_obj.get("id") or field_obj.get("key") or "").strip()
        key = (field_obj.get("key") or "").strip()
        if not field_id:
            return

        # real_type
        meta = None
        for vid in _field_id_variants(field_id, key):
            if vid in field_id_to_meta:
                meta = field_id_to_meta[vid]
                break
        if meta and getattr(meta, "schema_raw", None):
            field_obj["real_type"] = _jira_meta.schema_to_real_type(meta.schema_raw)
        else:
            schema_fallback = {}
            if meta:
                schema_fallback = {
                    "type": getattr(meta, "schema_type", "") or "",
                    "custom": getattr(meta, "schema_custom", "") or "",
                    "system": getattr(meta, "schema_system", "") or "",
                }
            field_obj["real_type"] = _jira_meta.schema_to_real_type(schema_fallback)

        # default_value and options: only for custom fields, when we have project_id
        context_id = None
        if project_id and meta and getattr(meta, "custom", False):
            try:
                mapping = client.get_field_context_mapping(
                    field_id, [project_id], [issuetype_id]
                )
                context_id = mapping[0].get("contextId") if mapping else None
            except Exception:
                pass

        if context_id and field_obj.get("real_type") != "Assets objects":
            try:
                defaults = client.get_field_context_default_value(
                    field_id, context_id=context_id
                )
                if defaults:
                    field_obj["default_value"] = defaults[0]
            except Exception:
                pass  # 403 or 400 (e.g. unsupported type) - leave default_value absent

        # options (valores possíveis) para Select List
        if context_id and field_obj.get("real_type") in (
            "Select List (single choice)",
            "Select List (multiple choices)",
        ):
            try:
                options_list = client.get_field_context_options(field_id, context_id)
                if options_list:
                    field_obj["options"] = options_list
            except Exception:
                pass

        # Assets: placeholders only when not already set (e.g. from wizard step 4).
        # Do not overwrite object_schema, filter_scope_aql, or any other Assets keys
        # (object_schema_id, object_type, object_type_id, etc.) when already present.
        if field_obj.get("real_type") == "Assets objects":
            if "object_schema" not in field_obj:
                field_obj["object_schema"] = None
            if "filter_scope_aql" not in field_obj:
                field_obj["filter_scope_aql"] = None


class DiscoveryWorker(QThread):
    """Worker thread para chamadas de discovery (projects, issue types, fields)."""

    projectsLoaded = Signal(list)  # list of dicts
    issueTypesLoaded = Signal(list)
    fieldsLoaded = Signal(list)
    discoveryError = Signal(str)

    def __init__(
        self,
        kind: str,
        jira_client: Any,
        config_manager: Any,
        project_id: Optional[str] = None,
        project_key: Optional[str] = None,
        issuetype_id: Optional[str] = None,
        parent=None,
    ):
        super().__init__(parent)
        self._kind = kind
        self._jira_client = jira_client
        self._config_manager = config_manager
        self.project_id = project_id
        self.project_key = project_key
        self.issuetype_id = issuetype_id

    def run(self):
        try:
            if self._kind == "projects":
                projects = self._jira_client.get_projects()
                out = [_jira_meta.project_to_dict(p) for p in projects]
                self.projectsLoaded.emit(out)
            elif self._kind == "issue_types":
                if not self.project_id:
                    self.discoveryError.emit("project_id is required")
                    return
                types_list = self._jira_client.get_project_issue_types(self.project_id)
                out = [_jira_meta.issue_type_to_dict(t) for t in types_list]
                self.issueTypesLoaded.emit(out)
            elif self._kind == "fields":
                if not self.project_key or not self.issuetype_id:
                    self.discoveryError.emit(
                        "project_key and issuetype_id are required"
                    )
                    return
                fields_list = self._jira_client.get_fields_for_issue_type(
                    self.project_key, self.issuetype_id
                )
                out = [_jira_meta.field_metadata_to_dict(f) for f in fields_list]
                # Enrich with real_type from GET /field (schema_raw) for Assets detection
                try:
                    all_fields = self._jira_client.get_fields()
                    field_id_to_real_type = {}
                    for meta in all_fields:
                        if meta.id:
                            rt = _jira_meta.schema_to_real_type(
                                getattr(meta, "schema_raw", None)
                            )
                            field_id_to_real_type[meta.id] = rt
                        if meta.key and meta.key not in field_id_to_real_type:
                            rt = _jira_meta.schema_to_real_type(
                                getattr(meta, "schema_raw", None)
                            )
                            field_id_to_real_type[meta.key] = rt
                    for item in out:
                        fid = (item.get("id") or item.get("key") or "").strip()
                        item["real_type"] = field_id_to_real_type.get(fid, "Unknown")
                except Exception:
                    for item in out:
                        if "real_type" not in item:
                            item["real_type"] = "Unknown"
                self.fieldsLoaded.emit(out)
            else:
                self.discoveryError.emit(f"Unknown discovery kind: {self._kind}")
        except Exception as e:
            self.discoveryError.emit(str(e))


class AssetsLoadWorker(QThread):
    """
    Worker que carrega object schemas ou object types do Jira Assets em background.
    Emite assetsObjectSchemasLoaded(list), assetsObjectTypesLoaded(list) ou assetsLoadError(str).
    """

    assetsObjectSchemasLoaded = Signal(list)
    assetsObjectTypesLoaded = Signal(list)
    assetsLoadError = Signal(str)

    def __init__(
        self,
        jira_client: Any,
        config_manager: Optional[Any],
        mode: str,
        schema_id: Optional[str] = None,
        parent=None,
    ):
        super().__init__(parent)
        self._jira_client = jira_client
        self._config_manager = config_manager
        self._mode = mode
        self._schema_id = (schema_id or "").strip() if schema_id else None

    def run(self):
        debug_log(
            "AssetsLoadWorker",
            "run",
            "mode=%s schema_id=%s",
            self._mode,
            self._schema_id or "(none)",
        )
        client = self._jira_client
        config = self._config_manager
        if not client:
            debug_log("AssetsLoadWorker", "run", "emitting assetsLoadError: no client")
            self.assetsLoadError.emit("Configure a conexão Jira primeiro.")
            return
        cloud_id = None
        if config:
            try:
                cloud_id = config.get_assets_cloud_id()
            except Exception:
                pass
        if not cloud_id and hasattr(client, "get_cloud_id_from_tenant"):
            try:
                cloud_id = client.get_cloud_id_from_tenant()
            except Exception:
                pass
        workspace_id = None
        if hasattr(client, "get_assets_workspace_id"):
            try:
                workspace_id = client.get_assets_workspace_id()
            except Exception:
                pass
        debug_log(
            "AssetsLoadWorker",
            "run",
            "cloud_id=%s workspace_id=%s",
            cloud_id if cloud_id else "missing",
            workspace_id if workspace_id else "missing",
        )
        if not cloud_id:
            debug_log(
                "AssetsLoadWorker", "run", "emitting assetsLoadError: no cloud_id"
            )
            self.assetsLoadError.emit(
                "Não foi possível obter o cloud ID. Verifique a conexão ou configure assets.cloud_id."
            )
            return
        if not workspace_id:
            debug_log(
                "AssetsLoadWorker", "run", "emitting assetsLoadError: no workspace_id"
            )
            self.assetsLoadError.emit(
                "Não foi possível carregar os object schemas. Verifique a conexão e se o Jira Assets está habilitado."
            )
            return
        try:
            if self._mode == "schemas":
                schemas = client.get_assets_object_schemas(cloud_id, workspace_id)
                self.assetsObjectSchemasLoaded.emit(schemas)
            elif self._mode == "types" and self._schema_id:
                types_list = client.get_assets_object_types(
                    cloud_id, workspace_id, self._schema_id
                )
                debug_log(
                    "AssetsLoadWorker",
                    "run",
                    "emitting assetsObjectTypesLoaded len=%s first=%s",
                    len(types_list),
                    types_list[0] if types_list else None,
                )
                self.assetsObjectTypesLoaded.emit(types_list)
            else:
                err = "Parâmetros inválidos para carregar Assets."
                debug_log(
                    "AssetsLoadWorker", "run", "emitting assetsLoadError: %s", err
                )
                self.assetsLoadError.emit(err)
        except Exception as e:
            debug_log(
                "AssetsLoadWorker", "run", "emitting assetsLoadError exception: %s", e
            )
            self.assetsLoadError.emit(str(e))


class JiraMetadataConfigModel(QObject):
    """Modelo para descoberta e persistência de metadata do Jira (QML)."""

    projectsLoaded = Signal(list)
    issueTypesLoaded = Signal(list)
    fieldsLoaded = Signal(list)
    discoveryError = Signal(str)
    saveFinished = Signal(bool)
    loadFinished = Signal(bool)
    assetsObjectSchemasLoaded = Signal(list)
    assetsObjectTypesLoaded = Signal(list)
    assetsLoadError = Signal(str)

    def __init__(
        self,
        jira_client: Optional[Any] = None,
        config_manager: Optional[Any] = None,
        parent=None,
    ):
        super().__init__(parent)
        self._jira_client = jira_client
        self._config_manager = config_manager or self._default_config_manager()
        self._loaded_metadata: Dict[str, Any] = {}
        self._worker: Optional[DiscoveryWorker] = None
        self._enrichment_worker: Optional[EnrichmentWorker] = None
        self._assets_worker: Optional[AssetsLoadWorker] = None

    def _default_config_manager(self):
        try:
            from config.config_manager import ConfigManager

            return ConfigManager()
        except Exception:
            return None

    @Slot(result=bool)
    def isAvailable(self) -> bool:
        """True se o cliente Jira está configurado e pode ser usado para discovery."""
        return self._jira_client is not None and self._config_manager is not None

    @Slot()
    def discoverProjects(self):
        """Inicia descoberta de projetos em background. Emite projectsLoaded ou discoveryError."""
        if not self._jira_client:
            self.discoveryError.emit("Configure a conexão Jira primeiro.")
            return
        self._worker = DiscoveryWorker(
            kind="projects",
            jira_client=self._jira_client,
            config_manager=self._config_manager,
        )
        self._worker.projectsLoaded.connect(self._on_projects_loaded)
        self._worker.discoveryError.connect(self._on_discovery_error)
        self._worker.finished.connect(self._worker.deleteLater)
        self._worker.start()

    def _on_projects_loaded(self, projects: list):
        self.projectsLoaded.emit(projects)

    def _on_discovery_error(self, message: str):
        self.discoveryError.emit(message)

    @Slot(str)
    def discoverIssueTypes(self, project_id: str):
        """Inicia descoberta de issue types do projeto. Emite issueTypesLoaded ou discoveryError."""
        if not self._jira_client:
            self.discoveryError.emit("Configure a conexão Jira primeiro.")
            return
        self._worker = DiscoveryWorker(
            kind="issue_types",
            jira_client=self._jira_client,
            config_manager=self._config_manager,
            project_id=project_id,
        )
        self._worker.issueTypesLoaded.connect(self.issueTypesLoaded.emit)
        self._worker.discoveryError.connect(self._on_discovery_error)
        self._worker.finished.connect(self._worker.deleteLater)
        self._worker.start()

    @Slot(str, str)
    def discoverFields(self, project_key: str, issuetype_id: str):
        """Inicia descoberta de campos para (project_key, issuetype_id). Emite fieldsLoaded ou discoveryError."""
        if not self._jira_client:
            self.discoveryError.emit("Configure a conexão Jira primeiro.")
            return
        self._worker = DiscoveryWorker(
            kind="fields",
            jira_client=self._jira_client,
            config_manager=self._config_manager,
            project_key=project_key,
            issuetype_id=issuetype_id,
        )
        self._worker.fieldsLoaded.connect(self.fieldsLoaded.emit)
        self._worker.discoveryError.connect(self._on_discovery_error)
        self._worker.finished.connect(self._worker.deleteLater)
        self._worker.start()

    @Slot()
    def loadAssetsObjectSchemas(self):
        """Carrega object schemas do Jira Assets em background. Emite assetsObjectSchemasLoaded(list) ou assetsLoadError(str)."""
        if not self._jira_client:
            self.assetsLoadError.emit("Configure a conexão Jira primeiro.")
            return
        self._assets_worker = AssetsLoadWorker(
            jira_client=self._jira_client,
            config_manager=self._config_manager,
            mode="schemas",
            parent=self,
        )
        self._assets_worker.assetsObjectSchemasLoaded.connect(
            self.assetsObjectSchemasLoaded.emit
        )
        self._assets_worker.assetsLoadError.connect(self.assetsLoadError.emit)
        self._assets_worker.finished.connect(self._assets_worker.deleteLater)
        self._assets_worker.start()

    @Slot(str)
    def loadAssetsObjectTypes(self, schema_id: str):
        """Carrega object types do schema Assets em background. Emite assetsObjectTypesLoaded(list) ou assetsLoadError(str)."""
        debug_log(
            "JiraMetadataConfigModel",
            "loadAssetsObjectTypes",
            "schema_id=%s",
            schema_id,
        )
        if not self._jira_client:
            self.assetsLoadError.emit("Configure a conexão Jira primeiro.")
            return
        if not (schema_id and str(schema_id).strip()):
            self.assetsLoadError.emit("ID do object schema é obrigatório.")
            return
        self._assets_worker = AssetsLoadWorker(
            jira_client=self._jira_client,
            config_manager=self._config_manager,
            mode="types",
            schema_id=str(schema_id).strip(),
            parent=self,
        )
        self._assets_worker.assetsObjectTypesLoaded.connect(
            self.assetsObjectTypesLoaded.emit
        )
        self._assets_worker.assetsLoadError.connect(self.assetsLoadError.emit)
        self._assets_worker.finished.connect(self._assets_worker.deleteLater)
        self._assets_worker.start()

    @Slot(dict)
    def saveConfiguration(self, data: Dict[str, Any]):
        """Salva o dict em jira_metadata.json. Emite saveFinished(True) ou discoveryError em caso de falha."""
        if not self._config_manager:
            self.discoveryError.emit("Configuração não disponível.")
            return
        try:
            self._config_manager.save_jira_metadata(data)
            self.saveFinished.emit(True)
        except Exception as e:
            self.discoveryError.emit(str(e))
            self.saveFinished.emit(False)

    @Slot(dict)
    def enrichAndSave(self, data: Dict[str, Any]):
        """
        Enriquece o payload com real_type, default_value e (se Assets) object_schema/filter_scope_aql,
        depois salva em jira_metadata.json. Emite saveFinished(True) ou discoveryError e saveFinished(False).
        """
        if not self._config_manager:
            self.discoveryError.emit("Configuração não disponível.")
            self.saveFinished.emit(False)
            return
        if not self._jira_client:
            self.discoveryError.emit("Configure a conexão Jira primeiro.")
            self.saveFinished.emit(False)
            return
        self._enrichment_worker = EnrichmentWorker(
            payload=data,
            jira_client=self._jira_client,
            parent=self,
        )
        self._enrichment_worker.enriched.connect(self._on_enrichment_done)
        self._enrichment_worker.enrichmentError.connect(self._on_enrichment_error)
        self._enrichment_worker.finished.connect(self._enrichment_worker.deleteLater)
        self._enrichment_worker.start()

    def _on_enrichment_done(self, enriched_data: Dict[str, Any]):
        self._enrichment_worker = None
        try:
            self._config_manager.save_jira_metadata(enriched_data)
            self.saveFinished.emit(True)
        except Exception as e:
            self.discoveryError.emit(str(e))
            self.saveFinished.emit(False)

    def _on_enrichment_error(self, message: str):
        self._enrichment_worker = None
        self.discoveryError.emit(message)
        self.saveFinished.emit(False)

    @Slot()
    def loadConfiguration(self):
        """Carrega jira_metadata.json e armazena em memória; emite loadFinished(True)."""
        if not self._config_manager:
            debug_log(
                "JiraMetadataConfigModel", "loadConfiguration", "no config_manager"
            )
            self._loaded_metadata = {}
            self.loadFinished.emit(False)
            return
        try:
            path = self._config_manager.get_jira_metadata_path()
            debug_log(
                "JiraMetadataConfigModel", "loadConfiguration", "loading path=%s", path
            )
            self._loaded_metadata = self._config_manager.load_jira_metadata()
            sp = self._loaded_metadata.get("selected_projects") or []
            debug_log(
                "JiraMetadataConfigModel",
                "loadConfiguration",
                "success selected_projects len=%s",
                len(sp),
            )
            self.loadFinished.emit(True)
        except Exception as e:
            debug_log("JiraMetadataConfigModel", "loadConfiguration", "error: %s", e)
            self._loaded_metadata = {}
            self.loadFinished.emit(False)

    @Slot(result="QVariantMap")
    def getLoadedMetadata(self) -> Dict[str, Any]:
        """Retorna o último dict carregado por loadConfiguration (para testes e QML). Exposto como Slot para QML."""
        return dict(self._loaded_metadata)

    @Slot(result="QVariantList")
    def getLoadedSelectedProjects(self) -> List[Dict[str, str]]:
        """Retorna lista de projetos para o QML, cada um com key e name como string (evita problemas de QVariant no Repeater)."""
        sp = self._loaded_metadata.get("selected_projects") or []
        return [
            {"key": str(p.get("key", "")), "name": str(p.get("name", ""))}
            for p in sp
            if isinstance(p, dict)
        ]
