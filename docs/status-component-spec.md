# Especificação: Componente de status (abas 7 e 8)

Componente reutilizável de seleção de status para **Criar work item** (aba 7) e **Minhas work items** (aba 8). Mostra todos os statuses do workflow; habilita apenas o status atual e os alcançáveis por transição; desabilita os sem caminho possível. Usa **workflow_metadata** e opcionalmente **happy_path** do `jira_metadata.json`. Isolado das abas 0 e 1 (JiraService/JiraClient); usa apenas **AtlassianService**, **AtlassianClient** e **atlassianMetadataConfigModel**.

---

## 1. Contrato do componente

### 1.1 Nome e ficheiros

| Item | Valor |
|------|--------|
| Componente QML | `WorkItemStatusField` |
| Ficheiro | `src/qml/components/controls/WorkItemStatusField.qml` |
| Lógica JS | `src/qml/utils/StatusReachableLogic.js` |
| Uso | Dentro de `WorkItemMetadataFields` (abas 7 e 8 apenas) |

### 1.2 Propriedades de entrada

| Propriedade | Tipo | Obrigatório | Descrição |
|-------------|------|-------------|-----------|
| `workflowEntry` | `var` (Object \| null) | Sim* | Objeto `{ statuses, transitions }` do `workflow_metadata` para o par (projectKey, issuetypeId). Se `null`, o model fica vazio (não mostra botões). |
| `currentStatusName` | `string` | Sim | Nome ou ID do status atual (ex.: `"In Progress"`, `"3"`). Usado para calcular quais statuses são reachable (fecho transitivo). Em modo criação, vazio. |
| `allPathsFromInitial` | `bool` | Não | Quando true (ex.: CreateWorkItemPage), **todos** os statuses ficam habilitados. Default: `false`. |
| `availableTransitions` | `var` (lista) | Não | Transições disponíveis da API (GET issue/transitions). Quando definida e não vazia, **enabled** pode ser calculado a partir desta lista; nas abas 7/8 o enabled usa o grafo (caminhos completos). |
| `selectedValue` | `string` | Sim | Nome do status atualmente selecionado (binding bidirecional com o modelo, ex.: `workItemModel.statusInicial`). |
| `enabled` | `bool` | Não | Se o bloco inteiro está habilitado. Default: `true`. |

\* Quando `workflowEntry` é `null`, o consumidor (ex.: `WorkItemMetadataFields`) deve mostrar um fallback (ex.: `IssueRadioGroup` com `statusSequence`).

### 1.3 Saída

| Saída | Tipo | Descrição |
|-------|------|-----------|
| Signal `valueChanged(string value)` | signal | Emitido quando o utilizador escolhe outro status. `value` = nome do status (ex.: `"Done"`). O consumidor deve atualizar o modelo (ex.: `workItemModel.statusInicial = value`). |

### 1.4 Comportamento resumido

- **Create (allPathsFromInitial)**: todos os statuses do workflow ficam **habilitados** (todos os caminhos possíveis).
- **Edit**: **habilitado** = status atual **ou** qualquer status alcançável por **caminhos completos** (fecho transitivo do grafo a partir do atual). Quando `availableTransitions` é fornecido, pode-se usar essa lista para enabled em vez do grafo (comportamento opcional).
- **Layout em duas colunas**: coluna principal = ordem por caminho directed (initial → caminho mais curto até done “positivo” → done “negativos”); segunda coluna = statuses que são destino de transição **global** (ex.: Blocked, Canceled).
- Cada item é um `RadioButton`: `text` = nome do status; `enabled` = resultado da lógica acima; `checked` quando `selectedValue === modelData.name`.
- Não depende de JiraService/JiraClient nem de `jiraMetadataConfigModel`; apenas de dados já fornecidos (workflow entry, status atual e opcionalmente lista de transições da API).

---

## 2. Dados do jira_metadata.json

### 2.1 workflow_metadata

Estrutura (por projeto e issue type):

```json
"workflow_metadata": {
  "PROJECT_KEY": {
    "ISSUETYPE_ID": {
      "workflowId": "...",
      "workflowName": "...",
      "statuses": [
        { "id": "10034", "name": "To Do", "category": "new", "categoryName": "To Do" },
        { "id": "3", "name": "In Progress", "category": "indeterminate", "categoryName": "In Progress" },
        { "id": "10077", "name": "Blocked", "category": "new", "categoryName": "To Do" },
        { "id": "10003", "name": "Done", "category": "done", "categoryName": "Done" }
      ],
      "transitions": [
        { "id": "21", "name": "In Progress", "type": "directed", "from": ["10034", "10077"], "to": { "id": "3", "name": "In Progress" } },
        { "id": "41", "name": "Done", "type": "directed", "from": ["3"], "to": { "id": "10003", "name": "Done" } },
        { "id": "2", "name": "Blocked", "type": "directed", "from": ["3"], "to": { "id": "10077", "name": "Blocked" } }
      ]
    }
  }
}
```

- **statuses**: lista de `{ id, name, category?, categoryName? }`. O componente usa `id` e `name`.
- **transitions**: cada item tem `type` (`"initial"` | `"directed"` | `"global"`), `from` (array de status IDs ou vazio), `to` (objeto `{ id, name }`).

