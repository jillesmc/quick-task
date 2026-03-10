# Campo Priority (Prioridade) — abas 7 e 8

Este documento especifica o campo **priority** (prioridade) para reutilização nas **abas 7 e 8** (Create Work Item / My Work Items). A análise tem por base o uso atual em IssueFormPage e MyIssuesPage (e painéis/controllers associados); a versão antiga (abas 0 e 1) permanece inalterada e fora do âmbito. O objetivo é definir o comportamento e o contrato do campo de forma a permitir uso consistente em CreateWorkItemPage e MyWorkItemsPage.

---

## 1. Backend (abas 7 e 8)

### 1.1 Modelo (WorkItemModel)

- **Propriedade**: `prioridade` (string). Exposta ao QML com `Property(str, notify=prioridadeChanged)`.
- **Sinal**: `prioridadeChanged`.
- **Valor padrão**: `"Medium"` (padrão Jira).
- **Setter**: se o valor recebido for vazio ou nulo, o modelo repõe para `"Medium"` (fallback).
- **Inicial e reset**: em `resetForNewIssue()` a prioridade é reposta para `"Medium"`.
- **Obrigatoriedade**: o campo **não é obrigatório** no submit. O backend (Atlassian/Jira API) aceita prioridade como opcional; quando não enviada, o Jira usa o default do projeto. O modelo garante sempre um valor válido (nunca vazio) via fallback "Medium".

Referência: [src/models/work_item_model.py](src/models/work_item_model.py) — propriedade `prioridade`, setter com `value or "Medium"`, reset em `resetForNewIssue()`.

### 1.2 Serviço (AtlassianService)

- **Criação**: `create_issue(..., prioridade, ...)`. O parâmetro `prioridade` é o **nome** da prioridade (ex.: `"High"`, `"Medium"`). Na API, o campo é enviado como `fields["priority"] = {"name": priority.strip()}` quando `priority` é não vazio; caso contrário, a prioridade não é enviada (Jira usa o default do projeto).
- **Atualização / transição**: `update_issue(..., prioridade, ...)` e `transitionToInProgress(..., prioridade, ...)` — mesmo contrato: nome da prioridade, opcional.
- **Leitura de detalhes**: a API Jira devolve `priority` como objeto `{ "id": "...", "name": "..." }`. O serviço normaliza para o dicionário de detalhes exposto ao QML:
  - `details.priority` = nome (string), usado para preencher o modelo e a UI.
  - `details.priorityId` = id (string), usado na lista para exibição e ícone (ex.: Jira Cloud usa IDs como `"10000"`, `"10001"` em vez de 1–5).

Referência: [src/atlassian_service.py](src/atlassian_service.py) — create/update com `prioridade`; parsing em `_parse_issue_to_details` (ou equivalente) que extrai `priority_name` e `priority_id` para `result["priority"]` e `result["priorityId"]`. Cliente HTTP: [core/atlassian_client.py](core/atlassian_client.py) — `fields["priority"] = {"name": priority.strip()}`.

### 1.3 Contrato para o frontend (abas 7 e 8)

- **Modelo**: `workItemModel` com `prioridade` (leitura/escrita) e sinal `prioridadeChanged`. Valor nunca vazio no modelo (fallback "Medium").
- **Serviço**: `atlassianService` com create/update/transition que aceitam `prioridade` (string, nome). Detalhes da issue expõem `priority` (nome) e `priorityId` (id para exibição/lista).

---

## 2. UI do campo (estado atual e contrato reutilizável)

### 2.1 Onde está hoje

O campo de prioridade está **dentro** do componente [IssueMetadataFields.qml](src/qml/components/controls/IssueMetadataFields.qml): secção "Prioridade:" com um `IssueRadioGroup` que faz binding bidirecional ao `issueModel.prioridade`. Tanto IssueFormPage (aba 0) como CreateWorkItemPage (aba 7) usam o mesmo `IssueMetadataFields` (passando `issueModel` ou `workItemModel`). O painel de detalhe (MyIssuesDetailPane / WorkItemDetailPane) também usa `IssueMetadataFields` para edição.

### 2.2 Opções atuais

As opções são **fixas** no QML (não vêm de config nem de jira_metadata). Lista:

| value    | label   | ícone Breeze |
|----------|---------|----------------|
| Highest  | Highest | flag-red      |
| High     | High    | flag-yellow   |
| Medium   | Medium  | flag          |
| Low      | Low     | flag-green    |
| Lowest   | Lowest  | flag-blue     |

