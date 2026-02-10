"""
GitHub service: list PRs (review required) and Issues (assigned to me), expose to QML.
Uses QThread for async work and signals for communication.
"""

from pathlib import Path
import sys
from typing import Any, Dict, List, Optional, Tuple

from PySide6.QtCore import QObject, Property, Signal, Slot, QThread  # type: ignore[import]

ROOT_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT_DIR))

from config.config_manager import ConfigManager

try:
    import requests
except ImportError:
    requests = None  # type: ignore[assignment]

GITHUB_API_BASE = "https://api.github.com"


def _normalize_item(
    item: Dict[str, Any], kind: str, review_kind: Optional[str] = None
) -> Dict[str, Any]:
    """Build a flat dict for QML from a GitHub search issue/PR item.
    review_kind: for PRs, "user" (requested for me) or "team" (requested for my team).
    """
    repo_url = (item.get("repository_url") or "").strip()
    repo = ""
    if "repos/" in repo_url:
        repo = repo_url.split("repos/", 1)[-1]
    labels = [lb.get("name", "") for lb in (item.get("labels") or []) if lb.get("name")]
    out: Dict[str, Any] = {
        "repo": repo,
        "number": item.get("number", 0),
        "title": (item.get("title") or "").strip(),
        "body": (item.get("body") or "").strip(),
        "url": (item.get("html_url") or "").strip(),
        "created_at": (item.get("created_at") or "").strip(),
        "labels": labels,
        "type": kind,
    }
    if review_kind:
        out["review_kind"] = review_kind
    return out


class GitHubLoadWorker(QThread):
    """Worker thread to fetch PRs (review requested for user, then for teams) and Issues."""

    dataLoaded = Signal(dict)  # { prsRequestedForUser, prsRequestedForTeam, issues }
    errorOccurred = Signal(str)

    def __init__(
        self,
        token: str,
        username: str,
        parent=None,
    ):
        super().__init__(parent)
        self._token = (token or "").strip()
        self._username = (username or "").strip()

    def run(self) -> None:
        if not requests:
            self.errorOccurred.emit("Biblioteca 'requests' não instalada.")
            return
        if not self._token:
            self.errorOccurred.emit("Configure o token do GitHub nas configurações.")
            return
        if not self._username:
            self.errorOccurred.emit("Configure o username do GitHub nas configurações.")
            return

        headers = {
            "Accept": "application/vnd.github.v3+json",
            "Authorization": f"token {self._token}",
        }
        session = requests.Session()
        session.headers.update(headers)

        # 1) PRs where I'm explicitly requested (user-review-requested = direct, not via team)
        pr_user_query = f"is:pr is:open user-review-requested:{self._username}"
        prs_user, err = _fetch_search_issues(session, pr_user_query, "pr", "user")
        if err:
            self.errorOccurred.emit(err)
            return

        user_urls = {it["url"] for it in prs_user}

        # 2) PRs where a team I'm in is requested (team-review-requested:org/slug)
        prs_team: List[Dict[str, Any]] = []
        teams, teams_err = _get_user_teams(session)
        if not teams_err and teams:
            for team in teams:
                org, slug = team.get("org", ""), team.get("slug", "")
                if not org or not slug:
                    continue
                q = f"is:pr is:open team-review-requested:{org}/{slug}"
                batch, batch_err = _fetch_search_issues(session, q, "pr", "team")
                if batch_err:
                    continue
                for it in batch:
                    if it["url"] not in user_urls:
                        prs_team.append(it)
                        user_urls.add(it["url"])

        # 3) Issues assigned to me
        issue_query = f"is:issue is:open assignee:{self._username}"
        issues, err = _fetch_search_issues(session, issue_query, "issue")
        if err:
            self.errorOccurred.emit(err)
            return

        self.dataLoaded.emit({
            "prsRequestedForUser": prs_user,
            "prsRequestedForTeam": prs_team,
            "issues": issues,
        })


