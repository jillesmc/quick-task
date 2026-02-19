"""
GitCommandHelper - Gera comandos gh CLI para branches e PRs do GitHub.
Usado no popover de Development para copiar comandos clone/checkout.
"""

from dataclasses import dataclass
from typing import Optional
from urllib.parse import urlparse

from PySide6.QtCore import QObject, Slot  # type: ignore[import]

from src.utils.debug import debug_log  # type: ignore[import]


@dataclass
class RepoInfo:
    """Informações extraídas de URL GitHub (branch ou PR)."""

    owner: str
    repo: str
    owner_repo: str  # "owner/repo"


def _parse_github_repo_from_url(url: str) -> Optional[RepoInfo]:
    """
    Extrai owner/repo de URL GitHub.
    Aceita: .../tree/branch, .../pull/123, etc.
    """
    url = (url or "").strip()
    if not url:
        return None
    try:
        parsed = urlparse(url)
        if parsed.netloc not in ("github.com", "www.github.com"):
            return None
        path_parts = parsed.path.strip("/").split("/")
        if len(path_parts) < 2:
            return None
        owner = path_parts[0]
        repo = path_parts[1]
        if repo.endswith(".git"):
            repo = repo[:-4]
        return RepoInfo(owner=owner, repo=repo, owner_repo=f"{owner}/{repo}")
    except Exception as e:
        debug_log("GitCommandHelper", "_parse_github_repo_from_url", "Erro: %s", str(e))
        return None


def _parse_pr_number(pr_url: str, pr_number: str) -> Optional[str]:
    """Extrai número do PR de URL ou do campo number."""
    if pr_number and str(pr_number).strip():
        return str(pr_number).strip()
    url = (pr_url or "").strip()
    if not url:
        return None
    try:
        parsed = urlparse(url)
        if parsed.netloc not in ("github.com", "www.github.com"):
            return None
        path_parts = parsed.path.strip("/").split("/")
        if len(path_parts) >= 4 and path_parts[2] == "pull":
            return path_parts[3]
    except Exception:
        pass
    return None


class GitCommandHelper(QObject):
    """Helper exposto ao QML para gerar comandos gh CLI de branches e PRs GitHub."""

    @Slot(str, str, result=str)
    def getGhBranchCloneCommand(self, branch_url: str, branch_name: str) -> str:
        """
        Gera comando gh repo clone para branch.
        Retorna string vazia se URL não for GitHub.
        """
        info = _parse_github_repo_from_url(branch_url or "")
        name = (branch_name or "").strip()
        if info is None or not name:
            return ""
        return f"gh repo clone {info.owner_repo} -- --branch {name}"

    @Slot(str, result=str)
    def getGhBranchCheckoutCommand(self, branch_name: str) -> str:
        """Gera comando git checkout BRANCH (repo já clonado)."""
        name = (branch_name or "").strip()
        if not name:
            return ""
        return f"git checkout {name}"

    @Slot(str, str, result=str)
    def getGhPrCloneCommand(self, pr_url: str, pr_number: str) -> str:
        """
        Gera comando gh repo clone + gh pr checkout para PR.
        Retorna string vazia se URL não for GitHub.
        """
        info = _parse_github_repo_from_url(pr_url or "")
        number = _parse_pr_number(pr_url or "", pr_number or "")
        if info is None or not number:
            return ""
        return f"gh repo clone {info.owner_repo} && cd {info.repo} && gh pr checkout {number}"

    @Slot(str, str, result=str)
    def getGhPrCheckoutCommand(self, pr_url: str, pr_number: str) -> str:
        """
        Gera comando gh pr checkout (repo já clonado).
        """
        number = _parse_pr_number(pr_url or "", pr_number or "")
        if not number:
            return ""
        return f"gh pr checkout {number}"

    @Slot(str, str, result=bool)
    def isBranchUrlValid(self, branch_url: str, branch_name: str) -> bool:
        """Retorna True se a branch tem URL GitHub válido."""
        info = _parse_github_repo_from_url(branch_url or "")
        name = (branch_name or "").strip()
        return info is not None and bool(name)

    @Slot(str, str, result=bool)
    def isPrUrlValid(self, pr_url: str, pr_number: str) -> bool:
        """Retorna True se o PR tem URL/número válido."""
        info = _parse_github_repo_from_url(pr_url or "")
        number = _parse_pr_number(pr_url or "", pr_number or "")
        return info is not None and bool(number)
