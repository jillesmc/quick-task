"""
Google Tasks service: load all todo tasks from all lists, expose to QML.
Uses QThread for async work and signals for communication.
"""

from typing import Any, Dict, List

from PySide6.QtCore import QObject, Signal, Slot, QThread  # type: ignore[import]

from src.utils.debug import debug_log


class GoogleTasksLoadWorker(QThread):
    """Worker thread to fetch all tasks with status needsAction (todo)."""

    tasksReady = Signal(list)
    errorOccurred = Signal(str)
    authRequired = Signal()

    def __init__(self, auth_manager, parent=None):
        super().__init__(parent)
        self._auth_manager = auth_manager

    def _extract_task_dict(
        self, t: Dict[str, Any], list_id: str, list_title: str
    ) -> Dict[str, Any]:
        """Extract task dict with assignmentInfo and links for QML."""
        assignment_info = t.get("assignmentInfo") or {}
        surface_type = assignment_info.get("surfaceType", "")
        link_to_task = (assignment_info.get("linkToTask") or "").strip()
        space_info = assignment_info.get("spaceInfo") or {}
        space_name = (space_info.get("space") or "").strip()

        links_raw = t.get("links") or []
        links = [
            {
                "type": (l.get("type") or "").strip(),
                "link": (l.get("link") or "").strip(),
                "description": (l.get("description") or "").strip(),
            }
            for l in links_raw
        ]

        return {
            "id": t.get("id", ""),
            "title": (t.get("title") or "(Sem título)").strip(),
            "notes": (t.get("notes") or "").strip(),
            "due": t.get("due", ""),
            "status": t.get("status", "needsAction"),
            "updated": t.get("updated", ""),
            "list_id": list_id,
            "list_title": list_title,
            "assignment_source": surface_type,
            "assignment_link": link_to_task,
            "space_name": space_name,
            "links": links,
        }

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
            from google_auth_httplib2 import AuthorizedHttp
            from googleapiclient.discovery import build
            import httplib2

            from src.google_auth import get_ca_bundle_path_for_google_api

            ca_path = get_ca_bundle_path_for_google_api()
            if ca_path:
                http = httplib2.Http(ca_certs=ca_path)
            else:
                http = httplib2.Http()
            authorized_http = AuthorizedHttp(creds, http=http)
            service = build("tasks", "v1", http=authorized_http)

            # Paginate task lists
            all_task_lists: List[Dict[str, Any]] = []
            page_token = None
            while True:
                list_params: Dict[str, Any] = {}
                if page_token:
                    list_params["pageToken"] = page_token
                task_lists_result = service.tasklists().list(**list_params).execute()
                items = task_lists_result.get("items", [])
                all_task_lists.extend(items)
                page_token = task_lists_result.get("nextPageToken")
                if not page_token:
                    break

            all_tasks: List[Dict[str, Any]] = []

            for tl in all_task_lists:
                list_id = tl.get("id", "")
                list_title = (tl.get("title") or "").strip()
                if not list_id:
                    continue
                try:
                    task_page_token = None
                    while True:
                        task_params: Dict[str, Any] = {
                            "tasklist": list_id,
                            "showCompleted": False,
                            "showHidden": False,
                            "showAssigned": True,
                            "maxResults": 100,
                        }
                        if task_page_token:
                            task_params["pageToken"] = task_page_token
                        tasks_result = service.tasks().list(**task_params).execute()
                        for t in tasks_result.get("items", []):
                            if t.get("status") == "completed":
                                continue
                            all_tasks.append(
                                self._extract_task_dict(t, list_id, list_title)
                            )
                        task_page_token = tasks_result.get("nextPageToken")
                        if not task_page_token:
                            break
                except Exception:
                    continue

            self.tasksReady.emit(all_tasks)
        except Exception as e:
            msg = str(e) if str(e) else "Erro ao carregar tarefas."
            debug_log("GoogleTasksLoadWorker", "run", "Erro: %s", msg)
            if "401" in msg or "403" in msg:
                self._auth_manager.remove_token()
                self.authRequired.emit()
            else:
                self.errorOccurred.emit(msg)


class GoogleTasksService(QObject):
    """
    QObject exposed to QML for Google Tasks.
    loadTasks() loads all tasks with status todo from all lists.
    """

    tasksReady = Signal(list)
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

    @Slot()
    def loadTasks(self) -> None:
        """Load all todo tasks from all task lists."""
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
        self._worker = GoogleTasksLoadWorker(self._auth_manager, parent=self)
        self._worker.tasksReady.connect(self.tasksReady.emit)
        self._worker.errorOccurred.connect(self.errorOccurred.emit)
        self._worker.authRequired.connect(self.authRequired.emit)
        self._worker.finished.connect(self._on_worker_finished)
        self._worker.start()
