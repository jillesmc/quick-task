---
name: jira-quick-task-new-field
description: Adds a new Jira custom field to jira-quick-task (config, IssueModel, JiraService, QML form). Use when the user wants to add a custom field, new form field, or new Jira field to the issue form.
---

# Adicionar novo campo customizado no Jira Quick Task

Fluxo em 4 passos. Seguir na ordem.

## 1. config/config.json.example

Em `custom_fields`, adicionar chave (snake_case) e valor (ID do campo no Jira, ex: `customfield_12088`):

```json
"custom_fields": {
  "novo_campo": "customfield_XXXXX"
}
```

Se o campo tiver lista fixa de valores, adicionar array com mesmo nome + `_values`, ex: `"novo_campo_values": ["Opção A", "Opção B"]`.

## 2. src/models/issue_model.py

- Declarar signal: `novoCampoChanged = Signal(str)` (ou tipo adequado: list para multi-select).
- Propriedade read: `@Property(str, notify=novoCampoChanged)` com getter `return self._novoCampo`.
- Setter: `@novoCampo.setter` que atribui a `self._novoCampo` e chama `novoCampoChanged.emit(...)`.
- Inicializar `self._novoCampo` no `__init__`.
- Se houver valores fixos: property read-only `novoCampoValues` lendo de `self._config` (ex: `get_novo_campo_values` no ConfigManager, se necessário).

Se for campo de asset (objeto Jira Assets): ver modelo de `valor_entregue` / `plataformas_afetadas` (assets em config, object_type_id, etc.).

## 3. src/jira_service.py

- No método que monta o payload de criação (ex: `create_issue`): obter alias com `self.config.get_custom_field("novo_campo")` e incluir em `custom_fields` passado ao `JiraClient`.
- Garantir que o valor venha do model (ex: `self.novo_campo`) no tipo esperado pela API (string, lista de objetos, etc.).

## 4. QML (formulário)

- Em `src/qml/pages/IssueFormPage.qml` (ou form reutilizável em `components/forms/`): adicionar controle (ComboBox, CheckBox, TextField, etc.) e binding bidirecional para a propriedade do model em camelCase, ex: `issueModel.novoCampo`.
- Se o model for exposto como context property (ex: `issueModel`), usar esse nome.

## Checklist rápido

- [ ] config.json.example: `custom_fields` + `*_values` se aplicável
- [ ] ConfigManager: getter para o campo (e para valores) se usado
- [ ] IssueModel: Signal, Property, setter, init
- [ ] JiraService: get_custom_field("novo_campo") e envio no payload
- [ ] QML: binding no formulário de criação de issue

## Referência

README.md seção "Adicionar Novos Campos". IDs reais dos campos: Jira API `GET /rest/api/3/field`.
