"""
Testes unitários para core/jira_client.py
"""

import json
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import pytest

from core.jira_client import JiraClient, _UNKNOWN_ERROR_MSG


@pytest.fixture
def mock_config_file(tmp_path):
    """Cria um arquivo de configuração temporário"""
    config_file = tmp_path / ".jira-config.yml"
    config_file.write_text(
        "server: https://test.atlassian.net\n"
        "login: test@example.com\n"
        "token: test-token\n"
    )
    return config_file


@patch("core.jira_client.requests.request")
def test_get_current_user_success(mock_request, mock_config_file):
    """Testa obtenção de usuário atual via REST API"""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "accountId": "12345",
        "emailAddress": "test@example.com",
        "displayName": "Test User",
    }
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_current_user()

    assert result == "test@example.com"
    mock_request.assert_called_once()
    call_args = mock_request.call_args
    assert call_args[0][0] == "GET"
    assert "myself" in call_args[0][1]


@patch("core.jira_client.requests.request")
def test_get_current_user_fallback(mock_request, mock_config_file):
    """Testa fallback para email do config quando API falha"""
    mock_response = Mock()
    mock_response.status_code = 500
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_current_user()

    assert result == "test@example.com"  # Fallback para config


@patch("core.jira_client.requests.request")
def test_create_issue_success(mock_request, mock_config_file):
    """Testa criação de issue com sucesso usando REST API"""
    # Mock para GET myself (quando assignee é o usuário atual)
    myself_response = Mock()
    myself_response.status_code = 200
    myself_response.json.return_value = {
        "accountId": "test-account-id-123",
        "emailAddress": "test@example.com",
    }

    # Mock para POST issue (criação)
    create_response = Mock()
    create_response.status_code = 201
    create_response.json.return_value = {
        "key": "TEST-123",
        "self": "https://test.atlassian.net/rest/api/3/issue/TEST-123",
    }

    # Configurar side_effect para múltiplas chamadas
    mock_request.side_effect = [myself_response, create_response]

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.create_issue(
        project="TEST",
        issue_type="Task",
        summary="Test issue",
        description="Test description",
        assignee="test@example.com",
    )

    assert result["issue_key"] == "TEST-123"
    assert "TEST-123" in result["issue_url"]
    # Verificar que foram feitas 2 chamadas: GET myself + POST issue
    assert mock_request.call_count == 2
    # Verificar a última chamada (POST issue)
    call_args = mock_request.call_args_list[1]
    assert call_args[0][0] == "POST"
    assert "issue" in call_args[0][1]
    # Verificar estrutura fields no payload
    payload = call_args[1]["json"]
    assert "fields" in payload
    assert payload["fields"]["project"]["key"] == "TEST"
    assert payload["fields"]["issuetype"]["name"] == "Task"
    assert payload["fields"]["summary"] == "Test issue"
    # Verificar que assignee foi definido com accountId (formato correto para API v3)
    assert "assignee" in payload["fields"]
    assert payload["fields"]["assignee"]["accountId"] == "test-account-id-123"


@patch("core.jira_client.requests.request")
def test_create_issue_with_custom_fields(mock_request, mock_config_file):
    """Testa criação de issue com campos customizados"""
    # Mock para POST issue (criação sem assignee, então não precisa de GET myself)
    create_response = Mock()
    create_response.status_code = 201
    create_response.json.return_value = {
        "key": "TEST-123",
        "self": "https://test.atlassian.net/rest/api/3/issue/TEST-123",
    }
    mock_request.return_value = create_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.create_issue(
        project="TEST",
        issue_type="Task",
        summary="Test",
        description="Test",
        custom_fields={"customfield_123": "valor1", "customfield_456": "valor2"},
    )

    assert result["issue_key"] == "TEST-123"
    # Verificar que campos customizados estão em fields
    # CREATE agora também usa formato {"value": "text"} para consistência
    call_args = mock_request.call_args
    payload = call_args[1]["json"]
    assert payload["fields"]["customfield_123"] == {"value": "valor1"}
    assert payload["fields"]["customfield_456"] == {"value": "valor2"}


@patch("core.jira_client.requests.request")
def test_create_issue_with_parent(mock_request, mock_config_file):
    """Testa criação de issue com parent"""
    # Mock para POST issue (criação sem assignee, então não precisa de GET myself)
    create_response = Mock()
    create_response.status_code = 201
    create_response.json.return_value = {
        "key": "TEST-123",
        "self": "https://test.atlassian.net/rest/api/3/issue/TEST-123",
    }
    mock_request.return_value = create_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.create_issue(
        project="TEST",
        issue_type="Task",
        summary="Test",
        description="Test",
        parent_issue_key="EPIC-456",
    )

    assert result["issue_key"] == "TEST-123"
    # Verificar que parent está em fields
    call_args = mock_request.call_args
    payload = call_args[1]["json"]
    assert payload["fields"]["parent"]["key"] == "EPIC-456"


