"""
Testes para src/services/worklog_service.py
"""

from datetime import date
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from config.config_manager import ConfigManager
from src.services.worklog_service import (
    WorklogService,
    TimesheetData,
    IssueWorklogSummary,
    WorklogEntry,
)


@pytest.fixture
def mock_jira_client():
    """JiraClient mock com search_issues_with_worklogs_in_period e get_issue_worklogs."""
    client = MagicMock()
    client.search_issues_with_worklogs_in_period.return_value = [
        {
            "key": "TEST-1",
            "fields": {
                "summary": "Test issue 1",
                "status": {"name": "Done"},
                "issuetype": {"name": "Task"},
            },
        }
    ]
    client.get_issue_worklogs.return_value = [
        {
            "id": "wl-1",
            "author": {
                "accountId": "acc-1",
                "displayName": "Test User",
                "emailAddress": "test@example.com",
            },
            "timeSpentSeconds": 3600,
            "started": "2025-01-15T09:00:00.000-0300",
            "comment": "Work done",
        },
    ]
    return client


@pytest.fixture
def temp_config_with_timesheet(tmp_path):
    """Config com seção timesheet."""
    config_path = tmp_path / "config.json"
    config = {
        "project": "TEST",
        "issue_type": "Task",
        "custom_fields": {},
        "tipo_atividade_values": [],
        "status_sequence": [],
        "timesheet": {
            "enabled": True,
            "cache_ttl_minutes": 5,
            "default_period": "last_7_days",
            "max_results": 500,
        },
    }
    import json

    config_path.write_text(json.dumps(config, indent=2))
    return ConfigManager(config_path=config_path)


def test_get_timesheet_data_returns_timesheet_data(
    mock_jira_client, temp_config_with_timesheet
):
    """get_timesheet_data retorna TimesheetData com issues e worklogs."""
    service = WorklogService(
        jira_client=mock_jira_client,
        config=temp_config_with_timesheet,
    )
    result = service.get_timesheet_data(
        user_email="test@example.com",
        start_date=date(2025, 1, 1),
        end_date=date(2025, 1, 31),
        use_cache=False,
    )
    assert isinstance(result, TimesheetData)
    assert result.start_date == date(2025, 1, 1)
    assert result.end_date == date(2025, 1, 31)
    assert len(result.issues) == 1
    issue = result.issues[0]
    assert isinstance(issue, IssueWorklogSummary)
    assert issue.issue_key == "TEST-1"
    assert issue.issue_summary == "Test issue 1"
    assert date(2025, 1, 15) in issue.worklogs_by_date
    worklogs = issue.worklogs_by_date[date(2025, 1, 15)]
    assert len(worklogs) == 1
    assert worklogs[0].time_spent_seconds == 3600
    assert worklogs[0].comment == "Work done"
    mock_jira_client.search_issues_with_worklogs_in_period.assert_called_once()
    mock_jira_client.get_issue_worklogs.assert_called_once_with(
        "TEST-1", start_at=0, max_results=100
    )


def test_get_timesheet_data_uses_cache(mock_jira_client, temp_config_with_timesheet):
    """Com use_cache=True, segunda chamada usa cache (não chama API)."""
    service = WorklogService(
        jira_client=mock_jira_client,
        config=temp_config_with_timesheet,
    )
    service.get_timesheet_data(
        user_email="test@example.com",
        start_date=date(2025, 1, 1),
        end_date=date(2025, 1, 31),
        use_cache=True,
    )
    service.get_timesheet_data(
        user_email="test@example.com",
        start_date=date(2025, 1, 1),
        end_date=date(2025, 1, 31),
        use_cache=True,
    )
    mock_jira_client.search_issues_with_worklogs_in_period.assert_called_once()


def test_invalidate_cache_forces_refresh(mock_jira_client, temp_config_with_timesheet):
    """Após invalidate_cache, próxima chamada busca da API."""
    service = WorklogService(
        jira_client=mock_jira_client,
        config=temp_config_with_timesheet,
    )
    service.get_timesheet_data(
        user_email="test@example.com",
        start_date=date(2025, 1, 1),
        end_date=date(2025, 1, 31),
        use_cache=True,
    )
    service.invalidate_cache()
    service.get_timesheet_data(
        user_email="test@example.com",
        start_date=date(2025, 1, 1),
        end_date=date(2025, 1, 31),
        use_cache=True,
    )
    assert mock_jira_client.search_issues_with_worklogs_in_period.call_count == 2


def test_worklog_entry_time_formatted():
    """WorklogEntry.time_spent_formatted retorna HH:MM."""
    entry = WorklogEntry(
        id="1",
        issue_key="TEST-1",
        time_spent_seconds=3661,
        started=date(2025, 1, 15),
        comment="x",
    )
    assert entry.time_spent_formatted == "01:01"


def test_issue_worklog_summary_total():
    """IssueWorklogSummary.total_seconds e total_formatted."""
    from datetime import datetime

    wl1 = WorklogEntry(
        id="1",
        issue_key="X",
        time_spent_seconds=3600,
        started=datetime(2025, 1, 15, 9, 0),
        comment="a",
    )
    wl2 = WorklogEntry(
        id="2",
        issue_key="X",
        time_spent_seconds=1800,
        started=datetime(2025, 1, 15, 14, 0),
        comment="b",
    )
    summary = IssueWorklogSummary(
        issue_key="X",
        issue_summary="Test",
        issue_status="Done",
        issue_type="Task",
        worklogs_by_date={date(2025, 1, 15): [wl1, wl2]},
    )
    assert summary.total_seconds == 5400
    assert summary.total_formatted == "01:30"
    assert summary.get_time_for_date(date(2025, 1, 15)) == "01:30"
    assert summary.get_time_for_date(date(2025, 1, 16)) == "00:00"
