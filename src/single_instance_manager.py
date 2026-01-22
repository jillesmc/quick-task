"""
Gerenciador de instância única para Jira Quick Task
Previne múltiplas instâncias da aplicação usando QLockFile e QLocalServer
"""

import sys
from pathlib import Path
from PySide2.QtCore import QObject, Signal, QLockFile, QDir, QByteArray  # type: ignore[import]
from PySide2.QtNetwork import QLocalServer, QLocalSocket  # type: ignore[import]


class SingleInstanceManager(QObject):
    """Gerencia instância única da aplicação"""
    
    # Sinal emitido quando outra instância tenta iniciar e precisa restaurar a janela
    restoreRequested = Signal()
    
    def __init__(self, app_name: str = "jira-quick-task", parent=None):
        super().__init__(parent)
        self.app_name = app_name
        self.lock_file = None
        self.local_server = None
        self.is_first_instance = False
        
    def try_lock(self) -> bool:
        """
        Tenta obter lock exclusivo. Retorna True se for a primeira instância.
        Se outra instância já estiver rodando, tenta comunicar com ela.
        """
        # Criar lock file no diretório temporário
        lock_path = Path(QDir.tempPath()) / f"{self.app_name}.lock"
        self.lock_file = QLockFile(str(lock_path))
        
        # Tentar obter lock (timeout de 100ms)
        if self.lock_file.tryLock(100):
            # Primeira instância - criar servidor local para receber mensagens
            self.is_first_instance = True
            self._setup_local_server()
            return True
        else:
            # Outra instância já está rodando
            # Tentar comunicar com ela para restaurar janela
            self._notify_existing_instance()
            return False
    
    def _setup_local_server(self):
        """Configura servidor local para receber mensagens de outras instâncias"""
        server_name = f"{self.app_name}_server"
        self.local_server = QLocalServer(self)
        
        # Remover servidor antigo se existir (caso de crash anterior)
        if QLocalServer.removeServer(server_name):
            pass  # Servidor antigo removido
        
        # Tentar escutar no servidor
        if not self.local_server.listen(server_name):
            # Se falhar, tentar remover e escutar novamente
            QLocalServer.removeServer(server_name)
            if not self.local_server.listen(server_name):
                # Aviso removido (debug)
                return
        
        # Conectar sinal de nova conexão
        self.local_server.newConnection.connect(self._handle_new_connection)
    
    def _handle_new_connection(self):
        """Lida com nova conexão de outra instância"""
        socket = self.local_server.nextPendingConnection()
        if socket:
            # Ler dados (se houver)
            socket.readyRead.connect(lambda: self._read_socket_data(socket))
            socket.disconnected.connect(socket.deleteLater)
            # Emitir sinal para restaurar janela
            self.restoreRequested.emit()
    
    def _read_socket_data(self, socket: QLocalSocket):
        """Lê dados do socket (se necessário no futuro)"""
        data = socket.readAll()
        # Por enquanto, apenas restaurar janela
        # No futuro, pode processar argumentos de linha de comando aqui
        socket.disconnectFromServer()
    
    def _notify_existing_instance(self):
        """Notifica instância existente para restaurar janela"""
        server_name = f"{self.app_name}_server"
        socket = QLocalSocket(self)
        socket.connectToServer(server_name)
        
        # Tentar conectar (timeout de 1 segundo)
        if socket.waitForConnected(1000):
            # Enviar mensagem simples (apenas para acionar o servidor)
            socket.write(QByteArray(b"restore"))
            socket.flush()
            socket.waitForBytesWritten(1000)
            socket.disconnectFromServer()
        else:
            # Se não conseguir conectar, a instância pode ter crashado
            # Mas o lock file ainda existe. Isso é OK, a nova instância vai falhar
            pass
        
        socket.deleteLater()
    
    def cleanup(self):
        """Limpa recursos (lock file e servidor)"""
        if self.lock_file:
            self.lock_file.unlock()
        if self.local_server and self.local_server.isListening():
            self.local_server.close()
            QLocalServer.removeServer(f"{self.app_name}_server")
