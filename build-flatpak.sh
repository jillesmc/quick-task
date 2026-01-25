#!/bin/bash

################################################################################
# Script para construir e testar Flatpak da aplicação Jira Quick Task
# Uso: ./build-flatpak.sh [opção]
#
# Opções:
#   install-deps    - Instala ferramentas e SDKs do Flatpak
#   build           - Constrói e instala o Flatpak localmente (DEFAULT)
#   test            - Executa a aplicação instalada
#   bundle          - Cria arquivo .flatpak para distribuição
#   clean           - Remove build local e aplicação instalada
#   logs            - Mostra logs recentes
#   override        - Abre prompt para modificar permissões
#
################################################################################

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações
APP_ID="org.kde.jira-quick-task"
MANIFEST="flatpak/org.kde.jira-quick-task.json"
BUILD_DIR="build-dir"
REPO_DIR="${HOME}/.local/share/flatpak/repo"

# Funções helper
print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Verificar pré-requisitos
check_requirements() {
    print_header "Verificando Pré-requisitos"
    
    if ! command -v flatpak &> /dev/null; then
        print_error "flatpak não está instalado"
        echo "Instale com: sudo apt install flatpak"
        exit 1
    fi
    print_success "flatpak instalado: $(flatpak --version)"
    
    if ! command -v flatpak-builder &> /dev/null; then
        print_error "flatpak-builder não está instalado"
        echo "Instale com: sudo apt install flatpak-builder"
        exit 1
    fi
    print_success "flatpak-builder instalado"
    
    if [ ! -f "$MANIFEST" ]; then
        print_error "Arquivo '$MANIFEST' não encontrado"
        exit 1
    fi
    print_success "Manifest encontrado: $MANIFEST"
}

# Instalar dependências
install_deps() {
    print_header "Instalando Dependências do Flatpak"
    
    # Verificar se repositório Flathub existe (user ou system)
    FLATHUB_USER=$(flatpak remote-list --user 2>/dev/null | grep -q flathub && echo "yes" || echo "no")
    FLATHUB_SYSTEM=$(flatpak remote-list --system 2>/dev/null | grep -q flathub && echo "yes" || echo "no")
    
    if [ "$FLATHUB_USER" != "yes" ] && [ "$FLATHUB_SYSTEM" != "yes" ]; then
        print_info "Adicionando repositório Flathub (user)..."
        flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo || \
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || \
        print_info "Repositório já existe ou erro ao adicionar"
    else
        print_info "Repositório Flathub já configurado"
    fi
    
    # Determinar se usar --user ou não baseado no repositório disponível
    if [ "$FLATHUB_USER" = "yes" ]; then
        INSTALL_FLAGS="--user"
        REMOTE="flathub"
    elif [ "$FLATHUB_SYSTEM" = "yes" ]; then
        INSTALL_FLAGS=""
        REMOTE="flathub"
    else
        INSTALL_FLAGS="--user"
        REMOTE="flathub"
    fi
    
    print_info "Instalando Platform do freedesktop..."
    flatpak install $INSTALL_FLAGS -y $REMOTE org.freedesktop.Platform//24.08 || print_info "Já instalado ou não disponível"
    
    # KDE Platform Qt 6 - versão 6.7
    print_info "Instalando KDE Platform 6.7 (Qt 6)..."
    flatpak install $INSTALL_FLAGS -y $REMOTE org.kde.Platform//6.7 || print_info "Já instalado ou não disponível"
    
    print_info "Instalando KDE SDK 6.7..."
    flatpak install $INSTALL_FLAGS -y $REMOTE org.kde.Sdk//6.7 || print_info "Já instalado ou não disponível"
    
    # PySide BaseApp para Qt 6
    print_info "Instalando PySide BaseApp 6.7..."
    flatpak install $INSTALL_FLAGS -y $REMOTE io.qt.PySide.BaseApp//6.7 || print_info "Já instalado ou não disponível"
    
    print_success "Todas as dependências instaladas!"
    print_info "Nota: Python 3.11 já vem incluído no BaseApp PySide6"
    print_info "Nota: PySide6 já vem pré-compilado no BaseApp"
}

# Construir Flatpak
build() {
    print_header "Construindo Flatpak"
    
    # Verificar se aplicação já está instalada
    if flatpak info "$APP_ID" &> /dev/null; then
        print_info "Aplicação já instalada, desinstalando..."
        flatpak uninstall --user -y "$APP_ID" || true
    fi
    
    # Limpar build anterior
    if [ -d "$BUILD_DIR" ]; then
        print_info "Limpando build anterior..."
        rm -rf "$BUILD_DIR"
    fi
    
    print_info "Iniciando build com flatpak-builder..."
    print_info "Isso pode demorar alguns minutos na primeira vez...\n"
    
    flatpak-builder \
        --user \
        --install \
        --force-clean \
        --ccache \
        --install-deps-from=flathub \
        "$BUILD_DIR" \
        "$MANIFEST"
    
    if [ $? -eq 0 ]; then
        print_success "Build e instalação concluída!"
        print_info "Aplicação instalada como: $APP_ID"
    else
        print_error "Build falhou!"
        exit 1
    fi
}

