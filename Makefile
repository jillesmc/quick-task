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

# ============================================================================
# Help
# ============================================================================

.PHONY: help
help:
	@echo "$(CYAN)Comandos disponíveis:$(RESET)"
	@echo ""
	@echo "$(GREEN)Desenvolvimento e Testes (Docker):$(RESET)"
	@echo "  $(YELLOW)make docker-build$(RESET)      - Constrói imagem Docker para desenvolvimento"
	@echo "  $(YELLOW)make docker-test$(RESET)       - Executa testes unitários no Docker"
	@echo "  $(YELLOW)make docker-shell$(RESET)      - Abre shell interativo no container Docker"
	@echo "  $(YELLOW)make docker-clean$(RESET)      - Remove containers e imagens Docker"
	@echo ""
	@echo "$(GREEN)Flatpak (Distribuição):$(RESET)"
	@echo "  $(YELLOW)make flatpak-install-deps$(RESET) - Instala SDKs e dependências do Flatpak"
	@echo "  $(YELLOW)make flatpak-build$(RESET)     - Constrói e instala o Flatpak localmente"
	@echo "  $(YELLOW)make flatpak-run$(RESET)       - Executa a aplicação Flatpak instalada"
	@echo "  $(YELLOW)make flatpak-clean$(RESET)     - Remove build e aplicação Flatpak instalada"
	@echo ""
	@echo "$(GREEN)Utilitários:$(RESET)"
	@echo "  $(YELLOW)make format$(RESET)             - Formata código com black (requer black no host ou Docker)"
	@echo "  $(YELLOW)make clean$(RESET)             - Remove arquivos gerados (__pycache__, .pyc, etc)"
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

.PHONY: docker-build
docker-build: check-docker
	@echo "$(CYAN)Construindo imagem Docker para desenvolvimento...$(RESET)"
	@$(DOCKER_COMPOSE) build

.PHONY: docker-test
docker-test: check-docker
	@echo "$(CYAN)Executando testes no Docker...$(RESET)"
	@$(DOCKER_COMPOSE) run --rm dev python3 -m pytest tests/ -v --tb=short

.PHONY: docker-shell
docker-shell: check-docker
	@echo "$(CYAN)Abrindo shell interativo no container...$(RESET)"
	@$(DOCKER_COMPOSE) run --rm dev /bin/bash

.PHONY: docker-format
docker-format: check-docker
	@echo "$(CYAN)Formatando código com black no Docker...$(RESET)"
	@$(DOCKER_COMPOSE) run --rm dev black src/ core/ config/ tests/

.PHONY: docker-clean
docker-clean: check-docker
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

.PHONY: flatpak-install-deps
flatpak-install-deps: check-flatpak
	@echo "$(CYAN)Instalando dependências do Flatpak...$(RESET)"
	@./build-flatpak.sh install-deps

.PHONY: flatpak-build
flatpak-build: check-flatpak
	@echo "$(CYAN)Construindo Flatpak...$(RESET)"
	@./build-flatpak.sh build

.PHONY: flatpak-run
flatpak-run: check-flatpak
	@echo "$(CYAN)Executando aplicação Flatpak...$(RESET)"
	@./build-flatpak.sh test


.PHONY: flatpak-clean
flatpak-clean: check-flatpak
	@echo "$(CYAN)Limpando dados do Flatpak...$(RESET)"
	@./build-flatpak.sh clean

# ============================================================================
# Utilitários
# ============================================================================

.PHONY: format
format:
	@echo "$(CYAN)Formatando código...$(RESET)"
	@if command -v black >/dev/null 2>&1; then \
		black src/ core/ config/ tests/; \
		echo "$(GREEN)✓ Código formatado$(RESET)"; \
	else \
		echo "$(YELLOW)⚠ black não encontrado no host$(RESET)"; \
		echo "$(YELLOW)Instale com: pip3 install black$(RESET)"; \
		echo "$(YELLOW)Ou formate dentro do Flatpak após o build$(RESET)"; \
		exit 1; \
	fi

.PHONY: clean
clean:
	@echo "$(CYAN)Limpando arquivos gerados...$(RESET)"
	@find . -type d -name "__pycache__" -exec rm -r {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@find . -type f -name "*.pyo" -delete 2>/dev/null || true
	@find . -type f -name "*.qmlc" -delete 2>/dev/null || true
	@find . -type d -name "*.egg-info" -exec rm -r {} + 2>/dev/null || true
	@find . -type d -name ".pytest_cache" -exec rm -r {} + 2>/dev/null || true
	@find . -type d -name ".mypy_cache" -exec rm -r {} + 2>/dev/null || true
	@rm -rf .coverage htmlcov .tox .nox 2>/dev/null || true
	@echo "$(GREEN)✓ Limpeza concluída$(RESET)"
