# Como Executar com Debug

Para diagnosticar problemas, execute a aplicação com debug habilitado:

## Opção 1: Via Makefile (Recomendado)

```bash
make flatpak-run-debug
```

## Opção 2: Via Flatpak diretamente

```bash
# Com parâmetro --debug
flatpak run org.kde.jira-quick-task --debug

# Ou com variável de ambiente
JIRA_QUICK_TASK_DEBUG=1 flatpak run org.kde.jira-quick-task
```

## Opção 3: Via build-flatpak.sh

```bash
./build-flatpak.sh test --debug
```

## O que você verá

Com debug habilitado, você verá mensagens no console no formato:
```
[DEBUG] ModuleName.function_name: mensagem
```

Exemplos:
- `[DEBUG] App.main: Criando TimerService...`
- `[DEBUG] TimerService.start: Iniciando timer para issue: PLATFORM-123`
- `[DEBUG] TimerModel.start_session: Sessão iniciada para issue: PLATFORM-123`

## Verificando se os serviços estão disponíveis

No console do QML (aberto com F12 ou via terminal), você verá:
- `TimerPage: timerService disponível: true/false`
- `TimerPage: timerModel disponível: true/false`

Se aparecer `false`, significa que os serviços não foram criados ou expostos corretamente.

## Logs do QML

O QML também emite logs no console quando você clica no botão "Iniciar Timer":
- `TimerPage: Clicou em Iniciar Timer`
- `TimerPage: Estado ANTES de iniciar: ...`
- `TimerPage: Chamando timerService.start(...)`
- `TimerPage: Estado APÓS iniciar: ...`
