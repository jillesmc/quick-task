"""
TimerFloatingWindow - Janela frameless com drag suave via Python
"""
import sys
from pathlib import Path
from PySide6.QtCore import Qt, QPoint, QUrl, QTimer
from PySide6.QtQuick import QQuickView
from PySide6.QtGui import QGuiApplication


class TimerFloatingWindow(QQuickView):
    """Janela frameless com drag suave implementado em Python"""
    
    def __init__(self, qml_file: str, parent=None):
        super().__init__(parent)
        self._qml_file = qml_file
        self._setup_window()
        self._init_drag_state()
        # QML será carregado depois que as propriedades forem expostas (no app.py)
    
    def _setup_window(self):
        """Configuração da janela"""
        self.setWidth(320)
        self.setHeight(200)
        self.setTitle("Timer Ativo")
        
        # Flags críticas para frameless
        self.setFlags(
            Qt.Window | 
            Qt.WindowStaysOnTopHint | 
            Qt.FramelessWindowHint | 
            Qt.Tool
        )
        
        # Cor transparente para permitir bordas arredondadas no QML
        self.setColor(Qt.transparent)
        
        # Configurar para redimensionar automaticamente o rootObject
        self.setResizeMode(QQuickView.SizeRootObjectToView)
    
    def _init_drag_state(self):
        """Inicializa estado do drag"""
        self.drag_start_pos = QPoint()
        self.window_start_pos = QPoint()
        self.is_dragging = False
        self._drag_area_height = 30  # Altura da área de drag (cabeçalho)
    
    def load_qml(self):
        """Carrega o conteúdo QML na janela (chamado após expor propriedades)"""
        try:
            qml_path = Path(self._qml_file)
            if not qml_path.exists():
                print(f"⚠ Aviso: Arquivo QML não encontrado: {self._qml_file}", file=sys.stderr)
                return
            
            qml_url = QUrl.fromLocalFile(str(qml_path.absolute()))
            self.setSource(qml_url)
            
            # Conectar sinal de status para posicionar quando pronto
            def on_status_changed():
                if self.status() == QQuickView.Status.Ready:
                    self.position_window()  # Chamar diretamente, sem delay
                    # NÃO chamar forceActiveFocus() aqui - a janela pode não estar visível ainda
                    # O foco será garantido quando a janela for realmente mostrada e ativada
                elif self.status() == QQuickView.Status.Error:
                    errors = self.errors()
                    print(f"⚠ Aviso: Erro ao carregar QML: {errors}", file=sys.stderr)
                    for error in errors:
                        print(f"  - {error.toString()}", file=sys.stderr)
            
            self.statusChanged.connect(on_status_changed)
            
            # Se já estiver pronto, posicionar imediatamente
            if self.status() == QQuickView.Status.Ready:
                self.position_window()
                # NÃO chamar forceActiveFocus() aqui - a janela pode não estar visível ainda
                # O foco será garantido quando a janela for realmente mostrada e ativada
        except Exception as e:
            print(f"⚠ Aviso: Exceção ao carregar QML: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc(file=sys.stderr)
    
    def mousePressEvent(self, event):
        """Captura início do arrasto"""
        # Só permite drag na área superior (cabeçalho)
        if event.position().y() < self._drag_area_height:
            self.drag_start_pos = event.globalPosition().toPoint()
            self.window_start_pos = self.position()
            self.is_dragging = True
            # Mudar cursor para feedback visual
            self.setCursor(Qt.ClosedHandCursor)
        
        super().mousePressEvent(event)
    
    def mouseMoveEvent(self, event):
        """Move janela com latência mínima"""
        if self.is_dragging:
            # ⚡ Operação atômica - bypass QML completamente
            delta = event.globalPosition().toPoint() - self.drag_start_pos
            new_pos = self.window_start_pos + delta
            
            # Limitar aos limites da tela
            screen = QGuiApplication.primaryScreen()
            if screen:
                geometry = screen.availableGeometry()
                max_x = geometry.width() - self.width()
                max_y = geometry.height() - self.height()
                new_pos.setX(max(0, min(new_pos.x(), max_x)))
                new_pos.setY(max(0, min(new_pos.y(), max_y)))
            
            # Atualizar posição diretamente (bypass QML bindings)
            self.setPosition(new_pos)
        
        super().mouseMoveEvent(event)
    
    def mouseReleaseEvent(self, event):
        """Termina o arrasto"""
        if self.is_dragging:
            self.is_dragging = False
            self.setCursor(Qt.ArrowCursor)
        
        super().mouseReleaseEvent(event)
    
    def enterEvent(self, event):
        """Resetar cursor quando mouse entra na janela"""
        # Resetar cursor para garantir que não fique preso em modo de seleção de texto
        # Se estiver na área de drag, usar OpenHandCursor, senão ArrowCursor
        from PySide6.QtGui import QCursor
        mouse_pos = self.mapFromGlobal(QCursor.pos())
        if mouse_pos.y() < self._drag_area_height:
            self.setCursor(Qt.OpenHandCursor)
        else:
            self.setCursor(Qt.ArrowCursor)
        super().enterEvent(event)
    
    def leaveEvent(self, event):
        """Resetar cursor quando mouse sai da janela"""
        # Garantir que cursor seja resetado quando sair
        if not self.is_dragging:
            self.setCursor(Qt.ArrowCursor)
        super().leaveEvent(event)
    
    def position_window(self):
        """Posiciona a janela no canto superior direito"""
        screen = QGuiApplication.primaryScreen()
        if screen:
            geometry = screen.availableGeometry()
            self.setX(geometry.width() - self.width() - 20)
            self.setY(20)
        else:
            # Fallback
            self.setX(100)
            self.setY(100)
