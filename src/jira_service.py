"""
Serviço Jira - Expõe métodos para criação de issues via QML
Usa QThread para operações assíncronas e signals para comunicação
"""

from pathlib import Path
import sys
from datetime import datetime
from typing import Any, Dict, List, Optional

from PySide6.QtCore import QObject, Signal, Slot, QThread  # type: ignore[import]

# Adicionar diretório raiz ao path
ROOT_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT_DIR))

from core.jira_client import JiraClient
from core.status_transition import transition_sequentially, WorklogConfig
from config.config_manager import ConfigManager


class JiraWorker(QThread):
    """Worker thread para operações Jira assíncronas"""

    # Signals para comunicação com a thread principal
    progressUpdated = Signal(int, str)  # percentage, message
    issueCreated = Signal(str, str)  # issue_key, issue_url
    errorOccurred = Signal(str)  # error_message
    finished = Signal()

    def __init__(
        self,
        jira_client: JiraClient,
        config: ConfigManager,
        summary: str,
        description: str,
        tipo_atividade: str,
        target_status: str,
        doc_anexa: str,
        uso_ia: str,
        registrar_worklog: bool = False,
        worklog_inicio: Optional[datetime] = None,
        worklog_duracao: int = 0,
        worklog_timezone: str = "UTC",
        parent_epic_key: str = "",
        worklog_comment: str = "",
        parent=None,
    ):
        super().__init__(parent)
        self.jira_client = jira_client
        self.config = config
        self.summary = summary
        self.description = description
        self.tipo_atividade = tipo_atividade
        self.target_status = target_status
        self.doc_anexa = doc_anexa
        self.uso_ia = uso_ia
        self.registrar_worklog = registrar_worklog
        self.worklog_inicio = worklog_inicio
        self.worklog_duracao = worklog_duracao
        self.worklog_timezone = worklog_timezone
        self.parent_epic_key = parent_epic_key.strip() if parent_epic_key else ""
        self.worklog_comment = worklog_comment or ""

    def run(self):
        """Executa a criação da issue e transições em thread separada"""
        try:
            # Progresso: Criando issue (0-50%)
            self.progressUpdated.emit(10, "Criando issue no Jira...")

            # Criar issue com TODOS os campos customizados de uma vez
            # Isso garante que os campos estejam preenchidos desde o início
            custom_fields = {
                self.config.get_custom_field("tipo_atividade"): self.tipo_atividade
            }

            # Adicionar documentação anexa e utilização de IA na criação
            # IMPORTANTE: Sempre adicionar, mesmo que seja "Não", pois são campos obrigatórios
            doc_anexa_alias = self.config.get_custom_field("documentacao_anexa")
            uso_ia_alias = self.config.get_custom_field("utilizacao_ia")

            if doc_anexa_alias:
                custom_fields[doc_anexa_alias] = (
                    self.doc_anexa if self.doc_anexa else "Não"
                )
            if uso_ia_alias:
                custom_fields[uso_ia_alias] = self.uso_ia if self.uso_ia else "Não"

            # Obter assignee: usar do config ou inferir do usuário atual do jira-cli
            assignee = self.config.get_assignee()
            if not assignee:
                # Tentar obter do usuário atual do jira-cli
                assignee = self.jira_client.get_current_user()
                # Se não conseguir obter, assignee será None e a issue será criada sem assignee

            result = self.jira_client.create_issue(
                project=self.config.get_project(),
                issue_type=self.config.get_issue_type(),
                summary=self.summary,
                description=self.description,
                assignee=assignee,
                custom_fields=custom_fields,
                parent_issue_key=self.parent_epic_key or None,
            )

            issue_key = result["issue_key"]
            issue_url = result["issue_url"]
            self.progressUpdated.emit(50, "Issue criada com sucesso!")

            # Os campos customizados já foram passados na criação da issue
            # Não precisamos atualizá-los novamente

            # Transicionar status se necessário
            if self.target_status != "TO DO":
                self.progressUpdated.emit(60, "Iniciando transições de status...")

                # Callback para progresso de transições
                def progress_callback(status, percentage, message):
                    # Converter porcentagem de transição (0-100) para range 60-100
                    # Assumindo que transições ocupam 40% do progresso total (60-100)
                    transition_progress = 60 + int((percentage * 40) / 100)
                    self.progressUpdated.emit(transition_progress, message)

                # Criar configuração de worklog se necessário
                worklog_config = None
                if self.registrar_worklog:
                    worklog_config = WorklogConfig(
                        registrar=self.registrar_worklog,
                        inicio=self.worklog_inicio,
                        duracao=self.worklog_duracao,
                        timezone=self.worklog_timezone,
                        comment=self.worklog_comment or None,
                    )

                # Transicionar sequencialmente

                # Transicionar sequencialmente
                transition_sequentially(
                    jira_client=self.jira_client,
                    issue_key=issue_key,
                    target_status=self.target_status,
                    status_sequence=self.config.get_status_sequence(),
                    progress_callback=progress_callback,
                    worklog=worklog_config,
                )

            self.progressUpdated.emit(100, "Concluído!")

            # Emitir sucesso
            self.issueCreated.emit(issue_key, issue_url)

        except Exception as e:
            error_msg = str(e)
            self.errorOccurred.emit(error_msg)
        finally:
            self.finished.emit()


