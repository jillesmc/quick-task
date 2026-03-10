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

# Variáveis Dev Tools (exportadas do Docker)
DEV_TOOLS_DIR := $(CURDIR)/dev-tools
DEV_TOOLS_BIN := $(DEV_TOOLS_DIR)/bin
DEV_TOOLS_LIB := $(DEV_TOOLS_DIR)/lib
DEV_TOOLS_QML := $(DEV_TOOLS_DIR)/qml
DEV_TOOLS_PLUGINS := $(DEV_TOOLS_DIR)/plugins

# qmllint: usar ferramentas exportadas do Docker se disponíveis, senão fallback
_QMLLINT_DEV_TOOLS := $(wildcard $(DEV_TOOLS_BIN)/qmllint)
_QMLLINT_PROJECT := $(wildcard $(CURDIR)/6.10.2/gcc_64/bin/qmllint)
QMLLINT ?= $(if $(_QMLLINT_DEV_TOOLS),$(_QMLLINT_DEV_TOOLS),$(if $(_QMLLINT_PROJECT),$(_QMLLINT_PROJECT),/home/jilles/Qt6/6.10.2/gcc_64/bin/qmllint))

# Import paths para qmllint (priorizar dev-tools, depois fallback)
QML_IMPORT_PATHS := $(if $(wildcard $(DEV_TOOLS_QML)),$(DEV_TOOLS_QML):/snap/kf6-core24-sdk/current/usr/lib/x86_64-linux-gnu/qml:/home/jilles/Qt6/6.10.2/gcc_64/qml:$(CURDIR)/src/qml,/snap/kf6-core24-sdk/current/usr/lib/x86_64-linux-gnu/qml:/home/jilles/Qt6/6.10.2/gcc_64/qml:$(CURDIR)/src/qml)
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
	@echo "  $(YELLOW)make flatpak-audio-deps$(RESET) - Gera flatpak/python3-audio.json (flatpak-pip-generator: sounddevice, scipy, numpy)"
	@echo "  $(YELLOW)make clean-build$(RESET)   - Remove build e aplicação Flatpak instalada"
	@echo ""
	@echo "$(GREEN)Utilitários:$(RESET)"
	@echo "  $(YELLOW)make clean$(RESET)    - Remove arquivos gerados (__pycache__, .pyc, .qmlc, etc)"
	@echo "  $(YELLOW)make qml-lint$(RESET)    - Executa qmllint em todos os arquivos QML"
	@echo "  $(YELLOW)make qml-lint FILES=\"...\"$(RESET)  - qmllint nos arquivos indicados"
	@echo "  $(YELLOW)make qml-format$(RESET)  - Formata todos os .qml em src/ com qmlformat6 (Docker)"
	@echo "  $(YELLOW)make python-lint$(RESET) - Verifica Python (ruff ou py_compile)"
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
DOCKER_USER := -e UID=$(DOCKER_UID) -e GID=$(DOCKER_GID)

.PHONY: dev-build
dev-build: check-docker
	@echo "$(CYAN)Construindo imagem Docker para desenvolvimento...$(RESET)"
	@$(DOCKER_COMPOSE) build
	@echo "$(CYAN)Exportando ferramentas Qt6/KF6 para dev-tools/...$(RESET)"
	@mkdir -p $(DEV_TOOLS_DIR)
	@$(DOCKER_COMPOSE) run $(DOCKER_USER) --rm dev /docker/setup-dev-tools.sh || true
	@if [ -f "$(DEV_TOOLS_BIN)/qmllint" ]; then \
		echo "$(GREEN)✓ Ferramentas exportadas com sucesso!$(RESET)"; \
	else \
		echo "$(YELLOW)⚠ Ferramentas não foram exportadas. Execute novamente: make dev-build$(RESET)"; \
	fi

.PHONY: dev-test
dev-test: check-docker
	@echo "$(CYAN)Executando testes no Docker...$(RESET)"
	@$(DOCKER_COMPOSE) run $(DOCKER_USER) --rm dev python3 -m pytest tests/ -v --tb=short

.PHONY: dev-shell
dev-shell: check-docker
	@echo "$(CYAN)Abrindo shell interativo no container...$(RESET)"
	@$(DOCKER_COMPOSE) run $(DOCKER_USER) --rm dev /bin/bash

.PHONY: dev-format
dev-format: check-docker
	@echo "$(CYAN)Formatando código com black no Docker...$(RESET)"
	@$(DOCKER_COMPOSE) run $(DOCKER_USER) --rm dev black src/ core/ config/ tests/
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

