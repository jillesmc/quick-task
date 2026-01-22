"""
Cliente Jira - Wrapper para REST API v3 do Jira
"""

import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
import requests
from requests.auth import HTTPBasicAuth

# Constante para mensagem de erro padrão
_UNKNOWN_ERROR_MSG = "Erro desconhecido"


class JiraClient:
    """Cliente para interagir com Jira via REST API v3"""

    def __init__(self, jira_cli_config_path: Optional[Path] = None, account_id: Optional[str] = None):
        """
        Inicializa o cliente Jira
        
        Args:
            jira_cli_config_path: Caminho para o arquivo de configuração .jira-config.yml.
                                 Usado para obter server URL e email para autenticação REST API.
            account_id: accountId do usuário atual (opcional, obtido do config.json).
                       Se fornecido, será usado quando o assignee for o usuário atual.
        """
        self._jira_cli_config_path = jira_cli_config_path
        self._server_url = None
        self._auth_email = None
        self._account_id = account_id  # accountId do usuário atual (do config.json)
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
        Obtém server URL e email para autenticação HTTPBasicAuth.
        """
        if not self._jira_cli_config_path or not self._jira_cli_config_path.exists():
            return

        try:
            import yaml
            with open(self._jira_cli_config_path, 'r', encoding='utf-8') as f:
                config = yaml.safe_load(f)
                self._server_url = config.get('server', '').rstrip('/')
                self._auth_email = config.get('login', '')
        except Exception as e:
            print(
                f"AVISO: Erro ao carregar .jira-config.yml: {e}",
                file=sys.stderr
            )
            # Não é crítico aqui - será validado no __init__

    def _get_auth(self) -> HTTPBasicAuth:
        """
        Retorna objeto de autenticação HTTPBasicAuth para REST API
        
        Returns:
            HTTPBasicAuth com email e token
            
        Raises:
            RuntimeError: Se JIRA_API_TOKEN ou email não estiverem configurados
        """
        api_token = os.environ.get("JIRA_API_TOKEN")
        if not api_token:
            raise RuntimeError(
                "JIRA_API_TOKEN não encontrado na variável de ambiente. "
                "Configure com: export JIRA_API_TOKEN=<seu-token>"
            )
        if not self._auth_email:
            raise RuntimeError(
                "Email não encontrado na configuração (.jira-config.yml). "
                "Configure o campo 'login' no arquivo de configuração."
            )
        return HTTPBasicAuth(self._auth_email, api_token)

    def _make_request(
        self,
        method: str,
        endpoint: str,
        json_data: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
        timeout: int = 30
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
        headers = {
            "Accept": "application/json",
            "Content-Type": "application/json"
        }
        
        print(
            f"[DEBUG] _make_request: {method} {url}",
            file=sys.stderr
        )
        if json_data:
            print(
                f"[DEBUG] _make_request: JSON keys: {list(json_data.keys())}",
                file=sys.stderr
            )
        if params:
            print(
                f"[DEBUG] _make_request: Params: {params}",
                file=sys.stderr
            )
        
        try:
            response = requests.request(
                method,
                url,
                json=json_data,
                params=params,
                auth=auth,
                headers=headers,
                timeout=timeout
            )
            
            print(
                f"[DEBUG] _make_request: Response status={response.status_code}",
                file=sys.stderr
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
                            error_msg = "; ".join(error_parts) if error_parts else str(errors_dict)
                        else:
                            error_msg = str(errors_dict)
                    # Log completo do erro e payload para debug
                    print(
                        f"[DEBUG] _make_request: Erro completo: {json.dumps(error_json, indent=2)}",
                        file=sys.stderr
                    )
                    if json_data:
                        print(
                            f"[DEBUG] _make_request: Payload que causou erro: {json.dumps(json_data, indent=2)}",
                            file=sys.stderr
                        )
                except (json.JSONDecodeError, KeyError):
                    # Se não conseguir parsear JSON, mostrar texto completo
                    print(
                        f"[DEBUG] _make_request: Response text completo: {response.text}",
                        file=sys.stderr
                    )
                
                raise RuntimeError(
                    f"Erro na requisição {method} {endpoint} (HTTP {response.status_code}): {error_msg}"
                )
            
            return response
            
        except requests.exceptions.Timeout as e:
            raise RuntimeError(f"Timeout ao fazer requisição {method} {endpoint} após {timeout}s") from e
        except requests.exceptions.RequestException as e:
            raise RuntimeError(f"Erro de rede ao fazer requisição {method} {endpoint}: {str(e)}") from e

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
                file=sys.stderr
            )
            # Fallback para email do config
            return self._auth_email
        except Exception as e:
            print(
                f"Erro inesperado ao obter usuário atual: {e}. Usando email do config como fallback.",
                file=sys.stderr
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
            response = self._make_request("GET", "user/search", params=params, timeout=10)
            users = response.json()
            
            # Garantir que users é uma lista
            if not isinstance(users, list):
                print(
                    f"[DEBUG] _get_user_account_id: Resposta inesperada do user/search (não é lista): {type(users)}",
                    file=sys.stderr
                )
                return None
            
            # Procurar usuário com email correspondente
            for user in users:
                if user.get("emailAddress", "").lower() == email.strip().lower():
                    account_id = user.get("accountId")
                    if account_id:
                        print(
                            f"[DEBUG] _get_user_account_id: Encontrado accountId={account_id} para email={email}",
                            file=sys.stderr
                        )
                        return account_id
            
            # Se não encontrou por email, tentar usar o primeiro resultado se houver
            if users and len(users) > 0:
                account_id = users[0].get("accountId")
                if account_id:
                    print(
                        f"[DEBUG] _get_user_account_id: Usando primeiro resultado accountId={account_id} para email={email}",
                        file=sys.stderr
                    )
                    return account_id
            
            print(
                f"[DEBUG] _get_user_account_id: Não encontrou accountId para email={email}",
                file=sys.stderr
            )
            return None
        except RuntimeError as e:
            print(
                f"Erro ao buscar accountId para email {email}: {e}",
                file=sys.stderr
            )
            return None
        except Exception as e:
            print(
                f"Erro inesperado ao buscar accountId para email {email}: {e}",
                file=sys.stderr
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
        print(f"[DEBUG] _text_to_adf: Iniciando conversão (text_len={len(text) if text else 0})", file=sys.stderr)
        if not text or not text.strip():
            return {
                "version": 1,
                "type": "doc",
                "content": [{"type": "paragraph", "content": []}]
            }
        
        lines = text.split('\n')
        print(f"[DEBUG] _text_to_adf: Texto dividido em {len(lines)} linhas", file=sys.stderr)
        content = []
        i = 0
        in_code_block = False
        code_block_lines = []
        code_block_lang = None
        
        while i < len(lines):
            if i % 50 == 0:  # Log a cada 50 linhas para não poluir muito
                print(f"[DEBUG] _text_to_adf: Processando linha {i}/{len(lines)}", file=sys.stderr)
            line = lines[i]
            stripped = line.strip()
            
            # Bloco de código
            if stripped.startswith('```'):
                if in_code_block:
                    # Fechar bloco de código
                    if code_block_lines:
                        content.append({
                            "type": "codeBlock",
                            "attrs": {"language": code_block_lang} if code_block_lang else {},
                            "content": [{
                                "type": "text",
                                "text": "\n".join(code_block_lines)
                            }]
                        })
                    code_block_lines = []
                    code_block_lang = None
                    in_code_block = False
                else:
                    # Abrir bloco de código
                    in_code_block = True
                    lang_match = re.match(r'^```(\w+)?', stripped)
                    code_block_lang = lang_match.group(1) if lang_match else None
                i += 1
                continue
            
            if in_code_block:
                code_block_lines.append(line)
                i += 1
                continue
            
            # Título
            heading_match = re.match(r'^(#{1,6})\s+(.+)$', stripped)
            if heading_match:
                level = len(heading_match.group(1))
                heading_text = heading_match.group(2)
                content.append({
                    "type": "heading",
                    "attrs": {"level": level},
                    "content": JiraClient._parse_inline_formatting(heading_text)
                })
                i += 1
                continue
            
            # Lista ordenada
            ordered_list_match = re.match(r'^(\d+)\.\s+(.+)$', stripped)
            if ordered_list_match:
                print(f"[DEBUG] _text_to_adf: Encontrada lista ordenada na linha {i}", file=sys.stderr)
                list_items = []
                list_start = i
                while i < len(lines) and re.match(r'^\d+\.\s+', lines[i].strip()):
                    item_match = re.match(r'^\d+\.\s+(.+)$', lines[i].strip())
                    if item_match:
                        item_text = item_match.group(1)
                        list_items.append({
                            "type": "listItem",
                            "content": [{
                                "type": "paragraph",
                                "content": JiraClient._parse_inline_formatting(item_text)
                            }]
                        })
                    i += 1
                    if i - list_start > 1000:  # Proteção contra loop infinito
                        print(f"[DEBUG] _text_to_adf: AVISO - Lista ordenada muito longa, parando em {i}", file=sys.stderr)
                        break
                if list_items:
                    content.append({
                        "type": "orderedList",
                        "content": list_items
                    })
                continue
            
            # Lista não ordenada
            unordered_list_match = re.match(r'^[-*+]\s+(.+)$', stripped)
            if unordered_list_match:
                print(f"[DEBUG] _text_to_adf: Encontrada lista não ordenada na linha {i}", file=sys.stderr)
                list_items = []
                list_start = i
                while i < len(lines) and re.match(r'^[-*+]\s+', lines[i].strip()):
                    item_match = re.match(r'^[-*+]\s+(.+)$', lines[i].strip())
                    if item_match:
                        item_text = item_match.group(1)
                        list_items.append({
                            "type": "listItem",
                            "content": [{
                                "type": "paragraph",
                                "content": JiraClient._parse_inline_formatting(item_text)
                            }]
                        })
                    i += 1
                    if i - list_start > 1000:  # Proteção contra loop infinito
                        print(f"[DEBUG] _text_to_adf: AVISO - Lista não ordenada muito longa, parando em {i}", file=sys.stderr)
                        break
                if list_items:
                    content.append({
                        "type": "bulletList",
                        "content": list_items
                    })
                continue
            
            # Parágrafo normal
            if stripped:
                if len(stripped) > 1000:  # Log para parágrafos muito longos
                    print(f"[DEBUG] _text_to_adf: Processando parágrafo longo ({len(stripped)} chars) na linha {i}", file=sys.stderr)
                content.append({
                    "type": "paragraph",
                    "content": JiraClient._parse_inline_formatting(stripped)
                })
            else:
                # Linha vazia - parágrafo vazio para espaçamento
                content.append({
                    "type": "paragraph",
                    "content": []
                })
            
            i += 1
        
        # Se ainda estiver em bloco de código, fechar
        if in_code_block and code_block_lines:
            content.append({
                "type": "codeBlock",
                "attrs": {"language": code_block_lang} if code_block_lang else {},
                "content": [{
                    "type": "text",
                    "text": "\n".join(code_block_lines)
                }]
            })
        
        # Se não houver conteúdo, criar parágrafo vazio
        if not content:
            content = [{"type": "paragraph", "content": []}]
        
        print(f"[DEBUG] _text_to_adf: Conversão concluída - {len(content)} elementos no content", file=sys.stderr)
        return {
            "version": 1,
            "type": "doc",
            "content": content
        }
    
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
            print(f"[DEBUG] _parse_inline_formatting: Processando texto longo ({len(text)} chars)", file=sys.stderr)
        
        nodes = []
        i = 0
        text_len = len(text)
        iterations = 0
        max_iterations = text_len * 2  # Proteção contra loop infinito
        
        while i < text_len:
            iterations += 1
            if iterations > max_iterations:
                print(f"[DEBUG] _parse_inline_formatting: AVISO - Loop infinito detectado! i={i}, text_len={text_len}, text_resto={text[i:i+50]}", file=sys.stderr)
                # Adicionar o resto do texto como texto simples e sair
                if i < text_len:
                    nodes.append({"type": "text", "text": text[i:]})
                break
            # Link [texto](url)
            link_match = re.match(r'\[([^\]]+)\]\(([^)]+)\)', text[i:])
            if link_match:
                link_text = link_match.group(1)
                link_url = link_match.group(2)
                nodes.append({
                    "type": "text",
                    "text": link_text,
                    "marks": [{"type": "link", "attrs": {"href": link_url}}]
                })
                i += link_match.end()
                continue
            
            # Código inline `código`
            code_match = re.match(r'`([^`]+)`', text[i:])
            if code_match:
                code_text = code_match.group(1)
                nodes.append({
                    "type": "text",
                    "text": code_text,
                    "marks": [{"type": "code"}]
                })
                i += code_match.end()
                continue
            
            # Negrito **texto** ou __texto__
            bold_match = re.match(r'(\*\*|__)([^*_\n]+?)\1', text[i:])
            if bold_match:
                bold_text = bold_match.group(2)
                nodes.append({
                    "type": "text",
                    "text": bold_text,
                    "marks": [{"type": "strong"}]
                })
                i += bold_match.end()
                continue
            
            # Itálico *texto* ou _texto_ (mas não ** ou __)
            italic_match = re.match(r'(?<!\*)\*(?!\*)([^*\n]+?)\*(?!\*)|(?<!_)_(?!_)([^_\n]+?)_(?!_)', text[i:])
            if italic_match:
                italic_text = italic_match.group(1) or italic_match.group(2)
                nodes.append({
                    "type": "text",
                    "text": italic_text,
                    "marks": [{"type": "em"}]
                })
                i += italic_match.end()
                continue
            
            # Texto normal - coletar até encontrar formatação
            start = i
            # Avançar pelo menos 1 caractere para evitar loop infinito
            i += 1
            while i < text_len:
                # Verificar se há formatação à frente
                char = text[i]
                next_char = text[i+1] if i + 1 < text_len else None
                
                # Verificar padrões de formatação
                if char == '`' and next_char != '`':
                    # Código inline
                    break
                elif char == '[' and '](' in text[i:]:
                    # Link
                    break
                elif char == '*' and next_char == '*':
                    # Negrito
                    break
                elif char == '_' and next_char == '_':
                    # Negrito
                    break
                elif char in ['*', '_'] and (i == 0 or text[i-1] not in ['*', '_']):
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
                    nodes.append({"type": "text", "text": text[start:start+1]})
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

        Returns:
            Dicionário com 'issue_key' e 'issue_url'

        Raises:
            RuntimeError: Se a criação falhar
        """
        print(f"[DEBUG] create_issue: Iniciando - project={project}, type={issue_type}, summary={summary[:50]}...", file=sys.stderr)
        print(f"[DEBUG] create_issue: custom_fields={custom_fields}, parent={parent_issue_key}, assignee={assignee}", file=sys.stderr)
        
        # Construir estrutura fields para REST API
        fields: Dict[str, Any] = {
            "project": {"key": project},
            "issuetype": {"name": issue_type},
            "summary": summary,
        }
        
        # Converter description para ADF se fornecido
        if description:
            print(f"[DEBUG] create_issue: Convertendo description para ADF (tamanho={len(description)})...", file=sys.stderr)
            fields["description"] = self._text_to_adf(description)
            print(f"[DEBUG] create_issue: Conversão ADF concluída", file=sys.stderr)
        
        # Adicionar assignee se fornecido
        # REST API v3 requer accountId (não aceita emailAddress diretamente)
        if assignee and assignee.strip():
            assignee_email = assignee.strip()
            account_id = None
            
            # Se for o usuário atual (mesmo email do config), usar accountId do config se disponível
            if assignee_email.lower() == self._auth_email.lower():
                if self._account_id:
                    account_id = self._account_id
                    print(f"[DEBUG] create_issue: Usando accountId={account_id} do config.json (usuário atual)", file=sys.stderr)
                else:
                    # Fallback: buscar via /myself se não estiver no config
                    try:
                        myself_response = self._make_request("GET", "myself", timeout=10)
                        myself_data = myself_response.json()
                        account_id = myself_data.get("accountId")
                        if account_id:
                            print(f"[DEBUG] create_issue: Usando accountId={account_id} obtido via /myself (usuário atual)", file=sys.stderr)
                    except Exception as e:
                        print(f"[DEBUG] create_issue: Erro ao obter accountId via myself: {e}", file=sys.stderr)
            
            # Se não encontrou ainda, buscar via user/search
            if not account_id:
                account_id = self._get_user_account_id(assignee_email)
            
            if account_id:
                fields["assignee"] = {"accountId": account_id}
                print(f"[DEBUG] create_issue: Assignee definido com accountId={account_id} para email={assignee_email}", file=sys.stderr)
            else:
                raise RuntimeError(
                    f"Não foi possível obter accountId para o assignee '{assignee_email}'. "
                    f"A API v3 do Jira requer accountId para definir assignee."
                )
        
        # Adicionar parent se fornecido (dentro de fields)
        if parent_issue_key and parent_issue_key.strip():
            fields["parent"] = {"key": parent_issue_key.strip()}
        
        # Adicionar campos customizados em fields
        # CREATE pode aceitar string direta, mas vamos usar {"value": "text"} para consistência
        # e garantir compatibilidade com campos select list
        if custom_fields:
            for field_id, field_value in custom_fields.items():
                if field_value is not None and str(field_value).strip():
                    # Formatar como objeto com "value" para campos select list
                    # Isso garante compatibilidade tanto para CREATE quanto UPDATE
                    fields[field_id] = {"value": str(field_value).strip()}
        
        # Construir payload completo
        payload = {"fields": fields}
        
        print("[DEBUG] create_issue: Payload preparado com fields: " + str(list(fields.keys())), file=sys.stderr)
        
        try:
            response = self._make_request("POST", "issue", json_data=payload, timeout=30)
            data = response.json()
            
            print(f"[DEBUG] create_issue: Resposta recebida: {list(data.keys())}", file=sys.stderr)
            
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
                issue_url = f"https://{project.lower()}.atlassian.net/browse/{issue_key}"
            
            print(f"[DEBUG] create_issue: Issue criada com sucesso - key={issue_key}, url={issue_url}", file=sys.stderr)
            return {"issue_key": issue_key, "issue_url": issue_url}
            
        except RuntimeError as e:
            print(f"[DEBUG] create_issue: ERRO - {e}", file=sys.stderr)
            raise
        except Exception as e:
            print(f"[DEBUG] create_issue: ERRO inesperado - {e}", file=sys.stderr)
            raise RuntimeError(f"Erro inesperado ao criar issue: {str(e)}") from e

    def update_issue(
        self,
        issue_key: str,
        summary: Optional[str] = None,
        description: Optional[str] = None,
        status: Optional[str] = None,
        custom_fields: Optional[Dict[str, str]] = None,
        parent_issue_key: Optional[str] = None,
    ) -> bool:
        """
        Atualiza campos de uma issue existente usando REST API.

        Args:
            issue_key: Chave da issue (ex: PLATFORM-123)
            summary: Novo summary (opcional)
            description: Nova description (opcional)
            status: Novo status (opcional) - NÃO use aqui, use transition_issue
            custom_fields: Dicionário com campos customizados (field_id: valor) (opcional)
            parent_issue_key: Nova chave do parent (opcional, use "" para remover parent)

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
            # Se description for string vazia, usar ADF vazio
            if description.strip():
                fields["description"] = self._text_to_adf(description)
            else:
                # Description vazia - usar ADF mínimo válido
                fields["description"] = {
                    "version": 1,
                    "type": "doc",
                    "content": [{"type": "paragraph", "content": []}]
                }
        
        # Adicionar campos customizados em fields (apenas se não forem vazios)
        # Campos customizados do tipo select list precisam do formato {"value": "text"} ou {"name": "text"}
        # Conforme documentação REST API v3: "Specify a valid 'id' or 'name' for [field]"
        if custom_fields:
            for field_id, field_value in custom_fields.items():
                # Ignorar valores None ou strings vazias
                if field_value is not None and str(field_value).strip():
                    # Formatar como objeto com "value" para campos select list
                    # A API aceita {"value": "text"} ou {"name": "text"}
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
        
        # Construir payload completo - apenas fields, sem update vazio
        if not fields:
            # Se não houver nada para atualizar, retornar True
            return True
        
        payload = {"fields": fields}
        
        # Log detalhado do payload para debug
        print(
            f"[DEBUG] update_issue: Payload completo (primeiros 2000 chars):\n{json.dumps(payload, indent=2, ensure_ascii=False)[:2000]}",
            file=sys.stderr
        )
        print(
            f"[DEBUG] update_issue: Campos sendo atualizados: {list(fields.keys())}",
            file=sys.stderr
        )

        try:
            self._make_request("PUT", f"issue/{issue_key}", json_data=payload, timeout=15)
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
    ) -> bool:
        """
        Transiciona uma issue para um novo status usando REST API

        Args:
            issue_key: Chave da issue
            status: Nome do status de destino
            max_retries: Número máximo de tentativas
            retry_delay: Delay entre tentativas (segundos)

        Returns:
            True se transicionado com sucesso
        """
        # Primeiro, obter lista de transições disponíveis
        try:
            response = self._make_request("GET", f"issue/{issue_key}/transitions", timeout=15)
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
            
            # Fazer a transição
            payload = {"transition": {"id": transition_id}}
            
        except RuntimeError as e:
            print(
                f"Erro ao obter transições para issue '{issue_key}': {e}",
                file=sys.stderr,
            )
            return False

        # Tentar transição com retry
        for attempt in range(max_retries):
            try:
                self._make_request("POST", f"issue/{issue_key}/transitions", json_data=payload, timeout=15)
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
                return False
            except Exception as e:
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue
                print(
                    f"Erro ao transicionar para '{status}': {str(e)}",
                    file=sys.stderr,
                )
                return False

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
        print(
            f"[DEBUG] register_worklog: Payload completo: {json.dumps(payload, indent=2, ensure_ascii=False)}",
            file=sys.stderr
        )

        try:
            response = self._make_request("POST", f"issue/{issue_key}/worklog", json_data=payload, timeout=15)
            return response.status_code == 201
        except RuntimeError as e:
            print(f"Erro ao registrar worklog: {e}", file=sys.stderr)
            return False
        except Exception as e:
            print(f"Erro inesperado ao registrar worklog: {str(e)}", file=sys.stderr)
            return False

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
            print(
                f"Erro ao formatar data/hora para worklog: {str(e)}", file=sys.stderr
            )
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
            "fields": ["key", "summary", "status", "issuetype", "assignee", "parent", "description"]
        }

        try:
            response = self._make_request("POST", "search/jql", json_data=payload, timeout=30)
            data = response.json()
            
            # REST API retorna issues em data["issues"]
            issues = data.get("issues", [])
            
            # Se precisar de mais resultados, fazer paginação com nextPageToken
            next_page_token = data.get("nextPageToken")
            while next_page_token and len(issues) < max_results:
                payload["nextPageToken"] = next_page_token
                payload["maxResults"] = min(max_results - len(issues), 100)
                
                try:
                    page_response = self._make_request("POST", "search/jql", json_data=payload, timeout=30)
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
        jql_parts = ['issuetype = Epic']
        
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
            jql_parts.append('statusCategory != Done')
        
        # Busca por query (key exata ou summary com wildcard)
        if query:
            query_stripped = query.strip()
            # Verificar se a query parece ser uma key de issue (formato: PROJECT-123)
            if re.match(r'^[A-Z]{1,20}-\d+$', query_stripped):
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
            "fields": ["key", "summary", "status", "issuetype", "assignee", "reporter"]
        }
        
        # Adicionar nextPageToken se fornecido
        if next_page_token:
            payload["nextPageToken"] = next_page_token

        try:
            response = self._make_request("POST", "search/jql", json_data=payload, timeout=30)
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

    def get_issue_details(self, issue_key: str) -> Optional[Dict[str, Any]]:
        """
        Busca dados completos de uma issue específica usando REST API.
        Otimizado para buscar apenas os campos necessários.

        Args:
            issue_key: Chave da issue (ex: PLATFORM-123)

        Returns:
            Dict com dados completos da issue (estrutura fields) ou None se não encontrada
        """
        if not issue_key:
            return None

        # Campos necessários: summary, description, status, parent (com summary), e campos customizados
        # Para parent, precisamos solicitar também o summary usando expand
        fields_list = [
            "summary",
            "description",
            "status",
            "parent",
            "customfield_12088",  # tipo_atividade
            "customfield_14840",  # documentacao_anexa
            "customfield_14841",  # utilizacao_ia
        ]
        
        # REST API aceita campos separados por vírgula no query param
        # Usar expand para obter campos do parent (incluindo summary)
        params = {
            "fields": ",".join(fields_list),
            "expand": "parent.fields.summary"  # Expandir campos do parent para obter summary
        }

        try:
            response = self._make_request("GET", f"issue/{issue_key}", params=params, timeout=30)
            data = response.json()
            
            # REST API retorna dados em data["fields"]
            # Retornar estrutura compatível com o que era esperado
            if "fields" in data:
                # Incluir também key e id no topo para compatibilidade
                result = {
                    "key": data.get("key", issue_key),
                    "id": data.get("id"),
                    **data["fields"]
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
