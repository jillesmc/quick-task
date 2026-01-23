#!/bin/bash
# Script para configurar arquivos de configuração do Jira Quick Task no Flatpak
# Cria os arquivos de config em ~/.config/jira-quick-task/ a partir dos templates

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carregar biblioteca comum
# No Flatpak, o script está em /app/bin, então precisamos encontrar common.sh
if [ -f "$SCRIPT_DIR/../scripts/lib/common.sh" ]; then
    source "$SCRIPT_DIR/../scripts/lib/common.sh"
elif [ -f "/app/scripts/lib/common.sh" ]; then
    source "/app/scripts/lib/common.sh"
elif [ -f "scripts/lib/common.sh" ]; then
    source "scripts/lib/common.sh"
else
    # Fallback: definir funções essenciais inline se common.sh não estiver disponível
    init_colors() {
        if [ -t 1 ]; then
            GREEN=$(tput setaf 2)
            YELLOW=$(tput setaf 3)
            BLUE=$(tput setaf 4)
            RED=$(tput setaf 1)
            NC=$(tput sgr0)
        else
            GREEN=""; YELLOW=""; BLUE=""; RED=""; NC=""
        fi
    }
    info() { echo "${GREEN}[INFO]${NC} $1"; }
    warn() { echo "${YELLOW}[WARN]${NC} $1"; }
    note() { echo "${BLUE}[NOTE]${NC} $1"; }
    error() { echo "${RED}[ERROR]${NC} $1" >&2; }
    is_flatpak() { [ -f "/.flatpak-info" ]; }
    adjust_ssl_paths() {
        if is_flatpak; then
            for var in SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE SSL_CERT_DIR; do
                if [ -n "${!var}" ] && [[ "${!var}" == /etc/* ]]; then
                    export "$var"="${!var/#\/etc\//\/run\/host\/etc\/}"
                fi
            done
        fi
    }
    validate_email() { [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; }
    validate_url() { [[ "$1" =~ ^https?:// ]]; }
    read_yaml_value() {
        local file="$1" key="$2"
        [ ! -f "$file" ] && echo "" && return 1
        grep "^${key}:" "$file" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | tr -d '"' | tr -d "'" | tr -d ' ' | grep -v "^#" | grep -v "^$" | grep -v "PREENCHA" || echo ""
    }
    update_yaml_value() {
        local file="$1" key="$2" value="$3"
        [ ! -f "$file" ] || ! grep -q "^${key}:" "$file" && return 1
        local escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sed -i "s|^${key}:.*|${key}: ${escaped_value}|" "$file"
    }
    json_key_exists() {
        local file="$1" key="$2"
        [ ! -f "$file" ] && echo "not_exists" && return 1
        python3 <<EOF 2>/dev/null
import json
try:
    with open('$file', 'r', encoding='utf-8') as f:
        config = json.load(f)
    value = config.get('$key')
    print('exists' if value and str(value).strip() else 'not_exists')
except Exception:
    print('not_exists')
EOF
    }
    update_json_value() {
        local file="$1" key="$2" value="$3"
        [ ! -f "$file" ] && return 1
        python3 <<EOF 2>/dev/null
import json
import sys
try:
    with open('$file', 'r', encoding='utf-8') as f:
        config = json.load(f)
    config['$key'] = '$value'
    with open('$file', 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    print('success')
except Exception as e:
    print(f'ERRO: {e}', file=sys.stderr)
    sys.exit(1)
EOF
    }
    fetch_account_id() {
        local server_url="$1" email="$2" api_token="$3"
        [ -z "$server_url" ] || [ -z "$email" ] || [ -z "$api_token" ] && return 1
        python3 <<EOF
import os, sys, requests
from requests.auth import HTTPBasicAuth
try:
    url = f'$server_url/rest/api/3/myself'
    auth = HTTPBasicAuth('$email', '$api_token')
    response = requests.get(url, auth=auth, timeout=10)
    if response.status_code == 200:
        print(response.json().get('accountId', ''))
    else:
        print(f'ERRO: HTTP {response.status_code}', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERRO: {type(e).__name__}: {str(e)[:150]}', file=sys.stderr)
    sys.exit(1)
EOF
    }
    setup_jira_config() {
        local template_dir="$1" config_dir="$2" force_recreate="${3:-false}" interactive="${4:-true}"
        local jira_email="$5" jira_base_url="$6" jira_api_token="$7"
        local example_config="$template_dir/.jira-config.yml.example"
        local config_file="$config_dir/.jira-config.yml"
        local config_json_example="$template_dir/config.json.example"
        local config_json_file="$config_dir/config.json"
        mkdir -p "$config_dir"
        local need_setup=false
        if [ "$force_recreate" = "true" ] || [ ! -f "$config_file" ]; then
            need_setup=true
            if [ -f "$example_config" ]; then
                [ -f "$config_file" ] && info "Recriando arquivo .jira-config.yml a partir do template..." || info "Configurando arquivo .jira-config.yml..."
                cp "$example_config" "$config_file"
                info "Arquivo .jira-config.yml criado/recriado a partir do template"
            else
                warn "Template .jira-config.yml.example não encontrado em $template_dir"
                return 1
            fi
        else
            info "Arquivo .jira-config.yml já existe, pulando criação"
        fi
        if [ "$need_setup" = "true" ]; then
            if [ -z "$jira_email" ]; then
                [ "$interactive" = "true" ] && [ -t 0 ] && echo "" && read -p "Digite seu e-mail do Jira: " jira_email
            else
                info "Usando e-mail da variável de ambiente: $jira_email"
            fi
            [ -n "$jira_email" ] && validate_email "$jira_email" && update_yaml_value "$config_file" "login" "$jira_email" && info "E-mail configurado: $jira_email" || warn "E-mail não fornecido ou inválido"
            if [ -z "$jira_base_url" ]; then
                [ "$interactive" = "true" ] && [ -t 0 ] && echo "" && read -p "Digite a URL do servidor Jira (ex: https://seu-projeto.atlassian.net): " jira_base_url
            else
                info "Usando server URL da variável de ambiente: $jira_base_url"
            fi
            [ -n "$jira_base_url" ] && validate_url "$jira_base_url" && update_yaml_value "$config_file" "server" "$jira_base_url" && info "Server URL configurado: $jira_base_url" || warn "Server URL não fornecido ou inválido"
        fi
        local need_json_setup=false
        if [ "$force_recreate" = "true" ] || [ ! -f "$config_json_file" ]; then
            need_json_setup=true
            [ -f "$config_json_example" ] && cp "$config_json_example" "$config_json_file" && info "Arquivo config.json criado/recriado a partir do template" || warn "Template config.json.example não encontrado"
        else
            info "Arquivo config.json já existe, pulando criação"
        fi
        if [ -f "$config_json_file" ] && [ -n "$jira_api_token" ]; then
            [ "$(json_key_exists "$config_json_file" "account_id")" != "exists" ] && [ -f "$config_file" ] && {
                [ -z "$jira_email" ] && jira_email=$(read_yaml_value "$config_file" "login")
                local server_url="${jira_base_url:-$(read_yaml_value "$config_file" "server")}"
                [ -n "$server_url" ] && [ -n "$jira_email" ] && {
                    server_url="${server_url%/}"
                    info "Buscando accountId na API do Jira..."
                    local account_id=$(fetch_account_id "$server_url" "$jira_email" "$jira_api_token" 2>&1)
                    [ -n "$account_id" ] && [[ ! "$account_id" =~ ^ERRO ]] && update_json_value "$config_json_file" "account_id" "$account_id" >/dev/null 2>&1 && info "accountId configurado automaticamente: $account_id" || [ -n "$account_id" ] && error "$account_id" || warn "Não foi possível obter accountId"
                } || warn "URL do servidor ou email não encontrado"
            } || info "accountId já está configurado no config.json"
        fi
        return 0
    }
    init_colors
fi

# No Flatpak, XDG_CONFIG_HOME aponta para o sandbox
# O finish-args permite acesso a xdg-config/jira-quick-task
if is_flatpak; then
    CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jira-quick-task"
    TEMPLATE_DIR="/app/share/jira-quick-task/config"
    info "Detectado ambiente Flatpak"
    USE_FLATPAK_CMD=false
    # No Flatpak, ler variáveis de ambiente do processo pai
    # (elas são passadas automaticamente pelo flatpak run)
    JIRA_API_TOKEN=$(printenv JIRA_API_TOKEN 2>/dev/null || echo "")
    JIRA_EMAIL=$(printenv JIRA_EMAIL 2>/dev/null || echo "")
    JIRA_BASE_URL=$(printenv JIRA_BASE_URL 2>/dev/null || echo "")
    
    # Ajustar caminhos SSL herdados do host para o sandbox
    adjust_ssl_paths
else
    TEMPLATE_DIR="$SCRIPT_DIR/config"
    info "Detectado ambiente local"
    USE_FLATPAK_CMD=true
    # Fora do Flatpak, ler do ambiente atual
    JIRA_API_TOKEN=$(printenv JIRA_API_TOKEN 2>/dev/null || echo "")
    JIRA_EMAIL=$(printenv JIRA_EMAIL 2>/dev/null || echo "")
    JIRA_BASE_URL=$(printenv JIRA_BASE_URL 2>/dev/null || echo "")
fi

FLATPAK_CONFIG_DIR="/app/share/jira-quick-task/config"
APP_ID="org.kde.jira-quick-task"

# Configurar arquivos de configuração do Jira usando função compartilhada
# No Flatpak, sempre recriar (force_recreate=true)
setup_jira_config "$TEMPLATE_DIR" "$CONFIG_DIR" "true" "true" "$JIRA_EMAIL" "$JIRA_BASE_URL" "$JIRA_API_TOKEN"

CONFIG_FILE="$CONFIG_DIR/.jira-config.yml"
CONFIG_JSON_FILE="$CONFIG_DIR/config.json"

# Mensagens finais sobre token
if [ -z "$JIRA_API_TOKEN" ]; then
    warn "IMPORTANTE: Configure o token Jira:"
    echo "  1. Obtenha um token em: https://id.atlassian.com/manage-profile/security/api-tokens"
    echo "  2. Configure o token: export JIRA_API_TOKEN=<seu-token>"
    echo "  3. Para tornar permanente, adicione ao ~/.bashrc ou ~/.zshrc:"
    echo "     echo 'export JIRA_API_TOKEN=<seu-token>' >> ~/.bashrc"
    echo ""
    if [ -n "$JIRA_EMAIL" ]; then
        echo "  O email já está configurado no arquivo $CONFIG_FILE"
        echo "  Após configurar o token, execute este script novamente para buscar o accountId automaticamente"
    fi
fi

echo ""
info "Configuração concluída!"
if is_flatpak; then
    # Dentro do Flatpak, mostrar caminho do sandbox
    SANDBOX_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/jira-quick-task"
    note "Arquivos de configuração criados no sandbox do Flatpak:"
    note "  $SANDBOX_CONFIG"
    note ""
    note "Para acessar de fora do Flatpak, os arquivos estão em:"
    note "  ~/.var/app/org.kde.jira-quick-task/config/jira-quick-task/"
else
    note "Arquivos de configuração em: $CONFIG_DIR"
fi
note ""
note "Arquivos criados:"
note "  - $CONFIG_FILE"
note "  - $CONFIG_JSON_FILE"
note ""
if [ -z "$JIRA_API_TOKEN" ]; then
    note "Próximo passo: Configure JIRA_API_TOKEN e execute este script novamente"
elif [ -n "$JIRA_EMAIL" ] && [ -n "$JIRA_BASE_URL" ]; then
    note "✓ Email configurado: $JIRA_EMAIL"
    note "✓ Server URL configurado: $JIRA_BASE_URL"
    note "✓ Token encontrado"
    note ""
    note "Aplicação pronta para uso!"
fi
