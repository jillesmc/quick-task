#!/bin/bash
# Hook para executar validação quando arquivos .py ou .qml são editados
# .py -> make dev-test; .qml -> make qml-lint
# Chamado pelo Cursor após edições de arquivos (afterFileEdit)

input=$(cat)

file_path=""
if command -v jq >/dev/null 2>&1; then
    file_path=$(echo "$input" | jq -r '.file_path // empty' 2>/dev/null)
fi

if [ -z "$file_path" ]; then
    file_path=$(echo "$input" | grep -oP '"file_path"\s*:\s*"\K[^"]*' 2>/dev/null || \
                echo "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | \
                sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

lock_file="/tmp/cursor-validation-lock"
cmd=""
if [[ "$file_path" == *.py ]]; then
    cmd="make dev-test"
elif [[ "$file_path" == *.qml ]]; then
    cmd="make qml-lint"
fi

if [ -z "$cmd" ]; then
    exit 0
fi

if [ -f "$lock_file" ]; then
    lock_pid=$(cat "$lock_file" 2>/dev/null)
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        echo "[run-validation hook] Validação já em execução (PID: $lock_pid), pulando..." >&2
        exit 0
    fi
    rm -f "$lock_file"
fi

echo $$ > "$lock_file"

(
    cd "${CURSOR_PROJECT_DIR:-.}" || exit 1
    sleep 1
    rm -f "$lock_file"

    echo "[run-validation hook] Executando $cmd após edição de: $file_path" >&2
    $cmd > /tmp/cursor-validation-output.log 2>&1
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "[run-validation hook] ✓ $cmd passou" >&2
    else
        echo "[run-validation hook] ✗ $cmd falhou (exit code: $exit_code)" >&2
        echo "[run-validation hook] Ver logs em: /tmp/cursor-validation-output.log" >&2
        tail -n 10 /tmp/cursor-validation-output.log >&2
    fi
) &

exit 0
