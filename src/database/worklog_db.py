"""
Gerenciador de banco de dados SQLite para worklogs locais
"""

import json
import os
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from src.utils.debug import debug_log


class WorklogDatabase:
    """Gerencia armazenamento local de worklogs em SQLite"""

    def __init__(self, db_path: Optional[Path] = None):
        """
        Inicializa o banco de dados
        
        Args:
            db_path: Caminho para o arquivo de banco de dados.
                    Se None, usa o mesmo diretório que ConfigManager (XDG_CONFIG_HOME/jira-quick-task/)
        """
        if db_path is None:
            # Usar o mesmo diretório que ConfigManager para manter consistência
            xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
            db_path = Path(xdg_config) / "jira-quick-task" / "worklogs.db"
        
        self.db_path = Path(db_path)
        self._init_database()

    def _init_database(self) -> None:
        """Cria tabelas se não existirem"""
        # Garantir que o diretório existe
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        
        debug_log("WorklogDatabase", "_init_database", "Inicializando banco de dados em: %s", self.db_path)
        
        conn = sqlite3.connect(str(self.db_path))
        cursor = conn.cursor()
        
        # Tabela de sessões de worklog
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS worklog_sessions (
                id TEXT PRIMARY KEY,
                issue_key TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT,
                duration_seconds INTEGER NOT NULL,
                pomodoros_json TEXT,
                is_synced BOOLEAN DEFAULT 0,
                jira_worklog_id TEXT,
                description TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # Índices para melhor performance
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_issue_key 
            ON worklog_sessions(issue_key)
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_is_synced 
            ON worklog_sessions(is_synced)
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_start_time 
            ON worklog_sessions(start_time)
        """)
        
        conn.commit()
        conn.close()
        
        debug_log("WorklogDatabase", "_init_database", "Banco de dados inicializado com sucesso")

    def save_session(
        self,
        session_id: str,
        issue_key: str,
        start_time: datetime,
        end_time: Optional[datetime],
        duration_seconds: int,
        pomodoros: Optional[List[Dict[str, Any]]] = None,
        description: str = "",
    ) -> None:
        """
        Salva uma sessão de worklog no banco de dados
        
        Args:
            session_id: ID único da sessão
            issue_key: Chave da issue Jira
            start_time: Data/hora de início
            end_time: Data/hora de fim (opcional)
            duration_seconds: Duração em segundos
            pomodoros: Lista de Pomodoros (opcional)
            description: Descrição do trabalho (opcional)
        """
        debug_log("WorklogDatabase", "save_session", "Salvando sessão: %s para issue %s", session_id, issue_key)
        
        conn = sqlite3.connect(str(self.db_path))
        cursor = conn.cursor()
        
        pomodoros_json = json.dumps(pomodoros) if pomodoros else None
        
        cursor.execute("""
            INSERT OR REPLACE INTO worklog_sessions 
            (id, issue_key, start_time, end_time, duration_seconds, 
             pomodoros_json, is_synced, jira_worklog_id, description)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            session_id,
            issue_key,
            start_time.isoformat(),
            end_time.isoformat() if end_time else None,
            duration_seconds,
            pomodoros_json,
            0,  # is_synced = False
            None,  # jira_worklog_id
            description,
        ))
        
        conn.commit()
        conn.close()
        
        debug_log("WorklogDatabase", "save_session", "Sessão salva com sucesso")

    def get_pending_worklogs(self) -> List[Dict[str, Any]]:
        """
        Obtém todas as sessões de worklog não sincronizadas
        
        Returns:
            Lista de dicionários com dados das sessões
        """
        debug_log("WorklogDatabase", "get_pending_worklogs", "Buscando worklogs pendentes")
        
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row  # Permite acesso por nome de coluna
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT * FROM worklog_sessions 
            WHERE is_synced = 0 
            ORDER BY start_time DESC
        """)
        
        rows = cursor.fetchall()
        conn.close()
        
        # Converter para lista de dicionários
        sessions = []
        for row in rows:
            session = {
                "id": row["id"],
                "issue_key": row["issue_key"],
                "start_time": row["start_time"],
                "end_time": row["end_time"],
                "duration_seconds": row["duration_seconds"],
                "pomodoros": json.loads(row["pomodoros_json"]) if row["pomodoros_json"] else [],
                "is_synced": bool(row["is_synced"]),
                "jira_worklog_id": row["jira_worklog_id"],
                "description": row["description"] or "",
                "created_at": row["created_at"],
            }
            sessions.append(session)
        
        debug_log("WorklogDatabase", "get_pending_worklogs", "Encontrados %d worklogs pendentes", len(sessions))
        return sessions

    def get_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        """
        Obtém uma sessão específica por ID
        
        Args:
            session_id: ID da sessão
            
        Returns:
            Dicionário com dados da sessão ou None se não encontrada
        """
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT * FROM worklog_sessions 
            WHERE id = ?
        """, (session_id,))
        
        row = cursor.fetchone()
        conn.close()
        
        if not row:
            return None
        
        return {
            "id": row["id"],
            "issue_key": row["issue_key"],
            "start_time": row["start_time"],
            "end_time": row["end_time"],
            "duration_seconds": row["duration_seconds"],
            "pomodoros": json.loads(row["pomodoros_json"]) if row["pomodoros_json"] else [],
            "is_synced": bool(row["is_synced"]),
            "jira_worklog_id": row["jira_worklog_id"],
            "description": row["description"] or "",
            "created_at": row["created_at"],
        }

    def mark_as_synced(self, session_id: str, jira_worklog_id: str) -> None:
        """
        Marca uma sessão como sincronizada
        
        Args:
            session_id: ID da sessão
            jira_worklog_id: ID do worklog no Jira
        """
        debug_log("WorklogDatabase", "mark_as_synced", "Marcando sessão %s como sincronizada", session_id)
        
        conn = sqlite3.connect(str(self.db_path))
        cursor = conn.cursor()
        
        cursor.execute("""
            UPDATE worklog_sessions 
            SET is_synced = 1, jira_worklog_id = ? 
            WHERE id = ?
        """, (jira_worklog_id, session_id))
        
        conn.commit()
        conn.close()
        
        debug_log("WorklogDatabase", "mark_as_synced", "Sessão marcada como sincronizada")

    def update_session(
        self,
        session_id: str,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        duration_seconds: Optional[int] = None,
        description: Optional[str] = None,
    ) -> None:
        """
        Atualiza uma sessão existente
        
        Args:
            session_id: ID da sessão
            start_time: Nova data/hora de início (opcional)
            end_time: Nova data/hora de fim (opcional)
            duration_seconds: Nova duração em segundos (opcional)
            description: Nova descrição (opcional)
        """
        debug_log("WorklogDatabase", "update_session", "Atualizando sessão: %s", session_id)
        
        conn = sqlite3.connect(str(self.db_path))
        cursor = conn.cursor()
        
        updates = []
        params = []
        
        if start_time is not None:
            updates.append("start_time = ?")
            params.append(start_time.isoformat())
        
        if end_time is not None:
            updates.append("end_time = ?")
            params.append(end_time.isoformat())
        
        if duration_seconds is not None:
            updates.append("duration_seconds = ?")
            params.append(duration_seconds)
        
        if description is not None:
            updates.append("description = ?")
            params.append(description)
        
        if not updates:
            conn.close()
            return
        
        params.append(session_id)
        
        cursor.execute(f"""
            UPDATE worklog_sessions 
            SET {', '.join(updates)}
            WHERE id = ?
        """, params)
        
        conn.commit()
        conn.close()
        
        debug_log("WorklogDatabase", "update_session", "Sessão atualizada com sucesso")

    def delete_session(self, session_id: str) -> None:
        """
        Deleta uma sessão do banco de dados
        
        Args:
            session_id: ID da sessão
        """
        debug_log("WorklogDatabase", "delete_session", "Deletando sessão: %s", session_id)
        
        conn = sqlite3.connect(str(self.db_path))
        cursor = conn.cursor()
        
        cursor.execute("""
            DELETE FROM worklog_sessions 
            WHERE id = ?
        """, (session_id,))
        
        conn.commit()
        conn.close()
        
        debug_log("WorklogDatabase", "delete_session", "Sessão deletada com sucesso")
    
    def delete_all_worklogs(self) -> int:
        """
        Deleta todos os worklogs pendentes do banco de dados
        
        Returns:
            Número de worklogs deletados
        """
        debug_log("WorklogDatabase", "delete_all_worklogs", "Deletando todos os worklogs pendentes")
        
        conn = sqlite3.connect(str(self.db_path))
        cursor = conn.cursor()
        
        cursor.execute("""
            DELETE FROM worklog_sessions 
            WHERE is_synced = 0
        """)
        
        deleted_count = cursor.rowcount
        conn.commit()
        conn.close()
        
        debug_log("WorklogDatabase", "delete_all_worklogs", "%d worklogs deletados", deleted_count)
        return deleted_count

    def get_sessions_by_issue(self, issue_key: str) -> List[Dict[str, Any]]:
        """
        Obtém todas as sessões de uma issue específica
        
        Args:
            issue_key: Chave da issue Jira
            
        Returns:
            Lista de dicionários com dados das sessões
        """
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT * FROM worklog_sessions 
            WHERE issue_key = ?
            ORDER BY start_time DESC
        """, (issue_key,))
        
        rows = cursor.fetchall()
        conn.close()
        
        sessions = []
        for row in rows:
            session = {
                "id": row["id"],
                "issue_key": row["issue_key"],
                "start_time": row["start_time"],
                "end_time": row["end_time"],
                "duration_seconds": row["duration_seconds"],
                "pomodoros": json.loads(row["pomodoros_json"]) if row["pomodoros_json"] else [],
                "is_synced": bool(row["is_synced"]),
                "jira_worklog_id": row["jira_worklog_id"],
                "description": row["description"] or "",
                "created_at": row["created_at"],
            }
            sessions.append(session)
        
        return sessions
