# Jira Quick Task

Aplicação desktop moderna para criar issues no Jira com interface gráfica usando Kirigami (KDE). Permite criar issues, configurar campos customizados, transicionar status sequencialmente e registrar worklogs automaticamente.

## Características

- Interface gráfica moderna com Kirigami 2 (KDE)
- Criação de issues com campos customizados
- Transição sequencial de status
- Registro automático de worklog após transição para "IN DEVELOPMENT"
- Configuração flexível via arquivo JSON
- Integração direta com **Jira REST API v3** para todas as operações

## Pré-requisitos

### mise (Obrigatório)

O projeto usa `mise` (anteriormente `rtx`) para gerenciar a versão do Python. O arquivo `.mise.toml` define Python 3.12.3 como versão requerida.

**Instalação do mise:**

```bash
curl https://mise.run | sh
```

Após instalar, reinicie o terminal ou execute:

```bash
source ~/.bashrc  # ou ~/.zshrc
```

**Mais informações:** [mise.jdx.dev](https://mise.jdx.dev)

### Dependências do Sistema (Ubuntu/Debian)

Os pacotes PySide2 e Kirigami devem ser instalados do sistema para serem usados pelo Python gerenciado via `mise`:

```bash
sudo apt update
sudo apt install \
    python3-pyside2.qtcore python3-pyside2.qtgui python3-pyside2.qtqml \
    python3-pyside2.qtwidgets \
    qml-module-org-kde-kirigami2 \
    python3-xlib
```

> **Nota:** Não é necessário instalar Python do sistema, pois o `mise` gerencia a versão do Python automaticamente.

### Token de API do Jira

A aplicação usa **Jira REST API v3** diretamente, sem necessidade de ferramentas externas. Você só precisa de um token de API do Jira.

**Obter Token de API:**

1. Acesse: https://id.atlassian.com/manage-profile/security/api-tokens
2. Clique em "Create API token"
3. Dê um nome ao token (ex: "Jira Quick Task")
4. Copie o token gerado

**Configurar Token:**

```bash
# Configure o token como variável de ambiente
export JIRA_API_TOKEN=<seu-token>
```

Para tornar o token permanente, adicione ao seu `~/.bashrc` ou `~/.zshrc`:

```bash
echo 'export JIRA_API_TOKEN=<seu-token>' >> ~/.bashrc  # ou ~/.zshrc
source ~/.bashrc  # ou source ~/.zshrc
```

**Mais informações:**
- [Como criar token de API](https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/)
- [Jira REST API v3](https://developer.atlassian.com/cloud/jira/platform/rest/v3/)

## Instalação

### 1. Clonar o repositório

```bash
git clone <url-do-repositorio>
cd jira-quick-task
```

### 2. Instalar ferramentas do mise

Instale as ferramentas definidas no `.mise.toml`:

```bash
mise install
```

Isso instalará automaticamente Python 3.12.3 conforme definido no `.mise.toml`.

### 3. Executar setup (Recomendado)

O script `setup.sh` verifica e instala as dependências do sistema:

```bash
./setup.sh
```

O script irá:
- Verificar e instalar dependências do sistema (PySide2, Kirigami, etc.)
- Criar arquivo de configuração `.jira-config.yml` a partir do template
- Instalar ícones e arquivo `.desktop`

### 4. Configurar Autenticação

**Token de API (Obrigatório):**

Configure o token de API do Jira:

```bash
# Configure o token como variável de ambiente
export JIRA_API_TOKEN=<seu-token>
```

Para tornar o token permanente, adicione ao seu `~/.bashrc` ou `~/.zshrc`:

```bash
echo 'export JIRA_API_TOKEN=<seu-token>' >> ~/.bashrc  # ou ~/.zshrc
source ~/.bashrc  # ou source ~/.zshrc
```

**Configuração do arquivo .jira-config.yml:**

O projeto inclui um template de configuração em `config/.jira-config.yml.example`. O script `setup.sh` cria automaticamente o arquivo `config/.jira-config.yml` e pede seu e-mail.

Se precisar criar manualmente:

```bash
# Copiar o template
cp config/.jira-config.yml.example config/.jira-config.yml

# Editar e preencher o campo 'login' com seu e-mail
nano config/.jira-config.yml
```

**Nota sobre o Token:**

O token `JIRA_API_TOKEN` é necessário para todas as operações via REST API (criação de issues, atualizações, transições, worklogs, etc.).

### 5. Instalar dependências Python

Instale as dependências Python definidas em `requirements.txt`:

```bash
mise run -- pip install -r requirements.txt
```

### 6. Configurar campos customizados

O arquivo `config/.jira-config.yml` já contém os IDs dos campos customizados. Se você precisar descobrir os IDs dos campos em outra instância Jira, use a API do Jira ou verifique no próprio Jira.

## Configuração

### Arquivo config.json

Edite `config/config.json` para configurar:

- `project`: Nome do projeto Jira
- `issue_type`: Tipo de issue (ex: "Task")
- `assignee`: Email do assignee padrão ou `"auto"` para inferir do usuário atual
- `jira_cli_config`: (Opcional) Caminho para o arquivo de configuração. Se não especificado, usa `config/.jira-config.yml`
- `custom_fields`: IDs dos campos customizados (não mais aliases, agora usamos IDs diretos)
- `tipo_atividade_values`: Valores possíveis para o campo "Tipo de atividade"
- `status_sequence`: Sequência de status para transições
- `worklog_timezone`: Timezone para registro de worklog (formato IANA, ex: "America/Sao_Paulo")

### Arquivo config/.jira-config.yml

Este arquivo contém a configuração do servidor Jira, projeto, e campos customizados. O arquivo `config/.jira-config.yml.example` no repositório é um template sem credenciais.

**Importante:** O arquivo `config/.jira-config.yml` está no `.gitignore` e não será versionado (contém credenciais). Após clonar o repositório, você precisa:

1. Copiar o template:
   ```bash
   cp config/.jira-config.yml.example config/.jira-config.yml
   ```

2. Configurar o login (email):
   Edite o arquivo diretamente e preencha o campo `login` com seu e-mail.

3. **Configurar token de API:**
   ```bash
   export JIRA_API_TOKEN=<seu-token>
   ```
   
   O token é necessário para todas as operações via REST API.

Exemplo de `config.json`:

```json
{
  "project": "PLATFORM",
  "issue_type": "Task",
  "assignee": "seu.email@exemplo.com",
  "custom_fields": {
    "tipo_atividade": "customfield_12088",
    "documentacao_anexa": "customfield_14840",
    "utilizacao_ia": "customfield_14841"
  },
  "tipo_atividade_values": [
    "Novas iniciativas/Novas funcionalidades/Melhorias funcionais",
    "Melhorias Técnicas/Atualizações Técnicas/Plataforma/Segurança",
    "Suporte Dúvidas/Suporte uso incorreto",
    "Bugs/Incidentes/Retrabalho Técnico",
    "Mudança de escopo"
  ],
  "status_sequence": [
    "TO DO",
    "WAITING DEVELOPMENT",
    "IN DEVELOPMENT",
    "CODE REVIEW",
    "WAITING FOR HOMOLOG",
    "IN HOMOLOGATION",
    "READY FOR DEPLOY",
    "DONE"
  ],
  "worklog_timezone": "America/Sao_Paulo"
}
```

## Execução

### Via script bash (Recomendado)

```bash
./jira-quick-task.sh
```

O script usa automaticamente o `mise` para garantir a versão correta do Python definida no `.mise.toml`.

### Via Python direto

```bash
mise run -- python -m src
```

### Via desktop file

Instale o arquivo `.desktop` no sistema:

```bash
# Copiar para aplicações do usuário
cp org.kde.jira-quick-task.desktop ~/.local/share/applications/

# Ou para aplicações do sistema (requer sudo)
sudo cp org.kde.jira-quick-task.desktop /usr/share/applications/

# Atualizar cache
update-desktop-database ~/.local/share/applications/
```

Depois, você pode executar a aplicação pelo menu de aplicações do KDE.

## Uso

1. **Summary**: Preencha o resumo da issue (obrigatório)
2. **Description**: Descrição da issue (opcional)
3. **Tipo de atividade**: Selecione o tipo de atividade
4. **Status inicial**: Selecione o status inicial (padrão: "TO DO")
5. **Documentação anexa**: Selecione "Sim" ou "Não"
6. **Utilização de IA**: Selecione "Sim" ou "Não"
7. **Worklog** (opcional):
   - Marque "Registrar worklog" se desejar registrar tempo
   - Informe data/hora de início (formato: YYYY-MM-DD HH:MM:SS)
   - Ajuste a duração (30 minutos a 9 horas, em incrementos de 30 minutos)
   - O worklog será registrado automaticamente após a transição para "IN DEVELOPMENT"

8. Clique em **"Criar"** para criar a issue

A aplicação mostrará uma barra de progresso durante a criação e transições de status.

## Estrutura do Projeto

```
jira-quick-task/
├── config/
│   ├── config.json          # Configuração do projeto
│   ├── .jira-config.yml.example  # Template de configuração Jira
│   └── config_manager.py    # Gerenciador de configuração
├── core/
│   ├── jira_client.py       # Cliente para Jira REST API v3
│   └── status_transition.py # Lógica de transição de status
├── src/
│   ├── app.py               # Aplicação principal PySide2
│   ├── jira_service.py      # Serviço Jira (QObject)
│   ├── models/
│   │   └── issue_model.py   # Modelo de dados (QObject)
│   └── qml/
│       ├── Main.qml         # Janela principal
│       ├── IssueFormPage.qml # Formulário de criação
│       ├── ProgressDialog.qml
│       ├── SuccessDialog.qml
│       └── ErrorDialog.qml
├── jira-quick-task.sh       # Script de execução
├── org.kde.jira-quick-task.desktop
└── requirements.txt
```

## Desenvolvimento

### Adicionar novos campos

1. Adicione o campo em `config/config.json`:
   ```json
   "custom_fields": {
     "novo_campo": "customfield_XXXXX"
   }
   ```

2. Adicione o campo em `config/.jira-config.yml` na seção `issue.fields.custom`

3. Adicione propriedade em `src/models/issue_model.py`:
   ```python
   novoCampoChanged = Signal(str)
   
   @Property(str, notify=novoCampoChanged)
   def novoCampo(self):
       return self._novoCampo
   ```

4. Adicione UI em `src/qml/IssueFormPage.qml`

5. Atualize `src/jira_service.py` para passar o campo na criação

## Troubleshooting

### "JIRA_API_TOKEN não encontrado"

- Configure o token: `export JIRA_API_TOKEN=<seu-token>`
- Verifique se está configurado: `echo $JIRA_API_TOKEN`
- Para tornar permanente, adicione ao `~/.bashrc` ou `~/.zshrc`

### "URL do servidor Jira não encontrada" ou "Email não encontrado na configuração"

- Verifique se o arquivo `config/.jira-config.yml` existe
- Verifique se contém os campos `server` e `login`
- Copie o template se necessário: `cp config/.jira-config.yml.example config/.jira-config.yml`

### "ModuleNotFoundError: No module named 'PySide2'"

- Instale os pacotes do sistema: `sudo apt install python3-pyside2.qtcore python3-pyside2.qtgui python3-pyside2.qtqml python3-pyside2.qtwidgets`
- Certifique-se de que os pacotes estão instalados: `dpkg -l | grep pyside2`

### "module 'org.kde.kirigami' is not installed"

- Instale o módulo Kirigami: `sudo apt install qml-module-org-kde-kirigami2`
- Verifique se o caminho do Qt 5 está correto em `src/app.py`

### "Qt: Session management error"

Este warning é normal e foi suprimido na aplicação. Se ainda aparecer, é apenas informativo e não afeta o funcionamento.

### Campos customizados não são preenchidos

- Verifique se os IDs dos campos em `config.json` correspondem aos IDs reais no Jira
- Verifique se os campos estão configurados em `config/.jira-config.yml`
- Verifique se o token de API tem permissões para editar os campos customizados

### Erro ao transicionar status

- Verifique se o nome do status em `config.json` corresponde exatamente ao nome no Jira (case-sensitive)
- Verifique se a sequência de status está correta
- Alguns status podem requerer campos customizados preenchidos antes da transição
- Verifique se há trace ID no erro e reporte se necessário

### Worklog não é registrado

- Verifique se o checkbox "Registrar worklog" está marcado
- Verifique se a data/hora está no formato correto (YYYY-MM-DD HH:MM:SS)
- Verifique se a duração é maior que 0
- Verifique se `JIRA_API_TOKEN` está configurado
- O worklog só é registrado após a transição para "IN DEVELOPMENT"

### Erros com trace ID

Se você receber um erro com "trace id: XXXXXXXX", copie e salve o trace ID. Ele pode ser solicitado pelo suporte da Atlassian ao reportar problemas.

## Licença

Este projeto é de uso pessoal.

## Referências

- [Jira REST API v3](https://developer.atlassian.com/cloud/jira/platform/rest/v3/) - Documentação oficial da API
- [Kirigami](https://develop.kde.org/frameworks/kirigami/) - Framework UI do KDE
- [PySide2](https://wiki.qt.io/Qt_for_Python) - Bindings Python para Qt 5
