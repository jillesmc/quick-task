"""
Google Drive comments service: load comments where the user is mentioned, expose to QML.
Uses QThread for async work and signals for communication. Issue #18.
"""

from typing import Any, Dict, List, Optional

from PySide6.QtCore import QObject, Signal, Slot, QThread  # type: ignore[import]

from src.utils.debug import debug_log

# MIME types for Google Workspace editable files that support comments
GOOGLE_APPS_MIME_PREFIX = "application/vnd.google-apps."
GOOGLE_APPS_DOCUMENT = "application/vnd.google-apps.document"
GOOGLE_APPS_SPREADSHEET = "application/vnd.google-apps.spreadsheet"
GOOGLE_APPS_PRESENTATION = "application/vnd.google-apps.presentation"

DEFAULT_MAX_FILES = 100
DEFAULT_MAX_COMMENTS = 50


def _file_type_from_mime(mime_type: str) -> str:
    if not mime_type:
        return "Google Drive File"
    if "document" in mime_type:
        return "Google Docs"
    if "spreadsheet" in mime_type:
        return "Google Sheets"
    if "presentation" in mime_type:
        return "Google Slides"
    if "form" in mime_type:
        return "Google Forms"
    if "drawing" in mime_type:
        return "Google Drawings"
    return "Google Drive File"


def _build_comment_url(file_web_view_link: str, comment_id: str, mime_type: str) -> str:
    if not file_web_view_link:
        return ""
    link = (file_web_view_link or "").strip()
    if "document" in (mime_type or ""):
        return f"{link}#comment_{comment_id}"
    if "spreadsheet" in (mime_type or ""):
        return f"{link}#gid=0&range=A1&comment={comment_id}"
    return link