# Testar aplicação
test_app() {
    print_header "Testando Aplicação"
    
    if ! flatpak info "$APP_ID" &> /dev/null; then
        print_error "Aplicação não está instalada"
        print_info "Execute: ./build-flatpak.sh build"
        exit 1
    fi
    
    print_info "Iniciando aplicação...\n"
    print_info "A aplicação usa interface gráfica para configuração."
    print_info "Configure a conexão Jira na aba de Configurações após iniciar.\n"
    print_info "Para executar com debug, use:"
    print_info "  flatpak run $APP_ID --debug"
    print_info "  ou"
    print_info "  JIRA_QUICK_TASK_DEBUG=1 flatpak run $APP_ID\n"
    
    # Verificar se --debug foi passado como argumento
    if [ "$1" = "--debug" ] || [ "$2" = "--debug" ]; then
        print_info "Executando com debug habilitado...\n"
        flatpak run "$APP_ID" --debug
    else
        flatpak run "$APP_ID"
    fi
}


# Criar bundle para distribuição
bundle() {
    print_header "Criando Bundle Flatpak para Distribuição"
    
    if ! flatpak info "$APP_ID" &> /dev/null; then
        print_error "Aplicação não está instalada"
        print_info "Execute: ./build-flatpak.sh build"
        exit 1
    fi
    
    if [ ! -d "$REPO_DIR" ]; then
        print_info "Criando repositório flatpak..."
        mkdir -p "$REPO_DIR"
    fi
    
    BUNDLE_FILE="jira-quick-task.flatpak"
    
    print_info "Criando bundle: $BUNDLE_FILE"
    print_info "Isso pode demorar...\n"
    
    flatpak build-bundle \
        "$REPO_DIR" \
        "$BUNDLE_FILE" \
        "$APP_ID"
    
    if [ -f "$BUNDLE_FILE" ]; then
        SIZE=$(du -h "$BUNDLE_FILE" | cut -f1)
        print_success "Bundle criado com sucesso!"
        print_info "Arquivo: $BUNDLE_FILE"
        print_info "Tamanho: $SIZE"
        print_info "\nPara instalar em outro sistema:"
        print_info "  flatpak install $BUNDLE_FILE"
    else
        print_error "Falha ao criar bundle"
        exit 1
    fi
}

# Limpar
clean() {
    print_header "Limpando Dados Locais"
    
    if flatpak info "$APP_ID" &> /dev/null; then
        print_info "Desinstalando aplicação..."
        flatpak uninstall --user -y "$APP_ID"
        print_success "Aplicação desinstalada"
    fi
    
    if [ -d "$BUILD_DIR" ]; then
        print_info "Removendo diretório de build..."
        rm -rf "$BUILD_DIR"
        print_success "Build removido"
    fi
    
    if [ -d ".flatpak-builder" ]; then
        print_info "Removendo cache do builder..."
        rm -rf ".flatpak-builder"
        print_success "Cache removido"
    fi
    
    print_success "Limpeza concluída!"
}

# Ver logs
show_logs() {
    print_header "Logs Recentes da Aplicação"
    
    if ! command -v journalctl &> /dev/null; then
        print_error "journalctl não disponível"
        exit 1
    fi
    
    print_info "Últimos 50 logs:\n"
    journalctl --user -u flatpak -n 50 --no-pager || \
    journalctl --user -n 50 --no-pager | grep -i "jira\|flatpak\|$APP_ID" || \
    print_info "Nenhum log encontrado"
}

# Override permissões
override_perms() {
    print_header "Gerenciador de Permissões"
    
    if ! flatpak info "$APP_ID" &> /dev/null; then
        print_error "Aplicação não está instalada"
        exit 1
    fi
    
    print_info "Permissões atuais:\n"
    flatpak override --user --show "$APP_ID"
    
    echo -e "\n${BLUE}Opções comuns:${NC}"
    echo "  flatpak override --user --filesystem=home $APP_ID"
    echo "  flatpak override --user --share=network $APP_ID"
    echo "  flatpak override --user --filesystem=xdg-config $APP_ID"
    echo -e "\n${BLUE}Para remover todas as overrides:${NC}"
    echo "  flatpak override --user --reset $APP_ID"
}

# Main
main() {
    # Determinar ação
    ACTION="${1:-build}"
    
    case "$ACTION" in
        install-deps)
            check_requirements
            install_deps
            ;;
        build)
            check_requirements
            build
            ;;
        test)
            check_requirements
            test_app
            ;;
        bundle)
            check_requirements
            bundle
            ;;
        clean)
            check_requirements
            clean
            ;;
        logs)
            show_logs
            ;;
        override)
            check_requirements
            override_perms
            ;;
        help|--help|-h)
            head -n 20 "$0"
            ;;
        *)
            print_error "Ação desconhecida: $ACTION"
            echo "Use: ./build-flatpak.sh [install-deps|build|test|bundle|clean|logs|override|help]"
            exit 1
            ;;
    esac
}

main "$@"
