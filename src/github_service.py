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
    from src.utils.debug import debug_log
except ImportError:

    def debug_log(_mod: str, _fn: str, _msg: str, *args: Any) -> None:
        pass


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


class GitHubLoadPRsWorker(QThread):
    """Worker to fetch PRs (review requested for user, then for teams)."""

    prsReady = Signal(list, list)  # prsUser, prsTeam
    errorOccurred = Signal(str)

    def __init__(self, token: str, username: str, parent=None):
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
        pr_user_query = f"is:pr is:open user-review-requested:{self._username}"
        prs_user, err = _fetch_search_issues(session, pr_user_query, "pr", "user")
        if err:
            self.errorOccurred.emit(err)
            return
        user_urls = {it["url"] for it in prs_user}
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
        self.prsReady.emit(prs_user, prs_team)


class GitHubLoadIssuesWorker(QThread):
    """Worker to fetch Issues assigned to me."""

    issuesReady = Signal(list)
    errorOccurred = Signal(str)

    def __init__(self, token: str, username: str, parent=None):
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
        issue_query = f"is:issue is:open assignee:{self._username}"
        issues, err = _fetch_search_issues(session, issue_query, "issue")
        if err:
            self.errorOccurred.emit(err)
            return
        self.issuesReady.emit(issues)


class GitHubLoadWorker(QThread):
    """Legacy worker: fetches PRs + Issues in one thread. Used by loadItems()."""

    dataLoaded = Signal(dict)  # { prsRequestedForUser, prsRequestedForTeam, issues }
    errorOccurred = Signal(str)

    def __init__(self, token: str, username: str, parent=None):
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
        pr_user_query = f"is:pr is:open user-review-requested:{self._username}"
        prs_user, err = _fetch_search_issues(session, pr_user_query, "pr", "user")
        if err:
            self.errorOccurred.emit(err)
            return
        user_urls = {it["url"] for it in prs_user}
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
        issue_query = f"is:issue is:open assignee:{self._username}"
        issues, err = _fetch_search_issues(session, issue_query, "issue")
        if err:
            self.errorOccurred.emit(err)
            return
        self.dataLoaded.emit(
            {
                "prsRequestedForUser": prs_user,
                "prsRequestedForTeam": prs_team,
                "issues": issues,
            }
        )


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
            msg = (
                resp.json().get("message", resp.text)
                if resp.text
                else "Rate limit ou acesso negado."
            )
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


