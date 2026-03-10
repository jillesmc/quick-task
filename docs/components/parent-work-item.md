# Campo Parent Work Item (abas 7 e 8)

Este documento especifica o campo **Parent Work Item** para a nova versão dos componentes das **abas 7 e 8** (Create Work Item / My Work Items). O campo representa o work item pai na hierarquia. Nomenclatura: **parentWorkItem**, **parentWorkItemKey**, **parentWorkItemSummary**. A versão antiga (abas 0 e 1) permanece inalterada e fora do âmbito deste documento.

---

## 0. Hierarquia e tipo de parent

A hierarquia pode variar por projeto; um exemplo de referência é:

**Initiative → Epic → Task → Sub-task**

Ou seja, o parent pode ser uma Initiative (acima do Epic), um Epic (acima da Task), uma Task (acima da Sub-task), etc. O tipo de parent que o campo aceita depende do contexto (ex.: ao criar uma Task, o parent é um Epic; ao criar uma Sub-task, o parent é uma Task). A API do serviço deve ser **genérica**: ao buscar ou obter o parent por chave, o chamador indica **que tipo de parent** está a usar (ex.: `"Epic"`, `"Initiative"`, `"Task"`). Assim o mesmo campo e os mesmos componentes servem qualquer nível da hierarquia, sem amarrar nomes de método a um tipo concreto (ex.: sem `searchEpicByKey`).

---

## 1. Backend (abas 7 e 8)

### 1.1 Modelo (WorkItemModel)

- **Propriedades**: `parentWorkItemKey` (string), `parentWorkItemSummary` (string). Expostas ao QML com `Property(str, notify=parentWorkItemKeyChanged)` e `Property(str, notify=parentWorkItemSummaryChanged)`.
- **Sinais**: `parentWorkItemKeyChanged`, `parentWorkItemSummaryChanged`.
- **Inicial e reset**: em `resetForNewIssue()` ambas são repostas para `""`.
- **Opcional**: o Parent Work Item é opcional em criação e edição; não há validação obrigatória.

**Nota:** Se o modelo ainda expuser `epicParentKey`/`epicParentSummary`, a migração para `parentWorkItemKey`/`parentWorkItemSummary` faz parte desta nova versão.

### 1.2 Serviço (AtlassianService)

API **genérica** para busca e seleção do work item pai nas abas 7/8. O **tipo de parent** (issue type esperado, ex.: Epic, Initiative, Task) é passado pelo chamador; o serviço não fixa um tipo no nome do método.

**Busca assíncrona (worker em thread):**

- **Método**: `searchParentsAsync(query, parent_issue_type, filters..., next_page_token)` → retorna `bool`.  
  `parent_issue_type` define que tipo de work items estamos a buscar (ex.: `"Epic"`, `"Initiative"`). Filtros (created_by_me, assigned_to_me, project_platform, exclude_done, etc.) podem ser um dict ou parâmetros nomeados.
- **Sinais**: `parentSearchStarted(parentIssueType)`, `parentSearchCompleted(parentIssueType, results, nextToken)`, `parentSearchPageCompleted(parentIssueType, results, nextToken)`. Incluir o tipo nos sinais permite múltiplas buscas em paralelo (ex.: um form para Epic parent e outro para Initiative) sem misturar resultados.

**Busca/obtenção por chave:**

- **Método**: `fetchParentByKey(key: str, parent_issue_type: str)` → retorna `Dict[str, str]` (ex.: `{"key": "PLATFORM-123", "summary": "..."}`). Usado no painel de edição para pré-preencher o parent quando os detalhes trazem `parentKey`; o chamador indica o tipo esperado (ex.: `"Epic"`) para que o serviço saiba o que buscar. Assim o método serve qualquer nível da hierarquia.

**Persistência de filtros:**

- **getParentFilters(parent_issue_type)**, **setParentFilters(parent_issue_type, ...)** — persistência por tipo de parent, para que filtros de “parent Epic” não se misturem com “parent Initiative”, etc.

### 1.3 Contrato para o frontend (abas 7 e 8)

- **Modelo**: `workItemModel` com `parentWorkItemKey` e `parentWorkItemSummary` (leitura/escrita) e sinais.
- **Serviço**: `atlassianService` com `searchParentsAsync(query, parentIssueType, ...)`, sinais de busca incluindo `parentIssueType`, `fetchParentByKey(key, parentIssueType)`, `getParentFilters(parentIssueType)`, `setParentFilters(parentIssueType, ...)`. O **parent issue type** (ex.: `"Epic"`) é definido pelo contexto da página/painel (ex.: prop do bloco ou da página).

---

## 2. Telas (abas 7 e 8)

### 2.1 CreateWorkItemPage (criação, aba 7)

