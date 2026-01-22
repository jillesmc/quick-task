"""
Modelo para lista de issues do usuário logado

Expõe uma lista simples de issues para uso em QML, obtida via ACLI (Atlassian CLI).
"""

from pathlib import Path
import sys
from typing import Any, Dict, List, Optional

from PySide2.QtCore import QObject, Property, Signal, Slot, QThread  # type: ignore[import]

# Adicionar diretório raiz ao path
ROOT_DIR = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT_DIR))

from config.config_manager import ConfigManager
from core.jira_client import JiraClient


class SearchWorker(QThread):
    """Worker thread para busca assíncrona de issues"""
    
    issuesFound = Signal(list)  # Lista de issues encontradas
    errorOccurred = Signal(str)  # Mensagem de erro
    
    def __init__(
        self,
        jira_client,
        config,
        assignee_email: str,
        query: str = "",
        parent=None,
    ):
        super().__init__(parent)
        self._jira_client = jira_client
        self._config = config
        self._assignee_email = assignee_email
        self._query = query
    
    def run(self):
        """Executa a busca em thread separada"""
        try:
            # Filtrar para não trazer issues já concluídas (statusCategory != Done)
            extra_jql = 'AND statusCategory != Done'
            raw_issues = self._jira_client.get_my_issues(
                assignee_email=self._assignee_email,
                max_results=100,
                extra_jql=extra_jql,
                query=self._query if self._query else "",
            )

            simplified: List[Dict[str, Any]] = []
            for issue in raw_issues:
                key = issue.get("key")
                fields = issue.get("fields") or {}
                summary = fields.get("summary", "")
                status = (fields.get("status") or {}).get("name", "")
                issue_type = (fields.get("issuetype") or {}).get("name", "")
                assignee = (fields.get("assignee") or {}).get("displayName", "")
                
                # Extrair informação de parent (Epic ou outro parent)
                # REST API retorna parent diretamente na busca
                parent_key = ""
                parent = fields.get("parent")
                if parent:
                    # REST API retorna parent como dict com key direto
                    if isinstance(parent, dict):
                        parent_key = parent.get("key", "")

                simplified.append(
                    {
                        "key": key,
                        "summary": summary,
                        "status": status,
                        "issueType": issue_type,
                        "assignee": assignee,
                        "parentKey": parent_key,
                        "parentSummary": "",  # Não buscamos mais o summary
                    }
                )

            self.issuesFound.emit(simplified)
        except Exception as e:
            self.errorOccurred.emit(str(e))


class MyIssuesModel(QObject):
    """Modelo para lista de issues do usuário"""

    issuesChanged = Signal()
    loadingChanged = Signal(bool)
    errorOccurred = Signal(str)

    def __init__(self, parent=None) -> None:
        super().__init__(parent)

        self._issues: List[Dict[str, Any]] = []
        self._is_loading: bool = False
        self._search_worker: Optional[SearchWorker] = None

        # Carregar configuração
        try:
            self._config = ConfigManager()
        except Exception as e:  # pragma: no cover - log simples
            print(f"Erro ao carregar configuração em MyIssuesModel: {e}", file=sys.stderr)
            self._config = None

        # Inicializar JiraClient com o mesmo caminho de config do .jira-config.yml
        try:
            jira_cli_config_path: Optional[Path] = None
            account_id = None
            if self._config:
                jira_cli_config_path = self._config.get_jira_cli_config_path()
                account_id = self._config.get_account_id()
            self._jira_client = JiraClient(jira_cli_config_path=jira_cli_config_path, account_id=account_id)
        except RuntimeError as e:  # pragma: no cover - log simples
            print(f"Erro ao inicializar JiraClient em MyIssuesModel: {e}", file=sys.stderr)
            self._jira_client = None

    # ------------------------------------------------------------------
    # Propriedades
    # ------------------------------------------------------------------

    @Property(list, notify=issuesChanged)
    def issues(self) -> List[Dict[str, Any]]:
        """Lista de issues do usuário."""
        return self._issues

    @Property(bool, notify=loadingChanged)
    def isLoading(self) -> bool:
        """Indica se uma busca está em andamento."""
        return self._is_loading

    # ------------------------------------------------------------------
    # Métodos auxiliares
    # ------------------------------------------------------------------

    def _set_loading(self, value: bool) -> None:
        if self._is_loading != value:
            self._is_loading = value
            self.loadingChanged.emit(value)

    def _set_issues(self, issues: List[Dict[str, Any]]) -> None:
        self._issues = issues or []
        self.issuesChanged.emit()

    def _resolve_assignee_email(self) -> Optional[str]:
        """
        Resolve o email do assignee padrão:

        1. Usa o assignee configurado em config.json, se houver
        2. Caso contrário, tenta obter o usuário atual via ACLI ou .jira-config.yml
        """
        if not self._config:
            return None

        # Primeiro tenta assignee configurado
        assignee = self._config.get_assignee()
        if assignee and assignee.strip():
            return assignee.strip()

        # Fallback: usuário atual do jira-cli
        if self._jira_client:
            return self._jira_client.get_current_user()

        return None

    # ------------------------------------------------------------------
    # Slots expostos ao QML
    # ------------------------------------------------------------------

    @Slot()
    @Slot(str)
    def refreshIssues(self, query: str = "") -> None:
        """
        Atualiza a lista de issues do usuário atual de forma assíncrona.
        
        Args:
            query: Texto opcional para buscar por summary ou key. Se vazio, busca todas as issues.
        """
        if not self._jira_client:
            self.errorOccurred.emit("ACLI não inicializado para MyIssuesModel")
            return

        assignee_email = self._resolve_assignee_email()
        if not assignee_email:
            self.errorOccurred.emit(
                "Não foi possível determinar o usuário (assignee). "
                "Configure o assignee em config.json ou o login no .jira-config.yml."
            )
            return

        # Cancelar worker anterior se existir
        if self._search_worker and self._search_worker.isRunning():
            self._search_worker.terminate()
            self._search_worker.wait()

        # Criar novo worker para busca assíncrona
        self._search_worker = SearchWorker(
            jira_client=self._jira_client,
            config=self._config,
            assignee_email=assignee_email,
            query=query if query else "",
        )

        # Conectar signals do worker
        self._search_worker.issuesFound.connect(self._on_issues_found)
        self._search_worker.errorOccurred.connect(self._on_search_error)
        self._search_worker.finished.connect(self._on_search_finished)

        # Iniciar busca
        self._set_loading(True)
        self._search_worker.start()

    def _on_issues_found(self, issues: List[Dict[str, Any]]) -> None:
        """Callback quando issues são encontradas"""
        self._set_issues(issues)

    def _on_search_error(self, error_message: str) -> None:
        """Callback quando ocorre erro na busca"""
        self.errorOccurred.emit(error_message)

    def _on_search_finished(self) -> None:
        """Callback quando busca termina"""
        self._set_loading(False)
        if self._search_worker:
            self._search_worker.deleteLater()
            self._search_worker = None

    @Slot(str, result="QVariant")
    def getIssue(self, key: str) -> Dict[str, Any]:
        """
        Retorna uma issue específica da lista pelo key.

        Args:
            key: Chave da issue (ex: PLATFORM-123).
        """
        for issue in self._issues:
            if issue.get("key") == key:
                return issue
        return {}

