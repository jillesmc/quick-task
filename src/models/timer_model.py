"""
Modelo de dados para timer e sessões de worklog
"""

import os
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional

from PySide6.QtCore import QObject, Property, Signal, Slot  # type: ignore[import]

from src.utils.debug import debug_log

# Helper para escrever logs de debug de forma segura
def _write_debug_log(data: dict) -> None:
    """Escreve log de debug, criando diretório se necessário"""
    try:
        log_path = Path('/home/jilles/data/projects/personal/jira-quick-task/.cursor/debug.log')
        log_path.parent.mkdir(parents=True, exist_ok=True)
        import json
        with open(log_path, 'a') as f:
            f.write(f'{json.dumps(data)}\n')
    except Exception:
        pass  # Ignorar erros de logging para não quebrar a aplicação


class TimerState(Enum):
    """Estados possíveis do timer"""
    IDLE = "idle"
    RUNNING = "running"
    PAUSED = "paused"
    STOPPED = "stopped"


@dataclass
class PomodoroSession:
    """Representa uma sessão de Pomodoro individual"""
    id: str
    start_time: datetime
    end_time: Optional[datetime] = None
    duration_seconds: int = 0
    is_break: bool = False
    break_type: Optional[str] = None  # "short" or "long"

    def to_dict(self) -> Dict[str, Any]:
        """Converte para dicionário para serialização"""
        return {
            "id": self.id,
            "start_time": self.start_time.isoformat(),
            "end_time": self.end_time.isoformat() if self.end_time else None,
            "duration_seconds": self.duration_seconds,
            "is_break": self.is_break,
            "break_type": self.break_type,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "PomodoroSession":
        """Cria instância a partir de dicionário"""
        return cls(
            id=data["id"],
            start_time=datetime.fromisoformat(data["start_time"]),
            end_time=datetime.fromisoformat(data["end_time"]) if data.get("end_time") else None,
            duration_seconds=data.get("duration_seconds", 0),
            is_break=data.get("is_break", False),
            break_type=data.get("break_type"),
        )


@dataclass
class WorklogSession:
    """Representa uma sessão de trabalho com múltiplos Pomodoros"""
    id: str
    issue_key: str
    start_time: datetime
    end_time: Optional[datetime] = None
    duration_seconds: int = 0
    pomodoros: List[PomodoroSession] = field(default_factory=list)
    is_synced: bool = False
    jira_worklog_id: Optional[str] = None
    description: str = ""

    def to_dict(self) -> Dict[str, Any]:
        """Converte para dicionário para serialização"""
        return {
            "id": self.id,
            "issue_key": self.issue_key,
            "start_time": self.start_time.isoformat(),
            "end_time": self.end_time.isoformat() if self.end_time else None,
            "duration_seconds": self.duration_seconds,
            "pomodoros": [p.to_dict() for p in self.pomodoros],
            "is_synced": self.is_synced,
            "jira_worklog_id": self.jira_worklog_id,
            "description": self.description,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "WorklogSession":
        """Cria instância a partir de dicionário"""
        return cls(
            id=data["id"],
            issue_key=data["issue_key"],
            start_time=datetime.fromisoformat(data["start_time"]),
            end_time=datetime.fromisoformat(data["end_time"]) if data.get("end_time") else None,
            duration_seconds=data.get("duration_seconds", 0),
            pomodoros=[PomodoroSession.from_dict(p) for p in data.get("pomodoros", [])],
            is_synced=data.get("is_synced", False),
            jira_worklog_id=data.get("jira_worklog_id"),
            description=data.get("description", ""),
        )


class TimerModel(QObject):
    """Modelo de dados para timer exposto ao QML"""

    # Sinais
    stateChanged = Signal(str)  # TimerState como string
    timeUpdated = Signal(int)  # segundos decorridos
    pomodoroCompleted = Signal(int)  # número do Pomodoro
    sessionSaved = Signal(str)  # session_id
    issueKeyChanged = Signal()
    breakDecisionRequested = Signal(int, str)  # pomodoro_num, break_type
    breakEnded = Signal()  # emitido quando a pausa termina
    isOnBreakChanged = Signal(bool)  # emitido quando isOnBreak muda
    isWaitingBreakDecisionChanged = Signal(bool)  # emitido quando isWaitingBreakDecision muda
    isWaitingBreakEndDecisionChanged = Signal(bool)  # emitido quando isWaitingBreakEndDecision muda

    def __init__(self, parent=None):
        super().__init__(parent)
        self._state = TimerState.IDLE
        self._issue_key = ""
        self._elapsed_seconds = 0
        self._current_pomodoro = 0
        self._current_session: Optional[WorklogSession] = None
        self._pomodoros_today = 0
        self._total_seconds_today = 0
        
        # Estados de pausa e alerta
        self._is_waiting_break_decision = False
        self._is_on_break = False
        self._break_remaining_seconds = 0
        self._break_type = ""  # "short" ou "long"
        self._is_waiting_break_end_decision = False

    @Property(str, notify=stateChanged)
    def state(self) -> str:
        """Estado atual do timer (idle, running, paused, stopped)"""
        return self._state.value

    @state.setter
    def state(self, value: str):
        try:
            new_state = TimerState(value)
            if self._state != new_state:
                self._state = new_state
                self.stateChanged.emit(value)
                debug_log("TimerModel", "state.setter", "Estado alterado para: %s", value)
        except ValueError:
            debug_log("TimerModel", "state.setter", "Estado inválido: %s", value)

    @Property(str, notify=issueKeyChanged)
    def issueKey(self) -> str:
        """Chave da issue Jira associada ao timer"""
        return self._issue_key

    @issueKey.setter
    def issueKey(self, value: str):
        if self._issue_key != value:
            self._issue_key = value
            self.issueKeyChanged.emit()
            debug_log("TimerModel", "issueKey.setter", "Issue alterada para: %s", value)

    @Property(int, notify=timeUpdated)
    def elapsedSeconds(self) -> int:
        """Segundos decorridos no timer atual"""
        return self._elapsed_seconds

    @elapsedSeconds.setter
    def elapsedSeconds(self, value: int):
        if self._elapsed_seconds != value:
            self._elapsed_seconds = value
            self.timeUpdated.emit(value)

    @Property(int, notify=pomodoroCompleted)
    def currentPomodoro(self) -> int:
        """Número do Pomodoro atual"""
        return self._current_pomodoro

    @currentPomodoro.setter
    def currentPomodoro(self, value: int):
        if self._current_pomodoro != value:
            # #region agent log
            _write_debug_log({"sessionId":"debug-session","runId":"run1","hypothesisId":"B","location":"timer_model.py:175","message":"currentPomodoro setter - antes de atualizar","data":{"old_value":self._current_pomodoro,"new_value":value},"timestamp":int(time.time()*1000)})
            # #endregion
            self._current_pomodoro = value
            self.pomodoroCompleted.emit(value)
            # #region agent log
            _write_debug_log({"sessionId":"debug-session","runId":"run1","hypothesisId":"B","location":"timer_model.py:178","message":"currentPomodoro setter - depois de atualizar e emitir signal","data":{"current_value":self._current_pomodoro},"timestamp":int(time.time()*1000)})
            # #endregion

    @Property(int, notify=timeUpdated)
    def pomodorosToday(self) -> int:
        """Número de Pomodoros completados hoje"""
        return self._pomodoros_today

    @pomodorosToday.setter
    def pomodorosToday(self, value: int):
        if self._pomodoros_today != value:
            self._pomodoros_today = value
            self.timeUpdated.emit(self._elapsed_seconds)

    @Property(int, notify=timeUpdated)
    def totalSecondsToday(self) -> int:
        """Total de segundos trabalhados hoje"""
        return self._total_seconds_today

    @totalSecondsToday.setter
    def totalSecondsToday(self, value: int):
        if self._total_seconds_today != value:
            self._total_seconds_today = value
            self.timeUpdated.emit(self._elapsed_seconds)

    def start_session(self, issue_key: str) -> None:
        """Inicia uma nova sessão de timer"""
        if self._state == TimerState.RUNNING:
            debug_log("TimerModel", "start_session", "Timer já está rodando")
            return

        self.issueKey = issue_key
        self._elapsed_seconds = 0
        # #region agent log
        _write_debug_log({"sessionId":"debug-session","runId":"run1","hypothesisId":"C","location":"timer_model.py:210","message":"start_session() - resetando currentPomodoro para 0","data":{"issue_key":issue_key,"current_before_reset":self._current_pomodoro},"timestamp":int(time.time()*1000)})
        # #endregion
        self._current_pomodoro = 0
        # #region agent log
        _write_debug_log({"sessionId":"debug-session","runId":"run1","hypothesisId":"C","location":"timer_model.py:210","message":"start_session() - depois de resetar currentPomodoro","data":{"current_after_reset":self._current_pomodoro},"timestamp":int(time.time()*1000)})
        # #endregion
        
        # Criar nova sessão
        self._current_session = WorklogSession(
            id=str(uuid.uuid4()),
            issue_key=issue_key,
            start_time=datetime.now(),
        )
        
        self.state = TimerState.RUNNING.value
        debug_log("TimerModel", "start_session", "Sessão iniciada para issue: %s", issue_key)

    def pause_session(self) -> None:
        """Pausa o timer atual"""
        if self._state != TimerState.RUNNING:
            debug_log("TimerModel", "pause_session", "Timer não está rodando")
            return

        self.state = TimerState.PAUSED.value
        debug_log("TimerModel", "pause_session", "Timer pausado")

    def resume_session(self) -> None:
        """Retoma o timer pausado"""
        if self._state != TimerState.PAUSED:
            debug_log("TimerModel", "resume_session", "Timer não está pausado")
            return

        self.state = TimerState.RUNNING.value
        debug_log("TimerModel", "resume_session", "Timer retomado")

    def stop_session(self) -> Optional[WorklogSession]:
        """Para o timer e retorna a sessão finalizada"""
        if self._state == TimerState.IDLE:
            debug_log("TimerModel", "stop_session", "Timer já está parado")
            return None

        if self._current_session:
            self._current_session.end_time = datetime.now()
            self._current_session.duration_seconds = self._elapsed_seconds
        
        session = self._current_session
        self._current_session = None
        self._elapsed_seconds = 0
        # #region agent log
        _write_debug_log({"sessionId":"debug-session","runId":"run1","hypothesisId":"C","location":"timer_model.py:271","message":"stop_session() - resetando currentPomodoro para 0","data":{"current_before":self._current_pomodoro},"timestamp":int(time.time()*1000)})
        # #endregion
        # Usar setter para notificar QML do reset
        self.currentPomodoro = 0
        self.state = TimerState.IDLE.value
        
        debug_log("TimerModel", "stop_session", "Timer parado, sessão finalizada")
        return session

    def add_pomodoro(self, pomodoro: PomodoroSession) -> None:
        """Adiciona um Pomodoro à sessão atual"""
        if self._current_session:
            self._current_session.pomodoros.append(pomodoro)
            # NÃO calcular currentPomodoro aqui - será atualizado pelo TimerService
            # que mantém o contador acumulado considerando sessões anteriores
            debug_log("TimerModel", "add_pomodoro", "Pomodoro adicionado à sessão (total na sessão: %d)", len(self._current_session.pomodoros))
    
    @Property(bool, notify=timeUpdated)
    def isWaitingBreakDecision(self) -> bool:
        """Flag visual indicando se está aguardando decisão de pausa"""
        return self._is_waiting_break_decision
    
    @isWaitingBreakDecision.setter
    def isWaitingBreakDecision(self, value: bool):
        if self._is_waiting_break_decision != value:
            self._is_waiting_break_decision = value
            self.isWaitingBreakDecisionChanged.emit(value)  # Signal específico
            self.timeUpdated.emit(self._elapsed_seconds)  # Manter para compatibilidade
    
    @Property(bool, notify=timeUpdated)
    def isOnBreak(self) -> bool:
        """Indica se o timer está em pausa (contagem regressiva)"""
        return self._is_on_break
    
    @isOnBreak.setter
    def isOnBreak(self, value: bool):
        if self._is_on_break != value:
            self._is_on_break = value
            self.isOnBreakChanged.emit(value)  # Signal específico
            self.timeUpdated.emit(self._elapsed_seconds)  # Manter para compatibilidade
    
    @Property(int, notify=timeUpdated)
    def breakRemainingSeconds(self) -> int:
        """Segundos restantes da pausa atual"""
        return self._break_remaining_seconds
    
    @breakRemainingSeconds.setter
    def breakRemainingSeconds(self, value: int):
        if self._break_remaining_seconds != value:
            self._break_remaining_seconds = value
            self.timeUpdated.emit(self._elapsed_seconds)
    
    @Property(str, notify=timeUpdated)
    def breakType(self) -> str:
        """Tipo de pausa atual: 'short' ou 'long'"""
        return self._break_type
    
    @breakType.setter
    def breakType(self, value: str):
        if self._break_type != value:
            self._break_type = value
            self.timeUpdated.emit(self._elapsed_seconds)
    
    @Property(bool, notify=timeUpdated)
    def isWaitingBreakEndDecision(self) -> bool:
        """Indica se está aguardando decisão após pausa terminar"""
        return self._is_waiting_break_end_decision
    
    @isWaitingBreakEndDecision.setter
    def isWaitingBreakEndDecision(self, value: bool):
        if self._is_waiting_break_end_decision != value:
            self._is_waiting_break_end_decision = value
            self.isWaitingBreakEndDecisionChanged.emit(value)  # Signal específico
            self.timeUpdated.emit(self._elapsed_seconds)  # Manter para compatibilidade