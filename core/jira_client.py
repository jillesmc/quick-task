"""
Cliente Jira - Wrapper para REST API v3 do Jira
"""

import json
import mimetypes
import os
import re
import sys
import time
from datetime import date
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, TYPE_CHECKING
import requests
from requests.auth import HTTPBasicAuth

from core import jira_metadata as _jira_meta

if TYPE_CHECKING:
    from config.config_manager import ConfigManager

# Constante para mensagem de erro padrão
_UNKNOWN_ERROR_MSG = "Erro desconhecido"

# Regex para detectar imagens/links com URL de attachment Jira (! ou [ sem !)
_RE_ATTACHMENT_URL_DETECT = re.compile(
    r"[!\[][^\]]*\]\([^)]*?/attachment/content/\d+[^)]*\)"
)
_RE_ATTACHMENT_URL_EXTRACT = re.compile(
    r"!\[[^\]]*\]\([^)]*?/attachment/content/(\d+)[^)]*\)"
)
# Regex para attr_list {: width="N" } após imagem
_RE_ATTR_WIDTH = re.compile(r"\s*\{:\s*width=[\"']?(\d+)[\"']?\s*\}")


class JiraClient:
    """Cliente para interagir com Jira via REST API v3"""

    def __init__(
        self,
        jira_cli_config_path: Optional[Path] = None,
        account_id: Optional[str] = None,
        config_manager: Optional["ConfigManager"] = None,
    ):
        """
        Inicializa o cliente Jira

        Args:
            jira_cli_config_path: Caminho para o arquivo de configuração .jira-config.yml.
                                 Usado para obter server URL e email para autenticação REST API.
            account_id: accountId do usuário atual (opcional, obtido do config.json).
                       Se fornecido, será usado quando o assignee for o usuário atual.
            config_manager: ConfigManager para verificar attachments.embed.enabled.
                           Se None, embed de mídia na descrição fica desabilitado.
        """
        self._jira_cli_config_path = jira_cli_config_path
        self._server_url = None
        self._auth_email = None
        self._api_token = (
            None  # Token do .jira-config.yml (não mais de variável de ambiente)
        )
        self._account_id = account_id  # accountId do usuário atual (do config.json)
        self._config_manager = config_manager
        self._load_config_for_rest_api()

        # Validar que temos o necessário para REST API
        if not self._server_url:
            raise RuntimeError(
                "URL do servidor Jira não encontrada. Configure o arquivo .jira-config.yml com 'server'."
            )
        if not self._auth_email:
            raise RuntimeError(
                "Email não encontrado na configuração. Configure o arquivo .jira-config.yml com 'login'."
            )

    def _load_config_for_rest_api(self) -> None:
        """
        Carrega configuração do .jira-config.yml para uso com REST API.
        Obtém server URL, email e token para autenticação HTTPBasicAuth.
        """
        if not self._jira_cli_config_path or not self._jira_cli_config_path.exists():
            return

        try:
            import yaml

            with open(self._jira_cli_config_path, "r", encoding="utf-8") as f:
                config = yaml.safe_load(f) or {}
                server = config.get("server") or ""
                self._server_url = server.rstrip("/") if server else ""
                self._auth_email = config.get("login") or ""
                # Armazenar token do arquivo (não mais de variável de ambiente)
                self._api_token = config.get("token") or ""
        except Exception as e:
            # Não é crítico aqui - será validado no __init__
            # Usar debug_log para não alarmar na primeira inicialização
            try:
                from src.utils.debug import debug_log

                debug_log(
                    "JiraClient",
                    "_load_config_for_rest_api",
                    "Erro ao carregar .jira-config.yml: %s (normal na primeira inicialização)",
                    e,
                )
            except ImportError:
                # Se debug não estiver disponível, não fazer nada (silencioso)
                pass

    def _get_auth(self) -> HTTPBasicAuth:
        """
        Retorna objeto de autenticação HTTPBasicAuth para REST API

        Returns:
            HTTPBasicAuth com email e token

        Raises:
            RuntimeError: Se token ou email não estiverem configurados no .jira-config.yml
        """
        if not self._api_token:
            raise RuntimeError(
                "Token de API não encontrado no arquivo de configuração (.jira-config.yml). "
                "Configure o campo 'token' na tela de configuração da aplicação."
            )
        if not self._auth_email:
            raise RuntimeError(
                "Email não encontrado na configuração (.jira-config.yml). "
                "Configure o campo 'login' na tela de configuração da aplicação."
            )
        return HTTPBasicAuth(self._auth_email, self._api_token)

    def _make_request(
        self,
        method: str,
        endpoint: str,
        json_data: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
        timeout: int = 30,
    ) -> requests.Response:
        """
        Faz requisição HTTP para REST API do Jira

        Args:
            method: Método HTTP (GET, POST, PUT, DELETE)
            endpoint: Endpoint da API (ex: "issue", "issue/PROJECT-123", "myself")
            json_data: Dados JSON para enviar no body (opcional)
            params: Parâmetros de query string (opcional)
            timeout: Timeout em segundos

        Returns:
            Response object da requisição

        Raises:
            RuntimeError: Se a requisição falhar (status >= 400) ou houver erro de rede
        """
        if not self._server_url:
            raise RuntimeError("URL do servidor Jira não configurada")

        url = f"{self._server_url}/rest/api/3/{endpoint}"
        auth = self._get_auth()
        headers = {"Accept": "application/json", "Content-Type": "application/json"}

        # Importar debug_log aqui para evitar dependência circular
        from src.utils.debug import debug_log

        debug_log("JiraClient", "_make_request", "%s %s", method, url)
        if json_data:
            debug_log(
                "JiraClient", "_make_request", "JSON keys: %s", list(json_data.keys())
            )
        if params:
            debug_log("JiraClient", "_make_request", "Params: %s", params)

        try:
            response = requests.request(
                method,
                url,
                json=json_data,
                params=params,
                auth=auth,
                headers=headers,
                timeout=timeout,
            )

            from src.utils.debug import debug_log

            debug_log(
                "JiraClient",
                "_make_request",
                "Response status=%d",
                response.status_code,
            )

            if response.status_code >= 400:
                error_msg = response.text or f"HTTP {response.status_code}"
                # Tentar extrair mensagem de erro do JSON se disponível
                try:
                    error_json = response.json()
                    if "errorMessages" in error_json:
                        error_msg = "; ".join(error_json["errorMessages"])
                    elif "errors" in error_json:
                        # errors é um dict, formatar melhor
                        errors_dict = error_json["errors"]
                        if errors_dict:
                            error_parts = []
                            for key, value in errors_dict.items():
                                error_parts.append(f"{key}: {value}")
                            error_msg = (
                                "; ".join(error_parts)
                                if error_parts
                                else str(errors_dict)
                            )
                        else:
                            error_msg = str(errors_dict)
                    # Log completo do erro e payload para debug
                    from src.utils.debug import debug_log

                    debug_log(
                        "JiraClient",
                        "_make_request",
                        "Erro completo: %s",
                        json.dumps(error_json, indent=2),
                    )
                    if json_data:
                        debug_log(
                            "JiraClient",
                            "_make_request",
                            "Payload que causou erro: %s",
                            json.dumps(json_data, indent=2),
                        )
                except (json.JSONDecodeError, KeyError):
                    # Se não conseguir parsear JSON, mostrar texto completo
                    from src.utils.debug import debug_log

                    debug_log(
                        "JiraClient",
                        "_make_request",
                        "Response text completo: %s",
                        response.text,
                    )

                raise RuntimeError(
                    f"Erro na requisição {method} {endpoint} (HTTP {response.status_code}): {error_msg}"
                )

            return response

        except requests.exceptions.Timeout as e:
            raise RuntimeError(
                f"Timeout ao fazer requisição {method} {endpoint} após {timeout}s"
            ) from e
        except requests.exceptions.RequestException as e:
            raise RuntimeError(
                f"Erro de rede ao fazer requisição {method} {endpoint}: {str(e)}"
            ) from e

    def _request_raw(
        self,
        method: str,
        url: str,
        json_data: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
        timeout: int = 30,
    ) -> requests.Response:
        """
        Faz requisição HTTP para uma URL absoluta (mesmo auth que REST API).
        Usado para servicedeskapi e api.atlassian.com.
        """
        auth = self._get_auth()
        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        response = requests.request(
            method,
            url,
            json=json_data,
            params=params,
            auth=auth,
            headers=headers,
            timeout=timeout,
        )
        if response.status_code >= 400:
            error_msg = response.text or f"HTTP {response.status_code}"
            try:
                err_json = response.json()
                if "errorMessages" in err_json:
                    error_msg = "; ".join(err_json["errorMessages"])
                elif "errors" in err_json and err_json["errors"]:
                    error_msg = "; ".join(
                        f"{k}: {v}" for k, v in err_json["errors"].items()
                    )
            except (json.JSONDecodeError, TypeError):
                pass
            raise RuntimeError(
                f"Erro na requisição {method} {url} (HTTP {response.status_code}): {error_msg}"
            )
        return response

    def fetch_attachment_as_bytes(self, url: str) -> Optional[bytes]:
        """
        Faz GET autenticado na URL de attachment Jira e retorna os bytes.

        URLs de attachment Jira (ex: .../rest/api/3/attachment/content/12345)
        exigem autenticação. Usado para converter em data URL e exibir no preview.

        Args:
            url: URL completa ou relativa (ex: /rest/api/3/attachment/content/12345).

        Returns:
            Bytes do arquivo ou None em caso de erro.
        """
        if not url or not isinstance(url, str) or "/attachment/content/" not in url:
            return None
        from core.adf_media import parse_attachment_content_url

        att_id = parse_attachment_content_url(url)
        if not att_id:
            return None
        if not self._server_url:
            return None
        # Construir URL absoluta
        base = self._server_url.rstrip("/")
        if url.startswith("http"):
            fetch_url = url
        else:
            fetch_url = (
                f"{base}{url}"
                if url.startswith("/")
                else f"{base}/rest/api/3/attachment/content/{att_id}"
            )
        try:
            auth = self._get_auth()
            response = requests.get(
                fetch_url,
                auth=auth,
                timeout=30,
                allow_redirects=True,
            )
            if response.status_code >= 400:
                return None
            return response.content
        except Exception:
            return None

    def get_attachment_settings(self) -> Dict[str, Any]:
        """
        Obtém configurações de anexos do Jira (GET /rest/api/3/attachment/meta).
        Retorna { "enabled": bool, "uploadLimit": int } (uploadLimit em bytes).
        """
        if not self._server_url:
            raise RuntimeError("URL do servidor Jira não configurada")
        try:
            response = self._make_request("GET", "attachment/meta", timeout=15)
            data = response.json()
            return {
                "enabled": data.get("enabled", True),
                "uploadLimit": data.get("uploadLimit", 10485760),
            }
        except RuntimeError:
            raise
        except Exception as e:
            raise RuntimeError(
                f"Erro ao obter configurações de anexos: {str(e)}"
            ) from e

    def get_projects(
        self, expand: Optional[str] = "description,lead,issueTypes"
    ) -> List["_jira_meta.JiraProject"]:
        """
        Lista projetos acessíveis (GET /rest/api/3/project).
        Retorna lista de JiraProject parseados.
        """
        params = {}
        if expand:
            params["expand"] = expand
        response = self._make_request("GET", "project", params=params or None)
        data = response.json()
        if (
            isinstance(data, dict)
            and "values" in data
            and isinstance(data["values"], list)
        ):
            data = data["values"]
        return _jira_meta.parse_projects_response(data)

    def get_project_issue_types(
        self, project_id: str
    ) -> List["_jira_meta.JiraIssueType"]:
        """
        Lista issue types do projeto (GET /rest/api/3/issuetype/project?projectId=).
        project_id: id do projeto (ex.: "10001"), não a key.
        """
        response = self._make_request(
            "GET", "issuetype/project", params={"projectId": project_id}
        )
        data = response.json()
        return _jira_meta.parse_issue_types_response(data)

    def get_issue_createmeta(
        self,
        project_keys: str,
        issuetype_ids: str,
        expand: str = "projects.issuetypes.fields",
    ) -> Dict[str, Any]:
        """
        Metadata para criação de issue (GET /rest/api/3/issue/createmeta).
        Retorna o JSON bruto (projects[].issuetypes[].fields).
        """
        params = {
            "projectKeys": project_keys,
            "issuetypeIds": issuetype_ids,
            "expand": expand,
        }
        response = self._make_request("GET", "issue/createmeta", params=params)
        return response.json()

    def get_createmeta_fields_for_issue_type(
        self, project_key: str, issuetype_id: str
    ) -> List["_jira_meta.JiraFieldMetadata"]:
        """
        Obtém campos disponíveis para criar issue (project_key + issuetype_id).
        Localiza projeto por key e issue type por id na resposta (não usa [0]).
        Retorna lista de JiraFieldMetadata.
        """
        raw = self.get_issue_createmeta(
            project_keys=project_key, issuetype_ids=issuetype_id
        )
        projects = raw.get("projects") or []
        project_key_str = str(project_key) if project_key is not None else ""
        issuetype_id_str = str(issuetype_id) if issuetype_id is not None else ""
        for project in projects:
            if str(project.get("key", "")) != project_key_str:
                continue
            issuetypes = project.get("issuetypes") or []
            for it in issuetypes:
                if str(it.get("id", "")) != issuetype_id_str:
                    continue
                fields_dict = it.get("fields") or {}
                return _jira_meta.parse_createmeta_fields(fields_dict)
        return []

    def get_editmeta_fields(
        self, issue_id_or_key: str
    ) -> List["_jira_meta.JiraFieldMetadata"]:
        """
        Obtém campos editáveis de uma issue (GET /rest/api/3/issue/{idOrKey}/editmeta).
        Retorna lista de JiraFieldMetadata (mesma estrutura de createmeta).
        """
        if not (issue_id_or_key and str(issue_id_or_key).strip()):
            return []
        path = f"issue/{str(issue_id_or_key).strip()}/editmeta"
        response = self._make_request("GET", path, timeout=15)
        data = response.json()
        fields_dict = data.get("fields") or {}
        return _jira_meta.parse_createmeta_fields(fields_dict)

    def get_fields_for_issue_type(
        self, project_key: str, issuetype_id: str
    ) -> List["_jira_meta.JiraFieldMetadata"]:
        """
        Obtém campos para (project_key, issuetype_id): tenta editmeta via JQL (1 issue),
        fallback para createmeta se não houver issue.
        """
        if not (project_key and issuetype_id):
            return []
        it_id = str(issuetype_id).strip()
        issuetype_jql = it_id if it_id.isdigit() else f'"{it_id}"'
        jql = f'project = "{project_key}" AND issuetype = {issuetype_jql}'
        issues = self.search_issues(jql, max_results=1)
        if issues:
            key = issues[0].get("key")
            if key:
                try:
                    return self.get_editmeta_fields(key)
                except Exception:
                    pass
        return self.get_createmeta_fields_for_issue_type(project_key, issuetype_id)

    def get_fields(self) -> List["_jira_meta.JiraFieldMetadata"]:
        """
        Lista todos os campos da instância (GET /rest/api/3/field).
        Retorna lista de JiraFieldMetadata (sem required/default/allowedValues).
        """
        response = self._make_request("GET", "field")
        data = response.json()
        return _jira_meta.parse_field_list_response(data)

    def get_field_contexts(self, field_id: str) -> List[Dict[str, Any]]:
        """
        Lista contextos de um custom field (GET /rest/api/3/field/{fieldId}/context).
        Requer permissão Administer Jira ou read:custom-field-contextual-configuration.
        """
        fid = str(field_id).strip()
        if not fid:
            return []
        response = self._make_request("GET", f"field/{fid}/context", timeout=15)
        data = response.json()
        values = data.get("values") if isinstance(data, dict) else []
        return list(values) if isinstance(values, list) else []

    def get_field_context_mapping(
        self,
        field_id: str,
        project_ids: List[str],
        issue_type_ids: List[str],
    ) -> List[Dict[str, Any]]:
        """
        Obtém contextId aplicável a pares (projectId, issueTypeId) (POST context/mapping).
        project_ids e issue_type_ids devem ter o mesmo comprimento (pares 1:1).
        Retorna lista de {"projectId", "issueTypeId", "contextId"}.
        """
        fid = str(field_id).strip()
        if not fid or not project_ids or not issue_type_ids:
            return []
        if len(project_ids) != len(issue_type_ids):
            return []
        mappings = [
            {"projectId": str(pid), "issueTypeId": str(iid)}
            for pid, iid in zip(project_ids, issue_type_ids)
        ]
        payload = {"mappings": mappings}
        response = self._make_request(
            "POST", f"field/{fid}/context/mapping", json_data=payload, timeout=15
        )
        data = response.json()
        values = data.get("values") if isinstance(data, dict) else []
        return list(values) if isinstance(values, list) else []

    def get_workflow_schemes_for_projects(
        self, project_ids: List[str]
    ) -> List[Dict[str, Any]]:
        """
        Obtém workflow schemes que atendem aos projetos (POST /rest/api/3/workflowscheme/read).
        Retorna lista de schemes; cada um pode ter workflowsForIssueTypes (issueTypeIds → workflow).
        Retorna [] em caso de 403 (falta de permissão).
        """
        if not project_ids:
            return []
        payload = {"projectIds": [str(pid).strip() for pid in project_ids if pid]}
        if not payload["projectIds"]:
            return []
        try:
            response = self._make_request(
                "POST", "workflowscheme/read", json_data=payload, timeout=30
            )
            data = response.json()
            # Log estrutura básica da resposta para diagnóstico de workflow_metadata
            try:
                from src.utils.debug import debug_log

                schemes = data if isinstance(data, list) else []
                first = schemes[0] if schemes else {}
                wf_items = first.get("workflowsForIssueTypes") or []
                debug_log(
                    "JiraClient",
                    "get_workflow_schemes_for_projects",
                    "workflowscheme/read projectIds=%s schemes=%d first.keys=%s has_defaultWorkflow=%s workflowsForIssueTypes.len=%d",
                    payload["projectIds"],
                    len(schemes),
                    list(first.keys()) if isinstance(first, dict) else [],
                    bool(isinstance(first, dict) and first.get("defaultWorkflow")),
                    len(wf_items) if isinstance(wf_items, list) else 0,
                )
            except Exception:
                # Logging não deve quebrar o fluxo normal
                pass
            return data if isinstance(data, list) else []
        except RuntimeError as e:
            if "403" in str(e) or "Forbidden" in str(e):
                return []
            raise

    def get_project_statuses(self, project_id_or_key: str) -> List[Dict[str, Any]]:
        """
        Lista statuses do projeto agrupados por issue type (GET /rest/api/3/project/{idOrKey}/statuses).
        project_id_or_key: id ou key do projeto.
        Retorna lista de objetos com id/name do issue type e array statuses.
        Retorna [] em caso de 403.
        """
        pid = (project_id_or_key or "").strip()
        if not pid:
            return []
        try:
            response = self._make_request("GET", f"project/{pid}/statuses", timeout=15)
            data = response.json()
            items = data if isinstance(data, list) else []
            # Log forma básica dos statuses para confirmar statusCategory/category
            try:
                from src.utils.debug import debug_log

                first_item = items[0] if items else {}
                statuses = first_item.get("statuses") or []
                first_status = (
                    statuses[0] if isinstance(statuses, list) and statuses else {}
                )
                status_cat = (
                    first_status.get("statusCategory")
                    if isinstance(first_status, dict)
                    else None
                )
                debug_log(
                    "JiraClient",
                    "get_project_statuses",
                    "project/%s/statuses items=%d first_issueType.id=%s statuses.len=%d first_status.keys=%s has_statusCategory=%s statusCategory.key=%s",
                    pid,
                    len(items),
                    (
                        str(first_item.get("id") or "")
                        if isinstance(first_item, dict)
                        else ""
                    ),
                    len(statuses) if isinstance(statuses, list) else 0,
                    list(first_status.keys()) if isinstance(first_status, dict) else [],
                    bool(isinstance(status_cat, dict)),
                    (
                        str(status_cat.get("key") or "")
                        if isinstance(status_cat, dict)
                        else ""
                    ),
                )
            except Exception:
                pass
            return items
        except RuntimeError as e:
            if "403" in str(e) or "Forbidden" in str(e):
                return []
            raise

    def get_workflows_search(
        self,
        expand: str = "values.transitions",
        query_string: Optional[str] = None,
        start_at: int = 0,
        max_results: int = 50,
        is_active: bool = True,
    ) -> Dict[str, Any]:
        """
        Busca workflows (GET /rest/api/3/workflows/search).
        expand=values.transitions traz statuses (top-level) e values[].statuses/transitions.
        query_string: filtro case-insensitive por nome do workflow.
        is_active=true filtra apenas workflows ativos.
        Retorna o JSON bruto (statuses no topo, values = lista de workflows).
        Retorna {"values": []} em caso de 403.
        """
        params = {
            "expand": expand,
            "startAt": start_at,
            "maxResults": max_results,
            "isActive": is_active,
        }
        if query_string and str(query_string).strip():
            params["queryString"] = str(query_string).strip()
        try:
            response = self._make_request(
                "GET", "workflows/search", params=params, timeout=30
            )
            data = response.json()
            obj = data if isinstance(data, dict) else {"values": []}
            try:
                from src.utils.debug import debug_log

                values = obj.get("values") if isinstance(obj, dict) else []
                top_statuses = obj.get("statuses") if isinstance(obj, dict) else []
                first = values[0] if isinstance(values, list) and values else {}
                raw_transitions = (
                    first.get("transitions") or [] if isinstance(first, dict) else []
                )
                first_id = first.get("id") if isinstance(first, dict) else None
                w_id_str = (
                    str(first_id)
                    if not isinstance(first_id, dict)
                    else str(first_id.get("entityId") or first_id.get("id") or "")
                )
                debug_log(
                    "JiraClient",
                    "get_workflows_search",
                    "workflows/search query=%s values.len=%d statuses.len=%d first.id=%s transitions.len=%d",
                    str(query_string or ""),
                    len(values) if isinstance(values, list) else 0,
                    len(top_statuses) if isinstance(top_statuses, list) else 0,
                    w_id_str,
                    len(raw_transitions) if isinstance(raw_transitions, list) else 0,
                )
            except Exception:
                pass
            return obj
        except RuntimeError as e:
            if "403" in str(e) or "Forbidden" in str(e):
                return {"values": []}
            raise

    def get_field_context_default_value(
        self,
        field_id: str,
        context_id: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """
        Obtém default values do custom field (GET context/defaultValue).
        Se context_id for passado, filtra por esse contexto.
        Retorno varia por tipo (option.single com optionId, etc.).
        Para campos Assets a API retorna 400; retorna [] em vez de exceção.
        """
        fid = str(field_id).strip()
        if not fid:
            return []
        params = {}
        if context_id:
            params["contextId"] = [str(context_id)]
        try:
            response = self._make_request(
                "GET",
                f"field/{fid}/context/defaultValue",
                params=params or None,
                timeout=15,
            )
        except RuntimeError:
            return []  # 400 (e.g. Assets "not supported") or other client error
        data = response.json()
        values = data.get("values") if isinstance(data, dict) else []
        return list(values) if isinstance(values, list) else []

    def get_field_context_options(
        self,
        field_id: str,
        context_id: str,
        max_results: int = 100,
    ) -> List[Dict[str, Any]]:
        """
        Obtém opções (valores possíveis) do custom field para um contexto
        (GET /rest/api/3/field/{fieldId}/context/{contextId}/option).
        Paginado; retorna lista de { id, value, ... } (optionId, disabled opcionais).
        Aplica-se a Select List (single/multiple/cascading), Radio, Checkboxes.
        """
        fid = str(field_id).strip()
        cid = str(context_id).strip()
        if not fid or not cid:
            return []
        result: List[Dict[str, Any]] = []
        start_at = 0
        while True:
            params = {"startAt": start_at, "maxResults": max_results}
            response = self._make_request(
                "GET",
                f"field/{fid}/context/{cid}/option",
                params=params,
                timeout=15,
            )
            data = response.json()
            values = data.get("values") if isinstance(data, dict) else []
            if not isinstance(values, list):
                break
            result.extend(values)
            if data.get("isLast", True) or len(values) < max_results:
                break
            start_at = data.get("startAt", 0) + len(values)

        return result

    def delete_attachment(self, attachment_id: str) -> bool:
        """
        Remove um anexo de uma issue (DELETE /rest/api/3/attachment/{id}).

        Args:
            attachment_id: ID do anexo (ex.: "1982426").

        Returns:
            True se a API retornar 204 No Content, False em caso de erro.

        Permissões Jira: "Delete own attachments" ou "Delete all attachments" no projeto.
        """
        if not attachment_id or not str(attachment_id).strip():
            return False
        aid = str(attachment_id).strip()
        try:
            response = self._make_request("DELETE", f"attachment/{aid}", timeout=15)
            return response.status_code == 204
        except RuntimeError as e:
            error_msg = str(e)
            if "403" in error_msg or "404" in error_msg:
                return False
            raise
        except Exception:
            return False

    def add_attachment(self, issue_key: str, file_path: str) -> List[Dict[str, Any]]:
        """
        Adiciona um anexo a uma issue (POST multipart/form-data).
        Requer header X-Atlassian-Token: no-check e parâmetro "file".

        Args:
            issue_key: Chave da issue (ex: PROJECT-123)
            file_path: Caminho local do arquivo

        Returns:
            Lista de dicts com id, filename, content (URL), mimeType, size
            para cada anexo retornado pela API (normalmente um item).

        Raises:
            RuntimeError: Se arquivo não existir, ou API retornar 403/404/413
        """
        path = Path(file_path)
        if not path.exists() or not path.is_file():
            raise RuntimeError(f"Arquivo não encontrado: {file_path}")

        url = f"{self._server_url}/rest/api/3/issue/{issue_key}/attachments"
        auth = self._get_auth()
        headers = {
            "Accept": "application/json",
            "X-Atlassian-Token": "no-check",
        }
        # Não definir Content-Type; requests define multipart/form-data com boundary
        filename = path.name
        mime_type, _ = mimetypes.guess_type(str(path))
        if not mime_type:
            mime_type = "application/octet-stream"

        try:
            with open(path, "rb") as f:
                files = {"file": (filename, f, mime_type)}
                response = requests.post(
                    url,
                    auth=auth,
                    headers=headers,
                    files=files,
                    timeout=60,
                )
            if response.status_code >= 400:
                error_msg = response.text or f"HTTP {response.status_code}"
                try:
                    err_json = response.json()
                    if "errorMessages" in err_json:
                        error_msg = "; ".join(err_json["errorMessages"])
                    elif "errors" in err_json and err_json["errors"]:
                        error_msg = "; ".join(
                            f"{k}: {v}" for k, v in err_json["errors"].items()
                        )
                except (json.JSONDecodeError, TypeError, ValueError):
                    pass
                if response.status_code == 413:
                    error_msg = "Arquivo muito grande. Reduza o tamanho ou use o limite do Jira."
                raise RuntimeError(
                    f"Erro ao anexar arquivo (HTTP {response.status_code}): {error_msg}"
                )
            data = response.json()
            if not isinstance(data, list):
                return []
            return [
                {
                    "id": str(a.get("id", "")),
                    "filename": a.get("filename", ""),
                    "content": a.get("content", ""),
                    "mimeType": a.get("mimeType", ""),
                    "size": a.get("size", 0),
                }
                for a in data
            ]
        except requests.exceptions.RequestException as e:
            raise RuntimeError(f"Erro de rede ao anexar arquivo: {str(e)}") from e

    def add_attachment_from_bytes(
        self,
        issue_key: str,
        data: bytes,
        filename: str,
    ) -> List[Dict[str, Any]]:
        """
        Adiciona um anexo a uma issue a partir de bytes (ex.: imagem da área de transferência).

        Args:
            issue_key: Chave da issue
            data: Conteúdo binário do arquivo
            filename: Nome do arquivo (ex.: paste.png)

        Returns:
            Lista de dicts com id, filename, content (URL), mimeType, size
        """
        import io

        url = f"{self._server_url}/rest/api/3/issue/{issue_key}/attachments"
        auth = self._get_auth()
        headers = {
            "Accept": "application/json",
            "X-Atlassian-Token": "no-check",
        }
        mime_type, _ = mimetypes.guess_type(filename)
        if not mime_type:
            mime_type = "application/octet-stream"

        try:
            files = {"file": (filename, io.BytesIO(data), mime_type)}
            response = requests.post(
                url,
                auth=auth,
                headers=headers,
                files=files,
                timeout=60,
            )
            if response.status_code >= 400:
                error_msg = response.text or f"HTTP {response.status_code}"
                try:
                    err_json = response.json()
                    if "errorMessages" in err_json:
                        error_msg = "; ".join(err_json["errorMessages"])
                    elif "errors" in err_json and err_json["errors"]:
                        error_msg = "; ".join(
                            f"{k}: {v}" for k, v in err_json["errors"].items()
                        )
                except (json.JSONDecodeError, TypeError, ValueError):
                    pass
                if response.status_code == 413:
                    error_msg = "Arquivo muito grande. Reduza o tamanho ou use o limite do Jira."
                raise RuntimeError(
                    f"Erro ao anexar arquivo (HTTP {response.status_code}): {error_msg}"
                )
            resp_data = response.json()
            if not isinstance(resp_data, list):
                return []
            return [
                {
                    "id": str(a.get("id", "")),
                    "filename": a.get("filename", ""),
                    "content": a.get("content", ""),
                    "mimeType": a.get("mimeType", ""),
                    "size": a.get("size", 0),
                }
                for a in resp_data
            ]
        except requests.exceptions.RequestException as e:
            raise RuntimeError(f"Erro de rede ao anexar arquivo: {str(e)}") from e

    def get_assets_workspace_id(self) -> Optional[str]:
        """
        Obtém o workspaceId do Jira Assets via GET rest/servicedeskapi/assets/workspace.
        Retorna o ID do primeiro workspace da resposta ou None em caso de erro/404.
        """
        if not self._server_url:
            return None
        url = f"{self._server_url.rstrip('/')}/rest/servicedeskapi/assets/workspace"
        try:
            resp = self._request_raw("GET", url, timeout=15)
            data = resp.json()
            # Resposta pode ser lista de workspaces ou objeto com "values"/"id"
            if isinstance(data, list) and data:
                w = data[0]
                return w.get("id") or w.get("workspaceId")
            if isinstance(data, dict):
                if "id" in data:
                    return data["id"]
                if "workspaceId" in data:
                    return data["workspaceId"]
                values = data.get("values") or data.get("workspaces")
                if isinstance(values, list) and values:
                    w = values[0]
                    return w.get("id") or w.get("workspaceId")
            return None
        except (
            RuntimeError,
            requests.exceptions.RequestException,
            json.JSONDecodeError,
        ):
            return None

    def get_cloud_id_from_tenant(self) -> Optional[str]:
        """
        Obtém o cloudId da instância Jira Cloud via GET /_edge/tenant_info no servidor.
        Só tenta se a URL do servidor for *.atlassian.net.
        Retorna o valor de 'cloudId' no JSON ou None em caso de erro.
        """
        if not self._server_url or ".atlassian.net" not in self._server_url:
            return None
        url = f"{self._server_url.rstrip('/')}/_edge/tenant_info"
        try:
            resp = self._request_raw("GET", url, timeout=10)
            data = resp.json()
            if isinstance(data, dict):
                return data.get("cloudId") or None
            return None
        except (
            RuntimeError,
            requests.exceptions.RequestException,
            json.JSONDecodeError,
        ):
            return None

    def get_field_id_by_name(self, field_name: str) -> Optional[str]:
        """
        Obtém o ID (customfield_XXXXX) de um campo pelo nome ou alias.
        Chama GET /rest/api/3/field e compara name/clauseNames (normalizado).
        """
        if not field_name or not field_name.strip():
            return None
        name_clean = field_name.strip().lower().replace(" ", "_")
        try:
            response = self._make_request("GET", "field", timeout=15)
            fields = response.json()
            if not isinstance(fields, list):
                return None
            for f in fields:
                fid = f.get("id")
                if not fid:
                    continue
                n = (f.get("name") or "").strip().lower().replace(" ", "_")
                if n == name_clean:
                    return fid
                for clause in f.get("clauseNames") or []:
                    if (clause or "").strip().lower() == name_clean:
                        return fid
            return None
        except (
            RuntimeError,
            requests.exceptions.RequestException,
            json.JSONDecodeError,
        ):
            return None

    def fetch_assets_objects_aql(
        self,
        cloud_id: str,
        workspace_id: str,
        ql_query: str,
        start_at: int = 0,
        max_results: int = 50,
        include_attributes: bool = True,
    ) -> Dict[str, Any]:
        """
        Lista objetos Asset via POST /object/aql em api.atlassian.com.
        Requer cloud_id (instância Jira Cloud) e workspace_id (Assets workspace).
        Retorna dict com 'values' (lista de objetos) e 'objectTypeAttributes'.
        """
        if not cloud_id or not workspace_id or not ql_query or not ql_query.strip():
            return {"values": [], "objectTypeAttributes": []}
        url = (
            f"https://api.atlassian.com/ex/jira/{cloud_id}/jsm/assets/workspace/"
            f"{workspace_id}/v1/object/aql"
        )
        params = {
            "startAt": start_at,
            "maxResults": max_results,
            "includeAttributes": str(include_attributes).lower(),
        }
        body = {"qlQuery": ql_query.strip()}
        try:
            resp = self._request_raw(
                "POST", url, json_data=body, params=params, timeout=30
            )
            data = resp.json()
            return {
                "values": data.get("values", []),
                "objectTypeAttributes": data.get("objectTypeAttributes", []),
                "total": data.get("total", 0),
                "isLast": data.get("isLast", True),
            }
        except (
            RuntimeError,
            requests.exceptions.RequestException,
            json.JSONDecodeError,
        ):
            return {
                "values": [],
                "objectTypeAttributes": [],
                "total": 0,
                "isLast": True,
            }

    def get_assets_object_schemas(
        self,
        cloud_id: str,
        workspace_id: str,
        start_at: int = 0,
        max_results: int = 100,
    ) -> List[Dict[str, Any]]:
        """
        Lista object schemas do Jira Assets via GET objectschema/list.
        Requer cloud_id e workspace_id. Retorna lista de dicts com id, name, objectSchemaKey.
        """
        if not cloud_id or not workspace_id:
            return []
        url = (
            f"https://api.atlassian.com/ex/jira/{cloud_id}/jsm/assets/workspace/"
            f"{workspace_id}/v1/objectschema/list"
        )
        params = {"startAt": start_at, "maxResults": max_results}
        try:
            resp = self._request_raw("GET", url, params=params, timeout=15)
            data = resp.json()
            values = data.get("values") if isinstance(data, dict) else []
            if not isinstance(values, list):
                return []
            return [
                {
                    "id": str(v.get("id", "")),
                    "name": str(v.get("name", "")),
                    "objectSchemaKey": str(v.get("objectSchemaKey", "")),
                }
                for v in values
                if isinstance(v, dict)
            ]
        except (
            RuntimeError,
            requests.exceptions.RequestException,
            json.JSONDecodeError,
        ):
            return []

    def get_assets_object_types(
        self,
        cloud_id: str,
        workspace_id: str,
        schema_id: str,
    ) -> List[Dict[str, Any]]:
        """
        Lista object types de um schema via GET objectschema/{id}/objecttypes.
        Retorna lista de dicts com id, name.
        """
        if not cloud_id or not workspace_id or not schema_id:
            return []
        schema_id = str(schema_id).strip()
        if not schema_id:
            return []
        url = (
            f"https://api.atlassian.com/ex/jira/{cloud_id}/jsm/assets/workspace/"
            f"{workspace_id}/v1/objectschema/{schema_id}/objecttypes"
        )
        try:
            from src.utils.debug import debug_log

            debug_log(
                "JiraClient",
                "get_assets_object_types",
                "url=%s schema_id=%s",
                url,
                schema_id,
            )
            resp = self._request_raw("GET", url, timeout=15)
            raw_text = (resp.text or "")[:500]
            try:
                data = resp.json()
            except json.JSONDecodeError:
                debug_log(
                    "JiraClient",
                    "get_assets_object_types",
                    "response not JSON status=%s body_preview=%s",
                    getattr(resp, "status_code", None),
                    raw_text,
                )
                return []
            if isinstance(data, list):
                entries = data
            elif isinstance(data, dict):
                entries = data.get("entries") or data.get("values") or []
            else:
                entries = []
            data_keys = list(data.keys()) if isinstance(data, dict) else []
            first_entry_keys = []
            if isinstance(entries, list) and entries and isinstance(entries[0], dict):
                first_entry_keys = list(entries[0].keys())
            debug_log(
                "JiraClient",
                "get_assets_object_types",
                "status=%s data_keys=%s len(entries)=%s first_entry_keys=%s",
                getattr(resp, "status_code", None),
                data_keys,
                len(entries) if isinstance(entries, list) else 0,
                first_entry_keys,
            )
            if not data_keys and isinstance(data, dict) and not entries:
                debug_log(
                    "JiraClient",
                    "get_assets_object_types",
                    "empty data_keys body_preview=%s",
                    raw_text,
                )
            if not isinstance(entries, list):
                return []
            return [
                {
                    "id": str(e.get("id", "")),
                    "name": str(e.get("name", "")),
                }
                for e in entries
                if isinstance(e, dict)
            ]
        except (
            RuntimeError,
            requests.exceptions.RequestException,
            json.JSONDecodeError,
        ) as e:
            try:
                from src.utils.debug import debug_log

                debug_log(
                    "JiraClient",
                    "get_assets_object_types",
                    "exception: %s",
                    e,
                )
            except Exception:
                pass
            return []

    def get_current_user(self) -> Optional[str]:
        """
        Obtém o email do usuário atual autenticado via REST API

        Returns:
            Email do usuário atual ou None se não conseguir obter
        """
        try:
            response = self._make_request("GET", "myself", timeout=10)
            data = response.json()
            # Tentar obter emailAddress primeiro, depois accountId como fallback
            email = data.get("emailAddress")
            if email:
                return email
            # Se email não disponível (privacidade), usar accountId
            account_id = data.get("accountId")
            if account_id:
                return account_id
            return None
        except RuntimeError as e:
            print(
                f"Erro ao obter usuário atual: {e}. Usando email do config como fallback.",
                file=sys.stderr,
            )
            # Fallback para email do config
            return self._auth_email
        except Exception as e:
            print(
                f"Erro inesperado ao obter usuário atual: {e}. Usando email do config como fallback.",
                file=sys.stderr,
            )
            return self._auth_email

    def _get_user_account_id(self, email: str) -> Optional[str]:
        """
        Busca o accountId de um usuário a partir do email usando REST API

        Args:
            email: Email do usuário

        Returns:
            accountId do usuário ou None se não encontrado
        """
        if not email or not email.strip():
            return None

        try:
            # Buscar usuário por email usando user/search
            params = {"query": email.strip()}
            response = self._make_request(
                "GET", "user/search", params=params, timeout=10
            )
            users = response.json()

            # Garantir que users é uma lista
            if not isinstance(users, list):
                from src.utils.debug import debug_log

                debug_log(
                    "JiraClient",
                    "_get_user_account_id",
                    "Resposta inesperada do user/search (não é lista): %s",
                    type(users),
                )
                return None

            # Procurar usuário com email correspondente
            for user in users:
                if user.get("emailAddress", "").lower() == email.strip().lower():
                    account_id = user.get("accountId")
                    if account_id:
                        from src.utils.debug import debug_log

                        debug_log(
                            "JiraClient",
                            "_get_user_account_id",
                            "Encontrado accountId=%s para email=%s",
                            account_id,
                            email,
                        )
                        return account_id

            # Se não encontrou por email, tentar usar o primeiro resultado se houver
            if users and len(users) > 0:
                account_id = users[0].get("accountId")
                if account_id:
                    from src.utils.debug import debug_log

                    debug_log(
                        "JiraClient",
                        "_get_user_account_id",
                        "Usando primeiro resultado accountId=%s para email=%s",
                        account_id,
                        email,
                    )
                    return account_id

            from src.utils.debug import debug_log

            debug_log(
                "JiraClient",
                "_get_user_account_id",
                "Não encontrou accountId para email=%s",
                email,
            )
            return None
        except RuntimeError as e:
            print(f"Erro ao buscar accountId para email {email}: {e}", file=sys.stderr)
            return None
        except Exception as e:
            print(
                f"Erro inesperado ao buscar accountId para email {email}: {e}",
                file=sys.stderr,
            )
            return None

    @staticmethod
    def _text_to_adf(text: str) -> Dict[str, Any]:
        """
        Converte texto simples/Markdown para formato ADF (Atlassian Document Format)
        Inspirado no jira-cli/pkg/adf (Go)

        Suporta:
        - Títulos (# ## ###)
        - Parágrafos
        - Negrito (**texto** ou __texto__)
        - Itálico (*texto* ou _texto_)
        - Código inline (`código`)
        - Blocos de código (```)
        - Listas ordenadas e não ordenadas
        - Links [texto](url)
        - Quebras de linha

        Args:
            text: Texto simples ou Markdown a ser convertido

        Returns:
            Dicionário no formato ADF
        """
        from src.utils.debug import debug_log

        debug_log(
            "JiraClient",
            "_text_to_adf",
            "Iniciando conversão (text_len=%d)",
            len(text) if text else 0,
        )
        if not text or not text.strip():
            return {
                "version": 1,
                "type": "doc",
                "content": [{"type": "paragraph", "content": []}],
            }

        lines = text.split("\n")
        debug_log(
            "JiraClient", "_text_to_adf", "Texto dividido em %d linhas", len(lines)
        )
        content = []
        i = 0
        in_code_block = False
        code_block_lines = []
        code_block_lang = None

        while i < len(lines):
            if i % 50 == 0:  # Log a cada 50 linhas para não poluir muito
                debug_log(
                    "JiraClient",
                    "_text_to_adf",
                    "Processando linha %d/%d",
                    i,
                    len(lines),
                )
            line = lines[i]
            stripped = line.strip()

            # Bloco de código
            if stripped.startswith("```"):
                if in_code_block:
                    # Fechar bloco de código
                    if code_block_lines:
                        content.append(
                            {
                                "type": "codeBlock",
                                "attrs": (
                                    {"language": code_block_lang}
                                    if code_block_lang
                                    else {}
                                ),
                                "content": [
                                    {
                                        "type": "text",
                                        "text": "\n".join(code_block_lines),
                                    }
                                ],
                            }
                        )
                    code_block_lines = []
                    code_block_lang = None
                    in_code_block = False
                else:
                    # Abrir bloco de código
                    in_code_block = True
                    lang_match = re.match(r"^```(\w+)?", stripped)
                    code_block_lang = lang_match.group(1) if lang_match else None
                i += 1
                continue

            if in_code_block:
                code_block_lines.append(line)
                i += 1
                continue

            # Título
            heading_match = re.match(r"^(#{1,6})\s+(.+)$", stripped)
            if heading_match:
                level = len(heading_match.group(1))
                heading_text = heading_match.group(2)
                content.append(
                    {
                        "type": "heading",
                        "attrs": {"level": level},
                        "content": JiraClient._parse_inline_formatting(heading_text),
                    }
                )
                i += 1
                continue

            # Lista ordenada
            ordered_list_match = re.match(r"^(\d+)\.\s+(.+)$", stripped)
            if ordered_list_match:
                debug_log(
                    "JiraClient",
                    "_text_to_adf",
                    "Encontrada lista ordenada na linha %d",
                    i,
                )
                list_items = []
                list_start = i
                while i < len(lines) and re.match(r"^\d+\.\s+", lines[i].strip()):
                    item_match = re.match(r"^\d+\.\s+(.+)$", lines[i].strip())
                    if item_match:
                        item_text = item_match.group(1)
                        list_items.append(
                            {
                                "type": "listItem",
                                "content": [
                                    {
                                        "type": "paragraph",
                                        "content": JiraClient._parse_inline_formatting(
                                            item_text
                                        ),
                                    }
                                ],
                            }
                        )
                    i += 1
                    if i - list_start > 1000:  # Proteção contra loop infinito
                        debug_log(
                            "JiraClient",
                            "_text_to_adf",
                            "AVISO - Lista ordenada muito longa, parando em %d",
                            i,
                        )
                        break
                if list_items:
                    content.append({"type": "orderedList", "content": list_items})
                continue

            # Lista não ordenada: - * + ou ├─ └─ (estilo árvore)
            unordered_list_match = re.match(r"^([-*+]\s+|├─\s*|└─\s*)(.*)$", stripped)
            if unordered_list_match:
                debug_log(
                    "JiraClient",
                    "_text_to_adf",
                    "Encontrada lista não ordenada na linha %d",
                    i,
                )
                list_items = []
                list_start = i
                _ul_bullet = re.compile(r"^([-*+]\s+|├─\s*|└─\s*)(.*)$")
                while i < len(lines) and _ul_bullet.match(lines[i].strip()):
                    item_match = _ul_bullet.match(lines[i].strip())
                    if item_match:
                        item_text = (item_match.group(2) or "").strip()
                        list_items.append(
                            {
                                "type": "listItem",
                                "content": [
                                    {
                                        "type": "paragraph",
                                        "content": JiraClient._parse_inline_formatting(
                                            item_text
                                        ),
                                    }
                                ],
                            }
                        )
                    i += 1
                    if i - list_start > 1000:  # Proteção contra loop infinito
                        debug_log(
                            "JiraClient",
                            "_text_to_adf",
                            "AVISO - Lista não ordenada muito longa, parando em %d",
                            i,
                        )
                        break
                if list_items:
                    content.append({"type": "bulletList", "content": list_items})
                continue

            # Parágrafo normal
            if stripped:
                if len(stripped) > 1000:  # Log para parágrafos muito longos
                    debug_log(
                        "JiraClient",
                        "_text_to_adf",
                        "Processando parágrafo longo (%d chars) na linha %d",
                        len(stripped),
                        i,
                    )
                content.append(
                    {
                        "type": "paragraph",
                        "content": JiraClient._parse_inline_formatting(stripped),
                    }
                )
                i += 1
            else:
                # Uma ou mais linhas vazias = um único parágrafo vazio (evita inflar no round-trip)
                content.append({"type": "paragraph", "content": []})
                i += 1
                while i < len(lines) and not lines[i].strip():
                    i += 1

        # Se ainda estiver em bloco de código, fechar
        if in_code_block and code_block_lines:
            content.append(
                {
                    "type": "codeBlock",
                    "attrs": {"language": code_block_lang} if code_block_lang else {},
                    "content": [{"type": "text", "text": "\n".join(code_block_lines)}],
                }
            )

        # Se não houver conteúdo, criar parágrafo vazio
        if not content:
            content = [{"type": "paragraph", "content": []}]

        debug_log(
            "JiraClient",
            "_text_to_adf",
            "Conversão concluída - %d elementos no content",
            len(content),
        )
        return {"version": 1, "type": "doc", "content": content}

    @staticmethod
    def _adf_to_markdown(adf_node: Any) -> str:
        """
        Converte nó ADF (Atlassian Document Format) para Markdown (plain markdown).
        Preserva estrutura: doc, heading, paragraph, listas, codeBlock, blockquote, rule,
        text com marks (strong, em, code, link), hardBreak. Fallback para outros blocos.
        """
        if adf_node is None:
            return ""
        if isinstance(adf_node, str):
            return adf_node
        if isinstance(adf_node, list):
            return "\n\n".join(
                JiraClient._adf_to_markdown(item) for item in adf_node
            ).strip()
        if not isinstance(adf_node, dict):
            return str(adf_node) if adf_node else ""

        node_type = adf_node.get("type", "")
        content = adf_node.get("content")
        if not isinstance(content, list):
            content = []

        if node_type == "doc":
            # Uma única linha em branco entre blocos; ignora blocos vazios para não inflar quebras
            parts = [JiraClient._adf_to_markdown(c).strip() for c in content]
            return "\n\n".join(p for p in parts if p).strip()

        if node_type == "heading":
            level = min(6, max(1, adf_node.get("attrs", {}).get("level", 1)))
            prefix = "#" * level + " "
            inline = "".join(
                JiraClient._adf_inline_to_markdown(c) for c in content
            ).strip()
            return prefix + inline + "\n"

        if node_type == "paragraph":
            inline = "".join(
                JiraClient._adf_inline_to_markdown(c) for c in content
            ).strip()
            return inline + "\n" if inline else ""

        if node_type == "bulletList":
            items = [
                "- " + JiraClient._adf_to_markdown(item).strip().replace("\n\n", "\n")
                for item in content
            ]
            return "\n".join(items) + "\n"

        if node_type == "orderedList":
            items = []
            for i, item in enumerate(content, 1):
                item_md = (
                    JiraClient._adf_to_markdown(item).strip().replace("\n\n", "\n")
                )
                items.append(f"{i}. " + item_md)
            return "\n".join(items) + "\n"

        if node_type == "listItem":
            # listItem pode ter paragraph(s) + bulletList/orderedList aninhados; ADF guarda o nível.
            # Processar todos os filhos; sublistas são indentadas (4 espaços) para Markdown.
            parts = []
            for block in content:
                if not isinstance(block, dict):
                    continue
                block_md = JiraClient._adf_to_markdown(block).strip()
                if not block_md:
                    continue
                if block.get("type") in ("bulletList", "orderedList"):
                    lines = [line for line in block_md.split("\n") if line.strip()]
                    parts.append("\n".join("    " + line for line in lines))
                else:
                    parts.append(block_md)
            return "\n".join(parts) if parts else ""

        if node_type == "codeBlock":
            lang = (adf_node.get("attrs") or {}).get("language", "")
            code_parts = []
            for c in content:
                if isinstance(c, dict) and c.get("type") == "text":
                    code_parts.append(c.get("text", ""))
                else:
                    code_parts.append(JiraClient._adf_to_markdown(c))
            code_text = "".join(code_parts)
            if lang:
                return "```" + lang + "\n" + code_text + "\n```\n"
            return "```\n" + code_text + "\n```\n"

        if node_type == "blockquote":
            parts = []
            for block in content:
                block_md = JiraClient._adf_to_markdown(block).strip()
                for line in block_md.split("\n"):
                    parts.append("> " + line)
            return "\n".join(parts) + "\n"

        if node_type == "rule":
            return "---\n"

        if node_type == "text":
            return JiraClient._adf_text_node_to_markdown(adf_node)

        if node_type == "hardBreak":
            return "\n"

        if node_type == "mediaSingle":
            single_attrs = adf_node.get("attrs") or {}
            width = single_attrs.get("width")
            width_suffix = f'{{: width="{width}" }}' if width is not None else ""
            for c in content:
                if isinstance(c, dict) and c.get("type") == "media":
                    attrs = c.get("attrs") or {}
                    alt = attrs.get("alt", "") or "attachment"
                    url = attrs.get("url", "")
                    if url:
                        return f"![{alt}]({url}){width_suffix}\n"
                    mid = attrs.get("id", "")
                    if mid:
                        url = f"/rest/api/3/attachment/content/{mid}"
                        return f"![{alt}]({url}){width_suffix}\n"
            return ""

        if node_type == "media":
            attrs = adf_node.get("attrs") or {}
            alt = attrs.get("alt", "") or "attachment"
            url = attrs.get("url", "")
            width = attrs.get("width")
            width_suffix = f'{{: width="{width}" }}' if width is not None else ""
            if url:
                return f"![{alt}]({url}){width_suffix}\n"
            mid = attrs.get("id", "")
            if mid:
                url = f"/rest/api/3/attachment/content/{mid}"
                return f"![{alt}]({url}){width_suffix}\n"
            return ""

        # Fallback: outros blocos (panel, table, etc.)
        if content:
            return (
                "\n\n".join(
                    JiraClient._adf_to_markdown(c).strip() for c in content
                ).strip()
                + "\n"
            )
        return ""

    @staticmethod
    def _adf_inline_to_markdown(inline_node: Any) -> str:
        """Converte nó inline ADF (text, hardBreak) para markdown."""
        if inline_node is None:
            return ""
        if isinstance(inline_node, dict):
            if inline_node.get("type") == "hardBreak":
                return "\n"
            if inline_node.get("type") == "text":
                return JiraClient._adf_text_node_to_markdown(inline_node)
        return ""

    @staticmethod
    def _adf_text_node_to_markdown(node: Dict[str, Any]) -> str:
        """Converte nó ADF type=text (com marks opcionais) para markdown."""
        text = node.get("text", "") or ""
        marks = node.get("marks") or []
        for m in marks:
            if not isinstance(m, dict):
                continue
            mark_type = m.get("type", "")
            if mark_type == "strong":
                return "**" + text + "**"
            if mark_type == "em":
                return "*" + text + "*"
            if mark_type == "code":
                return "`" + text + "`"
            if mark_type == "link":
                href = (m.get("attrs") or {}).get("href", "")
                # Links to Jira attachments must use ![alt](url) for images; [text](url) renders as link
                if "/attachment/content/" in (href or ""):
                    return "![" + text + "](" + href + ")"
                return "[" + text + "](" + href + ")"
        return text

    @staticmethod
    def _parse_inline_formatting(text: str) -> List[Dict[str, Any]]:
        """
        Parse inline formatting (negrito, itálico, código, links) em um texto

        Args:
            text: Texto com formatação inline

        Returns:
            Lista de nós ADF (text, text com marks, etc.)
        """
        if not text:
            return []

        # Log apenas para textos muito longos para não poluir
        if len(text) > 500:
            from src.utils.debug import debug_log

            debug_log(
                "JiraClient",
                "_parse_inline_formatting",
                "Processando texto longo (%d chars)",
                len(text),
            )

        nodes = []
        i = 0
        text_len = len(text)
        iterations = 0
        max_iterations = text_len * 2  # Proteção contra loop infinito

        while i < text_len:
            iterations += 1
            if iterations > max_iterations:
                debug_log(
                    "JiraClient",
                    "_parse_inline_formatting",
                    "AVISO - Loop infinito detectado! i=%d, text_len=%d, text_resto=%s",
                    i,
                    text_len,
                    text[i : i + 50],
                )
                # Adicionar o resto do texto como texto simples e sair
                if i < text_len:
                    nodes.append({"type": "text", "text": text[i:]})
                break
            # Link [texto](url)
            link_match = re.match(r"\[([^\]]+)\]\(([^)]+)\)", text[i:])
            if link_match:
                link_text = link_match.group(1)
                link_url = link_match.group(2)
                nodes.append(
                    {
                        "type": "text",
                        "text": link_text,
                        "marks": [{"type": "link", "attrs": {"href": link_url}}],
                    }
                )
                i += link_match.end()
                continue

            # Código inline `código`
            code_match = re.match(r"`([^`]+)`", text[i:])
            if code_match:
                code_text = code_match.group(1)
                nodes.append(
                    {"type": "text", "text": code_text, "marks": [{"type": "code"}]}
                )
                i += code_match.end()
                continue

            # Negrito **texto** ou __texto__
            bold_match = re.match(r"(\*\*|__)([^*_\n]+?)\1", text[i:])
            if bold_match:
                bold_text = bold_match.group(2)
                nodes.append(
                    {"type": "text", "text": bold_text, "marks": [{"type": "strong"}]}
                )
                i += bold_match.end()
                continue

            # Itálico *texto* ou _texto_ (mas não ** ou __)
            italic_match = re.match(
                r"(?<!\*)\*(?!\*)([^*\n]+?)\*(?!\*)|(?<!_)_(?!_)([^_\n]+?)_(?!_)",
                text[i:],
            )
            if italic_match:
                italic_text = italic_match.group(1) or italic_match.group(2)
                nodes.append(
                    {"type": "text", "text": italic_text, "marks": [{"type": "em"}]}
                )
                i += italic_match.end()
                continue

            # Texto normal - coletar até encontrar formatação
            start = i
            # Avançar pelo menos 1 caractere para evitar loop infinito
            i += 1
            while i < text_len:
                # Verificar se há formatação à frente
                char = text[i]
                next_char = text[i + 1] if i + 1 < text_len else None

                # Verificar padrões de formatação
                if char == "`" and next_char != "`":
                    # Código inline
                    break
                elif char == "[" and "](" in text[i:]:
                    # Link
                    break
                elif char == "*" and next_char == "*":
                    # Negrito
                    break
                elif char == "_" and next_char == "_":
                    # Negrito
                    break
                elif char in ["*", "_"] and (i == 0 or text[i - 1] not in ["*", "_"]):
                    # Possível itálico
                    break

                i += 1

            if i > start:
                plain_text = text[start:i]
                if plain_text:
                    nodes.append({"type": "text", "text": plain_text})
            else:
                # Se não avançou, adicionar pelo menos 1 caractere para evitar loop
                if start < text_len:
                    nodes.append({"type": "text", "text": text[start : start + 1]})
                    i = start + 1

        # Se não houver nós, retornar texto como está
        if not nodes:
            nodes = [{"type": "text", "text": text}]

        return nodes

    def create_issue(
        self,
        project: str,
        issue_type: str,
        summary: str,
        description: str,
        assignee: Optional[str] = None,
        custom_fields: Optional[Dict[str, str]] = None,
        parent_issue_key: Optional[str] = None,
        priority: Optional[str] = None,
    ) -> Dict[str, str]:
        """
        Cria uma issue no Jira usando REST API

        Args:
            project: Nome/chave do projeto (ex: "PLATFORM")
            issue_type: Tipo da issue (ex: "Task")
            summary: Resumo da issue
            description: Descrição da issue
            assignee: Email do assignee (opcional)
            custom_fields: Dicionário com campos customizados (field_id: valor)
            parent_issue_key: Chave da issue pai (Epic) (opcional)
            priority: Nome da prioridade (ex: "High", "Medium") (opcional)

        Returns:
            Dicionário com 'issue_key' e 'issue_url'

        Raises:
            RuntimeError: Se a criação falhar
        """
        from src.utils.debug import debug_log

        debug_log(
            "JiraClient",
            "create_issue",
            "Iniciando - project=%s, type=%s, summary=%s...",
            project,
            issue_type,
            summary[:50] if summary else "",
        )
        debug_log(
            "JiraClient",
            "create_issue",
            "custom_fields=%s, parent=%s, assignee=%s",
            custom_fields,
            parent_issue_key,
            assignee,
        )

        # Construir estrutura fields para REST API
        fields: Dict[str, Any] = {
            "project": {"key": project},
            "issuetype": {"name": issue_type},
            "summary": summary,
        }

        # Converter description para ADF se fornecido
        if description:
            debug_log(
                "JiraClient",
                "create_issue",
                "Convertendo description para ADF (tamanho=%d)...",
                len(description),
            )
            fields["description"] = self._text_to_adf(description)
            debug_log("JiraClient", "create_issue", "Conversão ADF concluída")

        # Adicionar assignee se fornecido
        # REST API v3 requer accountId (não aceita emailAddress diretamente)
        if assignee and assignee.strip():
            assignee_email = assignee.strip()
            account_id = None

            # Se for o usuário atual (mesmo email do config), usar accountId do config se disponível
            if assignee_email.lower() == self._auth_email.lower():
                if self._account_id:
                    account_id = self._account_id
                    debug_log(
                        "JiraClient",
                        "create_issue",
                        "Usando accountId=%s do config.json (usuário atual)",
                        account_id,
                    )
                else:
                    # Fallback: buscar via /myself se não estiver no config
                    try:
                        myself_response = self._make_request(
                            "GET", "myself", timeout=10
                        )
                        myself_data = myself_response.json()
                        account_id = myself_data.get("accountId")
                        if account_id:
                            debug_log(
                                "JiraClient",
                                "create_issue",
                                "Usando accountId=%s obtido via /myself (usuário atual)",
                                account_id,
                            )
                    except Exception as e:
                        debug_log(
                            "JiraClient",
                            "create_issue",
                            "Erro ao obter accountId via myself: %s",
                            e,
                        )

            # Se não encontrou ainda, buscar via user/search
            if not account_id:
                account_id = self._get_user_account_id(assignee_email)

            if account_id:
                fields["assignee"] = {"accountId": account_id}
                debug_log(
                    "JiraClient",
                    "create_issue",
                    "Assignee definido com accountId=%s para email=%s",
                    account_id,
                    assignee_email,
                )
            else:
                raise RuntimeError(
                    f"Não foi possível obter accountId para o assignee '{assignee_email}'. "
                    f"A API v3 do Jira requer accountId para definir assignee."
                )

        # Adicionar parent se fornecido (dentro de fields)
        if parent_issue_key and parent_issue_key.strip():
            fields["parent"] = {"key": parent_issue_key.strip()}

        # Adicionar prioridade se fornecido
        if priority and priority.strip():
            fields["priority"] = {"name": priority.strip()}

        # Adicionar campos customizados em fields
        # CREATE pode aceitar string direta, mas vamos usar {"value": "text"} para consistência
        # e garantir compatibilidade com campos select list
        # Não enviar placeholders (customfield_XXXXX, customfield_YYYYY) — causam HTTP 400
        try:
            from src.utils.field_utils import (
                is_placeholder_custom_field_id,
                normalize_asset_field_value,
            )
        except ImportError:
            is_placeholder_custom_field_id = lambda fid: fid in (
                "customfield_XXXXX",
                "customfield_YYYYY",
            )
            normalize_asset_field_value = lambda v: v
        if custom_fields:
            for field_id, field_value in custom_fields.items():
                if is_placeholder_custom_field_id(field_id):
                    debug_log(
                        "JiraClient",
                        "create_issue",
                        "Campo %s é placeholder; omitindo do payload (use Recarregar opções para descobrir o ID real)",
                        field_id,
                    )
                    continue
                if field_value is not None:
                    # Lista: normalizar para formato Assets (id, objectId, workspaceId) quando aplicável
                    if isinstance(field_value, list):
                        fields[field_id] = normalize_asset_field_value(field_value)
                    elif str(field_value).strip():
                        # Formatar como objeto com "value" para campos select list
                        fields[field_id] = {"value": str(field_value).strip()}

        # Construir payload completo
        payload = {"fields": fields}

        debug_log(
            "JiraClient",
            "create_issue",
            "Payload preparado com fields: %s",
            list(fields.keys()),
        )

        try:
            response = self._make_request(
                "POST", "issue", json_data=payload, timeout=30
            )
            data = response.json()

            debug_log(
                "JiraClient", "create_issue", "Resposta recebida: %s", list(data.keys())
            )

            # Extrair issue_key da resposta
            issue_key = data.get("key", "")
            if not issue_key:
                raise RuntimeError("REST API não retornou issue key na resposta")

            # Construir URL da issue usando a key diretamente
            # A URL "self" contém o ID numérico, não a key, então construímos manualmente
            if self._server_url:
                issue_url = f"{self._server_url}/browse/{issue_key}"
            else:
                # Fallback: construir URL baseado no projeto
                issue_url = (
                    f"https://{project.lower()}.atlassian.net/browse/{issue_key}"
                )

            debug_log(
                "JiraClient",
                "create_issue",
                "Issue criada com sucesso - key=%s, url=%s",
                issue_key,
                issue_url,
            )
            return {"issue_key": issue_key, "issue_url": issue_url}

        except RuntimeError as e:
            debug_log("JiraClient", "create_issue", "ERRO - %s", e)
            raise
        except Exception as e:
            debug_log("JiraClient", "create_issue", "ERRO inesperado - %s", e)
            raise RuntimeError(f"Erro inesperado ao criar issue: {str(e)}") from e

    def add_remotelink(self, issue_key: str, url: str, title: str) -> bool:
        """
        Add a remote link to an issue (e.g. link to Google Drive document).

        Args:
            issue_key: Issue key (e.g. "PROJECT-123")
            url: URL of the remote object
            title: Display title for the link

        Returns:
            True if successful.
        """
        if not issue_key or not url or not title:
            return False
        endpoint = f"issue/{issue_key.strip()}/remotelink"
        payload = {"object": {"url": url.strip(), "title": title.strip()}}
        try:
            self._make_request("POST", endpoint, json_data=payload, timeout=15)
            return True
        except Exception:
            return False

    def update_issue(
        self,
        issue_key: str,
        summary: Optional[str] = None,
        description: Optional[str] = None,
        status: Optional[str] = None,
        priority: Optional[str] = None,
        custom_fields: Optional[Dict[str, Any]] = None,
        parent_issue_key: Optional[str] = None,
        asset_field_updates: Optional[Dict[str, List[Dict[str, Any]]]] = None,
    ) -> bool:
        """
        Atualiza campos de uma issue existente usando REST API.

        Args:
            issue_key: Chave da issue (ex: PLATFORM-123)
            summary: Novo summary (opcional)
            description: Nova description (opcional)
            status: Novo status (opcional) - NÃO use aqui, use transition_issue
            priority: Nome da prioridade (ex: "High", "Medium") (opcional)
            custom_fields: Dicionário com campos customizados (field_id: valor) (opcional)
            parent_issue_key: Nova chave do parent (opcional, use "" para remover parent)
            asset_field_updates: Campos Asset a atualizar via "update"/"set" (field_id: lista de objetos
                { workspaceId, id, objectId }). Incluir apenas quando a transição for para In Development.

        Returns:
            True se atualizado com sucesso
        """
        if not issue_key:
            print("Erro: issue_key é obrigatório", file=sys.stderr)
            return False

        # Construir payload com estrutura fields conforme documentação REST API v3
        # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-put
        fields: Dict[str, Any] = {}

        if summary is not None and summary.strip():
            fields["summary"] = summary.strip()

        if description is not None:
            # Se description for dict (ADF), usar diretamente
            if isinstance(description, dict):
                fields["description"] = description
            # Se description for string vazia, usar ADF vazio
            elif description.strip():
                embed_enabled = (
                    self._config_manager is not None
                    and self._config_manager.get_attachment_embed_enabled()
                )
                has_attachment_urls = bool(
                    _RE_ATTACHMENT_URL_DETECT.search(description)
                )
                if embed_enabled and has_attachment_urls:
                    details = self.get_issue_details(issue_key)
                    issue_id = str(details.get("id", "")) if details else ""
                    if issue_id:
                        from core.adf_media import (
                            AttachmentInfo,
                            build_description_adf_with_media,
                            _MD_IMAGE_ATTACHMENT,
                            _MD_LINK_ATTACHMENT,
                        )

                        attachments_map: Dict[str, AttachmentInfo] = {}
                        default_width = None
                        if self._config_manager is not None:
                            default_width = (
                                self._config_manager.get_embed_max_display_width()
                            )
                        for m in _MD_IMAGE_ATTACHMENT.finditer(description):
                            alt = m.group(1) or ""
                            att_id = m.group(3)
                            width_override = default_width
                            rest = description[m.end() : m.end() + 80]
                            w_match = _RE_ATTR_WIDTH.match(rest)
                            if w_match:
                                width_override = int(w_match.group(1))
                            if att_id not in attachments_map:
                                attachments_map[att_id] = AttachmentInfo(
                                    id=att_id,
                                    filename=alt,
                                    mime_type="",
                                    size=0,
                                    collection_id=issue_id,
                                    display_width=width_override,
                                )
                        for m in _MD_LINK_ATTACHMENT.finditer(description):
                            alt = m.group(1) or ""
                            att_id = m.group(3)
                            width_override = default_width
                            rest = description[m.end() : m.end() + 80]
                            w_match = _RE_ATTR_WIDTH.match(rest)
                            if w_match:
                                width_override = int(w_match.group(1))
                            if att_id not in attachments_map:
                                attachments_map[att_id] = AttachmentInfo(
                                    id=att_id,
                                    filename=alt,
                                    mime_type="",
                                    size=0,
                                    collection_id=issue_id,
                                    display_width=width_override,
                                )
                        base_url = self._server_url or ""
                        fields["description"] = build_description_adf_with_media(
                            description,
                            attachments_map,
                            issue_id,
                            base_url,
                            self._text_to_adf,
                        )
                    else:
                        fields["description"] = self._text_to_adf(description)
                else:
                    fields["description"] = self._text_to_adf(description)
            else:
                # Description vazia - usar ADF mínimo válido
                fields["description"] = {
                    "version": 1,
                    "type": "doc",
                    "content": [{"type": "paragraph", "content": []}],
                }

        # Adicionar campos customizados em fields (apenas se não forem vazios)
        # Campos customizados do tipo select list precisam do formato {"value": "text"} ou {"name": "text"}
        # Campos multi-select precisam ser uma lista de objetos [{"value": "text"}, ...]
        # Conforme documentação REST API v3: "Specify a valid 'id' or 'name' for [field]"
        # Não enviar placeholders; normalizar listas para formato Assets (id, objectId, workspaceId)
        try:
            from src.utils.field_utils import (
                is_placeholder_custom_field_id,
                normalize_asset_field_value,
            )
        except ImportError:
            is_placeholder_custom_field_id = lambda fid: fid in (
                "customfield_XXXXX",
                "customfield_YYYYY",
            )
            normalize_asset_field_value = lambda v: v
        if custom_fields:
            for field_id, field_value in custom_fields.items():
                if is_placeholder_custom_field_id(field_id):
                    continue
                if field_value is not None:
                    if isinstance(field_value, list):
                        fields[field_id] = normalize_asset_field_value(field_value)
                    elif str(field_value).strip():
                        fields[field_id] = {"value": str(field_value).strip()}

        # Tratar parent conforme documentação REST API v3
        # Para definir: {"parent": {"key": "PARENT-KEY"}}
        # Para remover: {"parent": null} (não {"key": null})
        if parent_issue_key is not None:
            if parent_issue_key.strip():
                # Definir parent - formato correto para REST API v3
                fields["parent"] = {"key": parent_issue_key.strip()}
            else:
                # Remover parent - usar null diretamente conforme documentação
                fields["parent"] = None

        # Adicionar prioridade se fornecido
        if priority and priority.strip():
            fields["priority"] = {"name": priority.strip()}

        # Payload: fields + update (para campos Asset)
        payload: Dict[str, Any] = {}
        if fields:
            payload["fields"] = fields
        if asset_field_updates:
            # Campos Asset exigem "update": { field_id: [ { "set": [ objetos ] } ] }
            update_part: Dict[str, Any] = {}
            for field_id, objects in asset_field_updates.items():
                if objects is not None:
                    update_part[field_id] = [{"set": objects}]
            if update_part:
                payload["update"] = update_part

        if not payload:
            return True

        # Log detalhado do payload para debug
        from src.utils.debug import debug_log

        debug_log(
            "JiraClient",
            "update_issue",
            "Payload completo (primeiros 2000 chars):\n%s",
            json.dumps(payload, indent=2, ensure_ascii=False)[:2000],
        )
        debug_log(
            "JiraClient",
            "update_issue",
            "Campos/update sendo enviados: %s",
            list(payload.keys()),
        )

        try:
            self._make_request(
                "PUT", f"issue/{issue_key}", json_data=payload, timeout=15
            )
            return True
        except RuntimeError as e:
            error_msg = str(e)
            print(f"Erro ao atualizar issue: {error_msg}", file=sys.stderr)
            return False
        except Exception as e:
            print(f"Erro inesperado ao atualizar issue: {str(e)}", file=sys.stderr)
            return False

        # Status não é atualizado aqui - deve ser feito via transition_issue
        if status is not None:
            print(
                "AVISO: Status não deve ser atualizado via update_issue. Use transition_issue.",
                file=sys.stderr,
            )

    def update_custom_fields(self, issue_key: str, fields: Dict[str, str]) -> bool:
        """
        Atualiza campos customizados de uma issue (wrapper para update_issue)

        Args:
            issue_key: Chave da issue (ex: PLATFORM-123)
            fields: Dicionário com campos customizados (field_id: valor)

        Returns:
            True se atualizado com sucesso
        """
        return self.update_issue(issue_key, custom_fields=fields)

    def transition_issue(
        self,
        issue_key: str,
        status: str,
        max_retries: int = 3,
        retry_delay: float = 1.0,
        fields: Optional[Dict[str, Any]] = None,
    ) -> bool:
        """
        Transiciona uma issue para um novo status usando REST API.

        Alguns workflows do Jira exigem que campos obrigatórios sejam enviados
        no corpo da transição (ex.: Tipo de atividade, Utilização de IA, etc.).
        Use o parâmetro fields para enviar esses campos no POST da transição.

        Args:
            issue_key: Chave da issue
            status: Nome do status de destino
            max_retries: Número máximo de tentativas
            retry_delay: Delay entre tentativas (segundos)
            fields: Campos a enviar no corpo da transição (field_id -> valor no formato REST API)

        Returns:
            True se transicionado com sucesso
        """
        # Primeiro, obter lista de transições disponíveis
        try:
            response = self._make_request(
                "GET", f"issue/{issue_key}/transitions", timeout=15
            )
            transitions_data = response.json()
            transitions = transitions_data.get("transitions", [])

            # Mapear nome do status para ID de transição
            transition_id = None
            for transition in transitions:
                # Tentar match por nome exato (case-insensitive)
                if transition.get("name", "").lower() == status.lower():
                    transition_id = transition.get("id")
                    break
                # Tentar match pelo status de destino
                to_status = transition.get("to", {})
                if to_status.get("name", "").lower() == status.lower():
                    transition_id = transition.get("id")
                    break

            if not transition_id:
                print(
                    f"Erro: Transição para status '{status}' não encontrada. "
                    f"Transições disponíveis: {[t.get('name') for t in transitions]}",
                    file=sys.stderr,
                )
                return False

            # Fazer a transição (incluir fields se o workflow exigir)
            payload: Dict[str, Any] = {"transition": {"id": transition_id}}
            if fields:
                payload["fields"] = fields

        except RuntimeError as e:
            print(
                f"Erro ao obter transições para issue '{issue_key}': {e}",
                file=sys.stderr,
            )
            return False

        # Tentar transição com retry
        for attempt in range(max_retries):
            try:
                self._make_request(
                    "POST",
                    f"issue/{issue_key}/transitions",
                    json_data=payload,
                    timeout=15,
                )
                return True
            except RuntimeError as e:
                error_msg = str(e)
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue
                print(
                    f"Erro ao transicionar para '{status}': {error_msg}",
                    file=sys.stderr,
                )
                raise RuntimeError(error_msg) from e
            except Exception as e:
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue
                err_str = str(e)
                print(
                    f"Erro ao transicionar para '{status}': {err_str}",
                    file=sys.stderr,
                )
                raise RuntimeError(err_str) from e

        return False

    @staticmethod
    def _extract_issue_key(output: str) -> str:
        """Extrai a chave da issue do output (legado, mantido para compatibilidade)"""
        pattern = r"([A-Z]{1,20}-\d+)"
        match = re.search(pattern, output)
        return match.group(1) if match else ""

    @staticmethod
    def _extract_issue_url(output: str) -> str:
        """Extrai a URL da issue do output (legado, mantido para compatibilidade)"""
        pattern = r"(https://[^\s]+)"
        match = re.search(pattern, output)
        return match.group(1) if match else ""

    @staticmethod
    def _format_duration_minutes(minutes: int) -> str:
        """
        Converte minutos (int) para formato de duração (ex: "1h 30m")

        Args:
            minutes: Duração em minutos (30, 60, 90, etc.)

        Returns:
            String formatada (ex: "30m", "1h", "1h 30m", "2h")
        """
        if minutes < 60:
            return f"{minutes}m"

        hours = minutes // 60
        remaining_minutes = minutes % 60

        if remaining_minutes == 0:
            return f"{hours}h"
        else:
            return f"{hours}h {remaining_minutes}m"

    def register_worklog(
        self,
        issue_key: str,
        time_spent: str,
        started: str,
        timezone: str = "UTC",
        comment: Optional[str] = None,
    ) -> bool:
        """
        Registra worklog em uma issue usando Jira REST API

        Args:
            issue_key: Chave da issue (ex: PLATFORM-123)
            time_spent: Tempo gasto (ex: "1h 30m", "30m")
            started: Data/hora de início no formato "YYYY-MM-DD HH:MM:SS"
            timezone: Timezone no formato IANA (ex: "America/Sao_Paulo", default: "UTC")
            comment: Comentário opcional sobre o worklog

        Returns:
            True se registrado com sucesso
        """
        # Converter time_spent para segundos
        time_spent_seconds = self._parse_time_spent_to_seconds(time_spent)

        # Converter started para formato ISO 8601 com timezone
        started_iso = self._format_started_iso(started, timezone)

        # Construir payload JSON conforme documentação REST API v3
        # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-worklogs/#api-rest-api-3-issue-issueidorkey-worklog-post
        # Campos obrigatórios: timeSpentSeconds, started
        # Campo opcional: comment
        # NÃO incluir timeSpent (apenas timeSpentSeconds é necessário)
        payload: Dict[str, Any] = {
            "timeSpentSeconds": time_spent_seconds,
            "started": started_iso,
        }

        if comment:
            # Comentário em formato ADF (Atlassian Document Format)
            payload["comment"] = {
                "type": "doc",
                "version": 1,
                "content": [
                    {
                        "type": "paragraph",
                        "content": [{"type": "text", "text": comment}],
                    }
                ],
            }

        # Log do payload para debug
        from src.utils.debug import debug_log

        debug_log(
            "JiraClient",
            "register_worklog",
            "Payload completo: %s",
            json.dumps(payload, indent=2, ensure_ascii=False),
        )

        try:
            response = self._make_request(
                "POST", f"issue/{issue_key}/worklog", json_data=payload, timeout=15
            )
            return response.status_code == 201
        except RuntimeError as e:
            print(f"Erro ao registrar worklog: {e}", file=sys.stderr)
            return False
        except Exception as e:
            print(f"Erro inesperado ao registrar worklog: {str(e)}", file=sys.stderr)
            return False

    def get_issue_worklogs(
        self, issue_key: str, start_at: int = 0, max_results: int = 100
    ) -> List[Dict[str, Any]]:
        """
        Obtém worklogs de uma issue (GET /rest/api/3/issue/{key}/worklog).

        Args:
            issue_key: Chave da issue (ex: PLATFORM-123)
            start_at: Índice inicial para paginação
            max_results: Máximo de worklogs por página

        Returns:
            Lista de dicts com: id, author (accountId, displayName, emailAddress),
            timeSpentSeconds, started, comment (markdown).
        """
        if not issue_key:
            return []
        all_worklogs: List[Dict[str, Any]] = []
        start = start_at
        while True:
            params = {"startAt": start, "maxResults": min(max_results, 100)}
            try:
                response = self._make_request(
                    "GET",
                    f"issue/{issue_key}/worklog",
                    params=params,
                    timeout=30,
                )
                data = response.json()
            except RuntimeError as e:
                print(
                    f"Erro ao buscar worklogs da issue '{issue_key}': {e}",
                    file=sys.stderr,
                )
                return all_worklogs if all_worklogs else []
            except json.JSONDecodeError as e:
                print(
                    f"Erro ao decodificar JSON de worklogs: {e}",
                    file=sys.stderr,
                )
                return all_worklogs if all_worklogs else []
            worklogs = data.get("worklogs") or []
            total = data.get("total", 0)
            for w in worklogs:
                author = w.get("author") or {}
                body_raw = w.get("comment")
                if isinstance(body_raw, dict):
                    body_md = JiraClient._adf_to_markdown(body_raw)
                else:
                    body_md = str(body_raw) if body_raw else ""
                all_worklogs.append(
                    {
                        "id": str(w.get("id", "")),
                        "author": {
                            "accountId": author.get("accountId", ""),
                            "displayName": author.get("displayName", ""),
                            "emailAddress": author.get("emailAddress", ""),
                        },
                        "timeSpentSeconds": w.get("timeSpentSeconds", 0),
                        "started": w.get("started", ""),
                        "comment": body_md,
                    }
                )
            if start + len(worklogs) >= total:
                break
            start += len(worklogs)
            if not worklogs:
                break
        return all_worklogs

    def search_issues_with_worklogs_in_period(
        self,
        start_date: date,
        end_date: date,
        user_email: str,
        max_results: int = 500,
    ) -> List[Dict[str, Any]]:
        """
        Busca issues com worklogs do usuário em um período via JQL.

        Args:
            start_date: Data de início do período
            end_date: Data de fim do período
            user_email: Email do usuário (worklogAuthor)
            max_results: Número máximo de issues

        Returns:
            Lista de issues (estrutura da REST API).
        """
        jql = (
            f'worklogAuthor = "{user_email}" '
            f'AND worklogDate >= "{start_date.isoformat()}" '
            f'AND worklogDate <= "{end_date.isoformat()}"'
        )
        return self.search_issues(jql, max_results=max_results)

    def _parse_time_spent_to_seconds(self, time_spent: str) -> int:
        """Converte time_spent (ex: "1h 30m") para segundos"""
        total_seconds = 0
        # Padrão: "1h 30m" ou "30m" ou "2h"
        hour_match = re.search(r"(\d+)h", time_spent)
        minute_match = re.search(r"(\d+)m", time_spent)

        if hour_match:
            total_seconds += int(hour_match.group(1)) * 3600
        if minute_match:
            total_seconds += int(minute_match.group(1)) * 60

        return total_seconds

    def _format_started_iso(self, started: str, timezone: str) -> str:
        """
        Converte started (YYYY-MM-DD HH:MM:SS) para ISO 8601 com timezone
        Exemplo: "2025-01-20 09:30:00" + "America/Sao_Paulo" -> "2025-01-20T09:30:00.000-0300"
        """
        try:
            from datetime import datetime
            import pytz

            # Parsear data/hora
            dt = datetime.strptime(started, "%Y-%m-%d %H:%M:%S")

            # Aplicar timezone
            tz = pytz.timezone(timezone)
            dt_tz = tz.localize(dt)

            # Formatar como ISO 8601
            return dt_tz.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + dt_tz.strftime("%z")
        except Exception as e:
            print(f"Erro ao formatar data/hora para worklog: {str(e)}", file=sys.stderr)
            # Fallback: retornar formato simples sem timezone
            return started.replace(" ", "T") + ".000+0000"

    # -------------------------------------------------------------------------
    # Métodos de busca
    # -------------------------------------------------------------------------

    def search_issues(self, jql: str, max_results: int = 50) -> List[Dict[str, Any]]:
        """
        Busca issues usando JQL via REST API

        Args:
            jql: Consulta JQL.
            max_results: Número máximo de issues a retornar.

        Returns:
            Lista de issues (cada item é um dict com a estrutura da REST API).
        """
        # Body da requisição (POST)
        payload = {
            "jql": jql,
            "maxResults": min(max_results, 100),  # API limita a 100 por request
            "fields": [
                "key",
                "summary",
                "status",
                "issuetype",
                "assignee",
                "parent",
                "description",
                "priority",
            ],
        }

        try:
            response = self._make_request(
                "POST", "search/jql", json_data=payload, timeout=30
            )
            data = response.json()

            # REST API retorna issues em data["issues"]
            issues = data.get("issues", [])

            # Se precisar de mais resultados, fazer paginação com nextPageToken
            next_page_token = data.get("nextPageToken")
            while next_page_token and len(issues) < max_results:
                payload["nextPageToken"] = next_page_token
                payload["maxResults"] = min(max_results - len(issues), 100)

                try:
                    page_response = self._make_request(
                        "POST", "search/jql", json_data=payload, timeout=30
                    )
                    page_data = page_response.json()
                    page_issues = page_data.get("issues", [])
                    issues.extend(page_issues)
                    next_page_token = page_data.get("nextPageToken")
                    if not page_issues:  # Se não retornou issues, parar
                        break
                except RuntimeError:
                    # Se falhar na paginação, retornar o que já temos
                    break

            return issues[:max_results] if max_results else issues

        except RuntimeError as e:
            print(
                f"Erro ao buscar issues com JQL '{jql}': {e}",
                file=sys.stderr,
            )
            return []
        except json.JSONDecodeError as e:
            print(
                f"Erro ao decodificar JSON da resposta: {e}",
                file=sys.stderr,
            )
            return []
        except Exception as e:
            print(
                f"Erro inesperado ao buscar issues: {str(e)}",
                file=sys.stderr,
            )
            return []

    def search_epics(
        self,
        project: str,
        query: str = "",
        max_results: int = 50,
        created_by_me: bool = False,
        assigned_to_me: bool = False,
        project_filter: Optional[str] = None,
        exclude_done: bool = True,
        next_page_token: Optional[str] = None,
    ) -> Tuple[List[Dict[str, Any]], Optional[str]]:
        """
        Busca epics de um projeto opcionalmente filtrando por texto, key e filtros adicionais.

        Args:
            project: Chave do projeto (ex: PLATFORM). Usado como fallback se project_filter não for fornecido.
            query: Texto livre para filtrar summary ou key da issue (opcional).
            max_results: Número máximo de epics por página.
            created_by_me: Se True, filtra apenas epics criados pelo usuário atual.
            assigned_to_me: Se True, filtra apenas epics atribuídos ao usuário atual.
            project_filter: Chave do projeto para filtrar (ex: PLATFORM). Se None, usa project.
            exclude_done: Se True, exclui epics com status DONE.
            next_page_token: Token para buscar próxima página (paginação).

        Returns:
            Tuple com (lista de epics, nextPageToken ou None)
        """
        import os

        # Construir JQL base
        jql_parts = ["issuetype = Epic"]

        # Filtro de projeto
        # Se project_filter foi explicitamente passado (não None), usar ele
        # Se project_filter é None, não adicionar filtro de projeto (buscar em todos)
        # project (parâmetro) é usado apenas como fallback se project_filter não for fornecido na chamada
        if project_filter is not None:
            jql_parts.append(f'project = "{project_filter}"')
        # Se project_filter é None, não adicionamos filtro de projeto (busca em todos os projetos)

        # Filtro: criados por mim
        if created_by_me:
            current_user = self.get_current_user()
            if current_user:
                jql_parts.append(f'reporter = "{current_user}"')

        # Filtro: direcionados a mim
        if assigned_to_me:
            current_user = self.get_current_user()
            if current_user:
                jql_parts.append(f'assignee = "{current_user}"')

        # Filtro: excluir épicos concluídos (DONE)
        if exclude_done:
            jql_parts.append("statusCategory != Done")

        # Busca por query (key exata ou summary com wildcard)
        if query:
            query_stripped = query.strip()
            # Verificar se a query parece ser uma key de issue (formato: PROJECT-123)
            if re.match(r"^[A-Z]{1,20}-\d+$", query_stripped):
                # Buscar por key exata
                jql_parts.append(f'key = "{query_stripped}"')
            else:
                # Buscar por summary com wildcard no fim
                jql_parts.append(f'summary ~ "{query_stripped}*"')

        # Construir JQL final
        base_jql = " AND ".join(jql_parts)

        # Body da requisição (POST)
        payload = {
            "jql": base_jql,
            "maxResults": min(max_results, 100),  # API limita a 100 por request
            "fields": ["key", "summary", "status", "issuetype", "assignee", "reporter"],
        }

        # Adicionar nextPageToken se fornecido
        if next_page_token:
            payload["nextPageToken"] = next_page_token

        try:
            response = self._make_request(
                "POST", "search/jql", json_data=payload, timeout=30
            )
            data = response.json()

            # REST API retorna issues em data["issues"]
            issues = data.get("issues", [])

            # Retornar também o nextPageToken para paginação
            next_token = data.get("nextPageToken")

            return issues, next_token

        except RuntimeError as e:
            print(
                f"Erro ao buscar epics com JQL '{base_jql}': {e}",
                file=sys.stderr,
            )
            return [], None
        except json.JSONDecodeError as e:
            print(
                f"Erro ao decodificar JSON da resposta: {e}",
                file=sys.stderr,
            )
            return [], None
        except Exception as e:
            print(
                f"Erro inesperado ao buscar epics: {str(e)}",
                file=sys.stderr,
            )
            return [], None

    def get_my_issues(
        self,
        assignee_email: str,
        max_results: int = 100,
        extra_jql: str = "",
        query: str = "",
    ) -> List[Dict[str, Any]]:
        """
        Lista issues atribuídas a um usuário, opcionalmente filtrando por texto ou key.

        Args:
            assignee_email: Email do assignee.
            max_results: Número máximo de issues.
            extra_jql: Trecho adicional de JQL para filtrar (ex: 'AND statusCategory != Done').
            query: Texto livre para filtrar summary ou key da issue (opcional).

        Returns:
            Lista de issues (estrutura da REST API).
        """
        jql = f'assignee = "{assignee_email}" AND issuetype = Task'

        # Adicionar filtro de busca se fornecido
        if query:
            query_stripped = query.strip()
            # Usar campo 'summary' para busca no resumo da issue
            # O operador ~ faz busca parcial (LIKE) e é case-insensitive
            # Nota: JQL só permite wildcard no final, então usamos "texto*" para busca parcial
            # Formato: summary ~ "texto*" para buscar palavras que começam com "texto", case-insensitive
            jql += f' AND summary ~ "{query_stripped}*"'

        if extra_jql:
            # Garante que comece com AND ou OR se for um filtro adicional
            extra = extra_jql.strip()
            if not extra.upper().startswith(("AND ", "OR ")):
                extra = " AND " + extra
            # Sempre adicionar espaço antes do extra para garantir separação correta
            jql += " " + extra

        return self.search_issues(jql, max_results=max_results)

    def get_issue_details(
        self,
        issue_key: str,
        extra_fields: Optional[List[str]] = None,
    ) -> Optional[Dict[str, Any]]:
        """
        Busca dados completos de uma issue específica usando REST API.
        Otimizado para buscar apenas os campos necessários.

        Args:
            issue_key: Chave da issue (ex: PLATFORM-123)
            extra_fields: IDs adicionais de campos (ex.: customfield_24569 para Asset)

        Returns:
            Dict com dados completos da issue (estrutura fields) ou None se não encontrada
        """
        if not issue_key:
            return None

        # Campos necessários: summary, description, status, parent (com summary), priority,
        # attachment (lista de anexos da issue), e campos customizados
        fields_list = [
            "summary",
            "description",
            "status",
            "parent",
            "priority",
            "attachment",
            "customfield_12088",  # tipo_atividade
            "customfield_14840",  # documentacao_anexa
            "customfield_14841",  # utilizacao_ia
        ]
        if extra_fields:
            seen = set(fields_list)
            for f in extra_fields:
                if f and f.strip() and f not in seen:
                    seen.add(f)
                    fields_list.append(f)

        params = {
            "fields": ",".join(fields_list),
            "expand": "parent.fields.summary",
        }

        try:
            response = self._make_request(
                "GET", f"issue/{issue_key}", params=params, timeout=30
            )
            data = response.json()

            # REST API retorna dados em data["fields"]
            # Retornar estrutura compatível com o que era esperado
            if "fields" in data:
                # Incluir também key e id no topo para compatibilidade
                result = {
                    "key": data.get("key", issue_key),
                    "id": data.get("id"),
                    **data["fields"],
                }
                return result
            return None

        except RuntimeError as e:
            error_msg = str(e)
            print(
                f"Erro ao buscar issue '{issue_key}': {error_msg}",
                file=sys.stderr,
            )
            return None
        except json.JSONDecodeError as e:
            print(
                f"Erro ao decodificar JSON da issue '{issue_key}': {e}",
                file=sys.stderr,
            )
            return None
        except Exception as e:
            print(
                f"Erro inesperado ao buscar issue '{issue_key}': {str(e)}",
                file=sys.stderr,
            )
            return None

    def get_development_info(self, issue_id: str) -> Optional[Dict[str, Any]]:
        """
        Busca informações de development (branches, pull requests) vinculados à issue.

        Usa o endpoint /rest/dev-status/latest/issue/details.
        Requer issue_id (numérico) obtido de get_issue_details (campo "id"), não issueKey.

        Args:
            issue_id: ID interno da issue (numérico, ex.: "1739865"), obtido de get_issue_details.

        Returns:
            Dict com "branches" e "pullRequests" (listas normalizadas para QML), ou None/{} em
            caso de erro ou quando não houver dados (404/403 ou resposta vazia).
        """
        if not issue_id:
            return None
        url = f"{self._server_url.rstrip('/')}/rest/dev-status/latest/issue/details"
        params = {"issueId": str(issue_id)}
        try:
            auth = self._get_auth()
            response = requests.get(
                url,
                params=params,
                auth=auth,
                headers={"Accept": "application/json"},
                timeout=15,
            )
            if response.status_code in (403, 404):
                return {}
            response.raise_for_status()
            data = response.json()
            try:
                from src.utils.debug import debug_log

                data_str = json.dumps(data, ensure_ascii=False)[:500]
                debug_log(
                    "JiraClient",
                    "get_development_info",
                    "issue_id=%s status=%s data_keys=%s sample=%s",
                    issue_id,
                    response.status_code,
                    list(data.keys()) if isinstance(data, dict) else "non-dict",
                    data_str,
                )
            except ImportError:
                pass
            return self._parse_development_data(data)
        except requests.RequestException as e:
            try:
                from src.utils.debug import debug_log

                debug_log(
                    "JiraClient",
                    "get_development_info",
                    "Erro ao obter development info (issueId=%s): %s",
                    issue_id,
                    str(e),
                )
            except ImportError:
                pass
            return {}
        except Exception as e:
            try:
                from src.utils.debug import debug_log

                debug_log(
                    "JiraClient",
                    "get_development_info",
                    "Erro ao parsear development info: %s",
                    str(e),
                )
            except ImportError:
                pass
            return {}

    def _parse_development_data(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Normaliza a resposta do dev-status para estrutura fixa (camelCase para QML)."""
        branches: List[Dict[str, Any]] = []
        pull_requests: List[Dict[str, Any]] = []
        repo_names_seen: set = set()
        repositories: List[Dict[str, Any]] = []
        # Formato dev-status/latest: detail[] com branches e pullRequests direto
        detail_list = data.get("detail") or data.get("details") or []
        try:
            from src.utils.debug import debug_log

            debug_log(
                "JiraClient",
                "_parse_development_data",
                "detail_count=%s",
                len(detail_list),
            )
        except ImportError:
            pass

        def _add_branch(b: Dict[str, Any], repo_name: str) -> None:
            last_commit = b.get("lastCommit") or {}
            ts = last_commit.get("timestamp")
            last_commit_time = ""
            if ts is not None:
                try:
                    from datetime import datetime

                    dt = datetime.fromtimestamp(int(ts) / 1000)
                    last_commit_time = dt.isoformat()
                except (ValueError, OSError):
                    pass
            branches.append(
                {
                    "name": (b.get("name") or "").strip(),
                    "url": (b.get("url") or "").strip(),
                    "repository": repo_name,
                    "commitsAhead": int(b.get("aheadCount", 0) or 0),
                    "commitsBehind": int(b.get("behindCount", 0) or 0),
                    "lastCommitTime": last_commit_time,
                    "lastCommitMessage": (last_commit.get("message") or "").strip(),
                    "lastCommitAuthor": (last_commit.get("author") or {}).get(
                        "name", ""
                    ),
                }
            )

        def _add_pull_request(pr: Dict[str, Any]) -> None:
            src = pr.get("source") or {}
            dest = pr.get("destination") or {}
            author_obj = pr.get("author") or {}
            pr_id = pr.get("id") or ""
            number = pr_id.split("/")[-1] if "/" in pr_id else pr_id
            created_ts = pr.get("createdDate")
            updated_ts = pr.get("updatedDate")
            created_at = self._format_dev_timestamp(created_ts)
            updated_at = self._format_dev_timestamp(updated_ts)
            pull_requests.append(
                {
                    "number": str(number),
                    "title": (pr.get("name") or "").strip(),
                    "url": (pr.get("url") or "").strip(),
                    "state": (pr.get("status") or "open").lower(),
                    "sourceBranch": (src.get("branch") or "").strip(),
                    "targetBranch": (dest.get("branch") or "").strip(),
                    "createdAt": created_at,
                    "updatedAt": updated_at,
                    "author": (author_obj.get("name") or "").strip(),
                }
            )

        for detail in detail_list:
            for b in detail.get("branches") or []:
                repo_obj = b.get("repository") or {}
                repo_name = (
                    repo_obj.get("name") if isinstance(repo_obj, dict) else ""
                ) or ""
                if repo_name and repo_name not in repo_names_seen:
                    repo_names_seen.add(repo_name)
                    repositories.append({"name": repo_name})
                _add_branch(b, repo_name)
            for pr in detail.get("pullRequests") or []:
                _add_pull_request(pr)
        return {
            "branches": branches,
            "pullRequests": pull_requests,
            "repositories": repositories,
        }

    def _format_dev_timestamp(self, ts: Any) -> str:
        """Formata timestamp do dev-status (ms) para string ISO ou vazio."""
        if ts is None:
            return ""
        try:
            from datetime import datetime

            return datetime.fromtimestamp(int(ts) / 1000).isoformat()
        except (ValueError, OSError, TypeError):
            return ""

    def get_issue_comments(
        self, issue_key: str, start_at: int = 0, max_results: int = 100
    ) -> tuple:
        """
        Busca uma página de comentários da issue (GET /rest/api/3/issue/{key}/comment).
        Uma única requisição por chamada; converte body ADF para markdown.

        Args:
            issue_key: Chave da issue (ex: PLATFORM-123)
            start_at: Índice inicial para paginação
            max_results: Máximo de comentários por página

        Returns:
            Tuplo (comments, total): lista de dicts normalizados (id, author, body, created, updated)
            e total devolvido pela API. Em erro devolve ([], 0).
        """
        if not issue_key:
            return ([], 0)
        params = {"startAt": start_at, "maxResults": max_results}
        try:
            response = self._make_request(
                "GET",
                f"issue/{issue_key}/comment",
                params=params,
                timeout=30,
            )
            data = response.json()
        except RuntimeError as e:
            print(
                f"Erro ao buscar comentários da issue '{issue_key}': {e}",
                file=sys.stderr,
            )
            return ([], 0)
        except json.JSONDecodeError as e:
            print(
                f"Erro ao decodificar JSON de comentários: {e}",
                file=sys.stderr,
            )
            return ([], 0)
        comments_raw = data.get("comments") or []
        total = data.get("total", 0)
        comments: List[Dict[str, Any]] = []
        for c in comments_raw:
            author = c.get("author") or {}
            body_raw = c.get("body")
            if isinstance(body_raw, dict):
                body_md = JiraClient._adf_to_markdown(body_raw)
            else:
                body_md = str(body_raw) if body_raw else ""
            comments.append(
                {
                    "id": str(c.get("id", "")),
                    "author": {
                        "accountId": author.get("accountId", ""),
                        "displayName": author.get("displayName", ""),
                    },
                    "body": body_md,
                    "created": c.get("created", ""),
                    "updated": c.get("updated", ""),
                }
            )
        return (comments, total)

    def get_latest_issue_comment(self, issue_key: str) -> tuple:
        """
        Devolve apenas o comentário mais recente da issue e o total.
        Faz duas requisições: uma para obter total, outra para o último comentário.

        Returns:
            Tuplo (comment_dict ou None, total). (None, 0) se não houver comentários ou em erro.
        """
        if not issue_key:
            return (None, 0)
        comments_first, total = self.get_issue_comments(
            issue_key, start_at=0, max_results=1
        )
        if total == 0:
            return (None, 0)
        if total == 1 and comments_first:
            return (comments_first[0], 1)
        # total > 1: fetch last page (one item at index total-1)
        comments_last, _ = self.get_issue_comments(
            issue_key, start_at=total - 1, max_results=1
        )
        if not comments_last:
            return (None, total)
        return (comments_last[0], total)

    def _build_body_adf_with_media(self, body: str, issue_key: str) -> Dict[str, Any]:
        """Build ADF for body/comment with attachment URLs embedded as media."""
        from core.adf_media import (
            AttachmentInfo,
            build_description_adf_with_media,
        )

        details = self.get_issue_details(issue_key)
        issue_id = str(details.get("id", "")) if details else ""
        if not issue_id:
            return self._text_to_adf(body)
        default_width = None
        if self._config_manager is not None:
            default_width = self._config_manager.get_embed_max_display_width()
        attachments_map: Dict[str, AttachmentInfo] = {}
        for m in _RE_ATTACHMENT_URL_EXTRACT.finditer(body):
            att_id = m.group(1)
            width_override = default_width
            rest = body[m.end() : m.end() + 80]
            w_match = _RE_ATTR_WIDTH.match(rest)
            if w_match:
                width_override = int(w_match.group(1))
            if att_id not in attachments_map:
                attachments_map[att_id] = AttachmentInfo(
                    id=att_id,
                    filename="",
                    mime_type="",
                    size=0,
                    collection_id=issue_id,
                    display_width=width_override,
                )
        return build_description_adf_with_media(
            body,
            attachments_map,
            issue_id,
            self._server_url or "",
            self._text_to_adf,
        )

    def add_comment(
        self, issue_key: str, body_markdown: str
    ) -> Optional[Dict[str, Any]]:
        """
        Adiciona um comentário à issue (POST .../comment). Body em ADF.

        Args:
            issue_key: Chave da issue
            body_markdown: Conteúdo em markdown (convertido para ADF)

        Returns:
            Comentário criado normalizado (id, author, body markdown, created, updated)
            ou None em erro.
        """
        if not issue_key:
            return None
        body = body_markdown.strip() if body_markdown else ""
        adf = self._text_to_adf(body)
        embed_enabled = (
            self._config_manager is not None
            and self._config_manager.get_attachment_embed_enabled()
        )
        has_attachment_urls = bool(_RE_ATTACHMENT_URL_DETECT.search(body))
        if embed_enabled and has_attachment_urls and body:
            adf = self._build_body_adf_with_media(body, issue_key)
        payload = {"body": adf}
        try:
            response = self._make_request(
                "POST",
                f"issue/{issue_key}/comment",
                json_data=payload,
                timeout=30,
            )
            data = response.json()
        except (RuntimeError, json.JSONDecodeError) as e:
            print(
                f"Erro ao adicionar comentário em '{issue_key}': {e}",
                file=sys.stderr,
            )
            return None
        author = data.get("author") or {}
        body_raw = data.get("body")
        if isinstance(body_raw, dict):
            body_md = JiraClient._adf_to_markdown(body_raw)
        else:
            body_md = str(body_raw) if body_raw else ""
        return {
            "id": str(data.get("id", "")),
            "author": {
                "accountId": author.get("accountId", ""),
                "displayName": author.get("displayName", ""),
            },
            "body": body_md,
            "created": data.get("created", ""),
            "updated": data.get("updated", ""),
        }

    def update_comment(
        self, issue_key: str, comment_id: str, body_markdown: str
    ) -> Optional[Dict[str, Any]]:
        """
        Atualiza um comentário (PUT .../comment/{id}). Body em ADF.

        Returns:
            Comentário atualizado normalizado ou None em erro.
        """
        if not issue_key or not comment_id:
            return None
        body = body_markdown.strip() if body_markdown else ""
        adf = self._text_to_adf(body)
        embed_enabled = (
            self._config_manager is not None
            and self._config_manager.get_attachment_embed_enabled()
        )
        has_attachment_urls = bool(_RE_ATTACHMENT_URL_DETECT.search(body))
        if embed_enabled and has_attachment_urls and body:
            adf = self._build_body_adf_with_media(body, issue_key)
        payload = {"body": adf}
        try:
            response = self._make_request(
                "PUT",
                f"issue/{issue_key}/comment/{comment_id}",
                json_data=payload,
                timeout=30,
            )
            data = response.json()
        except (RuntimeError, json.JSONDecodeError) as e:
            print(
                f"Erro ao atualizar comentário {comment_id}: {e}",
                file=sys.stderr,
            )
            return None
        author = data.get("author") or {}
        body_raw = data.get("body")
        if isinstance(body_raw, dict):
            body_md = JiraClient._adf_to_markdown(body_raw)
        else:
            body_md = str(body_raw) if body_raw else ""
        return {
            "id": str(data.get("id", "")),
            "author": {
                "accountId": author.get("accountId", ""),
                "displayName": author.get("displayName", ""),
            },
            "body": body_md,
            "created": data.get("created", ""),
            "updated": data.get("updated", ""),
        }

    def delete_comment(self, issue_key: str, comment_id: str) -> bool:
        """
        Remove um comentário (DELETE .../comment/{id}). Resposta 204.

        Returns:
            True se sucesso, False em erro.
        """
        if not issue_key or not comment_id:
            return False
        try:
            self._make_request(
                "DELETE",
                f"issue/{issue_key}/comment/{comment_id}",
                timeout=30,
            )
            return True
        except RuntimeError as e:
            print(
                f"Erro ao excluir comentário {comment_id}: {e}",
                file=sys.stderr,
            )
            return False