# Gera flatpak/python3-audio.json (opcional; o arquivo já está no repositório).
# Requer: flatpak-pip-generator (pip install flatpak-pip-generator).
.PHONY: flatpak-audio-deps
flatpak-audio-deps:
	@(command -v flatpak-pip-generator >/dev/null 2>&1 || python3 -m flatpak_pip_generator --help >/dev/null 2>&1) || { \
		echo "$(RED)✗ flatpak-pip-generator não encontrado$(RESET)"; \
		echo "$(YELLOW)Instale com: pip install --user flatpak-pip-generator$(RESET)"; \
		exit 1; \
	}
	@echo "$(CYAN)Gerando flatpak/python3-audio.json (sounddevice, scipy, numpy)...$(RESET)"
	@python3 -m flatpak_pip_generator sounddevice scipy numpy --output flatpak/python3-audio
	@if [ -f flatpak/python3-audio.json ]; then \
		sed -i 's|https://files.pythonhosted.org/packages/eb/56/b1ba7935a17738ae8453301356628e8147c79dbb825bcbc73dc7401f9846/cffi-2.0.0.tar.gz|https://files.pythonhosted.org/packages/d7/91/500d892b2bf36529a75b77958edfcd5ad8e2ce4064ce2ecfeab2125d72d1/cffi-2.0.0-cp311-cp311-manylinux2014_x86_64.manylinux_2_17_x86_64.whl|' flatpak/python3-audio.json; \
		sed -i 's/44d1b5909021139fe36001ae048dbdde8214afa20200eda0f64c068cac5d5529/8941aaadaf67246224cee8c3803777eed332a19d909b47e29c9842ef1e79ac26/' flatpak/python3-audio.json; \
		sed -i 's|https://files.pythonhosted.org/packages/57/fd/0005efbd0af48e55eb3c7208af93f2862d4b1a56cd78e84309a2d959208d/numpy-2.4.2.tar.gz|https://files.pythonhosted.org/packages/1b/46/6fa4ea94f1ddf969b2ee941290cca6f1bfac92b53c76ae5f44afe17ceb69/numpy-2.4.2-cp311-cp311-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl|' flatpak/python3-audio.json; \
		sed -i 's/659a6107e31a83c4e33f763942275fd278b21d095094044eb35569e86a21ddae/c02ef4401a506fb60b411467ad501e1429a3487abca4664871d9ae0b46c8ba32/' flatpak/python3-audio.json; \
		sed -i 's|https://files.pythonhosted.org/packages/56/3e/9cca699f3486ce6bc12ff46dc2031f1ec8eb9ccc9a320fdaf925f1417426/scipy-1.17.0.tar.gz|https://files.pythonhosted.org/packages/ef/df/df1457c4df3826e908879fe3d76bc5b6e60aae45f4ee42539512438cfd5d/scipy-1.17.0-cp311-cp311-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl|' flatpak/python3-audio.json; \
		sed -i 's/2591060c8e648d8b96439e111ac41fd8342fdeff1876be2e19dea3fe8930454e/dac97a27520d66c12a34fd90a4fe65f43766c18c0d6e1c0a80f114d2260080e4/' flatpak/python3-audio.json; \
		echo "$(GREEN)✓ flatpak/python3-audio.json criado (cffi, numpy, scipy como wheels cp311)$(RESET)"; \
	else \
		echo "$(YELLOW)Verifique a saída do gerador$(RESET)"; \
	fi

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
qml-lint: check-docker
	@echo "$(CYAN)Executando qmllint nos QML...$(RESET)"
	@if [ -z "$(FILES)" ]; then \
		echo "$(CYAN)Usando qmllint dentro do container Docker (garante imports corretos)...$(RESET)"; \
		echo "$(CYAN)Verificando todos os arquivos QML...$(RESET)"; \
		$(DOCKER_COMPOSE) run $(DOCKER_USER) --rm dev bash -c \
			"cd /app && \
			LANG=C.UTF-8 LC_ALL=C.UTF-8 \
			QT_PLUGIN_PATH=/usr/lib64/qt6/plugins \
			QML_IMPORT_PATH=/usr/lib64/qt6/qml:/app/src/qml \
			QT_QPA_PLATFORM=offscreen \
			/usr/lib64/qt6/bin/qmllint \$$(find src/qml -name '*.qml')" 2>&1 || true; \
	else \
		echo "$(CYAN)Usando qmllint dentro do container Docker (garante imports corretos)...$(RESET)"; \
		echo "$(CYAN)Verificando arquivos especificados: $(FILES)$(RESET)"; \
		$(DOCKER_COMPOSE) run $(DOCKER_USER) --rm dev bash -c \
			"cd /app && \
			LANG=C.UTF-8 LC_ALL=C.UTF-8 \
			QT_PLUGIN_PATH=/usr/lib64/qt6/plugins \
			QML_IMPORT_PATH=/usr/lib64/qt6/qml:/app/src/qml \
			QT_QPA_PLATFORM=offscreen \
			/usr/lib64/qt6/bin/qmllint $(FILES)" 2>&1 || true; \
	fi

.PHONY: qml-format
qml-format: check-docker
	@echo "$(CYAN)Formatando QML em src/ com qmlformat no Docker...$(RESET)"
	@$(DOCKER_COMPOSE) run $(DOCKER_USER) --rm dev bash -c \
		"cd /app && find src -name '*.qml' -exec /usr/lib64/qt6/bin/qmlformat -i {} \;"
	@echo "$(GREEN)✓ QML formatado$(RESET)"

.PHONY: python-lint
python-lint:
	@echo "$(CYAN)Verificando Python...$(RESET)"
	@if command -v ruff >/dev/null 2>&1; then \
		ruff check src/ config/ core/ 2>&1 && echo "$(GREEN)✓ ruff OK$(RESET)" || exit 1; \
	else \
		echo "$(YELLOW)ruff não instalado; usando py_compile$(RESET)"; \
		python3 -m py_compile src/app.py config/config_manager.py core/jira_client.py 2>&1 && echo "$(GREEN)✓ py_compile OK$(RESET)" || exit 1; \
	fi

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
