"""
Tests for src/github_service.py (GitHub PRs/Issues list and import to Jira).
"""

import sys
from unittest.mock import MagicMock, patch

import os

is_flatpak = os.path.exists("/.flatpak-info")
if not is_flatpak and "/usr/lib/python3/dist-packages" not in sys.path:
    sys.path.insert(0, "/usr/lib/python3/dist-packages")

import pytest
from PySide6.QtCore import QCoreApplication

from src.github_service import (
    _normalize_item,
    _fetch_search_issues,
    _search_repos_impl,
    GitHubService,
    CreateBranchWorker,
)


def test_normalize_item_pr():
    """_normalize_item returns flat dict with type 'pr'."""
    raw = {
        "title": "Fix bug",
        "body": "Description",
        "html_url": "https://github.com/owner/repo/pull/1",
        "repository_url": "https://api.github.com/repos/owner/repo",
        "number": 1,
        "created_at": "2025-01-20T10:00:00Z",
        "labels": [{"name": "bug"}],
    }
    out = _normalize_item(raw, "pr")
    assert out["type"] == "pr"
    assert out["repo"] == "owner/repo"
    assert out["number"] == 1
    assert out["title"] == "Fix bug"
    assert out["body"] == "Description"
    assert out["url"] == "https://github.com/owner/repo/pull/1"
    assert out["created_at"] == "2025-01-20T10:00:00Z"
    assert out["labels"] == ["bug"]


def test_normalize_item_issue():
    """_normalize_item with type 'issue'."""
    raw = {
        "title": "Feature X",
        "body": "",
        "html_url": "https://github.com/a/b/issues/2",
        "repository_url": "https://api.github.com/repos/a/b",
        "number": 2,
        "created_at": "2025-01-19T12:00:00Z",
        "labels": [],
    }
    out = _normalize_item(raw, "issue")
    assert out["type"] == "issue"
    assert out["repo"] == "a/b"
    assert out["number"] == 2
    assert out["labels"] == []


def test_fetch_search_issues_success():
    """_fetch_search_issues returns items and None error on 200."""
    session = MagicMock()
    session.get.return_value = MagicMock(
        status_code=200,
        json=lambda: {
            "items": [
                {
                    "title": "PR one",
                    "body": "B",
                    "html_url": "https://github.com/o/r/pull/1",
                    "repository_url": "https://api.github.com/repos/o/r",
                    "number": 1,
                    "created_at": "2025-01-01T00:00:00Z",
                    "labels": [],
                }
            ]
        },
        text="",
        headers={},
    )
    items, err = _fetch_search_issues(session, "is:pr is:open", "pr")
    assert err is None
    assert len(items) == 1
    assert items[0]["type"] == "pr"
    assert items[0]["title"] == "PR one"


def test_fetch_search_issues_rate_limit():
    """_fetch_search_issues returns error on 429."""
    session = MagicMock()
    session.get.return_value = MagicMock(
        status_code=429,
        headers={"Retry-After": "60"},
        text='{"message": "rate limited"}',
        json=lambda: {"message": "rate limited"},
    )
    items, err = _fetch_search_issues(session, "is:pr", "pr")
    assert items == []
    assert err is not None
    assert "60" in err or "rate" in err.lower()


def test_fetch_search_issues_403():
    """_fetch_search_issues returns error on 403."""
    session = MagicMock()
    session.get.return_value = MagicMock(
        status_code=403,
        headers={},
        text="Forbidden",
        json=lambda: {"message": "Forbidden"},
    )
    items, err = _fetch_search_issues(session, "is:pr", "pr")
    assert items == []
    assert err is not None


def test_github_service_is_available_false():
    """GitHubService.isAvailable() is False when config has no token/username (usa get_github_token_from_config)."""
    with patch("src.github_service.ConfigManager") as MockConfig:
        mock_cfg = MagicMock()
        mock_cfg.get_github_token_from_config.return_value = ""
        mock_cfg.get_github_username.return_value = "user"
        MockConfig.return_value = mock_cfg
        svc = GitHubService()
    assert svc.isAvailable() is False

    with patch("src.github_service.ConfigManager") as MockConfig:
        mock_cfg = MagicMock()
        mock_cfg.get_github_token_from_config.return_value = "token"
        mock_cfg.get_github_username.return_value = ""
        MockConfig.return_value = mock_cfg
        svc = GitHubService()
    assert svc.isAvailable() is False


def test_github_service_is_available_true():
    """GitHubService.isAvailable() is True when token and username set in config."""
    with patch("src.github_service.ConfigManager") as MockConfig:
        mock_cfg = MagicMock()
        mock_cfg.get_github_token_from_config.return_value = "secret"
        mock_cfg.get_github_username.return_value = "me"
        MockConfig.return_value = mock_cfg
        svc = GitHubService()
    assert svc.isAvailable() is True


def test_search_repos_impl_short_query_returns_empty():
    """_search_repos_impl returns [] when query has < 2 chars."""
    session = MagicMock()
    assert _search_repos_impl(session, "a", "") == []
    assert _search_repos_impl(session, "", "org") == []
    session.get.assert_not_called()


