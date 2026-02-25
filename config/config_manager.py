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

    def _get_example_config_path(self) -> Optional[Path]:
        """Retorna o path do config.json.example (template); None se não existir."""
        flatpak_example = Path("/app/share/jira-quick-task/config/config.json.example")
        if flatpak_example.exists():
            return flatpak_example
        module_example = Path(__file__).parent / "config.json.example"
        if module_example.exists():
            return module_example
        return None

    def _load_voice_input_from_example(self) -> Dict[str, Any]:
        """Carrega a secção voice_input do config.json.example. Retorna {} se falhar."""
        path = self._get_example_config_path()
        if not path:
            return {}
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            voice = data.get("voice_input")
            return dict(voice) if isinstance(voice, dict) else {}
        except Exception:
            return {}

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

            debug_log(
                "ConfigManager",
                "load_config",
                "Arquivo de configuração não encontrado: %s",
                self.config_path,
            )
            print(
                f"Erro ao carregar configuração: Arquivo de configuração não encontrado: {self.config_path}",
                file=sys.stderr,
            )
            self._config = {}
            # Garantir defaults de assets em memória mesmo sem arquivo (evita ql_ve/ql_pa None no Flatpak)
            self._ensure_assets_defaults()
            return

        debug_log(
            "ConfigManager",
            "load_config",
            "Carregando configuração de: %s",
            self.config_path,
        )
        try:
            with open(self.config_path, "r", encoding="utf-8") as f:
                self._config = json.load(f)
            debug_log(
                "ConfigManager", "load_config", "Configuração carregada com sucesso"
            )
            # Garantir que "assets" exista com object_type_id_* (evita ql_ve/ql_pa None no Flatpak)
            self._ensure_assets_defaults()
        except json.JSONDecodeError as e:
            import sys

            debug_log("ConfigManager", "load_config", "Erro ao decodificar JSON: %s", e)
            print(f"Erro ao decodificar JSON: {e}", file=sys.stderr)
            self._config = {}
            return
        except Exception as e:
            import sys

            debug_log(
                "ConfigManager", "load_config", "Erro ao carregar configuração: %s", e
            )
            print(f"Erro ao carregar configuração: {e}", file=sys.stderr)
            self._config = {}
            return

        # Validação básica (só se tiver conteúdo)
        if self._config:
            try:
                self._validate_config()
                debug_log(
                    "ConfigManager", "load_config", "Configuração validada com sucesso"
                )
            except (ValueError, KeyError) as e:
                import sys

                debug_log(
                    "ConfigManager",
                    "load_config",
                    "Aviso: Configuração incompleta: %s",
                    e,
                )
                print(f"Aviso: Configuração incompleta: {e}", file=sys.stderr)
                # Continuar com config parcial

    def _ensure_assets_defaults(self) -> None:
        """
        Garante que _config tenha "assets" com object_type_id_* quando ausentes,
        para que a query AQL seja montada (evita ql_ve/ql_pa None no Flatpak
        quando o config do usuário foi criado sem o bloco assets).
        Só preenche em memória; não grava no disco (o usuário pode editar depois).
        """
        try:
            from src.utils.debug import debug_log
        except ImportError:

            def debug_log(*_args, **_kwargs):
                pass  # no-op quando src.utils.debug não disponível (ex.: testes/init)

        if "assets" not in self._config or not isinstance(self._config["assets"], dict):
            self._config["assets"] = {
                "cloud_id": None,
                "object_type_id_valor_entregue": 434,
                "object_type_id_plataformas_afetadas": 441,
                "object_type_valor_entregue": None,
                "object_type_plataformas_afetadas": None,
            }
            debug_log(
                "ConfigManager",
                "_ensure_assets_defaults",
                "Bloco assets ausente/inválido: definido em memória com object_type_id 434 e 441",
            )
            return
        assets = self._config["assets"]
        # Valor entregue: se nem ID nem nome estão preenchidos, usar ID padrão
        if assets.get("object_type_id_valor_entregue") is None and not assets.get(
            "object_type_valor_entregue"
        ):
            assets["object_type_id_valor_entregue"] = 434
            debug_log(
                "ConfigManager",
                "_ensure_assets_defaults",
                "object_type_id_valor_entregue ausente: definido 434 em memória",
            )
        # Plataformas: idem
        if assets.get("object_type_id_plataformas_afetadas") is None and not assets.get(
            "object_type_plataformas_afetadas"
        ):
            assets["object_type_id_plataformas_afetadas"] = 441
            debug_log(
                "ConfigManager",
                "_ensure_assets_defaults",
                "object_type_id_plataformas_afetadas ausente: definido 441 em memória",
            )

    def save_config(self) -> bool:
        """Persiste a configuração atual no arquivo JSON. Retorna True se salvou com sucesso."""
        try:
            # No Flatpak, config em /app é somente leitura; redirecionar para XDG
            if str(self.config_path).startswith("/app/"):
                xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
                self.config_path = Path(xdg_config) / "jira-quick-task" / "config.json"
            self.config_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
            return True
        except Exception:
            return False

    def set_custom_field(self, field_name: str, field_id: str) -> None:
        """Define o ID de um campo customizado em custom_fields (em memória). Use save_config() para persistir."""
        if "custom_fields" not in self._config:
            self._config["custom_fields"] = {}
        self._config["custom_fields"][field_name] = field_id

    def set_assets_config(
        self,
        cloud_id: Optional[str] = None,
        object_type_valor_entregue: Optional[str] = None,
        object_type_plataformas_afetadas: Optional[str] = None,
        object_type_id_valor_entregue: Optional[int] = None,
        object_type_id_plataformas_afetadas: Optional[int] = None,
    ) -> None:
        """Define opções de Assets (em memória). Use save_config() para persistir."""
        if "assets" not in self._config:
            self._config["assets"] = {}
        if cloud_id is not None:
            self._config["assets"]["cloud_id"] = cloud_id
        if object_type_valor_entregue is not None:
            self._config["assets"][
                "object_type_valor_entregue"
            ] = object_type_valor_entregue
        if object_type_plataformas_afetadas is not None:
            self._config["assets"][
                "object_type_plataformas_afetadas"
            ] = object_type_plataformas_afetadas
        if object_type_id_valor_entregue is not None:
            self._config["assets"][
                "object_type_id_valor_entregue"
            ] = object_type_id_valor_entregue
        if object_type_id_plataformas_afetadas is not None:
            self._config["assets"][
                "object_type_id_plataformas_afetadas"
            ] = object_type_id_plataformas_afetadas

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
        """Retorna a sequência de status (novo workflow: TO DO → IN PROGRESS → DONE)."""
        raw = self._config.get("status_sequence", [])
        if not raw:
            return ["TO DO", "IN PROGRESS", "DONE"]
        # Migração: se a config ainda tiver o workflow antigo (IN DEVELOPMENT), usar o novo
        if any((s or "").strip().upper() == "IN DEVELOPMENT" for s in raw):
            return ["TO DO", "IN PROGRESS", "DONE"]
        return raw

    def get_valor_entregue_values(self) -> List[str]:
        """Retorna a lista de valores para Valor Entregue"""
        return self._config.get("valor_entregue_values", [])

    def get_plataformas_afetadas_values(self) -> List[str]:
        """Retorna a lista de valores para Plataformas afetadas"""
        return self._config.get("plataformas_afetadas_values", [])

    def get_assets_cloud_id(self) -> Optional[str]:
        """
        Retorna o cloudId da instância Jira Cloud para chamadas à API de Assets em api.atlassian.com.
        Opcional: se não configurado, a listagem de objetos Asset não será possível.
        O usuário pode obter o cloudId via OAuth accessible-resources ou documentação Atlassian.
        """
        assets = self._config.get("assets") or {}
        if isinstance(assets, dict):
            return assets.get("cloud_id") or None
        return None

    def get_assets_object_type_valor_entregue(self) -> Optional[str]:
        """Nome do object type AQL para Valor entregue (ex.: 'TipoValor'). Opcional."""
        assets = self._config.get("assets") or {}
        if isinstance(assets, dict):
            return assets.get("object_type_valor_entregue") or None
        return None

    def get_assets_object_type_plataformas(self) -> Optional[str]:
        """Nome do object type AQL para Plataformas afetadas (ex.: 'Plataforma'). Opcional."""
        assets = self._config.get("assets") or {}
        if isinstance(assets, dict):
            return assets.get("object_type_plataformas_afetadas") or None
        return None

    def get_assets_object_type_id_valor_entregue(self) -> Optional[int]:
        """ID do object type para Valor entregue (ex.: 434). Preferível ao nome, pois não muda se o nome for alterado."""
        assets = self._config.get("assets") or {}
        if not isinstance(assets, dict):
            return None
        val = assets.get("object_type_id_valor_entregue")
        if val is None:
            return None
        try:
            return int(val)
        except (TypeError, ValueError):
            return None

    def get_assets_object_type_id_plataformas(self) -> Optional[int]:
        """ID do object type para Plataformas afetadas (ex.: 441). Preferível ao nome."""
        assets = self._config.get("assets") or {}
        if not isinstance(assets, dict):
            return None
        val = assets.get("object_type_id_plataformas_afetadas")
        if val is None:
            return None
        try:
            return int(val)
        except (TypeError, ValueError):
            return None

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

    def get_attachment_max_size_mb(self) -> int:
        """Retorna tamanho máximo de anexo em MB (default: 10)."""
        attachments = self._config.get("attachments", {})
        return attachments.get("max_file_size_mb", 10)

    def get_attachments_embed_enabled(self) -> bool:
        """Retorna se o embed de imagens/vídeos na descrição está habilitado."""
        attachments = self._config.get("attachments", {})
        embed = (
            attachments.get("embed")
            if isinstance(attachments.get("embed"), dict)
            else {}
        )
        return bool(embed.get("enabled", False))

    def get_allowed_attachment_extensions(self) -> List[str]:
        """
        Retorna lista de extensões permitidas para anexos (imagens + documentos).
        Valores default: png, jpg, jpeg, gif, webp, pdf, txt, md, json, yaml, xml, log.
        """
        attachments = self._config.get("attachments", {})
        images = attachments.get(
            "allowed_image_extensions",
            ["png", "jpg", "jpeg", "gif", "webp"],
        )
        documents = attachments.get(
            "allowed_document_extensions",
            ["pdf", "txt", "md", "json", "yaml", "xml", "log"],
        )
        seen = set()
        result = []
        for ext in images + documents:
            e = (ext or "").lower().lstrip(".")
            if e and e not in seen:
                seen.add(e)
                result.append(e)
        return result if result else ["png", "jpg", "jpeg", "gif", "webp"]

    def get_allowed_image_extensions(self) -> List[str]:
        """
        Retorna lista de extensões consideradas imagem (para preview/embed).
        Usado para decidir quando abrir o diálogo de preview vs inserir como link.
        Valores default: png, jpg, jpeg, gif, webp.
        """
        attachments = self._config.get("attachments", {})
        images = attachments.get(
            "allowed_image_extensions",
            ["png", "jpg", "jpeg", "gif", "webp"],
        )
        seen = set()
        result = []
        for ext in images:
            e = (ext or "").lower().lstrip(".")
            if e and e not in seen:
                seen.add(e)
                result.append(e)
        return result if result else ["png", "jpg", "jpeg", "gif", "webp"]

    def get_embed_max_display_width(self) -> int:
        """Retorna largura máxima de exibição para imagens embedadas (default: 760)."""
        attachments = self._config.get("attachments", {})
        embed = (
            attachments.get("embed")
            if isinstance(attachments.get("embed"), dict)
            else {}
        )
        images = (
            embed.get("images")
            if isinstance(embed.get("images"), dict)
            else {}
        )
        val = images.get("max_display_width")
        if val is None:
            return 760
        try:
            return max(100, min(2000, int(val)))
        except (TypeError, ValueError):
            return 760

    def get_attachment_embed_enabled(self) -> bool:
        """Retorna se o embed de anexos está habilitado (default: True se config presente)."""
        embed = (self._config.get("attachments") or {}).get("embed")
        if not isinstance(embed, dict):
            return True
        return embed.get("enabled", True)

    def get_embed_default_layout(self) -> str:
        """Retorna o layout padrão para imagens embed (default: center)."""
        images = ((self._config.get("attachments") or {}).get("embed") or {}).get(
            "images"
        )
        if not isinstance(images, dict):
            return "center"
        return str(images.get("default_layout", "center"))

    def get_embed_max_display_width(self) -> int:
        """Retorna a largura máxima de exibição para imagens embed (default: 760)."""
        images = ((self._config.get("attachments") or {}).get("embed") or {}).get(
            "images"
        )
        if not isinstance(images, dict):
            return 760
        val = images.get("max_display_width", 760)
        try:
            return int(val)
        except (TypeError, ValueError):
            return 760

    def get_voice_input_config(self) -> Dict[str, Any]:
        """
        Retorna configuração completa de entrada por voz.
        Valores padrão vêm de config.json.example; o config.json do utilizador sobrepõe.
        Se existir ollama_* e não existir localai_*, preenche localai_* a partir de ollama_* (migração).
        """
        defaults = self._load_voice_input_from_example()
        voice_config = self._config.get("voice_input")
        if not isinstance(voice_config, dict):
            return dict(defaults)
        result = dict(defaults)
        result.update({k: v for k, v in voice_config.items() if k != "whisper_model"})
        # Migração: se config antiga tem ollama_* e não tem localai_*, preencher localai_* a partir de ollama_*
        if "localai_base_url" not in voice_config and voice_config.get(
            "ollama_base_url"
        ):
            result["localai_base_url"] = voice_config["ollama_base_url"]
            result["localai_whisper_model"] = voice_config.get(
                "ollama_whisper_model"
            ) or defaults.get("localai_whisper_model", "")
            result["localai_llm_model"] = voice_config.get(
                "ollama_llm_model"
            ) or defaults.get("localai_llm_model", "")
        return result

    def get_voice_input_enabled(self) -> bool:
        """Retorna se a entrada por voz está habilitada (valor do arquivo)."""
        return bool(self.get_voice_input_config().get("enabled", False))

    def get_localai_base_url(self) -> str:
        """Retorna a URL base do LocalAI (valor do arquivo)."""
        return str(self.get_voice_input_config().get("localai_base_url") or "")

    def get_localai_whisper_model(self) -> str:
        """Retorna o modelo Whisper do LocalAI (valor do arquivo)."""
        return str(self.get_voice_input_config().get("localai_whisper_model") or "")

    def get_localai_llm_model(self) -> str:
        """Retorna o modelo LLM do LocalAI (valor do arquivo)."""
        return str(self.get_voice_input_config().get("localai_llm_model") or "")

    def get_localai_task_system_prompt(self) -> str:
        """Retorna o pré-prompt de sistema para extração de task (valor do arquivo)."""
        return str(
            self.get_voice_input_config().get("localai_task_system_prompt") or ""
        )

    def get_localai_comment_improvement_prompt(self) -> str:
        """Retorna o pré-prompt para melhoria de texto de comentários (valor do arquivo)."""
        return str(
            self.get_voice_input_config().get("localai_comment_improvement_prompt")
            or ""
        )

    def get_voice_input_language(self) -> str:
        """Retorna o idioma para transcrição (valor do arquivo)."""
        return str(self.get_voice_input_config().get("language") or "")

    def get_voice_input_max_recording_seconds(self) -> int:
        """Retorna duração máxima de gravação em segundos (valor do arquivo)."""
        return int(self.get_voice_input_config().get("max_recording_seconds") or 0)

    def get_voice_input_keyboard_shortcut(self) -> str:
        """Retorna o atalho de teclado (valor do arquivo)."""
        return str(self.get_voice_input_config().get("keyboard_shortcut") or "")

    def get_voice_input_auto_process_after_stop(self) -> bool:
        """Retorna se deve processar transcrição automaticamente ao parar gravação (valor do arquivo)."""
        return bool(self.get_voice_input_config().get("auto_process_after_stop", False))

    def get_voice_input_microphone_device(self) -> Optional[str]:
        """Retorna o dispositivo de microfone (valor do arquivo)."""
        dev = self.get_voice_input_config().get("microphone_device")
        return str(dev) if dev else None

    def save_voice_input_config(self, voice_config: Dict[str, Any]) -> None:
        """
        Salva configurações de entrada por voz no arquivo de configuração.

        Args:
            voice_config: Dict com as configurações de voice_input a salvar
        """
        self._config["voice_input"] = voice_config
        if str(self.config_path).startswith("/app/"):
            xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
            self.config_path = Path(xdg_config) / "jira-quick-task" / "config.json"
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
            self.load_config()
        except Exception as e:
            raise RuntimeError(
                f"Erro ao salvar configuração de voice_input: {e}"
            ) from e

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
                "return_from_break_sound_file": None,
            },
        }
        pomodoro_config = self._config.get("pomodoro", {})
        # Mesclar com defaults para garantir que todos os campos existam
        result = default_config.copy()
        result.update(pomodoro_config)
        # Mesclar também as notificações
        if "notifications" in pomodoro_config:
            result["notifications"] = {
                **default_config["notifications"],
                **pomodoro_config["notifications"],
            }
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
                # Forçar sincronização do sistema de arquivos (os já importado no topo do módulo)
                if hasattr(f, "fileno"):
                    try:
                        os.fsync(f.fileno())
                    except OSError:
                        pass  # Ignorar se não suportado
            # Recarregar do arquivo para garantir sincronização
            self.load_config()
        except Exception as e:
            raise RuntimeError(f"Erro ao salvar configuração de Pomodoro: {e}") from e

    def get_google_drive_comments_config(self) -> Dict[str, Any]:
        """
        Retorna configuração de comentários do Google Drive (Issue #18).

        Returns:
            Dict com enabled, max_comments, unresolved_only
        """
        default_config = {
            "enabled": True,
            "max_comments": 50,
            "unresolved_only": True,
        }
        google_config = self._config.get("google") or {}
        if not isinstance(google_config, dict):
            return default_config
        drive_comments = google_config.get("drive_comments") or {}
        if not isinstance(drive_comments, dict):
            return default_config
        result = dict(default_config)
        result.update({k: v for k, v in drive_comments.items() if k in result})
        return result

    def save_google_drive_comments_config(
        self, drive_comments_config: Dict[str, Any]
    ) -> None:
        """
        Salva configurações de drive_comments (google.drive_comments) no arquivo.
        """
        if "google" not in self._config or not isinstance(self._config["google"], dict):
            self._config["google"] = {}
        self._config["google"]["drive_comments"] = drive_comments_config
        if str(self.config_path).startswith("/app/"):
            xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
            self.config_path = Path(xdg_config) / "jira-quick-task" / "config.json"
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
                if hasattr(f, "fileno"):
                    try:
                        os.fsync(f.fileno())
                    except OSError:
                        pass
            self.load_config()
        except Exception as e:
            raise RuntimeError(
                f"Erro ao salvar configuração de drive_comments: {e}"
            ) from e

    def get_worklog_check_config(self) -> Dict[str, Any]:
        """
        Retorna configuração de verificação de worklogs ao transitar status.

        Returns:
            Dict com enabled, show_confirmation_dialog, block_transition_if_pending
        """
        default_config = {
            "enabled": True,
            "show_confirmation_dialog": True,
            "block_transition_if_pending": False,
        }
        status_transitions = self._config.get("status_transitions") or {}
        worklog_check = status_transitions.get("worklog_check") or {}
        if not isinstance(worklog_check, dict):
            return default_config
        result = dict(default_config)
        result.update({k: v for k, v in worklog_check.items() if k in result})
        return result

    def save_worklog_check_config(self, worklog_check_config: Dict[str, Any]) -> None:
        """
        Salva configurações de worklog_check no arquivo de configuração.
        """
        if "status_transitions" not in self._config:
            self._config["status_transitions"] = {}
        self._config["status_transitions"]["worklog_check"] = worklog_check_config
        if str(self.config_path).startswith("/app/"):
            xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
            self.config_path = Path(xdg_config) / "jira-quick-task" / "config.json"
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
            self.load_config()
        except Exception as e:
            raise RuntimeError(
                f"Erro ao salvar configuração de worklog_check: {e}"
            ) from e

    def worklog_check_enabled(self) -> bool:
        """Retorna se a verificação de worklogs pendentes está habilitada."""
        return bool(self.get_worklog_check_config().get("enabled", True))

    def worklog_check_show_dialog(self) -> bool:
        """Retorna se deve mostrar diálogo de confirmação quando houver pendentes."""
        return bool(
            self.get_worklog_check_config().get("show_confirmation_dialog", True)
        )

    def worklog_check_block_if_pending(self) -> bool:
        """Retorna se deve bloquear transição (apenas Sincronizar ou Cancelar)."""
        return bool(
            self.get_worklog_check_config().get("block_transition_if_pending", False)
        )

    def get_development_panel_config(self) -> Dict[str, Any]:
        """
        Retorna configuração do painel de Development (Minhas Issues).

        Returns:
            Dict com enabled, github_enrichment (defaults True e False).
        """
        default_config = {
            "enabled": True,
            "github_enrichment": False,
            "default_org": "",
        }
        dev_panel = self._config.get("development_panel") or {}
        if not isinstance(dev_panel, dict):
            return default_config
        result = dict(default_config)
        result.update({k: v for k, v in dev_panel.items() if k in result})
        return result

    def save_development_panel_config(
        self, development_panel_config: Dict[str, Any]
    ) -> None:
        """
        Salva configurações do painel de Development no arquivo de configuração.
        """
        self._config["development_panel"] = development_panel_config
        if str(self.config_path).startswith("/app/"):
            xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
            self.config_path = Path(xdg_config) / "jira-quick-task" / "config.json"
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
            self.load_config()
        except Exception as e:
            raise RuntimeError(
                f"Erro ao salvar configuração de development_panel: {e}"
            ) from e

    def development_panel_enabled(self) -> bool:
        """Retorna se o painel de Development está habilitado."""
        return bool(self.get_development_panel_config().get("enabled", True))

    def development_panel_github_enrichment(self) -> bool:
        """Retorna se o enriquecimento de PRs com dados do GitHub está habilitado."""
        return bool(self.get_development_panel_config().get("github_enrichment", False))

    def development_panel_default_org(self) -> str:
        """Org ou usuário GitHub para restringir a busca de repositórios no diálogo Criar branch."""
        return str(
            self.get_development_panel_config().get("default_org", "") or ""
        ).strip()

    def get_timesheet_config(self) -> Dict[str, Any]:
        """
        Retorna configuração do Timesheet.

        Returns:
            Dict com enabled, cache_ttl_minutes, default_period, max_results
        """
        default_config = {
            "enabled": True,
            "cache_ttl_minutes": 5,
            "default_period": "last_7_days",
            "max_results": 500,
        }
        timesheet = self._config.get("timesheet") or {}
        if not isinstance(timesheet, dict):
            return default_config
        result = dict(default_config)
        result.update({k: v for k, v in timesheet.items() if k in result})
        return result

    def save_timesheet_config(self, timesheet_config: Dict[str, Any]) -> None:
        """Salva configurações do Timesheet no arquivo de configuração."""
        self._config["timesheet"] = timesheet_config
        if str(self.config_path).startswith("/app/"):
            xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
            self.config_path = Path(xdg_config) / "jira-quick-task" / "config.json"
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
            self.load_config()
        except Exception as e:
            raise RuntimeError(f"Erro ao salvar configuração do Timesheet: {e}") from e

    def get_github_token(self) -> str:
        """Retorna o token de API do GitHub a partir do config.json (github.token). Única fonte."""
        return (self._config.get("github") or {}).get("token", "")

    def get_github_username(self) -> str:
        """Retorna o username do GitHub a partir do config.json (github.username)."""
        return (self._config.get("github") or {}).get("username", "")

    def get_github_token_from_config(self) -> str:
        """Retorna o token GitHub do config.json (github.token). Mesmo que get_github_token."""
        return self.get_github_token()

    def save_github_config(self, token: str, username: str) -> None:
        """
        Salva configurações GitHub no config.json (seção github).
        No Flatpak, salva em XDG_CONFIG_HOME.
        """
        if "github" not in self._config:
            self._config["github"] = {}
        self._config["github"]["token"] = token
        self._config["github"]["username"] = username
        if str(self.config_path).startswith("/app/"):
            xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
            self.config_path = Path(xdg_config) / "jira-quick-task" / "config.json"
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
            self.load_config()
        except Exception as e:
            raise RuntimeError(f"Erro ao salvar configuração GitHub: {e}") from e

    def get_google_oauth_config(self) -> Dict[str, str]:
        """Retorna a configuração Google OAuth do config.json (google_oauth)."""
        section = self._config.get("google_oauth") or {}
        return {
            "client_id": section.get("client_id", ""),
            "project_id": section.get("project_id", ""),
            "client_secret": section.get("client_secret", ""),
        }

    def save_google_oauth_config(
        self, client_id: str, project_id: str, client_secret: str
    ) -> None:
        """
        Salva configurações Google OAuth no config.json (seção google_oauth).
        No Flatpak, salva em XDG_CONFIG_HOME.
        """
        if "google_oauth" not in self._config:
            self._config["google_oauth"] = {}
        self._config["google_oauth"]["client_id"] = client_id
        self._config["google_oauth"]["project_id"] = project_id
        self._config["google_oauth"]["client_secret"] = client_secret
        if str(self.config_path).startswith("/app/"):
            xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
            self.config_path = Path(xdg_config) / "jira-quick-task" / "config.json"
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
            self.load_config()
        except Exception as e:
            raise RuntimeError(f"Erro ao salvar configuração Google OAuth: {e}") from e

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
            return (
                (self.config_path.parent / config_path)
                if (self.config_path.parent / config_path).exists()
                else None
            )

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
        flatpak_example = Path(
            "/app/share/jira-quick-task/config/.jira-config.yml.example"
        )
        if flatpak_example.exists():
            return flatpak_example

        return None

    def get_jira_login(self) -> str:
        """
        Retorna o email de login do Jira a partir do .jira-config.yml.
        Usado para timesheet (worklogAuthor no JQL).
        """
        path = self.get_jira_cli_config_path()
        if not path or not path.exists():
            return ""
        try:
            import yaml

            with open(path, "r", encoding="utf-8") as f:
                config = yaml.safe_load(f) or {}
                return str(config.get("login", "") or "").strip()
        except Exception:
            return ""

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
                Path(
                    "/app/share/jira-quick-task/config/.jira-config.yml.example"
                ),  # Flatpak
                Path(__file__).parent
                / ".jira-config.yml.example",  # Local (relativo ao módulo)
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
                    yaml.dump(
                        {
                            "login": "",
                            "server": "",
                            "token": "",
                        },
                        f,
                        default_flow_style=False,
                    )

        # Ler YAML atual
        try:
            with open(jira_config_path, "r", encoding="utf-8") as f:
                config = yaml.safe_load(f) or {}
        except Exception:
            config = {}

        # Atualizar campos
        config["server"] = server.rstrip("/")
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
