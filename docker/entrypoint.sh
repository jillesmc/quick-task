#!/bin/bash
set -e

# Se UID e GID foram passados, criar usuário correspondente
if [ -n "$UID" ] && [ -n "$GID" ]; then
    # Criar grupo se não existir
    if ! getent group "$GID" > /dev/null 2>&1; then
        groupadd -g "$GID" devgroup 2>/dev/null || true
    fi
    
    # Criar usuário se não existir
    if ! getent passwd "$UID" > /dev/null 2>&1; then
        useradd -u "$UID" -g "$GID" -m -s /bin/bash devuser 2>/dev/null || true
    fi
    
    # Executar comando como o usuário criado
    # Usar exec para substituir o processo atual
    # Não usar 'su -' (login shell) para manter o diretório de trabalho atual
    if [ $# -eq 0 ]; then
        exec su devuser
    else
        # Usar su sem '-' para manter o diretório de trabalho
        # Passar todos os argumentos como um único comando
        exec su devuser -c "$*"
    fi
else
    # Se não foram passados UID/GID, executar como root
    exec "$@"
fi
