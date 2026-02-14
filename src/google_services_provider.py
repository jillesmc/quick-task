"""
Google services provider exposed as QML singleton.
Creates GoogleAuthService, GoogleCalendarService, GoogleTasksService on first access (lazy loading).
Uses engine.rootContext().contextProperty("googleConfigManager") for config.
"""

from PySide6.QtCore import QObject, Property  # type: ignore[import]
from PySide6.QtQml import QQmlApplicationEngine, qmlRegisterSingletonType  # type: ignore[import]

from src.utils.debug import debug_log


def _create_google_services_provider(engine: QQmlApplicationEngine) -> "GoogleServicesProvider":
    """Factory for singleton: creates services using config from context."""
    config = engine.rootContext().contextProperty("googleConfigManager")
    if not config:
        debug_log("GoogleServicesProvider", "create", "googleConfigManager not in context")
        return GoogleServicesProvider(None, None, None)

    return create_provider_for_config(config)


def create_provider_for_config(config_manager) -> "GoogleServicesProvider":
    """Create provider with services. Use for singleton factory or context property."""
    from src.google_auth_service import GoogleAuthService
    from src.google_calendar_service import GoogleCalendarService
    from src.google_tasks_service import GoogleTasksService

    debug_log("GoogleServicesProvider", "create", "Creating GoogleAuthService...")
    auth_svc = GoogleAuthService(config_manager=config_manager)
    debug_log("GoogleServicesProvider", "create", "Creating GoogleCalendarService...")
    cal_svc = GoogleCalendarService(config_manager=config_manager)
    debug_log("GoogleServicesProvider", "create", "Creating GoogleTasksService...")
    tasks_svc = GoogleTasksService(config_manager=config_manager)

    cal_svc.authRequired.connect(auth_svc._update_authorized)
    tasks_svc.authRequired.connect(auth_svc._update_authorized)

    debug_log("GoogleServicesProvider", "create", "Google services created")
    return GoogleServicesProvider(auth_svc, cal_svc, tasks_svc)


class GoogleServicesProvider(QObject):
    """
    QML singleton exposing Google services.
    Created lazily when first accessed via create(engine).
    """

    def __init__(self, auth_service, calendar_service, tasks_service, parent=None):
        super().__init__(parent)
        self._auth_service = auth_service
        self._calendar_service = calendar_service
        self._tasks_service = tasks_service

    def _get_auth_service(self):
        return self._auth_service

    def _get_calendar_service(self):
        return self._calendar_service

    def _get_tasks_service(self):
        return self._tasks_service

    authService = Property(QObject, _get_auth_service, constant=True)
    calendarService = Property(QObject, _get_calendar_service, constant=True)
    tasksService = Property(QObject, _get_tasks_service, constant=True)


def register_google_services_provider():
    """Register GoogleServicesProvider as QML singleton. Call before engine.load()."""
    qmlRegisterSingletonType(
        GoogleServicesProvider,
        "JiraQuickTask",
        1,
        0,
        "GoogleServicesProvider",
        _create_google_services_provider,
    )
