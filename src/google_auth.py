"""
Google OAuth 2.0 authentication manager for Calendar and Tasks APIs.
Handles token storage and refresh; runs OAuth flow in blocking mode (use from Worker).
"""

import json
import os
from pathlib import Path
from typing import Optional

from src.utils.debug import debug_log


def get_ca_bundle_path_for_google_api() -> Optional[str]:
    """
    Path to CA bundle for Google API (Calendar/Tasks) HTTP client.
    Uses same env vars as the rest of the app (Flatpak host certs, Netskope, etc.).
    httplib2 (used by google-api-python-client) does not use REQUESTS_CA_BUNDLE
    by default, so we must pass ca_certs explicitly when building the service.
    """
    for var in ("SSL_CERT_FILE", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE"):
        path = os.environ.get(var)
        if path and os.path.isfile(path):
            return path
    try:
        import certifi

        return certifi.where()
    except ImportError:
        return None


def _get_token_path(config_path: Path) -> Path:
    """Return path for google_token.json (same directory as config)."""
    if str(config_path).startswith("/app/"):
        xdg_config = os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
        return Path(xdg_config) / "jira-quick-task" / "google_token.json"
    return config_path.parent / "google_token.json"


def _build_client_config(client_id: str, client_secret: str) -> dict:
    """Build client_config dict for InstalledAppFlow (OAuth installed application format)."""
    return {
        "installed": {
            "client_id": client_id.strip(),
            "client_secret": client_secret.strip(),
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": ["http://localhost"],
        }
    }


SCOPES = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/tasks.readonly",
    # drive (não drive.readonly): listar comentários + comments().update() para resolver
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/chat.spaces.readonly",
]


class GoogleAuthManager:
    """
    Manages Google OAuth credentials: loads from config, stores token locally.
    authenticate() is blocking (opens browser); run from QThread/Worker.
    """

    def __init__(self, config_manager):
        self._config = config_manager
        self._token_path = _get_token_path(config_manager.config_path)

    def remove_token(self) -> None:
        """Remove stored token (e.g. after 401/403). User must re-authorize."""
        if self._token_path.exists():
            try:
                self._token_path.unlink()
                debug_log(
                    "GoogleAuthManager",
                    "remove_token",
                    "Token removido (401/403 ou inválido)",
                )
            except OSError as e:
                debug_log(
                    "GoogleAuthManager", "remove_token", "Erro ao remover token: %s", e
                )

    def _get_scopes_for_load(self, data: dict) -> list:
        """Use scopes from saved token to avoid invalid_scope when token has fewer scopes."""
        saved = data.get("scopes")
        if saved and isinstance(saved, list):
            return saved
        return SCOPES

    def has_valid_token(self) -> bool:
        """Check if we have a stored token that can be used (or refreshed)."""
        if not self._token_path.exists():
            return False
        try:
            from google.oauth2.credentials import Credentials
            from google.auth.transport.requests import Request

            with open(self._token_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            scopes = self._get_scopes_for_load(data)
            creds = Credentials.from_authorized_user_info(data, scopes)
            if creds.expired and creds.refresh_token:
                creds.refresh(Request())
                self._save_token(creds)
            return getattr(creds, "valid", not creds.expired)
        except Exception as e:
            debug_log(
                "GoogleAuthManager", "has_valid_token", "Erro ao verificar token: %s", e
            )
            return False

    def _save_token(self, credentials) -> None:
        """Save credentials to token file with restricted permissions."""
        token_data = {
            "token": credentials.token,
            "refresh_token": credentials.refresh_token,
            "token_uri": credentials.token_uri,
            "client_id": credentials.client_id,
            "client_secret": credentials.client_secret,
            "scopes": list(credentials.scopes) if credentials.scopes else SCOPES,
        }
        self._token_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self._token_path, "w", encoding="utf-8") as f:
            json.dump(token_data, f, indent=2)
        os.chmod(self._token_path, 0o600)

    def authenticate(self):
        """
        Authenticate with Google. Uses cached token if valid; otherwise runs OAuth flow.
        Blocks (opens browser). Run from QThread/Worker.
        Returns credentials on success; raises on error.
        """
        from google.oauth2.credentials import Credentials
        from google.auth.transport.requests import Request
        from google_auth_oauthlib.flow import InstalledAppFlow

        goauth = self._config.get_google_oauth_config()
        client_id = (goauth.get("client_id") or "").strip()
        client_secret = (goauth.get("client_secret") or "").strip()

        if not client_id or not client_secret:
            raise ValueError(
                "Configure client_id e client_secret do Google OAuth nas Configurações."
            )

        # Try cached token first
        if self._token_path.exists():
            try:
                with open(self._token_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                scopes = self._get_scopes_for_load(data)
                creds = Credentials.from_authorized_user_info(data, scopes)
                if creds.expired and creds.refresh_token:
                    creds.refresh(Request())
                    self._save_token(creds)
                if creds.valid:
                    debug_log(
                        "GoogleAuthManager", "authenticate", "Token em cache válido"
                    )
                    return creds
            except Exception as e:
                debug_log(
                    "GoogleAuthManager",
                    "authenticate",
                    "Token em cache inválido: %s",
                    e,
                )

        # Run OAuth flow (opens browser)
        client_config = _build_client_config(client_id, client_secret)
        flow = InstalledAppFlow.from_client_config(client_config, scopes=SCOPES)
        creds = flow.run_local_server(port=0)
        self._save_token(creds)
        debug_log("GoogleAuthManager", "authenticate", "OAuth concluído, token salvo")
        return creds
