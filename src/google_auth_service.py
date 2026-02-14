"""
Google OAuth service exposed to QML.
Provides authorize() slot and isAuthorized property; runs OAuth flow in worker thread.
"""

from typing import Any

from PySide6.QtCore import QObject, Property, Signal, Slot, QThread  # type: ignore[import]

from src.utils.debug import debug_log


class GoogleAuthWorker(QThread):
    """Worker thread to run blocking OAuth flow."""

    authorized = Signal()
    errorOccurred = Signal(str)

    def __init__(self, auth_manager, parent=None):
        super().__init__(parent)
        self._auth_manager = auth_manager

    def run(self) -> None:
        try:
            self._auth_manager.authenticate()
            self.authorized.emit()
        except Exception as e:
            msg = str(e) if str(e) else "Erro ao autorizar com Google."
            debug_log("GoogleAuthWorker", "run", "Erro: %s", msg)
            self.errorOccurred.emit(msg)


class GoogleAuthService(QObject):
    """
    QObject exposed to QML for Google OAuth.
    authorize() runs OAuth flow in worker; isAuthorized reflects token status.
    """

    authorized = Signal()
    errorOccurred = Signal(str)

    def __init__(self, config_manager, parent=None):
        super().__init__(parent)
        from src.google_auth import GoogleAuthManager

        self._auth_manager = GoogleAuthManager(config_manager)
        self._worker: Any = None

    def _update_authorized(self) -> None:
        """Emit isAuthorizedChanged if we have a property notifier."""
        if hasattr(self, "isAuthorizedChanged"):
            self.isAuthorizedChanged.emit()

    def _on_worker_finished(self) -> None:
        """Clear worker reference when done; avoid dangling reference to deleted C++ object."""
        if self._worker:
            self._worker.deleteLater()
            self._worker = None

    @Slot()
    def authorize(self) -> None:
        """Start OAuth flow in worker thread (opens browser)."""
        if self._worker:
            try:
                if self._worker.isRunning():
                    return
            except RuntimeError:
                pass  # C++ object already deleted
            self._worker = None
        self._worker = GoogleAuthWorker(self._auth_manager, parent=self)
        self._worker.authorized.connect(self._on_authorized)
        self._worker.errorOccurred.connect(self._on_error)
        self._worker.finished.connect(self._on_worker_finished)
        self._worker.start()

    def _on_authorized(self) -> None:
        self._update_authorized()
        self.authorized.emit()

    def _on_error(self, msg: str) -> None:
        self.errorOccurred.emit(msg)

    def is_authorized(self) -> bool:
        """Check if we have valid Google OAuth token."""
        return self._auth_manager.has_valid_token()

    isAuthorizedChanged = Signal()

    @Property(bool, notify=isAuthorizedChanged)
    def isAuthorized(self) -> bool:
        """QML property: True if we have valid Google OAuth token."""
        return self.is_authorized()
