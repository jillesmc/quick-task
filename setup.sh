#!/bin/bash

# Script de setup para Jira Quick Task
# Este script ajuda a configurar o ambiente de desenvolvimento

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Cores para output usando tput
if [ -t 1 ]; then
    # Terminal suporta cores
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    NC=$(tput sgr0) # No Color (reset)
else
    # Redirecionamento ou pipe, sem cores
    RED=""
    GREEN=""
    YELLOW=""
    NC=""
fi

# Função para imprimir mensagens
info() {
    echo "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo "${RED}[ERROR]${NC} $1"
}

# Função para verificar se um comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Função para verificar se um pacote está instalado (Debian/Ubuntu)
package_installed() {
    dpkg -l | grep -q "^ii  $1 " 2>/dev/null
}

info "Verificando pré-requisitos..."

# Verificar mise (obrigatório)
if ! command_exists mise; then
    error "mise não encontrado (obrigatório)"
    echo "  Instale o mise: curl https://mise.run | sh"
    echo "  Mais informações: https://mise.jdx.dev"
    exit 1
fi

info "mise encontrado: $(mise --version)"
info "Instalando ferramentas do .mise.toml..."
if ! mise install --yes; then
    error "Falha ao instalar ferramentas do mise"
    echo "Execute manualmente: mise install"
    exit 1
fi

# Verificar se Python está instalado via mise
if ! mise which python >/dev/null 2>&1; then
    error "Python não encontrado no mise"
    echo "Execute: mise install"
    exit 1
fi

PYTHON_VERSION=$(mise exec -- python --version)
info "Python via mise: $PYTHON_VERSION"

# Verificar dependências do sistema
MISSING_PACKAGES=()

if ! package_installed python3-pyside2.qtcore; then
    MISSING_PACKAGES+=("python3-pyside2.qtcore")
fi

if ! package_installed python3-pyside2.qtgui; then
    MISSING_PACKAGES+=("python3-pyside2.qtgui")
fi

if ! package_installed python3-pyside2.qtqml; then
    MISSING_PACKAGES+=("python3-pyside2.qtqml")
fi

if ! package_installed python3-pyside2.qtwidgets; then
    MISSING_PACKAGES+=("python3-pyside2.qtwidgets")
fi

if ! package_installed qml-module-org-kde-kirigami2; then
    MISSING_PACKAGES+=("qml-module-org-kde-kirigami2")
fi

if ! package_installed python3-xlib; then
    MISSING_PACKAGES+=("python3-xlib")
fi

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    warn "Pacotes do sistema faltando: ${MISSING_PACKAGES[*]}"
    read -p "Deseja instalar os pacotes faltantes? (s/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        info "Instalando pacotes do sistema..."
        sudo apt update
        sudo apt install -y "${MISSING_PACKAGES[@]}"
        info "Pacotes instalados com sucesso"
    else
        warn "Pacotes não instalados. A aplicação pode não funcionar corretamente."
    fi
else
    info "Todos os pacotes do sistema estão instalados"
fi


# Verificar token de API do Jira
if [ -n "$JIRA_API_TOKEN" ]; then
    info "JIRA_API_TOKEN encontrado na variável de ambiente"
else
    warn "JIRA_API_TOKEN não encontrado na variável de ambiente"
    echo ""
    echo "A aplicação usa Jira REST API v3 diretamente e requer um token de API."
    echo ""
    echo "Para obter um token:"
    echo "  1. Acesse: https://id.atlassian.com/manage-profile/security/api-tokens"
    echo "  2. Clique em 'Create API token'"
    echo "  3. Dê um nome ao token (ex: 'Jira Quick Task')"
    echo "  4. Copie o token gerado"
    echo ""
    echo "Configure o token:"
    echo "  export JIRA_API_TOKEN=<seu-token>"
    echo ""
    echo "Para tornar permanente, adicione ao ~/.bashrc ou ~/.zshrc:"
    echo "  echo 'export JIRA_API_TOKEN=<seu-token>' >> ~/.bashrc"
    echo ""
fi

# Instalar dependências Python
if [ -f "requirements.txt" ]; then
    info "Instalando dependências Python..."
    if mise exec -- pip install -r requirements.txt; then
        info "Dependências Python instaladas com sucesso"
    else
        warn "Falha ao instalar dependências Python"
        echo "Execute manualmente: mise exec -- pip install -r requirements.txt"
    fi
