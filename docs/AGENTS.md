# Orientação para o agente (jira-quick-task)

Este documento ajuda o agente a aplicar o contexto certo em prompts futuros.

## O que é este projeto

- App desktop **Kirigami 6 (KDE)** para criar/issues Jira, worklogs, timer Pomodoro, entrada por voz (LocalAI).
- **Backend**: Python 3.11+, PySide6, Jira REST API v3. **Frontend**: QML em `src/qml/`.
- **Dev/testes**: Docker (`make dev-test`, `make dev-shell`, `make dev-format`). **Distribuição**: Flatpak (`make build`, `make run`).

## Regras do projeto (.cursor/rules/)

- **python-pyside-qml.mdc** — Ao editar Python (models, services, core, config): convenções PySide6, Property/Signal, ConfigManager, debug. Ao concluir: `make dev-test`.
- **qml-kirigami.mdc** — Ao editar QML: imports, estrutura de pastas, Kirigami, `make qml-lint`. Ao concluir: `make qml-lint`.
- **tests-pytest.mdc** — Ao editar ou pedir testes: fixtures em conftest, rodar com `make dev-test`.
- **ui-ux-design.mdc** — Princípios de design, acessibilidade, consistência com Kirigami (globs: `**/*.qml`).

## Skills do projeto (.cursor/skills/)

- **jira-quick-task-new-field** — Adicionar novo campo customizado Jira: config → IssueModel → JiraService → QML (ver SKILL.md para o checklist).
- **jira-quick-task-tests** — Escrever ou estender testes pytest usando as fixtures existentes e Docker.
- **jira-quick-task-backend** — Lógica Python, PySide6, models, services, Jira API, config. Use ao editar `src/**/*.py`, `core/**/*.py`, `config/**/*.py`.
- **jira-quick-task-frontend-qml** — QML, Kirigami 6, componentes, bindings. Use ao editar `src/qml/**/*.qml`.
- **jira-quick-task-ui-ux** — Design de interface, acessibilidade, usabilidade. Use para melhorias visuais, acessibilidade, UX ou redesign.

## Subagents (paralelização)

Para tarefas que envolvem backend e frontend em contextos distintos:
- Usar subagents para explorar/implementar em paralelo (ex.: backend Python e QML).
- Exemplo: adicionar novo campo → subagent 1: config + IssueModel + JiraService; subagent 2: formulário QML.

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
- **"Mudar UI em QML"** → Skill `jira-quick-task-frontend-qml`, regra `qml-kirigami.mdc`; ao final rodar `make qml-lint`.
- **"Mudar lógica Jira / config / models"** → Skill `jira-quick-task-backend`, regra `python-pyside-qml.mdc`; ao final rodar `make dev-test`; se tocar em criação de issue, considerar skill new-field.
- **"Melhorar acessibilidade"**, **"redesign"**, **"UX"** → Skill `jira-quick-task-ui-ux`, regra `ui-ux-design.mdc`.
