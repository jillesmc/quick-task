"""
Modelo para descoberta e configuração de metadata do Jira (projetos, issue types, fields).
Expõe slots e sinais para o wizard de configuração (Issue #25).
"""

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
                fields_list = self._jira_client.get_createmeta_fields_for_issue_type(
                    self.project_key, self.issuetype_id
                )
                out = [_jira_meta.field_metadata_to_dict(f) for f in fields_list]
                self.fieldsLoaded.emit(out)
            else:
                self.discoveryError.emit(f"Unknown discovery kind: {self._kind}")
        except Exception as e:
            self.discoveryError.emit(str(e))


class JiraMetadataConfigModel(QObject):
    """Modelo para descoberta e persistência de metadata do Jira (QML)."""

    projectsLoaded = Signal(list)
    issueTypesLoaded = Signal(list)
    fieldsLoaded = Signal(list)
    discoveryError = Signal(str)
    saveFinished = Signal(bool)
    loadFinished = Signal(bool)

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

    @Slot()
    def loadConfiguration(self):
        """Carrega jira_metadata.json e armazena em memória; emite loadFinished(True)."""
        if not self._config_manager:
            self._loaded_metadata = {}
            self.loadFinished.emit(False)
            return
        try:
            self._loaded_metadata = self._config_manager.load_jira_metadata()
            self.loadFinished.emit(True)
        except Exception:
            self._loaded_metadata = {}
            self.loadFinished.emit(False)

    def getLoadedMetadata(self) -> Dict[str, Any]:
        """Retorna o último dict carregado por loadConfiguration (para testes e QML)."""
        return dict(self._loaded_metadata)
