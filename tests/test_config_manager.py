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


def test_get_worklog_check_config_defaults(config_manager: ConfigManager):
    """Sem status_transitions no config, retorna defaults."""
    cfg = config_manager.get_worklog_check_config()
    assert cfg["enabled"] is True
    assert cfg["show_confirmation_dialog"] is True
    assert cfg["block_transition_if_pending"] is False


def test_worklog_check_getters_default(config_manager: ConfigManager):
    """Getters worklog_check retornam defaults quando secção ausente."""
    assert config_manager.worklog_check_enabled() is True
    assert config_manager.worklog_check_show_dialog() is True
    assert config_manager.worklog_check_block_if_pending() is False


def test_get_worklog_check_config_with_section():
    """Com status_transitions.worklog_check no config, retorna valores do arquivo."""
    config_with_worklog = {
        "project": "TEST",
        "issue_type": "Task",
        "assignee": "test@example.com",
        "custom_fields": {
            "tipo_atividade": "x",
            "documentacao_anexa": "y",
            "utilizacao_ia": "z",
        },
        "tipo_atividade_values": ["A"],
        "status_sequence": ["TO DO", "DONE"],
        "status_transitions": {
            "worklog_check": {
                "enabled": False,
                "show_confirmation_dialog": False,
                "block_transition_if_pending": True,
            }
        },
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_with_worklog, f)
        temp_path = Path(f.name)
    try:
        manager = ConfigManager(config_path=temp_path)
        cfg = manager.get_worklog_check_config()
        assert cfg["enabled"] is False
        assert cfg["show_confirmation_dialog"] is False
        assert cfg["block_transition_if_pending"] is True
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_save_worklog_check_config():
    """save_worklog_check_config persiste e recarrega."""
    config_base = {
        "project": "TEST",
        "issue_type": "Task",
        "assignee": "test@example.com",
        "custom_fields": {
            "tipo_atividade": "x",
            "documentacao_anexa": "y",
            "utilizacao_ia": "z",
        },
        "tipo_atividade_values": ["A"],
        "status_sequence": ["TO DO", "DONE"],
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_base, f)
        temp_path = Path(f.name)
    try:
        manager = ConfigManager(config_path=temp_path)
        manager.save_worklog_check_config(
            {
                "enabled": False,
                "show_confirmation_dialog": False,
                "block_transition_if_pending": True,
            }
        )
        assert manager.get_worklog_check_config()["enabled"] is False
        assert manager.worklog_check_block_if_pending() is True
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_get_github_token_from_config():
    """get_github_token returns token from config when no env."""
    config_with_github = {
        "project": "TEST",
        "github": {"token": "my-token", "username": "myuser"},
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_with_github, f)
        temp_path = Path(f.name)
    try:
        manager = ConfigManager(config_path=temp_path)
        assert manager.get_github_token_from_config() == "my-token"
        assert manager.get_github_username() == "myuser"
        assert manager.get_github_token() == "my-token"
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_get_github_token_only_from_config(monkeypatch):
    """get_github_token reads only from config.json; env vars are ignored."""
    config_with_github = {
        "project": "TEST",
        "github": {"token": "config-token", "username": "u"},
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_with_github, f)
        temp_path = Path(f.name)
    try:
        monkeypatch.setenv("GITHUB_API_TOKEN", "env-token-ignored")
        manager = ConfigManager(config_path=temp_path)
        assert manager.get_github_token() == "config-token"
        assert manager.get_github_token_from_config() == "config-token"
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_save_github_config():
    """save_github_config persists token and username and reloads."""
    config_base = {
        "project": "TEST",
        "github": {"token": "", "username": ""},
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_base, f)
        temp_path = Path(f.name)
    try:
        manager = ConfigManager(config_path=temp_path)
        manager.save_github_config("new-token", "newuser")
        assert manager.get_github_token_from_config() == "new-token"
        assert manager.get_github_username() == "newuser"
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_get_attachments_embed_enabled_default():
    """Sem attachments.embed no config, retorna False."""
    config_no_embed = {
        "project": "TEST",
        "issue_type": "Task",
        "assignee": "test@example.com",
        "custom_fields": {
            "tipo_atividade": "t",
            "documentacao_anexa": "d",
            "utilizacao_ia": "u",
        },
        "tipo_atividade_values": [],
        "status_sequence": [],
        "attachments": {"max_file_size_mb": 10},
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_no_embed, f)
        temp_path = Path(f.name)
    try:
        manager = ConfigManager(config_path=temp_path)
        assert manager.get_attachments_embed_enabled() is False
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_get_attachments_embed_enabled_true():
    """Com attachments.embed.enabled=true, retorna True."""
    config_with_embed = {
        "project": "TEST",
        "issue_type": "Task",
        "assignee": "test@example.com",
        "custom_fields": {
            "tipo_atividade": "t",
            "documentacao_anexa": "d",
            "utilizacao_ia": "u",
        },
        "tipo_atividade_values": [],
        "status_sequence": [],
        "attachments": {
            "max_file_size_mb": 10,
            "embed": {"enabled": True},
        },
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_with_embed, f)
        temp_path = Path(f.name)
    try:
        manager = ConfigManager(config_path=temp_path)
        assert manager.get_attachments_embed_enabled() is True
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_get_allowed_image_extensions_default():
    """Sem allowed_image_extensions no config, retorna default (png, jpg, jpeg, gif, webp)."""
    config_minimal = {
        "project": "TEST",
        "issue_type": "Task",
        "assignee": "test@example.com",
        "custom_fields": {"tipo_atividade": "t", "documentacao_anexa": "d", "utilizacao_ia": "u"},
        "tipo_atividade_values": [],
        "status_sequence": [],
        "attachments": {"max_file_size_mb": 10},
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_minimal, f)
        temp_path = Path(f.name)
    try:
        manager = ConfigManager(config_path=temp_path)
        result = manager.get_allowed_image_extensions()
        assert result == ["png", "jpg", "jpeg", "gif", "webp"]
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_get_allowed_image_extensions_from_config():
    """Com allowed_image_extensions no config, retorna a lista configurada."""
    config_with_images = {
        "project": "TEST",
        "issue_type": "Task",
        "assignee": "test@example.com",
        "custom_fields": {"tipo_atividade": "t", "documentacao_anexa": "d", "utilizacao_ia": "u"},
        "tipo_atividade_values": [],
        "status_sequence": [],
        "attachments": {
            "max_file_size_mb": 10,
            "allowed_image_extensions": ["png", "gif", "svg"],
        },
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_with_images, f)
        temp_path = Path(f.name)
    try:
        manager = ConfigManager(config_path=temp_path)
        result = manager.get_allowed_image_extensions()
        assert result == ["png", "gif", "svg"]
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_get_development_panel_config_defaults(config_manager: ConfigManager):
    """Sem development_panel no config, retorna defaults."""
    cfg = config_manager.get_development_panel_config()
    assert cfg["enabled"] is True
    assert cfg["github_enrichment"] is False
    assert cfg.get("default_org", "") == ""