def _search_repos_impl(
    session: "requests.Session",
    query: str,
    default_org: str,
) -> List[Dict[str, Any]]:
    """Fetch repos restricted by default_org (org or user) and filter by query. Returns list of {full_name, default_branch}."""
    try:
        from src.utils.debug import debug_log as _log
    except ImportError:

        def _log(_m: str, _f: str, _msg: str, *args: Any) -> None:
            pass

    q = (query or "").strip().lower()
    if len(q) < 2:
        return []

    # When we have default_org, use Search API so we get repos matching the query by name (not limited to first 100).
    if default_org:
        default_org = default_org.strip()
        # Try org: first, then user: (default_org can be an org or a username)
        for qualifier in ("org", "user"):
            search_q = f"{q} {qualifier}:{default_org} in:name"
            try:
                resp = session.get(
                    f"{GITHUB_API_BASE}/search/repositories",
                    params={"q": search_q, "per_page": 30, "sort": "updated"},
                    timeout=15,
                )
                if resp.status_code == 200:
                    data = resp.json() or {}
                    items = data.get("items") if isinstance(data, dict) else []
                    if isinstance(items, list) and items:
                        out = []
                        for r in items:
                            full_name = (r.get("full_name") or "").strip()
                            if not full_name:
                                continue
                            out.append(
                                {
                                    "full_name": full_name,
                                    "default_branch": (
                                        r.get("default_branch") or "main"
                                    ).strip(),
                                }
                            )
                        _log(
                            "_search_repos_impl",
                            "run",
                            "GET search/repositories q='%s' resultados=%s",
                            search_q[:50],
                            len(out),
                        )
                        return out
            except requests.RequestException as ex:
                _log(
                    "_search_repos_impl",
                    "run",
                    "Search API RequestException: %s",
                    str(ex),
                )
            # If org returned 0 or error, try user (and vice versa)

        # Fallback: list org repos and filter client-side (limited to first 100)
        repos: List[Dict[str, Any]] = []
        for url, params in [
            (
                f"{GITHUB_API_BASE}/orgs/{default_org}/repos",
                {"type": "all", "per_page": 100},
            ),
            (
                f"{GITHUB_API_BASE}/users/{default_org}/repos",
                {"sort": "updated", "per_page": 100},
            ),
        ]:
            try:
                resp = session.get(url, params=params, timeout=15)
                if resp.status_code == 404:
                    _log("_search_repos_impl", "run", "URL 404: %s", url[:60])
                    continue
                resp.raise_for_status()
                repos = resp.json() or []
                _log(
                    "_search_repos_impl",
                    "run",
                    "GET %s repos_raw=%s (fallback)",
                    url[:50],
                    len(repos),
                )
                break
            except requests.RequestException as ex:
                _log("_search_repos_impl", "run", "RequestException: %s", str(ex))
                return []
        out = []
        for r in repos:
            full_name = (r.get("full_name") or "").strip()
            name = (r.get("name") or "").strip()
            if not full_name:
                continue
            if q not in full_name.lower() and q not in name.lower():
                continue
            out.append(
                {
                    "full_name": full_name,
                    "default_branch": (r.get("default_branch") or "main").strip(),
                }
            )
        _log(
            "_search_repos_impl",
            "run",
            "após filtro query='%s' resultados=%s",
            q[:30],
            len(out),
        )
        return out

    # No default_org: list user repos and filter
    try:
        resp = session.get(
            f"{GITHUB_API_BASE}/user/repos",
            params={"sort": "updated", "per_page": 100},
            timeout=15,
        )
        resp.raise_for_status()
        repos = resp.json() or []
        _log("_search_repos_impl", "run", "GET /user/repos repos_raw=%s", len(repos))
    except requests.RequestException as ex:
        _log("_search_repos_impl", "run", "RequestException: %s", str(ex))
        return []
    out = []
    for r in repos:
        full_name = (r.get("full_name") or "").strip()
        name = (r.get("name") or "").strip()
        if not full_name:
            continue
        if q not in full_name.lower() and q not in name.lower():
            continue
        out.append(
            {
                "full_name": full_name,
                "default_branch": (r.get("default_branch") or "main").strip(),
            }
        )
    _log(
        "_search_repos_impl",
        "run",
        "após filtro query='%s' resultados=%s",
        q[:30],
        len(out),
    )
    return out


def _get_user_teams(
    session: "requests.Session",
) -> Tuple[List[Dict[str, Any]], Optional[str]]:
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


class SearchReposWorker(QThread):
    """Worker to search repositories (optionally scoped by default_org)."""

    reposSearchResults = Signal(
        str, list
    )  # (query_used, list of { full_name, default_branch })
    errorOccurred = Signal(str)

    def __init__(
        self,
        token: str,
        default_org: str,
        query: str,
        parent=None,
    ):
        super().__init__(parent)
        self._token = (token or "").strip()
        self._default_org = (default_org or "").strip()
        self._query = (query or "").strip()

    def run(self) -> None:
        if not requests:
            self.errorOccurred.emit("Biblioteca 'requests' não instalada.")
            return
        if len(self._query) < 2:
            debug_log("SearchReposWorker", "run", "query com < 2 chars, emitindo []")
            self.reposSearchResults.emit(self._query, [])
            return
        if not self._token:
            debug_log("SearchReposWorker", "run", "sem token, emitindo []")
            self.reposSearchResults.emit(self._query, [])
            return
        headers = {
            "Accept": "application/vnd.github.v3+json",
            "Authorization": f"token {self._token}",
        }
        session = requests.Session()
        session.headers.update(headers)
        try:
            results = _search_repos_impl(session, self._query, self._default_org)
            debug_log(
                "SearchReposWorker",
                "run",
                "query='%s' default_org='%s' resultados=%s",
                self._query[:50],
                self._default_org or "(vazio)",
                len(results),
            )
            if results:
                names = [
                    r.get("full_name", "") for r in results[:5] if isinstance(r, dict)
                ]
                debug_log(
                    "SearchReposWorker",
                    "run",
                    "query='%s' primeiros full_name: %s",
                    self._query[:30],
                    names,
                )
            self.reposSearchResults.emit(self._query, results)
        except Exception as e:
            debug_log("SearchReposWorker", "run", "exceção: %s", str(e))
            self.errorOccurred.emit(str(e))


