# ============================================================================
# Makefile para Jira Quick Task
# Desenvolvimento/Testes: Docker | Distribuição: Flatpak
# ============================================================================

# Cores usando tput
ifneq ($(TERM),)
	RED := $(shell tput setaf 1)
	GREEN := $(shell tput setaf 2)
	YELLOW := $(shell tput setaf 3)
	BLUE := $(shell tput setaf 4)
	CYAN := $(shell tput setaf 6)
	RESET := $(shell tput sgr0)
else
	RED :=
	GREEN :=
	YELLOW :=
	BLUE :=
	CYAN :=
	RESET :=
endif

# Variáveis Flatpak
APP_ID := org.kde.jira-quick-task
MANIFEST := flatpak/org.kde.jira-quick-task.json
BUILD_DIR := build-dir

# qmllint: use ./6.10.2/gcc_64/bin/qmllint se existir no projeto, senão Qt em HOME
_QMLLINT_PROJECT := $(wildcard $(CURDIR)/6.10.2/gcc_64/bin/qmllint)
QMLLINT ?= $(if $(_QMLLINT_PROJECT),$(_QMLLINT_PROJECT),/home/jilles/Qt6/6.10.2/gcc_64/bin/qmllint)
# Import paths para qmllint (Kirigami, Qt QML, projeto)
QML_IMPORT_PATHS := /snap/kf6-core24-sdk/current/usr/lib/x86_64-linux-gnu/qml:/home/jilles/Qt6/6.10.2/gcc_64/qml:$(CURDIR)/src/qml
QML2_IMPORT_PATHS := $(QML_IMPORT_PATHS)

# ============================================================================
# Help
# ============================================================================

.PHONY: help
help:
	@echo "$(CYAN)Comandos disponíveis:$(RESET)"
	@echo ""
	@echo "$(GREEN)Desenvolvimento e Testes (Docker):$(RESET)"
	@echo "  $(YELLOW)make dev-build$(RESET)  - Constrói imagem Docker para desenvolvimento"
	@echo "  $(YELLOW)make dev-test$(RESET)   - Executa testes unitários no Docker"
	@echo "  $(YELLOW)make dev-shell$(RESET) - Abre shell interativo no container Docker"
	@echo "  $(YELLOW)make dev-format$(RESET) - Formata código com black no Docker"
	@echo "  $(YELLOW)make dev-clean$(RESET)  - Remove containers e imagens Docker"
	@echo ""
	@echo "$(GREEN)Flatpak (Distribuição):$(RESET)"
	@echo "  $(YELLOW)make install-deps$(RESET)   - Instala SDKs e dependências do Flatpak"
	@echo "  $(YELLOW)make build$(RESET)          - Constrói e instala o Flatpak localmente"
	@echo "  $(YELLOW)make run$(RESET)            - Executa a aplicação Flatpak instalada"
	@echo "  $(YELLOW)make run-debug$(RESET)      - Executa a aplicação com saída de debug"
	@echo "  $(YELLOW)make dev$(RESET)            - Build + Run (útil durante desenvolvimento)"
	@echo "  $(YELLOW)make bundle$(RESET)         - Cria arquivo .flatpak para distribuição"
	@echo "  $(YELLOW)make clean-build$(RESET)   - Remove build e aplicação Flatpak instalada"
	@echo ""
	@echo "$(GREEN)Utilitários:$(RESET)"
	@echo "  $(YELLOW)make clean$(RESET)    - Remove arquivos gerados (__pycache__, .pyc, .qmlc, etc)"
	@echo "  $(YELLOW)make qml-lint$(RESET)  - Executa qmllint nos QML (QML_IMPORT_PATH + QML2_IMPORT_PATH)"
	@echo ""

# ============================================================================
# Docker (Desenvolvimento e Testes)
# ============================================================================

.PHONY: check-docker
check-docker:
	@echo "$(CYAN)Verificando Docker...$(RESET)"
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "$(RED)✗ docker não está instalado$(RESET)"; \
		echo "$(YELLOW)Instale com: sudo apt install docker.io docker-compose$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ docker instalado$(RESET)"
	@if ! docker info >/dev/null 2>&1; then \
		echo "$(RED)✗ docker não está rodando ou você não tem permissão$(RESET)"; \
		echo "$(YELLOW)Verifique: sudo systemctl start docker$(RESET)"; \
		echo "$(YELLOW)Ou adicione seu usuário ao grupo docker: sudo usermod -aG docker $$USER$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ docker está rodando$(RESET)"

# Detectar versão do Docker Compose (v2: docker compose, v1: docker-compose)
DOCKER_COMPOSE := $(shell docker compose version >/dev/null 2>&1 && echo "docker compose" || echo "docker-compose")
# Rodar como usuário do host para não gerar arquivos como root
DOCKER_UID := $(shell id -u)
DOCKER_GID := $(shell id -g)
DOCKER_USER := UID=$(DOCKER_UID) GID=$(DOCKER_GID)

