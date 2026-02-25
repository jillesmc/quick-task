"""
Modelo para configuração de conexão Jira
Expõe propriedades e métodos para configurar credenciais via QML
"""

import os
import shutil
from pathlib import Path
from typing import Optional
import sys

from PySide6.QtCore import QObject, Property, Signal, Slot, QThread  # type: ignore[import]

# Adicionar diretório raiz ao path
ROOT_DIR = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT_DIR))

from config.config_manager import ConfigManager
from src.utils.debug import debug_log


class SettingsModel(QObject):
    """Modelo para configuração de conexão Jira via UI"""

    # Sinais
    saved = Signal()
    errorOccurred = Signal(str)
    accountIdFetched = Signal(str)
    fetchingAccountId = Signal()

    def __init__(self, parent=None, config_manager=None):
        super().__init__(parent)
        try:
            debug_log("SettingsModel", "__init__", "Iniciando...")
            self._config_manager = (
                config_manager if config_manager is not None else ConfigManager()
            )
            debug_log("SettingsModel", "__init__", "ConfigManager criado")
            self._jira_base_url = ""
            self._jira_email = ""
            self._jira_api_token = ""
            self._account_id = ""
            self._account_id_worker = None

            # Propriedades de Pomodoro
            self._pomodoro_enabled = True
            self._pomodoro_duration_minutes = 25
            self._short_break_minutes = 5
            self._long_break_minutes = 15
            self._pomodoros_before_long_break = 4
            self._auto_continue_timeout_seconds = 30
            self._notifications_enabled = True
            self._sound_enabled = False
            self._desktop_notifications = True
            self._short_sound_file = "short"  # Nome do arquivo sem extensão
            self._long_sound_file = "long"  # Nome do arquivo sem extensão
            self._return_from_break_sound_file = (
                ""  # Opcional: som ao voltar da pausa; vazio = não toca
            )

            # Propriedades de entrada por voz (voice_input)
            self._voice_enabled = False
            self._localai_base_url = "http://localhost:8080"
            self._localai_whisper_model = "whisper-1"
            self._localai_llm_model = "qwen2.5:3b"
            self._localai_task_system_prompt = ""
            self._localai_comment_improvement_prompt = ""
            self._voice_language = "pt"
            self._voice_max_recording_seconds = 120
            self._voice_keyboard_shortcut = "Meta+F"
            self._voice_auto_process_after_stop = False

            # Propriedades de status_transitions.worklog_check
            self._worklog_check_enabled = True
            self._worklog_check_show_dialog = True
            self._worklog_check_block_if_pending = False

            # Propriedades de development_panel (painel de Development em Minhas Issues)
            self._development_panel_enabled = True
            self._development_panel_github_enrichment = False
            self._development_panel_default_org = ""

            # Propriedades de timesheet
            self._timesheet_enabled = True
            self._timesheet_cache_ttl_minutes = 1440  # 1 dia
            self._timesheet_default_period = "last_7_days"
            self._timesheet_max_results = 500

            # Propriedades GitHub
            self._github_token = ""
            self._github_username = ""

            # Propriedades Google OAuth
            self._google_oauth_client_id = ""
            self._google_oauth_project_id = ""
            self._google_oauth_client_secret = ""

            # Propriedades Google Drive Comments (Issue #18)
            self._drive_comments_enabled = True
            self._drive_comments_max_comments = 50
            self._drive_comments_unresolved_only = True

            debug_log("SettingsModel", "__init__", "Carregando valores atuais...")
            self._load_current_values()
            debug_log("SettingsModel", "__init__", "Concluído")
        except Exception as e:
            import traceback

            print(f"SettingsModel.__init__: ERRO: {e}", file=sys.stderr)
            traceback.print_exc(file=sys.stderr)
            raise

    def _load_current_values(self):
        """Carrega valores atuais do .jira-config.yml (não lê mais variáveis de ambiente)"""
        # Carregar apenas do .jira-config.yml
        jira_config_path = self._config_manager.get_jira_cli_config_path()
        debug_log(
            "SettingsModel",
            "_load_current_values",
            "Carregando valores de .jira-config.yml",
        )
        if jira_config_path and jira_config_path.exists():
            debug_log(
                "SettingsModel",
                "_load_current_values",
                "Arquivo encontrado: %s",
                jira_config_path,
            )
            try:
                import yaml

                with open(jira_config_path, "r", encoding="utf-8") as f:
                    config = yaml.safe_load(f) or {}
                    self._jira_base_url = config.get("server", "").rstrip("/")
                    self._jira_email = config.get("login", "")
                    self._jira_api_token = config.get("token", "")
                debug_log(
                    "SettingsModel",
                    "_load_current_values",
                    "Valores carregados: URL=%s, Email=%s",
                    bool(self._jira_base_url),
                    bool(self._jira_email),
                )
            except Exception as e:
                debug_log(
                    "SettingsModel",
                    "_load_current_values",
                    "Erro ao ler .jira-config.yml: %s",
                    e,
                )
                pass  # Se não conseguir ler, usar valores vazios
        else:
            debug_log(
                "SettingsModel",
                "_load_current_values",
                "Arquivo .jira-config.yml não encontrado",
            )

        # Carregar accountId do config.json
        account_id = self._config_manager.get_account_id()
        self._account_id = account_id if account_id else ""
        debug_log(
            "SettingsModel",
            "_load_current_values",
            "AccountId carregado: %s",
            bool(self._account_id),
        )

        # Carregar configurações de Pomodoro do config.json
        pomodoro_config = self._config_manager.get_pomodoro_config()
        self._pomodoro_enabled = pomodoro_config.get("enabled", True)
        self._pomodoro_duration_minutes = pomodoro_config.get(
            "pomodoro_duration_minutes", 25
        )
        self._short_break_minutes = pomodoro_config.get("short_break_minutes", 5)
        self._long_break_minutes = pomodoro_config.get("long_break_minutes", 15)
        self._pomodoros_before_long_break = pomodoro_config.get(
            "pomodoros_before_long_break", 4
        )
        self._auto_continue_timeout_seconds = pomodoro_config.get(
            "auto_continue_timeout_seconds", 30
        )
        notifications = pomodoro_config.get("notifications", {})
        self._notifications_enabled = notifications.get("enabled", True)
        self._sound_enabled = notifications.get("sound_enabled", False)
        self._desktop_notifications = notifications.get("desktop_notifications", True)
        # Usar setters para garantir que sinais sejam emitidos e valores sejam atualizados corretamente
        self.shortSoundFile = notifications.get("short_sound_file", "short")
        self.longSoundFile = notifications.get("long_sound_file", "long")
        self.returnFromBreakSoundFile = (
            notifications.get("return_from_break_sound_file") or ""
        )
        # Carregar configurações de voice_input do config.json (localai_*; migração de ollama_* em get_voice_input_config)
        voice_config = self._config_manager.get_voice_input_config()
        self._voice_enabled = voice_config.get("enabled", False)
        self._localai_base_url = voice_config.get(
            "localai_base_url", "http://localhost:8080"
        )
        self._localai_whisper_model = voice_config.get(
            "localai_whisper_model", "whisper-1"
        )
        self._localai_llm_model = voice_config.get("localai_llm_model", "qwen2.5:3b")
        self._localai_task_system_prompt = voice_config.get(
            "localai_task_system_prompt",
            self._config_manager.get_localai_task_system_prompt(),
        )
        self._localai_comment_improvement_prompt = voice_config.get(
            "localai_comment_improvement_prompt",
            self._config_manager.get_localai_comment_improvement_prompt(),
        )
        self._voice_language = voice_config.get("language", "pt")
        self._voice_max_recording_seconds = int(
            voice_config.get("max_recording_seconds", 120)
        )
        self._voice_keyboard_shortcut = voice_config.get("keyboard_shortcut", "Meta+F")
        self._voice_auto_process_after_stop = voice_config.get(
            "auto_process_after_stop", False
        )
        # Carregar configurações de status_transitions.worklog_check
        worklog_check_config = self._config_manager.get_worklog_check_config()
        self._worklog_check_enabled = worklog_check_config.get("enabled", True)
        self._worklog_check_show_dialog = worklog_check_config.get(
            "show_confirmation_dialog", True
        )
        self._worklog_check_block_if_pending = worklog_check_config.get(
            "block_transition_if_pending", False
        )
        # Carregar configurações de development_panel
        dev_panel_config = self._config_manager.get_development_panel_config()
        self._development_panel_enabled = dev_panel_config.get("enabled", True)
        self._development_panel_github_enrichment = dev_panel_config.get(
            "github_enrichment", False
        )
        self._development_panel_default_org = (
            dev_panel_config.get("default_org", "") or ""
        ).strip()
        # Carregar configurações de timesheet
        timesheet_config = self._config_manager.get_timesheet_config()
        self._timesheet_enabled = timesheet_config.get("enabled", True)
        self._timesheet_cache_ttl_minutes = int(
            timesheet_config.get("cache_ttl_minutes", 1440)
        )
        self._timesheet_default_period = (
            timesheet_config.get("default_period", "last_7_days") or "last_7_days"
        )
        self._timesheet_max_results = int(timesheet_config.get("max_results", 500))
        # Carregar configurações GitHub do config.json
        self._github_token = self._config_manager.get_github_token_from_config()
        self._github_username = self._config_manager.get_github_username()

        # Carregar configurações Google OAuth do config.json
        goauth = self._config_manager.get_google_oauth_config()
        self._google_oauth_client_id = goauth.get("client_id", "") or ""
        self._google_oauth_project_id = goauth.get("project_id", "") or ""
        self._google_oauth_client_secret = goauth.get("client_secret", "") or ""

        drive_comments_config = self._config_manager.get_google_drive_comments_config()
        self._drive_comments_enabled = drive_comments_config.get("enabled", True)
        self._drive_comments_max_comments = drive_comments_config.get(
            "max_comments", 50
        )
        self._drive_comments_unresolved_only = drive_comments_config.get(
            "unresolved_only", True
        )

        debug_log(
            "SettingsModel",
            "_load_current_values",
            "Configurações de Pomodoro carregadas: short_sound_file=%s, long_sound_file=%s, return_from_break_sound_file=%s",
            self._short_sound_file,
            self._long_sound_file,
            self._return_from_break_sound_file or "(vazio)",
        )

    def is_configured(self) -> bool:
        """Verifica se a configuração está completa"""
        return bool(
            self._jira_base_url
            and self._jira_email
            and self._jira_api_token
            and self._account_id
        )

    def needs_configuration(self) -> bool:
        """
        Verifica se a configuração precisa ser feita

        Verifica:
        - Se arquivos de configuração existem (config.json e .jira-config.yml)
        - Se os valores estão preenchidos (server, login, token, accountId)

        Returns:
            bool: True se precisa configurar, False se está tudo configurado
        """
        # Verificar se arquivos existem
        config_exists = self._config_manager.config_path.exists()
        jira_config_path = self._config_manager.get_jira_cli_config_path()
        jira_config_exists = jira_config_path and jira_config_path.exists()

        debug_log(
            "SettingsModel",
            "needs_configuration",
            "config.json existe: %s, .jira-config.yml existe: %s",
            config_exists,
            jira_config_exists,
        )

        # Verificar se valores estão preenchidos
        has_values = bool(
            self._jira_base_url
            and self._jira_email
            and self._jira_api_token
            and self._account_id
        )

        debug_log(
            "SettingsModel",
            "needs_configuration",
            "Valores preenchidos: URL=%s, Email=%s, Token=%s, AccountId=%s",
            bool(self._jira_base_url),
            bool(self._jira_email),
            bool(self._jira_api_token),
            bool(self._account_id),
        )

        # Precisa configurar se arquivos não existem OU valores não estão preenchidos
        needs_config = not (config_exists and jira_config_exists and has_values)
        debug_log(
            "SettingsModel",
            "needs_configuration",
            "Precisa configurar: %s",
            needs_config,
        )
        return needs_config

    def _find_template_dir(self) -> Optional[Path]:
        """Encontra diretório de templates"""
        # Flatpak
        flatpak_template = Path("/app/share/jira-quick-task/config")
        if flatpak_template.exists():
            return flatpak_template

        # Local (relativo ao módulo)
        local_template = ROOT_DIR / "config"
        if local_template.exists():
            return local_template

        return None

    def _create_config_from_templates(self) -> bool:
        """
        Cria arquivos de configuração a partir de templates se não existirem

        Nota: No Flatpak, sempre cria em XDG_CONFIG_HOME para evitar erro de "read-only file system"
        """
        template_dir = self._find_template_dir()
        if not template_dir:
            return False

        # SEMPRE usar XDG_CONFIG_HOME para criar arquivos (especialmente importante no Flatpak)
        import os

        xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
        config_dir = Path(xdg_config) / "jira-quick-task"
        config_dir.mkdir(parents=True, exist_ok=True)

        # Criar .jira-config.yml se não existir
        # Usar sempre o diretório do usuário (XDG_CONFIG_HOME)
        jira_config_path = config_dir / ".jira-config.yml"
        if not jira_config_path.exists():
            template_yaml = template_dir / ".jira-config.yml.example"
            if template_yaml.exists():
                try:
                    shutil.copy2(template_yaml, jira_config_path)
                except Exception:
                    return False

        # Criar config.json se não existir
        # Usar sempre o diretório do usuário (XDG_CONFIG_HOME)
        config_json_path = config_dir / "config.json"
        if not config_json_path.exists():
            template_json = template_dir / "config.json.example"
            if template_json.exists():
                try:
                    shutil.copy2(template_json, config_json_path)
                except Exception:
                    return False

        return True

    class _AccountIdWorker(QThread):
        """Worker thread interno para buscar accountId via API"""

        accountIdFetched = Signal(str)
        errorOccurred = Signal(str)

        def __init__(self, server_url: str, email: str, api_token: str, parent=None):
            super().__init__(parent)
            self._server_url = server_url
            self._email = email
            self._api_token = api_token

        def run(self):
            """Executa a busca em thread separada"""
            try:
                import requests
                from requests.auth import HTTPBasicAuth
                from src.utils.debug import debug_log

                url = f"{self._server_url}/rest/api/3/myself"
                debug_log(
                    "SettingsModel._AccountIdWorker",
                    "run",
                    "Buscando accountId em %s",
                    url,
                )
                debug_log(
                    "SettingsModel._AccountIdWorker", "run", "Email: %s", self._email
                )
                debug_log(
                    "SettingsModel._AccountIdWorker",
                    "run",
                    "Token presente: %s",
                    bool(self._api_token),
                )

                auth = HTTPBasicAuth(self._email, self._api_token)
                response = requests.get(url, auth=auth, timeout=10)

                debug_log(
                    "SettingsModel._AccountIdWorker",
                    "run",
                    "Response status=%d",
                    response.status_code,
                )

                if response.status_code == 200:
                    data = response.json()
                    account_id = data.get("accountId", "")
                    debug_log(
                        "SettingsModel._AccountIdWorker",
                        "run",
                        "accountId obtido: %s",
                        account_id,
                    )
                    if account_id:
                        self.accountIdFetched.emit(account_id)
                    else:
                        debug_log(
                            "SettingsModel._AccountIdWorker",
                            "run",
                            "accountId não encontrado na resposta",
                        )
                        self.errorOccurred.emit(
                            "accountId não encontrado na resposta da API"
                        )
                else:
                    debug_log(
                        "SettingsModel._AccountIdWorker",
                        "run",
                        "Erro HTTP %d",
                        response.status_code,
                    )
                    debug_log(
                        "SettingsModel._AccountIdWorker",
                        "run",
                        "Response: %s",
                        response.text[:200],
                    )
                    self.errorOccurred.emit(
                        f"Erro ao buscar accountId: HTTP {response.status_code}"
                    )
            except Exception as e:
                import traceback
                from src.utils.debug import debug_log

                debug_log("SettingsModel._AccountIdWorker", "run", "Exceção: %s", e)
                traceback.print_exc(file=sys.stderr)
                self.errorOccurred.emit(f"Erro ao buscar accountId: {str(e)}")

    def _start_fetch_account_id(self, server_url: str, email: str, api_token: str):
        """Inicia busca assíncrona de accountId via API do Jira"""
        debug_log(
            "SettingsModel", "_start_fetch_account_id", "Iniciando busca de accountId"
        )
        debug_log(
            "SettingsModel",
            "_start_fetch_account_id",
            "URL=%s, Email=%s",
            server_url,
            email,
        )

        # Cancelar worker anterior se existir (pode estar já deletado após deleteLater)
        try:
            if self._account_id_worker and self._account_id_worker.isRunning():
                debug_log(
                    "SettingsModel",
                    "_start_fetch_account_id",
                    "Cancelando worker anterior",
                )
                self._account_id_worker.terminate()
                self._account_id_worker.wait()
        except RuntimeError:
            # Objeto C++ já deletado (ex.: após deleteLater)
            self._account_id_worker = None

        # Criar novo worker
        debug_log("SettingsModel", "_start_fetch_account_id", "Criando novo worker")
        self._account_id_worker = self._AccountIdWorker(
            server_url, email, api_token, self
        )
        self._account_id_worker.accountIdFetched.connect(self._on_account_id_fetched)
        self._account_id_worker.errorOccurred.connect(self._on_account_id_error)
        self._account_id_worker.finished.connect(self._on_account_id_worker_finished)
        debug_log("SettingsModel", "_start_fetch_account_id", "Iniciando thread")
        self._account_id_worker.start()

    def _on_account_id_worker_finished(self):
        """Limpa referência ao worker após término (evita RuntimeError em save posterior)."""
        w = self._account_id_worker
        self._account_id_worker = None
        if w:
            w.deleteLater()

    def _on_account_id_fetched(self, account_id: str):
        """Callback quando accountId é obtido com sucesso"""
        # Salvar accountId no config.json
        self._config_manager.set_account_id(account_id)
        self._account_id = account_id

        # Recarregar valores para garantir sincronização
        debug_log(
            "SettingsModel",
            "_on_account_id_fetched",
            "Recarregando valores após accountId ser obtido",
        )
        self._load_current_values()

        self.accountIdChanged.emit()
        self.accountIdFetched.emit(account_id)

    def _on_account_id_error(self, error_message: str):
        """Callback quando ocorre erro ao buscar accountId"""
        self.errorOccurred.emit(error_message)

    @Slot()
    def saveGoogleOAuthOnly(self) -> bool:
        """
        Salva apenas as configurações Google OAuth no config.json.
        Usado antes de autorizar, para que o fluxo OAuth leia client_id e client_secret.
        Retorna True se salvou com sucesso, False em caso de erro.
        """
        try:
            self._config_manager.save_google_oauth_config(
                self._google_oauth_client_id,
                self._google_oauth_project_id,
                self._google_oauth_client_secret,
            )
            debug_log(
                "SettingsModel",
                "saveGoogleOAuthOnly",
                "Configurações Google OAuth salvas",
            )
            return True
        except Exception as e:
            debug_log("SettingsModel", "saveGoogleOAuthOnly", "Erro: %s", e)
            self.errorOccurred.emit(str(e))
            return False

    @Slot()
    def save(self):
        """Salva configurações e busca accountId automaticamente"""
        debug_log("SettingsModel", "save", "Iniciando salvamento")
        try:
            # 1. Criar arquivos de config a partir de templates se não existirem
            debug_log(
                "SettingsModel", "save", "Criando arquivos de config se necessário"
            )
            self._create_config_from_templates()

            # 2. Salvar no .jira-config.yml
            if (
                not self._jira_base_url
                or not self._jira_email
                or not self._jira_api_token
            ):
                debug_log("SettingsModel", "save", "Campos obrigatórios faltando")
                self.errorOccurred.emit("Todos os campos são obrigatórios")
                return

            debug_log("SettingsModel", "save", "Salvando no .jira-config.yml")
            self._config_manager.save_jira_config(
                server=self._jira_base_url,
                login=self._jira_email,
                token=self._jira_api_token,
            )

            # 3. Buscar accountId automaticamente (assíncrono)
            debug_log("SettingsModel", "save", "Iniciando busca de accountId")
            self.fetchingAccountId.emit()
            self._start_fetch_account_id(
                self._jira_base_url, self._jira_email, self._jira_api_token
            )

            # 4. Salvar configurações de Pomodoro
            debug_log("SettingsModel", "save", "Salvando configurações de Pomodoro")
            debug_log(
                "SettingsModel",
                "save",
                "Valores atuais antes de salvar: short_sound_file=%s, long_sound_file=%s",
                self._short_sound_file,
                self._long_sound_file,
            )
            pomodoro_config = {
                "enabled": self._pomodoro_enabled,
                "pomodoro_duration_minutes": self._pomodoro_duration_minutes,
                "short_break_minutes": self._short_break_minutes,
                "long_break_minutes": self._long_break_minutes,
                "pomodoros_before_long_break": self._pomodoros_before_long_break,
                "auto_continue_timeout_seconds": self._auto_continue_timeout_seconds,
                "notifications": {
                    "enabled": self._notifications_enabled,
                    "sound_enabled": self._sound_enabled,
                    "desktop_notifications": self._desktop_notifications,
                    "short_sound_file": self._short_sound_file,
                    "long_sound_file": self._long_sound_file,
                    "return_from_break_sound_file": self._return_from_break_sound_file
                    or None,
                },
            }
            self._config_manager.save_pomodoro_config(pomodoro_config)
            debug_log(
                "SettingsModel", "save", "Configurações de Pomodoro salvas no arquivo"
            )

            # 4b. Salvar configurações de entrada por voz
            voice_config = {
                "enabled": self._voice_enabled,
                "localai_base_url": self._localai_base_url,
                "localai_whisper_model": self._localai_whisper_model,
                "localai_llm_model": self._localai_llm_model,
                "localai_task_system_prompt": self._localai_task_system_prompt,
                "localai_comment_improvement_prompt": self._localai_comment_improvement_prompt,
                "language": self._voice_language,
                "max_recording_seconds": self._voice_max_recording_seconds,
                "keyboard_shortcut": self._voice_keyboard_shortcut,
                "auto_process_after_stop": self._voice_auto_process_after_stop,
                "microphone_device": "default",
            }
            self._config_manager.save_voice_input_config(voice_config)
            debug_log(
                "SettingsModel",
                "save",
                "Configurações de voice_input salvas no arquivo",
            )

            # 4c. Salvar configurações de worklog_check (status_transitions)
            worklog_check_config = {
                "enabled": self._worklog_check_enabled,
                "show_confirmation_dialog": self._worklog_check_show_dialog,
                "block_transition_if_pending": self._worklog_check_block_if_pending,
            }
            self._config_manager.save_worklog_check_config(worklog_check_config)
            debug_log(
                "SettingsModel",
                "save",
                "Configurações de worklog_check salvas no arquivo",
            )

            # 4c2. Salvar configurações de development_panel
            development_panel_config = {
                "enabled": self._development_panel_enabled,
                "github_enrichment": self._development_panel_github_enrichment,
                "default_org": self._development_panel_default_org,
            }
            self._config_manager.save_development_panel_config(development_panel_config)
            debug_log(
                "SettingsModel",
                "save",
                "Configurações de development_panel salvas no arquivo",
            )

            # 4c3. Salvar configurações de timesheet
            timesheet_config = {
                "enabled": self._timesheet_enabled,
                "cache_ttl_minutes": self._timesheet_cache_ttl_minutes,
                "default_period": self._timesheet_default_period,
                "max_results": self._timesheet_max_results,
            }
            self._config_manager.save_timesheet_config(timesheet_config)
            debug_log(
                "SettingsModel",
                "save",
                "Configurações de timesheet salvas no arquivo",
            )

            # 4d. Salvar configurações Google OAuth
            self._config_manager.save_google_oauth_config(
                self._google_oauth_client_id,
                self._google_oauth_project_id,
                self._google_oauth_client_secret,
            )
            debug_log(
                "SettingsModel",
                "save",
                "Configurações Google OAuth salvas no arquivo",
            )

            # 4d2. Salvar configurações Google Drive Comments
            drive_comments_config = {
                "enabled": self._drive_comments_enabled,
                "max_comments": self._drive_comments_max_comments,
                "unresolved_only": self._drive_comments_unresolved_only,
            }
            self._config_manager.save_google_drive_comments_config(
                drive_comments_config
            )
            debug_log(
                "SettingsModel",
                "save",
                "Configurações Google Drive Comments salvas no arquivo",
            )

            # 4e. Salvar configurações GitHub
            self._config_manager.save_github_config(
                self._github_token, self._github_username
            )
            debug_log(
                "SettingsModel",
                "save",
                "Configurações GitHub salvas no arquivo",
            )

            # 5. Recarregar valores após salvar
            debug_log("SettingsModel", "save", "Recarregando valores após salvar")
            self._load_current_values()

            # 6. Emitir sinal de sucesso (a busca de accountId continua em background)
            debug_log("SettingsModel", "save", "Emitindo sinal saved")
            self.saved.emit()

        except Exception as e:
            import traceback

            debug_log("SettingsModel", "save", "Erro: %s", e)
            traceback.print_exc(file=sys.stderr)
            self.errorOccurred.emit(f"Erro ao salvar configurações: {str(e)}")

    # Sinais para notificar mudanças nas propriedades
    jiraBaseUrlChanged = Signal()
    jiraEmailChanged = Signal()
    jiraApiTokenChanged = Signal()
    accountIdChanged = Signal()

    # Sinais para configurações de Pomodoro
    pomodoroEnabledChanged = Signal()
    pomodoroDurationMinutesChanged = Signal()
    shortBreakMinutesChanged = Signal()
    longBreakMinutesChanged = Signal()
    pomodorosBeforeLongBreakChanged = Signal()
    autoContinueTimeoutSecondsChanged = Signal()
    notificationsEnabledChanged = Signal()
    soundEnabledChanged = Signal()
    desktopNotificationsChanged = Signal()
    shortSoundFileChanged = Signal()
    longSoundFileChanged = Signal()
    returnFromBreakSoundFileChanged = Signal()

    # Sinais para worklog_check (status_transitions)
    worklogCheckEnabledChanged = Signal()
    worklogCheckShowDialogChanged = Signal()
    worklogCheckBlockIfPendingChanged = Signal()

    # Sinais para development_panel
    developmentPanelEnabledChanged = Signal()
    developmentPanelGitHubEnrichmentChanged = Signal()
    developmentPanelDefaultOrgChanged = Signal()

    # Sinais para timesheet
    timesheetEnabledChanged = Signal()
    timesheetCacheTtlMinutesChanged = Signal()
    timesheetDefaultPeriodChanged = Signal()
    timesheetMaxResultsChanged = Signal()

    # Sinais para GitHub
    githubTokenChanged = Signal()
    githubUsernameChanged = Signal()

    # Sinais para Google OAuth
    googleOAuthClientIdChanged = Signal()
    googleOAuthProjectIdChanged = Signal()
    googleOAuthClientSecretChanged = Signal()

    # Propriedades QML
    @Property(str, notify=jiraBaseUrlChanged)
    def jiraBaseUrl(self) -> str:
        """URL base do servidor Jira"""
        return self._jira_base_url

    @jiraBaseUrl.setter
    def jiraBaseUrl(self, value: str):
        if self._jira_base_url != value:
            self._jira_base_url = value
            self.jiraBaseUrlChanged.emit()

    @Property(str, notify=jiraEmailChanged)
    def jiraEmail(self) -> str:
        """Email do usuário Jira"""
        return self._jira_email

    @jiraEmail.setter
    def jiraEmail(self, value: str):
        if self._jira_email != value:
            self._jira_email = value
            self.jiraEmailChanged.emit()

    @Property(str, notify=jiraApiTokenChanged)
    def jiraApiToken(self) -> str:
        """Token de API do Jira"""
        return self._jira_api_token

    @jiraApiToken.setter
    def jiraApiToken(self, value: str):
        if self._jira_api_token != value:
            self._jira_api_token = value
            self.jiraApiTokenChanged.emit()

    @Property(str, notify=accountIdChanged)
    def accountId(self) -> str:
        """AccountId do usuário (read-only)"""
        return self._account_id

    @Property(bool, notify=accountIdChanged)
    def isConfigured(self) -> bool:
        """Indica se a configuração está completa"""
        return self.is_configured()

    @Property(bool, notify=accountIdChanged)
    def needsConfiguration(self) -> bool:
        """Indica se a configuração precisa ser feita (QML property)"""
        return self.needs_configuration()

    # Propriedades QML para Pomodoro
    @Property(bool, notify=pomodoroEnabledChanged)
    def pomodoroEnabled(self) -> bool:
        """Habilitar Pomodoro"""
        return self._pomodoro_enabled

    @pomodoroEnabled.setter
    def pomodoroEnabled(self, value: bool):
        if self._pomodoro_enabled != value:
            self._pomodoro_enabled = value
            self.pomodoroEnabledChanged.emit()

    @Property(int, notify=pomodoroDurationMinutesChanged)
    def pomodoroDurationMinutes(self) -> int:
        """Duração do Pomodoro em minutos"""
        return self._pomodoro_duration_minutes

    @pomodoroDurationMinutes.setter
    def pomodoroDurationMinutes(self, value: int):
        if self._pomodoro_duration_minutes != value:
            self._pomodoro_duration_minutes = value
            self.pomodoroDurationMinutesChanged.emit()

    @Property(int, notify=shortBreakMinutesChanged)
    def shortBreakMinutes(self) -> int:
        """Duração da pausa curta em minutos"""
        return self._short_break_minutes

    @shortBreakMinutes.setter
    def shortBreakMinutes(self, value: int):
        if self._short_break_minutes != value:
            self._short_break_minutes = value
            self.shortBreakMinutesChanged.emit()

    @Property(int, notify=longBreakMinutesChanged)
    def longBreakMinutes(self) -> int:
        """Duração da pausa longa em minutos"""
        return self._long_break_minutes

    @longBreakMinutes.setter
    def longBreakMinutes(self, value: int):
        if self._long_break_minutes != value:
            self._long_break_minutes = value
            self.longBreakMinutesChanged.emit()

    @Property(int, notify=pomodorosBeforeLongBreakChanged)
    def pomodorosBeforeLongBreak(self) -> int:
        """Número de Pomodoros antes da pausa longa"""
        return self._pomodoros_before_long_break

    @pomodorosBeforeLongBreak.setter
    def pomodorosBeforeLongBreak(self, value: int):
        if self._pomodoros_before_long_break != value:
            self._pomodoros_before_long_break = value
            self.pomodorosBeforeLongBreakChanged.emit()

    @Property(int, notify=autoContinueTimeoutSecondsChanged)
    def autoContinueTimeoutSeconds(self) -> int:
        """Timeout de auto-continuação em segundos"""
        return self._auto_continue_timeout_seconds

    @autoContinueTimeoutSeconds.setter
    def autoContinueTimeoutSeconds(self, value: int):
        if self._auto_continue_timeout_seconds != value:
            self._auto_continue_timeout_seconds = value
            self.autoContinueTimeoutSecondsChanged.emit()

    @Property(bool, notify=notificationsEnabledChanged)
    def notificationsEnabled(self) -> bool:
        """Habilitar notificações"""
        return self._notifications_enabled

    @notificationsEnabled.setter
    def notificationsEnabled(self, value: bool):
        if self._notifications_enabled != value:
            self._notifications_enabled = value
            self.notificationsEnabledChanged.emit()

    @Property(bool, notify=soundEnabledChanged)
    def soundEnabled(self) -> bool:
        """Habilitar som de alerta"""
        return self._sound_enabled

    @soundEnabled.setter
    def soundEnabled(self, value: bool):
        if self._sound_enabled != value:
            self._sound_enabled = value
            self.soundEnabledChanged.emit()

    @Property(bool, notify=desktopNotificationsChanged)
    def desktopNotifications(self) -> bool:
        """Habilitar notificações desktop"""
        return self._desktop_notifications

    @desktopNotifications.setter
    def desktopNotifications(self, value: bool):
        if self._desktop_notifications != value:
            self._desktop_notifications = value
            self.desktopNotificationsChanged.emit()

    @Property(str, notify=shortSoundFileChanged)
    def shortSoundFile(self) -> str:
        """Nome do arquivo de som para pausa curta (sem extensão)"""
        return self._short_sound_file

    @shortSoundFile.setter
    def shortSoundFile(self, value: str):
        if self._short_sound_file != value:
            self._short_sound_file = value
            self.shortSoundFileChanged.emit()

    @Property(str, notify=longSoundFileChanged)
    def longSoundFile(self) -> str:
        """Nome do arquivo de som para pausa longa (sem extensão)"""
        return self._long_sound_file

    @longSoundFile.setter
    def longSoundFile(self, value: str):
        if self._long_sound_file != value:
            self._long_sound_file = value
            self.longSoundFileChanged.emit()

    @Property(str, notify=returnFromBreakSoundFileChanged)
    def returnFromBreakSoundFile(self) -> str:
        """Arquivo de som ao voltar da pausa (opcional; vazio = não toca)"""
        return self._return_from_break_sound_file

    @returnFromBreakSoundFile.setter
    def returnFromBreakSoundFile(self, value: str):
        val = (value or "").strip()
        if self._return_from_break_sound_file != val:
            self._return_from_break_sound_file = val
            self.returnFromBreakSoundFileChanged.emit()

    # Sinais para configurações de entrada por voz
    voiceInputEnabledChanged = Signal()
    localaiBaseUrlChanged = Signal()
    localaiWhisperModelChanged = Signal()
    localaiLlmModelChanged = Signal()
    localaiTaskSystemPromptChanged = Signal()
    localaiCommentImprovementPromptChanged = Signal()
    voiceInputLanguageChanged = Signal()
    voiceInputMaxRecordingSecondsChanged = Signal()
    voiceInputKeyboardShortcutChanged = Signal()
    voiceInputAutoProcessAfterStopChanged = Signal()

    @Property(bool, notify=voiceInputEnabledChanged)
    def voiceInputEnabled(self) -> bool:
        return self._voice_enabled

    @voiceInputEnabled.setter
    def voiceInputEnabled(self, value: bool):
        if self._voice_enabled != value:
            self._voice_enabled = value
            self.voiceInputEnabledChanged.emit()

    @Property(str, notify=localaiBaseUrlChanged)
    def localaiBaseUrl(self) -> str:
        return self._localai_base_url

    @localaiBaseUrl.setter
    def localaiBaseUrl(self, value: str):
        v = (value or "http://localhost:8080").strip()
        if self._localai_base_url != v:
            self._localai_base_url = v
            self.localaiBaseUrlChanged.emit()

    @Property(str, notify=localaiWhisperModelChanged)
    def localaiWhisperModel(self) -> str:
        return self._localai_whisper_model

    @localaiWhisperModel.setter
    def localaiWhisperModel(self, value: str):
        v = value or "whisper-1"
        if self._localai_whisper_model != v:
            self._localai_whisper_model = v
            self.localaiWhisperModelChanged.emit()

    @Property(str, notify=localaiLlmModelChanged)
    def localaiLlmModel(self) -> str:
        return self._localai_llm_model

    @localaiLlmModel.setter
    def localaiLlmModel(self, value: str):
        v = value or "qwen2.5:3b"
        if self._localai_llm_model != v:
            self._localai_llm_model = v
            self.localaiLlmModelChanged.emit()

    @Property(str, notify=localaiTaskSystemPromptChanged)
    def localaiTaskSystemPrompt(self) -> str:
        return self._localai_task_system_prompt

    @localaiTaskSystemPrompt.setter
    def localaiTaskSystemPrompt(self, value: str):
        v = value or ""
        if self._localai_task_system_prompt != v:
            self._localai_task_system_prompt = v
            self.localaiTaskSystemPromptChanged.emit()

    @Property(str, notify=localaiCommentImprovementPromptChanged)
    def localaiCommentImprovementPrompt(self) -> str:
        return self._localai_comment_improvement_prompt

    @localaiCommentImprovementPrompt.setter
    def localaiCommentImprovementPrompt(self, value: str):
        v = value or ""
        if self._localai_comment_improvement_prompt != v:
            self._localai_comment_improvement_prompt = v
            self.localaiCommentImprovementPromptChanged.emit()

    @Property(str, notify=voiceInputLanguageChanged)
    def voiceInputLanguage(self) -> str:
        return self._voice_language

    @voiceInputLanguage.setter
    def voiceInputLanguage(self, value: str):
        if self._voice_language != (value or "pt"):
            self._voice_language = value or "pt"
            self.voiceInputLanguageChanged.emit()

    @Property(int, notify=voiceInputMaxRecordingSecondsChanged)
    def voiceInputMaxRecordingSeconds(self) -> int:
        return self._voice_max_recording_seconds

    @voiceInputMaxRecordingSeconds.setter
    def voiceInputMaxRecordingSeconds(self, value: int):
        if self._voice_max_recording_seconds != value:
            self._voice_max_recording_seconds = max(30, min(300, value))
            self.voiceInputMaxRecordingSecondsChanged.emit()

    @Property(str, notify=voiceInputKeyboardShortcutChanged)
    def voiceInputKeyboardShortcut(self) -> str:
        return self._voice_keyboard_shortcut

    @voiceInputKeyboardShortcut.setter
    def voiceInputKeyboardShortcut(self, value: str):
        v = (value or "Meta+F").strip()
        if self._voice_keyboard_shortcut != v:
            self._voice_keyboard_shortcut = v
            self.voiceInputKeyboardShortcutChanged.emit()

    @Property(bool, notify=voiceInputAutoProcessAfterStopChanged)
    def voiceInputAutoProcessAfterStop(self) -> bool:
        return self._voice_auto_process_after_stop

    @voiceInputAutoProcessAfterStop.setter
    def voiceInputAutoProcessAfterStop(self, value: bool):
        if self._voice_auto_process_after_stop != value:
            self._voice_auto_process_after_stop = value
            self.voiceInputAutoProcessAfterStopChanged.emit()

    # Propriedades QML para status_transitions.worklog_check
    @Property(bool, notify=worklogCheckEnabledChanged)
    def worklogCheckEnabled(self) -> bool:
        """Verificar worklogs pendentes antes de transitar status"""
        return self._worklog_check_enabled

    @worklogCheckEnabled.setter
    def worklogCheckEnabled(self, value: bool):
        if self._worklog_check_enabled != value:
            self._worklog_check_enabled = value
            self.worklogCheckEnabledChanged.emit()

    @Property(bool, notify=worklogCheckShowDialogChanged)
    def worklogCheckShowDialog(self) -> bool:
        """Mostrar diálogo de confirmação quando houver pendentes"""
        return self._worklog_check_show_dialog

    @worklogCheckShowDialog.setter
    def worklogCheckShowDialog(self, value: bool):
        if self._worklog_check_show_dialog != value:
            self._worklog_check_show_dialog = value
            self.worklogCheckShowDialogChanged.emit()

    @Property(bool, notify=worklogCheckBlockIfPendingChanged)
    def worklogCheckBlockIfPending(self) -> bool:
        """Bloquear transição se houver pendentes (apenas Sincronizar ou Cancelar)"""
        return self._worklog_check_block_if_pending

    @worklogCheckBlockIfPending.setter
    def worklogCheckBlockIfPending(self, value: bool):
        if self._worklog_check_block_if_pending != value:
            self._worklog_check_block_if_pending = value
            self.worklogCheckBlockIfPendingChanged.emit()

    @Property(bool, notify=developmentPanelEnabledChanged)
    def developmentPanelEnabled(self) -> bool:
        """Mostrar painel de Development (branches e PRs) nos detalhes da issue"""
        return self._development_panel_enabled

    @developmentPanelEnabled.setter
    def developmentPanelEnabled(self, value: bool):
        if self._development_panel_enabled != value:
            self._development_panel_enabled = value
            self.developmentPanelEnabledChanged.emit()

    @Property(bool, notify=developmentPanelGitHubEnrichmentChanged)
    def developmentPanelGitHubEnrichment(self) -> bool:
        """Enriquecer PRs com dados do GitHub (checks, aprovações)"""
        return self._development_panel_github_enrichment

    @developmentPanelGitHubEnrichment.setter
    def developmentPanelGitHubEnrichment(self, value: bool):
        if self._development_panel_github_enrichment != value:
            self._development_panel_github_enrichment = value
            self.developmentPanelGitHubEnrichmentChanged.emit()

    @Property(str, notify=developmentPanelDefaultOrgChanged)
    def developmentPanelDefaultOrg(self) -> str:
        return self._development_panel_default_org

    @developmentPanelDefaultOrg.setter
    def developmentPanelDefaultOrg(self, value: str):
        v = (value or "").strip()
        if self._development_panel_default_org != v:
            self._development_panel_default_org = v
            self.developmentPanelDefaultOrgChanged.emit()

    # Propriedades QML para timesheet
    @Property(bool, notify=timesheetEnabledChanged)
    def timesheetEnabled(self) -> bool:
        """Habilitar Timesheet"""
        return self._timesheet_enabled

    @timesheetEnabled.setter
    def timesheetEnabled(self, value: bool):
        if self._timesheet_enabled != value:
            self._timesheet_enabled = value
            self.timesheetEnabledChanged.emit()

    @Property(int, notify=timesheetCacheTtlMinutesChanged)
    def timesheetCacheTtlMinutes(self) -> int:
        """TTL do cache do Timesheet em minutos"""
        return self._timesheet_cache_ttl_minutes

    @timesheetCacheTtlMinutes.setter
    def timesheetCacheTtlMinutes(self, value: int):
        v = max(1, min(60, value))
        if self._timesheet_cache_ttl_minutes != v:
            self._timesheet_cache_ttl_minutes = v
            self.timesheetCacheTtlMinutesChanged.emit()

    @Property(str, notify=timesheetDefaultPeriodChanged)
    def timesheetDefaultPeriod(self) -> str:
        """Período padrão do Timesheet"""
        return self._timesheet_default_period

    @timesheetDefaultPeriod.setter
    def timesheetDefaultPeriod(self, value: str):
        v = value or "last_7_days"
        if self._timesheet_default_period != v:
            self._timesheet_default_period = v
            self.timesheetDefaultPeriodChanged.emit()

    @Property(int, notify=timesheetMaxResultsChanged)
    def timesheetMaxResults(self) -> int:
        """Máximo de issues por busca no Timesheet"""
        return self._timesheet_max_results

    @timesheetMaxResults.setter
    def timesheetMaxResults(self, value: int):
        v = max(50, min(1000, value))
        if self._timesheet_max_results != v:
            self._timesheet_max_results = v
            self.timesheetMaxResultsChanged.emit()

    @Property(str, notify=githubTokenChanged)
    def githubToken(self) -> str:
        """Token de API do GitHub (armazenado em config.json)"""
        return self._github_token

    @githubToken.setter
    def githubToken(self, value: str):
        if self._github_token != value:
            self._github_token = value or ""
            self.githubTokenChanged.emit()

    @Property(str, notify=githubUsernameChanged)
    def githubUsername(self) -> str:
        """Username do GitHub"""
        return self._github_username

    @githubUsername.setter
    def githubUsername(self, value: str):
        if self._github_username != value:
            self._github_username = (value or "").strip()
            self.githubUsernameChanged.emit()

    @Property(str, notify=googleOAuthClientIdChanged)
    def googleOAuthClientId(self) -> str:
        """Client ID do Google OAuth (GCP)"""
        return self._google_oauth_client_id

    @googleOAuthClientId.setter
    def googleOAuthClientId(self, value: str):
        if self._google_oauth_client_id != value:
            self._google_oauth_client_id = value or ""
            self.googleOAuthClientIdChanged.emit()

    @Property(str, notify=googleOAuthProjectIdChanged)
    def googleOAuthProjectId(self) -> str:
        """Project ID do Google OAuth (GCP)"""
        return self._google_oauth_project_id

    @googleOAuthProjectId.setter
    def googleOAuthProjectId(self, value: str):
        if self._google_oauth_project_id != value:
            self._google_oauth_project_id = value or ""
            self.googleOAuthProjectIdChanged.emit()

    @Property(str, notify=googleOAuthClientSecretChanged)
    def googleOAuthClientSecret(self) -> str:
        """Client Secret do Google OAuth (GCP)"""
        return self._google_oauth_client_secret

    @googleOAuthClientSecret.setter
    def googleOAuthClientSecret(self, value: str):
        if self._google_oauth_client_secret != value:
            self._google_oauth_client_secret = value or ""
            self.googleOAuthClientSecretChanged.emit()

    # Drive comments (Issue #18)
    driveCommentsEnabledChanged = Signal()
    driveCommentsMaxCommentsChanged = Signal()
    driveCommentsUnresolvedOnlyChanged = Signal()

    @Property(bool, notify=driveCommentsEnabledChanged)
    def driveCommentsEnabled(self) -> bool:
        """Habilitar coluna de comentários do Drive na aba Google"""
        return self._drive_comments_enabled

    @driveCommentsEnabled.setter
    def driveCommentsEnabled(self, value: bool):
        if self._drive_comments_enabled != value:
            self._drive_comments_enabled = value
            self.driveCommentsEnabledChanged.emit()

    @Property(int, notify=driveCommentsMaxCommentsChanged)
    def driveCommentsMaxComments(self) -> int:
        """Número máximo de comentários do Drive a carregar"""
        return self._drive_comments_max_comments

    @driveCommentsMaxComments.setter
    def driveCommentsMaxComments(self, value: int):
        if self._drive_comments_max_comments != value:
            self._drive_comments_max_comments = max(1, min(100, int(value)))
            self.driveCommentsMaxCommentsChanged.emit()

    @Property(bool, notify=driveCommentsUnresolvedOnlyChanged)
    def driveCommentsUnresolvedOnly(self) -> bool:
        """Carregar apenas comentários não resolvidos do Drive"""
        return self._drive_comments_unresolved_only

    @driveCommentsUnresolvedOnly.setter
    def driveCommentsUnresolvedOnly(self, value: bool):
        if self._drive_comments_unresolved_only != value:
            self._drive_comments_unresolved_only = value
            self.driveCommentsUnresolvedOnlyChanged.emit()