@patch("core.jira_client.requests.request")
def test_create_issue_with_priority(mock_request, mock_config_file):
    """Testa criação de issue com prioridade"""
    create_response = Mock()
    create_response.status_code = 201
    create_response.json.return_value = {
        "key": "TEST-123",
        "self": "https://test.atlassian.net/rest/api/3/issue/TEST-123",
    }
    mock_request.return_value = create_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.create_issue(
        project="TEST",
        issue_type="Task",
        summary="Test",
        description="Test",
        priority="High",
    )

    assert result["issue_key"] == "TEST-123"
    call_args = mock_request.call_args
    payload = call_args[1]["json"]
    assert payload["fields"]["priority"]["name"] == "High"


@patch("core.jira_client.requests.request")
def test_create_issue_error(mock_request, mock_config_file):
    """Testa erro ao criar issue"""
    mock_response = Mock()
    mock_response.status_code = 400
    mock_response.text = "Bad Request"
    mock_response.json.return_value = {"errorMessages": ["Invalid project"]}
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    with pytest.raises(RuntimeError, match="Erro na requisição"):
        client.create_issue(
            project="TEST",
            issue_type="Task",
            summary="Test",
            description="Test",
        )


@patch("core.jira_client.requests.request")
def test_transition_issue_success(mock_request, mock_config_file):
    """Testa transição de status com sucesso"""
    # Primeiro, mock da busca de transições
    transitions_response = Mock()
    transitions_response.status_code = 200
    transitions_response.json.return_value = {
        "transitions": [
            {"id": "11", "name": "To Do", "to": {"name": "To Do"}},
            {"id": "21", "name": "In Progress", "to": {"name": "In Progress"}},
            {"id": "31", "name": "Done", "to": {"name": "Done"}},
        ]
    }
    # Segundo, mock da transição
    transition_response = Mock()
    transition_response.status_code = 204

    mock_request.side_effect = [transitions_response, transition_response]

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.transition_issue("TEST-123", "In Progress")

    assert result is True
    assert mock_request.call_count == 2
    # Verificar que a segunda chamada foi para transitions
    transition_call = mock_request.call_args_list[1]
    assert transition_call[0][0] == "POST"
    assert "transitions" in transition_call[0][1]
    assert transition_call[1]["json"]["transition"]["id"] == "21"


@patch("core.jira_client.time.sleep")
@patch("core.jira_client.requests.request")
def test_transition_issue_retry(mock_request, mock_sleep, mock_config_file):
    """Testa retry em caso de falha"""
    transitions_response = Mock()
    transitions_response.status_code = 200
    transitions_response.json.return_value = {
        "transitions": [
            {"id": "21", "name": "In Progress", "to": {"name": "In Progress"}}
        ]
    }
    # Primeira tentativa falha, segunda sucede
    transition_response_fail = Mock()
    transition_response_fail.status_code = 500
    transition_response_fail.text = "Internal Server Error"
    transition_response_success = Mock()
    transition_response_success.status_code = 204

    # 1 GET para buscar transições + 2 POSTs (falha + sucesso)
    mock_request.side_effect = [
        transitions_response,  # GET transitions (uma vez no início)
        transition_response_fail,  # POST transition (primeira tentativa - falha)
        transition_response_success,  # POST transition (segunda tentativa - sucesso)
    ]

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.transition_issue("TEST-123", "In Progress", max_retries=3)

    assert result is True
    assert mock_request.call_count == 3  # 1 GET + 2 POSTs


@patch("core.jira_client.requests.request")
def test_transition_issue_not_found(mock_request, mock_config_file):
    """Testa quando transição não é encontrada"""
    transitions_response = Mock()
    transitions_response.status_code = 200
    transitions_response.json.return_value = {
        "transitions": [
            {"id": "21", "name": "In Progress", "to": {"name": "In Progress"}}
        ]
    }
    mock_request.return_value = transitions_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.transition_issue("TEST-123", "Non-existent Status")

    assert result is False


@patch("core.jira_client.requests.request")
def test_update_issue_success(mock_request, mock_config_file):
    """Testa atualização de issue com sucesso"""
    mock_response = Mock()
    mock_response.status_code = 204
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.update_issue(
        "TEST-123",
        summary="Updated summary",
        description="Updated description",
    )

    assert result is True
    mock_request.assert_called_once()
    call_args = mock_request.call_args
    assert call_args[0][0] == "PUT"
    assert "TEST-123" in call_args[0][1]
    payload = call_args[1]["json"]
    assert "fields" in payload
    assert payload["fields"]["summary"] == "Updated summary"


@patch("core.jira_client.requests.request")
def test_update_issue_with_custom_fields(mock_request, mock_config_file):
    """Testa atualização de issue com campos customizados"""
    mock_response = Mock()
    mock_response.status_code = 204
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.update_issue(
        "TEST-123",
        custom_fields={"customfield_123": "valor1"},
    )

    assert result is True
    call_args = mock_request.call_args
    payload = call_args[1]["json"]
    # UPDATE requer formato {"value": "text"} para campos select list
    assert payload["fields"]["customfield_123"] == {"value": "valor1"}


@patch("core.jira_client.requests.request")
def test_get_issue_details_success(mock_request, mock_config_file):
    """Testa obtenção de detalhes da issue"""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "key": "TEST-123",
        "id": "12345",
        "fields": {
            "summary": "Test issue",
            "description": {"type": "doc", "content": []},
            "status": {"name": "In Progress"},
        },
    }
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_issue_details("TEST-123")

    assert result is not None
    assert result["key"] == "TEST-123"
    assert result["summary"] == "Test issue"
    mock_request.assert_called_once()
    call_args = mock_request.call_args
    assert call_args[0][0] == "GET"
    assert "TEST-123" in call_args[0][1]
    assert "fields" in call_args[1]["params"]