class CreateBranchWorker(QThread):
    """Worker to create a branch via GitHub API (GET repo -> default, GET ref -> sha, POST refs)."""

    branchCreated = Signal(str, str, str, str)  # owner, repo, branchName, url
    errorOccurred = Signal(str)

    def __init__(
        self,
        token: str,
        owner: str,
        repo: str,
        branch_name: str,
        base_branch: str,
        parent=None,
    ):
        super().__init__(parent)
        self._token = (token or "").strip()
        self._owner = (owner or "").strip()
        self._repo = (repo or "").strip()
        self._branch_name = (branch_name or "").strip()
        self._base_branch = (base_branch or "").strip()

    def run(self) -> None:
        if not requests:
            self.errorOccurred.emit("Biblioteca 'requests' não instalada.")
            return
        if not self._token:
            self.errorOccurred.emit("Configure o token do GitHub nas configurações.")
            return
        if not self._owner or not self._repo:
            self.errorOccurred.emit("Repositório inválido (use owner/repo).")
            return
        if not self._branch_name:
            self.errorOccurred.emit("Nome da branch é obrigatório.")
            return
        headers = {
            "Accept": "application/vnd.github.v3+json",
            "Authorization": f"token {self._token}",
        }
        session = requests.Session()
        session.headers.update(headers)
        base_url = f"{GITHUB_API_BASE}/repos/{self._owner}/{self._repo}"
        try:
            # 1) Get default branch if base not set
            base = self._base_branch
            if not base:
                resp = session.get(base_url, timeout=15)
                if resp.status_code == 403:
                    self.errorOccurred.emit(
                        "Sem permissão para criar branch neste repositório."
                    )
                    return
                resp.raise_for_status()
                data = resp.json()
                base = (data.get("default_branch") or "main").strip()
            # 2) Get SHA of base ref
            ref_url = f"{base_url}/git/ref/heads/{base}"
            resp = session.get(ref_url, timeout=15)
            if resp.status_code == 404:
                self.errorOccurred.emit(f"Branch base '{base}' não encontrada.")
                return
            resp.raise_for_status()
            ref_data = resp.json()
            sha = (ref_data.get("object") or {}).get("sha")
            if not sha:
                self.errorOccurred.emit("Não foi possível obter o SHA da branch base.")
                return
            # 3) Create ref
            post_url = f"{base_url}/git/refs"
            body = {"ref": f"refs/heads/{self._branch_name}", "sha": sha}
            resp = session.post(post_url, json=body, timeout=15)
            if resp.status_code == 422:
                self.errorOccurred.emit("Já existe uma branch com este nome.")
                return
            if resp.status_code == 403:
                self.errorOccurred.emit(
                    "Sem permissão para criar branch neste repositório."
                )
                return
            resp.raise_for_status()
            url = f"https://github.com/{self._owner}/{self._repo}/tree/{self._branch_name}"
            self.branchCreated.emit(self._owner, self._repo, self._branch_name, url)
        except requests.RequestException as e:
            if hasattr(e, "response") and e.response is not None:
                try:
                    msg = e.response.json().get("message", e.response.text)
                except Exception:
                    msg = e.response.text or str(e)
                self.errorOccurred.emit(f"GitHub API: {msg}")
            else:
                self.errorOccurred.emit(f"Erro de rede. Tente novamente. {e}")
        except Exception as e:
            self.errorOccurred.emit(str(e))


