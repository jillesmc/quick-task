# Campo Registrar Worklog (abas 7 e 8)

Este documento especifica o campo **Registrar worklog** para reutilização nas **abas 7 e 8** (Create Work Item / My Work Items). O campo permite optar por registar um worklog na criação do work item ou ao atualizar/transicionar (ex.: ao atingir IN PROGRESS). A versão antiga (abas 0 e 1) permanece inalterada e fora do âmbito deste documento; a análise das telas IssueFormPage e MyIssuesPage/MyIssuesDetailPane serve apenas como referência para extrair o comportamento e documentá-lo aqui.

---

## 1. Backend (abas 7 e 8)

### 1.1 Modelo (WorkItemModel)

- **Propriedades**: `registrarWorklog` (bool), `worklogInicio` (string "yyyy-MM-dd HH:mm:ss"), `worklogDuracao` (int, minutos), `worklogComment` (string). Expostas ao QML com `Property(..., notify=...Changed)`.
- **Sinais**: `registrarWorklogChanged`, `worklogInicioChanged`, `worklogDuracaoChanged`, `worklogCommentChanged`.
- **Inicial e reset**: em `resetForNewIssue()` repõe-se `registrarWorklog = False`, `worklogInicio` com data/hora atual, `worklogDuracao = 30`, `worklogComment = ""`.
- **Comportamento**: o worklog é **opcional**. No fluxo Work Items (abas 7 e 8) a decisão é por **status category** (dados em memória a partir de `jira_metadata.json`): "Registrar worklog" é habilitado quando o **status category alvo ou atual é diferente de \"new\" (To Do)**. Desabilitado apenas quando ambos forem só To Do. Sem workflow carregado, a opção fica desabilitada. A página expõe uma propriedade derivada (`registrarWorklogEnabled`) para habilitar/desabilitar a UI.

### 1.2 Serviço (AtlassianService)

- **Criação**: `create_issue(..., registrar_worklog, worklog_inicio, worklog_duracao, worklog_timezone, worklog_comment, ...)`. Se `registrar_worklog` e data/duração válidos, o worklog pode ser registado após criar a issue ou ao transicionar para IN PROGRESS (conforme implementação do worker).
- **Atualização/transição**: `update_issue(..., registrar_worklog, worklog_inicio, worklog_duracao, worklog_timezone, worklog_comment, ...)`. Idem: worklog pode ser registado ao atingir IN PROGRESS na sequência de transições.
- **Formato**: `worklog_inicio` é `datetime` no Python; na fronteira QML usa-se string `"YYYY-MM-DD HH:MM:SS"`. Timezone vem da config (ex.: `config.json`); o serviço converte conforme necessário.

### 1.3 Contrato para o frontend (abas 7 e 8)

- **Modelo**: `workItemModel` com `registrarWorklog`, `worklogInicio`, `worklogDuracao`, `worklogComment` (leitura/escrita) e sinais.
- **Serviço**: `atlassianService` (ou equivalente nas abas 7/8) com create/update que aceitam parâmetros de worklog. Opcionalmente: `getRetroactiveMaxHours()`, `getDefaultDurations()` para o formulário de worklog.

---

## 2. Componente: WorklogForm

Componente reutilizável para formulário de worklog. Usado na **criação** (checkbox + form) e no **painel de detalhe** (edição/transição) nas abas 7 e 8.

### 2.1 Contrato (props / parâmetros configuráveis)

