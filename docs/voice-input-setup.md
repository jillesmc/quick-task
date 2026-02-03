# Configurar entrada por voz (LocalAI no host)

A funcionalidade **Criar tarefa por voz** grava áudio no app e envia para o **LocalAI** rodando no seu computador (localhost). O LocalAI faz a transcrição (Whisper) e o processamento do texto (LLM) para preencher Summary, Description e Tipo de atividade.

## Arquitetura

- **No Flatpak (app):** apenas gravação de áudio (sounddevice + PortAudio) e cliente HTTP para `http://localhost:8080`.
- **No host:** LocalAI com modelos Whisper (transcrição) e LLM (ex.: qwen2.5:3b).

O app **não** embute modelos de ML; tudo roda no LocalAI no host.

## 1. Instalar o LocalAI (host)

### Docker (recomendado)

Para instalação **com GPU NVIDIA CUDA** (driver, NVIDIA Container Toolkit, modelos Whisper e Qwen), use o guia **[LocalAI com NVIDIA CUDA via Docker](localai-docker-nvidia-setup.md)**.

Use o arquivo de composição incluído no repositório:

```bash
# Opcional: criar diretório para persistência de modelos
mkdir -p .localai-models

# Subir LocalAI (GPU NVIDIA CUDA 12)
docker compose -f docker-compose.localai.yml up -d
```

Para **CPU apenas**, edite `docker-compose.localai.yml`: use `image: localai/localai:latest` e remova o bloco `deploy` (recursos de GPU).

### Verificar

```bash
curl http://localhost:8080/v1/models
```

Se retornar JSON (lista de modelos ou vazia), o LocalAI está ativo.

## 2. Modelos no LocalAI

O app usa a API OpenAI-compatível do LocalAI:

- **Transcrição:** `POST /v1/audio/transcriptions` (modelo configurado em `localai_whisper_model`, ex.: `whisper-1`).
- **LLM:** `POST /v1/chat/completions` (modelo em `localai_llm_model`, ex.: `qwen2.5:3b`).