Não existe hoje lista dinâmica de prioridades por projeto (config ou API). Para extensão futura: poder-se-ia carregar prioridades do projeto via metadata/API e alimentar o modelo do radio group; até lá, documentar como fixas.

### 2.3 Bindings atuais

- `IssueRadioGroup.selectedValue` = `metadataFieldsRoot.issueModel.prioridade` (ou `workItemModel.prioridade` na página).
- `IssueRadioGroup.onValueChanged`: atualiza `issueModel.prioridade` / `workItemModel.prioridade`.
- `enabled`: repassado de `metadataFieldsRoot.enabled` (ex.: `!page.isProcessing` na criação).

### 2.4 Contrato de um bloco "Priority" reutilizável (abas 7 e 8)

Para uso em CreateWorkItemPage e no painel de detalhe de MyWorkItemsPage, um eventual componente dedicado (ex.: `PriorityBlock.qml` ou campo único) deveria expor:

| Prop       | Tipo   | Default   | Descrição |
|------------|--------|-----------|-----------|
| `model`    | object | required  | Objeto com propriedade `prioridade` (string) e sinal `prioridadeChanged` (ex.: `workItemModel`). |
| `enabled`  | bool   | `true`    | Habilita/desabilita o controle. |
| `labelText`| string | `qsTr("Prioridade:")` | Rótulo exibido acima do grupo de opções. |

- **Opções**: fixas (Highest, High, Medium, Low, Lowest) com ícones atuais; ou, em versão futura, prop `options` (lista de `{ value, label, icon? }`) vinda de config/metadata.
- **Comportamento**: valor sempre não vazio no modelo (default "Medium"); campo opcional no submit (backend aceita omitir). O componente apenas reflete e atualiza `model.prioridade`; não exige validação de obrigatoriedade.

---

## 3. Telas (abas 7 e 8)

### 3.1 CreateWorkItemPage (criação, aba 7)

- **Uso atual**: através de [IssueMetadataFields](src/qml/components/controls/IssueMetadataFields.qml) com `issueModel: page.workItemModel` e `enabled: !page.isProcessing`. A secção Prioridade faz parte do grid de metadados.
- **Reset**: na função de reset da página (ex.: após criar issue com sucesso), define-se `page.workItemModel.prioridade = "Medium"` para manter consistência com o modelo.
- **Submit**: o controller (ex.: WorkItemFormController) lê `workItemModel.prioridade` e envia no payload de criação (ex.: `data.prioridade || "Medium"`). O serviço envia apenas o **nome** da prioridade para a API.

### 3.2 MyWorkItemsPage (edição, aba 8)

- **Painel de detalhe**: WorkItemDetailPane usa `IssueMetadataFields` (ou eventual bloco Priority) com `workItemModel`. Ao carregar detalhes, `setDetails(details)` define `workItemModel.prioridade = String(details.priority || "Medium")`.
- **getFieldData()**: o painel inclui `fieldData.prioridade = workItemModel.prioridade || ""` para o controller usar no update/transição.
- **Controller**: MyWorkItemsController repassa `fieldData.prioridade` (ou fallback) em `updateIssue` e `transitionToInProgress`.
- **Lista**: quando os detalhes são carregados (ou após update bem-sucedido), a página chama `myWorkItemsModel.updateIssueInList(issueKey, summary, status, priority, priorityId)` para atualizar a linha da lista com o nome e o id da prioridade (ex.: para ícone e ordenação).

Referências: [WorkItemDetailPane.qml](src/qml/components/panes/WorkItemDetailPane.qml) — `setDetails` (prioridade), `getFieldData()` (prioridade); [MyWorkItemsController.qml](src/qml/controllers/MyWorkItemsController.qml) — passagem de `fieldData.prioridade` ao serviço; [MyWorkItemsPage.qml](src/qml/pages/MyWorkItemsPage.qml) — chamadas a `updateIssueInList(..., priority, priorityId)`.

---

## 4. Lista e exibição

### 4.1 List model (MyWorkItemsModel)

- **Roles**: cada item da lista expõe `priority` (nome) e `priorityId` (id), preenchidos na busca (ex.: search/jql) a partir do objeto `priority` da API. Quando a busca não retorna prioridade, podem ficar vazios; ao carregar detalhes ou após update, `updateIssueInList(key, summary, status, priority, priorityId)` corrige a exibição.
- **Método**: `updateIssueInList(issue_key, summary, status, priority="", priority_id="")` — `priority` e `priority_id` são opcionais; quando fornecidos, atualizam o item na lista para refletir ícone e ordenação.

