#!/bin/bash
# Hook para executar testes pytest quando arquivos .py são editados
# Este hook é chamado pelo Cursor após edições de arquivos

# Ler JSON de entrada do stdin
input=$(cat)

# Extrair o caminho do arquivo editado
# Tentar jq primeiro (mais confiável), depois grep/sed como fallback
file_path=""
if command -v jq >/dev/null 2>&1; then
    file_path=$(echo "$input" | jq -r '.file_path // empty' 2>/dev/null)
fi

# Fallback: usar grep/sed se jq não estiver disponível
if [ -z "$file_path" ]; then
    file_path=$(echo "$input" | grep -oP '"file_path"\s*:\s*"\K[^"]*' 2>/dev/null || \
                echo "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | \
                sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

# Verificar se o arquivo editado é um arquivo Python (.py)
if [[ "$file_path" == *.py ]]; then
    # Usar lock file para evitar execuções simultâneas
    lock_file="/tmp/cursor-test-lock"
    
    # Se já há um teste rodando, pular esta execução
    if [ -f "$lock_file" ]; then
        # Verificar se o processo ainda está rodando
        lock_pid=$(cat "$lock_file" 2>/dev/null)
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            echo "[run-tests hook] Testes já em execução (PID: $lock_pid), pulando..." >&2
            exit 0
        fi
        # Processo não existe mais, remover lock
        rm -f "$lock_file"
    fi
    
    # Criar lock file com PID atual
    echo $$ > "$lock_file"
    
    # Executar testes via make dev-test em background
    # O Cursor espera que o hook termine rapidamente
    (
        cd "${CURSOR_PROJECT_DIR:-.}" || exit 1
        
        # Aguardar 1 segundo para agrupar múltiplas edições rápidas
        sleep 1
        
        # Remover lock antes de executar (para permitir próxima execução)
        rm -f "$lock_file"
        
        echo "[run-tests hook] Executando testes após edição de: $file_path" >&2
        make dev-test > /tmp/cursor-test-output.log 2>&1
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            echo "[run-tests hook] ✓ Testes passaram" >&2
        else
            echo "[run-tests hook] ✗ Testes falharam (exit code: $exit_code)" >&2
            echo "[run-tests hook] Ver logs em: /tmp/cursor-test-output.log" >&2
            # Mostrar últimas 10 linhas do log em stderr
            tail -n 10 /tmp/cursor-test-output.log >&2
        fi
    ) &
    
    # Retornar imediatamente para não bloquear o Cursor
    exit 0
else
    # Arquivo não é .py, não fazer nada
    exit 0
fi
