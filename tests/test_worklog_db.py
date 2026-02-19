"""
Testes unitários para src/database/worklog_db.py
"""

import tempfile
from datetime import datetime
from pathlib import Path

import pytest

from src.database.worklog_db import WorklogDatabase


@pytest.fixture
def temp_db_path():
    """Caminho para banco de dados temporário."""
    fd, path = tempfile.mkstemp(suffix=".db")
    import os

    os.close(fd)
    yield Path(path)
    if Path(path).exists():
        Path(path).unlink()


@pytest.fixture
def worklog_db(temp_db_path):
    """WorklogDatabase com banco temporário."""
    return WorklogDatabase(db_path=temp_db_path)


def test_get_pending_worklogs_for_issue_empty(worklog_db: WorklogDatabase):
    """Retorna lista vazia quando não há sessões ou issue_key vazio."""
    assert worklog_db.get_pending_worklogs_for_issue("PROJ-1") == []
    assert worklog_db.get_pending_worklogs_for_issue("") == []
    assert worklog_db.get_pending_worklogs_for_issue("   ") == []


def test_get_pending_worklogs_for_issue_only_returns_unsynced(
    worklog_db: WorklogDatabase,
):
    """Retorna apenas sessões não sincronizadas da issue dada."""
    base = datetime(2026, 1, 15, 10, 0, 0)
    worklog_db.save_session(
        session_id="s1",
        issue_key="PROJ-1",
        start_time=base,
        end_time=base,
        duration_seconds=3600,
        description="",
    )
    worklog_db.save_session(
        session_id="s2",
        issue_key="PROJ-1",
        start_time=base,
        end_time=base,
        duration_seconds=1800,
        description="",
    )
    worklog_db.save_session(
        session_id="s3",
        issue_key="PROJ-2",
        start_time=base,
        end_time=base,
        duration_seconds=900,
        description="",
    )
    worklog_db.mark_as_synced("s2", "jira-123")
    pending_proj1 = worklog_db.get_pending_worklogs_for_issue("PROJ-1")
    pending_proj2 = worklog_db.get_pending_worklogs_for_issue("PROJ-2")
    assert len(pending_proj1) == 1
    assert pending_proj1[0]["id"] == "s1"
    assert pending_proj1[0]["issue_key"] == "PROJ-1"
    assert pending_proj1[0]["duration_seconds"] == 3600
    assert len(pending_proj2) == 1
    assert pending_proj2[0]["id"] == "s3"