.PHONY: dev-build
dev-build: check-docker
	@echo "$(CYAN)Construindo imagem Docker para desenvolvimento...$(RESET)"
	@$(DOCKER_COMPOSE) build

.PHONY: dev-test
dev-test: check-docker
	@echo "$(CYAN)Executando testes no Docker...$(RESET)"
	@$(DOCKER_USER) $(DOCKER_COMPOSE) run --rm dev python3 -m pytest tests/ -v --tb=short

.PHONY: dev-shell
dev-shell: check-docker
	@echo "$(CYAN)Abrindo shell interativo no container...$(RESET)"
	@$(DOCKER_USER) $(DOCKER_COMPOSE) run --rm dev /bin/bash

.PHONY: dev-format
dev-format: check-docker
	@echo "$(CYAN)Formatando código com black no Docker...$(RESET)"
	@$(DOCKER_USER) $(DOCKER_COMPOSE) run --rm dev black src/ core/ config/ tests/
	@echo "$(GREEN)✓ Código formatado$(RESET)"

.PHONY: dev-clean
dev-clean: check-docker
	@echo "$(CYAN)Limpando containers e imagens Docker...$(RESET)"
	@$(DOCKER_COMPOSE) down -v
	@docker rmi jira-quick-task_dev 2>/dev/null || true
	@echo "$(GREEN)✓ Limpeza concluída$(RESET)"

# ============================================================================
# Flatpak (Distribuição)
# ============================================================================

.PHONY: check-flatpak
check-flatpak:
	@echo "$(CYAN)Verificando Flatpak...$(RESET)"
	@if ! command -v flatpak >/dev/null 2>&1; then \
		echo "$(RED)✗ flatpak não está instalado$(RESET)"; \
		echo "$(YELLOW)Instale com: sudo apt install flatpak$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ flatpak instalado: $$(flatpak --version)$(RESET)"
	@if ! command -v flatpak-builder >/dev/null 2>&1; then \
		echo "$(RED)✗ flatpak-builder não está instalado$(RESET)"; \
		echo "$(YELLOW)Instale com: sudo apt install flatpak-builder$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ flatpak-builder instalado$(RESET)"
	@if [ ! -f "$(MANIFEST)" ]; then \
		echo "$(RED)✗ Arquivo '$(MANIFEST)' não encontrado$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ Manifest encontrado: $(MANIFEST)$(RESET)"

.PHONY: install-deps
install-deps: check-flatpak
	@echo "$(CYAN)Instalando dependências do Flatpak...$(RESET)"
	@./build-flatpak.sh install-deps

.PHONY: build
build: check-flatpak
	@echo "$(CYAN)Construindo Flatpak...$(RESET)"
	@./build-flatpak.sh build

.PHONY: run
run: check-flatpak
	@echo "$(CYAN)Executando aplicação Flatpak...$(RESET)"
	@./build-flatpak.sh test

.PHONY: run-debug
run-debug: check-flatpak
	@echo "$(CYAN)Executando aplicação Flatpak com debug...$(RESET)"
	@flatpak run org.kde.jira-quick-task --debug

.PHONY: dev
dev: check-flatpak
	@echo "$(CYAN)Build + Run (desenvolvimento)...$(RESET)"
	@./build-flatpak.sh build
	@echo ""
	@echo "$(CYAN)Executando aplicação Flatpak com debug...$(RESET)"
	@flatpak run org.kde.jira-quick-task --debug

.PHONY: bundle
bundle: check-flatpak
	@echo "$(CYAN)Criando bundle Flatpak para distribuição...$(RESET)"
	@./build-flatpak.sh bundle

.PHONY: clean-build
clean-build: check-flatpak
	@echo "$(CYAN)Limpando dados do Flatpak...$(RESET)"
	@./build-flatpak.sh clean

# ============================================================================
# Utilitários
# ============================================================================

.PHONY: qml-lint
qml-lint:
	@echo "$(CYAN)Executando qmllint nos QML...$(RESET)"
	@QML_IMPORT_PATH="$(QML_IMPORT_PATHS)" QML2_IMPORT_PATH="$(QML2_IMPORT_PATHS)" "$(QMLLINT)" $$(find src/qml -name '*.qml') 2>&1 || true

.PHONY: clean
clean:
	@echo "$(CYAN)Limpando arquivos gerados...$(RESET)"
	@find . -type d -name "__pycache__" -prune -exec rm -r {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@find . -type f -name "*.pyo" -delete 2>/dev/null || true
	@find . -type f -name "*.qmlc" -delete 2>/dev/null || true
	@find . -type d -name "*.egg-info" -prune -exec rm -r {} + 2>/dev/null || true
	@find . -type d -name ".pytest_cache" -prune -exec rm -r {} + 2>/dev/null || true
	@find . -type d -name ".mypy_cache" -prune -exec rm -r {} + 2>/dev/null || true
	@rm -rf .coverage htmlcov .tox .nox 2>/dev/null || true
	@echo "$(GREEN)✓ Limpeza concluída$(RESET)"
