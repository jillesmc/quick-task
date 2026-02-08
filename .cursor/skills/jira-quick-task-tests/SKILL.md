---
name: jira-quick-task-tests
description: Writes or extends pytest tests for jira-quick-task using existing fixtures and Docker. Use when adding tests, fixing test failures, or when the user asks how to test Python code in this project.
---

# Testes no jira-quick-task

## Execução

- **Sempre** rodar testes no Docker: `make dev-test`. Não assumir PySide6 ou dependências no host.
- Testes vivem em `tests/`; config pytest em `pyproject.toml`.

## Fixtures (tests/conftest.py)

| Fixture | Uso |
|--------|-----|
| `sample_config` | Dict de configuração (project, issue_type, assignee, custom_fields, tipo_atividade_values, status_sequence, worklog_timezone). |
| `temp_config_file(sample_config)` | Arquivo JSON temporário; limpa após o teste. |
| `config_manager(temp_config_file)` | `ConfigManager` real com arquivo temporário. |
| `mock_jira_client` | `MagicMock(spec=JiraClient)` com `create_issue`, `transition_issue`, `register_worklog`; `create_issue` retorna dict com `issue_key`, `issue_url`. |
| `mock_config_manager(sample_config)` | `MagicMock(spec=ConfigManager)` com getters (get_project, get_issue_type, get_assignee, get_custom_field, get_tipo_atividade_values, get_status_sequence, get_timezone). |

Usar essas fixtures em vez de recriar mocks quando cobrirem o cenário.

## Padrão para testar serviço que usa Jira e Config

- Injetar `mock_jira_client` e `mock_config_manager` (ou `config_manager` se precisar de config real).
- Para criar issue: chamar o método do serviço e assertar `mock_jira_client.create_issue.call_count` e/ou `call_args` e payload `custom_fields` se relevante.

## Testes existentes

- `test_jira_client.py`, `test_jira_service.py`, `test_config_manager.py`, `test_issue_model.py`, `test_status_transition.py`, etc.
- Ver `test_jira_service.py` para uso de `mock_jira_client` e `mock_config_manager` em testes de criação de issue e worklog.

## Formato

- Arquivos: `test_*.py`. Classes: `Test*`. Funções: `test_*`.
- Formatar antes de commitar: `make dev-format`.
