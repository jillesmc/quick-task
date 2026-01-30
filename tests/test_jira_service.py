"""
Testes unitários para src/jira_service.py
"""

import sys
from datetime import datetime
from unittest.mock import MagicMock, patch, Mock

# Adicionar pacotes do sistema ao path
# No Flatpak, PySide6 vem do runtime, então não precisamos adicionar este caminho
import os

is_flatpak = os.path.exists("/.flatpak-info")
if not is_flatpak and "/usr/lib/python3/dist-packages" not in sys.path:
    sys.path.insert(0, "/usr/lib/python3/dist-packages")

import pytest

# Importar QtBot do conftest (que já trata a disponibilidade)
from tests.conftest import QtBot

from src.jira_service import JiraService, JiraWorker
from core.status_transition import WorklogConfig


@pytest.fixture
def jira_service(qtbot, mock_jira_client, mock_config_manager):
    """Fixture para JiraService com dependências mockadas"""
    with (
        patch("src.jira_service.JiraClient", return_value=mock_jira_client),
        patch("src.jira_service.ConfigManager", return_value=mock_config_manager),
    ):
        service = JiraService()
        # JiraService é QObject, não QWidget, então não precisa de add_widget
        return service


def test_jira_service_init(jira_service, mock_jira_client, mock_config_manager):
    """Testa inicialização do serviço"""
    assert jira_service._jira_client is not None
    assert jira_service._config is not None


def test_jira_service_init_config_error(qtbot):
    """Testa erro ao carregar configuração"""
    with patch("src.jira_service.ConfigManager", side_effect=Exception("Config error")):
        service = JiraService()
        # JiraService é QObject, não QWidget
        assert service._config is None


def test_jira_service_init_jira_client_error(qtbot, mock_config_manager):
    """Testa erro ao inicializar cliente"""
    with (
        patch("src.jira_service.JiraClient", side_effect=RuntimeError("Jira error")),
        patch("src.jira_service.ConfigManager", return_value=mock_config_manager),
    ):
        service = JiraService()
        # JiraService é QObject, não QWidget
        assert service._jira_client is None


def test_jira_service_is_available(jira_service):
    """Testa verificação de disponibilidade"""
    assert jira_service.isAvailable() is True


def test_jira_service_is_available_false(qtbot):
    """Testa disponibilidade quando cliente não está inicializado"""
    with (
        patch("src.jira_service.JiraClient", return_value=None),
        patch("src.jira_service.ConfigManager", return_value=MagicMock()),
    ):
        service = JiraService()
        # JiraService é QObject, não QWidget
        assert service.isAvailable() is False


def test_jira_service_get_timezone(jira_service, sample_config):
    """Testa retorno de timezone"""
    timezone = jira_service.getTimezone()
    assert timezone == sample_config.get("worklog_timezone", "UTC")


def test_jira_service_create_issue_success(jira_service, qtbot, mock_jira_client):
    """Testa criação de issue com sucesso"""
    # Mockar worker para não executar thread real
    mock_worker = MagicMock(spec=JiraWorker)
    mock_worker.isRunning = Mock(return_value=False)

    with patch("src.jira_service.JiraWorker", return_value=mock_worker):
        result = jira_service.createIssue(
            summary="Test Issue",
            description="Test Description",
            tipoAtividade="Opção 1",
            statusInicial="TO DO",
            documentacaoAnexa="Não",
            utilizacaoIA="Não",
            registrarWorklog=False,
            worklogInicio="",
            worklogDuracao=0,
            worklogTimezone="UTC",
            parentEpicKey="",
            worklogComment="",
            valorEntregue="",
            plataformasAfetadas=[],
        )

        assert result is True
        assert jira_service._worker is not None


