"""
Serviço para gerenciar notificações desktop
"""

from typing import Optional

from PySide6.QtCore import QObject, QTimer, Signal  # type: ignore[import]

from src.utils.debug import debug_log

# Tentar importar QSystemTrayIcon
try:
    from PySide6.QtWidgets import QSystemTrayIcon  # type: ignore[import]
    TRAY_AVAILABLE = True
except ImportError:
    QSystemTrayIcon = None
    TRAY_AVAILABLE = False


class NotificationService(QObject):
    """Serviço para gerenciar notificações desktop"""

    # Sinais
    interactionTimeout = Signal()  # Sem interação após timeout
    pauseRequested = Signal()
    continueRequested = Signal()

    def __init__(self, tray_icon: Optional[QSystemTrayIcon] = None, parent=None):
        super().__init__(parent)
        self._tray_icon = tray_icon
        self._auto_continue_timer = QTimer(self)
        self._auto_continue_timer.timeout.connect(self._on_auto_continue)
        self._interaction_timeout_seconds = 30
        self._settings_model = None

    def set_interaction_timeout(self, seconds: int) -> None:
        """Define timeout de auto-continuação em segundos"""
        self._interaction_timeout_seconds = seconds

    def show_pomodoro_notification(
        self,
        issue_key: str,
        pomodoro_num: int,
        total_before_long: int,
        break_type: str,
    ) -> None:
        """
        Mostra notificação de Pomodoro completo
        
        Args:
            issue_key: Chave da issue Jira
            pomodoro_num: Número do Pomodoro completado
            total_before_long: Total de Pomodoros antes da pausa longa
            break_type: "short" ou "long"
        """
        title = "🍅 Pomodoro Concluído!"
        
        break_duration = "5 minutos" if break_type == "short" else "15 minutos"
        
        message = (
            f"Você trabalhou por 25 minutos em: {issue_key}\n\n"
            f"Pomodoro {pomodoro_num} de {total_before_long}\n\n"
            f"💡 Sugestão: Faça uma pausa de {break_duration}\n\n"
            f"Continuando automaticamente em {self._interaction_timeout_seconds}s..."
        )
        
        debug_log("NotificationService", "show_pomodoro_notification", 
                 "Mostrando notificação: %s", message)
        
        # Usar QSystemTrayIcon se disponível
        if TRAY_AVAILABLE and self._tray_icon:
            try:
                self._tray_icon.showMessage(
                    title,
                    message,
                    QSystemTrayIcon.Information,
                    self._interaction_timeout_seconds * 1000  # timeout em ms
                )
            except Exception as e:
                debug_log("NotificationService", "show_pomodoro_notification", 
                         "Erro ao mostrar notificação: %s", e)
        else:
            # Fallback: apenas log
            debug_log("NotificationService", "show_pomodoro_notification", 
                     "Tray icon não disponível, apenas logando")
            print(f"{title}\n{message}")
        
        # Iniciar timer de auto-continuação
        self._auto_continue_timer.start(self._interaction_timeout_seconds * 1000)
        debug_log("NotificationService", "show_pomodoro_notification", 
                 "Timer de auto-continuação iniciado: %ds", self._interaction_timeout_seconds)

    def _on_auto_continue(self) -> None:
        """Timer continua automaticamente se não houver interação"""
        self._auto_continue_timer.stop()
        debug_log("NotificationService", "_on_auto_continue", "Timeout atingido, continuando")
        self.interactionTimeout.emit()

    def cancel_auto_continue(self) -> None:
        """Cancela continuação automática (usuário interagiu)"""
        self._auto_continue_timer.stop()
        debug_log("NotificationService", "cancel_auto_continue", "Auto-continuação cancelada")

    def set_tray_icon(self, tray_icon: Optional[QSystemTrayIcon]) -> None:
        """Define o ícone do system tray para usar nas notificações"""
        self._tray_icon = tray_icon
    
    def set_settings_model(self, settings_model) -> None:
        """Define o SettingsModel para verificar se som está habilitado"""
        self._settings_model = settings_model
    
    def play_pomodoro_sound(self) -> None:
        """Toca som quando pomodoro completa ou pausa termina"""
        # Verificar se som está habilitado
        if self._settings_model and not self._settings_model.soundEnabled:
            debug_log("NotificationService", "play_pomodoro_sound", "Som desabilitado nas configurações")
            return
        
        try:
            # Usar beep do sistema via QSystemTrayIcon se disponível
            if TRAY_AVAILABLE and self._tray_icon:
                # Usar beep do tray icon (mostrar mensagem vazia por 1ms para tocar beep)
                self._tray_icon.showMessage("", "", QSystemTrayIcon.NoIcon, 1)
            else:
                # Fallback: usar beep do sistema via print (ASCII bell)
                print("\a", end="", flush=True)
            debug_log("NotificationService", "play_pomodoro_sound", "Som tocado")
        except Exception as e:
            debug_log("NotificationService", "play_pomodoro_sound", "Erro ao tocar som: %s", e)