"""
Serviço para sincronizar worklogs pendentes com Jira
"""

from datetime import datetime
from typing import List, Optional

from PySide6.QtCore import QObject, QThread, Signal, Slot  # type: ignore[import]

from config.config_manager import ConfigManager
from core.jira_client import JiraClient
from src.database.worklog_db import WorklogDatabase
from src.utils.debug import debug_log


class SyncWorker(QThread):
    """Worker thread para sincronização assíncrona de worklogs"""
    
    progressUpdated = Signal(int, int)  # current, total
    sessionSynced = Signal(str, str)  # session_id, jira_worklog_id
    sessionError = Signal(str, str)  # session_id, error_message
    finished = Signal()
    
    def __init__(
        self,
        jira_client: JiraClient,
        worklog_db: WorklogDatabase,
        session_ids: List[str],
        timezone: str,
        parent=None
    ):
        super().__init__(parent)
        self._jira_client = jira_client
        self._worklog_db = worklog_db
        self._session_ids = session_ids
        self._timezone = timezone
    
    def run(self):
        """Executa a sincronização em thread separada"""
        total = len(self._session_ids)
        synced = 0
        
        debug_log("SyncWorker", "run", "Iniciando sincronização de %d worklogs", total)
        
        for i, session_id in enumerate(self._session_ids):
            try:
                # Obter sessão do banco
                session = self._worklog_db.get_session(session_id)
                if not session:
                    debug_log("SyncWorker", "run", "Sessão %s não encontrada", session_id)
                    self.sessionError.emit(session_id, "Sessão não encontrada")
                    continue
                
                # Converter duração para formato do Jira
                duration_minutes = session["duration_seconds"] // 60
                time_spent = self._format_duration_minutes(duration_minutes)
                
                # Converter start_time para formato do Jira
                start_time = datetime.fromisoformat(session["start_time"])
                started_str = start_time.strftime("%Y-%m-%d %H:%M:%S")
                
                # Enviar para Jira
                debug_log("SyncWorker", "run", "Enviando worklog para Jira: issue=%s, duration=%s", 
                         session["issue_key"], time_spent)
                
                success = self._jira_client.register_worklog(
                    issue_key=session["issue_key"],
                    time_spent=time_spent,
                    started=started_str,
                    timezone=self._timezone,
                    comment=session.get("description", "") or None,
                )
                
                if success:
                    # Marcar como sincronizado (precisamos do worklog_id, mas register_worklog não retorna)
                    # Por enquanto, marcamos como sincronizado sem o ID
                    # TODO: Modificar register_worklog para retornar o ID do worklog_id
                    self._worklog_db.mark_as_synced(session_id, "synced")
                    synced += 1
                    self.sessionSynced.emit(session_id, "synced")
                    debug_log("SyncWorker", "run", "Worklog sincronizado com sucesso: %s", session_id)
                else:
                    error_msg = "Erro ao registrar worklog no Jira"
                    self.sessionError.emit(session_id, error_msg)
                    debug_log("SyncWorker", "run", "Erro ao sincronizar: %s", session_id)
                
            except Exception as e:
                error_msg = str(e)
                self.sessionError.emit(session_id, error_msg)
                debug_log("SyncWorker", "run", "Exceção ao sincronizar %s: %s", session_id, e)
            
            # Emitir progresso
            self.progressUpdated.emit(i + 1, total)
        
        debug_log("SyncWorker", "run", "Sincronização concluída: %d/%d", synced, total)
        self.finished.emit()
    
    def _format_duration_minutes(self, minutes: int) -> str:
        """Formata duração em minutos para formato do Jira (ex: "1h 30m")"""
        hours = minutes // 60
        mins = minutes % 60
        
        parts = []
        if hours > 0:
            parts.append(f"{hours}h")
        if mins > 0:
            parts.append(f"{mins}m")
        
        return " ".join(parts) if parts else "0m"


