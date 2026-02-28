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
os.environ.setdefault(
    "QT_LOGGING_RULES",
    "kf.kirigami.warning=false;"
    "qt.quick.controls.style.warning=false;"
    "qt.quick.controls.warning=false;"
    "qt.core.socketnotifier.warning=false",  # Suprimir QSocketNotifier warnings
)
# Habilitar mensagens QML para debug
os.environ.setdefault(
    "QT_LOGGING_RULES", os.environ.get("QT_LOGGING_RULES", "") + ";" "qt.qml.debug=true"
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
from PySide6.QtCore import QUrl, QObject, QTimer, Property  # type: ignore[import]
from PySide6.QtQml import QQmlApplicationEngine, qmlRegisterType  # type: ignore[import]
from PySide6.QtCore import Slot  # type: ignore[import]
import json
import time

# Tentar importar qInstallMessageHandler (disponível no Qt 6)
try:
    from PySide6.QtCore import qInstallMessageHandler  # type: ignore[import]

    HAS_MESSAGE_HANDLER = True
except ImportError:
    HAS_MESSAGE_HANDLER = False


# #region agent log
def _get_debug_log_path():
    from src.utils.debug import get_debug_log_path as _g

    return _g()


def _write_debug_ndjson(location, message, data=None, hypothesis_id=None):
    try:
        log_path = _get_debug_log_path()
        payload = {
            "timestamp": int(time.time() * 1000),
            "location": location,
            "message": message,
            "sessionId": "debug-session",
            "runId": "run1",
        }
        if data is not None:
            payload["data"] = data
        if hypothesis_id is not None:
            payload["hypothesisId"] = hypothesis_id
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(payload, ensure_ascii=False) + "\n")
    except Exception:
        pass


class DebugLogger(QObject):
    """Exposed to QML for instrumentation."""

    @Slot(str, str)
    def log(self, location, message):
        _write_debug_ndjson(location, message, hypothesis_id="C")

    # #endregion


def qt_message_handler(msg_type, context, message):
    """Filtro de mensagens do Qt para suprimir avisos específicos"""
    # Importar aqui para evitar import circular
    from src.utils.debug import is_debug_enabled

    # Converter mensagem para string de forma segura
    try:
        if hasattr(message, "__str__"):
            msg_str = str(message)
        else:
            msg_str = repr(message)
    except Exception:
        msg_str = ""

    # #region agent log
    try:
        mt = int(msg_type)
    except (TypeError, ValueError):
        mt = 0
    if mt >= 2 or "binding" in msg_str.lower() or "abort" in msg_str.lower():
        _write_debug_ndjson(
            "qt_message_handler",
            msg_str[:500],
            data={"msg_type": mt, "file": getattr(context, "file", "")},
            hypothesis_id="A" if "binding" in msg_str.lower() else "E",
        )
    # #endregion

    # Suprimir mensagem QSocketNotifier
    if (
        "QSocketNotifier" in msg_str
        or "Can only be used with threads started with QThread" in msg_str
    ):
        return

    # Suprimir erro conhecido do org.kde.desktop TabButton (bug no estilo KDE)
    # Este é um bug conhecido onde o estilo tenta acessar propriedade 'y' de um objeto null
    if ("TabButton.qml" in msg_str or "org/kde/desktop/TabButton" in msg_str) and (
        "Cannot read property 'y' of null" in msg_str or "TypeError" in msg_str
    ):
        return  # Suprimir este warning específico

    # Se debug estiver ativado, mostrar todas as mensagens QML (incluindo console.log)
    if is_debug_enabled():
        if (
            "qml" in msg_str.lower()
            or "QML" in msg_str
            or context.category in ["qml", "qml.import"]
        ):
            # Mostrar todas as mensagens QML quando debug está ativado
            type_names = {
                0: "Debug",
                1: "Warning",
                2: "Critical",
                3: "Fatal",
                4: "Info",
            }
            type_name = type_names.get(msg_type, f"Type{msg_type}")
            print(f"QML [{type_name}]: {msg_str}", file=sys.stderr)
            if context.file:
                print(f"  File: {context.file}:{context.line}", file=sys.stderr)
        return

    # Se debug não estiver ativado, mostrar apenas erros críticos
    if (
        "qml" in msg_str.lower()
        or "QML" in msg_str
        or context.category in ["qml", "qml.import"]
    ):
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
from src.models.work_item_model import WorkItemModel
from src.models.my_work_items_model import MyWorkItemsModel
from src.models.settings_model import SettingsModel
from src.jira_service import JiraService
from src.atlassian_service import AtlassianService
from src.github_service import GitHubService
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
        if (
            "QSocketNotifier" in message
            and "Can only be used with threads started with QThread" in message
        ):
            return  # Não escrever essa mensagem
        self.original_stderr.write(message)

    def flush(self):
        self.original_stderr.flush()

    def __getattr__(self, name):
        return getattr(self.original_stderr, name)


