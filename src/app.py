#!/usr/bin/env python3
"""
Jira Quick Task - Aplicação principal PySide2 + Kirigami 2
"""

import os
import sys
import signal
from pathlib import Path
from io import StringIO

# Configurar variáveis de ambiente ANTES de importar Qt
# Suprimir warnings do Kirigami, do estilo (Controls 2), Controls 1 (SplitView) e QSocketNotifier
# usando QT_LOGGING_RULES (forma oficial)
os.environ.setdefault("QT_LOGGING_RULES", 
    "kf.kirigami.warning=false;"
    "qt.quick.controls.style.warning=false;"
    "qt.quick.controls.warning=false;"
    "qt.core.socketnotifier.warning=false"  # Suprimir QSocketNotifier warnings
)

# Tentar importar QApplication de QtWidgets (necessário para QSystemTrayIcon)
# Nota: PySide2 do sistema está em /usr/lib/python3/dist-packages
# O PYTHONPATH já está configurado no script jira-quick-task.sh
try:
    from PySide2.QtWidgets import QApplication  # type: ignore[import]
except ImportError as e:
    print("Erro: PySide2.QtWidgets não está disponível.", file=sys.stderr)
    print("", file=sys.stderr)
    print("  O pacote python3-pyside2.qtwidgets não está instalado.", file=sys.stderr)
    print("  Instale com: sudo apt install python3-pyside2.qtwidgets", file=sys.stderr)
    print("", file=sys.stderr)
    print("  Ou execute o setup.sh que verifica e instala automaticamente:", file=sys.stderr)
    print("    ./setup.sh", file=sys.stderr)
    print("", file=sys.stderr)
    print(f"  Detalhes do erro: {e}", file=sys.stderr)
    sys.exit(1)

from PySide2.QtGui import QIcon  # type: ignore[import]
from PySide2.QtCore import QUrl  # type: ignore[import]
from PySide2.QtQml import QQmlApplicationEngine, qmlRegisterType  # type: ignore[import]

# Tentar importar qInstallMessageHandler (disponível no Qt 5.5+)
try:
    from PySide2.QtCore import qInstallMessageHandler  # type: ignore[import]
    HAS_MESSAGE_HANDLER = True
except ImportError:
    HAS_MESSAGE_HANDLER = False


def qt_message_handler(msg_type, context, message):
    """Filtro de mensagens do Qt para suprimir avisos específicos"""
    # Converter mensagem para string de forma segura
    try:
        if hasattr(message, '__str__'):
            msg_str = str(message)
        else:
            msg_str = repr(message)
    except:
        msg_str = ""
    
    # Suprimir mensagem QSocketNotifier
    if "QSocketNotifier" in msg_str or "Can only be used with threads started with QThread" in msg_str:
        return
    
    # Para outras mensagens, não fazer nada (suprimir tudo)
    # Se quiser ver outras mensagens, pode usar print aqui
    pass

# Adicionar diretório raiz ao path
ROOT_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT_DIR))

from src.models.issue_model import IssueModel
from src.models.my_issues_model import MyIssuesModel
from src.jira_service import JiraService
from src.single_instance_manager import SingleInstanceManager
from src.system_tray_manager import SystemTrayManager
from src.global_shortcut_manager import GlobalShortcutManager


class FilteredStderr:
    """Wrapper para stderr que filtra mensagens QSocketNotifier"""
    def __init__(self, original_stderr):
        self.original_stderr = original_stderr
    
    def write(self, message):
        # Filtrar mensagem QSocketNotifier
        if "QSocketNotifier" in message and "Can only be used with threads started with QThread" in message:
            return  # Não escrever essa mensagem
        self.original_stderr.write(message)
    
    def flush(self):
        self.original_stderr.flush()
    
    def __getattr__(self, name):
        return getattr(self.original_stderr, name)


