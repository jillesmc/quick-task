"""
Serviço para gerenciar timer e Pomodoro
"""

import time
from datetime import datetime
from typing import Optional

from PySide6.QtCore import QObject, QTimer, Signal, Slot  # type: ignore[import]

from config.config_manager import ConfigManager
from src.database.worklog_db import WorklogDatabase
from src.models.timer_model import PomodoroSession, TimerModel, TimerState
from src.utils.debug import debug_log


class TimerService(QObject):
    """Serviço para gerenciar timer e técnica Pomodoro"""

    # Sinais
    tick = Signal(int)  # segundos decorridos
    pomodoroCompleted = Signal(int)  # número do Pomodoro
    breakSuggested = Signal(str)  # "short" ou "long"

    def __init__(
        self,
        timer_model: TimerModel,
        config_manager: Optional[ConfigManager] = None,
        worklog_db: Optional[WorklogDatabase] = None,
        parent=None
    ):
        super().__init__(parent)
        self._timer_model = timer_model
        self._config_manager = config_manager or ConfigManager()
        self._worklog_db = worklog_db
        
        # Timer para atualização a cada segundo
        self._timer = QTimer(self)
        self._timer.timeout.connect(self._on_tick)
        self._timer.setInterval(1000)  # 1 segundo
        
        # Estado interno
        self._start_time: Optional[float] = None
        self._paused_elapsed = 0
        self._is_running = False
        
        # Configurações de Pomodoro
        self._load_pomodoro_config()

    def _load_pomodoro_config(self) -> None:
        """Carrega configurações de Pomodoro do config"""
        pomodoro_config = self._config_manager.get_pomodoro_config()
        self._pomodoro_enabled = pomodoro_config.get("enabled", True)
        self._pomodoro_duration_seconds = pomodoro_config.get("pomodoro_duration_minutes", 25) * 60
        self._short_break_seconds = pomodoro_config.get("short_break_minutes", 5) * 60
        self._long_break_seconds = pomodoro_config.get("long_break_minutes", 15) * 60
        self._pomodoros_before_long_break = pomodoro_config.get("pomodoros_before_long_break", 4)
        debug_log("TimerService", "_load_pomodoro_config", "Configurações carregadas: enabled=%s, duration=%ds", 
                 self._pomodoro_enabled, self._pomodoro_duration_seconds)

    @Slot(str)
    def start(self, issue_key: str) -> None:
        """Inicia o timer para uma issue"""
        # Se já está rodando, não fazer nada
        if self._is_running or self._timer_model.state == TimerState.RUNNING.value:
            debug_log("TimerService", "start", "Timer já está rodando - estado: %s, is_running: %s", 
                     self._timer_model.state, self._is_running)
            return

        debug_log("TimerService", "start", "Iniciando timer para issue: %s", issue_key)
        debug_log("TimerService", "start", "Estado antes: %s, is_running: %s", 
                 self._timer_model.state, self._is_running)
        
        # Parar timer anterior se estiver rodando (por segurança)
        if self._timer.isActive():
            self._timer.stop()
        
        # Iniciar sessão no modelo primeiro (isso muda o estado)
        self._timer_model.start_session(issue_key)
        
        # Verificar se realmente iniciou
        if self._timer_model.state != TimerState.RUNNING.value:
            debug_log("TimerService", "start", "Erro: estado não mudou para RUNNING após start_session. Estado atual: %s", 
                     self._timer_model.state)
            return
        
        # Configurar estado interno
        self._start_time = time.time()
        self._paused_elapsed = 0
        self._is_running = True
        
        # Iniciar timer
        self._timer.start()
        
        debug_log("TimerService", "start", "Timer iniciado com sucesso - estado: %s, is_running: %s, timer ativo: %s", 
                 self._timer_model.state, self._is_running, self._timer.isActive())

    @Slot()
    def pause(self) -> None:
        """Pausa o timer"""
        if not self._is_running:
            debug_log("TimerService", "pause", "Timer não está rodando")
            return

        debug_log("TimerService", "pause", "Pausando timer")
        self._timer.stop()
        if self._start_time:
            elapsed = time.time() - self._start_time
            self._paused_elapsed += elapsed
            self._start_time = None
        self._is_running = False
        self._timer_model.pause_session()

    @Slot()
    def resume(self) -> None:
        """Retoma o timer pausado"""
        if self._is_running:
            debug_log("TimerService", "resume", "Timer já está rodando")
            return

        debug_log("TimerService", "resume", "Retomando timer")
        self._start_time = time.time()
        self._is_running = True
        self._timer.start()
        self._timer_model.resume_session()

    @Slot()
    def stop(self) -> None:
        """Para o timer e salva a sessão no banco de dados"""
        debug_log("TimerService", "stop", "Parando timer")
        self._timer.stop()
        self._is_running = False
        
        # Obter sessão antes de resetar
        session = self._timer_model.stop_session()
        
        # Resetar estado
        self._start_time = None
        self._paused_elapsed = 0
        
        # Salvar sessão no banco de dados se disponível
        if session and self._worklog_db:
            try:
                from datetime import datetime
                pomodoros_data = [p.to_dict() for p in session.pomodoros]
                
                self._worklog_db.save_session(
                    session_id=session.id,
                    issue_key=session.issue_key,
                    start_time=session.start_time,
                    end_time=session.end_time,
                    duration_seconds=session.duration_seconds,
                    pomodoros=pomodoros_data,
                    description=session.description,
                )
                debug_log("TimerService", "stop", "Sessão salva no banco: %s", session.id)
                self._timer_model.sessionSaved.emit(session.id)
            except Exception as e:
                debug_log("TimerService", "stop", "Erro ao salvar sessão: %s", e)

    def _on_tick(self) -> None:
        """Callback chamado a cada segundo"""
        if not self._is_running or not self._start_time:
            return

        elapsed = time.time() - self._start_time
        total_elapsed = int(self._paused_elapsed + elapsed)
        
        # Atualizar modelo
        self._timer_model.elapsedSeconds = total_elapsed
        self.tick.emit(total_elapsed)
        
        # Verificar se completou um Pomodoro
        if self._pomodoro_enabled and total_elapsed > 0:
            pomodoros_completed = total_elapsed // self._pomodoro_duration_seconds
            current_pomodoro = self._timer_model.currentPomodoro
            
            if pomodoros_completed > current_pomodoro:
                # Novo Pomodoro completado
                new_pomodoro = pomodoros_completed
                self._timer_model.currentPomodoro = new_pomodoro
                self._timer_model.pomodorosToday += 1
                
                # Criar PomodoroSession
                pomodoro_start = datetime.now()
                pomodoro_start = pomodoro_start.replace(
                    second=0,
                    microsecond=0
                )
                pomodoro_start = pomodoro_start.replace(
                    second=total_elapsed % self._pomodoro_duration_seconds
                )
                # Ajustar para o início do Pomodoro
                pomodoro_start = pomodoro_start.replace(
                    second=(total_elapsed - (new_pomodoro - 1) * self._pomodoro_duration_seconds) % self._pomodoro_duration_seconds
                )
                
                # Simplificar: usar tempo atual como fim
                pomodoro_end = datetime.now()
                
                pomodoro = PomodoroSession(
                    id=f"pomodoro_{new_pomodoro}_{int(time.time())}",
                    start_time=pomodoro_start,
                    end_time=pomodoro_end,
                    duration_seconds=self._pomodoro_duration_seconds,
                )
                
                self._timer_model.add_pomodoro(pomodoro)
                self.pomodoroCompleted.emit(new_pomodoro)
                
                # Sugerir pausa
                if new_pomodoro % self._pomodoros_before_long_break == 0:
                    self.breakSuggested.emit("long")
                else:
                    self.breakSuggested.emit("short")
                
                debug_log("TimerService", "_on_tick", "Pomodoro %d completado", new_pomodoro)

    def get_elapsed_seconds(self) -> int:
        """Retorna segundos decorridos"""
        if not self._is_running or not self._start_time:
            return int(self._paused_elapsed)
        
        elapsed = time.time() - self._start_time
        return int(self._paused_elapsed + elapsed)

    def is_running(self) -> bool:
        """Verifica se o timer está rodando"""
        return self._is_running

    def reload_config(self) -> None:
        """Recarrega configurações de Pomodoro"""
        self._load_pomodoro_config()