def test_search_repos_impl_with_default_org_uses_search_api():
    """_search_repos_impl with default_org uses Search API when it returns results."""
    session = MagicMock()
    session.get.return_value = MagicMock(
        status_code=200,
        json=lambda: {
            "items": [
                {"full_name": "org/foo", "name": "foo", "default_branch": "main"},
                {
                    "full_name": "org/foobar",
                    "name": "foobar",
                    "default_branch": "master",
                },
            ]
        },
        raise_for_status=MagicMock(),
    )
    result = _search_repos_impl(session, "foo", "org")
    assert len(result) == 2
    assert result[0]["full_name"] == "org/foo"
    assert result[0]["default_branch"] == "main"
    assert result[1]["full_name"] == "org/foobar"
    session.get.assert_called_once()
    call_url = session.get.call_args[0][0]
    assert "search/repositories" in call_url


def test_search_repos_impl_with_default_org_calls_orgs_api():
    """_search_repos_impl with default_org falls back to orgs API when Search returns empty."""
    session = MagicMock()

    def mock_get(url, *args, **kwargs):
        resp = MagicMock(status_code=200, raise_for_status=MagicMock())
        if "search/repositories" in url:
            resp.json.return_value = {"items": []}
        else:
            resp.json.return_value = [
                {"full_name": "org/foo", "name": "foo", "default_branch": "main"},
                {
                    "full_name": "org/foobar",
                    "name": "foobar",
                    "default_branch": "master",
                },
            ]
        return resp

    session.get.side_effect = mock_get
    result = _search_repos_impl(session, "foo", "org")
    assert len(result) == 2
    assert result[0]["full_name"] == "org/foo"
    assert result[0]["default_branch"] == "main"
    assert result[1]["full_name"] == "org/foobar"
    assert session.get.call_count == 3  # Search org, Search user, fallback orgs
    last_call_url = session.get.call_args_list[-1][0][0]
    assert "orgs/org/repos" in last_call_url


def test_search_repos_impl_filters_by_query():
    """_search_repos_impl filters repos where query is in full_name or name."""
    session = MagicMock()

    def mock_get(url, *args, **kwargs):
        resp = MagicMock(status_code=200, raise_for_status=MagicMock())
        if "search/repositories" in url:
            resp.json.return_value = {"items": []}
        else:
            resp.json.return_value = [
                {"full_name": "org/abc", "name": "abc", "default_branch": "main"},
                {"full_name": "org/xyz", "name": "xyz", "default_branch": "main"},
            ]
        return resp

    session.get.side_effect = mock_get
    result = _search_repos_impl(session, "ab", "org")
    assert len(result) == 1
    assert result[0]["full_name"] == "org/abc"


@patch("src.github_service.requests")
def test_create_branch_worker_success(mock_requests):
    """CreateBranchWorker emits branchCreated with URL on successful GET repo, GET ref, POST refs."""
    app = QCoreApplication.instance() or QCoreApplication([])
    mock_session = MagicMock()
    mock_requests.Session.return_value = mock_session

    def get_side_effect(url, **kwargs):
        if "git/ref" in url:
            return MagicMock(
                status_code=200,
                json=lambda: {"object": {"sha": "abc123def"}},
                raise_for_status=MagicMock(),
            )
        return MagicMock(
            status_code=200,
            json=lambda: {"default_branch": "main"},
            raise_for_status=MagicMock(),
        )

    mock_session.get.side_effect = get_side_effect
    mock_session.post.return_value = MagicMock(
        status_code=201, raise_for_status=MagicMock()
    )

    captured = []

    def on_created(owner, repo, branch_name, url):
        captured.append((owner, repo, branch_name, url))

    worker = CreateBranchWorker("token", "owner", "repo", "feat-123", "", None)
    worker.branchCreated.connect(on_created)
    worker.start()
    worker.wait(5000)
    for _ in range(10):
        app.processEvents()

    assert len(captured) == 1
    assert captured[0][0] == "owner"
    assert captured[0][1] == "repo"
    assert captured[0][2] == "feat-123"
    assert captured[0][3] == "https://github.com/owner/repo/tree/feat-123"
    assert mock_session.get.call_count >= 2
    assert mock_session.post.call_count == 1
    post_call = mock_session.post.call_args
    assert "git/refs" in post_call[0][0]
    assert post_call[1]["json"]["ref"] == "refs/heads/feat-123"
    assert post_call[1]["json"]["sha"] == "abc123def"


@patch("src.github_service.requests")
def test_create_branch_worker_422_emits_error(mock_requests):
    """CreateBranchWorker emits errorOccurred when POST returns 422 (branch already exists)."""
    app = QCoreApplication.instance() or QCoreApplication([])
    mock_session = MagicMock()
    mock_requests.Session.return_value = mock_session
    mock_session.get.side_effect = [
        MagicMock(
            status_code=200,
            json=lambda: {"default_branch": "main"},
            raise_for_status=MagicMock(),
        ),
        MagicMock(
            status_code=200,
            json=lambda: {"object": {"sha": "abc"}},
            raise_for_status=MagicMock(),
        ),
    ]
    mock_session.post.return_value = MagicMock(
        status_code=422, raise_for_status=MagicMock()
    )

    errors = []

    def on_error(msg):
        errors.append(msg)

    worker = CreateBranchWorker("token", "o", "r", "branch", "", None)
    worker.errorOccurred.connect(on_error)
    worker.start()
    worker.wait(5000)
    for _ in range(10):
        app.processEvents()

    assert len(errors) == 1
    assert "existe" in errors[0] or "422" in errors[0] or "nome" in errors[0].lower()
