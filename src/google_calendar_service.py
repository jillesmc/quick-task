"""
Google Calendar service: load events for a date, expose to QML.
Uses QThread for async work and signals for communication.
"""

from datetime import datetime
from typing import Any, Dict, List

from PySide6.QtCore import QObject, Signal, Slot, QThread  # type: ignore[import]

from src.utils.debug import debug_log


class GoogleCalendarLoadWorker(QThread):
    """Worker thread to fetch events for a single day."""

    eventsReady = Signal(list)
    errorOccurred = Signal(str)
    authRequired = Signal()

    def __init__(self, auth_manager, date_str: str, parent=None):
        super().__init__(parent)
        self._auth_manager = auth_manager
        self._date_str = date_str  # YYYY-MM-DD

    def run(self) -> None:
        try:
            creds = self._auth_manager.authenticate()
        except Exception as e:
            if "Configure" in str(e) or "client" in str(e).lower():
                self.authRequired.emit()
            else:
                self.errorOccurred.emit(str(e))
            return

        try:
            from googleapiclient.discovery import build

            service = build("calendar", "v3", credentials=creds)

            # Use primary calendar
            calendar_id = "primary"

            # Parse date and build time range for the day (UTC)
            try:
                dt = datetime.strptime(self._date_str, "%Y-%m-%d")
            except ValueError:
                dt = datetime.utcnow()

            from datetime import timedelta

            start_dt = dt.replace(hour=0, minute=0, second=0, microsecond=0)
            end_dt = start_dt + timedelta(days=1)
            time_min = start_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
            time_max = end_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

            events_result = (
                service.events()
                .list(
                    calendarId=calendar_id,
                    timeMin=time_min,
                    timeMax=time_max,
                    singleEvents=True,
                    orderBy="startTime",
                )
                .execute()
            )

            events_raw = events_result.get("items", [])
            events: List[Dict[str, Any]] = []

            for e in events_raw:
                start = e.get("start", {}) or {}
                end = e.get("end", {}) or {}
                start_dt_str = start.get("dateTime") or start.get("date")
                end_dt_str = end.get("dateTime") or end.get("date")

                if not start_dt_str or not end_dt_str:
                    continue

                # Parse and compute duration in minutes
                try:
                    if "T" in start_dt_str:
                        s = datetime.fromisoformat(
                            start_dt_str.replace("Z", "+00:00")
                        )
                    else:
                        s = datetime.strptime(start_dt_str, "%Y-%m-%d")
                    if "T" in end_dt_str:
                        en = datetime.fromisoformat(
                            end_dt_str.replace("Z", "+00:00")
                        )
                    else:
                        en = datetime.strptime(end_dt_str, "%Y-%m-%d")
                    duration_minutes = int((en - s).total_seconds() / 60)
                except (ValueError, TypeError):
                    duration_minutes = 0

                events.append(
                    {
                        "id": e.get("id", ""),
                        "summary": (e.get("summary") or "(Sem título)").strip(),
                        "description": (e.get("description") or "").strip(),
                        "start": start_dt_str,
                        "end": end_dt_str,
                        "duration_minutes": duration_minutes,
                        "visibility": e.get("visibility", ""),
                    }
                )

            self.eventsReady.emit(events)
        except Exception as e:
            msg = str(e) if str(e) else "Erro ao carregar eventos."
            debug_log("GoogleCalendarLoadWorker", "run", "Erro: %s", msg)
            self.errorOccurred.emit(msg)


class GoogleCalendarService(QObject):
    """
    QObject exposed to QML for Google Calendar.
    loadEventsForDate(date_str) loads events for one day (YYYY-MM-DD).
    """

    eventsReady = Signal(list)
    errorOccurred = Signal(str)
    authRequired = Signal()

    def __init__(self, config_manager, parent=None):
        super().__init__(parent)
        from src.google_auth import GoogleAuthManager

        self._auth_manager = GoogleAuthManager(config_manager)
        self._worker = None

    def _is_authorized(self) -> bool:
        return self._auth_manager.has_valid_token()

    def _on_worker_finished(self) -> None:
        """Clear worker reference when done; avoid dangling reference to deleted C++ object."""
        if self._worker:
            self._worker.deleteLater()
            self._worker = None

    @Slot(str)
    def loadEventsForDate(self, date_str: str) -> None:
        """Load events for the given date (YYYY-MM-DD)."""
        if self._worker:
            try:
                if self._worker.isRunning():
                    return
            except RuntimeError:
                pass  # C++ object already deleted
            self._worker = None
        if not self._is_authorized():
            self.authRequired.emit()
            return
        self._worker = GoogleCalendarLoadWorker(
            self._auth_manager, date_str or "", parent=self
        )
        self._worker.eventsReady.connect(self.eventsReady.emit)
        self._worker.errorOccurred.connect(self.errorOccurred.emit)
        self._worker.authRequired.connect(self.authRequired.emit)
        self._worker.finished.connect(self._on_worker_finished)
        self._worker.start()
