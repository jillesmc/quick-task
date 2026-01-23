# Jira Quick Task

Aplicação desktop moderna para criar issues no Jira com interface gráfica usando Kirigami (KDE). Permite criar issues, configurar campos customizados, transicionar status sequencialmente e registrar worklogs automaticamente.

## Características

- Interface gráfica moderna com Kirigami 6 (KDE)
- Criação de issues com campos customizados
- Transição sequencial de status
- Registro automático de worklog após transição para "IN DEVELOPMENT"
- Configuração flexível via arquivo JSON
- Integração direta com **Jira REST API v3** para todas as operações

## Pré-requisitos

### Python 3.11 ou superior

O projeto requer Python 3.11 ou superior. Verifique se está instalado:

```bash
python3 --version
```

### Dependências do Sistema (Ubuntu/Debian)

Os pacotes PySide6 e Kirigami devem ser instalados do sistema:

```bash
sudo apt update
sudo apt install \
    python3-pyside6.qtcore python3-pyside6.qtgui python3-pyside6.qtqml \
    python3-pyside6.qtwidgets \
    qml-module-org-kde-kirigami \
    python3-xlib
```

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

### 2. Instalar dependências do sistema

Instale as dependências do sistema necessárias:

```bash
sudo apt install python3-pyside6.qtcore python3-pyside6.qtgui python3-pyside6.qtqml python3-pyside6.qtwidgets qml-module-org-kde-kirigami python3-xlib
```

### 3. Instalar dependências Python

Instale as dependências Python definidas em `requirements.txt`:

```bash
pip3 install -r requirements.txt
```

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

O projeto inclui um template de configuração em `config/.jira-config.yml.example`. 

Para criar o arquivo de configuração:

```bash
# Copiar o template
cp config/.jira-config.yml.example config/.jira-config.yml

# Editar e preencher os campos necessários
nano config/.jira-config.yml
```

Preencha os seguintes campos:
- `login`: Seu e-mail do Jira
- `server`: URL do seu servidor Jira (ex: `https://seu-projeto.atlassian.net`)

**Nota sobre o Token:**

O token `JIRA_API_TOKEN` é necessário para todas as operações via REST API (criação de issues, atualizações, transições, worklogs, etc.).

### 5. Configurar campos customizados

O arquivo `config/.jira-config.yml` já contém os IDs dos campos customizados. Se você precisar descobrir os IDs dos campos em outra instância Jira, use a API do Jira ou verifique no próprio Jira.

## Instalação via Flatpak

A aplicação pode ser empacotada e distribuída como Flatpak. Para construir e instalar:

```bash
# Instalar dependências do Flatpak (primeira vez)
make flatpak-install-deps

# Construir e instalar
make flatpak-build

# Executar
flatpak run org.kde.jira-quick-task
```

### Configuração no Flatpak

Após instalar o Flatpak, você precisa configurar os arquivos de configuração:

**Opção 1: Usar o script helper (recomendado)**

```bash
# As variáveis de ambiente do host são passadas automaticamente
flatpak run --command=jira-quick-task-config-setup org.kde.jira-quick-task
```

Este script:
- Pede seu email do Jira interativamente
- Cria os arquivos de configuração em `~/.config/jira-quick-task/` a partir dos templates
- Configura o email automaticamente no `.jira-config.yml`
- Se `JIRA_API_TOKEN` estiver configurado, busca o `accountId` automaticamente via API

**Opção 2: Configuração manual**

1. Criar diretório de configuração:
   ```bash
   mkdir -p ~/.config/jira-quick-task
   ```

2. Copiar templates:
   ```bash
   # Os templates estão em /app/share/jira-quick-task/config/ dentro do Flatpak
   # Você pode copiar manualmente ou usar o script helper acima
   ```

3. Editar `~/.config/jira-quick-task/config.json` com as configurações do seu projeto

