"""
Gerenciador de System Tray Icon para Jira Quick Task
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
    print("  Instale o pacote: sudo apt install python3-pyside6.qtwidgets", file=sys.stderr)
    print(f"  Detalhes: {e}", file=sys.stderr)
    # Criar classes dummy para não quebrar o código
    QSystemTrayIcon = None
    QMenu = None
    QAction = None


class SystemTrayManager(QObject):
    """Gerencia o ícone do system tray e menu de contexto"""
    
    # Sinais emitidos quando ações do menu são acionadas
    restoreRequested = Signal()
    toggleRequested = Signal()  # Novo sinal para toggle (mostrar/esconder)
    quitRequested = Signal()
    
    def __init__(self, icon_path: Path, parent=None):
        super().__init__(parent)
        self.icon_path = icon_path
        self.tray_icon = None
        self.menu = None
        self._setup_tray_icon()
    
    def _setup_tray_icon(self):
        """Configura o ícone do system tray e menu"""
        # Verificar se QtWidgets está disponível
        if QSystemTrayIcon is None:
            # Aviso removido (debug)
            return
        
        # Verificar se system tray está disponível
        if not QSystemTrayIcon.isSystemTrayAvailable():
            # Aviso removido (debug)
            return
        
        # Criar ícone
        icon = self._load_icon()
        self.tray_icon = QSystemTrayIcon(icon, self)
        
        # Criar menu de contexto
        self.menu = QMenu()
        
        # Ação Restaurar
        restore_action = QAction("Restaurar", self)
        restore_action.triggered.connect(self.restoreRequested.emit)
        self.menu.addAction(restore_action)
        
        # Separador
        self.menu.addSeparator()
        
        # Ação Fechar
        quit_action = QAction("Fechar", self)
        quit_action.triggered.connect(self.quitRequested.emit)
        self.menu.addAction(quit_action)
        
        # Configurar menu no tray icon
        self.tray_icon.setContextMenu(self.menu)
        
        # Conectar clique no ícone (restaurar janela)
        self.tray_icon.activated.connect(self._on_tray_icon_activated)
        
        # Tooltip
        self.tray_icon.setToolTip("Jira Quick Task")
    
    def _load_icon(self) -> QIcon:
        """Carrega o ícone do tray"""
        # System tray funciona melhor com PNG ao invés de SVG
        # Tentar usar PNG 22x22 ou 24x24 primeiro
        icon_dir = self.icon_path.parent
        
        # Tentar PNG 22x22 (tamanho comum para tray icons)
        png_22 = icon_dir / "jira-quick-task-22.png"
        if png_22.exists():
            return QIcon(str(png_22))
        
        # Tentar PNG 24x24
        png_24 = icon_dir / "jira-quick-task-24.png"
        if png_24.exists():
            return QIcon(str(png_24))
        
        # Tentar PNG 32x32
        png_32 = icon_dir / "jira-quick-task-32.png"
        if png_32.exists():
            return QIcon(str(png_32))
        
        # Fallback: tentar SVG
        if self.icon_path.exists():
            return QIcon(str(self.icon_path))
        
        # Último fallback: ícone do tema
        return QIcon.fromTheme("jira-quick-task")
    
    def _on_tray_icon_activated(self, reason: QSystemTrayIcon.ActivationReason):
        """Lida com ativação do tray icon"""
        if reason == QSystemTrayIcon.DoubleClick or reason == QSystemTrayIcon.Trigger:
            # Clique simples ou duplo - toggle (mostrar/esconder)
            self.toggleRequested.emit()
    
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
        return QSystemTrayIcon.isSystemTrayAvailable() and self.tray_icon is not None
