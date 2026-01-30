# Jira Quick Task

Aplicação desktop moderna para criar issues no Jira com interface gráfica usando Kirigami 6 (KDE). Permite criar issues, configurar campos customizados, transicionar status sequencialmente e registrar worklogs automaticamente.

## Características

- Interface gráfica moderna com Kirigami 6 (KDE)
- Criação de issues com campos customizados
- Visualização de issues do usuário
- Transição sequencial de status
- Registro automático de worklog após transição para "IN DEVELOPMENT"
- Configuração via interface gráfica (não requer edição manual de arquivos)
- Integração direta com **Jira REST API v3** para todas as operações
- Sistema de debug condicional (ativado com `--debug` ou `JIRA_QUICK_TASK_DEBUG=1`)
- Recarregamento automático de configurações após salvar

## Arquitetura

A aplicação usa:
- **PySide6/Qt6** para a interface gráfica
- **Kirigami 6** para componentes UI modernos
- **Jira REST API v3** diretamente (sem dependências externas como ACLI)
- **Flatpak** para distribuição
- **Docker** para desenvolvimento e testes

## Pré-requisitos

### Para Desenvolvimento e Testes

- **Docker** e **Docker Compose** instalados
  ```bash
  sudo apt install docker.io docker-compose
  ```
  Todas as dependências (Python, Qt6, KF6, PySide6, ferramentas QML) são instaladas automaticamente no container Docker. **Não é necessário instalar pacotes do sistema.**

### Para Executar a Aplicação (Flatpak)

- **Flatpak** instalado
  ```bash
  sudo apt install flatpak
  ```
- SDKs do Flatpak (instalados automaticamente via `make install-deps`)

**Nota**: A estratégia atual é usar Docker para desenvolvimento/testes (ambiente completo com Python + Qt6 + KF6) e Flatpak para executar a aplicação. Não é necessário instalar PySide6, Qt6 ou Kirigami no sistema host.

## Instalação

### Via Flatpak (Recomendado para Usuários)

A aplicação é distribuída como Flatpak. Para construir e instalar localmente:

```bash
# Instalar dependências do Flatpak (primeira vez)
make flatpak-install-deps

# Construir e instalar
make flatpak-build

# Executar
make flatpak-run
```

A aplicação também estará disponível no menu de aplicações do seu desktop environment.

### Para Desenvolvimento e Testes

Para desenvolvimento e testes, use Docker. O ambiente Docker unificado fornece Python, Qt6, KF6 (Kirigami 6) e todas as ferramentas necessárias:

```bash
# Construir imagem Docker unificada (Python + Qt6 + KF6) e exportar ferramentas
make dev-build

# Executar testes unitários
make dev-test

# Executar qmllint nos arquivos QML (usa ferramentas exportadas automaticamente)
make qml-lint

# Abrir shell interativo no container
make dev-shell

# Formatar código com black
make dev-format
```

**Importante**: 
- O Docker fornece ambiente completo (Python + Qt6 + KF6) para desenvolvimento e testes
- As ferramentas Qt6/KF6 são exportadas automaticamente para `dev-tools/` durante o build
- O comando `make qml-lint` configura variáveis de ambiente automaticamente (não precisa de configuração manual)
- Para executar a aplicação com UI, use Flatpak (veja seção abaixo)

## Configuração Inicial

### Primeira Execução

Na primeira execução, a aplicação abrirá automaticamente na aba de **Configuração**. Configure:

1. **URL do Servidor Jira**: Ex: `https://seu-projeto.atlassian.net`
2. **Email do Jira**: Seu email cadastrado no Jira
3. **Token de API**: Seu token de API do Jira

   **Como obter o token:**
   - Acesse: https://id.atlassian.com/manage-profile/security/api-tokens
   - Clique em "Create API token"
   - Dê um nome ao token (ex: "Jira Quick Task")
   - Copie o token gerado

4. Clique em **"Salvar"**: A aplicação irá:
   - Criar os arquivos de configuração automaticamente
   - Salvar suas credenciais
   - Buscar automaticamente o `accountId` via API do Jira
   - Recarregar configurações para que a aplicação funcione imediatamente

### Localização dos Arquivos de Configuração

- **Flatpak**: `~/.var/app/org.kde.jira-quick-task/config/jira-quick-task/`
- **Desenvolvimento local**: `~/.config/jira-quick-task/`