4. Editar `~/.config/jira-quick-task/.jira-config.yml` com suas credenciais:
   - `server`: URL do seu servidor Jira
   - `login`: Seu email do Jira
   - `token`: Seu token de API (obtenha em https://id.atlassian.com/manage-profile/security/api-tokens)

5. Configurar variável de ambiente `JIRA_API_TOKEN`:
   ```bash
   export JIRA_API_TOKEN=<seu-token>
   # Adicione ao ~/.bashrc ou ~/.zshrc para tornar permanente
   ```

### Certificados SSL/CA no Flatpak

A aplicação usa certificados CA do sistema host via bind mount (`--filesystem=host-etc:ro`). Esta abordagem:

- **Vantagens:**
  - Certificados sempre atualizados (não copiados para o sandbox)
  - Funciona com certificados corporativos (ex: Netskope) automaticamente
  - Compatível com diferentes distribuições Linux
  - Não requer rebuild quando certificados são atualizados
  - **Sem hardcoding**: Variáveis de ambiente são herdadas automaticamente do host

- **Como funciona:**
  - O Flatpak herda automaticamente variáveis de ambiente do host (incluindo `SSL_CERT_FILE`, `SSL_CERT_DIR`, etc.)
  - Certificados do host ficam acessíveis em `/run/host/etc/ssl/certs/` dentro do sandbox
  - O wrapper script (`flatpak-wrapper.sh`) apenas ajusta os caminhos herdados:
    - Se o host tem `SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`, o wrapper ajusta para `/run/host/etc/ssl/certs/ca-certificates.crt`
    - Não cria variáveis se não existirem - deixa o Flatpak/herança fazer isso
  - O `requests` Python detecta automaticamente essas variáveis

- **Configuração no host (opcional):**
  ```bash
  # ~/.bashrc ou ~/.zshenv (opcional - funciona sem isso também)
  export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
  export SSL_CERT_DIR=/etc/ssl/certs
  ```

- **Trade-off:**
  - Expõe acesso de leitura a `/etc` do host (reduz isolamento do sandbox)
  - Para maior isolamento, seria necessário copiar certificados durante o build, mas isso deixaria os certificados desatualizados

### Atalho Global (Super+J) no Flatpak

O atalho global **Super+J** está disponível no Flatpak! O `python-xlib` foi incluído como dependência e deve funcionar normalmente.

**Nota:** O atalho global requer X11 (não funciona em Wayland puro). Se você estiver usando Wayland, o atalho não estará disponível, mas você pode:
- Use o ícone na system tray para restaurar a janela
- Use o atalho de teclado local (Ctrl+Return) quando a janela estiver em foco

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

### Via Flatpak (Recomendado)

Após construir e instalar o Flatpak:

```bash
# Executar aplicação
flatpak run org.kde.jira-quick-task

# Ou usar o target do Makefile
make flatpak-test
```

A aplicação também estará disponível no menu de aplicações do seu desktop environment.

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
│   ├── app.py               # Aplicação principal PySide6
│   ├── jira_service.py      # Serviço Jira (QObject)
│   ├── models/
│   │   └── issue_model.py   # Modelo de dados (QObject)
│   └── qml/
│       ├── Main.qml         # Janela principal
│       ├── IssueFormPage.qml # Formulário de criação
│       ├── ProgressDialog.qml
│       ├── SuccessDialog.qml
│       └── ErrorDialog.qml
├── scripts/                 # Scripts utilitários
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

### "ModuleNotFoundError: No module named 'PySide6'"

- Instale os pacotes do sistema: `sudo apt install python3-pyside6.qtcore python3-pyside6.qtgui python3-pyside6.qtqml python3-pyside6.qtwidgets`
- Certifique-se de que os pacotes estão instalados: `dpkg -l | grep pyside6`

### "module 'org.kde.kirigami' is not installed"

- Instale o módulo Kirigami: `sudo apt install qml-module-org-kde-kirigami`
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
- [PySide6](https://wiki.qt.io/Qt_for_Python) - Bindings Python para Qt 6
