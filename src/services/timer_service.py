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
    breakDecisionRequested = Signal(int, str)  # pomodoro_num, break_type

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
        
        # Referência à PomodoroSession da pausa atual (para atualizar quando terminar)
        self._current_break_session: Optional[PomodoroSession] = None
        
        # Timer para contagem regressiva da pausa
        self._break_countdown_timer = QTimer(self)
        self._break_countdown_timer.timeout.connect(self._on_break_tick)
        self._break_countdown_timer.setInterval(1000)  # 1 segundo
        
        # Timer para auto-continuação do alerta
        self._break_decision_timeout_timer = QTimer(self)
        self._break_decision_timeout_timer.setSingleShot(True)
        self._break_decision_timeout_timer.timeout.connect(self._on_break_decision_timeout)
        
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
        self._auto_continue_timeout_seconds = pomodoro_config.get("auto_continue_timeout_seconds", 30)
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
        
        # Parar timer anterior se estiver rodando (por segurança)
        if self._timer.isActive():
            self._timer.stop()
        
        # Sempre iniciar nova sessão (não continuar sessão existente)
        self._timer_model.start_session(issue_key)
        # Resetar tempo acumulado para nova sessão
        self._paused_elapsed = 0
        
        # Verificar se realmente iniciou
        if self._timer_model.state != TimerState.RUNNING.value:
            debug_log("TimerService", "start", "Erro: estado não mudou para RUNNING após start_session. Estado atual: %s", 
                     self._timer_model.state)
            return
        
        # Configurar estado interno
        self._start_time = time.time()
        self._is_running = True
        
        # Iniciar timer
        self._timer.start()
        
        debug_log("TimerService", "start", "Timer iniciado com sucesso - estado: %s, is_running: %s, timer ativo: %s", 
                 self._timer_model.state, self._is_running, self._timer.isActive())

    @Slot()
    def pause(self) -> None:
        """
        Pausa o timer iniciando um cronômetro de pausa (curta ou longa)
        baseado no histórico de pausas na sessão atual.
        """
        if not self._is_running:
            debug_log("TimerService", "pause", "Timer não está rodando")
            return
        
        # Se já está em pausa, não fazer nada
        if self._timer_model.isOnBreak or self._timer_model.isWaitingBreakDecision:
            debug_log("TimerService", "pause", "Timer já está em pausa")
            return

        debug_log("TimerService", "pause", "Iniciando pausa com cronômetro")
        
        # Salvar worklog atual antes de pausar
        if self._timer_model._current_session:
            # Finalizar tempo decorrido antes de salvar
            if self._start_time:
                elapsed = time.time() - self._start_time
                self._paused_elapsed += elapsed
                self._start_time = None
            
            # Atualizar elapsedSeconds no modelo antes de salvar
            self._timer_model.elapsedSeconds = int(self._paused_elapsed)
            
            # Salvar sessão atual
            session = self._timer_model.stop_session()
            if session and self._worklog_db:
                try:
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
                    debug_log("TimerService", "pause", "Worklog salvo antes de pausar: %s", session.id)
                    self._timer_model.sessionSaved.emit(session.id)
                except Exception as e:
                    debug_log("TimerService", "pause", "Erro ao salvar sessão: %s", e)
            
            # Limpar sessão mas manter issue key
            # (issue key será mantida no modelo, não limpar aqui)
        
        # Resetar tempo acumulado (novo worklog começará após pausa)
        self._paused_elapsed = 0
        
        # Determinar tipo de pausa baseado no histórico
        break_type = self._determine_break_type()
        
        # Parar timer
        self._timer.stop()
        self._is_running = False
        
        # Mudar estado do modelo para IDLE durante a pausa
        self._timer_model.state = TimerState.IDLE.value
        
        # Criar PomodoroSession para a pausa (não adicionar à sessão - sessão foi salva)
        break_start = datetime.now()
        break_session = PomodoroSession(
            id=f"break_{break_type}_{int(time.time())}",
            start_time=break_start,
            is_break=True,
            break_type=break_type,
        )
        
        # Guardar referência para atualizar quando terminar (não adicionar à sessão)
        self._current_break_session = break_session
        
        # Determinar duração da pausa
        if break_type == "long":
            break_duration_seconds = self._long_break_seconds
        else:
            break_duration_seconds = self._short_break_seconds
        
        # Iniciar contagem regressiva da pausa
        self._timer_model.isOnBreak = True
        self._timer_model.breakType = break_type
        self._timer_model.breakRemainingSeconds = break_duration_seconds
        self._timer_model.isWaitingBreakDecision = False
        
        # Iniciar timer de contagem regressiva
        self._break_countdown_timer.start()
        
        debug_log("TimerService", "pause", "Pausa iniciada: tipo=%s, duração=%ds", break_type, break_duration_seconds)

    @Slot()
    def resume(self) -> None:
        """
        Retoma o timer - DEPRECADO: pausas agora usam cronômetro.
        Este método não faz mais sentido, mas é mantido para compatibilidade.
        Se estiver em isWaitingBreakEndDecision, chama continueAfterBreak().
        """
        # Se está esperando decisão após pausa terminar, continuar
        if self._timer_model.isWaitingBreakEndDecision:
            debug_log("TimerService", "resume", "Pausa terminou, continuando via continueAfterBreak")
            self.continueAfterBreak()
            return
        
        # Caso contrário, não fazer nada (pausa só termina quando cronômetro acaba)
        debug_log("TimerService", "resume", "Resume não é mais suportado - pausas usam cronômetro")

    @Slot()
    def stop(self) -> None:
        """Para o timer e salva a sessão no banco de dados"""
        debug_log("TimerService", "stop", "Parando timer")
        self._timer.stop()
        self._is_running = False
        
        # Parar cronômetro de pausa se estiver ativo
        if self._break_countdown_timer.isActive():
            self._break_countdown_timer.stop()
            debug_log("TimerService", "stop", "Cronômetro de pausa parado")
        
        # Cancelar timer de auto-continuação se estiver ativo
        if self._break_decision_timeout_timer.isActive():
            self._break_decision_timeout_timer.stop()
        
        # Limpar estados de pausa
        self._timer_model.isOnBreak = False
        self._timer_model.isWaitingBreakDecision = False
        self._timer_model.isWaitingBreakEndDecision = False
        self._current_break_session = None
        
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
        
        # Limpar issue key após salvar
        self._timer_model.issueKey = ""
        debug_log("TimerService", "stop", "Issue key limpa após parar timer")

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
                # NÃO definir currentPomodoro aqui - add_pomodoro() calculará baseado no tamanho da lista
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
                
                # Determinar tipo de pausa baseado no histórico de pausas realmente feitas
                break_type = self._determine_break_type()
                
                # Emitir sinal de decisão de pausa (novo fluxo)
                self._timer_model.isWaitingBreakDecision = True
                # Emitir do timerModel (QML escuta timerModel.breakDecisionRequested)
                self._timer_model.breakDecisionRequested.emit(new_pomodoro, break_type)
                
                # Manter sinal breakSuggested para compatibilidade
                self.breakSuggested.emit(break_type)
                
                # Iniciar timer de auto-continuação
                timeout_seconds = self._auto_continue_timeout_seconds
                self._break_decision_timeout_timer.start(timeout_seconds * 1000)
                
                debug_log("TimerService", "_on_tick", "Pomodoro %d completado, break_type=%s", new_pomodoro, break_type)

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
        """Recarrega configurações de Pomodoro - aplica apenas para novos timers"""
        # Salvar valores antigos para log
        old_pomodoro_duration = self._pomodoro_duration_seconds
        old_auto_continue_timeout = self._auto_continue_timeout_seconds
        old_short_break = self._short_break_seconds
        old_long_break = self._long_break_seconds
        old_pomodoros_before_long = self._pomodoros_before_long_break
        
        # Recarregar configurações
        self._load_pomodoro_config()
        
        # Logar mudanças (se houver)
        changed = []
        if old_pomodoro_duration != self._pomodoro_duration_seconds:
            changed.append(f"pomodoro_duration: {old_pomodoro_duration}s -> {self._pomodoro_duration_seconds}s")
        if old_auto_continue_timeout != self._auto_continue_timeout_seconds:
            changed.append(f"auto_continue_timeout: {old_auto_continue_timeout}s -> {self._auto_continue_timeout_seconds}s")
        if old_short_break != self._short_break_seconds:
            changed.append(f"short_break: {old_short_break}s -> {self._short_break_seconds}s")
        if old_long_break != self._long_break_seconds:
            changed.append(f"long_break: {old_long_break}s -> {self._long_break_seconds}s")
        if old_pomodoros_before_long != self._pomodoros_before_long_break:
            changed.append(f"pomodoros_before_long: {old_pomodoros_before_long} -> {self._pomodoros_before_long_break}")
        
        if changed:
            debug_log("TimerService", "reload_config", 
                     "Configurações recarregadas (aplicarão apenas para novos timers): %s", 
                     ", ".join(changed))
        else:
            debug_log("TimerService", "reload_config", 
                     "Configurações recarregadas (sem mudanças)")
        
        # Confirmar que timers ativos não foram modificados
        if self._break_decision_timeout_timer.isActive():
            debug_log("TimerService", "reload_config", 
                     "Timer de auto-continuação ativo - não modificado (usará novo valor no próximo pomodoro)")
        if self._break_countdown_timer.isActive():
            debug_log("TimerService", "reload_config", 
                     "Timer de pausa ativo - não modificado (usará novo valor na próxima pausa)")
    
    def _count_short_breaks_in_session(self) -> int:
        """Conta quantas pausas curtas foram feitas na sessão atual"""
        if not self._timer_model._current_session:
            return 0
        
        count = 0
        for pomodoro in self._timer_model._current_session.pomodoros:
            if pomodoro.is_break and pomodoro.break_type == "short":
                count += 1
        
        debug_log("TimerService", "_count_short_breaks_in_session", 
                 "Pausas curtas na sessão: %d", count)
        return count
    
    def _determine_break_type(self) -> str:
        """
        Determina o tipo de pausa (curta/longa) baseado no histórico de pausas
        realmente feitas na sessão atual, não em pomodoros completados.
        """
        short_breaks_count = self._count_short_breaks_in_session()
        
        # Se o número de pausas curtas é múltiplo de pomodoros_before_long_break,
        # então a próxima deve ser longa
        if short_breaks_count > 0 and short_breaks_count % self._pomodoros_before_long_break == 0:
            break_type = "long"
            debug_log("TimerService", "_determine_break_type", 
                     "Pausa longa determinada (pausas curtas: %d, antes de longa: %d)", 
                     short_breaks_count, self._pomodoros_before_long_break)
        else:
            break_type = "short"
            debug_log("TimerService", "_determine_break_type", 
                     "Pausa curta determinada (pausas curtas: %d, antes de longa: %d)", 
                     short_breaks_count, self._pomodoros_before_long_break)
        
        return break_type
    
    @Slot(str)
    def acceptBreak(self, break_type: str) -> None:
        """
        Aceita fazer pausa após Pomodoro completar.
        Usa o mesmo sistema de cronômetro que pause().
        """
        debug_log("TimerService", "acceptBreak", "Aceitando pausa após Pomodoro, tipo=%s", break_type)
        
        # Salvar worklog atual antes de iniciar pausa
        if self._timer_model._current_session:
            # Finalizar tempo decorrido antes de salvar
            if self._start_time:
                elapsed = time.time() - self._start_time
                self._paused_elapsed += elapsed
                self._start_time = None
            
            # Atualizar elapsedSeconds no modelo antes de salvar
            self._timer_model.elapsedSeconds = int(self._paused_elapsed)
            
            # Salvar sessão atual
            session = self._timer_model.stop_session()
            if session and self._worklog_db:
                try:
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
                    debug_log("TimerService", "acceptBreak", "Worklog salvo antes de pausar: %s", session.id)
                    self._timer_model.sessionSaved.emit(session.id)
                except Exception as e:
                    debug_log("TimerService", "acceptBreak", "Erro ao salvar sessão: %s", e)
            
            # Limpar sessão mas manter issue key
            # (issue key será mantida no modelo, não limpar aqui)
        
        # Resetar tempo acumulado (novo worklog começará após pausa)
        self._paused_elapsed = 0
        
        # Parar timer completamente
        self._timer.stop()
        self._is_running = False
        
        # Mudar estado do modelo para IDLE durante a pausa
        self._timer_model.state = TimerState.IDLE.value
        
        # Cancelar timer de auto-continuação
        self._break_decision_timeout_timer.stop()
        
        # Criar PomodoroSession para a pausa (não adicionar à sessão - sessão foi salva)
        break_start = datetime.now()
        break_session = PomodoroSession(
            id=f"break_{break_type}_{int(time.time())}",
            start_time=break_start,
            is_break=True,
            break_type=break_type,
        )
        
        # Guardar referência para atualizar quando terminar (não adicionar à sessão)
        self._current_break_session = break_session
        
        # Determinar duração da pausa
        if break_type == "long":
            break_duration_seconds = self._long_break_seconds
        else:
            break_duration_seconds = self._short_break_seconds
        
        # Iniciar contagem regressiva da pausa
        self._timer_model.isOnBreak = True
        self._timer_model.breakType = break_type
        self._timer_model.breakRemainingSeconds = break_duration_seconds
        self._timer_model.isWaitingBreakDecision = False
        
        # Iniciar timer de contagem regressiva
        self._break_countdown_timer.start()
        
        debug_log("TimerService", "acceptBreak", "Pausa iniciada: tipo=%s, duração=%ds", break_type, break_duration_seconds)
    
    def _on_break_tick(self) -> None:
        """Callback chamado a cada segundo durante a pausa"""
        if self._timer_model.breakRemainingSeconds > 0:
            self._timer_model.breakRemainingSeconds -= 1
        else:
            # Pausa terminou - atualizar PomodoroSession
            self._break_countdown_timer.stop()
            
            # Atualizar PomodoroSession da pausa com end_time e duration
            if self._current_break_session:
                break_end = datetime.now()
                self._current_break_session.end_time = break_end
                
                # Calcular duração baseada no tipo de pausa
                if self._current_break_session.break_type == "long":
                    self._current_break_session.duration_seconds = self._long_break_seconds
                else:
                    self._current_break_session.duration_seconds = self._short_break_seconds
                
                debug_log("TimerService", "_on_break_tick", 
                         "Pausa finalizada: tipo=%s, duração=%ds", 
                         self._current_break_session.break_type,
                         self._current_break_session.duration_seconds)
                
                # Limpar referência
                self._current_break_session = None
            
            self._timer_model.isOnBreak = False
            self._timer_model.isWaitingBreakEndDecision = True
            self._timer_model.breakEnded.emit()
            # Som será tocado via app.py quando breakEnded for emitido
            debug_log("TimerService", "_on_break_tick", "Pausa terminada")
    
    @Slot()
    def continueWithoutBreak(self) -> None:
        """Continua sem fazer pausa"""
        debug_log("TimerService", "continueWithoutBreak", "Continuando sem pausa")
        
        # Cancelar timer de auto-continuação
        self._break_decision_timeout_timer.stop()
        
        # Esconder alerta (timer já está rodando normalmente)
        self._timer_model.isWaitingBreakDecision = False
    
    def _on_break_decision_timeout(self) -> None:
        """Timeout de auto-continuação do alerta"""
        debug_log("TimerService", "_on_break_decision_timeout", "Timeout atingido, continuando automaticamente")
        self.continueWithoutBreak()
    
    @Slot()
    def continueAfterBreak(self) -> None:
        """Continua após pausa terminar - inicia nova sessão"""
        debug_log("TimerService", "continueAfterBreak", "Continuando após pausa")
        
        # Garantir que PomodoroSession da pausa está atualizado
        if self._current_break_session and not self._current_break_session.end_time:
            break_end = datetime.now()
            self._current_break_session.end_time = break_end
            if self._current_break_session.break_type == "long":
                self._current_break_session.duration_seconds = self._long_break_seconds
            else:
                self._current_break_session.duration_seconds = self._short_break_seconds
            self._current_break_session = None
        
        # Limpar estado de pausa
        self._timer_model.isWaitingBreakEndDecision = False
        
        # Obter issue key (mantida do worklog anterior)
        issue_key = self._timer_model.issueKey
        
        if issue_key:
            # Resetar tempo acumulado (nova sessão)
            self._paused_elapsed = 0
            # Iniciar nova sessão
            self.start(issue_key)
        else:
            debug_log("TimerService", "continueAfterBreak", "Sem issue key para continuar")
    
    @Slot()
    def stopAfterBreak(self) -> None:
        """Para após pausa terminar"""
        debug_log("TimerService", "stopAfterBreak", "Parando após pausa")
        
        # Garantir que PomodoroSession da pausa está atualizado
        # (já deve estar atualizado em _on_break_tick, mas garantir)
        if self._current_break_session and not self._current_break_session.end_time:
            break_end = datetime.now()
            self._current_break_session.end_time = break_end
            if self._current_break_session.break_type == "long":
                self._current_break_session.duration_seconds = self._long_break_seconds
            else:
                self._current_break_session.duration_seconds = self._short_break_seconds
            self._current_break_session = None
        
        # Manter timer parado (já está parado)
        self._timer_model.isWaitingBreakEndDecision = False
        
        # Limpar issue key e resetar contadores
        self._timer_model.issueKey = ""
        self._timer_model.elapsedSeconds = 0
        self._timer_model.currentPomodoro = 0
    
    @Slot()
    def cancelBreak(self) -> None:
        """Cancela a pausa atual e limpa todos os estados relacionados"""
        debug_log("TimerService", "cancelBreak", "Cancelando pausa")
        
        # Parar timer de contagem regressiva da pausa
        if self._break_countdown_timer.isActive():
            self._break_countdown_timer.stop()
            debug_log("TimerService", "cancelBreak", "Timer de contagem regressiva parado")
        
        # Cancelar timer de auto-continuação se estiver ativo
        if self._break_decision_timeout_timer.isActive():
            self._break_decision_timeout_timer.stop()
        
        # Remover PomodoroSession da pausa da lista de pomodoros se existir
        if self._current_break_session and self._timer_model._current_session:
            try:
                self._timer_model._current_session.pomodoros.remove(self._current_break_session)
                debug_log("TimerService", "cancelBreak", "PomodoroSession da pausa removida da sessão")
            except ValueError:
                debug_log("TimerService", "cancelBreak", "PomodoroSession da pausa não encontrada na lista")
            self._current_break_session = None
        
        # Limpar todos os estados de pausa
        self._timer_model.isOnBreak = False
        self._timer_model.breakType = ""
        self._timer_model.breakRemainingSeconds = 0
        self._timer_model.isWaitingBreakEndDecision = False
        self._timer_model.isWaitingBreakDecision = False
        
        # Restaurar estado do timer para IDLE para permitir reiniciar
        # Resetar estado para IDLE para que start() possa ser chamado novamente
        self._timer_model.state = TimerState.IDLE.value
        debug_log("TimerService", "cancelBreak", "Estado do timer resetado para IDLE")
        
        # Resetar estado interno
        self._is_running = False
        self._start_time = None
        # Não limpar _paused_elapsed aqui - pode ser útil manter o tempo acumulado
        # Não limpar issueKey aqui - será mantido para permitir continuar na mesma issue
        
        debug_log("TimerService", "cancelBreak", "Pausa cancelada e estados limpos")