@patch("core.jira_client.requests.request")
def test_get_issue_details_not_found(mock_request, mock_config_file):
    """Testa quando issue não é encontrada"""
    mock_response = Mock()
    mock_response.status_code = 404
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_issue_details("TEST-999")

    assert result is None


@patch("core.jira_client.requests.get")
def test_get_development_info_success(mock_get, mock_config_file):
    """get_development_info retorna branches e pullRequests (formato dev-status/latest)."""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.raise_for_status = Mock()
    mock_response.json.return_value = {
        "detail": [
            {
                "branches": [
                    {
                        "name": "feature/TEST-123",
                        "url": "https://github.com/owner/repo/tree/feature/TEST-123",
                        "repository": {"id": "1", "name": "owner/repo"},
                        "aheadCount": 2,
                        "behindCount": 0,
                        "lastCommit": {
                            "timestamp": 1700000000000,
                            "message": "Fix",
                            "author": {"name": "Dev"},
                        },
                    }
                ],
                "pullRequests": [
                    {
                        "id": "owner/repo/456",
                        "name": "Add feature",
                        "url": "https://github.com/owner/repo/pull/456",
                        "status": "OPEN",
                        "source": {"branch": "feature/TEST-123"},
                        "destination": {"branch": "main"},
                        "createdDate": 1700000000000,
                        "updatedDate": 1700000100000,
                        "author": {"name": "Dev"},
                    }
                ],
            }
        ]
    }
    mock_get.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_development_info("12345")

    assert result is not None
    assert "branches" in result
    assert "pullRequests" in result
    assert len(result["branches"]) == 1
    assert result["branches"][0]["name"] == "feature/TEST-123"
    assert result["branches"][0]["commitsAhead"] == 2
    assert result["branches"][0]["commitsBehind"] == 0
    assert len(result["pullRequests"]) == 1
    assert result["pullRequests"][0]["number"] == "456"
    assert result["pullRequests"][0]["state"] == "open"
    assert result["pullRequests"][0]["sourceBranch"] == "feature/TEST-123"
    assert "repositories" in result
    assert len(result["repositories"]) == 1
    assert result["repositories"][0]["name"] == "owner/repo"
    mock_get.assert_called_once()
    call_args = mock_get.call_args
    assert "issueId=12345" in str(call_args[1]["params"]) or "12345" in str(call_args)


@patch("core.jira_client.requests.get")
def test_get_development_info_returns_repositories_no_duplicates(
    mock_get, mock_config_file
):
    """repositories list has unique repo names when same repo appears in multiple details."""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.raise_for_status = Mock()
    mock_response.json.return_value = {
        "detail": [
            {
                "branches": [
                    {"name": "main", "repository": {"name": "org/a"}},
                    {"name": "feat", "repository": {"name": "org/b"}},
                ]
            },
            {
                "branches": [
                    {"name": "fix", "repository": {"name": "org/a"}},
                ]
            },
        ]
    }
    mock_get.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_development_info("123")

    assert "repositories" in result
    names = [r["name"] for r in result["repositories"]]
    assert names == ["org/a", "org/b"]


@patch("core.jira_client.requests.get")
def test_get_development_info_new_format_direct_branches(mock_get, mock_config_file):
    """dev-status/latest: detail[].branches direto (cada branch tem repository: {name})."""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.raise_for_status = Mock()
    mock_response.json.return_value = {
        "detail": [
            {
                "branches": [
                    {
                        "name": "PLATFORM-14840-feature",
                        "url": "https://github.com/org/repo/tree/PLATFORM-14840-feature",
                        "repository": {"id": "123", "name": "org/repo"},
                        "aheadCount": 1,
                        "behindCount": 0,
                    }
                ],
                "pullRequests": [
                    {
                        "id": "org/repo/99",
                        "name": "Add feature",
                        "url": "https://github.com/org/repo/pull/99",
                        "status": "OPEN",
                        "source": {"branch": "PLATFORM-14840-feature"},
                        "destination": {"branch": "main"},
                        "author": {"name": "Dev"},
                    }
                ],
            }
        ]
    }
    mock_get.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_development_info("1739865")

    assert len(result["branches"]) == 1
    assert result["branches"][0]["name"] == "PLATFORM-14840-feature"
    assert result["branches"][0]["repository"] == "org/repo"
    assert len(result["pullRequests"]) == 1
    assert result["pullRequests"][0]["number"] == "99"
    assert result["repositories"][0]["name"] == "org/repo"


@patch("core.jira_client.requests.get")
def test_get_development_info_404_returns_empty(mock_get, mock_config_file):
    """get_development_info retorna {} em 404/403."""
    mock_response = Mock()
    mock_response.status_code = 404
    mock_get.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_development_info("99999")

    assert result == {}


