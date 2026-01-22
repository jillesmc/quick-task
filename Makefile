.PHONY: help test test-verbose test-coverage test-watch install install-dev clean lint format run icons setup check-mise check-deps

# Cores usando tput
ifneq ($(TERM),)
	RED := $(shell tput setaf 1)
	GREEN := $(shell tput setaf 2)
	YELLOW := $(shell tput setaf 3)
	BLUE := $(shell tput setaf 4)
	MAGENTA := $(shell tput setaf 5)
	CYAN := $(shell tput setaf 6)
	RESET := $(shell tput sgr0)
else
	RED :=
	GREEN :=
	YELLOW :=
	BLUE :=
	MAGENTA :=
	CYAN :=
	RESET :=
endif

# Variáveis
PYTHON := mise exec -- python
PIP := mise exec -- pip
PYTEST := mise exec -- pytest
BLACK := mise exec -- python -m black
PYTHON_FILES := src/ core/ config/ tests/
TEST_DIR := tests

# Help padrão
help:
	@echo "$(CYAN)Comandos disponíveis:$(RESET)"
	@echo ""
	@echo "$(GREEN)Setup:$(RESET)"
	@echo "  $(YELLOW)make setup$(RESET)              - Executa setup completo do projeto"
	@echo "  $(YELLOW)make install$(RESET)            - Instala dependências Python"
	@echo "  $(YELLOW)make install-dev$(RESET)        - Instala dependências de desenvolvimento"
	@echo "  $(YELLOW)make check-mise$(RESET)         - Verifica se mise está instalado"
	@echo "  $(YELLOW)make check-deps$(RESET)         - Verifica dependências do sistema"
	@echo ""
	@echo "$(GREEN)Testes:$(RESET)"
	@echo "  $(YELLOW)make test$(RESET)               - Executa todos os testes"
	@echo "  $(YELLOW)make test-verbose$(RESET)       - Executa testes em modo verbose"
	@echo "  $(YELLOW)make test-coverage$(RESET)      - Executa testes com cobertura"
	@echo "  $(YELLOW)make test-watch$(RESET)         - Executa testes em modo watch (instala pytest-watch se necessário)"
	@echo ""
	@echo "$(GREEN)Qualidade de código:$(RESET)"
	@echo "  $(YELLOW)make lint$(RESET)               - Verifica estilo de código (black --check)"
	@echo "  $(YELLOW)make format$(RESET)             - Formata código com black"
	@echo ""
	@echo "$(GREEN)Execução:$(RESET)"
	@echo "  $(YELLOW)make run$(RESET)               - Executa a aplicação"
	@echo "  $(YELLOW)make icons$(RESET)            - Gera ícones PNG a partir do SVG"
	@echo ""
	@echo "$(GREEN)Limpeza:$(RESET)"
	@echo "  $(YELLOW)make clean$(RESET)             - Remove arquivos gerados (__pycache__, .pyc, etc)"
	@echo "  $(YELLOW)make clean-all$(RESET)         - Remove tudo incluindo .coverage e htmlcov"
	@echo ""

# Verificações
check-mise:
	@echo "$(CYAN)Verificando mise...$(RESET)"
	@if command -v mise >/dev/null 2>&1; then \
		echo "$(GREEN)✓ mise encontrado: $$(mise --version)$(RESET)"; \
	else \
		echo "$(RED)✗ mise não encontrado$(RESET)"; \
		echo "$(YELLOW)Instale com: curl https://mise.run | sh$(RESET)"; \
		exit 1; \
	fi

check-deps:
	@echo "$(CYAN)Verificando dependências do sistema...$(RESET)"
	@for pkg in python3-pyside2.qtcore python3-pyside2.qtgui python3-pyside2.qtqml python3-pyside2.qtwidgets qml-module-org-kde-kirigami2 python3-xlib; do \
		if dpkg -l | grep -q "^ii  $$pkg "; then \
			echo "$(GREEN)✓ $$pkg instalado$(RESET)"; \
		else \
			echo "$(YELLOW)⚠ $$pkg não encontrado$(RESET)"; \
		fi; \
	done

# Setup
setup: check-mise
	@echo "$(CYAN)Executando setup...$(RESET)"
	@./setup.sh

install: check-mise
	@echo "$(CYAN)Instalando dependências Python...$(RESET)"
	@$(PIP) install -r requirements.txt
	@echo "$(GREEN)✓ Dependências instaladas$(RESET)"

