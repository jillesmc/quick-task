# Cursor Hooks

Este diretório contém hooks do Cursor para automação durante o desenvolvimento.

## Hook: run-tests.sh

**Quando executa:** Após qualquer edição de arquivo Python (`.py`)

**O que faz:** Executa `make dev-test` automaticamente quando arquivos Python são editados.

**Como funciona:**
- Detecta quando um arquivo `.py` é editado
- Aguarda 1 segundo para agrupar múltiplas edições rápidas
- Executa `make dev-test` em background (não bloqueia o Cursor)
- Mostra resultado nos logs do Cursor

**Logs:**
- Saída completa: `/tmp/cursor-test-output.log`
- Mensagens no Cursor: aparecem no canal de saída "Hooks"

**Desabilitar temporariamente:**
- Comentar ou remover o hook em `.cursor/hooks.json`
- Ou renomear o script para não ser executável

**Requisitos:**
- `make dev-test` deve estar configurado no `Makefile`
- Docker deve estar rodando (para `make dev-test`)