@patch("core.jira_client.requests.request")
def test_register_worklog_success(mock_request, mock_config_file):
    """Testa registro de worklog com sucesso"""
    mock_response = Mock()
    mock_response.status_code = 201
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.register_worklog("TEST-123", "1h 30m", "2024-01-01 10:00:00", "UTC")

    assert result is True
    mock_request.assert_called_once()
    call_args = mock_request.call_args
    assert call_args[0][0] == "POST"
    assert "worklog" in call_args[0][1]
    payload = call_args[1]["json"]
    # REST API v3 requer apenas timeSpentSeconds (não timeSpent)
    assert "timeSpentSeconds" in payload
    assert payload["timeSpentSeconds"] == 5400  # 1h 30m = 5400 segundos
    assert "started" in payload


@patch("core.jira_client.requests.request")
def test_register_worklog_with_comment(mock_request, mock_config_file):
    """Testa registro de worklog com comentário"""
    mock_response = Mock()
    mock_response.status_code = 201
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.register_worklog(
        "TEST-123", "1h", "2024-01-01 10:00:00", "UTC", comment="Trabalho realizado"
    )

    assert result is True
    call_args = mock_request.call_args
    payload = call_args[1]["json"]
    assert "comment" in payload
    assert payload["comment"]["type"] == "doc"


@patch("core.jira_client.requests.request")
def test_search_issues_success(mock_request, mock_config_file):
    """Testa busca de issues com sucesso"""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "issues": [
            {"key": "TEST-1", "fields": {"summary": "Issue 1"}},
            {"key": "TEST-2", "fields": {"summary": "Issue 2"}},
        ],
        "nextPageToken": None,
    }
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    results = client.search_issues("project = TEST", max_results=50)

    assert len(results) == 2
    assert results[0]["key"] == "TEST-1"
    mock_request.assert_called_once()
    call_args = mock_request.call_args
    assert call_args[0][0] == "POST"
    assert "search/jql" in call_args[0][1]
    payload = call_args[1]["json"]
    assert payload["jql"] == "project = TEST"


def test_extract_issue_key():
    """Testa extração de chave da issue do output (método estático legado)"""
    output = "Issue PLATFORM-12345 created successfully"
    assert JiraClient._extract_issue_key(output) == "PLATFORM-12345"

    output2 = "Created TEST-999"
    assert JiraClient._extract_issue_key(output2) == "TEST-999"

    output3 = "No issue key here"
    assert JiraClient._extract_issue_key(output3) == ""


def test_extract_issue_url():
    """Testa extração de URL da issue do output (método estático legado)"""
    output = "Issue created: https://jira.example.com/browse/TEST-123"
    assert (
        JiraClient._extract_issue_url(output)
        == "https://jira.example.com/browse/TEST-123"
    )

    output2 = "URL: https://example.com/jira/TEST-456"
    assert JiraClient._extract_issue_url(output2) == "https://example.com/jira/TEST-456"

    output3 = "No URL here"
    assert JiraClient._extract_issue_url(output3) == ""


def test_format_duration_minutes_under_hour():
    """Testa formatação de minutos < 60"""
    assert JiraClient._format_duration_minutes(30) == "30m"
    assert JiraClient._format_duration_minutes(45) == "45m"
    assert JiraClient._format_duration_minutes(0) == "0m"


def test_format_duration_minutes_exact_hours():
    """Testa formatação de horas exatas"""
    assert JiraClient._format_duration_minutes(60) == "1h"
    assert JiraClient._format_duration_minutes(120) == "2h"
    assert JiraClient._format_duration_minutes(180) == "3h"


def test_format_duration_minutes_hours_and_minutes():
    """Testa formatação de horas e minutos"""
    assert JiraClient._format_duration_minutes(90) == "1h 30m"
    assert JiraClient._format_duration_minutes(150) == "2h 30m"
    assert JiraClient._format_duration_minutes(75) == "1h 15m"


# --- _adf_to_markdown ---


def test_adf_to_markdown_two_paragraphs():
    """ADF com dois paragraph → markdown com \\n\\n entre os dois."""
    adf = {
        "type": "doc",
        "content": [
            {"type": "paragraph", "content": [{"type": "text", "text": "First"}]},
            {"type": "paragraph", "content": [{"type": "text", "text": "Second"}]},
        ],
    }
    result = JiraClient._adf_to_markdown(adf)
    assert "First" in result and "Second" in result
    assert "\n\n" in result


def test_adf_to_markdown_heading_level_1():
    """ADF com heading level 1 → linha começando com '# '."""
    adf = {
        "type": "heading",
        "attrs": {"level": 1},
        "content": [{"type": "text", "text": "Title"}],
    }
    result = JiraClient._adf_to_markdown(adf)
    assert result.startswith("# ")
    assert "Title" in result


def test_adf_to_markdown_bullet_list():
    """ADF com bulletList de dois itens → duas linhas começando com '- '."""
    adf = {
        "type": "bulletList",
        "content": [
            {
                "type": "listItem",
                "content": [
                    {"type": "paragraph", "content": [{"type": "text", "text": "One"}]}
                ],
            },
            {
                "type": "listItem",
                "content": [
                    {"type": "paragraph", "content": [{"type": "text", "text": "Two"}]}
                ],
            },
        ],
    }
    result = JiraClient._adf_to_markdown(adf)
    lines = [line for line in result.strip().split("\n") if line]
    assert len(lines) >= 2
    assert lines[0].startswith("- ")
    assert lines[1].startswith("- ")
    assert "One" in result and "Two" in result


