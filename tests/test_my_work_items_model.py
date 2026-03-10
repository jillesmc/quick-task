"""
Testes para src/models/my_work_items_model.py
"""

from unittest.mock import MagicMock, patch

import pytest

from src.models.my_work_items_model import MyWorkItemsModel, SearchWorker


def _make_raw_issue(
    key: str = "PLATFORM-14891",
    summary: str = "test",
    status: str = "To Do",
    priority_name: str = "Highest",
    priority_id: str = "1",
) -> dict:
    """Cria um dict no formato da API para uma issue."""
    return {
        "key": key,
        "fields": {
            "summary": summary,
            "status": {"name": status},
            "issuetype": {"name": "Task"},
            "assignee": {"displayName": "User"},
            "parent": None,
            "priority": (
                {
                    "id": priority_id,
                    "name": priority_name,
                }
                if priority_name
                else None
            ),
        },
    }


@patch("src.models.my_work_items_model.ConfigManager")
@patch("src.models.my_work_items_model.AtlassianClient")
def test_search_worker_extracts_priority(MockAtlassianClient, MockConfigManager):
    """SearchWorker extrai priority e priorityId corretamente do payload da API."""
    raw = [
        _make_raw_issue(key="PLATFORM-14891", priority_name="Highest", priority_id="1"),
        _make_raw_issue(key="PLATFORM-430", priority_name="Medium", priority_id="3"),
    ]
    mock_client = MagicMock()
    mock_client.get_my_issues.return_value = raw
    MockAtlassianClient.return_value = mock_client
    MockConfigManager.return_value = MagicMock()

    worker = SearchWorker(
        jira_client=mock_client,
        config=MagicMock(),
        assignee_email="test@example.com",
        query="",
    )

    received = []

    def capture(issues):
        received.append(issues)

    worker.issuesFound.connect(capture)
    worker.run()

    assert len(received) == 1
    issues = received[0]
    assert len(issues) == 2

    i1 = next(x for x in issues if x["key"] == "PLATFORM-14891")
    assert i1["priority"] == "Highest"
    assert i1["priorityId"] == "1"

    i2 = next(x for x in issues if x["key"] == "PLATFORM-430")
    assert i2["priority"] == "Medium"
    assert i2["priorityId"] == "3"


@patch("src.models.my_work_items_model.ConfigManager")
@patch("src.models.my_work_items_model.AtlassianClient")
def test_update_issue_in_list_with_priority(MockAtlassianClient, MockConfigManager):
    """updateIssueInList atualiza priority e priorityId quando fornecidos."""
    MockConfigManager.return_value = MagicMock()
    MockAtlassianClient.return_value = MagicMock()

    model = MyWorkItemsModel()
    model._issues = [
        {
            "key": "PLATFORM-14891",
            "summary": "test",
            "status": "To Do",
            "priority": "",
            "priorityId": "",
        },
    ]
    model._jira_client = MagicMock()

    model.updateIssueInList(
        "PLATFORM-14891",
        "test updated",
        "IN PROGRESS",
        "Highest",
        "1",
    )

    issue = model.getIssue("PLATFORM-14891")
    assert issue["summary"] == "test updated"
    assert issue["status"] == "IN PROGRESS"
    assert issue["priority"] == "Highest"
    assert issue["priorityId"] == "1"
