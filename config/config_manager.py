"""
Gerenciador de configuração para Jira Quick Task
"""

import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional


class ConfigManager:
    """Gerencia o carregamento e acesso à configuração"""

    def __init__(self, config_path: Optional[Path] = None):
        """
        Inicializa o gerenciador de configuração

        Args:
            config_path: Caminho para o arquivo de configuração.
                        Se None, procura em múltiplos locais:
                        1. ~/.config/jira-quick-task/config.json (usuário)
                        2. /app/share/jira-quick-task/config/config.json (Flatpak)
                        3. config/config.json relativo ao módulo (fallback)
        """
        if config_path is None:
            config_path = self._find_config_file()
        
        self.config_path = Path(config_path)
        self._config: Dict[str, Any] = {}
        self.load_config()

    def _find_config_file(self) -> Path:
        """
        Procura o arquivo config.json em múltiplos locais
        
        Returns:
            Path do arquivo encontrado ou do fallback (pode não existir)
        """
        # 1. Configuração do usuário (XDG_CONFIG_HOME)
        xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
        user_config = Path(xdg_config) / "jira-quick-task" / "config.json"
        if user_config.exists():
            return user_config
        
        # 2. Configuração padrão do Flatpak
        flatpak_config = Path("/app/share/jira-quick-task/config/config.json")
        if flatpak_config.exists():
            return flatpak_config
        
        # 2b. Fallback: arquivo .example no Flatpak
        flatpak_example = Path("/app/share/jira-quick-task/config/config.json.example")
        if flatpak_example.exists():
            return flatpak_example
        
        # 3. Fallback: relativo ao módulo
        module_dir = Path(__file__).parent
        return module_dir / "config.json"

    def load_config(self) -> None:
        """Carrega a configuração do arquivo JSON"""
        if not self.config_path.exists():
            # Em vez de falhar, criar um dict vazio e logar aviso
            # Isso permite que a aplicação inicie mesmo sem config
            import sys
            print(
                f"Erro ao carregar configuração: Arquivo de configuração não encontrado: {self.config_path}",
                file=sys.stderr
            )
            self._config = {}
            return

        try:
            with open(self.config_path, "r", encoding="utf-8") as f:
                self._config = json.load(f)
        except json.JSONDecodeError as e:
            import sys
            print(
                f"Erro ao decodificar JSON do arquivo de configuração: {e}",
                file=sys.stderr
            )
            self._config = {}
            return
        except Exception as e:
            import sys
            print(
                f"Erro ao carregar configuração: {e}",
                file=sys.stderr
            )
            self._config = {}
            return

        # Validação básica (só se tiver conteúdo)
        if self._config:
            try:
                self._validate_config()
            except (ValueError, KeyError) as e:
                import sys
                print(
                    f"Aviso: Configuração incompleta: {e}",
                    file=sys.stderr
                )
                # Continuar com config parcial

    def _validate_config(self) -> None:
        """Valida a estrutura básica da configuração"""
        required_keys = [
            "project",
            "issue_type",
            "custom_fields",
            "tipo_atividade_values",
            "status_sequence",
        ]

        for key in required_keys:
            if key not in self._config:
                raise ValueError(
                    f"Chave obrigatória '{key}' não encontrada na configuração"
                )
        
        # Assignee é opcional - pode ser "auto" para inferir do usuário atual
        # Se não estiver presente, será tratado como "auto"

        # Validar custom_fields
        custom_fields = self._config.get("custom_fields", {})
        required_custom_fields = [
            "tipo_atividade",
            "documentacao_anexa",
            "utilizacao_ia",
        ]
        for field in required_custom_fields:
            if field not in custom_fields:
                raise ValueError(
                    f"Campo customizado obrigatório '{field}' não encontrado"
                )

    def get(self, key: str, default: Any = None) -> Any:
        """
        Obtém um valor da configuração usando notação de ponto

        Args:
            key: Chave da configuração (ex: "project" ou "custom_fields.tipo_atividade")
            default: Valor padrão se a chave não existir

        Returns:
            Valor da configuração ou default
        """
        keys = key.split(".")
        value = self._config

        try:
            for k in keys:
                value = value[k]
            return value
        except (KeyError, TypeError):
            return default

    def get_project(self) -> str:
        """Retorna o nome do projeto"""
        return self._config.get("project", "")

    def get_issue_type(self) -> str:
        """Retorna o tipo de issue"""
        return self._config.get("issue_type", "")

    def get_assignee(self) -> Optional[str]:
        """
        Retorna o assignee padrão
        
        Se o assignee for "auto" ou None, retorna None para indicar
        que deve ser inferido do usuário atual (via ACLI ou .jira-config.yml)
        """
        assignee = self._config.get("assignee")
        if assignee in (None, "", "auto"):
            return None
        return assignee

    def get_account_id(self) -> Optional[str]:
        """
        Retorna o accountId do usuário atual salvo no config.json
        
        Returns:
            accountId do usuário ou None se não estiver configurado
        """
        return self._config.get("account_id")

    def get_custom_field(self, field_name: str) -> str:
        """
        Retorna o ID de um campo customizado

        Args:
            field_name: Nome do campo (tipo_atividade, documentacao_anexa, utilizacao_ia)

        Returns:
            ID do campo customizado (ex: customfield_12088) configurado no config.json
        """
        # Retornar o ID diretamente do config.json
        # ACLI usa IDs diretos de campos customizados (customfield_XXXXX)
        custom_fields = self._config.get("custom_fields", {})
        return custom_fields.get(field_name, "")

    def get_tipo_atividade_values(self) -> List[str]:
        """Retorna a lista de valores para Tipo de atividade"""
        return self._config.get("tipo_atividade_values", [])

    def get_status_sequence(self) -> List[str]:
        """Retorna a sequência de status"""
        return self._config.get("status_sequence", [])

    def get_timezone(self) -> str:
        """Retorna o timezone para worklog (default: America/Sao_Paulo)"""
        return self._config.get("worklog_timezone", "America/Sao_Paulo")

    def get_jira_cli_config_path(self) -> Optional[Path]:
        """
        Retorna o caminho do arquivo de configuração do Jira (.jira-config.yml)
        
        Mantido para compatibilidade. Agora usado para obter server URL e email
        para REST API (worklogs), já que ACLI usa OAuth.
        
        Se jira_cli_config estiver definido no config.json, retorna esse caminho.
        Caso contrário, tenta usar config/.jira-config.yml (arquivo real com credenciais).
        Se não existir, retorna None.
        
        Returns:
            Caminho do arquivo de configuração do Jira ou None se não configurado
        """
        # Verificar se há um caminho customizado no config.json
        custom_path = self._config.get("jira_cli_config")
        if custom_path:
            config_path = Path(custom_path)
            if config_path.is_absolute():
                return config_path if config_path.exists() else None
            # Caminho relativo ao diretório do config.json
            return (self.config_path.parent / config_path) if (self.config_path.parent / config_path).exists() else None
        
        # Caminho padrão: procurar em múltiplos locais
        # 1. No mesmo diretório do config.json
        default_path = self.config_path.parent / ".jira-config.yml"
        if default_path.exists():
            return default_path
        
        # 2. Configuração do usuário (XDG_CONFIG_HOME)
        xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
        user_config = Path(xdg_config) / "jira-quick-task" / ".jira-config.yml"
        if user_config.exists():
            return user_config
        
        # 3. Configuração padrão do Flatpak
        flatpak_config = Path("/app/share/jira-quick-task/config/.jira-config.yml")
        if flatpak_config.exists():
            return flatpak_config
        
        # 3b. Fallback: arquivo .example no Flatpak
        flatpak_example = Path("/app/share/jira-quick-task/config/.jira-config.yml.example")
        if flatpak_example.exists():
            return flatpak_example
        
        return None

    def get_epic_filters(self) -> Dict[str, bool]:
        """
        Retorna os filtros de busca de épicos salvos na configuração.
        
        Returns:
            Dict com os filtros: created_by_me, assigned_to_me, project_platform, exclude_done
        """
        default_filters = {
            "created_by_me": False,
            "assigned_to_me": False,
            "project_platform": True,
            "exclude_done": True,
        }
        epic_filters = self._config.get("epic_filters", {})
        # Mesclar com defaults para garantir que todos os campos existam
        return {**default_filters, **epic_filters}

    def set_epic_filters(self, filters: Dict[str, bool]) -> None:
        """
        Salva os filtros de busca de épicos no arquivo de configuração.
        
        Args:
            filters: Dict com os filtros a salvar (created_by_me, assigned_to_me, project_platform, exclude_done)
        """
        # Atualizar configuração em memória
        if "epic_filters" not in self._config:
            self._config["epic_filters"] = {}
        
        self._config["epic_filters"].update(filters)
        
        # Salvar no arquivo
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
        except Exception as e:
            raise RuntimeError(f"Erro ao salvar configuração: {e}") from e