def test_adf_to_markdown_ordered_list():
    """ADF com orderedList de dois itens → '1. ...' e '2. ...'."""
    adf = {
        "type": "orderedList",
        "content": [
            {
                "type": "listItem",
                "content": [
                    {"type": "paragraph", "content": [{"type": "text", "text": "A"}]}
                ],
            },
            {
                "type": "listItem",
                "content": [
                    {"type": "paragraph", "content": [{"type": "text", "text": "B"}]}
                ],
            },
        ],
    }
    result = JiraClient._adf_to_markdown(adf)
    assert "1. " in result and "2. " in result
    assert "A" in result and "B" in result


def test_adf_to_markdown_code_block():
    """ADF com codeBlock → bloco entre ```."""
    adf = {
        "type": "codeBlock",
        "attrs": {"language": "py"},
        "content": [{"type": "text", "text": "print(1)"}],
    }
    result = JiraClient._adf_to_markdown(adf)
    assert result.startswith("```py\n")
    assert "print(1)" in result
    assert "```" in result


def test_adf_to_markdown_rule():
    """ADF com rule → '---\\n' (uma quebra; doc junta com \\n\\n)."""
    adf = {"type": "rule"}
    result = JiraClient._adf_to_markdown(adf)
    assert result == "---\n"


def test_adf_to_markdown_text_strong():
    """Nó text com mark strong → '**text**'."""
    adf = {"type": "text", "text": "bold", "marks": [{"type": "strong"}]}
    result = JiraClient._adf_to_markdown(adf)
    assert result == "**bold**"


def test_adf_to_markdown_non_dict_input():
    """Entrada não-dict (string, None) → retorno seguro."""
    assert JiraClient._adf_to_markdown(None) == ""
    assert JiraClient._adf_to_markdown("hello") == "hello"


def test_adf_to_markdown_doc_empty_content():
    """doc com content vazio → string vazia (após strip)."""
    adf = {"type": "doc", "content": []}
    result = JiraClient._adf_to_markdown(adf)
    assert result.strip() == ""


def test_adf_to_markdown_media_single():
    """mediaSingle com media node → ![alt](/rest/api/3/attachment/content/{id})."""
    adf = {
        "type": "mediaSingle",
        "attrs": {"layout": "center"},
        "content": [
            {
                "type": "media",
                "attrs": {
                    "id": "12345",
                    "type": "file",
                    "collection": "contentId-1",
                    "alt": "screenshot.png",
                    "width": 400,
                    "height": 300,
                },
            }
        ],
    }
    result = JiraClient._adf_to_markdown(adf)
    assert "![screenshot.png](/rest/api/3/attachment/content/12345)" in result


def test_adf_to_markdown_media_single_with_width():
    """mediaSingle com attrs.width → ![alt](url){: width=\"250\" }."""
    adf = {
        "type": "mediaSingle",
        "attrs": {"layout": "center", "width": 250, "widthType": "pixel"},
        "content": [
            {
                "type": "media",
                "attrs": {
                    "id": "12345",
                    "alt": "screenshot.png",
                },
            }
        ],
    }
    result = JiraClient._adf_to_markdown(adf)
    assert "![screenshot.png](/rest/api/3/attachment/content/12345)" in result
    assert '{: width="250" }' in result


def test_adf_to_markdown_media_node():
    """media node direto → ![alt](/rest/api/3/attachment/content/{id})."""
    adf = {
        "type": "media",
        "attrs": {"id": "999", "alt": "image", "width": 100, "height": 100},
    }
    result = JiraClient._adf_to_markdown(adf)
    assert "![image](/rest/api/3/attachment/content/999)" in result


# --- get_issue_comments, add_comment, update_comment, delete_comment ---


@patch("core.jira_client.requests.request")
def test_get_issue_comments_success(mock_request, mock_config_file):
    """get_issue_comments retorna lista normalizada com body em markdown."""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "comments": [
            {
                "id": "10000",
                "author": {
                    "accountId": "user-1",
                    "displayName": "João",
                },
                "body": {
                    "type": "doc",
                    "content": [
                        {
                            "type": "paragraph",
                            "content": [{"type": "text", "text": "Comentário teste"}],
                        }
                    ],
                },
                "created": "2025-01-20T10:30:00.000+0000",
                "updated": "2025-01-20T10:30:00.000+0000",
            }
        ],
        "total": 1,
        "startAt": 0,
        "maxResults": 50,
    }
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    comments, total = client.get_issue_comments("TEST-123")

    assert total == 1
    assert len(comments) == 1
    assert comments[0]["id"] == "10000"
    assert comments[0]["author"]["accountId"] == "user-1"
    assert comments[0]["author"]["displayName"] == "João"
    assert "Comentário teste" in comments[0]["body"]
    assert comments[0]["created"] == "2025-01-20T10:30:00.000+0000"
    mock_request.assert_called_once()
    call_args = mock_request.call_args
    assert call_args[0][0] == "GET"
    assert "TEST-123" in call_args[0][1]
    assert "comment" in call_args[0][1]


@patch("core.jira_client.requests.request")
def test_get_issue_comments_empty(mock_request, mock_config_file):
    """get_issue_comments retorna lista vazia quando não há comentários."""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "comments": [],
        "total": 0,
        "startAt": 0,
        "maxResults": 50,
    }
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    comments, total = client.get_issue_comments("TEST-123")

    assert comments == []
    assert total == 0