else
    warn "Arquivo requirements.txt não encontrado"
fi

# Tornar script executável
chmod +x jira-quick-task.sh

# Instalar ícones (SVG + PNG) no diretório padrão do sistema
ICON_SVG_SOURCE="$SCRIPT_DIR/assets/jira-quick-task.svg"
ICON_BASE_NAME="jira-quick-task"
ICON_THEME_DIR="$HOME/.local/share/icons/hicolor"

if [ -f "$ICON_SVG_SOURCE" ]; then
    info "Instalando ícones da aplicação..."

    # 1) SVG escalável
    ICON_SVG_INSTALL_DIR="$ICON_THEME_DIR/scalable/apps"
    mkdir -p "$ICON_SVG_INSTALL_DIR"
    cp "$ICON_SVG_SOURCE" "$ICON_SVG_INSTALL_DIR/$ICON_BASE_NAME.svg"
    info "Ícone SVG instalado em $ICON_SVG_INSTALL_DIR/$ICON_BASE_NAME.svg"

    # 2) PNGs em tamanhos fixos (fallback para componentes que não suportam SVG)
    ICON_SIZES=("16" "22" "24" "32" "48" "64" "128" "256")
    for size in "${ICON_SIZES[@]}"; do
        PNG_SOURCE="$SCRIPT_DIR/assets/${ICON_BASE_NAME}-${size}.png"
        if [ -f "$PNG_SOURCE" ]; then
            ICON_PNG_INSTALL_DIR="$ICON_THEME_DIR/${size}x${size}/apps"
            mkdir -p "$ICON_PNG_INSTALL_DIR"
            cp "$PNG_SOURCE" "$ICON_PNG_INSTALL_DIR/$ICON_BASE_NAME.png"
            info "Ícone PNG ${size}x${size} instalado em $ICON_PNG_INSTALL_DIR/$ICON_BASE_NAME.png"
        else
            warn "PNG ${size}x${size} não encontrado em $PNG_SOURCE (pulei este tamanho)"
        fi
    done

    # 3) Atualizar cache de ícones (se disponível)
    if command_exists gtk-update-icon-cache; then
        gtk-update-icon-cache -f -t "$ICON_THEME_DIR" 2>/dev/null || true
        info "Cache de ícones atualizado para $ICON_THEME_DIR"
    else
        warn "gtk-update-icon-cache não encontrado, cache de ícones não foi atualizado"
    fi
else
    warn "Ícone SVG não encontrado: $ICON_SVG_SOURCE"
fi

# Processar template .desktop e instalar
DESKTOP_TEMPLATE="org.kde.jira-quick-task.desktop.in"
DESKTOP_FILE="org.kde.jira-quick-task.desktop"
DESKTOP_INSTALL_DIR="$HOME/.local/share/applications"

if [ -f "$DESKTOP_TEMPLATE" ]; then
    info "Processando template .desktop..."
    
    # Criar arquivo .desktop a partir do template
    sed "s|@SCRIPT_DIR@|$SCRIPT_DIR|g" "$DESKTOP_TEMPLATE" > "$DESKTOP_FILE"
    
    # Criar diretório de aplicações se não existir
    mkdir -p "$DESKTOP_INSTALL_DIR"
    
    # Copiar arquivo .desktop para diretório de aplicações
    cp "$DESKTOP_FILE" "$DESKTOP_INSTALL_DIR/"
    info "Arquivo .desktop instalado em $DESKTOP_INSTALL_DIR/"
    
    # Atualizar cache do desktop database
    if command_exists update-desktop-database; then
        update-desktop-database "$DESKTOP_INSTALL_DIR" 2>/dev/null || true
        info "Cache do desktop database atualizado"
    else
        warn "update-desktop-database não encontrado, cache não foi atualizado"
    fi
else
    warn "Template .desktop não encontrado: $DESKTOP_TEMPLATE"
fi