def test_jira_service_create_issue_empty_summary(jira_service, qtbot):
    """Testa que summary vazio deve falhar"""
    with qtbot.wait_signal(jira_service.errorOccurred, timeout=1000):
        result = jira_service.createIssue(
            summary="   ",  # Apenas espaços
            description="",
            tipoAtividade="Opção 1",
            statusInicial="TO DO",
            documentacaoAnexa="Não",
            utilizacaoIA="Não",
            registrarWorklog=False,
            worklogInicio="",
            worklogDuracao=0,
            worklogTimezone="UTC",
            parentEpicKey="",
            worklogComment="",
            valorEntregue="",
            plataformasAfetadas=[],
        )

        assert result is False


def test_jira_service_create_issue_invalid_datetime(jira_service, qtbot):
    """Testa que data/hora inválida deve falhar"""
    with qtbot.wait_signal(jira_service.errorOccurred, timeout=1000):
        result = jira_service.createIssue(
            summary="Test",
            description="",
            tipoAtividade="Opção 1",
            statusInicial="TO DO",
            documentacaoAnexa="Não",
            utilizacaoIA="Não",
            registrarWorklog=True,
            worklogInicio="invalid date",
            worklogDuracao=60,
            worklogTimezone="UTC",
            parentEpicKey="",
            worklogComment="comentário",
            valorEntregue="",
            plataformasAfetadas=[],
        )

        assert result is False


def test_jira_service_create_issue_cancel_previous_worker(
    jira_service, qtbot, mock_jira_client
):
    """Testa cancelamento de worker anterior"""
    # Criar worker mockado que está rodando
    mock_worker_running = MagicMock(spec=JiraWorker)
    mock_worker_running.isRunning = Mock(return_value=True)
    mock_worker_running.terminate = Mock()
    mock_worker_running.wait = Mock()
    jira_service._worker = mock_worker_running

    # Criar novo worker mockado
    mock_worker_new = MagicMock(spec=JiraWorker)
    mock_worker_new.isRunning = Mock(return_value=False)

    with patch("src.jira_service.JiraWorker", return_value=mock_worker_new):
        jira_service.createIssue(
            summary="Test",
            description="",
            tipoAtividade="Opção 1",
            statusInicial="TO DO",
            documentacaoAnexa="Não",
            utilizacaoIA="Não",
            registrarWorklog=False,
            worklogInicio="",
            worklogDuracao=0,
            worklogTimezone="UTC",
            parentEpicKey="",
            worklogComment="",
            valorEntregue="",
            plataformasAfetadas=[],
        )

        # Verificar que worker anterior foi cancelado
        mock_worker_running.terminate.assert_called_once()
        mock_worker_running.wait.assert_called_once()


def test_jira_worker_run_success(mock_jira_client, mock_config_manager, sample_config):
    """Testa execução do worker com sucesso"""
    worker = JiraWorker(
        jira_client=mock_jira_client,
        config=mock_config_manager,
        summary="Test Issue",
        description="Test Description",
        tipo_atividade="Opção 1",
        target_status="TO DO",
        doc_anexa="Não",
        uso_ia="Não",
    )

    # Executar run() diretamente (não iniciar thread)
    worker.run()

    # Verificar que create_issue foi chamado
    mock_jira_client.create_issue.assert_called_once()


def test_jira_worker_run_with_transitions(
    mock_jira_client, mock_config_manager, sample_config
):
    """Testa worker executando transições"""
    with patch("src.jira_service.transition_sequentially") as mock_transition:
        worker = JiraWorker(
            jira_client=mock_jira_client,
            config=mock_config_manager,
            summary="Test",
            description="",
            tipo_atividade="Opção 1",
            target_status="DONE",
            doc_anexa="Não",
            uso_ia="Não",
        )

        worker.run()

        # Verificar que transition_sequentially foi chamado
        mock_transition.assert_called_once()