- **Posição**: coluna esquerda do SplitView, dentro do ScrollView; secção do parent work item entre dois `DividerBar` (acima: summary/description; abaixo: espaço final).
- **Layout**: `ColumnLayout` com label "Parent Work Item:" (ou equivalente) e formulário de busca com `Layout.fillWidth: true`, `Layout.fillHeight: true`. Altura redimensionável (ex.: variável de altura no ScrollView).
- **Bindings**: form ↔ `page.workItemModel.parentWorkItemKey` / `parentWorkItemSummary`. Valor vem do modelo; em criação não há shared.
- **Handlers**: `parentWorkItemSelected(key, summary)` atualiza `workItemModel` e, se aplicável, shared; `parentWorkItemCleared()` limpa shared e modelo.
- **enabled**: `!page.isProcessing`.

### 2.2 MyWorkItemsPage (edição, aba 8)

- **Painel de detalhe**: painel próprio para work items (ou extensão do existente) que usa `workItemModel` e o bloco Parent Work Item. Não depende do fluxo das abas 0/1.
- **Posição**: dentro do ScrollView do painel; mesmo padrão (label + form de busca), altura redimensionável.
- **Bindings**: modelo ↔ form; sincronização com `sharedParentWorkItemKey` e `sharedParentWorkItemSummary` quando a seleção vem da outra aba.
- **setDetails(details)**: quando os detalhes são carregados, se `details.parentKey` existe: (1) form `clearFilters()` e `clearAll()`; (2) `setSearchText(parentKey)`; (3) `atlassianService.fetchParentByKey(parentKey, parentIssueType)` — se retornar item, seleção programática; senão `requestAutoSelect` e `search(parentKey)`. O `parentIssueType` (ex.: `"Epic"`) vem do contexto do bloco/página. Se não há parent: `setDefaultFiltersForNoParent()` e `clearAll()`.
- **getParentWorkItemKey()**: retorna a chave do parent selecionado para o fluxo de update.
- **enabled**: conforme item selecionado e estado de processamento.

---

## 3. Formulário de busca

Nas abas 7 e 8 o bloco Parent Work Item usa um formulário de busca que recebe **parentIssueType** (ex.: `"Epic"`, `"Initiative"`) e chama a API genérica do serviço com esse tipo. Contrato necessário:

- **Props**: `enabled`, serviço (`atlassianService`), **`parentIssueType`** (string, ex.: `"Epic"`), chave e summary selecionados (mapeados para parentWorkItem no bloco), `isSearching`, `nextPageToken`, filtros, `autoSelectKey`/`autoSelectSummary`.
- **Sinais**: seleção (key, summary), cleared, search requested.
- **Métodos**: `performSearch(query, isPagination)` — usa `parentIssueType` ao chamar `atlassianService.searchParentsAsync(..., parentIssueType, ...)`; `search`, `clear`, `reset`, `selectParent(key, summary)`, `setSearchText`, `clearFilters`, `clearAll`, `setDefaultFiltersForNoParent`, `requestAutoSelect`, `loadFilters(parentIssueType)`, `saveFilters(parentIssueType)`.
- **Connections**: ao serviço para os sinais de busca, filtrando por `parentIssueType` quando os sinais o incluem, para não misturar resultados de vários tipos.

O bloco Parent Work Item expõe a API em termos de **parentWorkItem** (parentWorkItemSelected, parentWorkItemCleared, parentWorkItemKey); o form interno é genérico e recebe o tipo de parent como prop.

---

## 4. Bloco reutilizável "Parent Work Item" (wrapper)

Componente que agrupa o label, o form de busca e os bindings ao `workItemModel`, para uso em CreateWorkItemPage e no painel de detalhe de MyWorkItemsPage (abas 7 e 8).

### 4.1 Contrato (props)

| Prop | Tipo | Default | Descrição |
|------|------|---------|-----------|
| `model` | object | required | `workItemModel` com `parentWorkItemKey` e `parentWorkItemSummary`. |
| `atlassianService` | object | required | Serviço para busca do parent (abas 7/8). |
| **`parentIssueType`** | string | required | Tipo de issue do parent (ex.: `"Epic"`, `"Initiative"`, `"Task"`). Define o que se busca ao chamar `searchParentsAsync` / `fetchParentByKey`. |
| `enabled` | bool | `true` | Repassado ao form de busca. |
| `mode` | enum | `"create"` | `"create"` \| `"edit"`. Em edição suporta shared e setDetails. |
| `sharedParentWorkItemKey` | string | `""` | (Modo edit.) Sincroniza seleção vinda da outra aba. |
| `sharedParentWorkItemSummary` | string | `""` | (Modo edit.) Idem. |
| `preferredHeight` | real | (ex.: 250) | Altura preferida da secção. |
| `resizableHeight` | bool | `false` | Se true, secção redimensionável por drag. |

