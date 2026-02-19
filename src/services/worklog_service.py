"""
Serviço para buscar worklogs do Jira para a tela de Timesheet.
Cache da última visualização, TTL configurável.
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional

from PySide6.QtCore import QObject, Signal, Slot  # type: ignore[import]

from config.config_manager import ConfigManager
from core.jira_client import JiraClient
from src.utils.debug import debug_log


@dataclass
class WorklogEntry:
    """Um registro individual de worklog"""

    id: str
    issue_key: str
    time_spent_seconds: int
    started: datetime
    comment: Optional[str] = None
    author: str = ""

    @property
    def time_spent_formatted(self) -> str:
        """Formatar tempo como HH:MM"""
        hours = self.time_spent_seconds // 3600
        minutes = (self.time_spent_seconds % 3600) // 60
        return f"{hours:02d}:{minutes:02d}"

    @property
    def date(self) -> date:
        """Data do worklog (sem hora)"""
        return (
            self.started.date() if isinstance(self.started, datetime) else self.started
        )


@dataclass
class IssueWorklogSummary:
    """Consolidação de worklogs de uma issue"""

    issue_key: str
    issue_summary: str
    issue_status: str
    issue_type: str
    worklogs_by_date: Dict[date, List[WorklogEntry]] = field(default_factory=dict)

    @property
    def total_seconds(self) -> int:
        """Total de segundos trabalhados na issue"""
        return sum(
            wl.time_spent_seconds
            for worklogs in self.worklogs_by_date.values()
            for wl in worklogs
        )

    @property
    def total_formatted(self) -> str:
        """Total formatado como HH:MM"""
        hours = self.total_seconds // 3600
        minutes = (self.total_seconds % 3600) // 60
        return f"{hours:02d}:{minutes:02d}"

    def get_time_for_date(self, target_date: date) -> str:
        """Obter tempo trabalhado em uma data específica"""
        if target_date not in self.worklogs_by_date:
            return "00:00"
        total_seconds = sum(
            wl.time_spent_seconds for wl in self.worklogs_by_date[target_date]
        )
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        return f"{hours:02d}:{minutes:02d}"


@dataclass
class TimesheetData:
    """Dados completos do timesheet"""

    start_date: date
    end_date: date
    issues: List[IssueWorklogSummary]

    @property
    def date_range(self) -> List[date]:
        """Lista de datas no período"""
        dates = []
        current = self.start_date
        while current <= self.end_date:
            dates.append(current)
            current = current + timedelta(days=1)
        return dates

    def get_daily_total(self, target_date: date) -> str:
        """Total de horas trabalhadas em um dia específico"""
        total_seconds = 0
        for issue in self.issues:
            if target_date in issue.worklogs_by_date:
                total_seconds += sum(
                    wl.time_spent_seconds for wl in issue.worklogs_by_date[target_date]
                )
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        return f"{hours:02d}:{minutes:02d}"

    @property
    def grand_total(self) -> str:
        """Total geral de horas no período"""
        total_seconds = sum(issue.total_seconds for issue in self.issues)
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        return f"{hours:02d}:{minutes:02d}"


def _parse_started(started_str: str) -> datetime:
    """Parse started string (ISO format) para datetime."""
    if not started_str:
        return datetime.now()
    try:
        # Formato: 2025-01-20T09:30:00.000-0300
        if "T" in started_str:
            dt_str = started_str.split(".")[0].replace("Z", "+00:00")
            if "+" in dt_str or (len(dt_str) > 19 and dt_str[-5] in "+-"):
                return datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
            return datetime.strptime(dt_str[:19], "%Y-%m-%dT%H:%M:%S")
        return datetime.strptime(started_str[:10], "%Y-%m-%d")
    except (ValueError, TypeError):
        return datetime.now()


class WorklogService(QObject):
    """Service para buscar e cachear worklogs do Timesheet"""

    def __init__(
        self,
        jira_client: JiraClient,
        config: ConfigManager,
        parent=None,
    ):
        super().__init__(parent)
        self._jira_client = jira_client
        self._config = config
        self._cached_data: Optional[TimesheetData] = None
        self._cached_timestamp: Optional[datetime] = None
        self._cached_key: Optional[str] = None

    def _get_cache_ttl(self) -> timedelta:
        """TTL do cache em minutos (configurável). Padrão 1 dia."""
        cfg = self._config.get_timesheet_config()
        minutes = int(cfg.get("cache_ttl_minutes", 1440))
        return timedelta(minutes=max(1, min(10080, minutes)))  # 1 min a 7 dias

    def _get_max_results(self) -> int:
        """Máximo de issues por busca."""
        cfg = self._config.get_timesheet_config()
        return max(50, min(1000, int(cfg.get("max_results", 500))))

    def _generate_cache_key(
        self, user_email: str, start_date: date, end_date: date
    ) -> str:
        """Gerar chave única para cache."""
        return f"{user_email}_{start_date.isoformat()}_{end_date.isoformat()}"

    def get_timesheet_data(
        self,
        user_email: str,
        start_date: date,
        end_date: date,
        use_cache: bool = True,
    ) -> TimesheetData:
        """
        Obter dados de timesheet com cache.

        Args:
            user_email: Email do usuário
            start_date: Data de início
            end_date: Data de fim
            use_cache: Se deve usar cache

        Returns:
            TimesheetData consolidado
        """
        cache_key = self._generate_cache_key(user_email, start_date, end_date)

        if use_cache and self._cached_data and self._cached_key == cache_key:
            if self._cached_timestamp and (
                datetime.now() - self._cached_timestamp < self._get_cache_ttl()
            ):
                debug_log(
                    "WorklogService",
                    "get_timesheet_data",
                    "Cache hit para %s - %s",
                    start_date,
                    end_date,
                )
                return self._cached_data
            debug_log(
                "WorklogService",
                "get_timesheet_data",
                "Cache expirado, buscando dados novos...",
            )

        debug_log(
            "WorklogService",
            "get_timesheet_data",
            "Buscando worklogs de %s a %s...",
            start_date,
            end_date,
        )
        timesheet_data = self._fetch_from_api(user_email, start_date, end_date)
        self._cached_data = timesheet_data
        self._cached_timestamp = datetime.now()
        self._cached_key = cache_key
        return timesheet_data

    def invalidate_cache(
        self,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None,
    ) -> None:
        """Invalidar cache (substituir por None)."""
        self._cached_data = None
        self._cached_timestamp = None
        self._cached_key = None
        debug_log("WorklogService", "invalidate_cache", "Cache invalidado")

    def _fetch_from_api(
        self, user_email: str, start_date: date, end_date: date
    ) -> TimesheetData:
        """Buscar dados da API do Jira."""
        if not self._jira_client:
            return TimesheetData(start_date=start_date, end_date=end_date, issues=[])

        max_results = self._get_max_results()
        issues_data = self._jira_client.search_issues_with_worklogs_in_period(
            start_date=start_date,
            end_date=end_date,
            user_email=user_email,
            max_results=max_results,
        )

        issue_summaries: List[IssueWorklogSummary] = []
        date_range = [
            start_date + timedelta(days=i)
            for i in range((end_date - start_date).days + 1)
        ]

        def fetch_worklogs_for_issue(
            issue: Dict[str, Any],
        ) -> Optional[IssueWorklogSummary]:
            """Buscar worklogs de uma issue e montar IssueWorklogSummary."""
            key = issue.get("key", "")
            if not key:
                return None
            fields = issue.get("fields") or {}
            summary = (fields.get("summary") or "").strip()
            status_obj = fields.get("status") or {}
            status = (status_obj.get("name") or "").strip()
            issue_type_obj = fields.get("issuetype") or {}
            issue_type = (issue_type_obj.get("name") or "").strip()

            try:
                worklogs_raw = self._jira_client.get_issue_worklogs(
                    key, start_at=0, max_results=100
                )
            except Exception as e:
                debug_log(
                    "WorklogService",
                    "_fetch_from_api",
                    "Erro ao buscar worklogs de %s: %s",
                    key,
                    e,
                )
                return None

            user_worklogs: List[WorklogEntry] = []
            for w in worklogs_raw:
                author = w.get("author") or {}
                email = (
                    author.get("emailAddress") or author.get("accountId") or ""
                ).strip()
                if not email or email.lower() != user_email.lower():
                    continue
                started_str = w.get("started", "")
                started_dt = _parse_started(started_str)
                wl_date = (
                    started_dt.date()
                    if isinstance(started_dt, datetime)
                    else started_dt
                )
                if start_date <= wl_date <= end_date:
                    user_worklogs.append(
                        WorklogEntry(
                            id=str(w.get("id", "")),
                            issue_key=key,
                            time_spent_seconds=int(w.get("timeSpentSeconds", 0)),
                            started=started_dt,
                            comment=(w.get("comment") or "").strip() or None,
                            author=(author.get("displayName") or "").strip(),
                        )
                    )

            if not user_worklogs:
                return None

            worklogs_by_date: Dict[date, List[WorklogEntry]] = {}
            for wl in user_worklogs:
                wl_date = wl.date
                if wl_date not in worklogs_by_date:
                    worklogs_by_date[wl_date] = []
                worklogs_by_date[wl_date].append(wl)

            return IssueWorklogSummary(
                issue_key=key,
                issue_summary=summary,
                issue_status=status,
                issue_type=issue_type,
                worklogs_by_date=worklogs_by_date,
            )

        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = {
                executor.submit(fetch_worklogs_for_issue, issue): issue
                for issue in issues_data
            }
            for future in as_completed(futures):
                try:
                    result = future.result()
                    if result:
                        issue_summaries.append(result)
                except Exception as e:
                    debug_log(
                        "WorklogService",
                        "_fetch_from_api",
                        "Erro ao processar issue: %s",
                        e,
                    )

        return TimesheetData(
            start_date=start_date,
            end_date=end_date,
            issues=issue_summaries,
        )
