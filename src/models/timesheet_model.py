"""
ViewModel para a tela de Timesheet.
Expõe dados de worklogs para QML com loading assíncrono.
"""

from datetime import date, timedelta
from typing import Any, Dict, List, Optional

from PySide6.QtCore import QObject, Property, Signal, Slot, QThread  # type: ignore[import]

from config.config_manager import ConfigManager
from src.services.worklog_service import (
    WorklogService,
    TimesheetData,
    IssueWorklogSummary,
)
from src.utils.debug import debug_log


class TimesheetWorker(QThread):
    """Worker thread para carregar dados do timesheet."""

    dataLoaded = Signal(object)  # TimesheetData
    errorOccurred = Signal(str)

    def __init__(
        self,
        worklog_service: WorklogService,
        user_email: str,
        start_date: date,
        end_date: date,
        use_cache: bool,
        parent=None,
    ):
        super().__init__(parent)
        self._worklog_service = worklog_service
        self._user_email = user_email
        self._start_date = start_date
        self._end_date = end_date
        self._use_cache = use_cache

    def run(self):
        try:
            data = self._worklog_service.get_timesheet_data(
                user_email=self._user_email,
                start_date=self._start_date,
                end_date=self._end_date,
                use_cache=self._use_cache,
            )
            self.dataLoaded.emit(data)
        except Exception as e:
            debug_log("TimesheetWorker", "run", "Erro: %s", e)
            self.errorOccurred.emit(str(e))


