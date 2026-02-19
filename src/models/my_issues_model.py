"""
Modelo para lista de issues do usuário logado

Expõe uma lista simples de issues para uso em QML, obtida via Jira REST API v3.
"""

from pathlib import Path
import sys
from typing import Any, Dict, List, Optional

from PySide6.QtCore import QObject, Property, Signal, Slot, QThread  # type: ignore[import]

# Adicionar diretório raiz ao path
ROOT_DIR = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT_DIR))

from config.config_manager import ConfigManager
from core.jira_client import JiraClient

try:
    from src.utils.debug import debug_log
except ImportError:
    debug_log = lambda *a, **k: None


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
            extra_jql = "AND statusCategory != Done"
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
                priority_obj = fields.get("priority") or {}
                priority = (priority_obj.get("name") or "").strip()
                priority_id = str(priority_obj.get("id") or "")

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
                        "priority": priority,
                        "priorityId": priority_id,
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
        self._sort_by: str = "priority"  # "priority" | "status" | "key"

        # Carregar configuração
        try:
            self._config = ConfigManager()
        except Exception as e:  # pragma: no cover - log simples
            print(
                f"Erro ao carregar configuração em MyIssuesModel: {e}", file=sys.stderr
            )
            self._config = None

        # Inicializar JiraClient com o mesmo caminho de config do .jira-config.yml
        try:
            jira_cli_config_path: Optional[Path] = None
            account_id = None
            if self._config:
                jira_cli_config_path = self._config.get_jira_cli_config_path()
                account_id = self._config.get_account_id()
            self._jira_client = JiraClient(
                jira_cli_config_path=jira_cli_config_path, account_id=account_id
            )
        except RuntimeError as e:  # pragma: no cover - log simples
            # Não é erro crítico - é esperado na primeira inicialização sem config
            # Usar debug_log para não alarmar
            try:
                from src.utils.debug import debug_log

                debug_log(
                    "MyIssuesModel",
                    "__init__",
                    "JiraClient não inicializado: %s (normal se configuração ainda não foi feita)",
                    e,
                )
            except ImportError:
                # Se debug não estiver disponível, não fazer nada (silencioso)
                pass
            self._jira_client = None

    @Slot()
    def reloadConfiguration(self) -> None:
        """
        Recarrega configuração e recria JiraClient.
        Deve ser chamado após salvar configurações.
        """
        try:
            from src.utils.debug import debug_log

            debug_log(
                "MyIssuesModel", "reloadConfiguration", "Recarregando configuração..."
            )

            # Recarregar ConfigManager
            self._config = ConfigManager()

            # Recriar JiraClient com nova config
            jira_cli_config_path = None
            account_id = None
            if self._config:
                jira_cli_config_path = self._config.get_jira_cli_config_path()
                account_id = self._config.get_account_id()

            try:
                self._jira_client = JiraClient(
                    jira_cli_config_path=jira_cli_config_path, account_id=account_id
                )
                debug_log(
                    "MyIssuesModel",
                    "reloadConfiguration",
                    "JiraClient recriado com sucesso",
                )
            except RuntimeError as e:
                debug_log(
                    "MyIssuesModel",
                    "reloadConfiguration",
                    "JiraClient não pôde ser recriado: %s",
                    e,
                )
                self._jira_client = None
        except Exception as e:
            from src.utils.debug import debug_log

            debug_log(
                "MyIssuesModel", "reloadConfiguration", "Erro ao recarregar: %s", e
            )
            # Manter estado anterior em caso de erro

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
        2. Caso contrário, tenta obter o usuário atual via .jira-config.yml
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
            self.errorOccurred.emit(
                "JiraClient não inicializado. Configure a conexão na aba de Configurações."
            )
            return

        assignee_email = self._resolve_assignee_email()
        if not assignee_email:
            self.errorOccurred.emit(
                "Não foi possível determinar o usuário (assignee). "
                "Configure o assignee em config.json ou o login no .jira-config.yml."
            )
            return

        # Evitar terminar worker em execução (terminate() em thread ativa pode causar SIGABRT)
        if self._is_loading and self._search_worker and self._search_worker.isRunning():
            return

        # Cancelar worker anterior se existir (ex.: busca anterior já terminou mas callback ainda não)
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
        """Callback quando issues são encontradas. Ordena conforme sortBy atual."""
        debug_log(
            "MyIssuesModel",
            "_on_issues_found",
            "Recebidas %d issues",
            len(issues) if issues else 0,
        )
        if issues:
            first = issues[0]
            debug_log(
                "MyIssuesModel",
                "_on_issues_found",
                "Primeiro item keys=%s key=%s summary=%s status=%s priority=%s priorityId=%s",
                list(first.keys()) if isinstance(first, dict) else "?",
                first.get("key", "?") if isinstance(first, dict) else "?",
                (
                    (first.get("summary", "?") or "")[:40]
                    if isinstance(first, dict)
                    else "?"
                ),
                first.get("status", "?") if isinstance(first, dict) else "?",
                first.get("priority", "?") if isinstance(first, dict) else "?",
                first.get("priorityId", "?") if isinstance(first, dict) else "?",
            )
        sorted_issues = self._sort_issues(issues)
        self._set_issues(sorted_issues)
        debug_log("MyIssuesModel", "_on_issues_found", "issuesChanged emitido")

    def _sort_issues(self, issues: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Ordena issues conforme self._sort_by."""
        if self._sort_by == "status":
            return self._sort_by_status(issues)
        if self._sort_by == "key":
            return sorted(issues, key=lambda i: i.get("key", ""))
        return self._sort_by_priority(issues)

    def _sort_by_priority(self, issues: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Ordena por prioridade (Highest → Lowest), depois por key."""
        priority_order = {
            "Highest": 1,
            "High": 2,
            "Medium": 3,
            "Low": 4,
            "Lowest": 5,
        }

        def sort_key(issue: Dict[str, Any]) -> tuple:
            p = (issue.get("priority") or "Medium").strip()
            return (priority_order.get(p, 99), issue.get("key", ""))

        return sorted(issues, key=sort_key)

    def _sort_by_status(self, issues: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Ordena por status (To Do → Done), depois por prioridade."""
        status_order = {
            "TO DO": 1,
            "BACKLOG": 1,
            "WAITING DEVELOPMENT": 2,
            "IN DEVELOPMENT": 3,
            "IN PROGRESS": 3,
            "CODE REVIEW": 4,
            "IN REVIEW": 4,
            "WAITING FOR HOMOLOG": 5,
            "IN HOMOLOGATION": 6,
            "READY FOR DEPLOY": 7,
            "DONE": 8,
            "CLOSED": 8,
        }
        priority_order = {
            "Highest": 1,
            "High": 2,
            "Medium": 3,
            "Low": 4,
            "Lowest": 5,
        }

        def sort_key(issue: Dict[str, Any]) -> tuple:
            s = (issue.get("status") or "").strip().upper()
            p = (issue.get("priority") or "Medium").strip()
            return (
                status_order.get(s, 99),
                priority_order.get(p, 99),
                issue.get("key", ""),
            )

        return sorted(issues, key=sort_key)

    def _on_search_error(self, error_message: str) -> None:
        """Callback quando ocorre erro na busca"""
        self.errorOccurred.emit(error_message)

    def _on_search_finished(self) -> None:
        """Callback quando busca termina"""
        self._set_loading(False)
        if self._search_worker:
            self._search_worker.deleteLater()
            self._search_worker = None

    @Slot(str, str, str)
    @Slot(str, str, str, str, str)
    def updateIssueInList(
        self,
        issue_key: str,
        summary: str,
        status: str,
        priority: str = "",
        priority_id: str = "",
    ) -> None:
        """
        Atualiza uma issue na lista em memória pelo key.
        Usado após update bem-sucedido ou ao carregar detalhes.
        priority e priority_id são opcionais (para corrigir exibição quando a busca não retorna).
        """
        for i, issue in enumerate(self._issues):
            if issue.get("key") == issue_key:
                updates: Dict[str, Any] = {"summary": summary, "status": status}
                if priority:
                    updates["priority"] = priority
                if priority_id:
                    updates["priorityId"] = priority_id
                # Nova lista para forçar QML a detectar mudança (modelChanged) e re-sincronizar
                new_list = list(self._issues)
                new_list[i] = {**issue, **updates}
                self._issues = new_list
                self.issuesChanged.emit()
                return

    @Slot(str)
    def setSortBy(self, sort_by: str) -> None:
        """Define critério de ordenação e reordena a lista atual."""
        valid = ("priority", "status", "key")
        if sort_by not in valid:
            return
        if self._sort_by != sort_by:
            self._sort_by = sort_by
            sorted_issues = self._sort_issues(self._issues)
            self._set_issues(sorted_issues)

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