def test_jira_worker_run_with_worklog(
    mock_jira_client, mock_config_manager, sample_config
):
    """Testa worker registrando worklog"""
    with patch("src.jira_service.transition_sequentially") as mock_transition:
        worker = JiraWorker(
            jira_client=mock_jira_client,
            config=mock_config_manager,
            summary="Test",
            description="",
            tipo_atividade="Opção 1",
            target_status="DONE",
            doc_anexa="Não",
            uso_ia="Não",
            registrar_worklog=True,
            worklog_inicio=datetime(2024, 1, 1, 10, 0, 0),
            worklog_duracao=60,
            worklog_timezone="UTC",
        )

        worker.run()

        # Verificar que transition_sequentially foi chamado com worklog
        call_args = mock_transition.call_args
        assert call_args[1]["worklog"] is not None
        assert call_args[1]["worklog"].registrar is True


def test_jira_worker_run_create_issue_fails(
    mock_jira_client, mock_config_manager, sample_config
):
    """Testa falha na criação de issue"""
    mock_jira_client.create_issue.side_effect = RuntimeError("Create failed")

    worker = JiraWorker(
        jira_client=mock_jira_client,
        config=mock_config_manager,
        summary="Test",
        description="",
        tipo_atividade="Opção 1",
        target_status="TO DO",
        doc_anexa="Não",
        uso_ia="Não",
    )

    # Capturar signal de erro
    error_captured = []
    worker.errorOccurred.connect(lambda msg: error_captured.append(msg))

    worker.run()

    # Verificar que erro foi emitido
    assert len(error_captured) > 0
    assert "Create failed" in error_captured[0]


def test_jira_worker_run_transition_fails(
    mock_jira_client, mock_config_manager, sample_config
):
    """Testa falha na transição"""
    with patch(
        "src.jira_service.transition_sequentially",
        side_effect=RuntimeError("Transition failed"),
    ):
        worker = JiraWorker(
            jira_client=mock_jira_client,
            config=mock_config_manager,
            summary="Test",
            description="",
            tipo_atividade="Opção 1",
            target_status="DONE",
            doc_anexa="Não",
            uso_ia="Não",
        )

        error_captured = []
        worker.errorOccurred.connect(lambda msg: error_captured.append(msg))

        worker.run()

        assert len(error_captured) > 0
        assert "Transition failed" in error_captured[0]


def test_jira_worker_signals_emitted(
    mock_jira_client, mock_config_manager, sample_config
):
    """Testa que signals são emitidos corretamente"""
    worker = JiraWorker(
        jira_client=mock_jira_client,
        config=mock_config_manager,
        summary="Test",
        description="",
        tipo_atividade="Opção 1",
        target_status="TO DO",
        doc_anexa="Não",
        uso_ia="Não",
    )

    progress_calls = []
    issue_calls = []
    finished_called = []

    worker.progressUpdated.connect(lambda p, m: progress_calls.append((p, m)))
    worker.issueCreated.connect(lambda k, u: issue_calls.append((k, u)))
    worker.finished.connect(lambda: finished_called.append(True))

    worker.run()

    # Verificar signals
    assert len(progress_calls) > 0
    assert len(issue_calls) == 1
    assert len(finished_called) == 1
    assert issue_calls[0][0] == "TEST-123"  # issue_key do mock


def test_jira_worker_parent_epic_empty_sends_none(
    mock_jira_client, mock_config_manager, sample_config
):
    """
    JiraWorker deve converter parent_epic_key vazio em None ao criar a issue.
    Isso garante que nenhum parent seja enviado ao Jira quando o usuário
    não seleciona um Epic.
    """
    worker = JiraWorker(
        jira_client=mock_jira_client,
        config=mock_config_manager,
        summary="Test Issue",
        description="Test Description",
        tipo_atividade="Opção 1",
        target_status="TO DO",
        doc_anexa="Não",
        uso_ia="Não",
        parent_epic_key="",  # equivalente a nenhum parent selecionado
    )

    worker.run()

    # Verificar que create_issue foi chamado com parent_issue_key=None
    call_args = mock_jira_client.create_issue.call_args
    kwargs = call_args[1]
    assert "parent_issue_key" in kwargs
    assert kwargs["parent_issue_key"] is None