class WorklogSyncService(QObject):
    """Serviço para sincronizar worklogs pendentes com Jira"""
    
    # Sinais
    syncStarted = Signal()
    syncProgress = Signal(int, int)  # current, total
    syncCompleted = Signal(int)  # número de worklogs sincronizados
    syncError = Signal(str, str)  # session_id, error_message
    sessionSynced = Signal(str, str)  # session_id, jira_worklog_id
    
    def __init__(
        self,
        worklog_db: WorklogDatabase,
        config_manager: Optional[ConfigManager] = None,
        parent=None
    ):
        super().__init__(parent)
        self._worklog_db = worklog_db
        self._config_manager = config_manager or ConfigManager()
        self._sync_worker: Optional[SyncWorker] = None
        self._jira_client: Optional[JiraClient] = None
    
    def _get_jira_client(self) -> Optional[JiraClient]:
        """Obtém instância do JiraClient"""
        if self._jira_client is None:
            try:
                jira_config_path = self._config_manager.get_jira_cli_config_path()
                account_id = self._config_manager.get_account_id()
                self._jira_client = JiraClient(
                    jira_cli_config_path=jira_config_path,
                    account_id=account_id
                )
            except Exception as e:
                debug_log("WorklogSyncService", "_get_jira_client", "Erro ao criar JiraClient: %s", e)
                return None
        return self._jira_client
    
    @Slot(result="QVariantList")
    def get_pending_worklogs(self):
        """
        Obtém lista de worklogs pendentes para exibição no QML
        
        Returns:
            Lista de dicionários com dados das sessões pendentes
        """
        pending = self._worklog_db.get_pending_worklogs()
        debug_log("WorklogSyncService", "get_pending_worklogs", "Retornando %d worklogs pendentes", len(pending))
        return pending
    
    @Slot("QVariantList", result=bool)
    def sync_pending_worklogs(self, session_ids=None) -> bool:
        """
        Sincroniza worklogs pendentes com Jira
        
        Args:
            session_ids: Lista de IDs de sessões para sincronizar (QVariantList do QML).
                        Se None ou vazia, sincroniza todos os pendentes.
        
        Returns:
            True se a sincronização foi iniciada, False caso contrário
        """
        jira_client = self._get_jira_client()
        if not jira_client:
            debug_log("WorklogSyncService", "sync_pending_worklogs", "JiraClient não disponível")
            return False
        
        # Converter QVariantList para lista Python se necessário
        if session_ids is None:
            pending_sessions = self._worklog_db.get_pending_worklogs()
            session_ids = [s["id"] for s in pending_sessions]
        elif isinstance(session_ids, (list, tuple)) and len(session_ids) == 0:
            # Lista vazia - sincronizar todos
            pending_sessions = self._worklog_db.get_pending_worklogs()
            session_ids = [s["id"] for s in pending_sessions]
        else:
            # Converter para lista Python se for QVariantList ou lista do QML
            try:
                session_ids = list(session_ids) if hasattr(session_ids, '__iter__') and not isinstance(session_ids, str) else [session_ids]
            except:
                session_ids = [str(session_ids)]
        
        if not session_ids:
            debug_log("WorklogSyncService", "sync_pending_worklogs", "Nenhum worklog pendente")
            return False
        
        # Cancelar worker anterior se existir
        if self._sync_worker and self._sync_worker.isRunning():
            debug_log("WorklogSyncService", "sync_pending_worklogs", "Cancelando worker anterior")
            self._sync_worker.terminate()
            self._sync_worker.wait()
        
        # Obter timezone
        timezone = self._config_manager.get_timezone()
        
        # Criar novo worker
        self._sync_worker = SyncWorker(
            jira_client=jira_client,
            worklog_db=self._worklog_db,
            session_ids=session_ids,
            timezone=timezone,
            parent=self
        )
        
        # Conectar sinais
        self._sync_worker.progressUpdated.connect(self.syncProgress.emit)
        self._sync_worker.sessionSynced.connect(self._on_session_synced)
        self._sync_worker.sessionError.connect(self.syncError.emit)
        self._sync_worker.finished.connect(self._on_sync_finished)
        
        # Iniciar sincronização
        debug_log("WorklogSyncService", "sync_pending_worklogs", "Iniciando sincronização de %d worklogs", len(session_ids))
        self.syncStarted.emit()
        self._sync_worker.start()
        
        return True
    
    def _on_session_synced(self, session_id: str, jira_worklog_id: str) -> None:
        """Callback quando uma sessão é sincronizada"""
        self.sessionSynced.emit(session_id, jira_worklog_id)
    
    def _on_sync_finished(self) -> None:
        """Callback quando a sincronização termina"""
        # Contar quantos foram sincronizados
        pending = self._worklog_db.get_pending_worklogs()
        total_pending_before = len(pending) + (self._sync_worker._session_ids if self._sync_worker else [])
        # Estimativa: assumir que todos foram sincronizados se não houver erros
        # Na prática, isso seria calculado durante a sincronização
        synced_count = len(self._sync_worker._session_ids) if self._sync_worker else 0
        self.syncCompleted.emit(synced_count)
        debug_log("WorklogSyncService", "_on_sync_finished", "Sincronização concluída: %d worklogs", synced_count)
    
    @Slot(str, result=bool)
    def delete_worklog(self, session_id: str) -> bool:
        """
        Deleta um worklog pendente do banco de dados
        
        Args:
            session_id: ID da sessão a ser deletada
        
        Returns:
            True se deletado com sucesso, False caso contrário
        """
        if not session_id:
            debug_log("WorklogSyncService", "delete_worklog", "Session ID vazio")
            return False
        
        try:
            self._worklog_db.delete_session(session_id)
            debug_log("WorklogSyncService", "delete_worklog", "Worklog deletado: %s", session_id)
            # Emitir sinal para atualizar UI
            self.sessionSynced.emit(session_id, "deleted")
            return True
        except Exception as e:
            debug_log("WorklogSyncService", "delete_worklog", "Erro ao deletar worklog %s: %s", session_id, e)
            return False
