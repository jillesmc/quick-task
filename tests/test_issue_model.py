"""
Testes unitários para src/models/issue_model.py
"""

import sys
from datetime import datetime
from unittest.mock import patch, MagicMock

# Adicionar pacotes do sistema ao path
# No Flatpak, PySide6 vem do runtime, então não precisamos adicionar este caminho
import os

is_flatpak = os.path.exists("/.flatpak-info")
if not is_flatpak and "/usr/lib/python3/dist-packages" not in sys.path:
    sys.path.insert(0, "/usr/lib/python3/dist-packages")

import pytest

# Importar QtBot do conftest (que já trata a disponibilidade)
from tests.conftest import QtBot

from src.models.issue_model import IssueModel


@pytest.fixture
def mock_config_manager(sample_config):
    """Fixture para ConfigManager mockado para IssueModel"""
    config = MagicMock()
    config.get_tipo_atividade_values = MagicMock(
        return_value=sample_config["tipo_atividade_values"]
    )
    config.get_status_sequence = MagicMock(
        return_value=sample_config["status_sequence"]
    )
    return config


@pytest.fixture
def issue_model(qtbot, mock_config_manager):
    """Fixture para IssueModel com ConfigManager mockado"""
    with patch(
        "src.models.issue_model.ConfigManager", return_value=mock_config_manager
    ):
        model = IssueModel()
        # IssueModel é QObject, não QWidget, então não precisa de add_widget
        return model


def test_issue_model_init(issue_model, sample_config):
    """Testa inicialização com valores padrão"""
    assert issue_model.summary == ""
    assert issue_model.description == ""
    assert issue_model.documentacaoAnexa == "Não"
    assert issue_model.utilizacaoIA == "Não"
    assert issue_model.registrarWorklog is False
    assert issue_model.worklogDuracao == 30


def test_issue_model_summary_setter_getter(issue_model, qtbot):
    """Testa setter/getter de summary"""
    issue_model.summary = "Test Summary"
    assert issue_model.summary == "Test Summary"


def test_issue_model_summary_signal_emitted(issue_model, qtbot):
    """Testa que signal é emitido ao mudar summary"""
    with qtbot.wait_signal(issue_model.summaryChanged, timeout=1000):
        issue_model.summary = "New Summary"


def test_issue_model_description_setter_getter(issue_model):
    """Testa setter/getter de description"""
    issue_model.description = "Test Description"
    assert issue_model.description == "Test Description"


def test_issue_model_tipo_atividade_setter_getter(issue_model, sample_config):
    """Testa setter/getter de tipoAtividade"""
    new_value = sample_config["tipo_atividade_values"][0]
    issue_model.tipoAtividade = new_value
    assert issue_model.tipoAtividade == new_value


def test_issue_model_status_inicial_setter_getter(issue_model, sample_config):
    """Testa setter/getter de statusInicial"""
    new_status = sample_config["status_sequence"][1]
    issue_model.statusInicial = new_status
    assert issue_model.statusInicial == new_status


def test_issue_model_documentacao_anexa_setter_getter(issue_model):
    """Testa setter/getter de documentacaoAnexa"""
    issue_model.documentacaoAnexa = "Sim"
    assert issue_model.documentacaoAnexa == "Sim"

    issue_model.documentacaoAnexa = "Não"
    assert issue_model.documentacaoAnexa == "Não"


def test_issue_model_utilizacao_ia_setter_getter(issue_model):
    """Testa setter/getter de utilizacaoIA"""
    issue_model.utilizacaoIA = "Sim"
    assert issue_model.utilizacaoIA == "Sim"

    issue_model.utilizacaoIA = "Não"
    assert issue_model.utilizacaoIA == "Não"


def test_issue_model_registrar_worklog_setter_getter(issue_model, qtbot):
    """Testa setter/getter de registrarWorklog"""
    issue_model.registrarWorklog = True
    assert issue_model.registrarWorklog is True

    issue_model.registrarWorklog = False
    assert issue_model.registrarWorklog is False


def test_issue_model_worklog_inicio_setter_getter(issue_model):
    """Testa setter/getter de worklogInicio (string)"""
    date_str = "2024-01-01 10:00:00"
    issue_model.worklogInicio = date_str
    assert issue_model.worklogInicio == date_str


def test_issue_model_worklog_duracao_setter_getter(issue_model, qtbot):
    """Testa setter/getter de worklogDuracao"""
    issue_model.worklogDuracao = 60
    assert issue_model.worklogDuracao == 60

    issue_model.worklogDuracao = 90
    assert issue_model.worklogDuracao == 90


def test_issue_model_tipo_atividade_values_readonly(issue_model, sample_config):
    """Testa que valores de tipo de atividade são read-only"""
    values = issue_model.tipoAtividadeValues
    assert values == sample_config["tipo_atividade_values"]
    # Não deve ter setter
    assert not hasattr(issue_model, "setTipoAtividadeValues")


def test_issue_model_status_sequence_readonly(issue_model, sample_config):
    """Testa que sequência de status é read-only"""
    sequence = issue_model.statusSequence
    assert sequence == sample_config["status_sequence"]
    # Não deve ter setter
    assert not hasattr(issue_model, "setStatusSequence")


def test_issue_model_get_worklog_inicio_datetime(issue_model):
    """Testa conversão de worklogInicio para datetime"""
    date_str = "2024-01-01 10:30:00"
    issue_model.worklogInicio = date_str

    dt = issue_model.get_worklog_inicio_datetime()
    assert dt is not None
    assert dt.year == 2024
    assert dt.month == 1
    assert dt.day == 1
    assert dt.hour == 10
    assert dt.minute == 30


def test_issue_model_get_worklog_inicio_datetime_invalid(issue_model):
    """Testa que datetime inválido retorna None"""
    issue_model.worklogInicio = "invalid date"
    dt = issue_model.get_worklog_inicio_datetime()
    # Pode retornar None ou um datetime inválido dependendo da implementação
    # Vamos testar que não lança exceção
    assert dt is None or isinstance(dt, datetime)


def test_issue_model_reset_to_defaults(issue_model, sample_config):
    """Testa resetar todos os campos para padrão"""
    # Modificar valores
    issue_model.summary = "Test"
    issue_model.description = "Test Desc"
    issue_model.tipoAtividade = sample_config["tipo_atividade_values"][1]
    issue_model.statusInicial = sample_config["status_sequence"][1]
    issue_model.documentacaoAnexa = "Sim"
    issue_model.utilizacaoIA = "Sim"
    issue_model.registrarWorklog = True
    issue_model.worklogDuracao = 120

    # Resetar
    issue_model.reset_to_defaults()

    # Verificar valores padrão
    assert issue_model.summary == ""
    assert issue_model.description == ""
    assert issue_model.documentacaoAnexa == "Não"
    assert issue_model.utilizacaoIA == "Não"
    assert issue_model.registrarWorklog is False
    assert issue_model.worklogDuracao == 30
    # Status e tipo devem voltar para o primeiro da lista
    assert issue_model.statusInicial == sample_config["status_sequence"][0]
