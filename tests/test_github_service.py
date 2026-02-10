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

from src.github_service import (
    _normalize_item,
    _fetch_search_issues,
    GitHubService,
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
    """GitHubService.isAvailable() is False when config has no token/username."""
    with patch("src.github_service.ConfigManager") as MockConfig:
        mock_cfg = MagicMock()
        mock_cfg.get_github_token.return_value = ""
        mock_cfg.get_github_username.return_value = "user"
        MockConfig.return_value = mock_cfg
        svc = GitHubService()
    assert svc.isAvailable() is False

    with patch("src.github_service.ConfigManager") as MockConfig:
        mock_cfg = MagicMock()
        mock_cfg.get_github_token.return_value = "token"
        mock_cfg.get_github_username.return_value = ""
        MockConfig.return_value = mock_cfg
        svc = GitHubService()
    assert svc.isAvailable() is False


def test_github_service_is_available_true():
    """GitHubService.isAvailable() is True when token and username set."""
    with patch("src.github_service.ConfigManager") as MockConfig:
        mock_cfg = MagicMock()
        mock_cfg.get_github_token.return_value = "secret"
        mock_cfg.get_github_username.return_value = "me"
        MockConfig.return_value = mock_cfg
        svc = GitHubService()
    assert svc.isAvailable() is True


