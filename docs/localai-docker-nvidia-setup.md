# LocalAI com NVIDIA CUDA via Docker — guia de instalação

Este documento descreve o que foi necessário para instalar o **LocalAI** com acesso a **NVIDIA CUDA** via Docker e os **modelos** usados pela funcionalidade **Criar tarefa por voz** do Jira Quick Task.

---

## 1. Pré-requisitos

- **Linux** (este guia foi escrito para Ubuntu/Debian; outros distros têm passos equivalentes).
- **Driver NVIDIA** instalado e funcionando. No terminal:
  ```bash
  nvidia-smi
  ```
  Se o comando listar a GPU, o driver está ok.
- **Docker** e **Docker Compose** instalados.
- **NVIDIA Container Toolkit** — permite que o Docker use a GPU nos containers (instalação abaixo).

---

## 2. Instalar o NVIDIA Container Toolkit

Sem o toolkit, ao subir o container com `deploy.resources.reservations.devices` (GPU), o Docker retorna:
`could not select device driver "nvidia" with capabilities: [[gpu]]`.

### Ubuntu / Debian

Siga o [guia oficial da NVIDIA](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html). Resumo:

```bash
# 1. Adicionar repositório
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# 2. Instalar
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# 3. Configurar o runtime no Docker
sudo nvidia-ctk runtime configure --runtime=docker

# 4. Reiniciar o Docker
sudo systemctl restart docker
```

### Outros distros

- **RHEL/CentOS/Fedora:** repositório RPM + `yum`/`dnf install nvidia-container-toolkit`.
- **Arch:** `pacman -S nvidia-container-toolkit`.

Consulte sempre o [Installation Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) para o seu sistema.

### Testar o toolkit

```bash
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

Se aparecer a saída do `nvidia-smi`, o Docker está conseguindo usar a GPU.

---

## 3. Subir o LocalAI com GPU (Docker Compose)

No diretório do repositório do projeto:

```bash
# Diretório para persistência de modelos (mapeado no compose)
mkdir -p .localai-models

# Subir o serviço (imagem GPU NVIDIA CUDA 12)
docker compose -f docker-compose.localai.yml up -d
```

O arquivo `docker-compose.localai.yml` usa:

- **Imagem:** `localai/localai:latest-gpu-nvidia-cuda-12`
- **Porta:** `8080:8080`
- **Volume:** `./.localai-models:/models` (modelos ficam em `.localai-models` no projeto)
- **GPU:** bloco `deploy.resources.reservations.devices` com driver `nvidia` e `capabilities: [gpu]`

### Verificar se o LocalAI está no ar

```bash
curl http://localhost:8080/v1/models
```

Resposta em JSON (mesmo que `{"data":[]}`) indica que o LocalAI está ativo. Para ver os logs do container:

```bash
docker compose -f docker-compose.localai.yml logs -f localai
```

---

## 4. Modelos necessários para “Criar tarefa por voz”

O app usa dois tipos de modelo no LocalAI:

| Uso            | Endpoint LocalAI                    | Nome configurado no app (exemplo) | Função                          |
|----------------|-------------------------------------|-----------------------------------|---------------------------------|
| Transcrição    | `POST /v1/audio/transcriptions`     | `whisper-1`                       | Áudio → texto (Whisper)         |
| Extração LLM   | `POST /v1/chat/completions`         | `qwen2.5:3b`                      | Texto → summary, description, tipo de atividade |

Os nomes (`localai_whisper_model` e `localai_llm_model`) no `config.json` ou nas Configurações do app devem coincidir com os **nomes dos modelos no LocalAI** (como aparecem em `GET /v1/models` ou na WebUI).

### Modelos baixados neste projeto

| Uso            | Arquivo                         | Fonte (Hugging Face) |
|----------------|---------------------------------|----------------------|
| Transcrição    | `ggml-medium.bin`               | [whisper.cpp / ggml-medium.bin](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin) |
| LLM (chat)     | `qwen2.5-3b-instruct-q4_k_m.gguf` | [Qwen2.5-3B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/blob/main/qwen2.5-3b-instruct-q4_k_m.gguf) |

- **Whisper:** [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp) — variante `ggml-medium.bin` para transcrição de áudio. No app use o nome que o LocalAI der a esse modelo (ex.: `whisper-1` ou o nome do ficheiro/YAML).
- **Qwen:** [Qwen/Qwen2.5-3B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF) — ficheiro `qwen2.5-3b-instruct-q4_k_m.gguf` (quantização Q4_K_M, ~2.1 GB). No app use o nome configurado no LocalAI (ex.: `qwen2.5:3b` ou o nome do modelo na API).

### Como instalar os modelos no LocalAI

O LocalAI expõe a **WebUI** em `http://localhost:8080` e a **API** `/v1/models`. Três formas comuns de instalar:

#### Opção A — WebUI (recomendado)