# Configurar arquivo .jira-config.yml a partir do template
CONFIG_DIR="$SCRIPT_DIR/config"
EXAMPLE_CONFIG="$CONFIG_DIR/.jira-config.yml.example"
CONFIG_FILE="$CONFIG_DIR/.jira-config.yml"
CONFIG_JSON_FILE="$CONFIG_DIR/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "$EXAMPLE_CONFIG" ]; then
        info "Configurando arquivo .jira-config.yml..."
        
        # Copiar template
        cp "$EXAMPLE_CONFIG" "$CONFIG_FILE"
        info "Arquivo .jira-config.yml criado a partir do template"
        
        # Pedir e-mail do usuário
        echo ""
        read -p "Digite seu e-mail do Jira: " JIRA_EMAIL
        
        if [ -n "$JIRA_EMAIL" ]; then
            # Validar formato básico de e-mail
            if [[ "$JIRA_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                # Substituir o placeholder pelo e-mail
                # Procura por "login: # PREENCHA COM SEU EMAIL AQUI" ou qualquer linha que comece com "login:"
                # e substitui pelo e-mail fornecido
                if grep -q "^login:" "$CONFIG_FILE"; then
                    # Escapar caracteres especiais no e-mail para sed
                    ESCAPED_EMAIL=$(printf '%s\n' "$JIRA_EMAIL" | sed 's/[[\.*^$()+?{|]/\\&/g')
                    # Substituir qualquer linha que comece com "login:" seguido de qualquer coisa
                    sed -i "s|^login:.*|login: $ESCAPED_EMAIL|" "$CONFIG_FILE"
                    info "E-mail configurado: $JIRA_EMAIL"
                else
                    warn "Linha 'login:' não encontrada no arquivo de configuração"
                fi
            else
                warn "Formato de e-mail inválido. Você precisará editar $CONFIG_FILE manualmente"
            fi
        else
            warn "E-mail não fornecido. Você precisará editar $CONFIG_FILE manualmente"
        fi
        
        echo ""
        info "Arquivo de configuração criado: $CONFIG_FILE"
        
        # Verificar se JIRA_API_TOKEN está configurado
        if [ -n "$JIRA_API_TOKEN" ]; then
            info "JIRA_API_TOKEN encontrado na variável de ambiente"
            info "A aplicação está pronta para usar a REST API do Jira"
            info "O accountId será buscado automaticamente após a criação do config.json"
        else
            warn "IMPORTANTE: Configure o token Jira:"
            echo "  1. Obtenha um token em: https://id.atlassian.com/manage-profile/security/api-tokens"
            echo "  2. Configure o token: export JIRA_API_TOKEN=<seu-token>"
            echo "  3. Para tornar permanente, adicione ao ~/.bashrc ou ~/.zshrc:"
            echo "     echo 'export JIRA_API_TOKEN=<seu-token>' >> ~/.bashrc"
            echo ""
            echo "  O email já está configurado no arquivo $CONFIG_FILE"
            echo "  Após configurar o token, execute o setup novamente para buscar o accountId automaticamente"
        fi
    else
        warn "Template .jira-config.yml.example não encontrado em $CONFIG_DIR"
    fi
else
    info "Arquivo .jira-config.yml já existe, pulando criação"
fi

# Configurar arquivo config.json a partir do template
CONFIG_JSON_EXAMPLE="$CONFIG_DIR/config.json.example"

if [ ! -f "$CONFIG_JSON_FILE" ]; then
    if [ -f "$CONFIG_JSON_EXAMPLE" ]; then
        info "Configurando arquivo config.json..."
        
        # Copiar template
        cp "$CONFIG_JSON_EXAMPLE" "$CONFIG_JSON_FILE"
        info "Arquivo config.json criado a partir do template"
    else
        warn "Template config.json.example não encontrado em $CONFIG_DIR"
    fi
else
    info "Arquivo config.json já existe, pulando criação"
fi

# Verificar e buscar accountId se necessário
# Só busca se: accountId não estiver no config.json E JIRA_API_TOKEN estiver configurado
if [ -f "$CONFIG_JSON_FILE" ] && [ -n "$JIRA_API_TOKEN" ]; then
    # Verificar se accountId já está no config.json
    ACCOUNT_ID_EXISTS=$(mise exec -- python3 <<EOF
import json
import sys

try:
    with open("${CONFIG_JSON_FILE}", 'r', encoding='utf-8') as f:
        config = json.load(f)
    
    account_id = config.get("account_id")
    if account_id and account_id.strip():
        print("exists")
    else:
        print("not_exists")
except Exception:
    print("not_exists")
EOF
)
    
    if [ "$ACCOUNT_ID_EXISTS" != "exists" ]; then
        # accountId não existe, vamos buscar
        info "accountId não encontrado no config.json, buscando..."
        
        # Ler email do .jira-config.yml
        if [ -f "$CONFIG_FILE" ]; then
            JIRA_EMAIL=$(grep "^login:" "$CONFIG_FILE" | sed 's/^login:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d ' ')
            
            if [ -n "$JIRA_EMAIL" ]; then
                # Extrair server URL do .jira-config.yml
                SERVER_URL=$(grep "^server:" "$CONFIG_FILE" | sed 's/^server:[[:space:]]*//' | tr -d '"' | tr -d "'")
                
                if [ -n "$SERVER_URL" ]; then
                    # Remover trailing slash se houver
                    SERVER_URL="${SERVER_URL%/}"
                    
                    # Fazer chamada GET /myself para obter accountId
                    ACCOUNT_ID=$(mise exec -- python3 <<EOF
import json
import os
import sys
import requests
from requests.auth import HTTPBasicAuth

server_url = "${SERVER_URL}"
email = "${JIRA_EMAIL}"
api_token = os.environ.get("JIRA_API_TOKEN")

if not api_token:
    print("JIRA_API_TOKEN não encontrado", file=sys.stderr)
    sys.exit(1)

try:
    url = f"{server_url}/rest/api/3/myself"
    auth = HTTPBasicAuth(email, api_token)
    response = requests.get(url, auth=auth, timeout=10)
    
    if response.status_code == 200:
        data = response.json()
        account_id = data.get("accountId")
        if account_id:
            print(account_id)
        else:
            print("accountId não encontrado na resposta", file=sys.stderr)
            sys.exit(1)
    else:
        print(f"Erro ao buscar accountId: HTTP {response.status_code}", file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f"Erro ao buscar accountId: {e}", file=sys.stderr)
    sys.exit(1)
EOF
)
                    
                    if [ $? -eq 0 ] && [ -n "$ACCOUNT_ID" ]; then
                        # Atualizar config.json com accountId
                        mise exec -- python3 <<EOF
import json
import sys

config_file = "${CONFIG_JSON_FILE}"
account_id = "${ACCOUNT_ID}"

try:
    with open(config_file, 'r', encoding='utf-8') as f:
        config = json.load(f)
    
    config['account_id'] = account_id
    
    with open(config_file, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    
    print(f"accountId salvo no config.json: {account_id}")
except Exception as e:
    print(f"Erro ao salvar accountId: {e}", file=sys.stderr)
    sys.exit(1)
EOF
                        if [ $? -eq 0 ]; then
                            info "accountId configurado com sucesso no config.json"
                        else
                            warn "Não foi possível salvar accountId no config.json"
                        fi
                    else
                        warn "Não foi possível obter accountId. A aplicação tentará buscar automaticamente quando necessário."
                    fi
                else
                    warn "Server URL não encontrado no .jira-config.yml. Não foi possível buscar accountId."
                fi
            else
                warn "Email não encontrado no .jira-config.yml. Não foi possível buscar accountId."
            fi
        else
            warn "Arquivo .jira-config.yml não encontrado. Não foi possível buscar accountId."
        fi
    else
        info "accountId já está configurado no config.json, pulando busca"
    fi
fi

info "Setup concluído!"
echo ""
info "Próximos passos:"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "  1. Crie o arquivo de configuração: cp $EXAMPLE_CONFIG $CONFIG_FILE"
    echo "  2. Configure seu e-mail no arquivo $CONFIG_FILE"
fi
if [ -z "$JIRA_API_TOKEN" ]; then
    echo "  3. Obtenha um token de API em: https://id.atlassian.com/manage-profile/security/api-tokens"
    echo "  4. Configure o token: export JIRA_API_TOKEN=<seu-token>"
    echo "  5. Para tornar permanente, adicione ao ~/.bashrc ou ~/.zshrc:"
    echo "     echo 'export JIRA_API_TOKEN=<seu-token>' >> ~/.bashrc"
else
    echo "  3. Token JIRA_API_TOKEN já está configurado"
fi
echo "  6. Execute a aplicação: ./jira-quick-task.sh"
echo "  7. A aplicação está disponível no menu de aplicações do seu desktop environment"