def _fetch_search_issues(
    session: "requests.Session",
    q: str,
    kind: str,
    review_kind: Optional[str] = None,
) -> Tuple[List[Dict[str, Any]], Optional[str]]:
    """Call GitHub search/issues with q; return (list of normalized items, error message or None)."""
    url = f"{GITHUB_API_BASE}/search/issues"
    params = {"q": q, "per_page": 100, "sort": "created", "order": "desc"}
    try:
        resp = session.get(url, params=params, timeout=30)
        if resp.status_code == 403 or resp.status_code == 429:
            retry = resp.headers.get("Retry-After", "")
            msg = resp.json().get("message", resp.text) if resp.text else "Rate limit ou acesso negado."
            if retry:
                return [], f"GitHub rate limit. Tente novamente em {retry}s. {msg}"
            return [], f"GitHub API: {msg}"
        resp.raise_for_status()
        data = resp.json()
        items = data.get("items") or []
        return [_normalize_item(i, kind, review_kind) for i in items], None
    except requests.RequestException as e:
        return [], f"Erro ao chamar GitHub API: {e}"
    except Exception as e:
        return [], str(e)


def _get_user_teams(session: "requests.Session") -> Tuple[List[Dict[str, Any]], Optional[str]]:
    """GET /user/teams; return (list of {org, slug}, error or None). Requires read:org scope."""
    url = f"{GITHUB_API_BASE}/user/teams"
    try:
        resp = session.get(url, params={"per_page": 100}, timeout=15)
        if resp.status_code == 403 or resp.status_code == 404:
            return [], None  # no org permission or endpoint not available
        if resp.status_code == 429:
            return [], "GitHub rate limit."
        resp.raise_for_status()
        teams = resp.json() or []
        out = []
        for t in teams:
            org = (t.get("organization") or {}).get("login", "")
            slug = t.get("slug", "")
            if org and slug:
                out.append({"org": org, "slug": slug})
        return out, None
    except requests.RequestException:
        return [], None
    except Exception:
        return [], None


class GitHubService(QObject):
    """Service for listing GitHub PRs/Issues and exposing to QML."""

    itemsLoaded = Signal(list)  # deprecated: combined list for backward compat
    dataReady = Signal("QVariantMap")  # { prsRequestedForUser, prsRequestedForTeam, issues } — use from QML as onDataReady
    errorOccurred = Signal(str)
    availableChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        try:
            self._config = ConfigManager()
        except Exception as e:
            print(f"GitHubService: Erro ao carregar config: {e}", file=sys.stderr)
            self._config = None
        self._worker: Optional[GitHubLoadWorker] = None

    def _get_token(self) -> str:
        if not self._config:
            return ""
        return self._config.get_github_token()

    def _get_username(self) -> str:
        if not self._config:
            return ""
        return self._config.get_github_username()

    @Slot()
    def loadItems(self) -> None:
        """Load PRs (review requested) and Issues (assigned to me) in a background thread."""
        if self._worker and self._worker.isRunning():
            return
        token = self._get_token()
        username = self._get_username()
        self._worker = GitHubLoadWorker(token, username, parent=self)
        self._worker.dataLoaded.connect(self._on_data_loaded)
        self._worker.errorOccurred.connect(self.errorOccurred.emit)
        self._worker.finished.connect(self._on_worker_finished)
        self._worker.start()

    def _on_data_loaded(self, data: dict) -> None:
        self.dataReady.emit(data)
        # backward compat: combined list
        prs = (data.get("prsRequestedForUser") or []) + (data.get("prsRequestedForTeam") or [])
        self.itemsLoaded.emit(prs + (data.get("issues") or []))

    def _on_worker_finished(self) -> None:
        self._worker = None

    def isAvailable(self) -> bool:
        """True if token and username are configured (env or config)."""
        return bool(self._get_token() and self._get_username())

    @Property(bool, notify=availableChanged)
    def available(self) -> bool:
        """Exposed to QML as property (use githubService.available, not isAvailable())."""
        return self.isAvailable()