Baixe e configure os modelos conforme a [documentação do LocalAI](https://localai.io/getting-started/models/). Modelos sugeridos para ~6GB VRAM: Whisper (transcrição) + um LLM pequeno (ex.: qwen2.5:3b).

## 3. Configuração no app

No **config.json** (ou `~/.config/jira-quick-task/config.json`), bloco **voice_input**:

```json
"voice_input": {
  "enabled": true,
  "localai_base_url": "http://localhost:8080",
  "localai_whisper_model": "whisper-1",
  "localai_llm_model": "qwen2.5:3b",
  "localai_task_system_prompt": "Você extrai dados estruturados...",
  "localai_comment_improvement_prompt": "Você apenas melhora o texto...",
  "language": "pt",
  "max_recording_seconds": 120,
  "keyboard_shortcut": "Ctrl+Shift+V",
  "auto_process_after_stop": false,
  "microphone_device": "default"
}
```

- **localai_base_url:** URL do LocalAI (default: `http://localhost:8080`).
- **localai_whisper_model:** modelo de transcrição (ex.: `whisper-1`).
- **localai_llm_model:** modelo para extrair campos (ex.: `qwen2.5:3b`).
- **localai_task_system_prompt:** pré-prompt de sistema para extração de task (summary, description, tipo_atividade). Define como a **description** deve ser estruturada (ex.: Contexto, Passos, Critérios em Markdown).
- **localai_comment_improvement_prompt:** pré-prompt usado ao **melhorar comentários** com IA (apenas expandir e estruturar o texto, sem extração de campos).
- **enabled:** ativa a entrada por voz e o atalho.
- **language:** idioma da transcrição (ex.: `pt`).
- **max_recording_seconds**, **keyboard_shortcut**, **auto_process_after_stop**, **microphone_device:** como antes.

Na interface, em **Configurações → Entrada por voz**, você pode preencher URL base LocalAI, nomes dos modelos e os dois pré-prompts (campos multilinha). Os pré-prompts são lidos do config em cada pedido ao LocalAI, portanto alterações salvas passam a valer no próximo uso.

## 4. Flatpak: permissões

O manifest já inclui:

- **--share=network** – acesso a `localhost:8080`.
- **--socket=pulseaudio** – captura de áudio.

O módulo **python3-audio.json** (sounddevice, scipy, numpy) e **portaudio.json** fornecem apenas gravação; não há modelos de ML no Flatpak.

## 5. Quando a entrada por voz fica disponível

O bloco **Entrada por voz** (e o botão/atalho **Criar por voz**) só fica habilitado quando:

1. As dependências de **áudio** estão disponíveis (sounddevice, PortAudio no Flatpak).
2. O app consegue falar com o **LocalAI** em `localai_base_url` (ex.: `GET /v1/models` com sucesso).

Se o LocalAI não estiver rodando ou a URL estiver errada, a opção de voz permanece desabilitada. Inicie o LocalAI e, se precisar, ajuste `localai_base_url` nas configurações.

### Como identificar o que falta

1. **Rode o app com debug** (terminal): `jira-quick-task --debug` ou `flatpak run org.kde.jira-quick-task --debug`.
2. Abra **Configuração** e verifique se o bloco **Entrada por voz** aparece e se está habilitado/desabilitado.
3. **Veja o log de debug**: o `LocalAIClient` grava a URL usada e o erro quando a verificação falha.
   - Fora do Flatpak: `.cursor/debug.log` (na raiz do projeto) ou saída no terminal.
   - No Flatpak: `~/.config/jira-quick-task/debug.log` (ou variável `XDG_CONFIG_HOME`).
4. Exemplos de mensagem:
   - `GET http://localhost:8080/v1/models failed: Connection refused` → LocalAI não está rodando ou não está em 8080.
   - `GET http://localhost:8080/v1/models failed: ... timed out` → Firewall ou rede bloqueando.
   - **No Flatpak:** se `localhost` falhar mesmo com o LocalAI rodando no host, use o **IP da máquina** em vez de localhost (veja abaixo).

### Flatpak e localhost

Dentro do Flatpak, `127.0.0.1` / `localhost` pode referir-se ao loopback do sandbox, não ao host. Se o LocalAI está no host e o app é o Flatpak na mesma máquina:

1. Descubra o IP da sua máquina na LAN (ex.: `ip -4 addr` ou `hostname -I`), ex.: `192.168.1.10`.
2. Configure o LocalAI para escutar em todas as interfaces (ex.: bind em `0.0.0.0:8080` no Docker).
3. Nas configurações do app, em **URL base LocalAI**, use `http://192.168.1.10:8080` (ou o IP que você obteve).

## 6. Uso

1. Na aba **Criar Issue**, use o botão **Criar por voz** (microfone) ou o atalho (ex.: **Ctrl+Shift+V**).
2. **Gravar** para capturar áudio; **Parar** para enviar ao LocalAI e transcrever.
3. A transcrição aparece na caixa de texto; você pode editar antes de processar.
4. **Processar com IA** envia o texto ao LLM no LocalAI e preenche Summary, Description e Tipo de atividade.
5. Revise o formulário e clique em **Criar** para enviar ao Jira.

## Referências

- [LocalAI com NVIDIA CUDA via Docker](localai-docker-nvidia-setup.md) — guia de instalação com GPU e modelos (Whisper, Qwen)
- [LocalAI](https://localai.io/) – [Docker](https://localai.io/installation/docker/), [Audio-to-text](https://localai.io/features/audio-to-text/), [Text generation](https://localai.io/features/text-generation/), [GPU](https://localai.io/features/gpu-acceleration/)
- [SoundDevice](https://python-sounddevice.readthedocs.io/)
