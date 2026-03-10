# Campos Summary e Description: estado atual e componentes reutilizáveis

Este documento descreve o estado atual dos campos **summary** e **description** (frontend e backend) e a especificação de três componentes reutilizáveis: o campo Summary, o campo Description e um wrapper que agrupa os dois e adiciona as ações de Voice e IA, atendendo tanto à tela de criação quanto à de edição. Onde o comportamento puder ser único, mantém-se; onde precisar variar entre telas, expõe-se como parâmetro configurável.

---

## 1. Visão geral do backend

### 1.1 Summary
- **Modelo**: `IssueModel.summary` (string), signal `summaryChanged`. Inicial e reset: `""`.
- **Config**: não é custom field; não há entrada em config.
- **Summary vazio não é permitido em nenhum lugar**: nem no frontend nem no backend. Tanto na criação quanto na edição, o backend deve **rejeitar** (erro, não prosseguir) quando `summary` estiver vazio ou só espaços após `strip()`. O frontend deve validar e impedir submeter com summary vazio. Não há exceção.
- **Criação**: obrigatório. Backend: `summary.strip()` vazio → erro "Summary é obrigatório", não chama a API. Enviado como `fields["summary"]` (string) apenas quando válido.
- **Edição**: obrigatório. Backend: ao atualizar issue, se `summary` vier vazio ou só espaços → erro (ex.: "Summary é obrigatório"), não enviar PUT. O mesmo critério da criação.
- **Limite de caracteres**: único em toda a aplicação: **255 caracteres** para o summary. Esse limite vale no frontend (SummaryField), na validação antes de enviar ao Jira, e nos fluxos de Voice/LocalAI (truncar a 255 após parse). Não há outro valor de limite para summary; a lógica é única.

### 1.2 Description
Regras unificadas para criação e edição; detalhes da **forma única** de trabalhar com o campo estão em §1.4.
- **Modelo**: `IssueModel.description` (string em Markdown), signal `descriptionChanged`. `IssueModel.pendingAttachments` em criação e edição (ver §1.4).
- **Config**: não é custom field; config para embed de anexos (`get_attachment_embed_enabled()`, `get_embed_max_display_width()`) usada ao montar ADF na fronteira com a API.
- **No app**: descrição é sempre **Markdown**. ADF só existe na fronteira com o Jira (envio e leitura). Anexos novos: **pending** em ambos os fluxos até ao submit.

### 1.3 O que os componentes precisam do backend

Resumo do que frontend e componentes devem garantir e o que o backend assume.

**Summary**
- Valor: string, trim antes de enviar. **Obrigatório** em criação e edição — vazio não permitido em nenhum lugar (frontend valida, backend rejeita em create e em update).
- **Máximo 255 caracteres** — regra única (UI, validação, Voice/IA). Aplicar no TextField e na validação antes de submeter.

**Description**
- Ver **§1.4** para a forma única. Resumo: valor sempre em Markdown; opcional; anexos via pending em ambos; um único componente de preview.
- Anexos e preview: ver §1.4 (forma única para criação e edição).
- **Preview**: ver §1.4 — um único componente (Markdown + resolução de imagens Jira quando `jiraService` presente) para criação e edição.

### 1.4 Forma única de trabalhar com o campo description (criação e edição)

Um único modelo para o campo description em toda a aplicação: mesma representação, mesmo fluxo de anexos e mesma fronteira com a API.

**Representação no app (sempre)**
- **Sempre Markdown**: o valor editado e guardado no model é uma string em Markdown. Pode conter placeholders `pending:<id>` para anexos ainda não enviados. Nunca guardamos ADF no model; ADF existe só na comunicação com o Jira.

**Fronteira com a API (ADF)**
- **Envio**: no momento do submit (criação ou edição), a descrição é convertida **uma vez** de Markdown para ADF: (1) se há `pendingAttachments`, faz-se upload, substituem-se os placeholders no texto (por URL ou por nós de media no ADF), (2) converte-se o Markdown final para ADF (`_text_to_adf` ou `build_description_adf_with_media` quando há embed), (3) envia-se no create ou no update. A lógica de conversão e de embed é a mesma; só o momento difere (após `create_issue` no JiraWorker vs antes de `update_issue` no UpdateWorker).
- **Leitura**: a API devolve ADF; no app convertemos **sempre** para Markdown (`_adf_to_markdown`) e preenchemos `issueModel.description`. O frontend nunca trabalha com ADF, só com Markdown.

**Anexos (attachments)**
- **Mesmo fluxo em criação e edição**: ao arrastar/colar, não se faz upload; insere-se um placeholder `pending:<id>` na descrição e adiciona-se um item a `issueModel.pendingAttachments` `[{ path, filename, placeholderId, layout?, displayWidth? }]`. No submit: (1) upload de cada pendente (`add_attachment(issue_key, path)`), (2) substituição dos placeholders na descrição (por URL ou ADF com media, conforme config de embed), (3) envio da descrição. Na criação a `issue_key` só existe após criar a issue; na edição já existe — por isso o worker que orquestra é diferente, mas o algoritmo (upload → substituir → converter para ADF → enviar) é o mesmo.

