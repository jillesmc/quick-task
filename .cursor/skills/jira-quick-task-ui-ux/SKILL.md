---
name: jira-quick-task-ui-ux
description: Design de interface, acessibilidade, usabilidade, padrões Kirigami. Use quando o usuário pedir melhorias visuais, acessibilidade, UX ou redesign.
---

# UI/UX no jira-quick-task

## Princípios de design

- **Clareza**: hierarquia visual clara, labels descritivos, feedback imediato ao usuário.
- **Consistência**: seguir padrões Kirigami e componentes existentes.
- **Feedback**: indicar ações em progresso, sucesso e erro de forma visível.

## Acessibilidade

- Labels em controles (Accessible.name, Accessible.description).
- Contraste adequado entre texto e fundo.
- Ordem de foco lógica (KeyboardNavigation).

## Padrões Kirigami

- Cards para agrupamento de conteúdo.
- Formulários com labels e validação.
- Navegação por páginas (PageRouter, GlobalDrawer quando aplicável).

## Evitar

- "AI slop" visual: genéricos, excesso de padding, ícones sem propósito.
- Mudanças bruscas sem contexto; manter consistência com o resto do app.