### 2.2 happy_path (opcional)

Formato: por projeto/issue type, array de **status IDs** na ordem desejada (ex.: To Do → In Progress → Done). Não é usado pelo componente atual para habilitar/desabilitar; a regra de “reachable” baseia-se apenas em **transitions**. O happy_path pode ser usado noutros fluxos (ex.: wizard de configuração).

### 2.3 Origem do workflow entry nas abas 7 e 8

- **MyWorkItemsPage (aba 8)**: ao carregar detalhes da issue, o backend (AtlassianService) devolve `projectKey` e `issuetypeId` no objeto de detalhes. O painel (`WorkItemDetailPane`) guarda esses valores e passa `atlassianMetadataConfigModel`, `projectKey` e `issuetypeId` para `WorkItemMetadataFields`. O workflow entry é:  
  `getLoadedMetadata().workflow_metadata[projectKey][issuetypeId]`.
- **CreateWorkItemPage (aba 7)**: pode não ter issue selecionada; `projectKey`/`issuetypeId` podem estar vazios. Nesse caso `_workflowEntry` fica `null` e deve ser usado o fallback (ex.: `IssueRadioGroup` com `statusSequence` do config).

---

## 3. Algoritmo “reachable”

Implementado em `StatusReachableLogic.js`.

### 3.1 Grafo e fecho transitivo

O workflow é modelado como **grafo**: nós = statuses; arestas = transições (`initial`, `directed`, `global`).  
- **initial**: arco (criação) → `to.id`.  
- **directed**: para cada `from_id` em `t.from`, arco `from_id` → `to.id`.  
- **global**: de **qualquer** nó existe arco → `to.id`.

**Caminhos completos**: conjunto de todos os nós alcançáveis a partir de um nó (BFS/DFS no grafo).  
- Em **criação**: todos os statuses habilitados (ou nós alcançáveis a partir do(s) destino(s) da initial).  
- Em **edição**: habilitar = status atual + `reachableStatusIdsFull(workflowEntry, currentId)`.

### 3.2 reachableStatusIds / reachableStatusIdsFull

- `reachableStatusIds(workflowEntry, fromStatusId)`: um passo (transições diretas).  
- `reachableStatusIdsFull(workflowEntry, fromStatusId)`: **todos** os IDs alcançáveis (fecho transitivo). Se `fromStatusId === ""`, partida = destino(s) da transição initial.

### 3.3 buildStatusOptions / buildStatusOptionsWithColumns

- **buildStatusOptions(workflowEntry, currentStatusNameOrId)**: usa `reachableStatusIdsFull` para enabled; ordem por `statusDisplayOrder`.
- **buildStatusOptionsAllEnabled(workflowEntry)**: todos com `enabled: true` (modo criação).
- **buildStatusOptionsWithColumns(workflowEntry, currentStatusNameOrId, allEnabled)**: devolve `{ mainColumn, globalColumn }` para o layout em duas colunas; ordem main = `statusDisplayOrderMainColumn`, global = `statusIdsGlobalColumn`.

### 3.4 Ordem visual e layout em duas colunas

- **Coluna principal** (`statusDisplayOrderMainColumn`): (1) destino da transition **initial**; (2) caminho mais curto só por arestas **directed** até ao primeiro status da category `done` considerado “positivo” (ex.: nome "Done"); (3) outros statuses `done` “negativos” (ex.: Canceled); (4) restantes statuses não globais.
- **Coluna globais** (`statusIdsGlobalColumn`): IDs que são destino de alguma transição `type: "global"` (ex.: Blocked, Canceled).
- Exemplo de layout: coluna 1 = To Do, In Progress, Done; coluna 2 = Blocked, Canceled.

### 3.5 findPaths e fluxo ao salvar

- **findPaths(workflowEntry, fromStatusId, toStatusId)** devolve lista de caminhos (cada caminho = array de IDs).  
  Regras: (1) se target é o initial → `[]`; (2) se existe transição **global** para target → `[[fromId, toId]]`; (3) senão, subgrafo só **directed**, BFS/DFS para listar caminhos.
- **Ao salvar** (MyWorkItemsPage): se o status escolhido difere do atual, calculam-se os caminhos. Se 0 caminhos (target = initial), não se executa transição. Se 1 caminho, executa-se a sequência de transições (backend: `transition_along_path`). Se vários caminhos, mostra-se um diálogo para o utilizador escolher qual sequência executar.

### 3.6 buildStatusOptionsFromApi(workflowEntry, currentStatusNameOrId, availableTransitions)

Quando o painel está em modo “detalhe de issue” (aba 8), o backend envia as transições disponíveis (GET issue/transitions) em `details.availableTransitions`. O componente usa esta lista para **enabled**: habilitados são o status atual e todos os statuses que são destino (`to.id` ou `to.name`) de alguma transição em `availableTransitions`. A ordem continua a ser `statusDisplayOrder(workflowEntry)`.

---

## 4. Integração nas abas 7 e 8

