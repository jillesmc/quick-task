#!/bin/bash

# Obter o diretório onde o script está localizado
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mudar para o diretório do script
cd "$SCRIPT_DIR" || exit 1

# Cores para output usando tput
if [ -t 1 ]; then
    # Terminal suporta cores
    RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3)
    NC=$(tput sgr0) # No Color (reset)
else
    # Redirecionamento ou pipe, sem cores
    RED=""
    YELLOW=""
    NC=""
fi

# Função para verificar se um comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Função para imprimir mensagens
error() {
    echo "${RED}Erro:${NC} $1" >&2
}

warn() {
    echo "${YELLOW}Aviso:${NC} $1" >&2
}

# Verificar se mise está disponível (obrigatório)
if ! command_exists mise; then
    error "mise não encontrado no PATH"
    echo "" >&2
    echo "O mise (https://mise.jdx.dev) é obrigatório para este projeto." >&2
    echo "Instale o mise:" >&2
    echo "  curl https://mise.run | sh" >&2
    echo "" >&2
    echo "Após instalar, reinicie o terminal e execute:" >&2
    echo "  mise install" >&2
    exit 1
fi

# Garantir que mise está configurado para este diretório
mise install --yes >/dev/null 2>&1 || {
    error "Falha ao instalar ferramentas do mise"
    echo "Execute manualmente: mise install" >&2
    exit 1
}

# Verificar se acli (Atlassian CLI) está instalado
if ! command_exists acli; then
    error "acli (Atlassian CLI) não encontrado no PATH"
    echo "" >&2
    echo "O acli (Atlassian CLI oficial) deve estar instalado." >&2
    echo "Instale via APT:" >&2
    echo "  sudo apt install acli" >&2
    echo "" >&2
    echo "Mais informações: https://developer.atlassian.com/cloud/acli/guides/install-linux/" >&2
    exit 1
fi

# Verificar se acli está autenticado (opcional, apenas aviso)
if ! acli jira auth status >/dev/null 2>&1; then
    warn "ACLI pode não estar autenticado."
    warn "Autentique-se com: echo \$JIRA_API_TOKEN | acli jira auth login --site \"<seu-site>\" --email \"<seu-email>\" --token"
fi

# Adicionar pacotes do sistema ao PYTHONPATH para acessar PySide2
# PySide2 está instalado via apt em /usr/lib/python3/dist-packages
export PYTHONPATH="/usr/lib/python3/dist-packages:${PYTHONPATH}"

# Executar aplicação usando mise (obrigatório)
mise exec -- python -m src
