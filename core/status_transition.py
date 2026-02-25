"""
Máquina de estado para transições sequenciais de status
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Callable, Dict, List, Optional

from core.jira_client import JiraClient

# Mapeamento de nomes de status do config.json para nomes reais do Jira
# Este mapeamento é usado apenas quando necessário (normalmente jira-cli aceita uppercase)
# Se algum status não funcionar, adicione o mapeamento aqui
STATUS_NAME_MAPPING: Dict[str, str] = {
    # Adicionar mapeamentos apenas quando necessário
    # Exemplo: "DONE": "Done" se o Jira usar "Done" ao invés de "DONE"
}


def normalize_status_name(status: str) -> str:
    """
    Normaliza o nome do status do config.json para o nome real usado no Jira.

    O jira-cli aceita nomes em uppercase, então retornamos o status como está.
    Se houver mapeamento explícito, usamos ele.

    Args:
        status: Nome do status do config.json (ex: "TO DO", "DONE")

    Returns:
        Nome do status para uso com jira-cli (mantém formato original ou mapeado)
    """
    # Se houver mapeamento explícito, usar ele
    if status in STATUS_NAME_MAPPING:
        return STATUS_NAME_MAPPING[status]

    # Caso contrário, retornar como está (jira-cli aceita uppercase)
    return status


@dataclass
class WorklogConfig:
    """Configuração para registro de worklog"""

    registrar: bool = False
    inicio: Optional[datetime] = None
    duracao: int = 0
    timezone: str = "UTC"
    comment: Optional[str] = None


def _validate_parameters(issue_key: str, target_status: str) -> None:
    """Valida os parâmetros obrigatórios"""
    if not issue_key:
        raise ValueError("Issue key não fornecido")
    if not target_status:
        raise ValueError("Status alvo não fornecido")


def _get_target_index(target_status: str, status_sequence: List[str]) -> int:
    """Encontra o índice do status alvo na sequência"""
    try:
        return status_sequence.index(target_status)
    except ValueError:
        available = ", ".join(status_sequence)
        raise ValueError(
            f"Status '{target_status}' não encontrado na sequência. "
            f"Status disponíveis: {available}"
        )


def _get_status_index(status: str, status_sequence: List[str]) -> Optional[int]:
    """Retorna o índice do status na sequência (comparação case-insensitive). None se não encontrado."""
    if not status or not status_sequence:
        return None
    status_upper = (status or "").strip().upper()
    for i, s in enumerate(status_sequence):
        if (s or "").upper() == status_upper:
            return i
    return None


def _get_in_progress_index(status_sequence: List[str]) -> Optional[int]:
    """Retorna o índice do status 'IN PROGRESS' na sequência (case-insensitive). None se não existir."""
    return _get_status_index("IN PROGRESS", status_sequence)


def needs_two_phase_transition(
    current_status: str,
    target_status: str,
    status_sequence: List[str],
) -> bool:
    """
    Retorna True quando a transição deve ser feita em duas fases (parar em IN PROGRESS).

    Ou seja: current < IN PROGRESS e target > IN PROGRESS na sequência.
    """
    in_progress_idx = _get_in_progress_index(status_sequence)
    if in_progress_idx is None:
        return False
    current_idx = _get_status_index(current_status, status_sequence)
    target_idx = _get_status_index(target_status, status_sequence)
    if current_idx is None or target_idx is None:
        return False
    return current_idx < in_progress_idx and target_idx > in_progress_idx


def requires_worklog_check_before_transition(
    current_status: str,
    target_status: str,
    status_sequence: List[str],
) -> bool:
    """
    Retorna True se a transição exige verificação de worklogs pendentes (mostrar diálogo ou sync).

    True quando: current >= IN PROGRESS ou target > IN PROGRESS.
    Retorna False quando não há mudança de status (current == target).
    """
    if not current_status or not target_status:
        return False
    if (current_status or "").strip().upper() == (target_status or "").strip().upper():
        return False
    in_progress_idx = _get_in_progress_index(status_sequence)
    if in_progress_idx is None:
        return False
    current_idx = _get_status_index(current_status, status_sequence)
    target_idx = _get_status_index(target_status, status_sequence)
    if current_idx is None or target_idx is None:
        return False
    return current_idx >= in_progress_idx or target_idx > in_progress_idx


def _register_worklog_if_needed(
    jira_client: JiraClient,
    issue_key: str,
    next_status: str,
    worklog: Optional[WorklogConfig],
    progress_callback: Optional[Callable[[str, int, str], None]],
    percentage: int,
) -> None:
    """Registra worklog se necessário após transição para IN PROGRESS"""
    if next_status != "IN PROGRESS":
        return
    if not worklog or not worklog.registrar:
        return
    if not worklog.inicio or worklog.duracao <= 0:
        return

    if progress_callback:
        progress_callback("IN PROGRESS", percentage, "Registrando worklog...")

    time_spent = jira_client._format_duration_minutes(worklog.duracao)
    started_str = worklog.inicio.strftime("%Y-%m-%d %H:%M:%S")

    worklog_success = jira_client.register_worklog(
        issue_key=issue_key,
        time_spent=time_spent,
        started=started_str,
        timezone=worklog.timezone,
        comment=worklog.comment,
    )

    if not worklog_success:
        import sys

        print(
            f"AVISO: Não foi possível registrar worklog para {issue_key}",
            file=sys.stderr,
        )


def _transition_to_next_status(
    jira_client: JiraClient,
    issue_key: str,
    next_status: str,
    status_sequence: List[str],
    progress_callback: Optional[Callable[[str, int, str], None]],
    percentage: int,
    transition_fields: Optional[Dict[str, Any]] = None,
) -> None:
    """Transiciona para o próximo status (opcionalmente com campos no corpo da transição)."""
    if progress_callback:
        progress_callback(
            next_status, percentage, f"Transicionando para: {next_status}"
        )

    success = jira_client.transition_issue(
        issue_key,
        next_status,
        max_retries=3,
        retry_delay=1.5,
        fields=transition_fields,
    )

    if not success:
        error_msg = (
            f"Não foi possível transicionar para '{next_status}' após 3 tentativas"
        )
        if next_status not in status_sequence:
            error_msg += f". Status '{next_status}' não está na sequência configurada."
        raise RuntimeError(error_msg)


def transition_sequentially(
    jira_client: JiraClient,
    issue_key: str,
    target_status: str,
    status_sequence: List[str],
    progress_callback: Optional[Callable[[str, int, str], None]] = None,
    worklog: Optional[WorklogConfig] = None,
    transition_fields: Optional[Dict[str, Any]] = None,
) -> bool:
    """
    Transiciona uma issue sequencialmente pelos status até o status desejado.
    Ao atingir IN PROGRESS, registra worklog imediatamente se worklog estiver configurado.
    Descobre o estado atual da issue antes de começar as transições.
    Lança exceções em caso de erro.

    Args:
        jira_client: Instância do JiraClient
        issue_key: Chave da issue
        target_status: Status alvo desejado
        status_sequence: Lista sequencial de status
        progress_callback: Função callback(status_atual, porcentagem, mensagem)
        worklog: Configuração para registro de worklog (opcional); registrado ao atingir IN PROGRESS
        transition_fields: Campos a enviar em cada POST de transição (opcional)

    Returns:
        True se o worklog foi registrado ao atingir IN PROGRESS; False caso contrário.

    Raises:
        ValueError: Se parâmetros inválidos ou status não encontrado
        RuntimeError: Se transição falhar
    """
    _validate_parameters(issue_key, target_status)

    if target_status == "TO DO":
        return False

    target_index = _get_target_index(target_status, status_sequence)
    if target_index == 0:
        return False

    # Descobrir estado atual da issue
    # get_issue_details retorna dict achatado (key, id, **data["fields"]), sem chave "fields"
    current_status = None
    try:
        issue_details = jira_client.get_issue_details(issue_key)
        if issue_details:
            fields = (
                issue_details
                if "fields" not in issue_details
                else issue_details["fields"]
            )
            status_obj = fields.get("status", {}) if isinstance(fields, dict) else {}
            current_status = (status_obj.get("name", "") or "") if status_obj else ""
    except Exception:
        pass

    # Encontrar índice do estado atual na sequência
    current_index = 0
    if current_status:
        # Normalizar nome do status atual para comparar com a sequência
        # Tentar encontrar na sequência (case-insensitive)
        current_status_upper = current_status.upper()
        for idx, seq_status in enumerate(status_sequence):
            if seq_status.upper() == current_status_upper:
                current_index = idx
                break

    # Se já está no estado alvo ou além dele, não fazer nada
    if current_index >= target_index:
        if progress_callback:
            progress_callback(
                "", 100, f"Issue já está em {target_status} ou estado posterior"
            )
        return False

    # Transicionar sequencialmente do estado atual até o estado alvo.
    # Ao atingir IN PROGRESS, registra worklog imediatamente (se worklog configurado) e segue.
    worklog_registered = False
    while current_index < target_index:
        next_index = current_index + 1
        next_status = status_sequence[next_index]
        percentage = int((next_index * 100) / (target_index + 1))

        _transition_to_next_status(
            jira_client,
            issue_key,
            next_status,
            status_sequence,
            progress_callback,
            percentage,
            transition_fields=transition_fields,
        )

        # Registrar worklog logo após transicionar para IN PROGRESS (primeira opção de uso)
        if (
            worklog
            and (next_status or "").upper() == "IN PROGRESS"
            and worklog.registrar
            and worklog.inicio
            and worklog.duracao > 0
        ):
            _register_worklog_if_needed(
                jira_client,
                issue_key,
                next_status,
                worklog,
                progress_callback,
                percentage,
            )
            worklog_registered = True

        current_index = next_index

    if progress_callback:
        progress_callback("", 100, "Transições concluídas!")

    return worklog_registered