### 4.2 Ordenação

- O modelo de lista suporta ordenação por **prioridade** (critério `"priority"`). A ordem usada é Highest → High → Medium → Low → Lowest (maior prioridade primeiro). O cabeçalho da lista (ex.: combo "Ordenar por") oferece a opção "Prioridade" ao utilizador.

### 4.3 Exibição na célula (IssueListItem / lista de work items)

- **Ícone**: mapeamento por nome ou por `priorityId` (ex.: Jira Cloud 10000–10004, ou 1–5) para ícones Breeze (flag-red, flag-yellow, flag, flag-green, flag-blue).
- **Texto**: abreviação para exibição (ex.: "Máx", "Alta", "Média", "Baixa", "Mín") ou o próprio nome quando não houver mapeamento.
- **Dualidade nome vs id**: o valor **enviado** na API (create/update) é sempre o **nome** (`prioridade`). O **id** (`priorityId`) é usado apenas para exibição e consistência na lista quando a API o devolve nos detalhes ou na busca.

Referência: [IssueListItem.qml](src/qml/components/lists/IssueListItem.qml) — `priorityIcon` e `priorityDisplay` em função de `root.priority` e `root.priorityId`.

---

## 5. Resumo e ficheiros (abas 7 e 8)

| Onde            | O quê |
|-----------------|-------|
| Backend (modelo) | WorkItemModel: `prioridade` (Property str, sinal prioridadeChanged), default e reset "Medium", fallback no setter. |
| Backend (serviço) | AtlassianService: create/update/transition com parâmetro `prioridade` (nome, opcional); detalhes com `priority` e `priorityId`. |
| QML (UI atual)  | IssueMetadataFields — secção Prioridade com IssueRadioGroup (opções fixas, bindings ao model.prioridade). |
| QML (páginas)  | CreateWorkItemPage: IssueMetadataFields com workItemModel; reset prioridade "Medium"; controller envia prioridade no create. MyWorkItemsPage: painel com setDetails(getDetails.priority) e getFieldData().prioridade; updateIssueInList(..., priority, priorityId). |
| Lista           | MyWorkItemsModel: roles priority/priorityId, updateIssueInList, ordenação por prioridade. IssueListItem/lista: ícone e texto a partir de priority e priorityId. |

**Ficheiros no âmbito (abas 7 e 8):**

| Ficheiro | Papel |
|----------|--------|
| [src/models/work_item_model.py](src/models/work_item_model.py) | Propriedade `prioridade`, reset em resetForNewIssue(). |
| [src/atlassian_service.py](src/atlassian_service.py) | create_issue / update_issue / transition com prioridade; parsing de detalhes (priority, priorityId). |
| [src/qml/components/controls/IssueMetadataFields.qml](src/qml/components/controls/IssueMetadataFields.qml) | Secção Prioridade (label + IssueRadioGroup); hoje partilhado com abas 0/1; nas abas 7/8 usa workItemModel. |
| [src/qml/pages/CreateWorkItemPage.qml](src/qml/pages/CreateWorkItemPage.qml) | IssueMetadataFields com workItemModel; reset prioridade; controller usa prioridade no create. |
| [src/qml/pages/MyWorkItemsPage.qml](src/qml/pages/MyWorkItemsPage.qml) | Chama updateIssueInList(..., priority, priorityId); passa fieldData (com prioridade) ao controller. |
| [src/qml/components/panes/WorkItemDetailPane.qml](src/qml/components/panes/WorkItemDetailPane.qml) | setDetails(details.priority), getFieldData().prioridade. |
| [src/qml/controllers/WorkItemFormController.qml](src/qml/controllers/WorkItemFormController.qml) | Payload de criação com prioridade. |
| [src/qml/controllers/MyWorkItemsController.qml](src/qml/controllers/MyWorkItemsController.qml) | updateIssue / transitionToInProgress com fieldData.prioridade. |
| [src/models/my_work_items_model.py](src/models/my_work_items_model.py) | priority/priorityId na lista; updateIssueInList; ordenação por prioridade. |
| Componente de lista (ex.: IssueList.qml / delegate) | Exibição de priority/priorityId (ícone + texto). |

Implementação futura opcional: componente dedicado "Priority" (ex.: `PriorityBlock.qml`) que implemente o contrato do §2.4 e seja usado em CreateWorkItemPage e no painel de detalhe de MyWorkItemsPage, sem alterar as abas 0 e 1. Até lá, a reutilização nas abas 7 e 8 continua a ser feita através do mesmo IssueMetadataFields com `workItemModel`.