class GoogleDriveCommentsLoadWorker(QThread):
    """Worker thread to fetch Drive comments where the user is mentioned."""

    commentsReady = Signal(list)
    errorOccurred = Signal(str)
    authRequired = Signal()

    def __init__(
        self,
        auth_manager,
        unresolved_only: bool = True,
        max_results: int = DEFAULT_MAX_COMMENTS,
        max_files: int = DEFAULT_MAX_FILES,
        parent=None,
    ):
        super().__init__(parent)
        self._auth_manager = auth_manager
        self._unresolved_only = unresolved_only
        self._max_results = max_results
        self._max_files = max_files

    def _get_user_email(self, drive_service) -> str:
        try:
            about = drive_service.about().get(fields="user").execute()
            user = about.get("user") or {}
            return (user.get("emailAddress") or "").strip()
        except Exception:
            return ""

    def _is_user_mentioned(self, comment_data: dict, user_email: str) -> bool:
        if not user_email:
            return False
        content = (comment_data.get("content") or "").strip()
        if f"@{user_email}" in content or user_email in content:
            return True
        for reply in comment_data.get("replies") or []:
            reply_content = (reply.get("content") or "").strip()
            if f"@{user_email}" in reply_content or user_email in reply_content:
                return True
        author = comment_data.get("author") or {}
        if (author.get("emailAddress") or "").strip() == user_email:
            return True
        return False

    def _parse_comment(
        self,
        comment_data: dict,
        file_id: str,
        file_name: str,
        file_mime_type: str,
        file_web_view_link: str,
    ) -> Dict[str, Any]:
        author = comment_data.get("author") or {}
        quoted = comment_data.get("quotedFileContent") or {}
        quoted_value = (quoted.get("value") if isinstance(quoted, dict) else None) or ""
        comment_id = comment_data.get("id", "")
        file_url = _build_comment_url(file_web_view_link, comment_id, file_mime_type)
        return {
            "id": comment_id,
            "content": (comment_data.get("content") or "").strip(),
            "author": (author.get("displayName") or "").strip() or "Unknown",
            "author_email": (author.get("emailAddress") or "").strip(),
            "createdTime": comment_data.get("createdTime", ""),
            "modifiedTime": comment_data.get("modifiedTime", ""),
            "resolved": bool(comment_data.get("resolved", False)),
            "file_id": file_id,
            "file_name": file_name,
            "file_type": _file_type_from_mime(file_mime_type),
            "file_url": file_url or file_web_view_link or "",
            "quoted_text": quoted_value.strip() if quoted_value else "",
            "anchor": comment_data.get("anchor", ""),
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
            drive_service = build("drive", "v3", http=authorized_http)

            user_email = self._get_user_email(drive_service)

            # List recently modified Google Workspace files
            files_result = (
                drive_service.files()
                .list(
                    q="mimeType contains 'application/vnd.google-apps' and trashed=false",
                    spaces="drive",
                    fields="files(id, name, mimeType, webViewLink, modifiedTime)",
                    orderBy="modifiedTime desc",
                    pageSize=min(self._max_files, 100),
                )
                .execute()
            )
            files = files_result.get("files", [])
            comments: List[Dict[str, Any]] = []

            for f in files:
                if len(comments) >= self._max_results:
                    break
                file_id = f.get("id", "")
                file_name = (f.get("name") or "").strip()
                file_mime = (f.get("mimeType") or "").strip()
                file_link = (f.get("webViewLink") or "").strip()
                if not file_id:
                    continue
                try:
                    comments_result = (
                        drive_service.comments()
                        .list(
                            fileId=file_id,
                            fields="comments(id,content,author,createdTime,modifiedTime,resolved,quotedFileContent,anchor,replies)",
                            includeDeleted=False,
                        )
                        .execute()
                    )
                except Exception:
                    continue
                for c in comments_result.get("comments") or []:
                    if self._unresolved_only and c.get("resolved", False):
                        continue
                    if not self._is_user_mentioned(c, user_email):
                        continue
                    comments.append(
                        self._parse_comment(c, file_id, file_name, file_mime, file_link)
                    )
                    if len(comments) >= self._max_results:
                        break

            # Sort by modifiedTime descending
            comments.sort(
                key=lambda x: x.get("modifiedTime") or x.get("createdTime") or "",
                reverse=True,
            )
            comments = comments[: self._max_results]
            self.commentsReady.emit(comments)
        except Exception as e:
            msg = str(e) if str(e) else "Erro ao carregar comentários do Drive."
            debug_log("GoogleDriveCommentsLoadWorker", "run", "Erro: %s", msg)
            if "401" in msg or "403" in msg:
                self._auth_manager.remove_token()
                self.authRequired.emit()
            else:
                self.errorOccurred.emit(msg)


class GoogleDriveCommentsResolveWorker(QThread):
    """Worker to resolve a single comment (Drive API update)."""

    resolveFinished = Signal(bool)  # success
    errorOccurred = Signal(str)

    def __init__(
        self,
        auth_manager,
        file_id: str,
        comment_id: str,
        parent=None,
    ):
        super().__init__(parent)
        self._auth_manager = auth_manager
        self._file_id = file_id
        self._comment_id = comment_id

    def run(self) -> None:
        try:
            creds = self._auth_manager.authenticate()
        except Exception as e:
            self.errorOccurred.emit(str(e))
            self.resolveFinished.emit(False)
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
            drive_service = build("drive", "v3", http=authorized_http)
            # Na Drive API v3, "resolved" é read-only no comment. Para resolver é preciso
            # criar uma reply com action "resolve" (ver replies#Reply e replies.create).
            drive_service.replies().create(
                fileId=self._file_id,
                commentId=self._comment_id,
                body={"content": " ", "action": "resolve"},
                fields="id,action",
            ).execute()
            self.resolveFinished.emit(True)
        except Exception as e:
            self.errorOccurred.emit(str(e))
            self.resolveFinished.emit(False)


class GoogleDriveCommentsService(QObject):
    """
    QObject exposed to QML for Google Drive comments (Issue #18).
    loadComments() loads comments where the user is mentioned.
    resolveComment(fileId, commentId) marks a comment as resolved.
    """

    commentsReady = Signal(list)
    errorOccurred = Signal(str)
    authRequired = Signal()
    resolveFinished = Signal(bool)

    def __init__(self, config_manager, parent=None):
        super().__init__(parent)
        from src.google_auth import GoogleAuthManager

        self._config_manager = config_manager
        self._auth_manager = GoogleAuthManager(config_manager)
        self._worker: Optional[GoogleDriveCommentsLoadWorker] = None
        self._resolve_worker: Optional[GoogleDriveCommentsResolveWorker] = None

    def _is_authorized(self) -> bool:
        return self._auth_manager.has_valid_token()

    def _on_worker_finished(self) -> None:
        if self._worker:
            self._worker.deleteLater()
            self._worker = None

    def _on_resolve_worker_finished(self) -> None:
        if self._resolve_worker:
            self._resolve_worker.deleteLater()
            self._resolve_worker = None

    @Slot()
    def loadComments(self) -> None:
        """Load Drive comments where the user is mentioned (uses config: enabled, max_comments, unresolved_only)."""
        if self._worker:
            try:
                if self._worker.isRunning():
                    return
            except RuntimeError:
                pass
            self._worker = None
        cfg = {}
        if self._config_manager and hasattr(
            self._config_manager, "get_google_drive_comments_config"
        ):
            cfg = self._config_manager.get_google_drive_comments_config() or {}
        if not cfg.get("enabled", True):
            self.commentsReady.emit([])
            return
        if not self._is_authorized():
            self.authRequired.emit()
            return
        max_results = max(
            1, min(100, int(cfg.get("max_comments", DEFAULT_MAX_COMMENTS)))
        )
        unresolved_only = cfg.get("unresolved_only", True)
        self._worker = GoogleDriveCommentsLoadWorker(
            self._auth_manager,
            unresolved_only=unresolved_only,
            max_results=max_results,
            max_files=DEFAULT_MAX_FILES,
            parent=self,
        )
        self._worker.commentsReady.connect(self.commentsReady.emit)
        self._worker.errorOccurred.connect(self.errorOccurred.emit)
        self._worker.authRequired.connect(self.authRequired.emit)
        self._worker.finished.connect(self._on_worker_finished)
        self._worker.start()

    @Slot(str, str)
    def resolveComment(self, file_id: str, comment_id: str) -> None:
        """Mark a comment as resolved. Emits resolveFinished(success)."""
        if not file_id or not comment_id:
            self.resolveFinished.emit(False)
            return
        if self._resolve_worker:
            try:
                if self._resolve_worker.isRunning():
                    return
            except RuntimeError:
                pass
            self._resolve_worker = None
        self._resolve_worker = GoogleDriveCommentsResolveWorker(
            self._auth_manager,
            file_id.strip(),
            comment_id.strip(),
            parent=self,
        )
        self._resolve_worker.resolveFinished.connect(self.resolveFinished.emit)
        self._resolve_worker.errorOccurred.connect(self.errorOccurred.emit)
        self._resolve_worker.finished.connect(self._on_resolve_worker_finished)
        self._resolve_worker.start()