def test_get_development_panel_config_with_section():
    """Com development_panel no config, retorna valores do arquivo."""
    config_with_dev = {
        "project": "TEST",
        "development_panel": {
            "enabled": False,
            "github_enrichment": True,
            "default_org": "minha-org",
        },
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_with_dev, f)
        temp_path = Path(f.name)
    try:
        manager = ConfigManager(config_path=temp_path)
        cfg = manager.get_development_panel_config()
        assert cfg["enabled"] is False
        assert cfg["github_enrichment"] is True
        assert cfg.get("default_org") == "minha-org"
        assert manager.development_panel_default_org() == "minha-org"
        assert manager.development_panel_enabled() is False
        assert manager.development_panel_github_enrichment() is True
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_save_development_panel_config():
    """save_development_panel_config persiste e recarrega."""
    config_base = {"project": "TEST"}
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_base, f)
        temp_path = Path(f.name)
    try:
        manager = ConfigManager(config_path=temp_path)
        manager.save_development_panel_config(
            {"enabled": False, "github_enrichment": True, "default_org": "my-org"}
        )
        assert manager.get_development_panel_config()["enabled"] is False
        assert manager.development_panel_github_enrichment() is True
        assert manager.get_development_panel_config().get("default_org") == "my-org"
        assert manager.development_panel_default_org() == "my-org"
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_get_google_oauth_config_defaults(config_manager: ConfigManager):
    """Sem google_oauth no config, retorna dict vazio."""
    cfg = config_manager.get_google_oauth_config()
    assert cfg.get("client_id", "") == ""
    assert cfg.get("project_id", "") == ""
    assert cfg.get("client_secret", "") == ""


def test_get_google_oauth_config_with_section():
    """Com google_oauth no config, retorna valores do arquivo."""
    config_with_goauth = {
        "project": "TEST",
        "google_oauth": {
            "client_id": "my-client-id",
            "project_id": "my-project",
            "client_secret": "my-secret",
        },
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_with_goauth, f)
        temp_path = Path(f.name)
    try:
        manager = ConfigManager(config_path=temp_path)
        cfg = manager.get_google_oauth_config()
        assert cfg["client_id"] == "my-client-id"
        assert cfg["project_id"] == "my-project"
        assert cfg["client_secret"] == "my-secret"
    finally:
        if temp_path.exists():
            temp_path.unlink()


def test_save_google_oauth_config():
    """save_google_oauth_config persiste e recarrega."""
    config_base = {"project": "TEST"}
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config_base, f)
        temp_path = Path(f.name)
    try:
        manager = ConfigManager(config_path=temp_path)
        manager.save_google_oauth_config("new-client-id", "new-project", "new-secret")
        cfg = manager.get_google_oauth_config()
        assert cfg["client_id"] == "new-client-id"
        assert cfg["project_id"] == "new-project"
        assert cfg["client_secret"] == "new-secret"
    finally:
        if temp_path.exists():
            temp_path.unlink()