**Preview**
- **Um único comportamento**: um único componente de preview que recebe o texto em Markdown e, quando existir `jiraService`, resolve URLs de anexos Jira (`/attachment/content/<id>`) para exibir as imagens. Serve tanto para criação (texto pode ter só Markdown e eventualmente `pending:<id>`) como para edição (texto pode ter já URLs de anexos carregados da issue). Placeholders `pending:<id>` podem ser exibidos como texto ou como área reservada; o importante é não haver dois tipos de preview — usa-se sempre o mesmo que suporta Markdown e, opcionalmente, resolução de imagens Jira quando `jiraService` está disponível.

**Resumo**

| Aspecto   | Regra única |
|-----------|-------------|
| No app    | Sempre Markdown (string); placeholders `pending:<id>` para anexos pendentes. |
| ADF       | Só na fronteira: entrada/saída da API. Entrada: ADF → Markdown; saída: Markdown → ADF no submit. |
| Anexos    | Pending em ambos; upload e substituição apenas no submit; mesma lógica nos dois workers. |
| Preview   | Um componente: Markdown + resolução de URLs de anexos Jira quando `jiraService` presente. |

---

## 2. Componente: SummaryField

Campo de linha única para o resumo da issue, reutilizável na criação e na edição.

### 2.1 Contrato (props / parâmetros configuráveis)

| Prop | Tipo | Default | Descrição |
|------|------|---------|-----------|
| `text` | string (bindable) | `""` | Valor do summary (binding bidirecional com o model). |
| `enabled` | bool | `true` | Habilita/desabilita o TextField. |
| `labelText` | string | `qsTr("Summary:")` | Rótulo exibido acima do campo. |
| `placeholderText` | string | `""` | Placeholder do TextField (hoje não usado). |
| `maximumLength` | int | `255` | Limite de caracteres: **sempre 255** para o summary. Lógica única em toda a aplicação (este componente, validação e fluxos Voice/IA usam 255). O componente deve usar este valor no TextField (ex.: `maximumLength: 255`). Não configurável para outro valor. |
| `required` | bool | `true` | Sempre `true`. Summary não pode ficar vazio em nenhuma tela. O **frontend** (validator/controller) deve impedir submeter com summary vazio; o **backend** deve rejeitar em criação e edição — em nenhum lugar é permitido summary vazio. |
| `requestFocusOnLoad` | bool | `false` | Se true, chama `forceActiveFocus()` no campo quando o componente estiver pronto. **Criação**: `true`. **Edição**: `false`. |

Nenhum botão de ação (Voice, IA) fica dentro deste componente; eles ficam no wrapper.

### 2.2 Comportamento
- **Visual**: uma linha com label (negrito) e um `Controls.TextField` preenchendo a largura.
- **Binding**: `text` ↔ propriedade do model (ex.: `issueModel.summary`); `onTextChanged` atualiza o model.
- **Validação**: o validator (ex.: `Validators.validateIssueForm`) deve exigir summary não vazio em **criação e edição** — em nenhum lugar o frontend pode permitir submeter com summary vazio. O backend, por sua vez, deve rejeitar (erro) em create e em update se summary estiver vazio. Limite de **255 caracteres** na UI (TextField) e na validação antes de submeter (mesma regra em todo o app).
- **Simplificação**: hoje existem dois blocos quase iguais (IssueFormPage e MyIssuesDetailPane); um único componente com os parâmetros acima unifica os dois e mantém o mesmo aspecto.

### 2.3 Uso por tela
- **Criação**: `required: true`, `requestFocusOnLoad: true`, `enabled: !page.isProcessing`, `maximumLength: 255` (sempre).
- **Edição**: `required: true` — summary vazio não é permitido (frontend valida, backend rejeita). `requestFocusOnLoad: false`, `enabled: pane.selectedIssueKey !== "" && !pane.isProcessing`, `maximumLength: 255` (sempre).

---

## 3. Componente: DescriptionField

Campo multilinha com edição/preview, drag-and-drop e anexos, reutilizável na criação e na edição.

### 3.1 Contrato (props / parâmetros configuráveis)

| Prop | Tipo | Default | Descrição |
|------|------|---------|-----------|
| `text` | string (bindable) | `""` | Valor da descrição em Markdown (binding bidirecional). |
| `enabled` | bool | `true` | Habilita TextArea e DropArea. |
| `labelText` | string | `qsTr("Description:")` | Rótulo da seção. |
| `placeholderText` | string | (texto sobre arrastar/Ctrl+V) | Placeholder do TextArea. |
| `editMode` | bool (bindable) | `true` | true = modo edição (TextArea), false = modo preview. |
| `showEditPreviewToggle` | bool | `true` | Exibe o toggle Edição/Preview. |
| `showAttachmentsButton` | bool | `true` | Exibe o botão "Anexos na descrição". |
| `mode` | enum | `"create"` | `"create"` \| `"edit"`. Só afecta qual worker resolve os pendentes no submit (JiraWorker vs UpdateWorker). Comportamento do campo (Markdown, pending, preview) é o mesmo; ver §1.4. |
| `jiraService` | object | (obrigatório se drop/attachments) | Para extensões permitidas, upload (edit) e preview com imagens Jira. |
| `clipboardHelper` | object | optional | Para colar imagem (Ctrl+V). |
| `issueModel` | object | optional | Para `text` e para `pendingAttachments` em **criação e edição** (mesmo comportamento: anexos pendentes até o submit). |

