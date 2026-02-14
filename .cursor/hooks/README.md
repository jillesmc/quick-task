# Cursor Hooks

Este diretório contém hooks do Cursor para automação durante o desenvolvimento.

## Hook: run-validation.sh

**Quando executa:** Após edição de arquivo Python (`.py`) ou QML (`.qml`)

**O que faz:**
- Arquivos `.py` → executa `make dev-test`
- Arquivos `.qml` → executa `make qml-lint`
- Outros arquivos → não executa nada

**Como funciona:**
- Detecta o tipo de arquivo editado pelo payload (file_path)
- Aguarda 1 segundo para agrupar múltiplas edições rápidas
- Executa o comando apropriado em background (não bloqueia o Cursor)
- Mostra resultado nos logs do Cursor

**Logs:**
- Saída completa: `/tmp/cursor-validation-output.log`
- Mensagens no Cursor: aparecem no canal de saída "Hooks"

**Desabilitar temporariamente:**
- Comentar ou remover o hook em `.cursor/hooks.json`
- Ou renomear o script para não ser executável

**Requisitos:**
- `make dev-test` e `make qml-lint` devem estar configurados no `Makefile`
- Docker deve estar rodando (para ambos os comandos)