class TimesheetModel(QObject):
    """ViewModel para tela de Timesheet."""

    dataChanged = Signal()
    loadingChanged = Signal()
    errorChanged = Signal()
    worklogDetailsRequested = Signal("QVariant")  # dict com detalhes

    def __init__(
        self,
        worklog_service: WorklogService,
        config: ConfigManager,
        user_email: str,
        parent=None,
    ):
        super().__init__(parent)
        self._worklog_service = worklog_service
        self._config = config
        self._user_email = user_email
        self._timesheet_data: Optional[TimesheetData] = None
        self._loading = False
        self._error: Optional[str] = None
        self._current_period = "last_7_days"
        self._worker: Optional[TimesheetWorker] = None

    @Property(bool, notify=loadingChanged)
    def loading(self) -> bool:
        return self._loading

    @Property(str, notify=errorChanged)
    def error(self) -> str:
        return self._error or ""

    @Property(str, notify=dataChanged)
    def periodLabel(self) -> str:
        """Label do período atual (legado)."""
        return self._current_period.replace("_", " ").title()

    @Property(str, notify=dataChanged)
    def periodDateRange(self) -> str:
        """Intervalo de datas no formato DD/MM - DD/MM."""
        if not self._timesheet_data:
            return self._current_period.replace("_", " ").title()
        start = self._timesheet_data.start_date.strftime("%d/%m")
        end = self._timesheet_data.end_date.strftime("%d/%m")
        return f"{start} - {end}"

    @Property(bool, notify=dataChanged)
    def hasCachedData(self) -> bool:
        """True quando há dados em cache (já carregados)."""
        return self._timesheet_data is not None

    @Property(list, notify=dataChanged)
    def dateHeaders(self) -> list:
        """Headers de datas para colunas."""
        if not self._timesheet_data:
            return []
        return [
            {
                "date": d.isoformat(),
                "day": d.strftime("%d"),
                "weekday": d.strftime("%a").upper(),
            }
            for d in self._timesheet_data.date_range
        ]

    @Property(list, notify=dataChanged)
    def issueRows(self) -> list:
        """Linhas de issues para tabela."""
        if not self._timesheet_data:
            return []
        rows = []
        for issue in self._timesheet_data.issues:
            time_cells = [
                issue.get_time_for_date(d) for d in self._timesheet_data.date_range
            ]
            rows.append(
                {
                    "issueKey": issue.issue_key,
                    "summary": issue.issue_summary,
                    "status": issue.issue_status,
                    "statusIcon": self._get_status_icon(issue.issue_status),
                    "total": issue.total_formatted,
                    "timeCells": time_cells,
                    "worklogsByDate": {
                        d.isoformat(): [
                            {
                                "timeSpent": wl.time_spent_formatted,
                                "started": (
                                    wl.started.strftime("%H:%M")
                                    if hasattr(wl.started, "strftime")
                                    else ""
                                ),
                                "comment": wl.comment or "(sem descrição)",
                            }
                            for wl in wls
                        ]
                        for d, wls in issue.worklogs_by_date.items()
                    },
                }
            )
        return rows

    @Property(list, notify=dataChanged)
    def totalRow(self) -> list:
        """Linha de totais por dia."""
        if not self._timesheet_data:
            return []
        return [
            self._timesheet_data.get_daily_total(d)
            for d in self._timesheet_data.date_range
        ]

    @Property(str, notify=dataChanged)
    def grandTotal(self) -> str:
        """Total geral."""
        if not self._timesheet_data:
            return "00:00"
        return self._timesheet_data.grand_total

    @Slot(str)
    def setPeriod(self, period: str):
        """Alterar período exibido."""
        self._current_period = period
        start_date, end_date = self._calculate_period_dates(period)
        self._load_data(start_date, end_date, use_cache=True)

    @Slot()
    def navigatePrevious(self):
        """Navegar para período anterior."""
        if not self._timesheet_data:
            return
        delta = self._timesheet_data.end_date - self._timesheet_data.start_date
        new_end = self._timesheet_data.start_date - timedelta(days=1)
        new_start = new_end - delta
        self._load_data(new_start, new_end, use_cache=True)

    @Slot()
    def navigateNext(self):
        """Navegar para próximo período."""
        if not self._timesheet_data:
            return
        delta = self._timesheet_data.end_date - self._timesheet_data.start_date
        new_start = self._timesheet_data.end_date + timedelta(days=1)
        new_end = new_start + delta
        self._load_data(new_start, new_end, use_cache=True)

    @Slot()
    def refresh(self):
        """Forçar atualização (ignorar cache)."""
        if not self._timesheet_data:
            start_date, end_date = self._calculate_period_dates(self._current_period)
        else:
            start_date = self._timesheet_data.start_date
            end_date = self._timesheet_data.end_date
        self._worklog_service.invalidate_cache()
        self._load_data(start_date, end_date, use_cache=False)

    @Slot(str, str)
    def showWorklogDetails(self, issue_key: str, date_str: str):
        """Mostrar detalhes de worklogs de um dia específico."""
        if not self._timesheet_data:
            return
        try:
            target_date = date.fromisoformat(date_str)
        except (ValueError, TypeError):
            return
        issue = next(
            (i for i in self._timesheet_data.issues if i.issue_key == issue_key),
            None,
        )
        if not issue or target_date not in issue.worklogs_by_date:
            return
        worklogs = issue.worklogs_by_date[target_date]
        details = {
            "issueKey": issue_key,
            "date": date_str,
            "worklogs": [
                {
                    "timeSpent": wl.time_spent_formatted,
                    "started": (
                        wl.started.strftime("%H:%M")
                        if hasattr(wl.started, "strftime")
                        else ""
                    ),
                    "comment": wl.comment or "(sem descrição)",
                }
                for wl in worklogs
            ],
            "total": issue.get_time_for_date(target_date),
        }
        self.worklogDetailsRequested.emit(details)

    def _load_data(self, start_date: date, end_date: date, use_cache: bool = True):
        """Carregar dados de timesheet em thread."""
        if self._worker and self._worker.isRunning():
            return
        self._loading = True
        self._error = None
        self.loadingChanged.emit()
        self.errorChanged.emit()

        self._worker = TimesheetWorker(
            self._worklog_service,
            self._user_email,
            start_date,
            end_date,
            use_cache,
            self,
        )
        self._worker.dataLoaded.connect(self._on_data_loaded)
        self._worker.errorOccurred.connect(self._on_error)
        self._worker.finished.connect(self._on_worker_finished)
        self._worker.start()

    def _on_data_loaded(self, data: TimesheetData):
        self._timesheet_data = data
        self._loading = False
        self.loadingChanged.emit()
        self.dataChanged.emit()

    def _on_error(self, message: str):
        self._error = message
        self._loading = False
        self.loadingChanged.emit()
        self.errorChanged.emit()

    def _on_worker_finished(self):
        self._worker = None

    def _calculate_period_dates(self, period: str) -> tuple:
        """Calcular datas de início e fim do período."""
        today = date.today()
        if period == "today":
            return (today, today)
        if period == "this_week":
            start = today - timedelta(days=today.weekday())
            end = start + timedelta(days=6)
            return (start, end)
        if period == "last_week":
            this_week_start = today - timedelta(days=today.weekday())
            start = this_week_start - timedelta(days=7)
            end = start + timedelta(days=6)
            return (start, end)
        if period == "last_7_days":
            start = today - timedelta(days=6)
            return (start, today)
        if period == "this_month":
            start = today.replace(day=1)
            if today.month == 12:
                end = today.replace(year=today.year + 1, month=1, day=1) - timedelta(
                    days=1
                )
            else:
                end = today.replace(month=today.month + 1, day=1) - timedelta(days=1)
            return (start, end)
        if period == "last_month":
            first_this_month = today.replace(day=1)
            end = first_this_month - timedelta(days=1)
            start = end.replace(day=1)
            return (start, end)
        start = today - timedelta(days=6)
        return (start, today)

    def _get_status_icon(self, status: str) -> str:
        """Obter ícone para status."""
        status_lower = (status or "").lower()
        if "done" in status_lower or "closed" in status_lower:
            return "✅"
        if "progress" in status_lower or "doing" in status_lower:
            return "🔵"
        if "review" in status_lower:
            return "👀"
        if "todo" in status_lower or "open" in status_lower:
            return "⚪"
        return "🔘"

    @Slot()
    def loadInitial(self):
        """Carregar dados iniciais (período padrão da config). Usa cache se disponível."""
        cfg = self._config.get_timesheet_config()
        self._current_period = cfg.get("default_period", "last_7_days") or "last_7_days"
        start_date, end_date = self._calculate_period_dates(self._current_period)
        self._load_data(start_date, end_date, use_cache=True)