Os arquivos criados automaticamente:
- `config.json`: Configuração do projeto e campos customizados
- `.jira-config.yml`: Credenciais de conexão (server, login, token)

**Importante**: A aplicação **não lê mais variáveis de ambiente**. Toda configuração é feita via interface gráfica.

## Uso

### Criar uma Issue

1. **Summary**: Preencha o resumo da issue (obrigatório)
2. **Description**: Descrição da issue (opcional, suporta Markdown)
3. **Tipo de atividade**: Selecione o tipo de atividade
4. **Status inicial**: Selecione o status inicial (padrão: "TO DO")
5. **Documentação anexa**: Selecione "Sim" ou "Não"
6. **Utilização de IA**: Selecione "Sim" ou "Não"
7. **Épico** (opcional): Selecione um épico pai
8. **Worklog** (opcional):
   - Marque "Registrar worklog" se desejar registrar tempo
   - Informe data/hora de início (formato: YYYY-MM-DD HH:MM:SS)
   - Ajuste a duração (30 minutos a 9 horas, em incrementos de 30 minutos)
   - O worklog será registrado automaticamente após a transição para "IN DEVELOPMENT"

9. Clique em **"Criar"** para criar a issue

A aplicação mostrará uma barra de progresso durante a criação e transições de status.

### Visualizar Minhas Issues

A aba "Minhas Issues" mostra todas as issues atribuídas a você que não estão concluídas. Você pode:
- Buscar por texto (summary ou key)
- Ver detalhes da issue
- Atualizar a lista

## Debug

Para ativar mensagens de debug detalhadas:

```bash
# Via parâmetro
flatpak run org.kde.jira-quick-task --debug

# Via variável de ambiente
JIRA_QUICK_TASK_DEBUG=1 flatpak run org.kde.jira-quick-task
```

As mensagens de debug seguem o formato: `[DEBUG] ModuleName.function_name: mensagem`

## Estrutura do Projeto

```
jira-quick-task/
├── config/
│   ├── config.json.example          # Template de configuração do projeto
│   ├── .jira-config.yml.example     # Template de configuração Jira
│   └── config_manager.py            # Gerenciador de configuração
├── core/
│   ├── jira_client.py                  # Cliente para Jira REST API v3
│   └── status_transition.py          # Lógica de transição de status
├── src/
│   ├── app.py                        # Aplicação principal PySide6
│   ├── jira_service.py              # Serviço Jira (QObject)
│   ├── models/
│   │   ├── issue_model.py           # Modelo de dados do formulário
│   │   ├── my_issues_model.py       # Modelo para lista de issues
│   │   └── settings_model.py        # Modelo para configuração
│   ├── utils/
│   │   └── debug.py                  # Sistema de debug condicional
│   └── qml/
│       ├── Main.qml                  # Janela principal
│       ├── pages/
│       │   ├── IssueFormPage.qml    # Formulário de criação
│       │   ├── MyIssuesPage.qml      # Lista de issues
│       │   └── SettingsPage.qml      # Configuração
│       ├── components/               # Componentes reutilizáveis
│       └── controllers/              # Controladores QML
├── flatpak/                          # Manifestos Flatpak
├── Dockerfile.dev                    # Docker para desenvolvimento
├── docker-compose.yml                # Compose para desenvolvimento
└── requirements.txt                  # Dependências Python
```

## Desenvolvimento

### Adicionar Novos Campos

1. Adicione o campo em `config/config.json.example`:
   ```json
   "custom_fields": {
     "novo_campo": "customfield_XXXXX"
   }
   ```

2. Adicione propriedade em `src/models/issue_model.py`:
   ```python
   novoCampoChanged = Signal(str)
   
   @Property(str, notify=novoCampoChanged)
   def novoCampo(self):
       return self._novoCampo
   ```

3. Adicione UI em `src/qml/pages/IssueFormPage.qml`

4. Atualize `src/jira_service.py` para passar o campo na criação

### Comandos Úteis

```bash
# Desenvolvimento com Docker (ambiente unificado: Python + Qt6 + KF6)
make dev-build         # Construir imagem e exportar ferramentas Qt6/KF6
make dev-test          # Executar testes
make dev-shell         # Shell interativo
make dev-format        # Formatar código com black
make qml-lint          # Executar qmllint nos QML (configura variáveis automaticamente)

# Flatpak
make dev               # Build + Run (desenvolvimento)
make build             # Build completo
make clean-build       # Limpar build
```