**Comportamento (igual em criação e edição, §1.4)**:
- DropArea/colar: inserem placeholder na descrição e adicionam a `issueModel.pendingAttachments`; não fazem upload. Upload e substituição dos placeholders ocorrem só no submit (no worker correspondente).
- Preview: um único componente — recebe Markdown e, se `jiraService` estiver disponível, resolve URLs de anexos Jira para exibir imagens. Mesmo componente nas duas telas.

### 3.2 Comportamento
- **Visual**: label + barra com EditPreviewToggle + botão "Anexos na descrição" + área (StackLayout: edição ou preview).
- **Edição**: TextArea com wrap, dentro de DropArea; atalhos Ctrl+E (edição), Ctrl+Shift+P (preview), Escape (edição), Ctrl+V (colar imagem) — podem ser opcionais via prop se quiser.
- **Preview**: um único componente (§1.4): entrada = texto Markdown + opcional `jiraService`; renderiza Markdown e resolve URLs `/attachment/content/<id>` para imagens quando `jiraService` presente. Usado em criação e edição.
- **Drop**: extensões via `jiraService.getAllowedAttachmentExtensions()` / `getAllowedImageExtensions()`; insere placeholder na descrição e adiciona a `issueModel.pendingAttachments`. Upload e substituição só no submit (JiraWorker após create_issue ou UpdateWorker antes de update_issue).
- **getFieldData**: quem chama lê `issueModel.description`; binding bidirecional mantém o valor.
- **Simplificação**: um único DescriptionField e uma única forma de trabalhar (§1.4); `mode` só indica qual worker resolve no submit.

### 3.4 Nota: edição com pending (forma única §1.4)

A forma única em §1.4 aplica-se também à edição: anexos novos entram em pending e só são enviados no submit (UpdateWorker). A API do Jira permite (`add_attachment(issue_key, path)` para issue existente); no submit faz-se upload dos pendentes, substituição dos placeholders e `update_issue(description=...)`. Criação e edição usam assim o mesmo fluxo.

### 3.3 Uso por tela
- **Criação**: `mode: "create"`, `enabled: !page.isProcessing`, `jiraService`, `clipboardHelper`, `issueModel` (com `pendingAttachments`). Mesmo preview que na edição (Markdown + resolução de imagens Jira se `jiraService` presente).
- **Edição**: `mode: "edit"`, `enabled: pane.selectedIssueKey !== "" && !pane.isProcessing`, `jiraService`, `clipboardHelper`, `issueModel` (com `pendingAttachments`). Mesmo preview e mesmo fluxo de anexos (pending até ao submit); §1.4.

---

## 4. Componente: SummaryAndDescriptionBlock (wrapper)

Agrupa SummaryField e DescriptionField e adiciona os botões e features de Voice e IA existentes hoje na tela. O SummaryField é sempre usado com **limite de 255 caracteres** (lógica única; o wrapper não altera esse valor).

### 4.1 Contrato (props / parâmetros configuráveis)

| Prop | Tipo | Default | Descrição |
|------|------|---------|-----------|
| `issueModel` | object | required | Model com `summary`, `description` e `pendingAttachments` (criação e edição; §1.4). |
| `mode` | enum | `"create"` | `"create"` \| `"edit"`. Repassado ao DescriptionField e usado para habilitar/ocultar ações. |
| `enabled` | bool | `true` | Repassado para SummaryField e DescriptionField (ex.: `!page.isProcessing` ou `selectedIssueKey !== "" && !pane.isProcessing`). |
| `jiraService` | object | optional | Para DescriptionField (drop, anexos, preview — §1.4) e para extensões. |
| `clipboardHelper` | object | optional | Para colar imagem na descrição. |
| `voiceInputService` | object | optional | Quando presente e disponível, exibe e habilita botões de Voice e IA. |
| `showVoiceCreateButton` | bool | `true` | Exibe o botão "Criar por voz" ao lado do label do Summary (só faz sentido em create; em edit pode ser false ou oculto). |
| `showExpandWithAIButton` | bool | `true` | Exibe o botão "Expandir com IA" ao lado do Summary. |
| `requestSummaryFocus` | bool | `false` | Repassado ao SummaryField como `requestFocusOnLoad`. **Criação**: `true`. **Edição**: `false`. |
| `summaryRequired` | bool | `true` | Repassado ao SummaryField como `required`. Sempre `true`. Summary vazio não é permitido em nenhum lugar: frontend valida, backend rejeita em criação e edição. |