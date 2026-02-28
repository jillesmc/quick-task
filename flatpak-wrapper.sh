#!/bin/bash
# Wrapper script para executar a aplicação dentro do Flatpak
# Ajusta apenas os caminhos das env vars herdadas do host para o sandbox

# Carregar biblioteca comum
# No Flatpak, o script está em /app/bin, então precisamos encontrar o projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Tentar encontrar common.sh (pode estar no build ou no projeto)
if [ -f "$SCRIPT_DIR/../scripts/lib/common.sh" ]; then
    source "$SCRIPT_DIR/../scripts/lib/common.sh"
elif [ -f "/app/scripts/lib/common.sh" ]; then
    source "/app/scripts/lib/common.sh"
else
    # Fallback: definir função inline se common.sh não estiver disponível
    adjust_ssl_paths() {
        if [ -f "/.flatpak-info" ]; then
            for var in SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE SSL_CERT_DIR; do
                if [ -n "${!var}" ] && [[ "${!var}" == /etc/* ]]; then
                    export "$var"="${!var/#\/etc\//\/run\/host\/etc\/}"
                fi
            done
        fi
    }
fi

# Ajustar caminhos SSL se necessário
adjust_ssl_paths

# No Flatpak: garantir que usamos o app instalado em /app, não o source do host.
# Sem isso, se o usuário rodar flatpak run do diretório do projeto, Python encontra
# src/ no cwd e usa Path(__file__) do host → QML/Kirigami do runtime não batem.
if [ -f "/.flatpak-info" ]; then
    cd /app

    DEST="${XDG_CONFIG_HOME:-$HOME/.config}/jira-quick-task"
    mkdir -p "$DEST"
    BUNDLE_CONFIG="/app/share/jira-quick-task/config"

    # First-run: se não existir config no destino, copiar defaults do bundle.
    if [ ! -f "$DEST/config.json" ] && [ -d "$BUNDLE_CONFIG" ]; then
        for f in config.json jira_metadata.json .jira-config.yml; do
            if [ -f "$BUNDLE_CONFIG/$f" ]; then
                cp -f "$BUNDLE_CONFIG/$f" "$DEST/$f" 2>/dev/null || true
            fi
        done
    fi

    # Sincronizar config do host para o dir do Flatpak (XDG_CONFIG_HOME).
    # Assim config.json, jira_metadata.json e .jira-config.yml em ~/.config/jira-quick-task/
    # ficam disponíveis onde a app procura (mesmo padrão dos outros ficheiros).
    HOST_CONFIG="${HOME}/.config/jira-quick-task"
    if [ -d "$HOST_CONFIG" ]; then
        for f in config.json jira_metadata.json .jira-config.yml; do
            if [ -f "$HOST_CONFIG/$f" ]; then
                cp -f "$HOST_CONFIG/$f" "$DEST/$f" 2>/dev/null || true
            fi
        done
    fi
fi

# A aplicação não lê mais variáveis de ambiente - tudo vem da tela de configuração
# O token é lido diretamente do .jira-config.yml pelo código Python quando necessário

# Executar a aplicação Python
exec python3 -m src "$@"