class UpdateWorker(QThread):
    """Worker thread para atualização de issues Jira assíncronas"""

    # Signals para comunicação com a thread principal
    progressUpdated = Signal(int, str)  # percentage, message
    issueUpdated = Signal(str)  # issue_key
    errorOccurred = Signal(str)  # error_message
    finished = Signal()

    def __init__(
        self,
        jira_client: JiraClient,
        config: ConfigManager,
        issue_key: str,
        summary: Optional[str] = None,
        description: Optional[str] = None,
        tipo_atividade: Optional[str] = None,
        status: Optional[str] = None,
        doc_anexa: Optional[str] = None,
        uso_ia: Optional[str] = None,
        parent_epic_key: Optional[str] = None,
        registrar_worklog: bool = False,
        worklog_inicio: Optional[datetime] = None,
        worklog_duracao: int = 0,
        worklog_timezone: str = "UTC",
        worklog_comment: Optional[str] = None,
        parent=None,
    ):
        super().__init__(parent)
        self.jira_client = jira_client
        self.config = config
        self.issue_key = issue_key
        self.summary = summary
        self.description = description
        self.tipo_atividade = tipo_atividade
        self.status = status
        self.doc_anexa = doc_anexa
        self.uso_ia = uso_ia
        self.parent_epic_key = parent_epic_key.strip() if parent_epic_key else None
        self.registrar_worklog = registrar_worklog
        self.worklog_inicio = worklog_inicio
        self.worklog_duracao = worklog_duracao
        self.worklog_timezone = worklog_timezone
        self.worklog_comment = worklog_comment

    def run(self):
        """Executa a atualização da issue e worklog opcional em thread separada"""
        try:
            self.progressUpdated.emit(10, "Atualizando issue no Jira...")

            # Preparar campos customizados
            custom_fields = {}
            if self.tipo_atividade:
                tipo_atividade_alias = self.config.get_custom_field("tipo_atividade")
                if tipo_atividade_alias:
                    custom_fields[tipo_atividade_alias] = self.tipo_atividade

            if self.doc_anexa:
                doc_anexa_alias = self.config.get_custom_field("documentacao_anexa")
                if doc_anexa_alias:
                    custom_fields[doc_anexa_alias] = self.doc_anexa

            if self.uso_ia:
                uso_ia_alias = self.config.get_custom_field("utilizacao_ia")
                if uso_ia_alias:
                    custom_fields[uso_ia_alias] = self.uso_ia

            # Atualizar campos da issue (sem status)
            success = self.jira_client.update_issue(
                issue_key=self.issue_key,
                summary=self.summary,
                description=self.description,
                status=None,  # Não atualizar status aqui, vamos usar transição sequencial
                custom_fields=custom_fields if custom_fields else None,
                parent_issue_key=self.parent_epic_key,
            )

            if not success:
                self.errorOccurred.emit(f"Erro ao atualizar issue {self.issue_key}")
                return

            self.progressUpdated.emit(50, "Issue atualizada com sucesso!")

            # Transicionar status sequencialmente se fornecido
            if self.status and self.status.strip():
                from core.status_transition import transition_sequentially, WorklogConfig
                
                self.progressUpdated.emit(60, "Iniciando transições de status...")
                
                # Callback para progresso de transições
                def progress_callback(status, percentage, message):
                    # Converter porcentagem de transição (0-100) para range 60-100
                    transition_progress = 60 + int((percentage * 40) / 100)
                    self.progressUpdated.emit(transition_progress, message)
                
                # Criar configuração de worklog se necessário
                worklog_config = None
                if self.registrar_worklog:
                    worklog_config = WorklogConfig(
                        registrar=self.registrar_worklog,
                        inicio=self.worklog_inicio,
                        duracao=self.worklog_duracao,
                        timezone=self.worklog_timezone,
                        comment=self.worklog_comment or None,
                    )
                
                # Transicionar sequencialmente
                transition_sequentially(
                    jira_client=self.jira_client,
                    issue_key=self.issue_key,
                    target_status=self.status.strip(),
                    status_sequence=self.config.get_status_sequence(),
                    progress_callback=progress_callback,
                    worklog=worklog_config,
                )
                
                self.progressUpdated.emit(100, "Transições concluídas!")
            else:
                # Se não houver transição de status, registrar worklog separadamente se solicitado
                if self.registrar_worklog and self.worklog_inicio:
                    self.progressUpdated.emit(60, "Registrando worklog...")

                    time_spent = self.jira_client._format_duration_minutes(self.worklog_duracao)
                    started_str = self.worklog_inicio.strftime("%Y-%m-%d %H:%M:%S")

                    success = self.jira_client.register_worklog(
                        issue_key=self.issue_key,
                        time_spent=time_spent,
                        started=started_str,
                        timezone=self.worklog_timezone,
                        comment=self.worklog_comment,
                    )

                    if not success:
                        self.errorOccurred.emit(f"Erro ao registrar worklog para {self.issue_key}")
                        return

                    self.progressUpdated.emit(90, "Worklog registrado com sucesso!")

            self.progressUpdated.emit(100, "Concluído!")
            self.issueUpdated.emit(self.issue_key)

        except Exception as e:
            error_msg = str(e)
            self.errorOccurred.emit(error_msg)
        finally:
            self.finished.emit()