def main():
    """Função principal da aplicação"""
    # #region agent log
    _log_path = _get_debug_log_path()
    print(f"[DEBUG] debug.log path: {_log_path}", file=sys.stderr)
    _write_debug_ndjson("app.main:start", "main entered", hypothesis_id="A")
    # #endregion
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
    flatpak_icon = Path(
        "/app/share/icons/hicolor/scalable/apps/org.kde.jira-quick-task.svg"
    )
    icon_path = (
        flatpak_icon  # Usar mesmo se não existir (SystemTrayManager tem fallbacks)
    )
    if flatpak_icon.exists():
        app.setWindowIcon(QIcon(str(flatpak_icon)))
    else:
        app.setWindowIcon(QIcon.fromTheme("jira-quick-task"))

    # Configurar para não fechar quando última janela fecha (manter no tray)
    app.setQuitOnLastWindowClosed(False)

    # Configurar para fechar com Ctrl+C
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    # Configurar estilo Qt Quick Controls (evitar SIGABRT/134 com TabBar no estilo KDE)
    # org.kde.desktop/desktopstyle podem abortar com TabButton (binding ou null 'y').
    # TextArea no estilo KDE pode emitir "Binding loop detected for property width"; Basic não.
    # Basic evita o crash; override via QT_QUICK_CONTROLS_STYLE se quiser outro estilo.
    if not os.environ.get("QT_QUICK_CONTROLS_STYLE"):
        # Flatpak: usar Basic para evitar exit 134 (SIGABRT) ao abrir/alternar abas
        in_flatpak = os.path.exists("/.flatpak-info") or os.environ.get("FLATPAK_ID")
        if in_flatpak:
            os.environ["QT_QUICK_CONTROLS_STYLE"] = "Basic"
        else:
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
    qmlRegisterType(AtlassianService, "JiraQuickTask", 1, 0, "AtlassianService")

    # Criar instâncias do modelo e serviço
    debug_log("App", "main", "Criando modelos e serviços...")
    try:
        debug_log("App", "main", "Criando IssueModel (formulário de criação)...")
        issue_model = IssueModel()
        debug_log("App", "main", "IssueModel criado com sucesso")
    except Exception as e:
        print(f"✗ Erro ao criar IssueModel: {e}", file=sys.stderr)
        import traceback

        traceback.print_exc(file=sys.stderr)
        raise

    try:
        debug_log(
            "App", "main", "Criando IssueModel (detalhe/edição em Minhas Issues)..."
        )
        editing_issue_model = IssueModel()
        debug_log("App", "main", "editingIssueModel criado com sucesso")
    except Exception as e:
        print(f"✗ Erro ao criar editingIssueModel: {e}", file=sys.stderr)
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

    # Modelos workItem isolados (abas 7 e 8)
    try:
        debug_log("App", "main", "Criando work_item_model (formulário criação work item)...")
        work_item_model = WorkItemModel()
        editing_work_item_model = WorkItemModel()
        my_work_items_model = MyWorkItemsModel()
        debug_log("App", "main", "work_item_model, editing_work_item_model, my_work_items_model criados")
    except Exception as e:
        print(f"✗ Erro ao criar modelos workItem: {e}", file=sys.stderr)
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

    atlassian_service = None
    try:
        debug_log("App", "main", "Criando AtlassianService...")
        atlassian_service = AtlassianService()
        debug_log("App", "main", "AtlassianService criado com sucesso")
    except Exception as e:
        print(f"✗ Erro ao criar AtlassianService: {e}", file=sys.stderr)
        raise

    # Conectar cache de Assets aos modelos de issue (Valor entregue / Plataformas afetadas)
    # #region agent log
    _write_debug_ndjson(
        "app.main:before_get_assets_cache",
        "calling get_assets_cache",
        hypothesis_id="B",
    )
    # #endregion
    assets_cache = jira_service.get_assets_cache()
    if assets_cache:
        # #region agent log
        _write_debug_ndjson(
            "app.main:before_set_assets_cache",
            "calling set_assets_cache",
            data={"has_cache": True},
            hypothesis_id="B",
        )
        # #endregion
        issue_model.set_assets_cache(assets_cache)
        editing_issue_model.set_assets_cache(assets_cache)
        work_item_model.set_assets_cache(assets_cache)
        editing_work_item_model.set_assets_cache(assets_cache)
    assets_cache_atlassian = atlassian_service.get_assets_cache() if atlassian_service else None
    if assets_cache_atlassian:
        work_item_model.set_assets_cache(assets_cache_atlassian)
        editing_work_item_model.set_assets_cache(assets_cache_atlassian)
        # #region agent log
        _write_debug_ndjson(
            "app.main:after_set_assets_cache",
            "set_assets_cache done",
            hypothesis_id="B",
        )
        # #endregion

    def on_assets_cache_loaded(success, message):
        # Atualizar modelos na próxima volta do event loop para evitar cascata
        # de sinais síncronos que pode provocar assert/SIGABRT no Qt/QML.
        def update_models():
            issue_model.on_assets_cache_loaded()
            editing_issue_model.on_assets_cache_loaded()
            work_item_model.on_assets_cache_loaded()
            editing_work_item_model.on_assets_cache_loaded()

        QTimer.singleShot(0, update_models)

    def on_atlassian_assets_cache_loaded(success, message):
        def update_work_item_models():
            work_item_model.on_assets_cache_loaded()
            editing_work_item_model.on_assets_cache_loaded()
        QTimer.singleShot(0, update_work_item_models)
        if success and atlassian_service:
            cache = atlassian_service.get_assets_cache()
            if cache:
                work_item_model.set_assets_cache(cache)
                editing_work_item_model.set_assets_cache(cache)

    jira_service.assetsCacheLoaded.connect(on_assets_cache_loaded)
    if atlassian_service:
        atlassian_service.assetsCacheLoaded.connect(on_atlassian_assets_cache_loaded)

    # ConfigManager único: mesmo config em memória para JiraService, GitHubService, SettingsModel e TimerService
    from config.config_manager import ConfigManager as AppConfigManager

    app_config_manager = AppConfigManager()
    # Injetar config compartilhado no JiraService e no AtlassianService (para enrichment refletir configurações salvas)
    jira_service._config = app_config_manager
    if atlassian_service:
        atlassian_service._config = app_config_manager
    try:
        debug_log("App", "main", "Criando GitHubService...")
        github_service = GitHubService(config_manager=app_config_manager)
        debug_log("App", "main", "GitHubService criado com sucesso")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao criar GitHubService: {e}", file=sys.stderr)
        github_service = None

    # Google services: criados em lazy loading após engine.load() para não bloquear a GUI
    # Placeholders null serão expostos antes do load; serviços reais após load

    try:
        debug_log("App", "main", "Criando SettingsModel...")
        settings_model = SettingsModel(config_manager=app_config_manager)
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
    worklog_service = None
    timesheet_model = None

    try:
        from src.models.timer_model import TimerModel
        from src.services.timer_service import TimerService
        from src.services.notification_service import NotificationService
        from src.services.worklog_sync_service import WorklogSyncService
        from src.database.worklog_db import WorklogDatabase

        debug_log("App", "main", "Criando WorklogDatabase...")
        worklog_db = WorklogDatabase(
            db_path=app_config_manager.get_config_dir() / "worklogs.db"
        )
        debug_log("App", "main", "WorklogDatabase criado com sucesso")

        debug_log("App", "main", "Criando TimerModel...")
        timer_model = TimerModel()
        debug_log("App", "main", "TimerModel criado com sucesso")

        debug_log("App", "main", "Criando TimerService...")
        timer_service = TimerService(timer_model, app_config_manager, worklog_db)
        debug_log("App", "main", "TimerService criado com sucesso")

        # Conectar sinal saved do SettingsModel para recarregar configurações no TimerService
        if settings_model and timer_service:

            def on_settings_saved():
                """Recarrega configurações de Pomodoro no TimerService quando salvas"""
                debug_log(
                    "App",
                    "on_settings_saved",
                    "Configurações salvas, recarregando no TimerService",
                )
                timer_service.reload_config()
                if github_service and hasattr(github_service, "notifyConfigChanged"):
                    github_service.notifyConfigChanged()

            settings_model.saved.connect(on_settings_saved)
            debug_log(
                "App", "main", "Sinal saved conectado para recarregar configurações"
            )

        debug_log("App", "main", "Criando NotificationService...")
        tray_icon = None
        if tray_manager and hasattr(tray_manager, "tray_icon"):
            tray_icon = tray_manager.tray_icon
        notification_service = NotificationService(tray_icon=tray_icon)
        # Conectar settingsModel ao notificationService
        if notification_service and settings_model:
            notification_service.set_settings_model(settings_model)
        debug_log("App", "main", "NotificationService criado com sucesso")

        debug_log("App", "main", "Criando WorklogSyncService...")
        worklog_sync_service = WorklogSyncService(worklog_db, app_config_manager)
        debug_log("App", "main", "WorklogSyncService criado com sucesso")

        # WorklogService e TimesheetModel para tela de Timesheet
        jira_client = jira_service.get_jira_client() if jira_service else None
        if jira_client and app_config_manager:
            try:
                from src.services.worklog_service import WorklogService
                from src.models.timesheet_model import TimesheetModel

                worklog_service = WorklogService(
                    jira_client=jira_client,
                    config=app_config_manager,
                )
                user_email = app_config_manager.get_jira_login() or ""
                timesheet_model = TimesheetModel(
                    worklog_service=worklog_service,
                    config=app_config_manager,
                    user_email=user_email,
                )
                timesheet_model.loadInitial()
                debug_log("App", "main", "WorklogService e TimesheetModel criados")
                # Invalidação de cache quando worklogs são sincronizados ou registrados
                if worklog_sync_service:
                    worklog_sync_service.syncCompleted.connect(
                        worklog_service.invalidate_cache
                    )
                jira_service.worklogRegistered.connect(worklog_service.invalidate_cache)
            except Exception as e:
                print(
                    f"⚠ Aviso: Erro ao criar WorklogService/TimesheetModel: {e}",
                    file=sys.stderr,
                )
                worklog_service = None
                timesheet_model = None

        # JiraMetadataConfigModel para wizard de configuração de metadata (Issue #25)
        jira_metadata_config_model = None
        try:
            from src.models.jira_metadata_config_model import JiraMetadataConfigModel

            jira_metadata_config_model = JiraMetadataConfigModel(
                jira_client=jira_client,
                config_manager=app_config_manager,
            )
            debug_log("App", "main", "JiraMetadataConfigModel criado")
        except Exception as e:
            print(
                f"⚠ Aviso: Erro ao criar JiraMetadataConfigModel: {e}",
                file=sys.stderr,
            )

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
                            timer_model.currentPomodoro or 0,
                            timer_model.isOnBreak or False,
                        )
                        # Mostrar/esconder tray icon baseado no estado
                        # Mostrar se timer está rodando, pausado, ou em qualquer estado de pausa/break
                        timer_is_active = (
                            timer_model.state in ["running", "paused"]
                            or timer_model.isWaitingBreakDecision
                            or timer_model.isOnBreak
                            or timer_model.isWaitingBreakEndDecision
                        )
                        if timer_is_active:
                            timer_tray_manager.show()
                        else:
                            timer_tray_manager.hide()

                # Conectar sinais de mudança de estado
                timer_model.stateChanged.connect(update_tray_timer)
                timer_model.timeUpdated.connect(update_tray_timer)
                timer_model.issueKeyChanged.connect(update_tray_timer)

                # Também conectar a mudanças nos estados de pausa/break
                def on_break_state_changed():
                    """Atualiza tray quando estados de pausa mudam"""
                    update_tray_timer()

                # Conectar a timeUpdated que é emitido quando propriedades de break mudam
                timer_model.timeUpdated.connect(on_break_state_changed)

                # Conectar sinais do timerTrayManager para controlar o timer
                # restoreRequested será gerenciado pelo Main.qml via Connections
                timer_tray_manager.pauseRequested.connect(
                    lambda: timer_service.pause() if timer_service else None
                )
                # resumeRequested não faz mais sentido - pausas usam cronômetro, mas manter para compatibilidade
                timer_tray_manager.resumeRequested.connect(
                    lambda: timer_service.resume() if timer_service else None
                )
                timer_tray_manager.stopRequested.connect(
                    lambda: timer_service.stop() if timer_service else None
                )

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

    # ClipboardHelper para colar imagens em descrição/comentários
    try:
        from src.utils.clipboard_helper import ClipboardHelper

        clipboard_helper = ClipboardHelper(app)
        debug_log("App", "main", "ClipboardHelper criado com sucesso")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao criar ClipboardHelper: {e}", file=sys.stderr)
        clipboard_helper = None

    # GitCommandHelper para comandos git clone no popover de Development
    git_command_helper = None
    try:
        from src.utils.git_command_helper import GitCommandHelper

        git_command_helper = GitCommandHelper()
        debug_log("App", "main", "GitCommandHelper criado com sucesso")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao criar GitCommandHelper: {e}", file=sys.stderr)

    # VoiceInputService (entrada por voz): opcional; gravação local (sounddevice), transcrição/LLM via LocalAI no host
    voice_input_service = None
    try:
        from config.config_manager import ConfigManager as VoiceConfigManager
        from src.services.voice_input_service import VoiceInputService

        _voice_config = VoiceConfigManager()
        voice_input_service = VoiceInputService(
            issue_model, _voice_config, editing_issue_model=editing_issue_model
        )
        if voice_input_service.isAvailable():
            debug_log("App", "main", "VoiceInputService criado com sucesso")
        else:
            debug_log(
                "App", "main", "VoiceInputService criado (deps de voz não instaladas)"
            )
    except Exception as e:
        print(f"⚠ Aviso: Erro ao criar VoiceInputService: {e}", file=sys.stderr)
        voice_input_service = None

    # voiceTranscriptionService: segunda instância para abas work item (7 e 8)
    voice_transcription_service = None
    try:
        from config.config_manager import ConfigManager as _VoiceTranscriptionConfig
        from src.services.voice_input_service import VoiceInputService as _VoiceInputServiceClass

        _vts_config = _VoiceTranscriptionConfig()
        voice_transcription_service = _VoiceInputServiceClass(
            work_item_model,
            _vts_config,
            editing_issue_model=editing_work_item_model,
            expand_overlay_on_process_transcription=True,
        )
        if voice_transcription_service.isAvailable():
            debug_log("App", "main", "voiceTranscriptionService criado com sucesso")
        else:
            debug_log(
                "App", "main",
                "voiceTranscriptionService criado (deps de voz não instaladas)",
            )
    except Exception as e:
        print(f"⚠ Aviso: Erro ao criar voiceTranscriptionService: {e}", file=sys.stderr)
        voice_transcription_service = None

    # Expor ao contexto QML
    debug_log("App", "main", "Expondo modelos ao contexto QML...")
    try:
        engine.rootContext().setContextProperty("issueModel", issue_model)
        debug_log("App", "main", "issueModel exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor issueModel: {e}", file=sys.stderr)
        raise

    try:
        engine.rootContext().setContextProperty(
            "editingIssueModel", editing_issue_model
        )
        debug_log("App", "main", "editingIssueModel exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor editingIssueModel: {e}", file=sys.stderr)
        raise

    try:
        engine.rootContext().setContextProperty("myIssuesModel", my_issues_model)
        debug_log("App", "main", "myIssuesModel exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor myIssuesModel: {e}", file=sys.stderr)
        raise

    try:
        engine.rootContext().setContextProperty("workItemModel", work_item_model)
        debug_log("App", "main", "workItemModel exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor workItemModel: {e}", file=sys.stderr)
        raise

    try:
        engine.rootContext().setContextProperty(
            "editingWorkItemModel", editing_work_item_model
        )
        debug_log("App", "main", "editingWorkItemModel exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor editingWorkItemModel: {e}", file=sys.stderr)
        raise

    try:
        engine.rootContext().setContextProperty("myWorkItemsModel", my_work_items_model)
        debug_log("App", "main", "myWorkItemsModel exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor myWorkItemsModel: {e}", file=sys.stderr)
        raise

    try:
        engine.rootContext().setContextProperty("jiraService", jira_service)
        debug_log("App", "main", "jiraService exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor jiraService: {e}", file=sys.stderr)
        raise

    try:
        engine.rootContext().setContextProperty("atlassianService", atlassian_service)
        debug_log("App", "main", "atlassianService exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor atlassianService: {e}", file=sys.stderr)
        raise

    try:
        engine.rootContext().setContextProperty(
            "githubService", github_service if github_service else None
        )
        if github_service:
            debug_log("App", "main", "githubService exposto ao contexto QML")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao expor githubService: {e}", file=sys.stderr)

    # Google services: Opção B - criados após load e atribuídos ao root

    try:
        engine.rootContext().setContextProperty("settingsModel", settings_model)
        debug_log("App", "main", "settingsModel exposto ao contexto QML")
    except Exception as e:
        print(f"✗ Erro ao expor settingsModel: {e}", file=sys.stderr)
        raise

    try:
        engine.rootContext().setContextProperty(
            "jiraMetadataConfigModel",
            jira_metadata_config_model if jira_metadata_config_model else None,
        )
        if jira_metadata_config_model:
            debug_log("App", "main", "jiraMetadataConfigModel exposto ao contexto QML")
    except Exception as e:
        print(
            f"⚠ Aviso: Erro ao expor jiraMetadataConfigModel: {e}",
            file=sys.stderr,
        )

    try:
        engine.rootContext().setContextProperty(
            "atlassianMetadataConfigModel",
            jira_metadata_config_model if jira_metadata_config_model else None,
        )
        if jira_metadata_config_model:
            debug_log("App", "main", "atlassianMetadataConfigModel exposto ao contexto QML")
    except Exception as e:
        print(
            f"⚠ Aviso: Erro ao expor atlassianMetadataConfigModel: {e}",
            file=sys.stderr,
        )

    try:
        engine.rootContext().setContextProperty(
            "clipboardHelper", clipboard_helper if clipboard_helper else None
        )
        if clipboard_helper:
            debug_log("App", "main", "clipboardHelper exposto ao contexto QML")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao expor clipboardHelper: {e}", file=sys.stderr)

    try:
        engine.rootContext().setContextProperty(
            "gitCommandHelper",
            git_command_helper if git_command_helper else None,
        )
        if git_command_helper:
            debug_log("App", "main", "gitCommandHelper exposto ao contexto QML")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao expor gitCommandHelper: {e}", file=sys.stderr)

    try:
        engine.rootContext().setContextProperty(
            "voiceInputService",
            voice_input_service if voice_input_service else None,
        )
        if voice_input_service:
            debug_log("App", "main", "voiceInputService exposto ao contexto QML")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao expor voiceInputService: {e}", file=sys.stderr)

    try:
        engine.rootContext().setContextProperty(
            "voiceTranscriptionService",
            voice_transcription_service if voice_transcription_service else None,
        )
        if voice_transcription_service:
            debug_log("App", "main", "voiceTranscriptionService exposto ao contexto QML")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao expor voiceTranscriptionService: {e}", file=sys.stderr)

    # MarkdownPreviewRenderer para modo Edit/Preview em description e comentários
    try:
        from src.services.markdown_preview_renderer import MarkdownPreviewRenderer

        markdown_preview_renderer = MarkdownPreviewRenderer()
        engine.rootContext().setContextProperty(
            "markdownPreviewRenderer", markdown_preview_renderer
        )
        debug_log("App", "main", "markdownPreviewRenderer exposto ao contexto QML")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao expor markdownPreviewRenderer: {e}", file=sys.stderr)
        engine.rootContext().setContextProperty("markdownPreviewRenderer", None)

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
            print(
                "⚠ Aviso: timerModel não está disponível (timer é feature opcional)",
                file=sys.stderr,
            )
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
            print(
                "⚠ Aviso: timerService não está disponível (timer é feature opcional)",
                file=sys.stderr,
            )
    except Exception as e:
        print(f"✗ Erro ao expor timerService: {e}", file=sys.stderr)
        import traceback

        traceback.print_exc(file=sys.stderr)

    try:
        engine.rootContext().setContextProperty(
            "notificationService", notification_service
        )
        if notification_service:
            debug_log("App", "main", "notificationService exposto ao contexto QML")
        else:
            debug_log("App", "main", "notificationService é None - não foi criado")
    except Exception as e:
        print(f"✗ Erro ao expor notificationService: {e}", file=sys.stderr)
        import traceback

        traceback.print_exc(file=sys.stderr)

    try:
        engine.rootContext().setContextProperty(
            "worklogSyncService", worklog_sync_service
        )
        if worklog_sync_service:
            debug_log("App", "main", "worklogSyncService exposto ao contexto QML")
        else:
            debug_log("App", "main", "worklogSyncService é None - não foi criado")
    except Exception as e:
        print(f"✗ Erro ao expor worklogSyncService: {e}", file=sys.stderr)
        import traceback

        traceback.print_exc(file=sys.stderr)

    try:
        engine.rootContext().setContextProperty("timesheetViewModel", timesheet_model)
        if timesheet_model:
            debug_log("App", "main", "timesheetViewModel exposto ao contexto QML")
        else:
            debug_log("App", "main", "timesheetViewModel é None - não foi criado")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao expor timesheetViewModel: {e}", file=sys.stderr)

    # Expor timerTrayManager ao contexto QML
    try:
        timer_tray_manager_var = (
            timer_tray_manager if "timer_tray_manager" in locals() else None
        )
        engine.rootContext().setContextProperty(
            "timerTrayManager", timer_tray_manager_var
        )
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
            debug_log(
                "App", "main", "Criando gerenciador de janela flutuante do timer..."
            )
            from src.timer_floating_window import TimerFloatingWindow

            # Caminho para o QML do conteúdo do timer
            qml_content_path = (
                Path(__file__).parent
                / "qml"
                / "components"
                / "timer"
                / "TimerFloatingPanelContent.qml"
            )

            # Estado centralizado de visibilidade da janela
            # "auto" = visibilidade controlada automaticamente pelo estado do timer
            # "hidden" = usuário minimizou manualmente, deve permanecer escondida
            # "visible" = usuário restaurou manualmente, deve permanecer visível
            _window_visibility_state = "auto"  # "auto" | "hidden" | "visible"

            # Função auxiliar para ativar janela (reutilizável)
            def _activate_timer_window():
                """
                Ativa janela do timer com sequência padrão do Qt.

                IMPORTANTE - Limitação do Wayland:
                No Wayland, requestActivate() pode não funcionar devido a limitações do protocolo
                XDG Activation. Esta é uma limitação conhecida do Qt/Wayland, não um bug do nosso código.

                Referências:
                - Qt Documentation: https://doc.qt.io/qt-6/qwindow.html#requestActivate
                - Wayland XDG Activation Protocol: https://wayland.app/protocols/xdg-activation-v1

                Em ambientes Wayland, a janela pode não ser trazida para o primeiro plano automaticamente.
                O usuário pode precisar clicar manualmente na janela ou usar o ícone do system tray.
                """
                if not timer_floating_window:
                    return
                # Sequência padrão do Qt para ativar janela
                timer_floating_window.raise_()
                timer_floating_window.requestActivate()
                # Tentar activate() se disponível (QWindow pode ter este método)
                try:
                    if hasattr(timer_floating_window, "activate"):
                        timer_floating_window.activate()
                except Exception as e:
                    debug_log(
                        "App",
                        "_activate_timer_window",
                        "activate() não disponível ou falhou: %s",
                        e,
                    )

                # Hipótese 1: Garantir foco no root object QML para capturar eventos
                # IMPORTANTE: Só chamar forceActiveFocus() se a janela estiver visível
                # Isso evita roubar foco quando a janela não está sendo mostrada
                if timer_floating_window.isVisible():
                    try:
                        root_object = timer_floating_window.rootObject()
                        if root_object:
                            # Chamar forceActiveFocus() no root object QML apenas se janela estiver visível
                            if hasattr(root_object, "forceActiveFocus"):
                                root_object.forceActiveFocus()
                                debug_log(
                                    "App",
                                    "_activate_timer_window",
                                    "forceActiveFocus() chamado no root object (janela visível)",
                                )
                            else:
                                debug_log(
                                    "App",
                                    "_activate_timer_window",
                                    "root object não tem forceActiveFocus()",
                                )
                    except Exception as e:
                        debug_log(
                            "App",
                            "_activate_timer_window",
                            "Erro ao chamar forceActiveFocus() no root object: %s",
                            e,
                        )
                else:
                    debug_log(
                        "App",
                        "_activate_timer_window",
                        "Janela não está visível, não chamando forceActiveFocus() para evitar roubo de foco",
                    )

            def create_timer_window():
                """Cria a janela flutuante do timer"""
                nonlocal timer_floating_window
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

                        def __init__(
                            self,
                            window_ref,
                            timer_model_ref,
                            timer_service_ref,
                            parent=None,
                        ):
                            super().__init__(parent)
                            # Manter referência forte à janela para evitar garbage collection
                            self._window_ref = window_ref
                            self._timer_model_ref = timer_model_ref
                            self._timer_service_ref = timer_service_ref

                        @Slot()
                        def hide(self):
                            """Esconde a janela flutuante do timer (chamado do QML)"""
                            nonlocal _window_visibility_state
                            debug_log(
                                "App",
                                "TimerWindowHelper.hide",
                                "Usuário minimizou janela manualmente",
                            )
                            # Marcar que o usuário quer a janela escondida
                            _window_visibility_state = "hidden"
                            # Atualizar visibilidade baseado no novo estado
                            if timer_floating_window:
                                _update_window_visibility()

                        @Slot()
                        def stopTimer(self):
                            """Para o timer (fallback quando timerService não está disponível no QML)"""
                            if self._timer_service_ref:
                                self._timer_service_ref.stop()

                    # Criar instância do helper COM A JANELA COMO PARENT
                    # Isso garante que o helper não seja garbage collected enquanto a janela existir
                    timer_window_helper = TimerWindowHelper(
                        timer_floating_window,
                        timer_model,
                        timer_service,
                        parent=timer_floating_window,
                    )

                    # Expor modelos e serviços ao contexto da janela ANTES de carregar QML
                    root_context = timer_floating_window.rootContext()
                    root_context.setContextProperty("timerModel", timer_model)
                    root_context.setContextProperty("timerService", timer_service)
                    root_context.setContextProperty("settingsModel", settings_model)
                    root_context.setContextProperty("hideWindow", timer_window_helper)

                    # Carregar QML após expor propriedades
                    timer_floating_window.load_qml()

                    # Função para restaurar janela do timer do tray
                    def restore_timer_window():
                        """Restaura a janela do timer do tray para primeiro plano"""
                        nonlocal _window_visibility_state
                        debug_log(
                            "App",
                            "restore_timer_window",
                            "Usuário restaurou janela do tray",
                        )
                        # Mudar estado para "visible" (usuário restaurou manualmente)
                        _window_visibility_state = "visible"
                        if timer_floating_window:
                            _update_window_visibility()
                            # Garantir ativação explícita após restaurar (usar função auxiliar)
                            if timer_floating_window.isVisible():
                                _activate_timer_window()

                    # Conectar sinal de restore do tray manager
                    if timer_tray_manager:
                        timer_tray_manager.restoreRequested.connect(
                            restore_timer_window
                        )

                    # Conectar sinais de breakDecisionRequested, breakStarted e breakEnded
                    if timer_service:
                        # Conectar sinal breakStarted para tocar som quando pausa manual inicia
                        timer_service.breakStarted.connect(
                            lambda break_type: (
                                notification_service.play_pomodoro_sound(break_type)
                                if notification_service
                                else None
                            )
                        )

                        def on_break_decision_requested(pomodoro_num, break_type):
                            # Alerta de pausa - sempre mostrar janela (mesmo se estava minimizada)
                            nonlocal _window_visibility_state
                            if _window_visibility_state != "visible":
                                _window_visibility_state = "visible"
                                debug_log(
                                    "App",
                                    "on_break_decision_requested",
                                    "Alerta de pausa, mudando estado para visible (era: %s)",
                                    _window_visibility_state,
                                )
                            else:
                                debug_log(
                                    "App",
                                    "on_break_decision_requested",
                                    "Alerta de pausa, estado já é visible",
                                )
                            # Atualizar visibilidade (função centralizada)
                            _update_window_visibility()

                            # Garantir ativação explícita quando alerta aparece (mesmo se janela já estiver visível)
                            if (
                                timer_floating_window
                                and timer_floating_window.isVisible()
                            ):
                                _activate_timer_window()

                            # Tocar som com tipo de pausa
                            if notification_service:
                                notification_service.play_pomodoro_sound(break_type)

                        def on_break_ended():
                            # Atualizar visibilidade (função centralizada decide baseado no estado)
                            _update_window_visibility()

                            # Tocar som de volta da pausa (opcional; só se configurado)
                            if notification_service:
                                notification_service.play_return_from_break_sound()

                        # Conectar aos sinais do timerModel
                        if timer_model:
                            timer_model.breakDecisionRequested.connect(
                                on_break_decision_requested
                            )
                            timer_model.breakEnded.connect(on_break_ended)

                            # Callback para quando aceita pausa (isOnBreak muda para True)
                            def on_is_on_break_changed(value: bool):
                                """Callback quando isOnBreak muda - atualizar visibilidade"""
                                # Pausa aceita - sempre mostrar janela (mesmo se estava minimizada)
                                nonlocal _window_visibility_state
                                if value:  # isOnBreak mudou para True
                                    if _window_visibility_state != "visible":
                                        _window_visibility_state = "visible"
                                        debug_log(
                                            "App",
                                            "on_is_on_break_changed",
                                            "Pausa aceita, mudando estado para visible (era: %s)",
                                            _window_visibility_state,
                                        )
                                    else:
                                        debug_log(
                                            "App",
                                            "on_is_on_break_changed",
                                            "Pausa aceita, estado já é visible",
                                        )
                                    # Atualizar visibilidade (função centralizada)
                                    _update_window_visibility()

                            # Conectar diretamente aos signals específicos
                            timer_model.isOnBreakChanged.connect(on_is_on_break_changed)
                            timer_model.isWaitingBreakDecisionChanged.connect(
                                lambda v: _update_window_visibility() if v else None
                            )
                            timer_model.isWaitingBreakEndDecisionChanged.connect(
                                lambda v: _update_window_visibility() if v else None
                            )

                    debug_log(
                        "App", "main", "Janela flutuante do timer criada com sucesso"
                    )
                except Exception as e:
                    print(
                        f"⚠ Aviso: Erro ao criar janela flutuante do timer: {e}",
                        file=sys.stderr,
                    )
                    import traceback

                    traceback.print_exc(file=sys.stderr)

            def destroy_timer_window():
                """Destrói a janela flutuante do timer"""
                nonlocal timer_floating_window
                if timer_floating_window:
                    timer_floating_window.close()
                    timer_floating_window = None
                    debug_log("App", "main", "Janela flutuante do timer destruída")

            def _update_window_visibility():
                """
                Função centralizada que decide se a janela deve estar visível ou escondida.
                Este é o ÚNICO lugar que chama show()/hide() na janela do timer.

                Lógica simplificada:
                - Se usuário forçou hidden e timer requer visível: manter escondido (respeitar escolha do usuário)
                - Se usuário forçou visible ou auto requer visível: mostrar
                - Se timer não requer visível: esconder e resetar para auto quando idle
                """
                nonlocal _window_visibility_state

                if not timer_model or not timer_floating_window:
                    return

                # Verificar se o timer requer janela visível (baseado no estado do timer)
                timer_requires_visible = (
                    timer_model.state in ["running", "paused"]
                    or timer_model.isWaitingBreakDecision
                    or timer_model.isOnBreak
                    or timer_model.isWaitingBreakEndDecision
                )

                # Lógica simplificada: se usuário forçou hidden, respeitar
                # Se usuário forçou visible e timer requer, mostrar
                # Caso contrário, usar auto (baseado em timer_requires_visible)
                if _window_visibility_state == "hidden" and timer_requires_visible:
                    # Timer requer visível mas usuário minimizou - manter escondido
                    if timer_floating_window.isVisible():
                        timer_floating_window.hide()
                elif _window_visibility_state == "visible" or (
                    _window_visibility_state == "auto" and timer_requires_visible
                ):
                    # Mostrar se usuário restaurou ou auto requer
                    if not timer_floating_window.isVisible():
                        timer_floating_window.show()
                        _activate_timer_window()
                elif not timer_requires_visible:
                    # Timer não requer visível - esconder e resetar para auto
                    if timer_floating_window.isVisible():
                        timer_floating_window.hide()
                    if timer_model.state == "idle":
                        _window_visibility_state = "auto"

            def update_timer_window_visibility():
                """Wrapper que garante que a janela existe antes de atualizar visibilidade"""
                if not timer_floating_window:
                    # Verificar se precisa criar a janela
                    if timer_model and (
                        timer_model.state in ["running", "paused"]
                        or timer_model.isWaitingBreakDecision
                        or timer_model.isOnBreak
                        or timer_model.isWaitingBreakEndDecision
                    ):
                        create_timer_window()
                # Atualizar visibilidade (função centralizada)
                _update_window_visibility()

                # Garantir que quando timer para completamente, estado é resetado
                if timer_model and timer_model.state == "idle":
                    nonlocal _window_visibility_state
                    if not (
                        timer_model.isWaitingBreakDecision
                        or timer_model.isOnBreak
                        or timer_model.isWaitingBreakEndDecision
                    ):
                        # Timer realmente parado (não está em pausa) - resetar estado
                        if _window_visibility_state != "auto":
                            _window_visibility_state = "auto"
                            debug_log(
                                "App",
                                "update_timer_window_visibility",
                                "Timer completamente parado, resetando estado para auto",
                            )
                            # Garantir que janela está escondida
                            if (
                                timer_floating_window
                                and timer_floating_window.isVisible()
                            ):
                                timer_floating_window.hide()

            # Rastrear estado anterior para detectar transições
            _prev_timer_state = timer_model.state if timer_model else "idle"

            def on_timer_state_changed(new_state):
                """Callback quando estado do timer muda - detecta início de timer"""
                nonlocal _window_visibility_state, _prev_timer_state

                # Detectar transição "idle" -> "running" (novo timer iniciou)
                if _prev_timer_state == "idle" and new_state == "running":
                    debug_log(
                        "App",
                        "on_timer_state_changed",
                        "Novo timer iniciou (idle -> running), resetando estado para auto",
                    )
                    # Resetar para "auto" para garantir comportamento padrão
                    # Isso permite que _update_window_visibility() mostre a janela automaticamente
                    _window_visibility_state = "auto"
                    # Atualizar visibilidade (aplicará comportamento padrão)
                    _update_window_visibility()
                    # Garantir ativação explícita após mostrar
                    if timer_floating_window and timer_floating_window.isVisible():
                        _activate_timer_window()

                _prev_timer_state = new_state
                # Também atualizar visibilidade normalmente
                update_timer_window_visibility()

            # Conectar sinais do timerModel para gerenciar a janela
            timer_model.stateChanged.connect(on_timer_state_changed)
            # Também conectar a timeUpdated para capturar mudanças em isOnBreak
            timer_model.timeUpdated.connect(update_timer_window_visibility)

            # Verificar estado inicial
            update_timer_window_visibility()

            debug_log(
                "App", "main", "Gerenciador de janela flutuante do timer configurado"
            )
    except Exception as e:
        print(
            f"⚠ Aviso: Erro ao configurar janela flutuante do timer: {e}",
            file=sys.stderr,
        )
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

    # #region agent log
    _write_debug_ndjson(
        "app.main:before_engine_load", "about to engine.load", hypothesis_id="A"
    )
    debug_logger = DebugLogger(app)
    engine.rootContext().setContextProperty("debugLog", debug_logger)
    # #endregion
    debug_log("App", "main", "Chamando engine.load()...")
    engine.load(url)
    # #region agent log
    _write_debug_ndjson(
        "app.main:after_engine_load", "engine.load returned", hypothesis_id="A"
    )

    def _log_500ms():
        _write_debug_ndjson("app.main:500ms", "500ms after load", hypothesis_id="D")

    def _log_2s():
        _write_debug_ndjson("app.main:2s", "2s after load", hypothesis_id="D")

    QTimer.singleShot(500, _log_500ms)
    QTimer.singleShot(2000, _log_2s)
    # #endregion
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
            with open(qml_path, "r", encoding="utf-8") as f:
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
        debug_log(
            "App", "main", "Import paths configurados: %s", engine.importPathList()
        )

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
                                debug_log(
                                    "App", "main", "  Conteúdo de org/: %s", org_items
                                )
                                if "kde" in org_items:
                                    kde_path = os.path.join(org_path, "kde")
                                    if os.path.isdir(kde_path):
                                        kde_items = os.listdir(kde_path)
                                        debug_log(
                                            "App",
                                            "main",
                                            "  Conteúdo de org/kde/: %s",
                                            kde_items,
                                        )
                    except Exception as e:
                        debug_log("App", "main", "  Erro ao listar: %s", e)
            else:
                debug_log("App", "main", "  Path não existe")

        sys.exit(-1)

    debug_log("App", "main", "QML carregado com sucesso")
    _write_debug_ndjson("App.main", "after_qml_loaded", "step1", hypothesis_id="S")

    # Opção B: criar serviços Google e atribuir ao root
    try:
        from src.google_auth_service import GoogleAuthService
        from src.google_calendar_service import GoogleCalendarService
        from src.google_tasks_service import GoogleTasksService
        from src.google_drive_comments_service import GoogleDriveCommentsService

        auth_svc = GoogleAuthService(config_manager=app_config_manager)
        cal_svc = GoogleCalendarService(config_manager=app_config_manager)
        tasks_svc = GoogleTasksService(config_manager=app_config_manager)
        drive_comments_svc = GoogleDriveCommentsService(
            config_manager=app_config_manager
        )
        cal_svc.authRequired.connect(auth_svc._update_authorized)
        tasks_svc.authRequired.connect(auth_svc._update_authorized)
        drive_comments_svc.authRequired.connect(auth_svc._update_authorized)

        root_obj = root_objects[0]
        root_obj.setProperty("_ctxGoogleAuthService", auth_svc)
        root_obj.setProperty("_ctxGoogleCalendarService", cal_svc)
        root_obj.setProperty("_ctxGoogleTasksService", tasks_svc)
        root_obj.setProperty("_ctxGoogleDriveCommentsService", drive_comments_svc)
        debug_log("App", "main", "Serviços Google atribuídos ao root")
    except Exception as e:
        print(f"⚠ Aviso: Erro ao criar serviços Google: {e}", file=sys.stderr)

    # Obter referência à janela principal
    main_window = root_objects[0]
    _write_debug_ndjson("App.main", "after_main_window", "step2", hypothesis_id="S")

    # Conectar sinais do tray manager
    # As funções restore_window, hide_window e toggle_window já foram definidas acima
    # e usam closure para acessar main_window
    tray_manager.restoreRequested.connect(restore_window)
    tray_manager.toggleRequested.connect(
        toggle_window
    )  # Clique no tray icon faz toggle
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
    _write_debug_ndjson(
        "App.main", "after_shortcut_register", "step3", hypothesis_id="S"
    )

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
                elif (
                    hasattr(tray_manager, "tray_icon")
                    and tray_manager.tray_icon is not None
                ):
                    # Tray icon existe mas is_available() retornou False - mostrar diretamente
                    tray_manager.show()
                else:
                    # Tentar criar tray icon diretamente
                    tray_manager._setup_tray_icon()
                    if (
                        hasattr(tray_manager, "tray_icon")
                        and tray_manager.tray_icon is not None
                    ):
                        tray_manager.show()
        except Exception:
            pass  # Falha silenciosa - tray icon não é crítico

    # Verificar disponibilidade do system tray antes de tentar mostrar
    from PySide6.QtWidgets import QSystemTrayIcon

    def show_tray_icon():
        try:
            if not QSystemTrayIcon.isSystemTrayAvailable():
                return  # Tray não disponível, não tentar
            if tray_manager and tray_manager.is_available():
                tray_manager.show()
            elif (
                hasattr(tray_manager, "tray_icon")
                and tray_manager.tray_icon is not None
            ):
                # Tray icon existe mas is_available() retornou False - mostrar diretamente
                tray_manager.show()
            else:
                # Tentar criar tray icon diretamente
                if hasattr(tray_manager, "_setup_tray_icon"):
                    tray_manager._setup_tray_icon()
                    if (
                        hasattr(tray_manager, "tray_icon")
                        and tray_manager.tray_icon is not None
                    ):
                        tray_manager.show()
        except Exception:
            pass  # Falha silenciosa - tray icon não é crítico

    # Tentar mostrar imediatamente (após QApplication estar pronto)
    show_tray_icon()
    _write_debug_ndjson("App.main", "before_app_exec", "step4", hypothesis_id="S")

    # Executar aplicação
    exit_code = app.exec()

    # Cleanup
    shortcut_manager.unregister()
    single_instance.cleanup()

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
