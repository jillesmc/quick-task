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
        
        # Conectar sinal saved do SettingsModel para recarregar configurações no TimerService
        if settings_model and timer_service:
            def on_settings_saved():
                """Recarrega configurações de Pomodoro no TimerService quando salvas"""
                debug_log("App", "on_settings_saved", "Configurações salvas, recarregando no TimerService")
                timer_service.reload_config()
            
            settings_model.saved.connect(on_settings_saved)
            debug_log("App", "main", "Sinal saved conectado para recarregar configurações")
        
        debug_log("App", "main", "Criando NotificationService...")
        tray_icon = None
        if tray_manager and hasattr(tray_manager, 'tray_icon'):
            tray_icon = tray_manager.tray_icon
        notification_service = NotificationService(tray_icon=tray_icon)
        # Conectar settingsModel ao notificationService
        if notification_service and settings_model:
            notification_service.set_settings_model(settings_model)
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
    
    # Criar janela flutuante do timer (gerenciada em Python para drag suave)
    timer_floating_window = None
    try:
        if timer_model and timer_service:
            debug_log("App", "main", "Criando gerenciador de janela flutuante do timer...")
            from src.timer_floating_window import TimerFloatingWindow
            
            # Caminho para o QML do conteúdo do timer
            qml_content_path = Path(__file__).parent / "qml" / "components" / "timer" / "TimerFloatingPanelContent.qml"
            
            # Variável para lembrar estado de visibilidade antes do alerta
            _was_minimized_before_alert = False
            # Flag para indicar que o usuário restaurou manualmente a janela
            _user_restored_manually = False
            # Flag para indicar que o usuário minimizou durante a pausa
            _user_minimized_during_break = False
            
            def create_timer_window():
                """Cria a janela flutuante do timer"""
                nonlocal timer_floating_window, _was_minimized_before_alert
                if timer_floating_window:
                    return  # Já existe
                
                try:
                    # Criar janela com QML content
                    timer_floating_window = TimerFloatingWindow(str(qml_content_path))
                    
                    # Adicionar import paths ao engine da janela (necessário para Kirigami)
                    qml_dir = Path(__file__).parent / "qml"
                    from PySide6.QtQml import QQmlEngine
                    qml_engine = timer_floating_window.engine()
                    if qml_engine:
                        qml_engine.addImportPath(str(qml_dir.absolute()))
                        
                        # Adicionar paths do sistema
                        qml_paths = ["/app/qml", "/usr/qml"]
                        for path in qml_paths:
                            if os.path.exists(path):
                                qml_engine.addImportPath(path)
                    
                    # Criar um QObject wrapper para expor a função hideWindow ao QML
                    # QQuickView não reconhece funções Python simples como callable no QML
                    # Precisamos usar um QObject com @Slot() para que funcione corretamente
                    from PySide6.QtCore import QObject, Slot
                    
                    class TimerWindowHelper(QObject):
                        """Helper QObject para expor funções da janela do timer ao QML"""
                        def __init__(self, window_ref, timer_model_ref, parent=None):
                            super().__init__(parent)
                            # Manter referência forte à janela para evitar garbage collection
                            self._window_ref = window_ref
                            self._timer_model_ref = timer_model_ref
                        
                        @Slot()
                        def hide(self):
                            """Esconde a janela flutuante do timer (chamado do QML)"""
                            nonlocal _user_minimized_during_break
                            debug_log("App", "TimerWindowHelper.hide", "Escondendo janela do timer")
                            if self._window_ref:
                                debug_log("App", "TimerWindowHelper.hide", "Janela encontrada, chamando hide()")
                                # Se está em pausa, marcar que foi minimizado durante a pausa
                                if self._timer_model_ref and self._timer_model_ref.isOnBreak:
                                    _user_minimized_during_break = True
                                    debug_log("App", "TimerWindowHelper.hide", "Minimizado durante pausa, flag definida")
                                self._window_ref.hide()
                                debug_log("App", "TimerWindowHelper.hide", "hide() chamado com sucesso")
                            else:
                                debug_log("App", "TimerWindowHelper.hide", "AVISO: _window_ref é None")
                    
                    # Criar instância do helper COM A JANELA COMO PARENT
                    # Isso garante que o helper não seja garbage collected enquanto a janela existir
                    timer_window_helper = TimerWindowHelper(timer_floating_window, timer_model, parent=timer_floating_window)
                    
                    # Expor modelos e serviços ao contexto da janela ANTES de carregar QML
                    root_context = timer_floating_window.rootContext()
                    root_context.setContextProperty("timerModel", timer_model)
                    root_context.setContextProperty("timerService", timer_service)
                    root_context.setContextProperty("settingsModel", settings_model)
                    root_context.setContextProperty("hideWindow", timer_window_helper)
                    
                    debug_log("App", "create_timer_window", "Propriedades expostas ao contexto QML da janela flutuante")
                    debug_log("App", "create_timer_window", "hideWindow exposto como TimerWindowHelper QObject (parent: janela)")
                    
                    # Verificar se a propriedade foi exposta corretamente (diagnóstico)
                    try:
                        qml_engine = timer_floating_window.engine()
                        if qml_engine:
                            test_result = qml_engine.evaluate("typeof hideWindow")
                            debug_log("App", "create_timer_window", "Verificação: typeof hideWindow = %s", test_result)
                            # Verificar se o método hide está disponível
                            test_result2 = qml_engine.evaluate("typeof hideWindow.hide")
                            debug_log("App", "create_timer_window", "Verificação: typeof hideWindow.hide = %s", test_result2)
                    except Exception as e:
                        debug_log("App", "create_timer_window", "Erro ao verificar hideWindow: %s", e)
                    
                    # Carregar QML após expor propriedades
                    timer_floating_window.load_qml()
                    
                    # Função para restaurar janela do timer do tray
                    def restore_timer_window():
                        """Restaura a janela do timer do tray para primeiro plano"""
                        nonlocal _user_restored_manually
                        if timer_floating_window:
                            debug_log("App", "restore_timer_window", "Restaurando janela do timer do tray")
                            _user_restored_manually = True
                            timer_floating_window.show()
                            timer_floating_window.raise_()
                            timer_floating_window.requestActivate()
                            debug_log("App", "restore_timer_window", "Janela restaurada e ativada")
                    
                    # Conectar sinal de restore do tray manager
                    if timer_tray_manager:
                        timer_tray_manager.restoreRequested.connect(restore_timer_window)
                    
                    # Conectar sinais de breakDecisionRequested e breakEnded
                    if timer_service:
                        def on_break_decision_requested(pomodoro_num, break_type):
                            nonlocal _was_minimized_before_alert, _user_restored_manually
                            # Salvar estado atual (apenas se não foi restaurado manualmente)
                            if timer_floating_window:
                                if not _user_restored_manually:
                                    _was_minimized_before_alert = not timer_floating_window.isVisible()
                                # Trazer janela para primeiro plano
                                timer_floating_window.show()
                                timer_floating_window.raise_()
                                timer_floating_window.requestActivate()
                            
                            # Tocar som com tipo de pausa
                            if notification_service:
                                notification_service.play_pomodoro_sound(break_type)
                        
                        def on_break_ended():
                            # Trazer janela para primeiro plano novamente
                            if timer_floating_window:
                                timer_floating_window.show()
                                timer_floating_window.raise_()
                                timer_floating_window.requestActivate()
                            
                            # Tocar som (sem tipo específico, usa padrão)
                            if notification_service:
                                notification_service.play_pomodoro_sound()
                        
                        # Conectar ao sinal do timerModel (QML também escuta este)
                        if timer_model:
                            timer_model.breakDecisionRequested.connect(on_break_decision_requested)
                            timer_model.breakEnded.connect(on_break_ended)
                            
                            # Variáveis para rastrear estado anterior das flags de pausa
                            _prev_is_waiting_break_decision = False
                            _prev_is_on_break = False
                            _prev_is_waiting_break_end_decision = False
                            
                            # Conectar mudanças de propriedades para restaurar visibilidade
                            def restore_visibility_if_needed():
                                """Restaura visibilidade se os flags de alerta/pausa foram desativados"""
                                nonlocal _was_minimized_before_alert, _user_restored_manually
                                nonlocal _prev_is_waiting_break_decision, _prev_is_on_break, _prev_is_waiting_break_end_decision
                                
                                if not timer_floating_window or not timer_model:
                                    return
                                
                                # Verificar se houve mudança real nos estados
                                current_waiting = timer_model.isWaitingBreakDecision
                                current_on_break = timer_model.isOnBreak
                                current_waiting_end = timer_model.isWaitingBreakEndDecision
                                
                                # Se não mudou nada, não fazer nada (evitar execução desnecessária)
                                if (current_waiting == _prev_is_waiting_break_decision and
                                    current_on_break == _prev_is_on_break and
                                    current_waiting_end == _prev_is_waiting_break_end_decision):
                                    return
                                
                                # Atualizar estados anteriores
                                _prev_is_waiting_break_decision = current_waiting
                                _prev_is_on_break = current_on_break
                                _prev_is_waiting_break_end_decision = current_waiting_end
                                
                                # Se não está mais em nenhum estado de alerta/pausa
                                if (not current_waiting and 
                                    not current_on_break and 
                                    not current_waiting_end):
                                    # Resetar flag de minimização durante pausa quando pausa termina
                                    nonlocal _user_minimized_during_break
                                    if _user_minimized_during_break:
                                        _user_minimized_during_break = False
                                        debug_log("App", "restore_visibility_if_needed", 
                                                 "Pausa terminou, resetando flag de minimização durante pausa")
                                    
                                    # Se o usuário restaurou manualmente, não esconder
                                    if _user_restored_manually:
                                        debug_log("App", "restore_visibility_if_needed", 
                                                 "Usuário restaurou manualmente, mantendo janela visível")
                                        return
                                    
                                    # Restaurar visibilidade conforme estado anterior
                                    if _was_minimized_before_alert:
                                        debug_log("App", "restore_visibility_if_needed", 
                                                 "Restaurando estado anterior: esconder janela")
                                        timer_floating_window.hide()
                                        _was_minimized_before_alert = False
                                    # Se estava visível, manter visível (já está visível)
                            
                            # Conectar ao sinal timeUpdated que é emitido quando propriedades mudam
                            timer_model.timeUpdated.connect(restore_visibility_if_needed)
                            
                            # Callback para quando aceita pausa (isOnBreak muda para True)
                            def on_is_on_break_changed():
                                """Callback quando isOnBreak muda - garantir que janela vá para primeiro plano"""
                                nonlocal _user_restored_manually, _user_minimized_during_break
                                if timer_model and timer_model.isOnBreak:
                                    if timer_floating_window:
                                        # Se foi minimizado durante pausa anterior, não mostrar
                                        if _user_minimized_during_break:
                                            debug_log("App", "on_is_on_break_changed", 
                                                     "Pausa aceita, mas usuário minimizou anteriormente, mantendo escondida")
                                            return
                                        debug_log("App", "on_is_on_break_changed", 
                                                 "Pausa aceita, trazendo janela para primeiro plano")
                                        timer_floating_window.show()
                                        timer_floating_window.raise_()
                                        timer_floating_window.requestActivate()
                                        # Se foi restaurado manualmente antes, manter a flag
                            
                            # Conectar ao timeUpdated e verificar mudança de isOnBreak
                            # Usar a mesma variável _prev_is_on_break que já está sendo rastreada
                            def check_is_on_break_change():
                                nonlocal _prev_is_on_break
                                if timer_model:
                                    current = timer_model.isOnBreak
                                    if current != _prev_is_on_break:
                                        old_value = _prev_is_on_break
                                        _prev_is_on_break = current
                                        # Se mudou de False para True, chamar callback
                                        if current and not old_value:
                                            on_is_on_break_changed()
                            
                            timer_model.timeUpdated.connect(check_is_on_break_change)
                    
                    debug_log("App", "main", "Janela flutuante do timer criada com sucesso")
                except Exception as e:
                    print(f"⚠ Aviso: Erro ao criar janela flutuante do timer: {e}", file=sys.stderr)
                    import traceback
                    traceback.print_exc(file=sys.stderr)
            
            def destroy_timer_window():
                """Destrói a janela flutuante do timer"""
                nonlocal timer_floating_window
                if timer_floating_window:
                    timer_floating_window.close()
                    timer_floating_window = None
                    debug_log("App", "main", "Janela flutuante do timer destruída")
            
            def update_timer_window_visibility():
                """Atualiza visibilidade da janela baseado no estado do timer"""
                nonlocal _user_restored_manually, _user_minimized_during_break
                if not timer_model:
                    return
                
                # Verificar se está em estado que requer janela visível
                should_be_visible = (
                    timer_model.state in ["running", "paused"] or
                    timer_model.isWaitingBreakDecision or
                    timer_model.isOnBreak or
                    timer_model.isWaitingBreakEndDecision
                )
                
                if should_be_visible:
                    if not timer_floating_window:
                        create_timer_window()
                    if timer_floating_window:
                        # Se o usuário minimizou durante a pausa, não mostrar
                        if timer_model.isOnBreak and _user_minimized_during_break:
                            debug_log("App", "update_timer_window_visibility", 
                                     "Usuário minimizou durante pausa, mantendo janela escondida")
                            return
                        
                        # Se o usuário restaurou manualmente, não forçar mostrar (já está visível)
                        if _user_restored_manually and timer_floating_window.isVisible():
                            debug_log("App", "update_timer_window_visibility", 
                                     "Usuário restaurou manualmente, mantendo janela visível")
                            return
                        
                        # Garantir que a janela seja mostrada após QML estar pronto
                        from PySide6.QtQuick import QQuickView
                        from PySide6.QtCore import QTimer
                        
                        def show_when_ready():
                            if timer_floating_window and timer_floating_window.status() == QQuickView.Status.Ready:
                                timer_floating_window.show()
                                timer_floating_window.raise_()
                                timer_floating_window.requestActivate()
                            else:
                                # Tentar novamente após um delay
                                QTimer.singleShot(200, show_when_ready)
                        
                        # Se já estiver pronto, mostrar imediatamente
                        if timer_floating_window.status() == QQuickView.Status.Ready:
                            timer_floating_window.show()
                            timer_floating_window.raise_()
                            timer_floating_window.requestActivate()
                        else:
                            # Aguardar QML estar pronto
                            show_when_ready()
                else:
                    # Timer parado e não está em pausa/alerta
                    # Resetar flags quando timer realmente parar
                    if timer_model.state == "idle":
                        _user_restored_manually = False
                        _user_minimized_during_break = False
                        debug_log("App", "update_timer_window_visibility", 
                                 "Timer parado, resetando flags de restauração e minimização")
                    
                    if timer_floating_window:
                        timer_floating_window.hide()
            
            # Conectar sinais do timerModel para gerenciar a janela
            timer_model.stateChanged.connect(update_timer_window_visibility)
            
            # Verificar estado inicial
            update_timer_window_visibility()
            
            debug_log("App", "main", "Gerenciador de janela flutuante do timer configurado")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao configurar janela flutuante do timer: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        # Não falhar completamente - janela flutuante é feature opcional
    
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
