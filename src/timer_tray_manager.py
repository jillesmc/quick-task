"""
Gerenciador de System Tray Icon para Timer do Jira Quick Task
"""

import sys
from pathlib import Path
from PySide6.QtCore import QObject, Signal, QTimer  # type: ignore[import]
from PySide6.QtGui import QIcon, QAction  # type: ignore[import]

# Importar QtWidgets (necessário para QSystemTrayIcon e QMenu)
try:
    from PySide6.QtWidgets import QSystemTrayIcon, QMenu  # type: ignore[import]
except ImportError as e:
    print("Aviso: PySide6.QtWidgets não está disponível.", file=sys.stderr)
    print(
        "  Instale o pacote: sudo apt install python3-pyside6.qtwidgets",
        file=sys.stderr,
    )
    print(f"  Detalhes: {e}", file=sys.stderr)
    # Criar classes dummy para não quebrar o código
    QSystemTrayIcon = None
    QMenu = None
    QAction = None


class TimerTrayManager(QObject):
    """Gerencia o ícone do system tray específico para o timer"""

    # Sinais emitidos quando ações do menu são acionadas
    restoreRequested = Signal()
    pauseRequested = Signal()
    resumeRequested = Signal()
    stopRequested = Signal()

    def __init__(self, icon_path: Path, parent=None):
        super().__init__(parent)
        self.icon_path = icon_path
        self.tray_icon = None
        self.menu = None
        self._update_timer = QTimer(self)
        self._update_timer.timeout.connect(self._update_tooltip)
        self._update_timer.start(1000)  # Atualizar a cada segundo
        self._current_issue_key = ""
        self._current_elapsed_seconds = 0
        self._current_state = "idle"
        self._current_pomodoro = 0
        self._is_on_break = False
        self._setup_tray_icon()

    def _setup_tray_icon(self):
        """Configura o ícone do system tray e menu"""
        # Verificar se QtWidgets está disponível
        if QSystemTrayIcon is None:
            return

        # Verificar se system tray está disponível
        try:
            tray_available = QSystemTrayIcon.isSystemTrayAvailable()
        except Exception:
            tray_available = False

        if not tray_available:
            return

        # Criar ícone
        icon = self._load_icon()
        self.tray_icon = QSystemTrayIcon(icon, self)

        # Criar menu de contexto
        self.menu = QMenu()

        # Ação Restaurar
        restore_action = QAction("Restaurar Timer", self)
        restore_action.triggered.connect(self.restoreRequested.emit)
        self.menu.addAction(restore_action)

        # Separador
        self.menu.addSeparator()

        # Ação Pausar/Retomar (será atualizada dinamicamente)
        self._pause_resume_action = QAction("Pausar", self)
        self._pause_resume_action.triggered.connect(self._on_pause_resume)
        self.menu.addAction(self._pause_resume_action)

        # Ação Parar
        stop_action = QAction("Parar Timer", self)
        stop_action.triggered.connect(self.stopRequested.emit)
        self.menu.addAction(stop_action)

        # Configurar menu no tray icon
        self.tray_icon.setContextMenu(self.menu)

        # Conectar clique no ícone (restaurar janela)
        self.tray_icon.activated.connect(self._on_tray_icon_activated)

        # Tooltip inicial
        self._update_tooltip()

    def _load_icon(self) -> QIcon:
        """Carrega o ícone do tray para o timer"""
        # Usar ícone de cronômetro do tema
        icon = QIcon.fromTheme("chronometer")
        if icon.isNull():
            # Fallback: tentar outros ícones relacionados
            icon = QIcon.fromTheme("timer")
            if icon.isNull():
                icon = QIcon.fromTheme("clock")

        # Se ainda não tiver ícone, tentar usar o ícone da aplicação
        if icon.isNull() and self.icon_path and self.icon_path.exists():
            icon = QIcon(str(self.icon_path))

        return icon

    def _on_tray_icon_activated(self, reason: QSystemTrayIcon.ActivationReason):
        """Lida com ativação do tray icon"""
        if reason == QSystemTrayIcon.DoubleClick or reason == QSystemTrayIcon.Trigger:
            # Clique simples ou duplo - restaurar janela do timer
            self.restoreRequested.emit()

    def _on_pause_resume(self):
        """Lida com ação de pausar/retomar"""
        # Com sistema unificado, só podemos pausar se estiver rodando
        # Não podemos mais retomar diretamente (pausa só termina quando cronômetro acaba)
        if self._current_state == "running" and not self._is_on_break:
            self.pauseRequested.emit()
        # Se estiver em pausa (isOnBreak), não fazer nada - usuário deve esperar cronômetro terminar

    def update_timer_state(
        self,
        issue_key: str,
        elapsed_seconds: int,
        state: str,
        pomodoro: int = 0,
        is_on_break: bool = False,
    ):
        """Atualiza o estado do timer para exibir no tooltip"""
        self._current_issue_key = issue_key
        self._current_elapsed_seconds = elapsed_seconds
        self._current_state = state
        self._current_pomodoro = pomodoro
        self._is_on_break = is_on_break

        # Atualizar menu
        if self._pause_resume_action:
            if state == "running" and not is_on_break:
                self._pause_resume_action.setText("Pausar")
                self._pause_resume_action.setEnabled(True)
            else:
                # Durante pausa ou timer parado, desabilitar botão pausar/retomar
                self._pause_resume_action.setText("Pausar")
                self._pause_resume_action.setEnabled(False)

        # Atualizar tooltip
        self._update_tooltip()

    def _update_tooltip(self):
        """Atualiza o tooltip do tray icon com informações do timer"""
        if not self.tray_icon:
            return

        if self._current_state == "idle" or not self._current_issue_key:
            self.tray_icon.setToolTip("Timer não está ativo")
            return

        # Formatar tempo
        hours = self._current_elapsed_seconds // 3600
        minutes = (self._current_elapsed_seconds % 3600) // 60
        seconds = self._current_elapsed_seconds % 60

        time_str = f"{hours:02d}:{minutes:02d}:{seconds:02d}"

        # Estado - considerar que pode estar em pausa mesmo com state="idle"
        state_str = "Pausado" if self._current_state == "paused" else "Rodando"

        # Tooltip
        tooltip = f"Timer: {self._current_issue_key}\n"
        tooltip += f"Tempo: {time_str}\n"
        tooltip += f"Estado: {state_str}"

        if self._current_pomodoro > 0:
            tooltip += f"\nPomodoro: {self._current_pomodoro}"

        self.tray_icon.setToolTip(tooltip)

    def show(self):
        """Mostra o tray icon"""
        if self.tray_icon:
            self.tray_icon.show()

    def hide(self):
        """Esconde o tray icon"""
        if self.tray_icon:
            self.tray_icon.hide()

    def is_available(self) -> bool:
        """Verifica se system tray está disponível"""
        if QSystemTrayIcon is None:
            return False

        # Sempre verificar se system tray está disponível (pode mudar durante execução)
        try:
            tray_available = QSystemTrayIcon.isSystemTrayAvailable()
        except Exception:
            tray_available = False

        # Se tray_icon não foi criado E system tray está disponível, tentar criar
        if self.tray_icon is None and tray_available:
            self._setup_tray_icon()

        return tray_available and self.tray_icon is not None
