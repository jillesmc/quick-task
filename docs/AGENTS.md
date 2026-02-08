# Orientação para o agente (jira-quick-task)

Este documento ajuda o agente a aplicar o contexto certo em prompts futuros.

## O que é este projeto

- App desktop **Kirigami 6 (KDE)** para criar/issues Jira, worklogs, timer Pomodoro, entrada por voz (LocalAI).
- **Backend**: Python 3.11+, PySide6, Jira REST API v3. **Frontend**: QML em `src/qml/`.
- **Dev/testes**: Docker (`make dev-test`, `make dev-shell`, `make dev-format`). **Distribuição**: Flatpak (`make build`, `make run`).

## Regras do projeto (.cursor/rules/)

- **python-pyside-qml.mdc** — Ao editar Python (models, services, core, config): convenções PySide6, Property/Signal, ConfigManager, debug.
- **qml-kirigami.mdc** — Ao editar QML: imports, estrutura de pastas, Kirigami, `make qml-lint`.
- **tests-pytest.mdc** — Ao editar ou pedir testes: fixtures em conftest, rodar com `make dev-test`.

## Skills do projeto (.cursor/skills/)

- **jira-quick-task-new-field** — Adicionar novo campo customizado Jira: config → IssueModel → JiraService → QML (ver SKILL.md para o checklist).
- **jira-quick-task-tests** — Escrever ou estender testes pytest usando as fixtures existentes e Docker.

## Comandos úteis

| Objetivo | Comando |
|----------|--------|
| Testes | `make dev-test` |
| Formatar Python | `make dev-format` |
| Lint QML | `make qml-lint` |
| Shell no container | `make dev-shell` |
| Build/run Flatpak | `make build` / `make run` ou `make dev` |

## Quando sugerir skills/regras

- **"Adicionar um campo X no formulário de issue"** → Usar skill `jira-quick-task-new-field` e regra `python-pyside-qml.mdc` + `qml-kirigami.mdc`.
- **"Escrever testes para X"** ou **"testes falhando"** → Usar skill `jira-quick-task-tests` e regra `tests-pytest.mdc`; lembrar `make dev-test`.
- **"Mudar UI em QML"** → Regra `qml-kirigami.mdc`; ao final sugerir `make qml-lint`.
- **"Mudar lógica Jira / config / models"** → Regra `python-pyside-qml.mdc`; se tocar em criação de issue, considerar se novo campo precisa do fluxo da skill new-field.