## Troubleshooting

### "Configuração do Jira não encontrada"

- A aplicação abrirá automaticamente na aba de Configuração
- Preencha URL, Email e Token de API
- Clique em "Salvar"
- A aplicação recarregará automaticamente e estará pronta para usar

### "URL do servidor Jira não encontrada" ou "Email não encontrado na configuração"

- Verifique se os arquivos de configuração foram criados:
  - Flatpak: `~/.var/app/org.kde.jira-quick-task/config/jira-quick-task/`
  - Local: `~/.config/jira-quick-task/`
- Verifique se contém os campos `server`, `login` e `token` no `.jira-config.yml`
- Se necessário, reconfigure via interface gráfica

### "ModuleNotFoundError: No module named 'PySide6'"

- Se estiver usando Docker: Execute `make dev-build` para construir a imagem unificada com todas as dependências (Python + Qt6 + KF6)
- Se estiver usando Flatpak: O PySide6 vem do runtime `io.qt.PySide.BaseApp` - verifique se o Flatpak foi construído corretamente
- **Nota**: Não é necessário instalar PySide6, Qt6 ou KF6 no sistema host se você usar Docker ou Flatpak

### "module 'org.kde.kirigami' is not installed"

- No Flatpak: O Kirigami vem do runtime KDE Platform - verifique se o runtime está instalado: `flatpak list | grep org.kde.Platform`
- Se estiver desenvolvendo localmente (não recomendado): Instale `qml-module-org-kde-kirigami`, mas a estratégia recomendada é usar Docker para testes e Flatpak para executar

### Campos customizados não são preenchidos

- Verifique se os IDs dos campos em `config.json` correspondem aos IDs reais no Jira
- Use a API do Jira para descobrir os IDs: `GET /rest/api/3/field`

### Erro ao transicionar status

- Verifique se o nome do status em `config.json` corresponde exatamente ao nome no Jira (case-sensitive)
- Verifique se a sequência de status está correta
- Alguns status podem requerer campos customizados preenchidos antes da transição

### Worklog não é registrado

- Verifique se o checkbox "Registrar worklog" está marcado
- Verifique se a data/hora está no formato correto (YYYY-MM-DD HH:MM:SS)
- Verifique se a duração é maior que 0
- O worklog só é registrado após a transição para "IN DEVELOPMENT"

### Aplicação não abre na aba de configuração na primeira execução

- Verifique se os arquivos de configuração não existem:
  - Flatpak: `~/.var/app/org.kde.jira-quick-task/config/jira-quick-task/`
  - Local: `~/.config/jira-quick-task/`
- Se existirem mas estiverem incompletos, delete-os e reinicie a aplicação

## Certificados SSL/CA no Flatpak

A aplicação usa certificados CA do sistema host via bind mount (`--filesystem=host-etc:ro`). Esta abordagem:

- **Vantagens:**
  - Certificados sempre atualizados (não copiados para o sandbox)
  - Funciona com certificados corporativos (ex: Netskope) automaticamente
  - Compatível com diferentes distribuições Linux
  - Não requer rebuild quando certificados são atualizados

- **Trade-off:**
  - Expõe acesso de leitura a `/etc` do host (reduz isolamento do sandbox)
  - Para maior isolamento, seria necessário copiar certificados durante o build, mas isso deixaria os certificados desatualizados

## Atalho Global (Super+J)

O atalho global **Super+J** está disponível no Flatpak! O `python-xlib` foi incluído como dependência e deve funcionar normalmente.

**Nota:** O atalho global requer X11 (não funciona em Wayland puro). Se você estiver usando Wayland, o atalho não estará disponível, mas você pode:
- Usar o ícone na system tray para restaurar a janela
- Usar o atalho de teclado local (Ctrl+Return) quando a janela estiver em foco

## Licença

Este projeto é de uso pessoal.

## Referências

- [Jira REST API v3](https://developer.atlassian.com/cloud/jira/platform/rest/v3/) - Documentação oficial da API
- [Kirigami](https://develop.kde.org/frameworks/kirigami/) - Framework UI do KDE
- [PySide6](https://wiki.qt.io/Qt_for_Python) - Bindings Python para Qt 6
- [Flatpak](https://flatpak.org/) - Sistema de empacotamento de aplicações
