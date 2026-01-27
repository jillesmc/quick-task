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
        # Importar debug_log aqui para evitar dependência circular
        try:
            from src.utils.debug import debug_log
        except ImportError:
            # Se não conseguir importar (pode acontecer durante inicialização), usar print
            def debug_log(module, func, msg, *args):
                pass
        
        if not self.config_path.exists():
            # Em vez de falhar, criar um dict vazio e logar aviso
            # Isso permite que a aplicação inicie mesmo sem config
            import sys
            debug_log("ConfigManager", "load_config", "Arquivo de configuração não encontrado: %s", self.config_path)
            print(
                f"Erro ao carregar configuração: Arquivo de configuração não encontrado: {self.config_path}",
                file=sys.stderr
            )
            self._config = {}
            return

        debug_log("ConfigManager", "load_config", "Carregando configuração de: %s", self.config_path)
        try:
            with open(self.config_path, "r", encoding="utf-8") as f:
                self._config = json.load(f)
            debug_log("ConfigManager", "load_config", "Configuração carregada com sucesso")
        except json.JSONDecodeError as e:
            import sys
            debug_log("ConfigManager", "load_config", "Erro ao decodificar JSON: %s", e)
            print(
                f"Erro ao decodificar JSON: {e}",
                file=sys.stderr
            )
            self._config = {}
            return
        except Exception as e:
            import sys
            debug_log("ConfigManager", "load_config", "Erro ao carregar configuração: %s", e)
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
                debug_log("ConfigManager", "load_config", "Configuração validada com sucesso")
            except (ValueError, KeyError) as e:
                import sys
                debug_log("ConfigManager", "load_config", "Aviso: Configuração incompleta: %s", e)
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
        que deve ser inferido do usuário atual (via .jira-config.yml)
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
        # REST API usa IDs diretos de campos customizados (customfield_XXXXX)
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

    def get_retroactive_max_hours(self) -> int:
        """Retorna horas máximas permitidas para worklog retroativo (default: 24)"""
        worklog_config = self._config.get("worklog", {})
        return worklog_config.get("retroactive_max_hours", 24)

    def get_default_durations(self) -> List[int]:
        """Retorna lista de durações padrão em minutos (default: [30, 60, 120, 240, 480])"""
        worklog_config = self._config.get("worklog", {})
        return worklog_config.get("default_durations", [30, 60, 120, 240, 480])

    def get_pomodoro_config(self) -> Dict[str, Any]:
        """
        Retorna configuração completa de Pomodoro
        
        Returns:
            Dict com todas as configurações de Pomodoro e valores padrão
        """
        default_config = {
            "enabled": True,
            "pomodoro_duration_minutes": 25,
            "short_break_minutes": 5,
            "long_break_minutes": 15,
            "pomodoros_before_long_break": 4,
            "auto_continue_timeout_seconds": 30,
            "notifications": {
                "enabled": True,
                "sound_enabled": False,
                "desktop_notifications": True,
                "short_sound_file": "short",
                "long_sound_file": "long",
            },
        }
        pomodoro_config = self._config.get("pomodoro", {})
        # Mesclar com defaults para garantir que todos os campos existam
        result = default_config.copy()
        result.update(pomodoro_config)
        # Mesclar também as notificações
        if "notifications" in pomodoro_config:
            result["notifications"] = {**default_config["notifications"], **pomodoro_config["notifications"]}
        return result

    def save_pomodoro_config(self, pomodoro_config: Dict[str, Any]) -> None:
        """
        Salva configurações de Pomodoro no arquivo de configuração.
        
        Args:
            pomodoro_config: Dict com as configurações de Pomodoro a salvar
        
        Nota: No Flatpak, sempre salva em XDG_CONFIG_HOME para evitar erro de "read-only file system"
        """
        # Atualizar configuração em memória
        self._config["pomodoro"] = pomodoro_config
        
        # Se o config_path atual está em /app (somente leitura no Flatpak), usar XDG_CONFIG_HOME
        if str(self.config_path).startswith("/app/"):
            xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
            self.config_path = Path(xdg_config) / "jira-quick-task" / "config.json"
        
        # Garantir que o diretório existe
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Salvar no arquivo
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
                # Forçar sincronização do sistema de arquivos
                import os
                if hasattr(f, 'fileno'):
                    try:
                        os.fsync(f.fileno())
                    except OSError:
                        pass  # Ignorar se não suportado
            # Recarregar do arquivo para garantir sincronização
            self.load_config()
        except Exception as e:
            raise RuntimeError(f"Erro ao salvar configuração de Pomodoro: {e}") from e

    def get_jira_cli_config_path(self) -> Optional[Path]:
        """
        Retorna o caminho do arquivo de configuração do Jira (.jira-config.yml)
        
        Retorna o caminho do arquivo de configuração .jira-config.yml.
        Usado para obter server URL, email e token para autenticação REST API.
        
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
        
        # Se o config_path atual está em /app (somente leitura no Flatpak), usar XDG_CONFIG_HOME
        if str(self.config_path).startswith("/app/"):
            xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
            self.config_path = Path(xdg_config) / "jira-quick-task" / "config.json"
        
        # Garantir que o diretório existe
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Salvar no arquivo
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
        except Exception as e:
            raise RuntimeError(f"Erro ao salvar configuração: {e}") from e

    def set_account_id(self, account_id: str) -> None:
        """
        Salva o accountId do usuário no arquivo de configuração.
        
        Args:
            account_id: accountId do usuário a salvar
        
        Nota: No Flatpak, sempre salva em XDG_CONFIG_HOME para evitar erro de "read-only file system"
        """
        # Atualizar configuração em memória
        self._config["account_id"] = account_id
        
        # Se o config_path atual está em /app (somente leitura no Flatpak), usar XDG_CONFIG_HOME
        if str(self.config_path).startswith("/app/"):
            xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
            self.config_path = Path(xdg_config) / "jira-quick-task" / "config.json"
        
        # Garantir que o arquivo existe
        if not self.config_path.exists():
            # Criar diretório se não existir
            self.config_path.parent.mkdir(parents=True, exist_ok=True)
            # Criar arquivo vazio
            self._config = {}
        
        # Salvar no arquivo
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
        except Exception as e:
            raise RuntimeError(f"Erro ao salvar accountId: {e}") from e

    def save_jira_config(self, server: str, login: str, token: str) -> None:
        """
        Salva configurações de conexão Jira no arquivo .jira-config.yml
        
        Args:
            server: URL do servidor Jira
            login: Email do usuário
            token: Token de API do Jira
        
        Nota: No Flatpak, sempre salva em XDG_CONFIG_HOME (~/.var/app/.../config/)
              para evitar erro de "read-only file system" em /app
        """
        import yaml
        import shutil

        # SEMPRE usar XDG_CONFIG_HOME para salvar (especialmente importante no Flatpak)
        # No Flatpak, XDG_CONFIG_HOME aponta para ~/.var/app/org.kde.jira-quick-task/config/
        xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
        config_dir = Path(xdg_config) / "jira-quick-task"
        config_dir.mkdir(parents=True, exist_ok=True)
        jira_config_path = config_dir / ".jira-config.yml"
        
        # Se não existir, criar a partir do template
        if not jira_config_path.exists():
            # Encontrar template
            template_paths = [
                Path("/app/share/jira-quick-task/config/.jira-config.yml.example"),  # Flatpak
                Path(__file__).parent / ".jira-config.yml.example",  # Local (relativo ao módulo)
            ]
            
            template_found = None
            for template_path in template_paths:
                if template_path.exists():
                    template_found = template_path
                    break
            
            if template_found:
                shutil.copy2(template_found, jira_config_path)
            else:
                # Criar arquivo básico se template não existir
                with open(jira_config_path, "w", encoding="utf-8") as f:
                    yaml.dump({
                        "login": "",
                        "server": "",
                        "token": "",
                    }, f, default_flow_style=False)

        # Ler YAML atual
        try:
            with open(jira_config_path, "r", encoding="utf-8") as f:
                config = yaml.safe_load(f) or {}
        except Exception:
            config = {}

        # Atualizar campos
        config["server"] = server.rstrip('/')
        config["login"] = login
        config["token"] = token

        # Preservar outros campos (board, epic, issue, timezone, etc.)
        # Os campos que não são server/login/token são preservados automaticamente

        # Salvar YAML
        try:
            with open(jira_config_path, "w", encoding="utf-8") as f:
                yaml.safe_dump(config, f, default_flow_style=False, sort_keys=False)
            
            # Definir permissões restritas (chmod 600)
            try:
                os.chmod(jira_config_path, 0o600)
            except Exception:
                pass  # Ignorar erro de permissões se não for possível
        except Exception as e:
            raise RuntimeError(f"Erro ao salvar .jira-config.yml: {e}") from e