1. Abra **http://localhost:8080** no navegador.
2. Vá na aba **Models**.
3. Procure por **Whisper** (audio-to-text) e por **Qwen** (ou modelo de chat compatível).
4. Clique em **Install** nos modelos desejados e aguarde o download.
5. Anote os **nomes** exatos dos modelos (ex.: `whisper-1`, `qwen2.5:3b`) para usar no app.

#### Opção B — Galeria / CLI (se tiver o binário `local-ai`)

```bash
# Listar modelos disponíveis na galeria
local-ai models list

# Instalar Whisper e um LLM (nomes podem variar na galeria)
local-ai models install <nome-whisper>
local-ai models install <nome-qwen-ou-llm>
```

Consulte a [documentação de modelos do LocalAI](https://localai.io/getting-started/models/) e a [Model Gallery](https://models.localai.io) para os nomes exatos.

#### Opção C — Download manual (arquivos usados neste projeto)

Com o LocalAI no ar e o volume `./.localai-models` mapeado, baixe os ficheiros para dentro do volume (no host, no diretório do projeto):

```bash
mkdir -p .localai-models
cd .localai-models

# Whisper (transcrição) — ggml-medium.bin
wget -O ggml-medium.bin "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"

# Qwen 2.5 3B Instruct (LLM) — q4_k_m, ~2.1 GB
wget -O qwen2.5-3b-instruct-q4_k_m.gguf "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"
```

Em seguida, configure no LocalAI os nomes dos modelos (via YAML no mesmo diretório ou pela WebUI/API), de forma a que o app use os mesmos nomes em `localai_whisper_model` e `localai_llm_model`. Consulte a [documentação de modelos do LocalAI](https://localai.io/getting-started/models/) para YAMLs e backends (ex.: whisper.cpp para `ggml-medium.bin`, llama-cpp para o GGUF).

#### Opção D — Outros ficheiros no volume

O volume do compose é `./.localai-models:/models`. Você pode colocar outros arquivos de modelo (ex.: `.gguf`) e YAMLs de configuração em `.localai-models/`, seguindo o [Method 4: Manual Installation](https://localai.io/getting-started/models/) do LocalAI. Reinicie o container se necessário e verifique com `curl http://localhost:8080/v1/models`. O nome do modelo no app deve coincidir com o que o LocalAI expõe (YAML `name` ou nome reconhecido pela API).

### Conferir modelos instalados

```bash
curl http://localhost:8080/v1/models
```

Ou na WebUI em **http://localhost:8080** → aba **Models**. Use exatamente esses nomes em `localai_whisper_model` e `localai_llm_model` no app.

---

## 5. Configuração no app (Jira Quick Task)

No **config.json** (ex.: `~/.config/jira-quick-task/config.json`) ou em **Configurações → Entrada por voz**:

- **localai_base_url:** `http://localhost:8080`
- **localai_whisper_model:** nome do modelo Whisper no LocalAI (ex.: `whisper-1`)
- **localai_llm_model:** nome do modelo LLM no LocalAI (ex.: `qwen2.5:3b`)
- **localai_task_system_prompt:** (opcional) instrução de sistema para a extração de task; define o formato da description (estrutura em Markdown).
- **localai_comment_improvement_prompt:** (opcional) instrução para o botão **Melhorar com IA** em comentários (apenas expandir e estruturar o texto).
- **enabled:** `true`

Os pré-prompts podem ser alterados em **Configurações → Entrada por voz** para ajustar o formato da description da task e o comportamento na melhoria de comentários. Detalhes, Flatpak e diagnóstico estão em **[Configurar entrada por voz (LocalAI)](voice-input-setup.md)**.

---

## 6. Resumo do que foi preciso

| Passo | O que foi feito |
|-------|------------------|
| 1 | Driver NVIDIA instalado (`nvidia-smi` ok) |
| 2 | Docker e Docker Compose instalados |
| 3 | **NVIDIA Container Toolkit** instalado e configurado (`nvidia-ctk runtime configure --runtime=docker`); Docker reiniciado |
| 4 | `mkdir -p .localai-models` e `docker compose -f docker-compose.localai.yml up -d` |
| 5 | Verificação com `curl http://localhost:8080/v1/models` |
| 6 | Download/instalação dos modelos **Whisper** (transcrição) e **Qwen 2.5 3B** (LLM) via WebUI ou galeria/manual |
| 7 | Configuração no app: URL `http://localhost:8080`, nomes dos modelos e `voice_input.enabled: true` |

---

## Referências

- [NVIDIA Container Toolkit — Installation Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- [LocalAI — Docker Installation](https://localai.io/installation/docker/)
- [LocalAI — Setting Up Models](https://localai.io/getting-started/models/)
- [LocalAI — GPU Acceleration](https://localai.io/features/gpu-acceleration/)
- [Jira Quick Task — Configurar entrada por voz](voice-input-setup.md)
