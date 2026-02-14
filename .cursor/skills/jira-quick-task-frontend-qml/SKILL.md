---
name: jira-quick-task-frontend-qml
description: QML, Kirigami 6, componentes, bindings, integração com models Python. Use ao editar src/qml/**/*.qml ou quando o usuário pedir alterações de interface.
---

# Frontend Qt6 QML no jira-quick-task

## Imports padrão

- `QtQuick`, `QtQuick.Layouts`, `QtQuick.Controls as Controls`, `org.kde.kirigami as Kirigami`.
- Componentes internos: `import "./pages"`, `import "./components/..."` conforme estrutura em `src/qml/`.

## Estrutura de pastas

- **pages/**: páginas principais (IssueFormPage, MyIssuesPage, SettingsPage, TimerPage, PendingWorklogsPage).
- **components/**: `controls/`, `dialogs/`, `forms/`, `lists/`, `panes/`, `settings/`, `timer/`.
- **controllers/**: lógica QML (ex: IssueFormController, MyIssuesController).
- **utils/**: DialogHelpers.js, FormatUtils.js, Validators.js, etc.
- Cada pasta com componentes tem `qmldir`.

## Kirigami

- Janela principal: `Kirigami.ApplicationWindow` em Main.qml.
- Usar componentes Kirigami para navegação, cards, formulários; manter `Kirigami.Theme.inherit = true` onde aplicável.
- Evitar drawers se não forem usados: `globalDrawer: null`, `contextDrawer: null`.

## Lint

- **Sempre** rodar `make qml-lint` ao concluir alterações em QML. Se falhar, analisar os erros, corrigir e rodar novamente até passar.
- Usar qmllint dentro do Docker com QML_IMPORT_PATH correto. Não assumir qmllint no host.
