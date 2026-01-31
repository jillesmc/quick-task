"""
Sistema de debug condicional para Jira Quick Task
"""

import os
import sys
from pathlib import Path

_DEBUG_ENABLED = None
_DEBUG_LOG_PATH = None


def get_debug_log_path():
    """
    Retorna o caminho do arquivo de log de debug (sempre gravável).
    No Flatpak (/app) usa XDG_CONFIG_HOME/jira-quick-task/debug.log;
    fora do Flatpak usa <projeto>/.cursor/debug.log.
    """
    global _DEBUG_LOG_PATH
    if _DEBUG_LOG_PATH is not None:
        return _DEBUG_LOG_PATH
    this_file = Path(__file__).resolve()
    # Flatpak instala em /app; projeto local tem src/utils/debug.py
    if str(this_file).startswith("/app/"):
        xdg = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
        _DEBUG_LOG_PATH = Path(xdg) / "jira-quick-task" / "debug.log"
    else:
        project_root = this_file.parent.parent.parent  # utils -> src -> project
        _DEBUG_LOG_PATH = project_root / ".cursor" / "debug.log"
    return _DEBUG_LOG_PATH


def is_debug_enabled():
    """
    Verifica se debug está habilitado

    Verifica:
    - Parâmetro --debug em sys.argv
    - Variável de ambiente JIRA_QUICK_TASK_DEBUG=1

    Returns:
        bool: True se debug está habilitado, False caso contrário
    """
    global _DEBUG_ENABLED
    if _DEBUG_ENABLED is None:
        _DEBUG_ENABLED = (
            "--debug" in sys.argv or os.environ.get("JIRA_QUICK_TASK_DEBUG") == "1"
        )
    return _DEBUG_ENABLED


def debug_log(module_name, function_name, message, *args):
    """
    Loga mensagem de debug se debug estiver habilitado

    Formato: [DEBUG] ModuleName.function_name: mensagem

    Args:
        module_name: Nome do módulo/classe (ex: "SettingsModel", "App")
        function_name: Nome da função/método (ex: "save", "main")
        message: Mensagem de debug (pode usar %s, %d, etc. para formatação)
        *args: Argumentos para formatação da mensagem (opcional)

    Examples:
        debug_log("SettingsModel", "save", "Iniciando salvamento")
        debug_log("SettingsModel", "_start_fetch_account_id", "URL=%s, Email=%s", url, email)
    """
    if is_debug_enabled():
        if args:
            try:
                formatted_msg = message % args
            except (TypeError, ValueError):
                # Se formatação falhar, usar f-string como fallback
                formatted_msg = f"{message} | args: {args}"
        else:
            formatted_msg = message
        print(
            f"[DEBUG] {module_name}.{function_name}: {formatted_msg}", file=sys.stderr
        )