### 4.2 Sinais

| Sinal | Argumentos | Descrição |
|-------|------------|-----------|
| `parentWorkItemSelected(key, summary)` | string, string | Emitido quando o utilizador seleciona um parent; página/painel atualiza shared. |
| `parentWorkItemCleared()` | — | Emitido ao limpar; página/painel limpa shared e modelo. |

### 4.3 Edição: setDetails

Quando o painel recebe detalhes do work item (ex.: `details.parentKey`, `details.parentSummary`):

- **Se há parent**: (1) form `clearFilters()` e `clearAll()`; (2) `setSearchText(parentKey)`; (3) `atlassianService.fetchParentByKey(parentKey, parentIssueType)` — se retornar item, seleção programática; senão `requestAutoSelect` e `search(parentKey)`. O `parentIssueType` é o definido na prop do bloco.
- **Se não há parent**: `setDefaultFiltersForNoParent()` e `clearAll()` no form.

O bloco pode expor **`setParentFromDetails(parentKey, parentSummary)`** que encapsula essa lógica (usando internamente a prop `parentIssueType` na chamada a `fetchParentByKey`).

### 4.4 Valor para submit

O bloco expõe **`getParentWorkItemKey()`** (ou propriedade `parentWorkItemKey`) para o controller/página obter a chave atual no fluxo de update. Alternativamente o pai lê `model.parentWorkItemKey` com bindings ativos.

### 4.5 Uso nas abas 7 e 8

- **CreateWorkItemPage**: `model: page.workItemModel`, `atlassianService: page.atlassianService`, **`parentIssueType`** definido pelo tipo de work item que se está a criar (ex.: `"Epic"` se o parent for Epic), `enabled: !page.isProcessing`, `mode: "create"`. Handlers repassam `parentWorkItemSelected` e `parentWorkItemCleared`.
- **Painel de detalhe (MyWorkItemsPage)**: `model: pane.workItemModel`, `atlassianService`, **`parentIssueType`** conforme a hierarquia do item em edição (ex.: `"Epic"` para Tasks), `enabled` conforme seleção e processamento, `mode: "edit"`, `sharedParentWorkItemKey`, `sharedParentWorkItemSummary`. Ao carregar detalhes, chamar `setParentFromDetails`. Painel expõe `getParentWorkItemKey()` para o update.

---

## 5. Resumo e ficheiros (abas 7 e 8)

| Onde | O quê |
|------|--------|
| Backend (modelo) | WorkItemModel: `parentWorkItemKey`, `parentWorkItemSummary` (Property str, sinais). Opcional; reset em resetForNewIssue(). |
| Backend (serviço) | AtlassianService: API genérica por tipo — `searchParentsAsync(query, parentIssueType, ...)`, sinais com `parentIssueType`, `fetchParentByKey(key, parentIssueType)`, `getParentFilters(parentIssueType)`, `setParentFilters(parentIssueType, ...)`. |
| QML (form) | Form de busca genérico: recebe `parentIssueType` e chama a API do serviço com esse tipo; usado pelo bloco. |
| QML (wrapper) | Bloco "Parent Work Item": prop `parentIssueType` + label + form + bindings ao workItemModel + (edit) shared + setDetails/getParentWorkItemKey. |

**Ficheiros no âmbito (abas 7 e 8):**

| Ficheiro | Papel |
|----------|--------|
| [src/models/work_item_model.py](src/models/work_item_model.py) | parentWorkItemKey, parentWorkItemSummary. |
| [src/atlassian_service.py](src/atlassian_service.py) | API genérica de parent: searchParentsAsync, fetchParentByKey, getParentFilters, setParentFilters (todos com tipo de parent). |
| [src/qml/pages/CreateWorkItemPage.qml](src/qml/pages/CreateWorkItemPage.qml) | Bloco parent (coluna esquerda) com `parentIssueType` definido pelo contexto. |
| [src/qml/pages/MyWorkItemsPage.qml](src/qml/pages/MyWorkItemsPage.qml) | Painel de detalhe + bloco parent com `parentIssueType` adequado. |
| Form de busca (genérico por tipo) | Busca e seleção do parent; recebe `parentIssueType` e usa a API genérica. |
| Bloco (a criar, ex.: `ParentWorkItemBlock.qml`) | Wrapper com contrato do §4, incluindo prop `parentIssueType`. |

Implementação: criar `ParentWorkItemBlock.qml` (ou equivalente) que implemente o contrato do §4 e seja usado em CreateWorkItemPage e no painel de detalhe de MyWorkItemsPage, com `workItemModel`, `atlassianService` e **`parentIssueType`** (ex.: `"Epic"` para o nível Initiative→Epic→Task→Sub-task quando o parent é Epic), sem depender das abas 0 e 1.