| Prop | Tipo | Default | Descrição |
|------|------|---------|-----------|
| `enabled` | bool | `true` | Habilita/desabilita todos os controles do formulário. |
| `jiraService` | object | `null` | Opcional. Se presente, no `Component.onCompleted` pode chamar `getRetroactiveMaxHours()` e `getDefaultDurations()` para configurar `retroactiveMaxHours` e `defaultDurations`. |
| `showCheckbox` | bool | `true` | Se `true`, exibe o checkbox "Registrar worklog"; se `false`, o formulário de data/hora/duração/comentário ainda é exibido mas o checkbox fica oculto (útil quando a opção de registar é controlada fora do componente). |
| `shouldRegister` | bool (alias) | — | Alias para o estado do checkbox (só faz sentido quando `showCheckbox` é `true`). |
| `date` | string (alias) | — | Alias para o campo de data (YYYY-MM-DD). |
| `time` | string (alias) | — | Alias para o campo de hora (HH:MM:SS). |
| `duration` | real (alias) | — | Alias para o valor do slider de duração (minutos). |
| `comment` | string (alias) | — | Alias para o campo de comentário. |
| `defaultDurations` | array | `[30, 60, 120, 240, 480]` | Presets de duração (minutos) para botões rápidos. |
| `retroactiveMaxHours` | int | `24` | Limite em horas para cálculo retroativo de data/hora (botão ao lado do campo hora). |

### 2.2 Sinais

| Sinal | Descrição |
|-------|------------|
| `worklogChanged()` | Emitido quando qualquer campo relevante muda (checkbox, date, time, duration, comment). |

### 2.3 Métodos

| Método | Descrição |
|--------|-----------|
| `getWorklogData()` | Retorna objeto `{ shouldRegister, date, time, duration, comment, inicioStr }`. `inicioStr` é `date + " " + time` quando ambos preenchidos; `duration` é `Math.round(duration)`. Usado pela página/controller para enviar ao serviço. |
| `setWorklogData(data)` | Define os campos do formulário a partir de um objeto com propriedades opcionais: `shouldRegister`, `date`, `time`, `duration`, `comment`. Usado para sincronizar a partir do modelo (ex.: ao carregar detalhes ou ao mudar status inicial). |
| `reset()` | Repõe data/hora para agora, duração 30, comentário vazio, checkbox desmarcado (se visível). Equivalente a `initializeDefaults()`. |

Comportamento interno (sem alterar contrato): formatação de data/hora com `FormatUtils`, botão de cálculo retroativo (`calculateAndSetRetroactiveTime`), presets de duração, e inicialização de defaults no `Component.onCompleted`.

### 2.4 Uso por contexto

- **Criação (CreateWorkItemPage)**: Checkbox "Registrar worklog" fora ou como parte do bloco; quando marcado, exibe `WorklogForm` com `showCheckbox: false` (o checkbox da página controla a visibilidade). Bindings bidirecionais entre form e `workItemModel` (worklogInicio, worklogDuracao, worklogComment, registrarWorklog). `enabled: !page.isProcessing && worklogCheckbox.checked`. Ao submeter, o controller lê do modelo (ou do form) e envia `registrarWorklog`, `worklogInicio`, `worklogDuracao`, `worklogComment` ao serviço. Após submit com sucesso, chama `workItemModel` reset e `worklogForm.reset()`.
- **Edição (MyWorkItemsPage / WorkItemDetailPane)**: Checkbox "Registrar worklog" + `WorklogForm` no painel de detalhe; bindings para `workItemModel`. O painel expõe **`getWorklogData()`**: se o checkbox está marcado e o form existe, retorna `worklogForm.getWorklogData()`; senão retorna objeto com `shouldRegister: false` ou equivalente para não registar. Na ação de update/transição, a página chama `detailPane.getWorklogData()` e passa `worklogData` ao controller (ex.: `controller.updateIssue(issueKey, fieldData, worklogData, parentKey, originalStatus)`). Integração com worklogs pendentes (worklogSyncService) e diálogo de confirmação fica na página; o componente WorklogForm apenas fornece os dados do formulário.

---

## 3. Telas (abas 7 e 8)

### 3.1 CreateWorkItemPage (criação, aba 7)