@patch("core.jira_client.requests.request")
def test_get_latest_issue_comment_empty(mock_request, mock_config_file):
    """get_latest_issue_comment retorna (None, 0) quando não há comentários."""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "comments": [],
        "total": 0,
        "startAt": 0,
        "maxResults": 1,
    }
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    comment, total = client.get_latest_issue_comment("TEST-123")

    assert comment is None
    assert total == 0
    assert mock_request.call_count == 1


@patch("core.jira_client.requests.request")
def test_get_latest_issue_comment_one(mock_request, mock_config_file):
    """get_latest_issue_comment com um comentário retorna esse comentário e total=1."""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "comments": [
            {
                "id": "10000",
                "author": {"accountId": "u1", "displayName": "User"},
                "body": {"type": "doc", "content": []},
                "created": "2025-01-20T10:00:00.000+0000",
                "updated": "2025-01-20T10:00:00.000+0000",
            }
        ],
        "total": 1,
        "startAt": 0,
        "maxResults": 1,
    }
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    comment, total = client.get_latest_issue_comment("TEST-123")

    assert comment is not None
    assert comment["id"] == "10000"
    assert total == 1
    assert mock_request.call_count == 1


@patch("core.jira_client.requests.request")
def test_get_latest_issue_comment_multiple(mock_request, mock_config_file):
    """get_latest_issue_comment com vários comentários faz 2 requests e retorna o último."""
    first_resp = Mock(status_code=200)
    first_resp.json.return_value = {
        "comments": [
            {"id": "1", "author": {}, "body": {}, "created": "", "updated": ""}
        ],
        "total": 3,
        "startAt": 0,
        "maxResults": 1,
    }
    last_resp = Mock(status_code=200)
    last_resp.json.return_value = {
        "comments": [
            {
                "id": "3",
                "author": {"accountId": "u3", "displayName": "Last"},
                "body": {"type": "doc", "content": []},
                "created": "2025-01-20T12:00:00.000+0000",
                "updated": "2025-01-20T12:00:00.000+0000",
            }
        ],
        "total": 3,
        "startAt": 2,
        "maxResults": 1,
    }
    mock_request.side_effect = [first_resp, last_resp]

    client = JiraClient(jira_cli_config_path=mock_config_file)
    comment, total = client.get_latest_issue_comment("TEST-123")

    assert comment is not None
    assert comment["id"] == "3"
    assert comment["author"]["displayName"] == "Last"
    assert total == 3
    assert mock_request.call_count == 2


@patch("core.jira_client.requests.request")
def test_add_comment_success(mock_request, mock_config_file):
    """add_comment envia body em ADF e retorna comentário normalizado."""
    mock_response = Mock()
    mock_response.status_code = 201
    mock_response.json.return_value = {
        "id": "10001",
        "author": {"accountId": "me", "displayName": "Eu"},
        "body": {
            "type": "doc",
            "content": [
                {
                    "type": "paragraph",
                    "content": [{"type": "text", "text": "Novo comentário"}],
                }
            ],
        },
        "created": "2025-01-21T09:00:00.000+0000",
        "updated": "2025-01-21T09:00:00.000+0000",
    }
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.add_comment("TEST-123", "Novo comentário")

    assert result is not None
    assert result["id"] == "10001"
    assert "Novo comentário" in result["body"]
    call_args = mock_request.call_args
    assert call_args[0][0] == "POST"
    payload = call_args[1]["json"]
    assert "body" in payload
    assert payload["body"].get("type") == "doc"


@patch("core.jira_client.requests.request")
def test_update_comment_success(mock_request, mock_config_file):
    """update_comment envia body em ADF e retorna comentário atualizado."""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "id": "10000",
        "author": {"accountId": "user-1", "displayName": "João"},
        "body": {
            "type": "doc",
            "content": [
                {
                    "type": "paragraph",
                    "content": [{"type": "text", "text": "Texto editado"}],
                }
            ],
        },
        "created": "2025-01-20T10:30:00.000+0000",
        "updated": "2025-01-21T11:00:00.000+0000",
    }
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.update_comment("TEST-123", "10000", "Texto editado")

    assert result is not None
    assert result["id"] == "10000"
    assert "Texto editado" in result["body"]
    call_args = mock_request.call_args
    assert call_args[0][0] == "PUT"
    assert "10000" in call_args[0][1]


@patch("core.jira_client.requests.request")
def test_delete_comment_success(mock_request, mock_config_file):
    """delete_comment retorna True em 204."""
    mock_response = Mock()
    mock_response.status_code = 204
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.delete_comment("TEST-123", "10000")

    assert result is True
    call_args = mock_request.call_args
    assert call_args[0][0] == "DELETE"
    assert "10000" in call_args[0][1]


# --- Attachment API ---


@patch("core.jira_client.requests.request")
def test_get_attachment_settings_success(mock_request, mock_config_file):
    """get_attachment_settings retorna enabled e uploadLimit."""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {"enabled": True, "uploadLimit": 10485760}
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_attachment_settings()

    assert result["enabled"] is True
    assert result["uploadLimit"] == 10485760
    call_args = mock_request.call_args
    assert call_args[0][0] == "GET"
    assert "attachment/meta" in call_args[0][1]


