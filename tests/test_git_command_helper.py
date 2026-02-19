"""
Testes para src.utils.git_command_helper (comandos gh CLI para branches e PRs).
"""

import pytest

from src.utils.git_command_helper import GitCommandHelper


def test_get_gh_branch_clone_command():
    """getGhBranchCloneCommand retorna gh repo clone com --branch."""
    helper = GitCommandHelper()
    cmd = helper.getGhBranchCloneCommand(
        "https://github.com/empresa/projeto/tree/feature/QTASK-123",
        "feature/QTASK-123",
    )
    assert cmd == "gh repo clone empresa/projeto -- --branch feature/QTASK-123"


def test_get_gh_branch_clone_command_invalid_returns_empty():
    """getGhBranchCloneCommand retorna vazio para URL não-GitHub."""
    helper = GitCommandHelper()
    assert helper.getGhBranchCloneCommand("https://gitlab.com/o/r/-/tree/x", "x") == ""
    assert helper.getGhBranchCloneCommand("", "main") == ""


def test_get_gh_branch_checkout_command():
    """getGhBranchCheckoutCommand retorna git checkout BRANCH."""
    helper = GitCommandHelper()
    assert (
        helper.getGhBranchCheckoutCommand("feature/QTASK-123")
        == "git checkout feature/QTASK-123"
    )
    assert helper.getGhBranchCheckoutCommand("main") == "git checkout main"
    assert helper.getGhBranchCheckoutCommand("") == ""


def test_get_gh_pr_clone_command():
    """getGhPrCloneCommand retorna gh repo clone + cd + gh pr checkout."""
    helper = GitCommandHelper()
    cmd = helper.getGhPrCloneCommand(
        "https://github.com/empresa/projeto/pull/42",
        "42",
    )
    assert cmd == "gh repo clone empresa/projeto && cd projeto && gh pr checkout 42"


def test_get_gh_pr_clone_command_from_url_only():
    """getGhPrCloneCommand extrai número do PR da URL quando number vazio."""
    helper = GitCommandHelper()
    cmd = helper.getGhPrCloneCommand(
        "https://github.com/owner/repo/pull/123",
        "",
    )
    assert cmd == "gh repo clone owner/repo && cd repo && gh pr checkout 123"


def test_get_gh_pr_clone_command_invalid_returns_empty():
    """getGhPrCloneCommand retorna vazio para URL não-GitHub."""
    helper = GitCommandHelper()
    assert (
        helper.getGhPrCloneCommand("https://gitlab.com/o/r/-/merge_requests/1", "1")
        == ""
    )


def test_get_gh_pr_checkout_command():
    """getGhPrCheckoutCommand retorna gh pr checkout NUMBER."""
    helper = GitCommandHelper()
    assert (
        helper.getGhPrCheckoutCommand("https://github.com/o/r/pull/99", "99")
        == "gh pr checkout 99"
    )
    assert helper.getGhPrCheckoutCommand("", "42") == "gh pr checkout 42"
    assert helper.getGhPrCheckoutCommand("", "") == ""


def test_is_branch_url_valid():
    """isBranchUrlValid retorna True para URL GitHub válido."""
    helper = GitCommandHelper()
    assert helper.isBranchUrlValid("https://github.com/o/r/tree/main", "main") is True
    assert helper.isBranchUrlValid("https://gitlab.com/o/r", "main") is False
    assert helper.isBranchUrlValid("https://github.com/o/r/tree/x", "") is False


def test_is_pr_url_valid():
    """isPrUrlValid retorna True para PR com URL/número válido."""
    helper = GitCommandHelper()
    assert helper.isPrUrlValid("https://github.com/o/r/pull/1", "1") is True
    assert helper.isPrUrlValid("https://github.com/o/r/pull/1", "") is True
    assert helper.isPrUrlValid("https://gitlab.com/o/r", "1") is False
    assert helper.isPrUrlValid("", "") is False