class JiraService(QObject):
    """Serviço para criação de issues Jira via QML"""

    # Signals para comunicação com QML
    progressUpdated = Signal(int, str)  # percentage, message
    issueCreated = Signal(str, str)  # issue_key, issue_url
    issueUpdated = Signal(str)  # issue_key
    errorOccurred = Signal(str)  # error_message
    # Signals específicos para busca de Epics (modo assíncrono)
    epicSearchStarted = Signal()
    epicSearchCompleted = Signal("QVariant", str)  # lista de epics (list[dict], nextPageToken)
    epicSearchPageCompleted = Signal("QVariant", str)  # lista de epics para paginação incremental (list[dict], nextPageToken)
    # Signals específicos para carregamento de detalhes de issue (modo assíncrono)
    issueDetailsStarted = Signal(str)  # issueKey
    issueDetailsLoaded = Signal("QVariant")  # dict com detalhes da issue

    def __init__(self, parent=None):
        super().__init__(parent)

        # Carregar configuração
        try:
            self._config = ConfigManager()
        except Exception as e:
            print(f"Erro ao carregar configuração: {e}", file=sys.stderr)
            self._config = None

        # Inicializar cliente Jira com config do .jira-config.yml se disponível
        try:
            jira_cli_config_path = None
            account_id = None
            if self._config:
                jira_cli_config_path = self._config.get_jira_cli_config_path()
                account_id = self._config.get_account_id()
            self._jira_client = JiraClient(jira_cli_config_path=jira_cli_config_path, account_id=account_id)
        except RuntimeError as e:
            print(f"Erro ao inicializar cliente Jira: {e}", file=sys.stderr)
            self._jira_client = None

        self._worker: Optional[JiraWorker] = None
        self._update_worker: Optional[UpdateWorker] = None
        self._epic_search_worker: Optional[QThread] = None
        self._issue_details_worker: Optional[QThread] = None

    @Slot(str, str, str, str, str, str, bool, str, int, str, str, str, result=bool)
    def createIssue(  # NOSONAR - camelCase necessário para compatibilidade com QML
        self,
        summary: str,
        description: str,
        tipoAtividade: str,  # NOSONAR
        statusInicial: str,  # NOSONAR
        documentacaoAnexa: str,  # NOSONAR
        utilizacaoIA: str,  # NOSONAR
        registrarWorklog: bool,  # NOSONAR
        worklogInicio: str,  # NOSONAR
        worklogDuracao: int,  # NOSONAR
        worklogTimezone: str,  # NOSONAR
        parentEpicKey: str,  # NOSONAR - pode ser vazio
        worklogComment: str = "",  # NOSONAR - comentário opcional do worklog
    ) -> bool:
        """
        Cria uma issue no Jira de forma assíncrona

        Args:
            summary: Resumo da issue
            description: Descrição da issue
            tipoAtividade: Tipo de atividade
            statusInicial: Status inicial desejado
            documentacaoAnexa: Documentação anexa (Sim/Não)
            utilizacaoIA: Utilização de IA (Sim/Não)
            registrarWorklog: Se True, registra worklog após transição para IN DEVELOPMENT
            worklogInicio: Data/hora de início do worklog (formato "YYYY-MM-DD HH:MM:SS")
            worklogDuracao: Duração do worklog em minutos
            worklogTimezone: Timezone para o worklog (ex: "America/Sao_Paulo")

        Returns:
            True se iniciado com sucesso, False caso contrário
        """
        # Validar campos obrigatórios
        if not summary.strip():
            self.errorOccurred.emit("Summary é obrigatório")
            return False

        # Description não é obrigatório

        if not self._jira_client:
            self.errorOccurred.emit("Cliente Jira não inicializado")
            return False

        if not self._config:
            self.errorOccurred.emit("Configuração não carregada")
            return False

        # Cancelar worker anterior se existir
        if self._worker and self._worker.isRunning():
            self._worker.terminate()
            self._worker.wait()

        # Converter worklogInicio de string para datetime se fornecido
        worklog_inicio_dt = None
        if registrarWorklog and worklogInicio:
            try:
                worklog_inicio_dt = datetime.strptime(
                    worklogInicio.strip(), "%Y-%m-%d %H:%M:%S"
                )
            except (ValueError, AttributeError):
                self.errorOccurred.emit(
                    f"Formato de data/hora inválido: {worklogInicio}"
                )
                return False

        # Sempre usar timezone do config.json (não aceitar da UI)
        worklogTimezone = self._config.get_timezone() if self._config else "America/Sao_Paulo"

        # Criar novo worker
        self._worker = JiraWorker(
            jira_client=self._jira_client,
            config=self._config,
            summary=summary.strip(),
            description=description.strip() if description else "",
            tipo_atividade=tipoAtividade,
            target_status=statusInicial,
            doc_anexa=documentacaoAnexa,
            uso_ia=utilizacaoIA,
            registrar_worklog=registrarWorklog,
            worklog_inicio=worklog_inicio_dt,
            worklog_duracao=worklogDuracao,
            worklog_timezone=worklogTimezone,
            parent_epic_key=parentEpicKey,
            # Para criação via transições, usamos o comentário do worklog
            # apenas se registrarWorklog estiver ativo.
            worklog_comment=worklogComment.strip() if worklogComment else "",
        )

        # Conectar signals do worker
        self._worker.progressUpdated.connect(self.progressUpdated.emit)
        self._worker.issueCreated.connect(self.issueCreated.emit)
        self._worker.errorOccurred.connect(self.errorOccurred.emit)

        # Iniciar worker
        self._worker.start()

        return True

    @Slot(result=bool)
    def isAvailable(self) -> bool:
        """Verifica se o serviço está disponível"""
        return self._jira_client is not None and self._config is not None

    @Slot(result=str)
    def getErrorMessage(self) -> str:
        """Retorna mensagem de erro se houver"""
        if not self._jira_client:
            return (
                "acli (Atlassian CLI) não encontrado. Instale com:\n"
                "  sudo apt install acli\n\n"
                "Após instalar, configure o token e autentique-se:\n"
                "  export JIRA_API_TOKEN=<seu-token>\n"
                "  echo $JIRA_API_TOKEN | acli jira auth login --site \"<seu-site>\" --email \"<seu-email>\" --token"
            )
        if not self._config:
            return "Erro ao carregar configuração"
        return ""

    @Slot(result=str)
    def getTimezone(self) -> str:
        """Retorna o timezone configurado para worklog"""
        if self._config:
            return self._config.get_timezone()
        return "America/Sao_Paulo"

    # ------------------------------------------------------------------
    # Slots auxiliares para buscas e worklog em issues existentes
    # ------------------------------------------------------------------

    @Slot(str, result=list)
    def searchEpics(self, query: str) -> List[Dict[str, str]]:
        """
        Busca epics do projeto configurado de forma síncrona.

        Mantido para compatibilidade e uso em testes/CLI simples.
        Para uso em QML com feedback visual, prefira searchEpicsAsync.
        """
        if not self._jira_client or not self._config:
            self.errorOccurred.emit("Serviço Jira não está disponível")
            return []

        project_key = self._config.get_project()
        raw_epics = self._jira_client.search_epics(
            project=project_key, query=query, max_results=50
        )

        epics: List[Dict[str, str]] = []
        for issue in raw_epics:
            key = issue.get("key", "")
            fields = issue.get("fields") or {}
            summary = fields.get("summary", "")
            status = (fields.get("status") or {}).get("name", "")

            if not key:
                continue

            epics.append(
                {
                    "key": key,
                    "summary": summary,
                    "status": status,
                }
            )

        return epics

    @Slot(str, bool, bool, bool, bool, str, result=bool)
    def searchEpicsAsync(
        self,
        query: str = "",
        created_by_me: bool = False,
        assigned_to_me: bool = False,
        project_platform: bool = True,
        exclude_done: bool = True,
        next_page_token: str = "",
    ) -> bool:
        """
        Inicia busca de Epics em thread separada, emitindo sinais para QML.

        Args:
            query: Texto para buscar (key ou summary).
            created_by_me: Filtrar apenas epics criados por mim.
            assigned_to_me: Filtrar apenas epics atribuídos a mim.
            project_platform: Filtrar por projeto PLATFORM.
            exclude_done: Se True, exclui epics com status DONE.
            next_page_token: Token para buscar próxima página (paginação).

        Returns:
            True se a busca foi iniciada, False caso contrário.
        """
        if not self._jira_client or not self._config:
            self.errorOccurred.emit("Serviço Jira não está disponível")
            self.epicSearchCompleted.emit([], "")
            return False

        # Cancelar busca anterior se ainda estiver rodando (apenas se não for paginação)
        if not next_page_token and self._epic_search_worker and self._epic_search_worker.isRunning():
            self._epic_search_worker.terminate()
            self._epic_search_worker.wait()

        # Worker simples inline para não poluir o namespace público
        class _EpicSearchWorker(QThread):
            resultsReady = Signal("QVariant", str)  # Para busca normal: (results, nextPageToken)
            pageReady = Signal("QVariant", str)  # Para paginação incremental: (results, nextPageToken)
            errorOccurred = Signal(str)
            is_pagination: bool = False

            def __init__(
                self,
                jira_client: JiraClient,
                project: str,
                query_text: str,
                created_by_me_flag: bool,
                assigned_to_me_flag: bool,
                project_filter: Optional[str],
                exclude_done_flag: bool,
                next_token: Optional[str],
                is_pag: bool,
            ):
                super().__init__()
                self._jira_client = jira_client
                self._project = project
                self._query = query_text
                self._created_by_me = created_by_me_flag
                self._assigned_to_me = assigned_to_me_flag
                self._project_filter = project_filter
                self._exclude_done = exclude_done_flag
                self._next_token = next_token
                self.is_pagination = is_pag

            def run(self) -> None:
                try:
                    raw_epics, next_page = self._jira_client.search_epics(
                        project=self._project,
                        query=self._query,
                        max_results=50,
                        created_by_me=self._created_by_me,
                        assigned_to_me=self._assigned_to_me,
                        project_filter=self._project_filter,
                        exclude_done=self._exclude_done,
                        next_page_token=self._next_token,
                    )

                    epics: List[Dict[str, str]] = []
                    for issue in raw_epics:
                        key = issue.get("key", "")
                        fields = issue.get("fields") or {}
                        summary = fields.get("summary", "")
                        status = (fields.get("status") or {}).get("name", "")

                        if not key:
                            continue

                        epics.append(
                            {
                                "key": key,
                                "summary": summary,
                                "status": status,
                            }
                        )

                    # Sempre incluir nextPageToken nos resultados
                    next_token_str = next_page if next_page else ""
                    
                    # Se for paginação, usar signal diferente
                    if self.is_pagination:
                        self.pageReady.emit(epics, next_token_str)
                    else:
                        self.resultsReady.emit(epics, next_token_str)
                except Exception as e:  # pragma: no cover - falhas inesperadas
                    self.errorOccurred.emit(str(e))
                    if self.is_pagination:
                        self.pageReady.emit([], "")
                    else:
                        self.resultsReady.emit([], "")

        project_key = self._config.get_project()
        project_filter = "PLATFORM" if project_platform else None
        is_pagination = bool(next_page_token)
        
        worker = _EpicSearchWorker(
            self._jira_client,
            project_key,
            query,
            created_by_me,
            assigned_to_me,
            project_filter,
            exclude_done,
            next_page_token if next_page_token else None,
            is_pagination,
        )
        self._epic_search_worker = worker

        # Propagar resultados/erros para QML
        if is_pagination:
            worker.pageReady.connect(self.epicSearchPageCompleted.emit)
        else:
            worker.resultsReady.connect(self.epicSearchCompleted.emit)
        worker.errorOccurred.connect(self.errorOccurred.emit)

        # Limpar referência quando terminar
        def _cleanup() -> None:
            if self._epic_search_worker is worker:
                self._epic_search_worker = None

        worker.finished.connect(_cleanup)

        # Iniciar busca
        # Para paginação, não emitir epicSearchStarted (para não mostrar loading na busca inicial)
        # Mas ainda precisamos indicar que está carregando mais
        if not is_pagination:
            self.epicSearchStarted.emit()
        worker.start()
        return True

    @Slot(str, result="QVariant")
    def searchEpicByKey(self, epic_key: str) -> Dict[str, str]:
        """
        Busca um epic específico por key exata.
        Usado na segunda aba para buscar o parent epic de uma issue.

        Args:
            epic_key: Chave do epic (ex: PLATFORM-123).

        Returns:
            Dict com key, summary e status do epic, ou dict vazio se não encontrado.
        """
        if not self._jira_client or not self._config:
            return {}

        try:
            # Buscar epic por key exata
            raw_epics, _ = self._jira_client.search_epics(
                project=self._config.get_project(),
                query=epic_key,
                max_results=1,
                created_by_me=False,
                assigned_to_me=False,
                project_filter=None,
                exclude_done=False,  # Não excluir DONE ao buscar epic exato por key
                next_page_token=None,
            )

            if raw_epics and len(raw_epics) > 0:
                issue = raw_epics[0]
                key = issue.get("key", "")
                fields = issue.get("fields") or {}
                summary = fields.get("summary", "")
                status = (fields.get("status") or {}).get("name", "")

                if key:
                    return {
                        "key": key,
                        "summary": summary,
                        "status": status,
                    }
        except Exception as e:
            print(f"Erro ao buscar epic por key {epic_key}: {e}", file=sys.stderr)

        return {}

    @Slot(result="QVariant")
    def getEpicFilters(self) -> Dict[str, bool]:
        """
        Retorna os filtros de busca de épicos salvos na configuração.
        
        Returns:
            Dict com os filtros: created_by_me, assigned_to_me, project_platform, exclude_done
        """
        if not self._config:
            return {
                "created_by_me": False,
                "assigned_to_me": False,
                "project_platform": True,
            }
        return self._config.get_epic_filters()

    @Slot(bool, bool, bool, bool, result=bool)
    def setEpicFilters(
        self, created_by_me: bool, assigned_to_me: bool, project_platform: bool, exclude_done: bool
    ) -> bool:
        """
        Salva os filtros de busca de épicos no arquivo de configuração.
        
        Args:
            created_by_me: Filtrar apenas epics criados por mim.
            assigned_to_me: Filtrar apenas epics atribuídos a mim.
            project_platform: Filtrar por projeto PLATFORM.
            exclude_done: Excluir epics com status DONE.
        
        Returns:
            True se salvou com sucesso, False caso contrário.
        """
        if not self._config:
            return False
        
        try:
            filters = {
                "created_by_me": created_by_me,
                "assigned_to_me": assigned_to_me,
                "project_platform": project_platform,
                "exclude_done": exclude_done,
            }
            self._config.set_epic_filters(filters)
            return True
        except Exception as e:
            print(f"Erro ao salvar filtros de épicos: {e}", file=sys.stderr)
            return False

    @Slot(result=list)
    def getMyIssues(self) -> List[Dict[str, str]]:
        """
        Retorna lista simplificada de issues atribuídas ao usuário atual.

        Esta é uma alternativa direta ao MyIssuesModel para cenários onde
        apenas uma chamada síncrona for suficiente.
        """
        if not self._jira_client or not self._config:
            self.errorOccurred.emit("Serviço Jira não está disponível")
            return []

        assignee = self._config.get_assignee() or self._jira_client.get_current_user()
        if not assignee:
            self.errorOccurred.emit(
                "Não foi possível determinar o usuário (assignee) para buscar issues"
            )
            return []

        raw_issues = self._jira_client.get_my_issues(
            assignee_email=assignee,
            max_results=100,
            extra_jql="AND statusCategory != Done",
        )

        issues: List[Dict[str, str]] = []
        for issue in raw_issues:
            key = issue.get("key", "")
            fields = issue.get("fields") or {}
            summary = fields.get("summary", "")
            status = (fields.get("status") or {}).get("name", "")
            issue_type = (fields.get("issuetype") or {}).get("name", "")

            if not key:
                continue

            issues.append(
                {
                    "key": key,
                    "summary": summary,
                    "status": status,
                    "issueType": issue_type,
                }
            )

        return issues

    @Slot(str, int, str, str, str, result=bool)
    def registerWorklogToIssue(  # NOSONAR - camelCase para QML
        self,
        issueKey: str,
        worklogDuracao: int,
        worklogInicio: str,
        worklogTimezone: str,
        comment: str,
    ) -> bool:
        """
        Registra worklog em uma issue existente.

        Args:
            issueKey: Chave da issue (ex: PLATFORM-123)
            worklogDuracao: Duração em minutos
            worklogInicio: Data/hora de início (\"YYYY-MM-DD HH:MM:SS\")
            worklogTimezone: Timezone (ex: \"America/Sao_Paulo\")
            comment: Comentário opcional
        """
        if not self._jira_client:
            self.errorOccurred.emit("Cliente Jira não inicializado")
            return False

        # Converter worklogInicio de string para datetime para validar formato
        try:
            datetime.strptime(worklogInicio.strip(), "%Y-%m-%d %H:%M:%S")
        except (ValueError, AttributeError):
            self.errorOccurred.emit(f"Formato de data/hora inválido: {worklogInicio}")
            return False

        # Sempre usar timezone do config.json (não aceitar da UI)
        worklogTimezone = self._config.get_timezone() if self._config else "America/Sao_Paulo"

        # Converter duração em minutos para formato do jira-cli
        time_spent = self._jira_client._format_duration_minutes(worklogDuracao)

        success = self._jira_client.register_worklog(
            issue_key=issueKey.strip(),
            time_spent=time_spent,
            started=worklogInicio.strip(),
            timezone=worklogTimezone,
            comment=comment.strip() if comment else None,
        )

        if not success:
            self.errorOccurred.emit(f"Não foi possível registrar worklog para {issueKey}")

        return success

    @Slot(str, result="QVariant")
    def getIssueDetails(self, issueKey: str) -> Dict[str, Any]:  # NOSONAR
        """
        Busca dados completos de uma issue específica.

        Args:
            issueKey: Chave da issue (ex: PLATFORM-123)

        Returns:
            Dict com dados da issue ou dict vazio se não encontrada
        """
        if not self._jira_client:
            self.errorOccurred.emit("Cliente Jira não inicializado")
            return {}

        if not issueKey or not issueKey.strip():
            return {}

        issue_data = self._jira_client.get_issue_details(issueKey.strip())
        if not issue_data:
            return {}

        return self._build_issue_details_dict(issue_data)

    @Slot(str, str, str, str, str, str, str, str, bool, str, int, str, str, result=bool)
    def updateIssue(  # NOSONAR - camelCase necessário para compatibilidade com QML
        self,
        issueKey: str,  # NOSONAR
        summary: str,
        description: str,
        tipoAtividade: str,  # NOSONAR
        status: str,
        documentacaoAnexa: str,  # NOSONAR
        utilizacaoIA: str,  # NOSONAR
        parentEpicKey: str,  # NOSONAR
        registrarWorklog: bool,  # NOSONAR
        worklogInicio: str,  # NOSONAR
        worklogDuracao: int,  # NOSONAR
        worklogTimezone: str,  # NOSONAR
        worklogComment: str,  # NOSONAR
    ) -> bool:
        """
        Atualiza uma issue existente no Jira de forma assíncrona.

        Args:
            issueKey: Chave da issue (ex: PLATFORM-123)
            summary: Novo summary (opcional, pode ser vazio para não atualizar)
            description: Nova description (opcional, pode ser vazio para não atualizar)
            tipoAtividade: Novo tipo de atividade (opcional, pode ser vazio)
            status: Novo status (opcional, pode ser vazio para não atualizar)
            documentacaoAnexa: Nova documentação anexa (Sim/Não) (opcional)
            utilizacaoIA: Nova utilização de IA (Sim/Não) (opcional)
            parentEpicKey: Nova chave do parent Epic (opcional, pode ser vazio)
            registrarWorklog: Se True, registra worklog após atualização
            worklogInicio: Data/hora de início do worklog (formato "YYYY-MM-DD HH:MM:SS")
            worklogDuracao: Duração do worklog em minutos
            worklogTimezone: Timezone para o worklog (ex: "America/Sao_Paulo")
            worklogComment: Comentário do worklog (opcional)

        Returns:
            True se iniciado com sucesso, False caso contrário
        """
        if not self._jira_client:
            self.errorOccurred.emit("Cliente Jira não inicializado")
            return False

        if not self._config:
            self.errorOccurred.emit("Configuração não carregada")
            return False

        if not issueKey or not issueKey.strip():
            self.errorOccurred.emit("Issue key é obrigatório")
            return False

        # Cancelar worker anterior se existir
        if self._update_worker and self._update_worker.isRunning():
            self._update_worker.terminate()
            self._update_worker.wait()

        # Converter worklogInicio de string para datetime se fornecido
        worklog_inicio_dt = None
        if registrarWorklog and worklogInicio:
            try:
                worklog_inicio_dt = datetime.strptime(
                    worklogInicio.strip(), "%Y-%m-%d %H:%M:%S"
                )
            except (ValueError, AttributeError):
                self.errorOccurred.emit(
                    f"Formato de data/hora inválido: {worklogInicio}"
                )
                return False

        # Sempre usar timezone do config.json (não aceitar da UI)
        worklogTimezone = self._config.get_timezone() if self._config else "America/Sao_Paulo"

        # Criar novo worker de atualização
        self._update_worker = UpdateWorker(
            jira_client=self._jira_client,
            config=self._config,
            issue_key=issueKey.strip(),
            summary=summary.strip() if summary else None,
            description=description.strip() if description else None,
            tipo_atividade=tipoAtividade if tipoAtividade else None,
            status=status if status else None,
            doc_anexa=documentacaoAnexa if documentacaoAnexa else None,
            uso_ia=utilizacaoIA if utilizacaoIA else None,
            parent_epic_key=parentEpicKey.strip() if parentEpicKey else None,
            registrar_worklog=registrarWorklog,
            worklog_inicio=worklog_inicio_dt,
            worklog_duracao=worklogDuracao,
            worklog_timezone=worklogTimezone,
            worklog_comment=worklogComment.strip() if worklogComment else None,
        )

        # Conectar signals do worker
        self._update_worker.progressUpdated.connect(self.progressUpdated.emit)
        self._update_worker.issueUpdated.connect(self.issueUpdated.emit)
        self._update_worker.errorOccurred.connect(self.errorOccurred.emit)

        # Iniciar worker
        self._update_worker.start()

        return True

    # ------------------------------------------------------------------
    # Helpers internos
    # ------------------------------------------------------------------

    def _build_issue_details_dict(self, issue_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Constrói o dicionário de detalhes de issue no formato esperado pelo QML.
        Reutilizado tanto pelo caminho síncrono quanto pelo assíncrono.
        
        A REST API retorna dados em data["fields"], mas get_issue_details já expande
        os campos no topo do dicionário para compatibilidade.
        """
        # REST API retorna campos em data["fields"], mas get_issue_details já expande
        # Se ainda tiver "fields" aninhado, usar ele; senão, usar os campos no topo
        if "fields" in issue_data and isinstance(issue_data["fields"], dict):
            # Estrutura com fields aninhado (compatibilidade)
            fields = issue_data["fields"]
        else:
            # Estrutura com campos no topo (REST API após expansão)
            fields = issue_data
        
        parent = fields.get("parent")
        parent_key = ""
        parent_summary = ""
        if parent:
            # REST API retorna parent como dict com key e fields aninhado
            if isinstance(parent, dict):
                parent_key = parent.get("key", "")
                # Tentar obter summary de diferentes formas
                parent_fields = parent.get("fields", {})
                if parent_fields and isinstance(parent_fields, dict):
                    parent_summary = parent_fields.get("summary", "")
                else:
                    # Se não tiver fields aninhado, tentar summary direto
                    parent_summary = parent.get("summary", "")

        # Extrair valores de campos customizados
        tipo_atividade = ""
        documentacao_anexa = ""
        utilizacao_ia = ""

        CUSTOM_FIELD_IDS = {
            "tipo_atividade": "customfield_12088",
            "documentacao_anexa": "customfield_14840",
            "utilizacao_ia": "customfield_14841",
        }

        def extract_custom_field_by_id(field_id: str) -> str:
            if not field_id or field_id not in fields:
                return ""

            value = fields[field_id]
            if value is None:
                return ""

            if isinstance(value, dict):
                result = value.get("value", "")
                if not result:
                    result = value.get("name", "")
                return str(result) if result else ""

            result = str(value) if value else ""
            return result

        tipo_atividade = extract_custom_field_by_id(CUSTOM_FIELD_IDS["tipo_atividade"])
        documentacao_anexa = extract_custom_field_by_id(
            CUSTOM_FIELD_IDS["documentacao_anexa"]
        )
        utilizacao_ia = extract_custom_field_by_id(CUSTOM_FIELD_IDS["utilizacao_ia"])

        # Converter description para string se for objeto (ADF format)
        description = fields.get("description", "")
        if description is None:
            description = ""
        elif isinstance(description, dict):

            def extract_text_from_adf(adf_node):
                if isinstance(adf_node, dict):
                    text_parts = []
                    if "text" in adf_node:
                        text_parts.append(str(adf_node["text"]))
                    if "content" in adf_node:
                        if isinstance(adf_node["content"], list):
                            for item in adf_node["content"]:
                                text_parts.append(extract_text_from_adf(item))
                    return " ".join(text_parts)
                elif isinstance(adf_node, list):
                    text_parts = []
                    for item in adf_node:
                        text_parts.append(extract_text_from_adf(item))
                    return " ".join(text_parts)
                else:
                    return str(adf_node) if adf_node else ""

            description = extract_text_from_adf(description)
        else:
            description = str(description) if description else ""

        status_obj = fields.get("status")
        status_name = ""
        if status_obj:
            if isinstance(status_obj, dict):
                status_name = status_obj.get("name", "")
            else:
                status_name = str(status_obj)
        status_name = status_name.upper() if status_name else ""

        return {
            "key": issue_data.get("key", ""),
            "summary": fields.get("summary", ""),
            "description": description,
            "status": status_name,
            "tipoAtividade": tipo_atividade,
            "documentacaoAnexa": documentacao_anexa,
            "utilizacaoIA": utilizacao_ia,
            "parentKey": parent_key,
            "parentSummary": parent_summary,
        }

    @Slot(str)
    def getIssueDetailsAsync(self, issueKey: str) -> None:
        """
        Inicia o carregamento de detalhes da issue em thread separada.

        - Emite issueDetailsStarted(issueKey) imediatamente.
        - Emite issueDetailsLoaded(dict) ao concluir (ou {} em caso de erro).
        """
        if not self._jira_client:
            self.errorOccurred.emit("Cliente Jira não inicializado")
            self.issueDetailsLoaded.emit({})
            return

        if not issueKey or not issueKey.strip():
            self.issueDetailsLoaded.emit({})
            return

        # Cancelar worker anterior se ainda estiver rodando
        if self._issue_details_worker and self._issue_details_worker.isRunning():
            self._issue_details_worker.terminate()
            self._issue_details_worker.wait()

        class _IssueDetailsWorker(QThread):
            resultReady = Signal("QVariant")
            errorOccurred = Signal(str)

            def __init__(self, jira_client: JiraClient, key: str, parent=None):
                super().__init__(parent)
                self._jira_client = jira_client
                self._key = key

            def run(self) -> None:
                try:
                    issue_data = self._jira_client.get_issue_details(self._key.strip())
                    if not issue_data:
                        self.resultReady.emit({})
                        return
                    self.resultReady.emit(issue_data)
                except Exception as e:  # pragma: no cover - falhas inesperadas
                    self.errorOccurred.emit(str(e))
                    self.resultReady.emit({})

        worker = _IssueDetailsWorker(self._jira_client, issueKey)
        self._issue_details_worker = worker

        def _on_result_ready(issue_data_variant):
            if not issue_data_variant:
                self.issueDetailsLoaded.emit({})
                return
            # Reaproveitar lógica de construção do dicionário
            details = self._build_issue_details_dict(issue_data_variant)
            self.issueDetailsLoaded.emit(details)

        worker.resultReady.connect(_on_result_ready)
        worker.errorOccurred.connect(self.errorOccurred.emit)

        def _cleanup() -> None:
            if self._issue_details_worker is worker:
                self._issue_details_worker = None

        worker.finished.connect(_cleanup)

        # Notificar início e disparar thread
        self.issueDetailsStarted.emit(issueKey.strip())
        worker.start()

    @Slot(str, result=str)
    def getIssueUrl(self, issueKey: str) -> str:
        """
        Constrói a URL de uma issue/epic no Jira.
        
        Args:
            issueKey: Chave da issue/epic (ex: PLATFORM-123)
            
        Returns:
            URL completa da issue/epic no Jira
        """
        if not issueKey or not issueKey.strip():
            return ""
        
        # Obter server URL do jira_client
        if not self._jira_client:
            return ""
        
        # Tentar obter server URL do jira_client
        # O JiraClient tem _server_url que vem do .jira-config.yml
        try:
            # Usar reflexão para acessar _server_url (propriedade privada)
            server_url = getattr(self._jira_client, '_server_url', None)
            if server_url:
                return f"{server_url}/browse/{issueKey.strip()}"
        except Exception:
            pass
        
        # Fallback: tentar construir URL baseado na chave
        # Assumir formato padrão: https://<project>.atlassian.net
        if '-' in issueKey:
            project = issueKey.split('-')[0]
            return f"https://{project.lower()}.atlassian.net/browse/{issueKey.strip()}"
        
        return ""
