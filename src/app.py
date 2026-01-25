#!/usr/bin/env python3
"""
Jira Quick Task - Aplicação principal PySide6 + Kirigami 6
"""

import os
import sys
import signal
from pathlib import Path
from io import StringIO

# Configurar variáveis de ambiente ANTES de importar Qt
# Suprimir warnings do Kirigami, do estilo (Controls 2), Controls 1 (SplitView) e QSocketNotifier
# usando QT_LOGGING_RULES (forma oficial)
# TEMPORARIAMENTE: Não suprimir erros QML para debug
os.environ.setdefault("QT_LOGGING_RULES", 
    "kf.kirigami.warning=false;"
    "qt.quick.controls.style.warning=false;"
    "qt.quick.controls.warning=false;"
    "qt.core.socketnotifier.warning=false"  # Suprimir QSocketNotifier warnings
)
# Habilitar mensagens QML para debug
os.environ.setdefault("QT_LOGGING_RULES", 
    os.environ.get("QT_LOGGING_RULES", "") + ";"
    "qt.qml.debug=true"
)

# Tentar importar QApplication de QtWidgets (necessário para QSystemTrayIcon)
# Nota: PySide6 do sistema está em /usr/lib/python3/dist-packages
# O PYTHONPATH é configurado no Makefile ou pode ser exportado manualmente
try:
    from PySide6.QtWidgets import QApplication  # type: ignore[import]
except ImportError as e:
    print("Erro: PySide6.QtWidgets não está disponível.", file=sys.stderr)
    print("", file=sys.stderr)
    print("  O pacote python3-pyside6.qtwidgets não está instalado.", file=sys.stderr)
    print("  Instale com: sudo apt install python3-pyside6.qtwidgets", file=sys.stderr)
    print("", file=sys.stderr)
    print(f"  Detalhes do erro: {e}", file=sys.stderr)
    sys.exit(1)

from PySide6.QtGui import QIcon  # type: ignore[import]
from PySide6.QtCore import QUrl  # type: ignore[import]
from PySide6.QtQml import QQmlApplicationEngine, qmlRegisterType  # type: ignore[import]

# Tentar importar qInstallMessageHandler (disponível no Qt 6)
try:
    from PySide6.QtCore import qInstallMessageHandler  # type: ignore[import]
    HAS_MESSAGE_HANDLER = True
except ImportError:
    HAS_MESSAGE_HANDLER = False


def qt_message_handler(msg_type, context, message):
    """Filtro de mensagens do Qt para suprimir avisos específicos"""
    # Importar aqui para evitar import circular
    from src.utils.debug import is_debug_enabled
    
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
    
    # Suprimir erro conhecido do org.kde.desktop TabButton (bug no estilo KDE)
    # Este é um bug conhecido onde o estilo tenta acessar propriedade 'y' de um objeto null
    if ("TabButton.qml" in msg_str or "org/kde/desktop/TabButton" in msg_str) and \
       ("Cannot read property 'y' of null" in msg_str or "TypeError" in msg_str):
        return  # Suprimir este warning específico
    
    # Se debug estiver ativado, mostrar todas as mensagens QML (incluindo console.log)
    if is_debug_enabled():
        if "qml" in msg_str.lower() or "QML" in msg_str or context.category in ["qml", "qml.import"]:
            # Mostrar todas as mensagens QML quando debug está ativado
            type_names = {0: "Debug", 1: "Warning", 2: "Critical", 3: "Fatal", 4: "Info"}
            type_name = type_names.get(msg_type, f"Type{msg_type}")
            print(f"QML [{type_name}]: {msg_str}", file=sys.stderr)
            if context.file:
                print(f"  File: {context.file}:{context.line}", file=sys.stderr)
        return
    
    # Se debug não estiver ativado, mostrar apenas erros críticos
    if "qml" in msg_str.lower() or "QML" in msg_str or context.category in ["qml", "qml.import"]:
        # Mostrar apenas erros críticos, não warnings do estilo KDE
        if msg_type in [4, 5]:  # QtCriticalMsg ou QtFatalMsg
            print(f"QML Message [{msg_type}]: {msg_str}", file=sys.stderr)
            if context.file:
                print(f"  File: {context.file}:{context.line}", file=sys.stderr)
    
    # Para outras mensagens, não fazer nada (suprimir tudo)
    pass

