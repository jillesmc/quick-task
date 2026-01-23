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

# Executar a aplicação Python
exec python3 -m src "$@"