@patch("core.jira_client.requests.request")
def test_delete_attachment_success(mock_request, mock_config_file):
    """delete_attachment retorna True quando a API retorna 204 No Content."""
    mock_response = Mock()
    mock_response.status_code = 204
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.delete_attachment("1982426")

    assert result is True
    mock_request.assert_called_once()
    call_args = mock_request.call_args
    assert call_args[0][0] == "DELETE"
    assert "attachment/1982426" in call_args[0][1]


@patch("core.jira_client.requests.request")
def test_delete_attachment_not_found(mock_request, mock_config_file):
    """delete_attachment retorna False quando a API retorna 404."""
    mock_response = Mock()
    mock_response.status_code = 404
    mock_response.text = "Not Found"
    mock_response.json.return_value = {"errorMessages": ["Attachment not found"]}
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.delete_attachment("999999")

    assert result is False
    mock_request.assert_called_once()


def test_delete_attachment_empty_id_returns_false(mock_config_file):
    """delete_attachment retorna False quando attachment_id é vazio."""
    client = JiraClient(jira_cli_config_path=mock_config_file)
    assert client.delete_attachment("") is False
    assert client.delete_attachment(None) is False


@patch("core.jira_client.requests.post")
def test_add_attachment_success(mock_post, mock_config_file, tmp_path):
    """add_attachment envia multipart e retorna lista de anexos."""
    f = tmp_path / "test.txt"
    f.write_text("hello")
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = [
        {
            "id": "10001",
            "filename": "test.txt",
            "content": "https://test.atlassian.net/rest/api/3/attachment/content/10001",
            "mimeType": "text/plain",
            "size": 5,
        }
    ]
    mock_post.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.add_attachment("TEST-123", str(f))

    assert len(result) == 1
    assert result[0]["id"] == "10001"
    assert result[0]["filename"] == "test.txt"
    assert "attachment/content/10001" in result[0]["content"]
    call_args = mock_post.call_args
    assert call_args[1]["headers"].get("X-Atlassian-Token") == "no-check"
    assert "file" in call_args[1]["files"]


@patch("core.jira_client.requests.post")
def test_add_attachment_413(mock_post, mock_config_file, tmp_path):
    """add_attachment levanta RuntimeError em 413."""
    f = tmp_path / "big.bin"
    f.write_bytes(b"x" * 100)
    mock_response = Mock()
    mock_response.status_code = 413
    mock_response.text = "Request Entity Too Large"
    mock_response.json.side_effect = ValueError("not json")
    mock_post.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    with pytest.raises(RuntimeError) as exc_info:
        client.add_attachment("TEST-123", str(f))
    assert "413" in str(exc_info.value) or "muito grande" in str(exc_info.value).lower()


@patch("core.jira_client.requests.post")
def test_add_attachment_from_bytes_success(mock_post, mock_config_file):
    """add_attachment_from_bytes envia bytes e retorna lista de anexos."""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = [
        {
            "id": "10002",
            "filename": "paste.png",
            "content": "https://test.atlassian.net/rest/api/3/attachment/content/10002",
            "mimeType": "image/png",
            "size": 1024,
        }
    ]
    mock_post.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.add_attachment_from_bytes(
        "TEST-123", b"\x89PNG\r\n\x1a\n", "paste.png"
    )

    assert len(result) == 1
    assert result[0]["filename"] == "paste.png"
    assert "attachment/content/10002" in result[0]["content"]


@patch("core.jira_client.requests.request")
def test_get_issue_worklogs_success(mock_request, mock_config_file):
    """Testa obtenção de worklogs de uma issue."""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "worklogs": [
            {
                "id": "10001",
                "author": {
                    "accountId": "acc-1",
                    "displayName": "Test User",
                    "emailAddress": "test@example.com",
                },
                "timeSpentSeconds": 3600,
                "started": "2025-01-20T09:00:00.000-0300",
                "comment": "Work done",
            },
            {
                "id": "10002",
                "author": {
                    "accountId": "acc-1",
                    "displayName": "Test User",
                    "emailAddress": "test@example.com",
                },
                "timeSpentSeconds": 1800,
                "started": "2025-01-20T14:00:00.000-0300",
                "comment": None,
            },
        ],
        "total": 2,
    }
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_issue_worklogs("TEST-123")

    assert len(result) == 2
    assert result[0]["id"] == "10001"
    assert result[0]["timeSpentSeconds"] == 3600
    assert result[0]["comment"] == "Work done"
    assert result[0]["author"]["emailAddress"] == "test@example.com"
    assert result[1]["id"] == "10002"
    assert result[1]["timeSpentSeconds"] == 1800
    assert result[1]["comment"] == ""
    mock_request.assert_called_once()
    call_args = mock_request.call_args
    assert call_args[0][0] == "GET"
    assert "issue/TEST-123/worklog" in call_args[0][1]


@patch("core.jira_client.requests.request")
def test_get_issue_worklogs_empty_issue_key(mock_request, mock_config_file):
    """Testa que issue_key vazia retorna lista vazia."""
    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_issue_worklogs("")
    assert result == []
    mock_request.assert_not_called()


