"""
Testes unitários para config/config_manager.py
"""

import json
import tempfile
from pathlib import Path

import pytest

from config.config_manager import ConfigManager


def test_load_config_success(temp_config_file: Path, sample_config: dict):
    """Testa carregamento de configuração válida"""
    manager = ConfigManager(config_path=temp_config_file)
    assert manager.get_project() == sample_config["project"]
    assert manager.get_issue_type() == sample_config["issue_type"]


def test_load_config_file_not_found():
    """Testa comportamento quando arquivo não existe (não lança exceção, apenas loga)"""
    # ConfigManager não lança exceção; cria config com defaults de assets em memória
    manager = ConfigManager(config_path=Path("/nonexistent/config.json"))
    assert "assets" in manager._config
    assert manager._config["assets"]["object_type_id_valor_entregue"] == 434
    assert manager._config["assets"]["object_type_id_plataformas_afetadas"] == 441
    assert len(manager._config) == 1


def test_load_config_invalid_json():
    """Testa comportamento quando JSON é inválido (não lança exceção, apenas loga)"""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        f.write("{ invalid json }")
        temp_path = Path(f.name)

    try:
        # ConfigManager não lança exceção, apenas cria config vazio e loga erro
        manager = ConfigManager(config_path=temp_path)
        assert manager._config == {}
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_validate_config_missing_required_keys():
    """Testa validação quando chaves obrigatórias estão faltando (não lança exceção, apenas loga)"""
    incomplete_config = {
        "project": "TEST"
        # Faltam outras chaves obrigatórias
    }

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(incomplete_config, f)
        temp_path = Path(f.name)

    try:
        # ConfigManager não lança exceção, apenas loga aviso e continua com config parcial
        manager = ConfigManager(config_path=temp_path)
        assert manager._config["project"] == incomplete_config["project"]
        assert "assets" in manager._config
        # Verificar que get() retorna None para chaves faltantes
        assert manager.get("issue_type") is None
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_validate_config_missing_custom_fields():
    """Testa validação quando campos customizados estão faltando (não lança exceção, apenas loga)"""
    config_missing_fields = {
        "project": "TEST",
        "issue_type": "Task",
        "assignee": "test@example.com",
        "custom_fields": {
            "tipo_atividade": "tipo-de-atividade"
            # Faltam documentacao_anexa e utilizacao_ia
        },
        "tipo_atividade_values": ["Opção 1"],
        "status_sequence": ["TO DO", "DONE"],
    }

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_missing_fields, f)
        temp_path = Path(f.name)

    try:
        # ConfigManager não lança exceção, apenas loga aviso e continua com config parcial
        manager = ConfigManager(config_path=temp_path)
        for key, value in config_missing_fields.items():
            assert manager._config.get(key) == value
        assert "assets" in manager._config
        # Verificar que get_custom_field() retorna string vazia para campos faltantes
        assert manager.get_custom_field("documentacao_anexa") == ""
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_get_project(config_manager: ConfigManager, sample_config: dict):
    """Testa retorno do projeto"""
    assert config_manager.get_project() == sample_config["project"]


def test_get_issue_type(config_manager: ConfigManager, sample_config: dict):
    """Testa retorno do tipo de issue"""
    assert config_manager.get_issue_type() == sample_config["issue_type"]


def test_get_assignee(config_manager: ConfigManager, sample_config: dict):
    """Testa retorno do assignee"""
    assert config_manager.get_assignee() == sample_config["assignee"]


def test_get_custom_field(config_manager: ConfigManager, sample_config: dict):
    """Testa retorno de alias de campo customizado"""
    assert (
        config_manager.get_custom_field("tipo_atividade")
        == sample_config["custom_fields"]["tipo_atividade"]
    )
    assert (
        config_manager.get_custom_field("documentacao_anexa")
        == sample_config["custom_fields"]["documentacao_anexa"]
    )


def test_get_custom_field_not_found(config_manager: ConfigManager):
    """Testa retorno quando campo customizado não existe"""
    assert config_manager.get_custom_field("campo_inexistente") == ""


def test_get_tipo_atividade_values(config_manager: ConfigManager, sample_config: dict):
    """Testa retorno de valores de tipo de atividade"""
    assert (
        config_manager.get_tipo_atividade_values()
        == sample_config["tipo_atividade_values"]
    )


def test_get_status_sequence(config_manager: ConfigManager, sample_config: dict):
    """Testa retorno de sequência de status"""
    assert config_manager.get_status_sequence() == sample_config["status_sequence"]


def test_get_timezone(config_manager: ConfigManager, sample_config: dict):
    """Testa retorno de timezone"""
    assert config_manager.get_timezone() == sample_config["worklog_timezone"]


def test_get_timezone_default():
    """Testa retorno de timezone padrão quando não configurado"""
    config_no_timezone = {
        "project": "TEST",
        "issue_type": "Task",
        "assignee": "test@example.com",
        "custom_fields": {
            "tipo_atividade": "tipo-de-atividade",
            "documentacao_anexa": "documentacao-anexa",
            "utilizacao_ia": "utilizacao-de-ia",
        },
        "tipo_atividade_values": ["Opção 1"],
        "status_sequence": ["TO DO", "DONE"],
    }

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_no_timezone, f)
        temp_path = Path(f.name)

    try:
        manager = ConfigManager(config_path=temp_path)
        # Quando não configurado, deve usar o timezone padrão da aplicação
        assert manager.get_timezone() == "America/Sao_Paulo"
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_get_nested_key(config_manager: ConfigManager):
    """Testa acesso a chave aninhada com notação de ponto"""
    # get() suporta notação de ponto
    assert config_manager.get("custom_fields.tipo_atividade") == "tipo-de-atividade"
    assert (
        config_manager.get("custom_fields.documentacao_anexa") == "documentacao-anexa"
    )


def test_get_key_with_default(config_manager: ConfigManager):
    """Testa retorno de default quando chave não existe"""
    assert config_manager.get("chave_inexistente", "default_value") == "default_value"
    assert config_manager.get("custom_fields.inexistente", "default") == "default"
