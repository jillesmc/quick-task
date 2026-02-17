# LocalAI com NVIDIA CUDA via Docker

Guia para instalar o **LocalAI** com GPU NVIDIA via Docker e os **modelos** usados pela funcionalidade **Criar tarefa por voz** do Jira Quick Task.

## Quick start

1. **NVIDIA Container Toolkit** — instale e configure (seção 2).
2. **Subir LocalAI** — `mkdir -p .localai-models` e `docker compose -f docker-compose.localai.yml up -d`.
3. **Modelos** — instale Whisper (transcrição) e Qwen (LLM) via WebUI em http://localhost:8080 ou download manual (seção 4).

## 1. Pré-requisitos

- **Linux** (Ubuntu/Debian; outros distros têm passos equivalentes).
- **Driver NVIDIA** instalado (`nvidia-smi` deve listar a GPU).
- **Docker** e **Docker Compose** instalados.
- **NVIDIA Container Toolkit** (instalação abaixo).

## 2. Instalar o NVIDIA Container Toolkit

Sem o toolkit, o Docker retorna: `could not select device driver "nvidia" with capabilities: [[gpu]]`.

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

Consulte o [Installation Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html).

### Testar o toolkit

```bash
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

## 3. Subir o LocalAI com GPU

No diretório do repositório:

```bash
mkdir -p .localai-models
docker compose -f docker-compose.localai.yml up -d
```

O `docker-compose.localai.yml` usa:
- **Imagem:** `localai/localai:latest-gpu-nvidia-cuda-12`
- **Porta:** `8080:8080`
- **Volume:** `./.localai-models:/models`
- **GPU:** `deploy.resources.reservations.devices` com driver `nvidia`

### Verificar

```bash
curl http://localhost:8080/v1/models
```

Resposta em JSON indica que o LocalAI está ativo. Logs: `docker compose -f docker-compose.localai.yml logs -f localai`.

## 4. Modelos necessários

| Uso | Endpoint | Nome no app (exemplo) | Função |
|-----|----------|------------------------|--------|
| Transcrição | `POST /v1/audio/transcriptions` | `whisper-1` | Áudio → texto |
| Extração LLM | `POST /v1/chat/completions` | `qwen2.5:3b` | Texto → summary, description, tipo |

Os nomes em `config.json` devem coincidir com os nomes no LocalAI (`GET /v1/models` ou WebUI).

### Arquivos usados neste projeto

| Uso | Arquivo | Fonte (Hugging Face) |
|-----|---------|----------------------|
| Transcrição | `ggml-medium.bin` | [whisper.cpp / ggml-medium.bin](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin) |
| LLM | `qwen2.5-3b-instruct-q4_k_m.gguf` | [Qwen2.5-3B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/blob/main/qwen2.5-3b-instruct-q4_k_m.gguf) |

No app use o nome que o LocalAI der ao modelo (ex.: `whisper-1`, `qwen2.5:3b`).

### Como instalar os modelos

#### Opção A — WebUI (recomendado)

1. Abra http://localhost:8080 no navegador.
2. Aba **Models** → procure Whisper e Qwen.
3. Clique em **Install** e anote os nomes exatos.

#### Opção B — Galeria / CLI

```bash
local-ai models list
local-ai models install <nome-whisper>
local-ai models install <nome-llm>
```

#### Opção C — Download manual

```bash
mkdir -p .localai-models
cd .localai-models

wget -O ggml-medium.bin "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
wget -O qwen2.5-3b-instruct-q4_k_m.gguf "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"
```

Configure os nomes no LocalAI (YAML ou WebUI). Consulte a [documentação de modelos](https://localai.io/getting-started/models/).

#### Opção D — Outros arquivos

O volume é `./.localai-models:/models`. Coloque outros arquivos de modelo e YAMLs em `.localai-models/` conforme a documentação do LocalAI.

### Conferir modelos instalados

```bash
curl http://localhost:8080/v1/models
```

## 5. Configuração no app

Configure URL e nomes dos modelos em **Configurações → Entrada por voz** ou no `config.json`. Detalhes completos, Flatpak e diagnóstico: **[Configurar entrada por voz (LocalAI)](voice-input-setup.md)**.

## 6. Resumo

| Passo | O que foi feito |
|-------|------------------|
| 1 | Driver NVIDIA instalado (`nvidia-smi` ok) |
| 2 | Docker e Docker Compose instalados |
| 3 | NVIDIA Container Toolkit instalado e configurado; Docker reiniciado |
| 4 | `mkdir -p .localai-models` e `docker compose -f docker-compose.localai.yml up -d` |
| 5 | Verificação com `curl http://localhost:8080/v1/models` |
| 6 | Download/instalação dos modelos Whisper e Qwen 2.5 3B |
| 7 | Configuração no app: URL, nomes dos modelos e `voice_input.enabled: true` |

## Referências

- [NVIDIA Container Toolkit — Installation Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- [LocalAI — Docker](https://localai.io/installation/docker/), [Models](https://localai.io/getting-started/models/), [GPU](https://localai.io/features/gpu-acceleration/)
- [Configurar entrada por voz](voice-input-setup.md)
