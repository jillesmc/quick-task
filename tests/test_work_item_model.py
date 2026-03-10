"""
Testes unitários para src/models/work_item_model.py
"""

import sys
from datetime import datetime
from unittest.mock import patch, MagicMock

import os

is_flatpak = os.path.exists("/.flatpak-info")
if not is_flatpak and "/usr/lib/python3/dist-packages" not in sys.path:
    sys.path.insert(0, "/usr/lib/python3/dist-packages")

import pytest

from tests.conftest import QtBot
from src.models.work_item_model import WorkItemModel


@pytest.fixture
def mock_config_manager_work_item(sample_config):
    """Fixture para ConfigManager mockado para WorkItemModel"""
    config = MagicMock()
    config.get_tipo_atividade_values = MagicMock(
        return_value=sample_config["tipo_atividade_values"]
    )
    config.get_status_sequence = MagicMock(
        return_value=sample_config["status_sequence"]
    )
    return config


@pytest.fixture
def work_item_model(qtbot, mock_config_manager_work_item):
    """Fixture para WorkItemModel com ConfigManager mockado"""
    with patch(
        "src.models.work_item_model.ConfigManager",
        return_value=mock_config_manager_work_item,
    ):
        model = WorkItemModel()
        return model


def test_work_item_model_init(work_item_model, sample_config):
    """Testa inicialização com valores padrão"""
    assert work_item_model.summary == ""
    assert work_item_model.description == ""
    assert work_item_model.documentacaoAnexa == "Não"
    assert work_item_model.utilizacaoIA == "Não"
    assert work_item_model.registrarWorklog is False
    assert work_item_model.worklogDuracao == 30


def test_work_item_model_summary_setter_getter(work_item_model, qtbot):
    """Testa setter/getter de summary"""
    work_item_model.summary = "Test Summary"
    assert work_item_model.summary == "Test Summary"


def test_work_item_model_summary_signal_emitted(work_item_model, qtbot):
    """Testa que signal é emitido ao mudar summary"""
    with qtbot.wait_signal(work_item_model.summaryChanged, timeout=1000):
        work_item_model.summary = "New Summary"


def test_work_item_model_set_assets_cache_no_raise(work_item_model):
    """set_assets_cache aceita cache (ou None) e não levanta"""
    work_item_model.set_assets_cache(None)
    work_item_model.set_assets_cache(MagicMock())


def test_work_item_model_reset_to_defaults(work_item_model, sample_config):
    """Testa resetar todos os campos para padrão"""
    work_item_model.summary = "Test"
    work_item_model.description = "Test Desc"
    work_item_model.tipoAtividade = sample_config["tipo_atividade_values"][1]
    work_item_model.statusInicial = sample_config["status_sequence"][1]
    work_item_model.registrarWorklog = True
    work_item_model.worklogDuracao = 120

    work_item_model.reset_to_defaults()

    assert work_item_model.summary == ""
    assert work_item_model.description == ""
    assert work_item_model.registrarWorklog is False
    assert work_item_model.worklogDuracao == 30
    assert work_item_model.statusInicial == sample_config["status_sequence"][0]
