"""
Serviço para gerenciar notificações desktop
"""

from pathlib import Path
from typing import Optional

from PySide6.QtCore import QObject, QTimer, Signal, QUrl  # type: ignore[import]

from src.utils.debug import debug_log

# Tentar importar QSystemTrayIcon
try:
    from PySide6.QtWidgets import QSystemTrayIcon  # type: ignore[import]
    TRAY_AVAILABLE = True
except ImportError:
    QSystemTrayIcon = None
    TRAY_AVAILABLE = False

# Tentar importar QMediaPlayer para tocar arquivos de som
try:
    from PySide6.QtMultimedia import QMediaPlayer, QAudioOutput  # type: ignore[import]
    MEDIA_PLAYER_AVAILABLE = True
except ImportError:
    QMediaPlayer = None
    QAudioOutput = None
    MEDIA_PLAYER_AVAILABLE = False


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
        
        # Inicializar player de áudio para arquivos de som
        self._sound_player = None
        self._audio_output = None
        if MEDIA_PLAYER_AVAILABLE:
            try:
                self._audio_output = QAudioOutput(self)
                self._sound_player = QMediaPlayer(self)
                self._sound_player.setAudioOutput(self._audio_output)
                # Conectar sinal para limpar quando terminar
                self._sound_player.playbackStateChanged.connect(self._on_sound_finished)
            except Exception as e:
                debug_log("NotificationService", "__init__", "Erro ao inicializar player de áudio: %s", e)
                self._sound_player = None
                self._audio_output = None

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
    
    def _on_sound_finished(self, state):
        """Callback quando som termina de tocar"""
        if not MEDIA_PLAYER_AVAILABLE:
            return
        # QMediaPlayer.PlaybackState.StoppedState = 0
        if state == 0:  # StoppedState
            # Limpar source para permitir tocar novamente
            if self._sound_player:
                self._sound_player.setSource(QUrl())
    
    def _find_sound_file(self, break_type: Optional[str] = None) -> Optional[Path]:
        """
        Procura arquivo de som nos assets ou usa caminho completo se fornecido.
        
        Args:
            break_type: "short" ou "long" para escolher o arquivo correto.
                       Se None, usa "pomodoro" como padrão.
        
        Ordem de prioridade:
        1. Se shortSoundFile/longSoundFile for caminho absoluto e existir, usar diretamente
        2. Caso contrário, buscar em assets/ com nome do arquivo
        3. Formatos suportados: ogg, mp3, m4r, wav
        """
        # Determinar nome do arquivo ou caminho baseado no tipo de pausa
        if break_type and self._settings_model:
            if break_type == "short":
                filename_or_path = self._settings_model.shortSoundFile or "short"
                debug_log("NotificationService", "_find_sound_file", 
                         "Pausa curta: usando arquivo/caminho: %s", filename_or_path)
            elif break_type == "long":
                filename_or_path = self._settings_model.longSoundFile or "long"
                debug_log("NotificationService", "_find_sound_file", 
                         "Pausa longa: usando arquivo/caminho: %s", filename_or_path)
            else:
                filename_or_path = "pomodoro"  # Fallback
        else:
            filename_or_path = "pomodoro"  # Fallback padrão
        
        # Verificar se é caminho absoluto
        sound_path = Path(filename_or_path)
        if sound_path.is_absolute() and sound_path.exists():
            debug_log("NotificationService", "_find_sound_file", 
                     "Usando caminho completo fornecido: %s (break_type=%s)", sound_path, break_type)
            return sound_path
        
        # Se não, tratar como nome de arquivo e buscar em assets/
        # Extrair nome do arquivo (sem extensão se houver)
        # Se for um caminho relativo, usar apenas o nome do arquivo (sem diretório)
        if sound_path.suffix:
            # Se tem extensão, usar o nome sem extensão
            filename = sound_path.stem  # Nome sem extensão
        else:
            # Se não tem extensão, usar o nome do arquivo (última parte do caminho)
            # Se for caminho relativo com barras, pegar apenas o nome final
            filename = sound_path.name if sound_path.name else sound_path.stem if sound_path.stem else str(sound_path)
        
        # Possíveis locais para assets
        possible_paths = [
            Path(__file__).parent.parent.parent.parent / "assets",  # src/services/../../assets (desenvolvimento)
            Path("/app/share/jira-quick-task/assets"),  # Flatpak
            Path("/usr/share/jira-quick-task/assets"),  # Sistema
        ]
        
        # Formatos suportados em ordem de prioridade
        formats = ["ogg", "mp3", "m4r", "wav"]
        
        for base_path in possible_paths:
            if not base_path.exists():
                continue
            
            for fmt in formats:
                sound_file = base_path / f"{filename}.{fmt}"
                if sound_file.exists():
                    debug_log("NotificationService", "_find_sound_file", 
                             "Arquivo de som encontrado: %s (break_type=%s)", sound_file, break_type)
                    return sound_file
        
        debug_log("NotificationService", "_find_sound_file", 
                 "Nenhum arquivo de som encontrado para '%s' nos assets", filename)
        return None
    
    def play_pomodoro_sound(self, break_type: Optional[str] = None) -> None:
        """
        Toca som quando pomodoro completa ou pausa termina
        
        Args:
            break_type: "short" para pausa curta, "long" para pausa longa, None para som padrão
        """
        # Verificar se som está habilitado
        if self._settings_model and not self._settings_model.soundEnabled:
            debug_log("NotificationService", "play_pomodoro_sound", "Som desabilitado nas configurações")
            return
        
        # Tentar tocar arquivo de som primeiro
        sound_file = self._find_sound_file(break_type)
        if sound_file and MEDIA_PLAYER_AVAILABLE and self._sound_player:
            try:
                sound_url = QUrl.fromLocalFile(str(sound_file.absolute()))
                # Limpar source anterior para garantir que novo arquivo seja carregado
                self._sound_player.stop()
                self._sound_player.setSource(QUrl())  # Limpar primeiro
                # Definir novo source
                self._sound_player.setSource(sound_url)
                self._sound_player.play()
                debug_log("NotificationService", "play_pomodoro_sound", 
                         "Tocando arquivo de som: %s (break_type=%s)", sound_file, break_type)
                return
            except Exception as e:
                debug_log("NotificationService", "play_pomodoro_sound", 
                         "Erro ao tocar arquivo de som: %s", e)
                # Continuar para fallback
        
        # Fallback: usar beep do sistema
        try:
            if TRAY_AVAILABLE and self._tray_icon:
                # Usar beep do tray icon (mostrar mensagem vazia por 1ms para tocar beep)
                self._tray_icon.showMessage("", "", QSystemTrayIcon.NoIcon, 1)
            else:
                # Fallback: usar beep do sistema via print (ASCII bell)
                print("\a", end="", flush=True)
            debug_log("NotificationService", "play_pomodoro_sound", "Som tocado (beep do sistema)")
        except Exception as e:
            debug_log("NotificationService", "play_pomodoro_sound", "Erro ao tocar som: %s", e)