- **Posição**: coluna esquerda do SplitView, secção abaixo de summary/description e parent work item (ou conforme layout atual).
- **Elementos**: Checkbox "Registrar worklog" (`registrarWorklogEnabled` é true quando o status inicial tem **status category** diferente de \"new\" (To Do), usando workflow em memória de `jira_metadata.json`; sem workflow fica desabilitado); `WorklogForm` visível quando checkbox marcado.
- **Bindings**: form ↔ `page.workItemModel` (registrarWorklog, worklogInicio, worklogDuracao, worklogComment). Inicialização de worklogInicio com data/hora atual se vazio.
- **Submit**: controller obtém do modelo (ou do form) os dados de worklog e chama o serviço de criação com esses parâmetros. Após sucesso: reset do modelo e `worklogForm.reset()`.

### 3.2 MyWorkItemsPage (edição, aba 8)

- **Painel de detalhe**: WorkItemDetailPane (ou equivalente) contém checkbox "Registrar worklog" e `WorklogForm`. Bindings para `pane.workItemModel`.
- **Método exposto**: `detailPane.getWorklogData()` — usado pela página ao disparar update/transição; retorna objeto compatível com o esperado pelo controller (`shouldRegister`, `date`, `time`, `duration`, `comment`, `inicioStr`).
- **Fluxo de update**: página obtém `fieldData` e `worklogData = detailPane.getWorklogData()`. A verificação de **worklogs pendentes** é exigida **sempre que for sair de um status com category IN PROGRESS para outro que não seja IN PROGRESS** (usando workflow em memória); a página pode então mostrar diálogo e chamar `controller.updateIssue(...)` (ou fluxo em duas fases). O controller repassa worklogData ao serviço. **Timer**: "Iniciar timer" usa apenas workflow (category IN PROGRESS para "já em progresso"); sem workflow o botão fica desabilitado (com tooltip). Fonte de dados: `jira_metadata.json` já armazenado (em memória); não se chama a API do Jira para metadata neste fluxo.

---

## 4. Resumo e ficheiros (abas 7 e 8)

| Onde | O quê |
|------|--------|
| Backend (modelo) | WorkItemModel: `registrarWorklog`, `worklogInicio`, `worklogDuracao`, `worklogComment` (Property + sinais). Reset em resetForNewIssue(). |
| Backend (serviço) | AtlassianService: create_issue e update_issue com parâmetros de worklog; worklog pode ser registado na criação ou ao transicionar para IN PROGRESS. |
| QML (componente) | WorklogForm: props (enabled, jiraService, showCheckbox, date, time, duration, comment, defaultDurations, retroactiveMaxHours); signal worklogChanged; métodos getWorklogData(), setWorklogData(data), reset(). |
| QML (páginas) | CreateWorkItemPage: checkbox + WorklogForm, bindings ao workItemModel, registrarWorklogEnabled, reset após submit. MyWorkItemsPage: painel de detalhe com getWorklogData(); página passa worklogData ao controller no update. |

**Ficheiros no âmbito (abas 7 e 8):**

| Ficheiro | Papel |
|----------|--------|
| [src/models/work_item_model.py](src/models/work_item_model.py) | registrarWorklog, worklogInicio, worklogDuracao, worklogComment. |
| [src/atlassian_service.py](src/atlassian_service.py) | create_issue / update_issue com parâmetros de worklog. |
| [src/qml/components/forms/WorklogForm.qml](src/qml/components/forms/WorklogForm.qml) | Componente reutilizável; contrato §2. |
| [src/qml/pages/CreateWorkItemPage.qml](src/qml/pages/CreateWorkItemPage.qml) | Secção worklog com checkbox + WorklogForm e bindings ao workItemModel. |
| [src/qml/pages/MyWorkItemsPage.qml](src/qml/pages/MyWorkItemsPage.qml) | Chama detailPane.getWorklogData() e passa worklogData ao controller. |
| Painel de detalhe (WorkItemDetailPane ou equivalente) | Checkbox + WorklogForm; expõe getWorklogData() para a página. |

A reutilização nas abas 7 e 8 consiste em usar o mesmo WorklogForm e o mesmo contrato (getWorklogData / setWorklogData / reset) com `workItemModel` e com o controller/serviço das abas 7 e 8, sem depender das abas 0 e 1.
