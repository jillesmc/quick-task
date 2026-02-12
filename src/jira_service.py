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
from core.status_transition import (
    transition_sequentially,
    WorklogConfig,
    needs_two_phase_transition,
    requires_worklog_check_before_transition,
    _get_in_development_index,
    _get_status_index,
)
from config.config_manager import ConfigManager
from src.services.assets_cache import AssetsCacheService
from src.utils.field_utils import is_placeholder_custom_field_id


def _is_status_at_or_after_in_development(
    target_status: str, status_sequence: List[str]
) -> bool:
    """Retorna True se target_status for IN DEVELOPMENT ou posterior na sequência."""
    if not target_status or not status_sequence:
        return False
    target_upper = target_status.strip().upper()
    in_dev_idx = None
    status_idx = None
    for i, s in enumerate(status_sequence):
        s_upper = (s or "").upper()
        if s_upper == "IN DEVELOPMENT":
            in_dev_idx = i
        if s_upper == target_upper:
            status_idx = i
    if in_dev_idx is None or status_idx is None:
        return False
    return status_idx >= in_dev_idx


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
        valor_entregue: str = "",
        plataformas_afetadas: Optional[List[str]] = None,
        registrar_worklog: bool = False,
        worklog_inicio: Optional[datetime] = None,
        worklog_duracao: int = 0,
        worklog_timezone: str = "UTC",
        parent_epic_key: str = "",
        worklog_comment: str = "",
        asset_custom_fields: Optional[Dict[str, Any]] = None,
        assets_cache: Any = None,
        pending_attachments: Optional[List[Dict[str, Any]]] = None,
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
        self.valor_entregue = valor_entregue or ""
        self.plataformas_afetadas = plataformas_afetadas or []
        self.registrar_worklog = registrar_worklog
        self.worklog_inicio = worklog_inicio
        self.worklog_duracao = worklog_duracao
        self.worklog_timezone = worklog_timezone
        self.parent_epic_key = parent_epic_key.strip() if parent_epic_key else ""
        self.worklog_comment = worklog_comment or ""
        self.asset_custom_fields = asset_custom_fields or {}
        self.assets_cache = assets_cache
        self.pending_attachments = pending_attachments or []

    def run(self):
        """Executa a criação da issue e transições em thread separada"""
        try:
            # Descobrir IDs reais dos campos Asset se forem placeholders (para incluir no create)
            if (self.valor_entregue or self.plataformas_afetadas) and self.assets_cache:
                self.assets_cache.ensure_field_ids()

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

            # Campos Asset (Valor entregue, Plataformas afetadas): usar objetos resolvidos se fornecidos
            if self.asset_custom_fields:
                for field_id, value in self.asset_custom_fields.items():
                    if value is not None:
                        custom_fields[field_id] = value
            else:
                # Fallback: Assets exigem formato {id, objectId, workspaceId} (ver Atlassian doc)
                # Resolver via cache quando disponível; senão usar [{"value": ...]} (pode falhar em Asset)
                valor_entregue_alias = self.config.get_custom_field("valor_entregue")
                if valor_entregue_alias and self.valor_entregue:
                    if self.assets_cache:
                        obj = self.assets_cache.resolve_valor_entregue_object(
                            self.valor_entregue
                        )
                        if obj:
                            custom_fields[valor_entregue_alias] = [obj]
                        else:
                            custom_fields[valor_entregue_alias] = [
                                {"value": self.valor_entregue}
                            ]
                    else:
                        custom_fields[valor_entregue_alias] = [
                            {"value": self.valor_entregue}
                        ]
                plataformas_alias = self.config.get_custom_field("plataformas_afetadas")
                if plataformas_alias and self.plataformas_afetadas:
                    if self.assets_cache:
                        objs = self.assets_cache.resolve_plataformas_objects(
                            self.plataformas_afetadas
                        )
                        if objs:
                            custom_fields[plataformas_alias] = objs
                        else:
                            custom_fields[plataformas_alias] = [
                                {"value": p} for p in self.plataformas_afetadas
                            ]
                    else:
                        custom_fields[plataformas_alias] = [
                            {"value": p} for p in self.plataformas_afetadas
                        ]

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

            # Anexos pendentes: upload e substituir placeholders na descrição
            description_final = self.description
            if self.pending_attachments:
                self.progressUpdated.emit(52, "Enviando anexos...")
                placeholder_to_url: Dict[str, str] = {}
                for i, item in enumerate(self.pending_attachments):
                    path = (item.get("path") or "").strip()
                    placeholder_id = (item.get("placeholderId") or "").strip()
                    if not path or not placeholder_id:
                        continue
                    try:
                        att_result = self.jira_client.add_attachment(
                            issue_key, path
                        )
                        if att_result and len(att_result) > 0:
                            content_url = att_result[0].get("content", "")
                            if content_url:
                                placeholder_to_url[placeholder_id] = content_url
                    except Exception as e:
                        self.errorOccurred.emit(
                            f"Erro ao anexar arquivo: {str(e)}"
                        )
                # Substituir placeholders na descrição
                for pid, content_url in placeholder_to_url.items():
                    description_final = description_final.replace(
                        f"pending:{pid}", content_url
                    )
                if placeholder_to_url:
                    self.jira_client.update_issue(
                        issue_key=issue_key,
                        description=description_final,
                    )
                self.progressUpdated.emit(55, "Anexos enviados!")

            # Transicionar status se necessário (worklog é registrado ao atingir IN DEVELOPMENT)
            if self.target_status != "TO DO":
                self.progressUpdated.emit(60, "Iniciando transições de status...")

                # Callback para progresso de transições
                def progress_callback(status, percentage, message):
                    transition_progress = 60 + int((percentage * 40) / 100)
                    self.progressUpdated.emit(transition_progress, message)

                sequence = self.config.get_status_sequence()
                worklog_config = None
                if (
                    self.registrar_worklog
                    and self.worklog_inicio
                    and self.worklog_duracao
                    and _is_status_at_or_after_in_development(
                        self.target_status, sequence
                    )
                ):
                    worklog_config = WorklogConfig(
                        registrar=True,
                        inicio=self.worklog_inicio,
                        duracao=self.worklog_duracao,
                        timezone=self.worklog_timezone,
                        comment=self.worklog_comment,
                    )
                worklog_registered = transition_sequentially(
                    jira_client=self.jira_client,
                    issue_key=issue_key,
                    target_status=self.target_status,
                    status_sequence=sequence,
                    progress_callback=progress_callback,
                    worklog=worklog_config,
                )

                # Registrar worklog no fim só se não foi registrado ao atingir IN DEVELOPMENT
                # (ex.: issue já estava em ou após IN DEVELOPMENT e transitou para status posterior)
                if (
                    not worklog_registered
                    and self.registrar_worklog
                    and self.worklog_inicio
                    and self.worklog_duracao
                    and _is_status_at_or_after_in_development(
                        self.target_status, sequence
                    )
                ):
                    self.progressUpdated.emit(85, "Registrando worklog...")
                    time_spent = self.jira_client._format_duration_minutes(
                        self.worklog_duracao
                    )
                    started_str = self.worklog_inicio.strftime(
                        "%Y-%m-%d %H:%M:%S"
                    )
                    worklog_ok = self.jira_client.register_worklog(
                        issue_key=issue_key,
                        time_spent=time_spent,
                        started=started_str,
                        timezone=self.worklog_timezone,
                        comment=self.worklog_comment,
                    )
                    if not worklog_ok:
                        self.errorOccurred.emit(
                            f"AVISO: Não foi possível registrar worklog para {issue_key}"
                        )
                    else:
                        self.progressUpdated.emit(
                            90, "Worklog registrado com sucesso!"
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
    reachedInDevelopment = Signal(str)  # issue_key (Fase 1 completa; usado em transição em duas fases)
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
        valor_entregue: Optional[str] = None,
        plataformas_afetadas: Optional[List[str]] = None,
        parent_epic_key: Optional[str] = None,
        registrar_worklog: bool = False,
        worklog_inicio: Optional[datetime] = None,
        worklog_duracao: int = 0,
        worklog_timezone: str = "UTC",
        worklog_comment: Optional[str] = None,
        assets_cache: Any = None,
        target_status_override: Optional[str] = None,
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
        self.valor_entregue = valor_entregue
        self.plataformas_afetadas = plataformas_afetadas or []
        self.parent_epic_key = parent_epic_key.strip() if parent_epic_key else None
        self.registrar_worklog = registrar_worklog
        self.worklog_inicio = worklog_inicio
        self.worklog_duracao = worklog_duracao
        self.worklog_timezone = worklog_timezone
        self.worklog_comment = worklog_comment
        self.assets_cache = assets_cache
        self.target_status_override = target_status_override

    def run(self):
        """Executa a atualização da issue e worklog opcional em thread separada"""
        try:
            # Descobrir IDs reais dos campos Asset se forem placeholders (para incluir no update)
            if (self.valor_entregue or self.plataformas_afetadas) and self.assets_cache:
                self.assets_cache.ensure_field_ids()

            self.progressUpdated.emit(10, "Atualizando issue no Jira...")

            # Preparar campos customizados (sem Asset quando transição for In Development e tiver cache)
            custom_fields: Dict[str, Any] = {}
            status_normalized = (self.status or "").strip().upper()
            use_asset_update = (
                status_normalized == "IN DEVELOPMENT" and self.assets_cache
            )

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

            if not use_asset_update:
                if self.valor_entregue:
                    valor_entregue_alias = self.config.get_custom_field(
                        "valor_entregue"
                    )
                    if valor_entregue_alias:
                        if self.assets_cache:
                            obj = self.assets_cache.resolve_valor_entregue_object(
                                self.valor_entregue
                            )
                            custom_fields[valor_entregue_alias] = (
                                [obj] if obj else [{"value": self.valor_entregue}]
                            )
                        else:
                            custom_fields[valor_entregue_alias] = [
                                {"value": self.valor_entregue}
                            ]
                if self.plataformas_afetadas:
                    plataformas_alias = self.config.get_custom_field(
                        "plataformas_afetadas"
                    )
                    if plataformas_alias:
                        if self.assets_cache:
                            objs = self.assets_cache.resolve_plataformas_objects(
                                self.plataformas_afetadas
                            )
                            custom_fields[plataformas_alias] = (
                                objs if objs else [{"value": p} for p in self.plataformas_afetadas]
                            )
                        else:
                            custom_fields[plataformas_alias] = [
                                {"value": p} for p in self.plataformas_afetadas
                            ]

            asset_field_updates: Dict[str, List[Dict[str, Any]]] = {}
            if use_asset_update and self.assets_cache:
                valor_field_id = self.config.get_custom_field("valor_entregue")
                plataformas_field_id = self.config.get_custom_field(
                    "plataformas_afetadas"
                )
                if (
                    valor_field_id
                    and not is_placeholder_custom_field_id(valor_field_id)
                    and self.valor_entregue
                ):
                    obj = self.assets_cache.resolve_valor_entregue_object(
                        self.valor_entregue
                    )
                    if obj:
                        asset_field_updates[valor_field_id] = [obj]
                if (
                    plataformas_field_id
                    and not is_placeholder_custom_field_id(plataformas_field_id)
                    and self.plataformas_afetadas
                ):
                    objs = self.assets_cache.resolve_plataformas_objects(
                        self.plataformas_afetadas
                    )
                    if objs:
                        asset_field_updates[plataformas_field_id] = objs

            # Não enviar "fields" no POST da transição: o ecrã de cada transição no Jira
            # define quais campos podem ser definidos; enviar campos que não estão no ecrã
            # causa "Field cannot be set. It is not on the appropriate screen".
            # Os campos são definidos no PUT (update_issue) antes de transicionar.

            # Atualizar campos da issue (sem status)
            success = self.jira_client.update_issue(
                issue_key=self.issue_key,
                summary=self.summary,
                description=self.description,
                status=None,
                custom_fields=custom_fields if custom_fields else None,
                parent_issue_key=self.parent_epic_key,
                asset_field_updates=(
                    asset_field_updates if asset_field_updates else None
                ),
            )

            if not success:
                self.errorOccurred.emit(f"Erro ao atualizar issue {self.issue_key}")
                return

            self.progressUpdated.emit(50, "Issue atualizada com sucesso!")

            # Transicionar status sequencialmente se fornecido (ou target_status_override para Fase 1)
            transition_target = (
                self.target_status_override.strip()
                if self.target_status_override and self.target_status_override.strip()
                else (self.status.strip() if self.status and self.status.strip() else None)
            )
            if transition_target:
                self.progressUpdated.emit(60, "Iniciando transições de status...")

                # Callback para progresso de transições
                def progress_callback(status, percentage, message):
                    transition_progress = 60 + int((percentage * 40) / 100)
                    self.progressUpdated.emit(transition_progress, message)

                sequence = self.config.get_status_sequence()
                worklog_config = None
                if (
                    self.registrar_worklog
                    and self.worklog_inicio
                    and self.worklog_duracao
                    and _is_status_at_or_after_in_development(
                        transition_target, sequence
                    )
                ):
                    worklog_config = WorklogConfig(
                        registrar=True,
                        inicio=self.worklog_inicio,
                        duracao=self.worklog_duracao,
                        timezone=self.worklog_timezone,
                        comment=self.worklog_comment,
                    )

                # Transicionar (worklog é registrado ao atingir IN DEVELOPMENT)
                worklog_registered = transition_sequentially(
                    jira_client=self.jira_client,
                    issue_key=self.issue_key,
                    target_status=transition_target,
                    status_sequence=sequence,
                    progress_callback=progress_callback,
                    worklog=worklog_config,
                )

                # Registrar worklog no fim só se não foi registrado ao atingir IN DEVELOPMENT
                if (
                    not worklog_registered
                    and self.registrar_worklog
                    and self.worklog_inicio
                    and self.worklog_duracao
                    and _is_status_at_or_after_in_development(
                        transition_target, sequence
                    )
                ):
                    self.progressUpdated.emit(85, "Registrando worklog...")
                    time_spent = self.jira_client._format_duration_minutes(
                        self.worklog_duracao
                    )
                    started_str = self.worklog_inicio.strftime(
                        "%Y-%m-%d %H:%M:%S"
                    )
                    worklog_ok = self.jira_client.register_worklog(
                        issue_key=self.issue_key,
                        time_spent=time_spent,
                        started=started_str,
                        timezone=self.worklog_timezone,
                        comment=self.worklog_comment,
                    )
                    if not worklog_ok:
                        self.errorOccurred.emit(
                            f"Erro ao registrar worklog para {self.issue_key}"
                        )
                        return
                    self.progressUpdated.emit(90, "Worklog registrado com sucesso!")

                self.progressUpdated.emit(100, "Transições concluídas!")
            else:
                # Se não houver transição de status, registrar worklog separadamente se solicitado
                if self.registrar_worklog and self.worklog_inicio:
                    self.progressUpdated.emit(60, "Registrando worklog...")

                    time_spent = self.jira_client._format_duration_minutes(
                        self.worklog_duracao
                    )
                    started_str = self.worklog_inicio.strftime("%Y-%m-%d %H:%M:%S")

                    success = self.jira_client.register_worklog(
                        issue_key=self.issue_key,
                        time_spent=time_spent,
                        started=started_str,
                        timezone=self.worklog_timezone,
                        comment=self.worklog_comment,
                    )

                    if not success:
                        self.errorOccurred.emit(
                            f"Erro ao registrar worklog para {self.issue_key}"
                        )
                        return

                    self.progressUpdated.emit(90, "Worklog registrado com sucesso!")

            self.progressUpdated.emit(100, "Concluído!")
            if self.target_status_override:
                self.reachedInDevelopment.emit(self.issue_key)
            else:
                self.issueUpdated.emit(self.issue_key)

        except Exception as e:
            error_msg = str(e)
            # Dica quando o Jira exige campos obrigatórios na transição
            if "preencher" in error_msg.lower() or "tipo de atividade" in error_msg.lower():
                error_msg += (
                    "\n\nPreencha no formulário: Tipo de atividade, Utilização de IA, "
                    "Documentação Anexa, Plataformas Afetadas e Valor entregue; depois tente novamente."
                )
            self.errorOccurred.emit(error_msg)
        finally:
            self.finished.emit()


class TransitionFromInDevelopmentWorker(QThread):
    """Worker que apenas transiciona a issue de IN DEVELOPMENT até o status alvo (Fase 2)."""

    progressUpdated = Signal(int, str)
    issueUpdated = Signal(str)
    errorOccurred = Signal(str)
    finished = Signal()

    def __init__(
        self,
        jira_client: JiraClient,
        config: ConfigManager,
        issue_key: str,
        target_status: str,
        parent=None,
    ):
        super().__init__(parent)
        self._jira_client = jira_client
        self._config = config
        self._issue_key = issue_key
        self._target_status = target_status.strip() if target_status else ""

    def run(self):
        try:
            if not self._target_status:
                self.errorOccurred.emit("Status alvo não fornecido")
                return
            sequence = self._config.get_status_sequence()
            self.progressUpdated.emit(10, "Transicionando para " + self._target_status + "...")

            def progress_cb(_status, percentage, message):
                self.progressUpdated.emit(10 + int((percentage * 90) / 100), message)

            transition_sequentially(
                jira_client=self._jira_client,
                issue_key=self._issue_key,
                target_status=self._target_status,
                status_sequence=sequence,
                progress_callback=progress_cb,
                worklog=None,
            )
            self.progressUpdated.emit(100, "Transições concluídas!")
            self.issueUpdated.emit(self._issue_key)
        except Exception as e:
            self.errorOccurred.emit(str(e))
        finally:
            self.finished.emit()


class EnsureInDevelopmentWorker(QThread):
    """Worker que transita a issue para IN DEVELOPMENT se estiver antes na sequência (para iniciar timer)."""

    inDevelopmentReady = Signal(str)  # issue_key quando pronto para timer
    progressUpdated = Signal(int, str)
    errorOccurred = Signal(str)
    finished = Signal()

    def __init__(
        self,
        jira_client: JiraClient,
        config: ConfigManager,
        issue_key: str,
        parent=None,
    ):
        super().__init__(parent)
        self._jira_client = jira_client
        self._config = config
        self._issue_key = issue_key.strip() if issue_key else ""

    def run(self):
        try:
            if not self._issue_key:
                self.errorOccurred.emit("Issue key não fornecido")
                return
            sequence = self._config.get_status_sequence()
            in_dev_idx = _get_in_development_index(sequence)
            if in_dev_idx is None:
                self.inDevelopmentReady.emit(self._issue_key)
                return
            issue_data = self._jira_client.get_issue_details(self._issue_key)
            if not issue_data:
                self.errorOccurred.emit("Não foi possível obter dados da issue")
                return
            status_obj = issue_data.get("status")
            if isinstance(status_obj, dict):
                current_status = status_obj.get("name", "") or ""
            else:
                current_status = str(status_obj) if status_obj else ""
            current_idx = _get_status_index(current_status, sequence)
            # Só transicionar quando o status está antes de IN DEVELOPMENT na sequência.
            # Se o status não estiver na sequência (current_idx is None), tratar como já OK (não transitar).
            if current_idx is None or current_idx >= in_dev_idx:
                self.inDevelopmentReady.emit(self._issue_key)
                return
            self.progressUpdated.emit(10, "Transicionando para IN DEVELOPMENT...")

            def progress_cb(_status, percentage, message):
                self.progressUpdated.emit(10 + int((percentage * 90) / 100), message)

            transition_sequentially(
                jira_client=self._jira_client,
                issue_key=self._issue_key,
                target_status="IN DEVELOPMENT",
                status_sequence=sequence,
                progress_callback=progress_cb,
                worklog=None,
            )
            self.progressUpdated.emit(100, "Pronto para iniciar timer.")
            self.inDevelopmentReady.emit(self._issue_key)
        except Exception as e:
            self.errorOccurred.emit(str(e))
        finally:
            self.finished.emit()


class AttachmentUploadWorker(QThread):
    """Worker para upload de um anexo em thread separada."""

    uploadSucceeded = Signal(str, str, str)  # issueKey, contentUrl, filename
    uploadFailed = Signal(str, str)  # issueKey, errorMessage
    finished = Signal()

    def __init__(
        self,
        jira_client: JiraClient,
        issue_key: str,
        file_path: str,
        parent=None,
    ):
        super().__init__(parent)
        self._jira_client = jira_client
        self._issue_key = issue_key
        self._file_path = file_path

    def run(self) -> None:
        try:
            result = self._jira_client.add_attachment(
                self._issue_key, self._file_path
            )
            if result and len(result) > 0:
                content_url = result[0].get("content", "")
                filename = result[0].get("filename", "")
                self.uploadSucceeded.emit(
                    self._issue_key, content_url, filename
                )
            else:
                self.uploadFailed.emit(
                    self._issue_key, "Resposta vazia ao anexar arquivo"
                )
        except Exception as e:
            self.uploadFailed.emit(self._issue_key, str(e))
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
    epicSearchCompleted = Signal(
        "QVariant", str
    )  # lista de epics (list[dict], nextPageToken)
    epicSearchPageCompleted = Signal(
        "QVariant", str
    )  # lista de epics para paginação incremental (list[dict], nextPageToken)
    # Signals específicos para carregamento de detalhes de issue (modo assíncrono)
    issueDetailsStarted = Signal(str)  # issueKey
    issueDetailsLoaded = Signal("QVariant")  # dict com detalhes da issue
    # Enriquecimento de PRs com dados do GitHub (checks, approvals)
    developmentEnriched = Signal(str, "QVariant")  # issueKey, list of enriched PR dicts
    # Enriquecimento de branches com ahead/behind do GitHub (compare API)
    developmentBranchesEnriched = Signal(str, "QVariant")  # issueKey, list of enriched branch dicts
    # Cache de opções de Assets (Valor entregue, Plataformas afetadas)
    assetsCacheLoaded = Signal(bool, str)  # success, message
    # Comentários de issues
    commentsLoaded = Signal("QVariantList")  # list of comment dicts
    commentAdded = Signal(str, "QVariant")  # issueKey, commentDict
    commentUpdated = Signal(str, str, "QVariant")  # issueKey, commentId, commentDict
    commentDeleted = Signal(str, str)  # issueKey, commentId
    # Anexos: upload imediato (comentário / edição de task)
    attachmentUploaded = Signal(str, str, str)  # issueKey, contentUrl, filename
    uploadFailed = Signal(str, str)  # issueKey, errorMessage
    # Transição em duas fases: ao atingir IN DEVELOPMENT (para sync worklogs pendentes)
    reachedInDevelopment = Signal(str)  # issueKey
    inDevelopmentReady = Signal(str)  # issueKey (para iniciar timer após transição automática)

    def __init__(self, parent=None, config_manager: Optional[ConfigManager] = None):
        super().__init__(parent)

        # Usar ConfigManager compartilhado (SettingsModel) para enrichment, ou criar próprio
        try:
            from src.utils.debug import debug_log

            debug_log("JiraService", "__init__", "Carregando configuração...")
            self._config = config_manager if config_manager is not None else ConfigManager()
            debug_log("JiraService", "__init__", "Configuração carregada com sucesso")
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
            self._jira_client = JiraClient(
                jira_cli_config_path=jira_cli_config_path, account_id=account_id
            )
        except RuntimeError as e:
            # Não é erro crítico - é esperado na primeira inicialização sem config
            # Usar debug_log para não alarmar
            try:
                from src.utils.debug import debug_log

                debug_log(
                    "JiraService",
                    "__init__",
                    "JiraClient não inicializado: %s (normal se configuração ainda não foi feita)",
                    e,
                )
            except ImportError:
                # Se debug não estiver disponível, não fazer nada (silencioso)
                pass
            self._jira_client = None

        self._assets_cache: Optional[AssetsCacheService] = None
        if self._jira_client and self._config:
            try:
                self._assets_cache = AssetsCacheService(
                    self._jira_client, self._config
                )
                self._assets_cache.load()
            except Exception:
                self._assets_cache = None

        self._worker: Optional[JiraWorker] = None
        self._update_worker: Optional[UpdateWorker] = None
        self._transition_from_in_dev_worker: Optional[
            TransitionFromInDevelopmentWorker
        ] = None
        self._ensure_in_dev_worker: Optional[EnsureInDevelopmentWorker] = None
        self._epic_search_worker: Optional[QThread] = None
        self._issue_details_worker: Optional[QThread] = None
        self._reload_worker: Optional[QThread] = None  # manter referência para não GC antes do thread terminar
        self._comments_worker: Optional[QThread] = None
        self._attachment_worker: Optional[QThread] = None
        self._development_enrich_worker: Optional[QThread] = None
        self._development_branches_enrich_worker: Optional[QThread] = None

    def get_assets_cache(self) -> Optional[AssetsCacheService]:
        """Retorna o serviço de cache de Assets (para IssueModel e payloads)."""
        return self._assets_cache

    @Slot()
    def reloadAssetsCache(self) -> None:
        """
        Recarrega opções de Valor entregue e Plataformas afetadas da API de Assets.
        Emite assetsCacheLoaded(success, message) ao concluir.
        Executa em thread para não bloquear a UI.
        """
        if not self._assets_cache:
            self.assetsCacheLoaded.emit(
                False, "Cache de Assets não disponível (conecte o Jira primeiro)."
            )
            return

        class ReloadWorker(QThread):
            finishedWithResult = Signal(bool, str)

            def __init__(self, cache: AssetsCacheService):
                super().__init__()
                self._cache = cache

            def run(self):
                ok, msg = self._cache.reload()
                self.finishedWithResult.emit(ok, msg)

        # Manter referência ao worker até terminar; senão o GC pode destruir o QThread
        # com a thread ainda rodando e causar SIGABRT (ex.: ao clicar "Recarregar opções").
        if self._reload_worker is not None and self._reload_worker.isRunning():
            self.assetsCacheLoaded.emit(False, "Recarregamento já em andamento.")
            return
        self._reload_worker = ReloadWorker(self._assets_cache)

        def on_reload_done(ok: bool, msg: str):
            self.assetsCacheLoaded.emit(ok, msg)
            self._reload_worker = None

        def on_thread_finished():
            self._reload_worker = None

        self._reload_worker.finishedWithResult.connect(on_reload_done)
        self._reload_worker.finished.connect(on_thread_finished)
        self._reload_worker.start()

    def getValorEntregueLabels(self) -> List[str]:
        """Retorna lista de labels para Valor entregue (para exibição na UI). Nunca levanta."""
        try:
            if self._assets_cache:
                return self._assets_cache.get_valor_entregue_labels()
            if self._config:
                return self._config.get_valor_entregue_values() or []
        except Exception:
            pass
        return []

    def getPlataformasAfetadasLabels(self) -> List[str]:
        """Retorna lista de labels para Plataformas afetadas (para exibição na UI). Nunca levanta."""
        try:
            if self._assets_cache:
                return self._assets_cache.get_plataformas_afetadas_labels()
            if self._config:
                return self._config.get_plataformas_afetadas_values() or []
        except Exception:
            pass
        return []

    def getValorEntregueOptions(self) -> List[Dict[str, Any]]:
        """Retorna lista de opções Valor entregue: [{ objectId, id, workspaceId, label }, ...]. Nunca levanta."""
        try:
            if self._assets_cache:
                return self._assets_cache.get_valor_entregue_options()
        except Exception:
            pass
        return []

    def getPlataformasAfetadasOptions(self) -> List[Dict[str, Any]]:
        """Retorna lista de opções Plataformas afetadas. Nunca levanta."""
        try:
            if self._assets_cache:
                return self._assets_cache.get_plataformas_afetadas_options()
        except Exception:
            pass
        return []

    @Slot()
    def reloadConfiguration(self) -> None:
        """
        Recarrega configuração e recria JiraClient.
        Deve ser chamado após salvar configurações.
        """
        try:
            from src.utils.debug import debug_log

            debug_log(
                "JiraService", "reloadConfiguration", "Recarregando configuração..."
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
                    "JiraService",
                    "reloadConfiguration",
                    "JiraClient recriado com sucesso",
                )
            except RuntimeError as e:
                debug_log(
                    "JiraService",
                    "reloadConfiguration",
                    "JiraClient não pôde ser recriado: %s",
                    e,
                )
                self._jira_client = None

            # Recriar cache de Assets
            self._assets_cache = None
            if self._jira_client and self._config:
                try:
                    self._assets_cache = AssetsCacheService(
                        self._jira_client, self._config
                    )
                    self._assets_cache.load()
                except Exception:
                    self._assets_cache = None
        except Exception as e:
            from src.utils.debug import debug_log

            debug_log("JiraService", "reloadConfiguration", "Erro ao recarregar: %s", e)
            # Manter estado anterior em caso de erro

    @Slot(
        str,
        str,
        str,
        str,
        str,
        str,
        str,
        list,
        bool,
        str,
        int,
        str,
        str,
        str,
        "QVariantList",
        result=bool,
    )
    def createIssue(  # NOSONAR - camelCase necessário para compatibilidade com QML
        self,
        summary: str,
        description: str,
        tipoAtividade: str,  # NOSONAR
        statusInicial: str,  # NOSONAR
        documentacaoAnexa: str,  # NOSONAR
        utilizacaoIA: str,  # NOSONAR
        valorEntregue: str,  # NOSONAR
        plataformasAfetadas: List[str],  # NOSONAR
        registrarWorklog: bool,  # NOSONAR
        worklogInicio: str,  # NOSONAR
        worklogDuracao: int,  # NOSONAR
        worklogTimezone: str,  # NOSONAR
        parentEpicKey: str,  # NOSONAR - pode ser vazio
        worklogComment: str = "",  # NOSONAR - comentário opcional do worklog
        pendingAttachments: Optional[List[Any]] = None,  # NOSONAR
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
        worklogTimezone = (
            self._config.get_timezone() if self._config else "America/Sao_Paulo"
        )

        # Incluir objetos Asset (Valor entregue, Plataformas afetadas) apenas quando
        # o status alvo for In Development (regra de negócio). Não usar placeholders:
        # se os IDs forem placeholders, o worker fará ensure_field_ids() e construirá a partir do config.
        asset_custom_fields: Dict[str, Any] = {}
        target_normalized = (statusInicial or "").strip().upper()
        if target_normalized == "IN DEVELOPMENT" and self._assets_cache:
            valor_field_id = self._config.get_custom_field("valor_entregue")
            plataformas_field_id = self._config.get_custom_field("plataformas_afetadas")
            if (
                valor_field_id
                and not is_placeholder_custom_field_id(valor_field_id)
                and valorEntregue
            ):
                obj = self._assets_cache.resolve_valor_entregue_object(
                    valorEntregue
                )
                if obj:
                    asset_custom_fields[valor_field_id] = [obj]
            if (
                plataformas_field_id
                and not is_placeholder_custom_field_id(plataformas_field_id)
                and plataformasAfetadas
            ):
                objs = self._assets_cache.resolve_plataformas_objects(
                    plataformasAfetadas
                )
                if objs:
                    asset_custom_fields[plataformas_field_id] = objs

        # Normalizar pendingAttachments: QML envia lista de mapas { path, filename, placeholderId }
        pending_list: List[Dict[str, Any]] = []
        if pendingAttachments:
            for item in pendingAttachments:
                if isinstance(item, dict):
                    pending_list.append(
                        {
                            "path": str(item.get("path", "")).strip(),
                            "filename": str(item.get("filename", "")).strip(),
                            "placeholderId": str(
                                item.get("placeholderId", "")
                            ).strip(),
                        }
                    )
                elif hasattr(item, "get"):
                    pending_list.append(
                        {
                            "path": str(getattr(item, "path", "")).strip(),
                            "filename": str(
                                getattr(item, "filename", "")
                            ).strip(),
                            "placeholderId": str(
                                getattr(item, "placeholderId", "")
                            ).strip(),
                        }
                    )

        # Criar novo worker (assets_cache para fallback com formato id/objectId/workspaceId)
        self._worker = JiraWorker(
            jira_client=self._jira_client,
            config=self._config,
            summary=summary.strip(),
            description=description.strip() if description else "",
            tipo_atividade=tipoAtividade,
            target_status=statusInicial,
            doc_anexa=documentacaoAnexa,
            uso_ia=utilizacaoIA,
            valor_entregue=valorEntregue if valorEntregue else "",
            plataformas_afetadas=plataformasAfetadas if plataformasAfetadas else [],
            registrar_worklog=registrarWorklog,
            worklog_inicio=worklog_inicio_dt,
            worklog_duracao=worklogDuracao,
            worklog_timezone=worklogTimezone,
            parent_epic_key=parentEpicKey,
            worklog_comment=worklogComment.strip() if worklogComment else "",
            asset_custom_fields=asset_custom_fields if asset_custom_fields else None,
            assets_cache=self._assets_cache,
            pending_attachments=pending_list if pending_list else None,
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
                "Configuração do Jira não encontrada. Configure a conexão na aba de Configurações:\n"
                "  1. URL do servidor Jira\n"
                "  2. Email do usuário\n"
                "  3. Token de API do Jira\n\n"
                "O token pode ser obtido em: https://id.atlassian.com/manage-profile/security/api-tokens"
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

    @Slot(result=int)
    def getRetroactiveMaxHours(self) -> int:
        """Retorna horas máximas permitidas para worklog retroativo"""
        if self._config:
            return self._config.get_retroactive_max_hours()
        return 24

    @Slot(result="QVariantList")
    def getDefaultDurations(self) -> List[int]:
        """Retorna lista de durações padrão em minutos para presets"""
        if self._config:
            return self._config.get_default_durations()
        return [30, 60, 120, 240, 480]

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
        if (
            not next_page_token
            and self._epic_search_worker
            and self._epic_search_worker.isRunning()
        ):
            self._epic_search_worker.terminate()
            self._epic_search_worker.wait()

        # Worker simples inline para não poluir o namespace público
        class _EpicSearchWorker(QThread):
            resultsReady = Signal(
                "QVariant", str
            )  # Para busca normal: (results, nextPageToken)
            pageReady = Signal(
                "QVariant", str
            )  # Para paginação incremental: (results, nextPageToken)
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
        self,
        created_by_me: bool,
        assigned_to_me: bool,
        project_platform: bool,
        exclude_done: bool,
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
        worklogTimezone = (
            self._config.get_timezone() if self._config else "America/Sao_Paulo"
        )

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
            self.errorOccurred.emit(
                f"Não foi possível registrar worklog para {issueKey}"
            )

        return success

    @Slot(str, str, result=bool)
    def uploadAttachment(  # NOSONAR - camelCase para QML
        self, issueKey: str, filePath: str
    ) -> bool:
        """
        Envia um anexo para a issue em thread separada.
        Emite attachmentUploaded(issueKey, contentUrl, filename) ou
        uploadFailed(issueKey, errorMessage) ao concluir.
        Valida tamanho e extensão antes do upload (config + limite do Jira quando disponível).
        """
        if not self._jira_client:
            self.errorOccurred.emit("Cliente Jira não inicializado")
            return False
        if not issueKey or not filePath:
            return False
        path = Path(filePath.strip())
        if not path.exists() or not path.is_file():
            self.uploadFailed.emit(issueKey.strip(), "Arquivo não encontrado.")
            return False
        max_mb = 10
        allowed_extensions: List[str] = []
        if self._config:
            max_mb = self._config.get_attachment_max_size_mb()
            allowed_extensions = self._config.get_allowed_attachment_extensions()
        max_bytes = max_mb * 1024 * 1024
        try:
            file_size = path.stat().st_size
        except OSError:
            self.uploadFailed.emit(issueKey.strip(), "Não foi possível ler o tamanho do arquivo.")
            return False
        if file_size > max_bytes:
            self.uploadFailed.emit(
                issueKey.strip(),
                f"Arquivo muito grande (máx. {max_mb} MB).",
            )
            return False
        try:
            jira_settings = self._jira_client.get_attachment_settings()
            upload_limit = jira_settings.get("uploadLimit")
            if upload_limit is not None and file_size > int(upload_limit):
                self.uploadFailed.emit(
                    issueKey.strip(),
                    "Arquivo excede o limite de anexos do Jira.",
                )
                return False
        except Exception:
            pass
        ext = (path.suffix or "").lstrip(".").lower()
        if ext and allowed_extensions and ext not in allowed_extensions:
            self.uploadFailed.emit(
                issueKey.strip(),
                "Tipo de arquivo não permitido.",
            )
            return False
        if self._attachment_worker and self._attachment_worker.isRunning():
            return False
        worker = AttachmentUploadWorker(
            self._jira_client, issueKey.strip(), filePath.strip()
        )
        self._attachment_worker = worker

        def on_success(ik: str, content_url: str, filename: str):
            self.attachmentUploaded.emit(ik, content_url, filename)

        def on_fail(ik: str, msg: str):
            self.uploadFailed.emit(ik, msg)
            self.errorOccurred.emit(msg)

        def cleanup():
            if self._attachment_worker is worker:
                self._attachment_worker = None

        worker.uploadSucceeded.connect(on_success)
        worker.uploadFailed.connect(on_fail)
        worker.finished.connect(cleanup)
        worker.start()
        return True

    def _get_assets_extra_fields(self) -> List[str]:
        """IDs dos campos Asset (Valor entregue, Plataformas) para incluir no GET issue; filtra placeholders."""
        try:
            from src.utils.field_utils import is_placeholder_custom_field_id
        except ImportError:
            is_placeholder_custom_field_id = lambda fid: fid in (
                "customfield_XXXXX",
                "customfield_YYYYY",
            )
        if not self._config:
            return []
        out = []
        for key in ("valor_entregue", "plataformas_afetadas"):
            fid = self._config.get_custom_field(key)
            if fid and not is_placeholder_custom_field_id(fid):
                out.append(fid)
        return out

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

        extra = self._get_assets_extra_fields()
        issue_data = self._jira_client.get_issue_details(
            issueKey.strip(), extra_fields=extra if extra else None
        )
        if not issue_data:
            return {}

        return self._build_issue_details_dict(issue_data)

    @Slot(
        str,
        str,
        str,
        str,
        str,
        str,
        str,
        str,
        list,
        str,
        bool,
        str,
        int,
        str,
        str,
        result=bool,
    )
    @Slot(str, str, result=bool)
    def needsTwoPhaseTransition(  # NOSONAR
        self, currentStatus: str, targetStatus: str  # NOSONAR
    ) -> bool:
        """Retorna True se a transição deve ser em duas fases (parar em IN DEVELOPMENT)."""
        if not self._config:
            return False
        sequence = self._config.get_status_sequence()
        return needs_two_phase_transition(
            currentStatus or "", targetStatus or "", sequence
        )

    @Slot(str, str, result=bool)
    def requiresWorklogCheckBeforeTransition(  # NOSONAR
        self, currentStatus: str, targetStatus: str  # NOSONAR
    ) -> bool:
        """Retorna True se deve verificar worklogs pendentes (mostrar diálogo ou sync)."""
        if not self._config:
            return False
        sequence = self._config.get_status_sequence()
        return requires_worklog_check_before_transition(
            currentStatus or "", targetStatus or "", sequence
        )

    @Slot(result=bool)
    def worklogCheckEnabled(self) -> bool:
        """Retorna se a verificação de worklogs pendentes está habilitada (config)."""
        return bool(self._config and self._config.worklog_check_enabled())

    @Slot(result=bool)
    def worklogCheckShowDialog(self) -> bool:
        """Retorna se deve mostrar diálogo de confirmação quando houver pendentes (config)."""
        return bool(self._config and self._config.worklog_check_show_dialog())

    @Slot(result=bool)
    def worklogCheckBlockIfPending(self) -> bool:
        """Retorna se deve bloquear transição se houver pendentes (config)."""
        return bool(self._config and self._config.worklog_check_block_if_pending())

    @Slot(str, str, str, str, str, str, str, str, list, str, bool, str, int, str, str, result=bool)
    def transitionToInDevelopment(  # NOSONAR - Fase 1: atualizar campos e transitar até IN DEVELOPMENT
        self,
        issueKey: str,  # NOSONAR
        summary: str,
        description: str,
        tipoAtividade: str,  # NOSONAR
        status: str,
        documentacaoAnexa: str,  # NOSONAR
        utilizacaoIA: str,  # NOSONAR
        valorEntregue: str,  # NOSONAR
        plataformasAfetadas: List[str],  # NOSONAR
        parentEpicKey: str,  # NOSONAR
        registrarWorklog: bool,  # NOSONAR
        worklogInicio: str,  # NOSONAR
        worklogDuracao: int,  # NOSONAR
        worklogTimezone: str,  # NOSONAR
        worklogComment: str,  # NOSONAR
    ) -> bool:
        """Fase 1: atualiza campos da issue e transiciona até IN DEVELOPMENT; emite reachedInDevelopment(issueKey)."""
        if not self._jira_client or not self._config or not issueKey or not issueKey.strip():
            if not issueKey or not issueKey.strip():
                self.errorOccurred.emit("Issue key é obrigatório")
            return False
        if self._update_worker and self._update_worker.isRunning():
            self._update_worker.terminate()
            self._update_worker.wait()
        worklog_inicio_dt = None
        if registrarWorklog and worklogInicio:
            try:
                worklog_inicio_dt = datetime.strptime(
                    worklogInicio.strip(), "%Y-%m-%d %H:%M:%S"
                )
            except (ValueError, AttributeError):
                self.errorOccurred.emit(f"Formato de data/hora inválido: {worklogInicio}")
                return False
        worklogTimezone = self._config.get_timezone() if self._config else "America/Sao_Paulo"
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
            valor_entregue=valorEntregue if valorEntregue else None,
            plataformas_afetadas=plataformasAfetadas if plataformasAfetadas else None,
            parent_epic_key=parentEpicKey.strip() if parentEpicKey else None,
            registrar_worklog=registrarWorklog,
            worklog_inicio=worklog_inicio_dt,
            worklog_duracao=worklogDuracao,
            worklog_timezone=worklogTimezone,
            worklog_comment=worklogComment.strip() if worklogComment else None,
            assets_cache=self._assets_cache,
            target_status_override="IN DEVELOPMENT",
        )
        self._update_worker.progressUpdated.connect(self.progressUpdated.emit)
        self._update_worker.reachedInDevelopment.connect(self.reachedInDevelopment.emit)
        self._update_worker.errorOccurred.connect(self.errorOccurred.emit)
        self._update_worker.start()
        return True

    @Slot(str, str, result=bool)
    def transitionFromInDevelopmentToTarget(  # NOSONAR
        self, issueKey: str, targetStatus: str  # NOSONAR
    ) -> bool:
        """Fase 2: transiciona de IN DEVELOPMENT até o status alvo (sem worklog)."""
        if not self._jira_client or not self._config or not issueKey or not issueKey.strip():
            return False
        if self._transition_from_in_dev_worker and self._transition_from_in_dev_worker.isRunning():
            self._transition_from_in_dev_worker.terminate()
            self._transition_from_in_dev_worker.wait()
        self._transition_from_in_dev_worker = TransitionFromInDevelopmentWorker(
            jira_client=self._jira_client,
            config=self._config,
            issue_key=issueKey.strip(),
            target_status=targetStatus or "",
            parent=self,
        )
        self._transition_from_in_dev_worker.progressUpdated.connect(
            self.progressUpdated.emit
        )
        self._transition_from_in_dev_worker.issueUpdated.connect(
            self.issueUpdated.emit
        )
        self._transition_from_in_dev_worker.errorOccurred.connect(
            self.errorOccurred.emit
        )
        self._transition_from_in_dev_worker.start()
        return True

    @Slot(str, result=bool)
    def transitionToInDevelopmentIfNeeded(  # NOSONAR
        self, issueKey: str  # NOSONAR
    ) -> bool:
        """
        Se a issue estiver em status anterior a IN DEVELOPMENT, transita para IN DEVELOPMENT.
        Emite inDevelopmentReady(issueKey) quando a issue estiver pronta (para iniciar timer).
        """
        if not self._jira_client or not self._config or not issueKey or not issueKey.strip():
            if issueKey and issueKey.strip():
                self.inDevelopmentReady.emit(issueKey.strip())
            return False
        if self._ensure_in_dev_worker and self._ensure_in_dev_worker.isRunning():
            return True
        self._ensure_in_dev_worker = EnsureInDevelopmentWorker(
            jira_client=self._jira_client,
            config=self._config,
            issue_key=issueKey.strip(),
            parent=self,
        )
        self._ensure_in_dev_worker.inDevelopmentReady.connect(
            self.inDevelopmentReady.emit
        )
        self._ensure_in_dev_worker.progressUpdated.connect(
            self.progressUpdated.emit
        )
        self._ensure_in_dev_worker.errorOccurred.connect(
            self.errorOccurred.emit
        )
        self._ensure_in_dev_worker.start()
        return True

    @Slot(
        str,
        str,
        str,
        str,
        str,
        str,
        str,
        str,
        list,
        str,
        bool,
        str,
        int,
        str,
        str,
        result=bool,
    )
    def updateIssue(  # NOSONAR - camelCase necessário para compatibilidade com QML
        self,
        issueKey: str,  # NOSONAR
        summary: str,
        description: str,
        tipoAtividade: str,  # NOSONAR
        status: str,
        documentacaoAnexa: str,  # NOSONAR
        utilizacaoIA: str,  # NOSONAR
        valorEntregue: str,  # NOSONAR
        plataformasAfetadas: List[str],  # NOSONAR
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
        worklogTimezone = (
            self._config.get_timezone() if self._config else "America/Sao_Paulo"
        )

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
            valor_entregue=valorEntregue if valorEntregue else None,
            plataformas_afetadas=plataformasAfetadas if plataformasAfetadas else None,
            parent_epic_key=parentEpicKey.strip() if parentEpicKey else None,
            registrar_worklog=registrarWorklog,
            worklog_inicio=worklog_inicio_dt,
            worklog_duracao=worklogDuracao,
            worklog_timezone=worklogTimezone,
            worklog_comment=worklogComment.strip() if worklogComment else None,
            assets_cache=self._assets_cache,
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
        valor_entregue = ""
        plataformas_afetadas: List[str] = []

        # Obter IDs dos campos customizados do config (com fallback para valores hardcoded)
        config = self._config
        CUSTOM_FIELD_IDS = {
            "tipo_atividade": (
                config.get_custom_field("tipo_atividade")
                if config
                else "customfield_12088"
            ),
            "documentacao_anexa": (
                config.get_custom_field("documentacao_anexa")
                if config
                else "customfield_14840"
            ),
            "utilizacao_ia": (
                config.get_custom_field("utilizacao_ia")
                if config
                else "customfield_14841"
            ),
            "valor_entregue": (
                config.get_custom_field("valor_entregue") if config else ""
            ),
            "plataformas_afetadas": (
                config.get_custom_field("plataformas_afetadas") if config else ""
            ),
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

        def extract_multi_select_field(field_id: str) -> List[str]:
            """Extrai valores de campo multi-select (lista de objetos)"""
            if not field_id or field_id not in fields:
                return []

            value = fields[field_id]
            if value is None:
                return []

            result = []
            if isinstance(value, list):
                for item in value:
                    if isinstance(item, dict):
                        item_value = item.get("value") or item.get("name")
                        if item_value:
                            result.append(str(item_value))
                    elif isinstance(item, str):
                        result.append(item)
            elif isinstance(value, dict):
                # Caso único valor
                item_value = value.get("value") or value.get("name")
                if item_value:
                    result.append(str(item_value))
            elif isinstance(value, str):
                result.append(value)

            return result

        def _asset_object_id(obj: Any) -> Optional[str]:
            """Extrai objectId (ou id global) de um objeto Asset da API."""
            if not isinstance(obj, dict):
                return str(obj) if obj else None
            oid = obj.get("objectId") or obj.get("id")
            if oid is not None:
                return str(oid)
            return None

        def extract_asset_single(field_id: str) -> str:
            """Extrai objectId de campo Asset (valor único: objeto ou lista de um)."""
            if not field_id or field_id not in fields:
                return ""
            value = fields[field_id]
            if value is None:
                return ""
            if isinstance(value, list) and value:
                return _asset_object_id(value[0]) or ""
            return _asset_object_id(value) or ""

        def extract_asset_multi(field_id: str) -> List[str]:
            """Extrai objectIds de campo Asset (lista de objetos)."""
            if not field_id or field_id not in fields:
                return []
            value = fields[field_id]
            if value is None:
                return []
            result = []
            if isinstance(value, list):
                for item in value:
                    oid = _asset_object_id(item)
                    if oid:
                        result.append(oid)
            else:
                oid = _asset_object_id(value)
                if oid:
                    result.append(oid)
            return result

        tipo_atividade = extract_custom_field_by_id(CUSTOM_FIELD_IDS["tipo_atividade"])
        documentacao_anexa = extract_custom_field_by_id(
            CUSTOM_FIELD_IDS["documentacao_anexa"]
        )
        utilizacao_ia = extract_custom_field_by_id(CUSTOM_FIELD_IDS["utilizacao_ia"])

        if CUSTOM_FIELD_IDS["valor_entregue"]:
            raw_ve = fields.get(CUSTOM_FIELD_IDS["valor_entregue"])
            # Se for objeto/dict com objectId ou id (formato Asset), usar extract_asset_single
            if isinstance(raw_ve, dict) and (
                "objectId" in raw_ve or "id" in raw_ve or "workspaceId" in raw_ve
            ):
                valor_entregue = extract_asset_single(CUSTOM_FIELD_IDS["valor_entregue"])
            elif isinstance(raw_ve, list) and raw_ve and isinstance(raw_ve[0], dict):
                valor_entregue = extract_asset_single(CUSTOM_FIELD_IDS["valor_entregue"])
            else:
                valor_entregue = extract_custom_field_by_id(
                    CUSTOM_FIELD_IDS["valor_entregue"]
                )

        if CUSTOM_FIELD_IDS["plataformas_afetadas"]:
            raw_pa = fields.get(CUSTOM_FIELD_IDS["plataformas_afetadas"])
            if isinstance(raw_pa, list) and raw_pa and isinstance(raw_pa[0], dict):
                plataformas_afetadas = extract_asset_multi(
                    CUSTOM_FIELD_IDS["plataformas_afetadas"]
                )
            elif isinstance(raw_pa, dict) and (
                "objectId" in raw_pa or "id" in raw_pa
            ):
                plataformas_afetadas = extract_asset_multi(
                    CUSTOM_FIELD_IDS["plataformas_afetadas"]
                )
            else:
                plataformas_afetadas = extract_multi_select_field(
                    CUSTOM_FIELD_IDS["plataformas_afetadas"]
                )

        # Converter description para string se for objeto (ADF format)
        description = fields.get("description", "")
        if description is None:
            description = ""
        elif isinstance(description, dict):
            description = JiraClient._adf_to_markdown(description)
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

        result = {
            "key": issue_data.get("key", ""),
            "summary": fields.get("summary", ""),
            "description": description,
            "status": status_name,
            "tipoAtividade": tipo_atividade,
            "documentacaoAnexa": documentacao_anexa,
            "utilizacaoIA": utilizacao_ia,
            "valorEntregue": valor_entregue,
            "plataformasAfetadas": plataformas_afetadas,
            "parentKey": parent_key,
            "parentSummary": parent_summary,
        }
        # Pass through development info only when it was requested (feature enabled)
        if "development" in issue_data and isinstance(issue_data["development"], dict):
            result["development"] = issue_data["development"]
        # When key absent, UI hides the Development block
        return result

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

        fetch_development = bool(
            self._config and self._config.development_panel_enabled()
        )

        class _IssueDetailsWorker(QThread):
            resultReady = Signal("QVariant")
            errorOccurred = Signal(str)

            def __init__(
                self,
                jira_client: JiraClient,
                key: str,
                extra_fields: Optional[List[str]] = None,
                fetch_development: bool = False,
                parent=None,
            ):
                super().__init__(parent)
                self._jira_client = jira_client
                self._key = key
                self._extra_fields = extra_fields or []
                self._fetch_development = fetch_development

            def run(self) -> None:
                try:
                    issue_data = self._jira_client.get_issue_details(
                        self._key.strip(),
                        extra_fields=self._extra_fields if self._extra_fields else None,
                    )
                    if not issue_data:
                        self.resultReady.emit({})
                        return
                    if self._fetch_development:
                        issue_id = issue_data.get("id")
                        if issue_id:
                            dev_info = self._jira_client.get_development_info(
                                str(issue_id)
                            )
                            try:
                                from src.utils.debug import debug_log

                                debug_log(
                                    "JiraService",
                                    "_IssueDetailsWorker.run",
                                    "issue_id=%s dev_info=%s branches=%s pullRequests=%s",
                                    issue_id,
                                    bool(dev_info),
                                    len(dev_info.get("branches", [])) if dev_info else 0,
                                    len(dev_info.get("pullRequests", [])) if dev_info else 0,
                                )
                            except ImportError:
                                pass
                            issue_data["development"] = dev_info if dev_info else {}
                        else:
                            issue_data["development"] = {}
                    # When not requested, do not set "development" so the UI can hide the block
                    self.resultReady.emit(issue_data)
                except Exception as e:  # pragma: no cover - falhas inesperadas
                    self.errorOccurred.emit(str(e))
                    self.resultReady.emit({})

        worker = _IssueDetailsWorker(
            self._jira_client,
            issueKey,
            self._get_assets_extra_fields(),
            fetch_development=fetch_development,
        )
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

    @Slot(str, "QVariant")
    def enrichPullRequests(self, issue_key: str, pr_list: Any) -> None:
        """
        Enriquece lista de PRs com dados do GitHub (reviews/approvals). Emite developmentEnriched(issue_key, enriched_list).
        Não faz nada se token GitHub ou github_enrichment estiver desativado.
        pr_list: list of dicts (from QML can be QVariantList).
        """
        if not issue_key:
            return
        prs = pr_list if isinstance(pr_list, list) else []
        if not prs:
            return
        if not self._config or not self._config.development_panel_github_enrichment():
            return
        token = (self._config.get_github_token() or "").strip()
        if not token:
            return
        if self._development_enrich_worker and self._development_enrich_worker.isRunning():
            return

        class _DevelopmentEnrichWorker(QThread):
            resultReady = Signal(str, "QVariant")

            def __init__(
                self,
                key: str,
                prs: List[Dict[str, Any]],
                gh_token: str,
            ):
                super().__init__()
                self._key = key
                self._prs = prs
                self._token = gh_token

            def run(self) -> None:
                try:
                    import re

                    try:
                        import requests
                    except ImportError:
                        self.resultReady.emit(self._key, self._prs)
                        return
                    headers = {
                        "Accept": "application/vnd.github.v3+json",
                        "Authorization": f"token {self._token}",
                    }
                    enriched = []
                    for pr in self._prs:
                        pr_url = (pr.get("url") or "").strip()
                        if not pr_url:
                            enriched.append(dict(pr))
                            continue
                        # Parse https://github.com/owner/repo/pull/123
                        match = re.search(
                            r"github\.com/([^/]+)/([^/]+)/pull/(\d+)",
                            pr_url,
                            re.IGNORECASE,
                        )
                        if not match:
                            enriched.append(dict(pr))
                            continue
                        owner, repo, number = match.group(1), match.group(2), match.group(3)
                        row = dict(pr)
                        try:
                            r = requests.get(
                                f"https://api.github.com/repos/{owner}/{repo}/pulls/{number}",
                                headers=headers,
                                timeout=10,
                            )
                            if r.ok:
                                data = r.json()
                                row["mergeableState"] = data.get("mergeable_state") or ""
                            rev = requests.get(
                                f"https://api.github.com/repos/{owner}/{repo}/pulls/{number}/reviews",
                                headers=headers,
                                timeout=10,
                            )
                            if rev.ok:
                                reviews = rev.json() or []
                                approvals = sum(
                                    1 for x in reviews if (x.get("state") or "").upper() == "APPROVED"
                                )
                                changes = any(
                                    (x.get("state") or "").upper() == "CHANGES_REQUESTED"
                                    for x in reviews
                                )
                                row["approvalsCount"] = approvals
                                row["changesRequested"] = changes
                        except Exception:
                            pass
                        enriched.append(row)
                    self.resultReady.emit(self._key, enriched)
                except Exception:
                    self.resultReady.emit(self._key, self._prs)

        worker = _DevelopmentEnrichWorker(
            issue_key.strip(), list(prs), token
        )
        self._development_enrich_worker = worker

        def _on_enriched(key: str, enriched_list: Any) -> None:
            self.developmentEnriched.emit(key, enriched_list)
            if self._development_enrich_worker is worker:
                self._development_enrich_worker = None

        def _cleanup() -> None:
            if self._development_enrich_worker is worker:
                self._development_enrich_worker = None

        worker.resultReady.connect(_on_enriched)
        worker.finished.connect(_cleanup)
        worker.start()

    @Slot(str, "QVariant")
    def enrichBranches(self, issue_key: str, branch_list: Any) -> None:
        """
        Enriquece lista de branches com ahead/behind do GitHub (compare API).
        Emite developmentBranchesEnriched(issue_key, enriched_list).
        Só executa se github_enrichment estiver ativado.
        """
        try:
            from src.utils.debug import debug_log

            debug_log(
                "JiraService",
                "enrichBranches",
                "issue_key=%s branches_count=%s config=%s github_enrichment=%s",
                issue_key or "",
                len(branch_list) if isinstance(branch_list, list) else 0,
                "ok" if self._config else "null",
                self._config.development_panel_github_enrichment() if self._config else False,
            )
        except ImportError:
            pass
        if not issue_key:
            return
        branches = branch_list if isinstance(branch_list, list) else []
        if not branches:
            return
        if not self._config or not self._config.development_panel_github_enrichment():
            return
        token = (self._config.get_github_token() or "").strip()
        if not token:
            return
        if self._development_branches_enrich_worker and self._development_branches_enrich_worker.isRunning():
            return

        class _BranchesEnrichWorker(QThread):
            resultReady = Signal(str, "QVariant")

            def __init__(self, key: str, brs: List[Dict[str, Any]], gh_token: str):
                super().__init__()
                self._key = key
                self._branches = brs
                self._token = gh_token

            def run(self) -> None:
                try:
                    import re

                    try:
                        import requests
                    except ImportError:
                        self.resultReady.emit(self._key, self._branches)
                        return
                    headers = {
                        "Accept": "application/vnd.github.v3+json",
                        "Authorization": f"token {self._token}",
                    }
                    enriched = []
                    for br in self._branches:
                        br_url = (br.get("url") or "").strip()
                        br_name = (br.get("name") or "").strip()
                        if not br_url or not br_name:
                            enriched.append(dict(br))
                            continue
                        match = re.search(
                            r"github\.com/([^/]+)/([^/]+)/tree/",
                            br_url,
                            re.IGNORECASE,
                        )
                        if not match:
                            enriched.append(dict(br))
                            continue
                        owner, repo = match.group(1), match.group(2)
                        row = dict(br)
                        for base in ("production", "main", "master"):
                            try:
                                r = requests.get(
                                    f"https://api.github.com/repos/{owner}/{repo}/compare/{base}...{br_name}",
                                    headers=headers,
                                    timeout=10,
                                )
                                if r.ok:
                                    data = r.json()
                                    row["commitsAhead"] = int(
                                        data.get("ahead_by", 0) or 0
                                    )
                                    row["commitsBehind"] = int(
                                        data.get("behind_by", 0) or 0
                                    )
                                    try:
                                        from src.utils.debug import debug_log

                                        debug_log(
                                            "JiraService",
                                            "enrichBranches",
                                            "branch=%s base=%s ahead=%s behind=%s",
                                            br_name,
                                            base,
                                            row["commitsAhead"],
                                            row["commitsBehind"],
                                        )
                                    except ImportError:
                                        pass
                                    break
                            except Exception:
                                pass
                        enriched.append(row)
                    try:
                        from src.utils.debug import debug_log

                        debug_log(
                            "JiraService",
                            "enrichBranches",
                            "emitting developmentBranchesEnriched count=%s",
                            len(enriched),
                        )
                    except ImportError:
                        pass
                    self.resultReady.emit(self._key, enriched)
                except Exception:
                    self.resultReady.emit(self._key, self._branches)

        worker = _BranchesEnrichWorker(
            issue_key.strip(), list(branches), token
        )
        self._development_branches_enrich_worker = worker

        def _on_branches_enriched(key: str, enriched_list: Any) -> None:
            self.developmentBranchesEnriched.emit(key, enriched_list)
            if self._development_branches_enrich_worker is worker:
                self._development_branches_enrich_worker = None

        def _cleanup_br() -> None:
            if self._development_branches_enrich_worker is worker:
                self._development_branches_enrich_worker = None

        worker.resultReady.connect(_on_branches_enriched)
        worker.finished.connect(_cleanup_br)
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
            server_url = getattr(self._jira_client, "_server_url", None)
            if server_url:
                return f"{server_url}/browse/{issueKey.strip()}"
        except Exception:
            pass

        # Fallback: tentar construir URL baseado na chave
        # Assumir formato padrão: https://<project>.atlassian.net
        if "-" in issueKey:
            project = issueKey.split("-")[0]
            return f"https://{project.lower()}.atlassian.net/browse/{issueKey.strip()}"

        return ""

    @Slot(result=str)
    def getAccountId(self) -> str:
        """
        Retorna o accountId do usuário atual (para comparar com author dos comentários).
        Lê do config; retorna string vazia se não configurado.
        """
        if not self._config:
            return ""
        try:
            aid = self._config.get_account_id()
            return aid if aid is not None else ""
        except Exception:
            return ""

    @Slot(str)
    def getCommentsAsync(self, issueKey: str) -> None:
        """
        Carrega comentários da issue em thread. Emite commentsLoaded(list) ou errorOccurred(str).
        """
        if not self._jira_client:
            self.errorOccurred.emit("Cliente Jira não inicializado")
            return
        if not issueKey or not issueKey.strip():
            self.errorOccurred.emit("Chave da issue é obrigatória")
            return
        if self._comments_worker and self._comments_worker.isRunning():
            return
        key = issueKey.strip()

        class _CommentsLoadWorker(QThread):
            resultReady = Signal("QVariantList")
            errorOccurred = Signal(str)

            def __init__(self, jira_client: JiraClient, issue_key: str):
                super().__init__()
                self._client = jira_client
                self._key = issue_key

            def run(self) -> None:
                try:
                    comments = self._client.get_issue_comments(self._key)
                    self.resultReady.emit(comments)
                except Exception as e:
                    self.errorOccurred.emit(str(e))

        worker = _CommentsLoadWorker(self._jira_client, key)

        def _on_result(comments: list):
            self.commentsLoaded.emit(comments)
            self._comments_worker = None

        def _on_error(msg: str):
            self.errorOccurred.emit(msg)
            self._comments_worker = None

        def _cleanup():
            if self._comments_worker is worker:
                self._comments_worker = None

        worker.resultReady.connect(_on_result)
        worker.errorOccurred.connect(_on_error)
        worker.finished.connect(_cleanup)
        self._comments_worker = worker
        worker.start()

    @Slot(str, str, result=bool)
    def addComment(self, issueKey: str, body: str) -> bool:
        """
        Adiciona comentário à issue (síncrono). Emite commentAdded(issueKey, commentDict) em sucesso.
        Retorna True se iniciado com sucesso (operação é síncrona).
        """
        if not self._jira_client:
            self.errorOccurred.emit("Cliente Jira não inicializado")
            return False
        if not issueKey or not issueKey.strip():
            return False
        try:
            comment = self._jira_client.add_comment(issueKey.strip(), body or "")
            if comment:
                self.commentAdded.emit(issueKey.strip(), comment)
                return True
            self.errorOccurred.emit("Falha ao adicionar comentário")
            return False
        except Exception as e:
            self.errorOccurred.emit(str(e))
            return False

    @Slot(str, str, str, result=bool)
    def updateComment(self, issueKey: str, commentId: str, body: str) -> bool:
        """
        Atualiza comentário. Emite commentUpdated(issueKey, commentId, commentDict) em sucesso.
        """
        if not self._jira_client:
            self.errorOccurred.emit("Cliente Jira não inicializado")
            return False
        if not issueKey or not commentId:
            return False
        try:
            comment = self._jira_client.update_comment(
                issueKey.strip(), commentId, body or ""
            )
            if comment:
                self.commentUpdated.emit(issueKey.strip(), commentId, comment)
                return True
            self.errorOccurred.emit("Falha ao atualizar comentário")
            return False
        except Exception as e:
            self.errorOccurred.emit(str(e))
            return False

    @Slot(str, str, result=bool)
    def deleteComment(self, issueKey: str, commentId: str) -> bool:
        """
        Remove comentário. Emite commentDeleted(issueKey, commentId) em sucesso.
        """
        if not self._jira_client:
            self.errorOccurred.emit("Cliente Jira não inicializado")
            return False
        if not issueKey or not commentId:
            return False
        try:
            ok = self._jira_client.delete_comment(issueKey.strip(), commentId)
            if ok:
                self.commentDeleted.emit(issueKey.strip(), commentId)
                return True
            self.errorOccurred.emit("Falha ao excluir comentário")
            return False
        except Exception as e:
            self.errorOccurred.emit(str(e))
            return False