# Adicionar diretório raiz ao path
ROOT_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT_DIR))

from src.models.issue_model import IssueModel
from src.models.my_issues_model import MyIssuesModel
from src.models.settings_model import SettingsModel
from src.jira_service import JiraService
from src.single_instance_manager import SingleInstanceManager
from src.system_tray_manager import SystemTrayManager
from src.global_shortcut_manager import GlobalShortcutManager
from src.utils.debug import debug_log


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
        sys.exit(0)
    
    # Criar QApplication (necessário para QSystemTrayIcon)
    app = QApplication(sys.argv)

    # Definir ícone da aplicação (Flatpak: ícone está em /app/share/icons)
    flatpak_icon = Path("/app/share/icons/hicolor/scalable/apps/org.kde.jira-quick-task.svg")
    icon_path = flatpak_icon  # Usar mesmo se não existir (SystemTrayManager tem fallbacks)
    if flatpak_icon.exists():
        app.setWindowIcon(QIcon(str(flatpak_icon)))
    else:
        app.setWindowIcon(QIcon.fromTheme("jira-quick-task"))

    # Configurar para não fechar quando última janela fecha (manter no tray)
    app.setQuitOnLastWindowClosed(False)

    # Configurar para fechar com Ctrl+C
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    # Configurar estilo KDE (necessário para usar tema KDE fora do Plasma)
    # Para Kirigami 6 (KF6), usar "org.kde.desktop" ou "org.kde.desktopstyle"
    # O problema: org.kde.desktop tem um bug conhecido com TabButton (TypeError: Cannot read property 'y' of null)
    # Solução: usar "Material" ou "Basic" como fallback, ou "org.kde.desktopstyle" se disponível
    # Não definir se já estiver definido (permite override via variável de ambiente)
    if not os.environ.get("QT_QUICK_CONTROLS_STYLE"):
        # Tentar usar org.kde.desktopstyle primeiro (mais estável)
        # Se não funcionar, o usuário pode definir QT_QUICK_CONTROLS_STYLE=Material ou Basic
        os.environ["QT_QUICK_CONTROLS_STYLE"] = "org.kde.desktopstyle"

    # Criar engine QML
    engine = QQmlApplicationEngine()

    # Adicionar caminho do QML ao engine para encontrar módulos locais
    qml_dir = Path(__file__).parent / "qml"
    engine.addImportPath(str(qml_dir.absolute()))

    # Flatpak: usar caminhos do runtime KDE Platform
    # BaseApp tem /app/qml, mas Kirigami vem do runtime em /usr/qml
    qml_paths = [
        "/app/qml",  # Módulos QML do BaseApp
        "/usr/qml",  # Módulos QML do KDE Platform runtime (inclui Kirigami)
    ]
    for path in qml_paths:
        if os.path.exists(path):
            engine.addImportPath(path)

    # Registrar tipos Python no QML
    qmlRegisterType(IssueModel, "JiraQuickTask", 1, 0, "IssueModel")
    qmlRegisterType(JiraService, "JiraQuickTask", 1, 0, "JiraService")

    # Criar instâncias do modelo e serviço
    debug_log("App", "main", "Criando modelos e serviços...")
    try:
        debug_log("App", "main", "Criando IssueModel...")
        issue_model = IssueModel()
        debug_log("App", "main", "IssueModel criado com sucesso")
    except Exception as e:
        print(f"✗ Erro ao criar IssueModel: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        raise
    
    try:
        debug_log("App", "main", "Criando MyIssuesModel...")
        my_issues_model = MyIssuesModel()
        debug_log("App", "main", "MyIssuesModel criado com sucesso")
    except Exception as e:
        print(f"✗ Erro ao criar MyIssuesModel: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        raise
    
    try:
        debug_log("App", "main", "Criando JiraService...")
        jira_service = JiraService()
        debug_log("App", "main", "JiraService criado com sucesso")
    except Exception as e:
        print(f"✗ Erro ao criar JiraService: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        raise
    
    try:
        debug_log("App", "main", "Criando SettingsModel...")
        settings_model = SettingsModel()
        debug_log("App", "main", "SettingsModel criado com sucesso")
    except Exception as e:
        print(f"✗ Erro ao criar SettingsModel: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        raise
    
    # Criar SystemTrayManager
    try:
        tray_manager = SystemTrayManager(icon_path, app)
    except Exception as e:
        import traceback
        print(f"Erro ao criar SystemTrayManager: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        # Continuar sem tray manager
        tray_manager = None
    
    # Criar GlobalShortcutManager
    shortcut_manager = GlobalShortcutManager(app)
    
    # Criar modelos e serviços de timer (após tray_manager para poder usar o tray_icon)
    timer_model = None
    timer_service = None
    notification_service = None
    worklog_sync_service = None
    worklog_db = None
    
    try:
        from src.models.timer_model import TimerModel
        from src.services.timer_service import TimerService
        from src.services.notification_service import NotificationService
        from src.services.worklog_sync_service import WorklogSyncService
        from src.database.worklog_db import WorklogDatabase
        from config.config_manager import ConfigManager
        
        debug_log("App", "main", "Criando WorklogDatabase...")
        worklog_db = WorklogDatabase()
        debug_log("App", "main", "WorklogDatabase criado com sucesso")
        
        debug_log("App", "main", "Criando TimerModel...")
        timer_model = TimerModel()
        debug_log("App", "main", "TimerModel criado com sucesso")
        
        debug_log("App", "main", "Criando TimerService...")
        config_manager = ConfigManager()
        timer_service = TimerService(timer_model, config_manager, worklog_db)
        debug_log("App", "main", "TimerService criado com sucesso")
        
        debug_log("App", "main", "Criando NotificationService...")
        tray_icon = None
        if tray_manager and hasattr(tray_manager, 'tray_icon'):
            tray_icon = tray_manager.tray_icon
        notification_service = NotificationService(tray_icon=tray_icon)
        debug_log("App", "main", "NotificationService criado com sucesso")
        
        debug_log("App", "main", "Criando WorklogSyncService...")
        worklog_sync_service = WorklogSyncService(worklog_db, config_manager)
        debug_log("App", "main", "WorklogSyncService criado com sucesso")
        
        # Criar TimerTrayManager para ícone separado do timer
        timer_tray_manager = None
        try:
            debug_log("App", "main", "Criando TimerTrayManager...")
            from src.timer_tray_manager import TimerTrayManager
            timer_tray_manager = TimerTrayManager(icon_path, app)
            debug_log("App", "main", "TimerTrayManager criado com sucesso")
            
            # Conectar sinais do timerModel para atualizar o timerTrayManager
            if timer_model and timer_tray_manager:
                def update_tray_timer():
                    if timer_model and timer_tray_manager:
                        timer_tray_manager.update_timer_state(
                            timer_model.issueKey or "",
                            timer_model.elapsedSeconds or 0,
                            timer_model.state or "idle",
                            timer_model.currentPomodoro or 0
                        )
                        # Mostrar/esconder tray icon baseado no estado
                        if timer_model.state in ["running", "paused"]:
                            timer_tray_manager.show()
                        else:
                            timer_tray_manager.hide()
                
                # Conectar sinais de mudança de estado
                timer_model.stateChanged.connect(update_tray_timer)
                timer_model.timeUpdated.connect(update_tray_timer)
                timer_model.issueKeyChanged.connect(update_tray_timer)
                
                # Conectar sinais do timerTrayManager para controlar o timer
                # restoreRequested será gerenciado pelo Main.qml via Connections
                timer_tray_manager.pauseRequested.connect(lambda: timer_service.pause() if timer_service else None)
                timer_tray_manager.resumeRequested.connect(lambda: timer_service.resume() if timer_service else None)
                timer_tray_manager.stopRequested.connect(lambda: timer_service.stop() if timer_service else None)
                
                # Atualizar estado inicial
                update_tray_timer()
        except Exception as e:
            print(f"⚠ Aviso: Erro ao criar TimerTrayManager: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc(file=sys.stderr)
            # Não falhar completamente - timer tray é feature opcional
    except Exception as e:
        print(f"✗ Erro ao criar serviços de timer: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        # Não falhar completamente - timer é feature opcional
    
    # Expor ao contexto QML
    debug_log("App", "main", "Expondo modelos ao contexto QML...")
    try:
        engine.rootContext().setContextProperty("issueModel", issue_model)
        debug_log("App", "main", "issueModel exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor issueModel: {e}", file=sys.stderr)
        raise
    
    try:
        engine.rootContext().setContextProperty("myIssuesModel", my_issues_model)
        debug_log("App", "main", "myIssuesModel exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor myIssuesModel: {e}", file=sys.stderr)
        raise
    
    try:
        engine.rootContext().setContextProperty("jiraService", jira_service)
        debug_log("App", "main", "jiraService exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor jiraService: {e}", file=sys.stderr)
        raise
    
    try:
        engine.rootContext().setContextProperty("settingsModel", settings_model)
        debug_log("App", "main", "settingsModel exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor settingsModel: {e}", file=sys.stderr)
        raise
    
    try:
        engine.rootContext().setContextProperty("trayManager", tray_manager)
        debug_log("App", "main", "trayManager exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor trayManager: {e}", file=sys.stderr)
        raise
    
    # Expor serviços de timer ao contexto QML
    # IMPORTANTE: Sempre expor, mesmo se None, para evitar erros no QML
    try:
        engine.rootContext().setContextProperty("timerModel", timer_model)
        if timer_model:
            debug_log("App", "main", "timerModel exposto ao contexto QML")
        else:
            debug_log("App", "main", "timerModel é None - não foi criado")
            print("⚠ Aviso: timerModel não está disponível (timer é feature opcional)", file=sys.stderr)
    except Exception as e:
        print(f"✗ Erro ao expor timerModel: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
    
    try:
        engine.rootContext().setContextProperty("timerService", timer_service)
        if timer_service:
            debug_log("App", "main", "timerService exposto ao contexto QML")
        else:
            debug_log("App", "main", "timerService é None - não foi criado")
            print("⚠ Aviso: timerService não está disponível (timer é feature opcional)", file=sys.stderr)
    except Exception as e:
        print(f"✗ Erro ao expor timerService: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
    
    try:
        engine.rootContext().setContextProperty("notificationService", notification_service)
        if notification_service:
            debug_log("App", "main", "notificationService exposto ao contexto QML")
        else:
            debug_log("App", "main", "notificationService é None - não foi criado")
    except Exception as e:
        print(f"✗ Erro ao expor notificationService: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
    
    try:
        engine.rootContext().setContextProperty("worklogSyncService", worklog_sync_service)
        if worklog_sync_service:
            debug_log("App", "main", "worklogSyncService exposto ao contexto QML")
        else:
            debug_log("App", "main", "worklogSyncService é None - não foi criado")
    except Exception as e:
        print(f"✗ Erro ao expor worklogSyncService: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
    
    # Expor timerTrayManager ao contexto QML
    try:
        timer_tray_manager_var = timer_tray_manager if 'timer_tray_manager' in locals() else None
        engine.rootContext().setContextProperty("timerTrayManager", timer_tray_manager_var)
        if timer_tray_manager_var:
            debug_log("App", "main", "timerTrayManager exposto ao contexto QML")
        else:
            debug_log("App", "main", "timerTrayManager é None - não foi criado")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao expor timerTrayManager: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
    
    # WorklogDatabase não é QObject, então não pode ser exposto diretamente
    # Será acessado via WorklogSyncService quando necessário

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
    debug_log("App", "main", "Carregando QML...")
    qml_path = Path(__file__).parent / "qml" / "Main.qml"
    debug_log("App", "main", "Caminho QML: %s", qml_path)
    debug_log("App", "main", "Arquivo existe: %s", qml_path.exists())
    
    if not qml_path.exists():
        print(f"Erro: Arquivo QML não encontrado: {qml_path}", file=sys.stderr)
        sys.exit(-1)
    
    url = QUrl.fromLocalFile(str(qml_path.absolute()))
    debug_log("App", "main", "URL QML: %s", url.toString())

    debug_log("App", "main", "Chamando engine.load()...")
    engine.load(url)
    debug_log("App", "main", "engine.load() concluído")

    # Verificar se a janela foi carregada
    debug_log("App", "main", "Verificando objetos raiz...")
    root_objects = engine.rootObjects()
    debug_log("App", "main", "Número de objetos raiz: %d", len(root_objects))
    
    if not root_objects:
        print("Erro: Não foi possível carregar a interface QML", file=sys.stderr)
        print("Verifique os erros QML acima para mais detalhes.", file=sys.stderr)
        
        # Tentar ler o arquivo QML para verificar se há problemas óbvios
        debug_log("App", "main", "Tentando ler o arquivo QML para diagnóstico...")
        try:
            with open(qml_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
                debug_log("App", "main", "Arquivo QML tem %d linhas", len(lines))
                # Verificar as primeiras linhas para problemas de import
                debug_log("App", "main", "Primeiras 30 linhas do QML:")
                for i, line in enumerate(lines[:30], 1):
                    debug_log("App", "main", "  %3d: %s", i, line.rstrip())
        except Exception as e:
            debug_log("App", "main", "Erro ao ler arquivo QML: %s", e)
        
        # Verificar se o problema pode ser com imports
        debug_log("App", "main", "Verificando imports QML...")
        debug_log("App", "main", "Import paths configurados: %s", engine.importPathList())
        
        # Verificar se os módulos necessários estão disponíveis
        debug_log("App", "main", "Verificando disponibilidade de módulos QML...")
        import_paths = engine.importPathList()
        for path in import_paths:
            debug_log("App", "main", "Verificando path: %s", path)
            if os.path.exists(path):
                debug_log("App", "main", "  Path existe")
                # Listar alguns arquivos se for diretório
                if os.path.isdir(path):
                    try:
                        items = os.listdir(path)[:10]  # Primeiros 10 itens
                        debug_log("App", "main", "  Conteúdo (primeiros 10): %s", items)
                        # Verificar especificamente se Kirigami está presente
                        if "org" in items:
                            org_path = os.path.join(path, "org")
                            if os.path.isdir(org_path):
                                org_items = os.listdir(org_path)
                                debug_log("App", "main", "  Conteúdo de org/: %s", org_items)
                                if "kde" in org_items:
                                    kde_path = os.path.join(org_path, "kde")
                                    if os.path.isdir(kde_path):
                                        kde_items = os.listdir(kde_path)
                                        debug_log("App", "main", "  Conteúdo de org/kde/: %s", kde_items)
                    except Exception as e:
                        debug_log("App", "main", "  Erro ao listar: %s", e)
            else:
                debug_log("App", "main", "  Path não existe")
        
        sys.exit(-1)
    
    debug_log("App", "main", "QML carregado com sucesso")
    
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
        pass
    
    # Mostrar tray icon
    def show_tray_icon():
        """Função para mostrar o tray icon (pode ser chamada múltiplas vezes)"""
        try:
            # Verificar diretamente se system tray está disponível
            from PySide6.QtWidgets import QSystemTrayIcon
            tray_available = QSystemTrayIcon.isSystemTrayAvailable()
            
            if tray_available:
                # Tentar usar is_available() primeiro (que tenta criar se necessário)
                if tray_manager.is_available():
                    tray_manager.show()
                elif hasattr(tray_manager, 'tray_icon') and tray_manager.tray_icon is not None:
                    # Tray icon existe mas is_available() retornou False - mostrar diretamente
                    tray_manager.show()
                else:
                    # Tentar criar tray icon diretamente
                    tray_manager._setup_tray_icon()
                    if hasattr(tray_manager, 'tray_icon') and tray_manager.tray_icon is not None:
                        tray_manager.show()
        except Exception:
            pass  # Falha silenciosa - tray icon não é crítico
    
    # Tentar mostrar imediatamente
    show_tray_icon()
    
    # Também tentar mostrar após um pequeno delay (para garantir que QApplication está pronto)
    from PySide6.QtCore import QTimer
    QTimer.singleShot(100, show_tray_icon)  # Tentar novamente após 100ms
    QTimer.singleShot(500, show_tray_icon)  # Tentar novamente após 500ms (fallback)

    # Executar aplicação
    exit_code = app.exec()
    
    # Cleanup
    shortcut_manager.unregister()
    single_instance.cleanup()
    
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