@patch("core.jira_client.requests.request")
def test_search_issues_with_worklogs_in_period(mock_request, mock_config_file):
    """Testa busca de issues com worklogs no período."""
    from datetime import date

    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "issues": [
            {
                "key": "TEST-1",
                "fields": {
                    "summary": "Issue 1",
                    "status": {"name": "Done"},
                    "issuetype": {"name": "Task"},
                },
            }
        ],
        "total": 1,
    }
    mock_request.return_value = mock_response

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.search_issues_with_worklogs_in_period(
        start_date=date(2025, 1, 1),
        end_date=date(2025, 1, 31),
        user_email="test@example.com",
        max_results=100,
    )

    assert len(result) == 1
    assert result[0]["key"] == "TEST-1"
    mock_request.assert_called_once()
    call_args = mock_request.call_args
    assert call_args[0][0] == "POST"
    assert "search/jql" in call_args[0][1]
    jql = call_args[1]["json"].get("jql", "")
    assert "worklogAuthor" in jql
    assert "test@example.com" in jql
    assert "2025-01-01" in jql
    assert "2025-01-31" in jql


# --- Discovery (metadata) ---


@patch("core.jira_client.requests.request")
def test_get_projects_success(mock_request, mock_config_file):
    """get_projects retorna lista de JiraProject parseados."""
    mock_request.return_value.status_code = 200
    mock_request.return_value.json.return_value = [
        {
            "id": "10001",
            "key": "QTASK",
            "name": "Quick Task",
            "projectTypeKey": "software",
            "avatarUrls": {"48x48": "https://a.png"},
            "description": "Desc",
            "lead": {"displayName": "Lead"},
        }
    ]
    from core.jira_metadata import JiraProject

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_projects()
    assert len(result) == 1
    assert isinstance(result[0], JiraProject)
    assert result[0].key == "QTASK"
    assert result[0].name == "Quick Task"
    assert result[0].lead == "Lead"
    call_args = mock_request.call_args
    assert call_args[0][0] == "GET"
    assert "project" in call_args[0][1].lower() or call_args[1]["params"]


@patch("core.jira_client.requests.request")
def test_get_project_issue_types_success(mock_request, mock_config_file):
    """get_project_issue_types retorna lista de JiraIssueType."""
    mock_request.return_value.status_code = 200
    mock_request.return_value.json.return_value = [
        {"id": "1", "name": "Task", "subtask": False, "hierarchyLevel": 0},
    ]
    from core.jira_metadata import JiraIssueType

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_project_issue_types("10001")
    assert len(result) == 1
    assert isinstance(result[0], JiraIssueType)
    assert result[0].name == "Task"
    assert (
        "issuetype" in mock_request.call_args[0][1].lower()
        or "project" in mock_request.call_args[0][1].lower()
    )


@patch("core.jira_client.requests.request")
def test_get_issue_createmeta_success(mock_request, mock_config_file):
    """get_issue_createmeta retorna dict com projects/issuetypes/fields."""
    mock_request.return_value.status_code = 200
    mock_request.return_value.json.return_value = {
        "projects": [
            {
                "key": "X",
                "issuetypes": [
                    {
                        "id": "1",
                        "name": "Task",
                        "fields": {
                            "summary": {
                                "name": "Summary",
                                "required": True,
                                "schema": {"type": "string"},
                            }
                        },
                    },
                ],
            }
        ]
    }
    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_issue_createmeta(project_keys="X", issuetype_ids="1")
    assert "projects" in result
    assert len(result["projects"]) == 1
    assert "issuetypes" in result["projects"][0]
    assert len(result["projects"][0]["issuetypes"]) == 1
    assert "summary" in result["projects"][0]["issuetypes"][0]["fields"]


@patch("core.jira_client.requests.request")
def test_get_createmeta_fields_for_issue_type_returns_parsed_list(
    mock_request, mock_config_file
):
    """get_createmeta_fields_for_issue_type retorna List[JiraFieldMetadata]."""
    mock_request.return_value.status_code = 200
    mock_request.return_value.json.return_value = {
        "projects": [
            {
                "key": "X",
                "issuetypes": [
                    {
                        "id": "1",
                        "fields": {
                            "summary": {
                                "fieldId": "summary",
                                "name": "Summary",
                                "required": True,
                                "schema": {"type": "string"},
                            },
                        },
                    },
                ],
            }
        ]
    }
    from core.jira_metadata import JiraFieldMetadata

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_createmeta_fields_for_issue_type(
        project_key="X", issuetype_id="1"
    )
    assert len(result) == 1
    assert isinstance(result[0], JiraFieldMetadata)
    assert result[0].key == "summary"
    assert result[0].required is True


@patch("core.jira_client.requests.request")
def test_get_fields_success(mock_request, mock_config_file):
    """get_fields retorna lista de JiraFieldMetadata."""
    mock_request.return_value.status_code = 200
    mock_request.return_value.json.return_value = [
        {
            "id": "summary",
            "name": "Summary",
            "key": "summary",
            "custom": False,
            "schema": {"type": "string"},
        },
    ]
    from core.jira_metadata import JiraFieldMetadata

    client = JiraClient(jira_cli_config_path=mock_config_file)
    result = client.get_fields()
    assert len(result) == 1
    assert isinstance(result[0], JiraFieldMetadata)
    assert result[0].id == "summary"
