"""
Gerenciador de atalho global para Jira Quick Task
Implementa atalho Super+J (Meta+J) para restaurar janela
Usa python-xlib diretamente para compatibilidade com PySide6
"""

import sys
import threading
from PySide6.QtCore import QObject, Signal  # type: ignore[import]


class GlobalShortcutManager(QObject):
    """Gerencia atalho global Super+J para restaurar janela usando python-xlib"""
    
    # Sinal emitido quando o atalho é pressionado
    activated = Signal()
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self._listener_thread = None
        self._is_registered = False
        self._stop_event = threading.Event()
        self._xlib_available = False
        self._setup_keybinder()
    
    def _setup_keybinder(self):
        """Configura o keybinder usando python-xlib"""
        try:
            # Tentar importar Xlib
            try:
                from Xlib import X, display
                from Xlib.ext import record
                from Xlib.protocol import rq
                self._xlib_available = True
            except ImportError:
                # python-xlib não está instalado
                print("Aviso: python-xlib não está instalado. Atalho global Super+J não estará disponível.", file=sys.stderr)
                print("  Instale com: sudo apt install python3-xlib", file=sys.stderr)
                self._xlib_available = False
                return
            
            # Verificar se estamos em X11 (não Wayland)
            try:
                dpy = display.Display()
                dpy.close()
            except Exception as e:
                print(f"Aviso: Não foi possível conectar ao servidor X11: {e}", file=sys.stderr)
                print("  Atalho global requer X11 (não funciona em Wayland puro)", file=sys.stderr)
                self._xlib_available = False
                return
                
        except Exception as e:
            print(f"Erro ao configurar atalho global: {e}", file=sys.stderr)
            self._xlib_available = False
    
    def register_with_window(self, window):
        """
        Registra o atalho Super+J
        Nota: window não é usado com xlib, mas mantemos a assinatura para compatibilidade
        """
        if not self._xlib_available or self._is_registered:
            return
        
        try:
            # Iniciar thread de escuta de teclas
            self._listener_thread = threading.Thread(
                target=self._key_listener_thread,
                daemon=True  # Thread daemon será terminada automaticamente quando o processo principal terminar
            )
            self._listener_thread.start()
            self._is_registered = True
            # Mensagem de debug removida
        except Exception as e:
            print(f"Erro ao registrar atalho global: {e}", file=sys.stderr)
    
    def _key_listener_thread(self):
        """Thread que escuta eventos de teclado via X11"""
        try:
            from Xlib import X, display
            from Xlib.ext import record
            from Xlib.protocol import rq
            
            # Dois displays: um para operações normais, outro para record
            local_dpy = None
            record_dpy = None
            ctx = None
            
            try:
                local_dpy = display.Display()
                record_dpy = display.Display()
                
                # Verificar se record extension está disponível
                if not record_dpy.has_extension("RECORD"):
                    # Aviso removido (debug)
                    return
                
                # Função callback para eventos de teclado
                def handler(reply):
                    """Processa eventos de teclado"""
                    if reply.category != record.FromServer:
                        return
                    
                    if reply.client_swapped:
                        return
                    
                    if not len(reply.data) or reply.data[0] < 2:
                        return
                    
                    data = reply.data
                    while len(data):
                        event, data = rq.EventField(None).parse_binary_value(
                            data, record_dpy.display, None, None
                        )
                        
                        # Verificar se é KeyPress
                        if event.type == X.KeyPress:
                            # Obter código da tecla
                            keycode = event.detail
                            
                            # Verificar modificadores (Super/Meta = Mod4)
                            # Mod4 é tipicamente a tecla Super/Windows
                            mod4_mask = X.Mod4Mask
                            if event.state & mod4_mask:
                                # Converter keycode para keysym
                                keysym = local_dpy.keycode_to_keysym(keycode, 0)
                                
                                # J = 0x006a (j minúsculo) ou 0x004a (J maiúsculo)
                                # Valores hexadecimais padrão para tecla J
                                if keysym in (0x006a, 0x004a):
                                    # Emitir sinal diretamente (sinais Qt são thread-safe)
                                    # O Qt automaticamente enfileira o sinal para o thread principal
                                    self.activated.emit()
                
                # Criar contexto de record
                ctx = record_dpy.record_create_context(
                    0,
                    [record.AllClients],
                    [{
                        'core_requests': (0, 0),
                        'core_replies': (0, 0),
                        'ext_requests': (0, 0, 0, 0),
                        'ext_replies': (0, 0, 0, 0),
                        'delivered_events': (0, 0),
                        'device_events': (X.KeyPress, X.KeyRelease),
                        'errors': (0, 0),
                        'client_started': False,
                        'client_died': False,
                    }]
                )
                
                # Criar uma thread auxiliar para monitorar stop_event e fechar o display
                def monitor_stop():
                    self._stop_event.wait()
                    # Quando stop_event for setado, fechar o display para interromper record_enable_context
                    try:
                        if record_dpy:
                            record_dpy.close()
                    except:
                        pass
                
                stop_monitor = threading.Thread(target=monitor_stop, daemon=True)
                stop_monitor.start()
                
                # Iniciar escuta (bloqueia até o display ser fechado ou contexto desabilitado)
                # Se o display for fechado pela thread monitor, isso retornará
                try:
                    record_dpy.record_enable_context(ctx, handler)
                except Exception as e:
                    if not self._stop_event.is_set():
                        print(f"Erro ao processar eventos de teclado: {e}", file=sys.stderr)
                
            finally:
                # Cleanup seguro
                try:
                    if ctx and record_dpy:
                        record_dpy.record_free_context(ctx)
                except:
                    pass
                try:
                    if local_dpy:
                        local_dpy.close()
                except:
                    pass
                try:
                    if record_dpy:
                        record_dpy.close()
                except:
                    pass
            
        except ImportError:
            # python-xlib não está instalado
            print("Aviso: python-xlib não está instalado. Atalho global Super+J não estará disponível.", file=sys.stderr)
            print("  Instale com: sudo apt install python3-xlib", file=sys.stderr)
        except Exception as e:
            if not self._stop_event.is_set():
                print(f"Erro na thread de escuta de teclado: {e}", file=sys.stderr)
            self._is_registered = False
    
    def unregister(self):
        """Remove o registro do atalho"""
        if self._is_registered:
            try:
                # Solicitar parada da thread
                self._stop_event.set()
                # Como a thread é daemon, não precisamos aguardar explicitamente
                # Ela será terminada automaticamente quando o processo principal terminar
                # Mas podemos aguardar um pouco para cleanup gracioso
                if self._listener_thread and self._listener_thread.is_alive():
                    self._listener_thread.join(timeout=0.5)  # Timeout curto
                self._is_registered = False
            except Exception as e:
                # Não imprimir erro aqui para evitar spam no shutdown
                pass
    
    def is_available(self) -> bool:
        """Verifica se atalho global está disponível"""
        return self._xlib_available and self._is_registered