class GitHubService(QObject):
    """Service for listing GitHub PRs/Issues and exposing to QML."""

    itemsLoaded = Signal(list)  # deprecated: combined list for backward compat
    dataReady = Signal(
        "QVariantMap"
    )  # { prsRequestedForUser, prsRequestedForTeam, issues } — use from QML as onDataReady
    errorOccurred = Signal(str)
    prsReady = Signal(list, list)  # prsUser, prsTeam
    prsErrorOccurred = Signal(str)
    issuesReady = Signal(list)
    issuesErrorOccurred = Signal(str)
    availableChanged = Signal()
    reposSearchResults = Signal(
        str, list
    )  # (query_used, list of { full_name, default_branch })
    branchCreated = Signal(str, str, str, str)  # owner, repo, branchName, url

    def __init__(self, parent=None, config_manager=None):
        super().__init__(parent)
        injected = config_manager is not None
        try:
            self._config = config_manager if injected else ConfigManager()
        except Exception as e:
            print(f"GitHubService: Erro ao carregar config: {e}", file=sys.stderr)
            self._config = None
        debug_log(
            "GitHubService",
            "__init__",
            "config_injected=%s (True=mesmo config que Settings)",
            injected,
        )
        self._worker: Optional[GitHubLoadWorker] = None
        self._prs_worker: Optional[GitHubLoadPRsWorker] = None
        self._issues_worker: Optional[GitHubLoadIssuesWorker] = None
        self._search_repos_worker: Optional[SearchReposWorker] = None
        self._create_branch_worker: Optional[CreateBranchWorker] = None

    def _reload_config(self) -> None:
        """Recarrega o config do arquivo para refletir alterações feitas em Configurações."""
        if not self._config:
            return
        try:
            self._config.load_config()
        except Exception:
            pass

    def _get_token(self) -> str:
        """Token para chamadas à API: apenas config.json (github.token)."""
        if not self._config:
            return ""
        self._reload_config()
        return self._config.get_github_token()

    def _get_username(self) -> str:
        if not self._config:
            return ""
        self._reload_config()
        return self._config.get_github_username()

    def _get_token_from_config(self) -> str:
        """Token apenas do config.json (mesma fonte da tela Configurações). Usado para 'available'."""
        if not self._config:
            return ""
        self._reload_config()
        return self._config.get_github_token_from_config()

    def _get_username_from_config(self) -> str:
        if not self._config:
            return ""
        self._reload_config()
        return self._config.get_github_username()

    @Slot()
    def loadItems(self) -> None:
        """Load PRs and Issues in parallel (calls loadPRs + loadIssues)."""
        self.loadPRs()
        self.loadIssues()

    @Slot()
    def loadPRs(self) -> None:
        """Load PRs (review requested for user, then for teams) in background."""
        if self._prs_worker and self._prs_worker.isRunning():
            return
        token = self._get_token()
        username = self._get_username()
        self._prs_worker = GitHubLoadPRsWorker(token, username, parent=self)
        self._prs_worker.prsReady.connect(self.prsReady.emit)
        self._prs_worker.errorOccurred.connect(self.prsErrorOccurred.emit)
        self._prs_worker.finished.connect(self._on_prs_worker_finished)
        self._prs_worker.start()

    def _on_prs_worker_finished(self) -> None:
        self._prs_worker = None

    @Slot()
    def loadIssues(self) -> None:
        """Load Issues (assigned to me) in background."""
        if self._issues_worker and self._issues_worker.isRunning():
            return
        token = self._get_token()
        username = self._get_username()
        self._issues_worker = GitHubLoadIssuesWorker(token, username, parent=self)
        self._issues_worker.issuesReady.connect(self.issuesReady.emit)
        self._issues_worker.errorOccurred.connect(self.issuesErrorOccurred.emit)
        self._issues_worker.finished.connect(self._on_issues_worker_finished)
        self._issues_worker.start()

    def _on_issues_worker_finished(self) -> None:
        self._issues_worker = None

    @Slot()
    def loadItemsLegacy(self) -> None:
        """Legacy: single worker for PRs+Issues. Used when both needed in one dataReady."""
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
        prs = (data.get("prsRequestedForUser") or []) + (
            data.get("prsRequestedForTeam") or []
        )
        self.itemsLoaded.emit(prs + (data.get("issues") or []))

    def _on_worker_finished(self) -> None:
        self._worker = None

    def _get_default_org(self) -> str:
        if not self._config:
            return ""
        self._reload_config()
        return self._config.development_panel_default_org()

    @Slot(str)
    def searchRepositories(self, query: str) -> None:
        """Search repos (min 2 chars); when default_org is set, scope to that org/user. Emits reposSearchResults(query, list)."""
        q = (query or "").strip()
        if self._search_repos_worker and self._search_repos_worker.isRunning():
            debug_log(
                "GitHubService",
                "searchRepositories",
                "ignorado (worker já rodando) query='%s'",
                q[:50],
            )
            return
        token = self._get_token()
        default_org = self._get_default_org()
        debug_log(
            "GitHubService",
            "searchRepositories",
            "iniciando busca query='%s' default_org='%s' token_len=%s",
            q[:50],
            default_org or "(vazio)",
            len(token) if token else 0,
        )
        self._search_repos_worker = SearchReposWorker(
            token, default_org, query or "", parent=self
        )
        self._search_repos_worker.reposSearchResults.connect(
            self.reposSearchResults.emit
        )
        self._search_repos_worker.errorOccurred.connect(self.errorOccurred.emit)
        self._search_repos_worker.finished.connect(self._on_search_repos_finished)
        self._search_repos_worker.start()

    def _on_search_repos_finished(self) -> None:
        self._search_repos_worker = None

    @Slot(str, str, str)
    def createBranch(
        self,
        owner_repo: str,
        branch_name: str,
        base_branch: str = "",
    ) -> None:
        """Create a branch in owner/repo from base_branch (empty = default branch). Emits branchCreated(owner, repo, name, url) or errorOccurred(msg)."""
        if self._create_branch_worker and self._create_branch_worker.isRunning():
            return
        parts = (owner_repo or "").strip().split("/", 1)
        if len(parts) != 2 or not parts[0] or not parts[1]:
            self.errorOccurred.emit("Repositório inválido (use owner/repo).")
            return
        owner, repo = parts[0].strip(), parts[1].strip()
        token = self._get_token()
        self._create_branch_worker = CreateBranchWorker(
            token,
            owner,
            repo,
            (branch_name or "").strip(),
            (base_branch or "").strip(),
            parent=self,
        )
        self._create_branch_worker.branchCreated.connect(self.branchCreated.emit)
        self._create_branch_worker.errorOccurred.connect(self.errorOccurred.emit)
        self._create_branch_worker.finished.connect(self._on_create_branch_finished)
        self._create_branch_worker.start()

    def _on_create_branch_finished(self) -> None:
        self._create_branch_worker = None

    def isAvailable(self) -> bool:
        """True se token e username estão no config (mesma fonte da tela Configurações). Assim a UI e o diálogo ficam em sintonia; chamadas à API ainda usam _get_token() (env pode sobrepor)."""
        has_cfg = self._config is not None
        config_path = getattr(self._config, "config_path", None) if has_cfg else None
        token_from_config = self._get_token_from_config() if has_cfg else ""
        username = self._get_username() if has_cfg else ""
        result = bool(token_from_config and username)
        raw = getattr(self._config, "_config", {}) if has_cfg else {}
        has_github_key = "github" in raw
        debug_log(
            "GitHubService",
            "isAvailable",
            "config_path=%s has_github_key=%s token_len=%s username=%s result=%s",
            str(config_path) if config_path else "None",
            has_github_key,
            len(token_from_config) if token_from_config else 0,
            username or "(vazio)",
            result,
        )
        return result

    @Slot()
    def notifyConfigChanged(self) -> None:
        """Chamado quando as configurações foram salvas (ex.: SettingsModel.saved) para a UI atualizar available."""
        self._reload_config()
        self.availableChanged.emit()

    @Property(bool, notify=availableChanged)
    def available(self) -> bool:
        """Exposed to QML as property (use githubService.available, not isAvailable())."""
        return self.isAvailable()
