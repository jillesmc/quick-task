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

## Dialogs e popovers em `components/dialogs/`

- **Não** usar `import "../components/dialogs/Foo.qml"` (ou caminho equivalente) no topo da página. Imports estáticos de ficheiros em subpastas podem falhar no Flatpak (resolução no load) e quebram o padrão do projeto.
- **Carregar em runtime** com `Qt.createComponent(...)` e caminho **relativo ao ficheiro que chama**:
  - Chamador em **pages/** (ex.: IssueFormPage.qml): `Qt.createComponent("../components/dialogs/NomeDialog.qml")`.
  - Chamador em **components/panes/** ou **components/controls/** etc.: `Qt.createComponent("../dialogs/NomeDialog.qml")`.
- Tratar `comp.status !== Component.Ready` (e.g. conectar `comp.statusChanged` e re-tentar quando `Component.Ready`).
- Instanciar com `comp.createObject(parent)` (ex.: o botão que abre o popover), configurar propriedades, `closed.connect(function () { obj.destroy() })`, e `open()`.
- Exemplos no projeto: AttachmentEmbedPreviewDialog, DescriptionAttachmentsPopover, ErrorDialog (via DialogHelpers com path string).

## Kirigami

- Janela principal: `Kirigami.ApplicationWindow` em Main.qml.
- Usar componentes Kirigami para navegação, cards, formulários; manter `Kirigami.Theme.inherit = true` onde aplicável.
- Evitar drawers se não forem usados: `globalDrawer: null`, `contextDrawer: null`.

## Lint

- **Sempre** rodar `make qml-lint` ao concluir alterações em QML. Se falhar, analisar os erros, corrigir e rodar novamente até passar.
- Usar qmllint dentro do Docker com QML_IMPORT_PATH correto. Não assumir qmllint no host.