def main():
    """Função principal da aplicação"""
    # Redirecionar stderr para filtrar mensagens QSocketNotifier
    filtered_stderr = FilteredStderr(sys.stderr)
    sys.stderr = filtered_stderr
    
    # Instalar filtro de mensagens do Qt para suprimir QSocketNotifier
    # IMPORTANTE: Deve ser feito ANTES de criar QApplication
    if HAS_MESSAGE_HANDLER:
        try:
            qInstallMessageHandler(qt_message_handler)
        except Exception:
            # Se falhar, continuar sem filtro
            pass
    
    # Verificar single instance ANTES de criar QApplication
    single_instance = SingleInstanceManager("jira-quick-task")
    if not single_instance.try_lock():
        # Outra instância já está rodando
        # Mensagem removida (debug)
        sys.exit(0)
    
    # Criar QApplication (necessário para QSystemTrayIcon)
    app = QApplication(sys.argv)

    # Definir ícone da aplicação
    # Primeiro tenta usar o ícone do tema (jira-quick-task)
    # Se não encontrar, usa o SVG local como fallback
    icon_path = ROOT_DIR / "assets" / "jira-quick-task.svg"
    if icon_path.exists():
        app.setWindowIcon(QIcon(str(icon_path)))
    else:
        # Fallback: tentar usar o ícone do tema pelo nome
        app.setWindowIcon(QIcon.fromTheme("jira-quick-task"))

    # Desabilitar fallback session management (solução semântica)
    # Isso evita o warning "Session management error"
    QApplication.setFallbackSessionManagementEnabled(False)
    
    # Configurar para não fechar quando última janela fecha (manter no tray)
    app.setQuitOnLastWindowClosed(False)

    # Configurar para fechar com Ctrl+C
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    # Configurar estilo KDE (necessário para usar tema KDE fora do Plasma)
    # Para Kirigami 2 (KF5), usar "org.kde.desktop" ou "org.kde.desktopstyle"
    # O "org.kde.desktop" é mais compatível e resolve o warning do platform plugin
    # Não definir se já estiver definido (permite override via variável de ambiente)
    if not os.environ.get("QT_QUICK_CONTROLS_STYLE"):
        os.environ["QT_QUICK_CONTROLS_STYLE"] = "org.kde.desktop"
    
    # Controls 1.4 (SplitView) usa variável de ambiente diferente
    # Definir estilo Base para Controls 1 para evitar warning de estilo não encontrado
    if not os.environ.get("QT_QUICK_CONTROLS_1_STYLE"):
        os.environ["QT_QUICK_CONTROLS_1_STYLE"] = "Plasma"

    # Criar engine QML
    engine = QQmlApplicationEngine()

    # Adicionar caminho do QML ao engine para encontrar módulos locais
    qml_dir = Path(__file__).parent / "qml"
    engine.addImportPath(str(qml_dir.absolute()))

    # Adicionar caminho do Qt 5 do sistema para encontrar módulos Kirigami 2
    # Agora que usamos pacotes do sistema (Qt 5.15), os plugins são compatíveis
    qt5_qml_path = "/usr/lib/x86_64-linux-gnu/qt5/qml"
    if os.path.exists(qt5_qml_path):
        engine.addImportPath(qt5_qml_path)

    # Registrar tipos Python no QML
    qmlRegisterType(IssueModel, "JiraQuickTask", 1, 0, "IssueModel")
    qmlRegisterType(JiraService, "JiraQuickTask", 1, 0, "JiraService")

    # Criar instâncias do modelo e serviço
    issue_model = IssueModel()
    my_issues_model = MyIssuesModel()
    jira_service = JiraService()
    
    # Criar SystemTrayManager
    tray_manager = SystemTrayManager(icon_path, app)
    
    # Criar GlobalShortcutManager
    shortcut_manager = GlobalShortcutManager(app)
    
    # Expor ao contexto QML
    engine.rootContext().setContextProperty("issueModel", issue_model)
    engine.rootContext().setContextProperty("myIssuesModel", my_issues_model)
    engine.rootContext().setContextProperty("jiraService", jira_service)
    engine.rootContext().setContextProperty("trayManager", tray_manager)

    # Variável para armazenar referência à janela principal (será definida depois)
    main_window = None
    
    # Função para esconder janela (minimizar ao tray)
    # Usa closure para acessar main_window quando disponível
    def hide_window():
        """Esconde a janela principal (minimiza ao tray)"""
        nonlocal main_window
        if main_window:
            main_window.hide()
    
    # Função para restaurar janela (será definida depois que main_window estiver disponível)
    def restore_window():
        """Restaura e ativa a janela principal"""
        nonlocal main_window
        if main_window:
            main_window.show()
            main_window.raise_()
            main_window.requestActivate()
    
    # Função para toggle (mostrar/esconder) janela
    def toggle_window():
        """Alterna entre mostrar e esconder a janela"""
        nonlocal main_window
        if main_window:
            if main_window.isVisible():
                # Janela está visível - esconder
                hide_window()
            else:
                # Janela está escondida - mostrar
                restore_window()
    
    # Expor função para esconder janela ao QML (antes de carregar QML)
    engine.rootContext().setContextProperty("hideWindow", hide_window)

    # Carregar QML principal
    # Usar caminho relativo ao arquivo app.py
    qml_path = Path(__file__).parent / "qml" / "Main.qml"
    if not qml_path.exists():
        print(f"Erro: Arquivo QML não encontrado: {qml_path}", file=sys.stderr)
        sys.exit(-1)
    url = QUrl.fromLocalFile(str(qml_path.absolute()))

    engine.load(url)

    # Verificar se a janela foi carregada
    root_objects = engine.rootObjects()
    if not root_objects:
        print("Erro: Não foi possível carregar a interface QML", file=sys.stderr)
        print("Verifique os erros QML acima para mais detalhes.", file=sys.stderr)
        sys.exit(-1)
    
    # Obter referência à janela principal
    main_window = root_objects[0]
    
    # Conectar sinais do tray manager
    # As funções restore_window, hide_window e toggle_window já foram definidas acima
    # e usam closure para acessar main_window
    tray_manager.restoreRequested.connect(restore_window)
    tray_manager.toggleRequested.connect(toggle_window)  # Clique no tray icon faz toggle
    tray_manager.quitRequested.connect(app.quit)
    
    # Conectar sinal do single instance (quando outra instância tenta iniciar)
    single_instance.restoreRequested.connect(restore_window)
    
    # Conectar sinal do shortcut manager (Super+J)
    shortcut_manager.activated.connect(restore_window)
    
    # Registrar atalho global com a janela
    # main_window é um QQuickWindow (Kirigami.ApplicationWindow herda de QQuickWindow)
    try:
        shortcut_manager.register_with_window(main_window)
    except Exception:
        # Aviso removido (debug)
        pass
    
    # Mostrar tray icon
    if tray_manager.is_available():
        tray_manager.show()

    # Executar aplicação
    exit_code = app.exec_()
    
    # Cleanup
    shortcut_manager.unregister()
    single_instance.cleanup()
    
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