install-dev: install
	@echo "$(CYAN)Instalando dependências de desenvolvimento...$(RESET)"
	@$(PIP) install pytest pytest-mock pytest-qt pytest-cov black
	@echo "$(GREEN)✓ Dependências de desenvolvimento instaladas$(RESET)"

# Testes
test: check-mise
	@echo "$(CYAN)Executando testes...$(RESET)"
	@$(PYTEST) -q --tb=short --disable-warnings $(TEST_DIR) || (echo "$(RED)✗ Testes falharam$(RESET)" && exit 1)
	@echo "$(GREEN)✓ Todos os testes passaram$(RESET)"

test-verbose: check-mise
	@echo "$(CYAN)Executando testes (verbose)...$(RESET)"
	@$(PYTEST) -v --tb=short --disable-warnings $(TEST_DIR)

test-coverage: check-mise
	@echo "$(CYAN)Executando testes com cobertura...$(RESET)"
	@$(PYTEST) --cov=src --cov=core --cov=config \
		--cov-report=term-missing --cov-report=html \
		-q --tb=short --disable-warnings \
		$(TEST_DIR) || (echo "$(RED)✗ Testes falharam$(RESET)" && exit 1)
	@echo "$(GREEN)✓ Cobertura gerada em htmlcov/index.html$(RESET)"

test-watch: check-mise
	@echo "$(CYAN)Executando testes em modo watch...$(RESET)"
	@if ! mise exec -- python -c "import pytest_watch" 2>/dev/null; then \
		echo "$(YELLOW)⚠ pytest-watch não encontrado, instalando...$(RESET)"; \
		mise exec -- pip install -q pytest-watch; \
	fi
	@mise exec -- python -m pytest_watch --config /dev/null $(TEST_DIR) -- -q --tb=short --disable-warnings

# Qualidade de código
lint: check-mise
	@echo "$(CYAN)Verificando estilo de código...$(RESET)"
	@$(BLACK) --check $(PYTHON_FILES) || (echo "$(RED)✗ Código não está formatado$(RESET)" && exit 1)
	@echo "$(GREEN)✓ Código está formatado corretamente$(RESET)"

format: check-mise
	@echo "$(CYAN)Formatando código...$(RESET)"
	@$(BLACK) $(PYTHON_FILES)
	@echo "$(GREEN)✓ Código formatado$(RESET)"

# Geração de ícones
icons: check-mise
	@echo "$(CYAN)Gerando ícones PNG a partir do SVG...$(RESET)"
	@if command -v rsvg-convert >/dev/null 2>&1; then \
		echo "$(GREEN)Usando rsvg-convert (melhor qualidade para gradientes)$(RESET)"; \
		cd assets && for s in 16 22 24 32 48 64 128 256; do \
			rsvg-convert -w $$s -h $$s -o "jira-quick-task-$$s.png" jira-quick-task.svg; \
		done; \
	elif command -v convert >/dev/null 2>&1; then \
		echo "$(YELLOW)Usando ImageMagick (fallback)$(RESET)"; \
		cd assets && for s in 16 22 24 32 48 64 128 256; do \
			convert -background transparent -density 300 -colorspace sRGB -alpha on -resize "$${s}x$${s}" jira-quick-task.svg "jira-quick-task-$$s.png"; \
		done; \
	else \
		echo "$(RED)Erro: rsvg-convert ou ImageMagick não encontrados$(RESET)"; \
		echo "Instale: sudo apt-get install librsvg2-bin imagemagick"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ Ícones PNG gerados$(RESET)"

# Execução
run: check-mise
	@echo "$(CYAN)Executando aplicação...$(RESET)"
	@./jira-quick-task.sh

# Limpeza
clean:
	@echo "$(CYAN)Limpando arquivos gerados...$(RESET)"
	@find . -type d -name "__pycache__" -exec rm -r {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@find . -type f -name "*.pyo" -delete 2>/dev/null || true
	@find . -type f -name "*.qmlc" -delete 2>/dev/null || true
	@find . -type d -name "*.egg-info" -exec rm -r {} + 2>/dev/null || true
	@echo "$(GREEN)✓ Limpeza concluída$(RESET)"

clean-all: clean
	@echo "$(CYAN)Limpando arquivos de teste e cobertura...$(RESET)"
	@rm -rf .coverage htmlcov .pytest_cache .mypy_cache .tox .nox
	@echo "$(GREEN)✓ Limpeza completa concluída$(RESET)"