### 4.1 WorkItemMetadataFields

- Novas propriedades: `atlassianMetadataConfigModel`, `projectKey`, `issuetypeId`.
- Propriedade derivada: `_workflowEntry` = `getLoadedMetadata().workflow_metadata[projectKey][issuetypeId]` (ou `null` se faltar metadata/project/issuetype).
- **Quando `_workflowEntry` existe**: usa `WorkItemStatusField` com:
  - `workflowEntry`: `_workflowEntry`
  - `currentStatusName`: quando `allPathsFromInitial` é true, `""`; senão `statusForRestriction || workItemModel.statusInicial`
  - `allPathsFromInitial`: true na CreateWorkItemPage (todos os statuses habilitados)
  - `availableTransitions`: opcional; quando definido pode ser usado para **enabled**; nas abas 7/8 o enabled é calculado pelo grafo (caminhos completos)
  - `selectedValue`: `workItemModel.statusInicial`
  - `enabled`: igual ao do formulário
  - `onValueChanged`: atualiza `workItemModel.statusInicial`
  - Layout em duas colunas (main + globais) conforme secção 3.4.
- Propriedades em `WorkItemMetadataFields`: `allPathsFromInitial` (false por defeito; true na CreateWorkItemPage), `availableTransitions` (opcional).
- **Quando `_workflowEntry` é null**: usa o fallback `IssueRadioGroup` com `statusSequence` e `minEnabledIndex` (comportamento anterior).

### 4.2 WorkItemDetailPane (aba 8)

- Recebe `atlassianMetadataConfigModel` da página.
- Em `setDetails(details)` preenche `projectKey`, `issuetypeId` e `availableTransitions` a partir de `details` (retornados pelo backend; as transições vêm de GET issue/transitions no JiraService ao carregar detalhes).
- Passa `atlassianMetadataConfigModel`, `projectKey`, `issuetypeId` e `availableTransitions` para `WorkItemMetadataFields`.
- Após o utilizador atualizar a issue (ou fazer uma transição/quick action), a página chama novamente `loadIssueDetails(issueKey)` para re-obter detalhes (incluindo `availableTransitions`), de modo que o painel atualize os caminhos possíveis sem recarregar manualmente.

### 4.3 CreateWorkItemPage (aba 7)

- Pode passar `atlassianMetadataConfigModel`; se não houver `projectKey`/`issuetypeId` (sem issue), `_workflowEntry` fica `null` e o fallback com `statusSequence` é usado.
- Define `allPathsFromInitial: true` em `WorkItemMetadataFields`, para que **todos** os statuses do workflow apareçam habilitados (todos os caminhos possíveis na criação).

### 4.4 Isolamento

- O componente e a lógica de status das abas 7 e 8 **não** usam JiraService, JiraClient nem `jiraMetadataConfigModel`.
- Usam apenas AtlassianService, AtlassianClient e `atlassianMetadataConfigModel`, e dados já presentes em `jira_metadata.json` (workflow_metadata).

---

## 5. Acessibilidade

- Cada `RadioButton` tem `Accessible.description`:
  - Se `enabled`: “Transição permitida para este status.”
  - Se desabilitado: “Sem transição possível a partir do status atual.”
- O texto do botão é o nome do status (`modelData.name`), legível por leitores de ecrã.

---

## 6. Casos de borda

| Caso | Comportamento |
|------|----------------|
| `workflowEntry` é `null` | `_statusOptions` fica `[]`; não se mostra nenhum botão. O consumidor deve mostrar o fallback (IssueRadioGroup). |
| `workflowEntry.statuses` vazio ou ausente | `buildStatusOptions` retorna `[]`. |
| `currentStatusName` não existe no workflow | `currentId` fica `""`; apenas transições do tipo initial/global (e as directed com `from` vazio) ficam reachable; o “atual” não fica habilitado (nenhum item com `id === currentId`). |
| Status atual por nome em maiúsculas (ex.: `"IN PROGRESS"`) | O JS mapeia também `name.toUpperCase()` para id; o status atual é reconhecido e fica habilitado. |
| Comparação de `selectedValue` com `modelData.name` | Feita por igualdade de string; o nome no Jira pode variar em capitalização — o backend/API trata; no UI mantém-se o nome vindo do workflow. |

---

## 7. Resumo

- **Componente**: `WorkItemStatusField` — entrada (workflow, status atual, allPathsFromInitial, valor selecionado) e saída (signal ao mudar).
- **Regra de UI**: Create = todos habilitados; Edit = status atual + todos alcançáveis por caminhos completos (fecho transitivo); layout em duas colunas (main + globais).
- **Ao salvar**: sequência de transições até ao status escolhido (findPaths; se vários caminhos, diálogo de escolha); backend executa `transition_along_path` com a lista de nomes de status.
- **Dados**: `workflow_metadata` do `jira_metadata.json`; abas 7 e 8 usam apenas AtlassianService/AtlassianClient e `atlassianMetadataConfigModel`.
- **Simplicidade**: um único componente QML + módulo JS (grafo, reachable full, findPaths, ordem em duas colunas); sem lógica de rede no componente.
