"""
Cliente HTTP para LocalAI no host: transcrição (Whisper) e processamento de tarefa (LLM).
API compatível OpenAI: /v1/models, /v1/audio/transcriptions, /v1/chat/completions.
"""

import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

from PySide6.QtCore import QObject, Signal, QThread, Slot  # type: ignore[import]

from src.constants import SUMMARY_MAX_LENGTH

try:
    import requests

    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

DEFAULT_BASE_URL = "http://localhost:8080"
LOCALAI_TIMEOUT_MODELS = 2
LOCALAI_TIMEOUT_GENERATE = 60
LOCALAI_TIMEOUT_TRANSCRIBE = 120
LOCALAI_TIMEOUT_IMPROVE_COMMENT = 60

DEFAULT_TASK_SYSTEM_PROMPT = (
    "Você extrai dados estruturados de texto para tarefas Jira. "
    "A description da task deve seguir uma estrutura simples em Markdown: "
    "Contexto (breve), Passos ou Critérios de aceite (lista), quando fizer sentido. Seja conciso."
)
DEFAULT_COMMENT_IMPROVEMENT_PROMPT = (
    "Você apenas melhora o texto do utilizador: expanda ligeiramente as ideias e "
    "estruture em parágrafos ou listas quando apropriado. Mantenha o tom e não invente informações. "
    "Responda somente com o texto melhorado, sem explicações nem metatexto."
)


class _TranscribeWorker(QThread):
    """Thread para transcrição assíncrona via LocalAI Whisper."""

    finished = Signal(str)
    error_occurred = Signal(str)

    def __init__(
        self,
        client: "LocalAIClient",
        audio_path: str,
        parent=None,
    ):
        super().__init__(parent)
        self._client = client
        self._audio_path = audio_path

    def run(self) -> None:
        try:
            text = self._client.transcribe_audio_sync(self._audio_path)
            self.finished.emit(text or "")
        except Exception as e:
            self.error_occurred.emit(str(e))


class _ImproveCommentWorker(QThread):
    """Thread para melhoria de texto de comentário via LocalAI."""

    finished = Signal(str)
    error_occurred = Signal(str)

    def __init__(
        self,
        client: "LocalAIClient",
        text: str,
        comment_improvement_prompt: Optional[str],
        parent=None,
    ):
        super().__init__(parent)
        self._client = client
        self._text = text
        self._prompt = comment_improvement_prompt

    def run(self) -> None:
        try:
            result = self._client._improve_comment_text_sync(self._text, self._prompt)
            self.finished.emit(result or "")
        except Exception as e:
            self.error_occurred.emit(str(e))


class _ProcessTaskWorker(QThread):
    """Thread para processamento de tarefa a partir de transcrição (Expandir com IA)."""

    finished = Signal(object)  # Dict[str, Any]
    error_occurred = Signal(str)

    def __init__(
        self,
        client: "LocalAIClient",
        transcription: str,
        tipo_atividade_values: List[str],
        task_system_prompt: Optional[str],
        parent=None,
    ):
        super().__init__(parent)
        self._client = client
        self._transcription = transcription
        self._tipo_atividade_values = tipo_atividade_values
        self._task_system_prompt = task_system_prompt

    def run(self) -> None:
        try:
            result = self._client._process_task_sync(
                self._transcription,
                self._tipo_atividade_values,
                self._task_system_prompt,
            )
            self.finished.emit(result)
        except Exception as e:
            self.error_occurred.emit(str(e))


class LocalAIClient(QObject):
    """
    Cliente para LocalAI no host: check_connection, transcribe (Whisper), process_task (LLM).
    API OpenAI-compatível: GET /v1/models, POST /v1/audio/transcriptions, POST /v1/chat/completions.
    """

    transcriptionComplete = Signal(str)
    processingComplete = Signal(dict)
    commentTextImproved = Signal(str)
    error = Signal(str)

    def __init__(
        self,
        base_url: str = DEFAULT_BASE_URL,
        whisper_model: str = "whisper-1",
        llm_model: str = "qwen2.5:3b",
        parent=None,
    ):
        super().__init__(parent)
        self._base_url = (base_url or DEFAULT_BASE_URL).rstrip("/")
        self._whisper_model = whisper_model or "whisper-1"
        self._llm_model = llm_model or "qwen2.5:3b"
        self._worker: Optional[_TranscribeWorker] = None
        self._improve_worker: Optional["_ImproveCommentWorker"] = None
        self._process_task_worker: Optional[_ProcessTaskWorker] = None

    def _get_models_url(self) -> str:
        return f"{self._base_url}/v1/models"

    def _get_transcriptions_url(self) -> str:
        return f"{self._base_url}/v1/audio/transcriptions"

    def _get_chat_completions_url(self) -> str:
        return f"{self._base_url}/v1/chat/completions"

    @Slot(result=bool)
    def check_connection(self) -> bool:
        """Verifica se LocalAI está acessível (GET /v1/models)."""
        if not REQUESTS_AVAILABLE:
            return False
        url = self._get_models_url()
        try:
            r = requests.get(url, timeout=LOCALAI_TIMEOUT_MODELS)
            if r.status_code == 200:
                return True
            try:
                from src.utils.debug import debug_log, is_debug_enabled

                if is_debug_enabled():
                    debug_log(
                        "LocalAIClient",
                        "check_connection",
                        "GET %s -> HTTP %s",
                        url,
                        r.status_code,
                    )
            except Exception:
                pass
            return False
        except Exception as e:
            try:
                from src.utils.debug import debug_log, is_debug_enabled

                if is_debug_enabled():
                    debug_log(
                        "LocalAIClient",
                        "check_connection",
                        "GET %s failed: %s (If running as Flatpak, use host IP instead of localhost, e.g. http://192.168.x.x:8080)",
                        url,
                        e,
                    )
            except Exception:
                pass
            return False

    def transcribe_audio_sync(self, audio_path: str) -> str:
        """
        Transcreve áudio via LocalAI Whisper (OpenAI-compatible).
        POST /v1/audio/transcriptions com multipart: file, model, language, response_format.
        """
        if not REQUESTS_AVAILABLE:
            raise RuntimeError("requests não disponível")
        path = Path(audio_path)
        if not path.exists():
            raise FileNotFoundError(f"Arquivo de áudio não encontrado: {audio_path}")

        with open(path, "rb") as f:
            files = {"file": (path.name or "audio.wav", f, "audio/wav")}
            data = {
                "model": self._whisper_model,
                "language": "pt",
                "response_format": "json",
            }
            r = requests.post(
                self._get_transcriptions_url(),
                files=files,
                data=data,
                timeout=LOCALAI_TIMEOUT_TRANSCRIBE,
            )

        if r.status_code != 200:
            raise RuntimeError(f"Transcrição falhou: HTTP {r.status_code}")
        resp = r.json()
        text = (resp.get("text") or "").strip()
        return text

    @Slot(str)
    def transcribe_audio(self, audio_path: str) -> None:
        """
        Inicia transcrição em thread. Emite transcriptionComplete(str) ou error(str).
        """
        if self._worker is not None and self._worker.isRunning():
            self.error.emit("Transcrição já em andamento")
            return
        self._worker = _TranscribeWorker(self, audio_path, parent=self)
        self._worker.finished.connect(self._on_transcribe_finished)
        self._worker.error_occurred.connect(self._on_transcribe_error)
        self._worker.finished.connect(lambda: setattr(self, "_worker", None))
        self._worker.error_occurred.connect(lambda: setattr(self, "_worker", None))
        self._worker.start()

    def _on_transcribe_finished(self, text: str) -> None:
        self.transcriptionComplete.emit(text or "")

    def _on_transcribe_error(self, msg: str) -> None:
        self.error.emit(msg)

    def _improve_comment_text_sync(
        self,
        text: str,
        comment_improvement_prompt: Optional[str] = None,
    ) -> str:
        """Melhora texto de comentário via LocalAI; retorna texto original em falha."""
        text = (text or "").strip()
        if not text:
            return ""
        if not REQUESTS_AVAILABLE:
            return text
        prompt = (
            comment_improvement_prompt or ""
        ).strip() or DEFAULT_COMMENT_IMPROVEMENT_PROMPT
        try:
            r = requests.post(
                self._get_chat_completions_url(),
                json={
                    "model": self._llm_model,
                    "messages": [
                        {"role": "system", "content": prompt},
                        {"role": "user", "content": text},
                    ],
                    "temperature": 0.3,
                },
                timeout=LOCALAI_TIMEOUT_IMPROVE_COMMENT,
            )
            if r.status_code != 200:
                return text
            data = r.json()
            raw = ""
            try:
                raw = (
                    data.get("choices", [{}])[0].get("message", {}).get("content") or ""
                ).strip()
            except (IndexError, KeyError, TypeError):
                pass
            return raw if raw else text
        except Exception:
            return text

    @Slot(str)
    def improve_comment_text(
        self, text: str, comment_improvement_prompt: Optional[str] = None
    ) -> None:
        """
        Inicia melhoria de texto de comentário em thread.
        Emite commentTextImproved(str) com o texto melhorado ou o original em falha.
        """
        if self._improve_worker is not None and self._improve_worker.isRunning():
            self.error.emit("Melhoria de comentário já em andamento")
            return
        self._improve_worker = _ImproveCommentWorker(
            self, text, comment_improvement_prompt, parent=self
        )
        self._improve_worker.finished.connect(self._on_improve_finished)
        self._improve_worker.error_occurred.connect(self._on_improve_error)
        self._improve_worker.finished.connect(
            lambda: setattr(self, "_improve_worker", None)
        )
        self._improve_worker.error_occurred.connect(
            lambda: setattr(self, "_improve_worker", None)
        )
        self._improve_worker.start()

    def _on_improve_finished(self, result: str) -> None:
        self.commentTextImproved.emit(result or "")

    def _on_improve_error(self, msg: str) -> None:
        self.error.emit(msg)

    def _process_task_sync(
        self,
        transcription: str,
        tipo_atividade_values: List[str],
        task_system_prompt: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Processa transcrição com LLM (HTTP + parse). Bloqueante; não emite sinais.
        Retorna dict com summary, description, tipo_atividade, utilizacaoIA.
        Em falha "soft" (HTTP != 200, parse falhou) retorna heuristic_fallback.
        Em exceção (rede, etc.) deixa propagar para o worker emitir error_occurred.
        """
        transcription = (transcription or "").strip()
        if not tipo_atividade_values:
            tipo_atividade_values = ["Suporte Dúvidas/Suporte uso incorreto"]

        if not REQUESTS_AVAILABLE:
            return self._heuristic_fallback(transcription, tipo_atividade_values)

        system_content = (
            (task_system_prompt or "").strip() or DEFAULT_TASK_SYSTEM_PROMPT
        )
        prompt = self._build_llm_prompt(transcription, tipo_atividade_values)
        r = requests.post(
            self._get_chat_completions_url(),
            json={
                "model": self._llm_model,
                "messages": [
                    {"role": "system", "content": system_content},
                    {"role": "user", "content": prompt},
                ],
                "temperature": 0.3,
                "response_format": {"type": "json_object"},
            },
            timeout=LOCALAI_TIMEOUT_GENERATE,
        )
        if r.status_code != 200:
            return self._heuristic_fallback(transcription, tipo_atividade_values)
        data = r.json()
        raw = ""
        try:
            raw = (
                data.get("choices", [{}])[0].get("message", {}).get("content") or ""
            ).strip()
        except (IndexError, KeyError, TypeError):
            pass
        parsed = self._extract_json(raw)
        if parsed:
            summary = (parsed.get("summary") or "").strip()[:SUMMARY_MAX_LENGTH]
            description = (parsed.get("description") or transcription).strip()
            tipo = (parsed.get("tipo_atividade") or "").strip()
            if tipo not in tipo_atividade_values:
                tipo = tipo_atividade_values[0]
            return {
                "summary": summary or self._heuristic_summary(transcription),
                "description": description or transcription,
                "tipo_atividade": tipo,
                "utilizacaoIA": "Sim",
            }
        return self._heuristic_fallback(transcription, tipo_atividade_values)

    @Slot()
    def process_task_from_voice(
        self,
        transcription: str,
        tipo_atividade_values: List[str],
        task_system_prompt: Optional[str] = None,
    ) -> None:
        """
        Inicia processamento em thread (Expandir com IA).
        Emite processingComplete(dict) ou error(str) quando o worker terminar.
        """
        if self._process_task_worker is not None and self._process_task_worker.isRunning():
            self.error.emit("Expandir com IA já em andamento")
            return
        transcription = (transcription or "").strip()
        if not tipo_atividade_values:
            tipo_atividade_values = ["Suporte Dúvidas/Suporte uso incorreto"]
        self._process_task_worker = _ProcessTaskWorker(
            self,
            transcription,
            tipo_atividade_values,
            task_system_prompt,
            parent=self,
        )
        self._process_task_worker.finished.connect(self._on_process_task_finished)
        self._process_task_worker.error_occurred.connect(self._on_process_task_error)
        self._process_task_worker.finished.connect(
            lambda: setattr(self, "_process_task_worker", None)
        )
        self._process_task_worker.error_occurred.connect(
            lambda: setattr(self, "_process_task_worker", None)
        )
        self._process_task_worker.start()

    def _on_process_task_finished(self, result: Dict[str, Any]) -> None:
        self.processingComplete.emit(result)

    def _on_process_task_error(self, msg: str) -> None:
        self.error.emit(msg)

    def _build_llm_prompt(
        self,
        transcription: str,
        tipo_atividade_values: List[str],
    ) -> str:
        values_str = "\n".join(f"- {v}" for v in tipo_atividade_values)
        return f"""Você é um assistente que converte comandos de voz em tarefas Jira estruturadas.

Transcrição do usuário: "{transcription}"

Valores permitidos para tipo_atividade (use exatamente um):
{values_str}

Extraia e retorne APENAS um JSON válido, sem texto antes ou depois, com as chaves:
- "summary": resumo conciso da tarefa (máximo 100 caracteres)
- "description": descrição detalhada em Markdown (pode usar a transcrição formatada)
- "tipo_atividade": um dos valores da lista acima, exatamente como escrito

Exemplo de resposta:
{{"summary": "Corrigir bug de login", "description": "## Problema\\nUsuários não conseguem fazer login.", "tipo_atividade": "Bugs/Incidentes/Retrabalho Técnico"}}
"""

    def _extract_json(self, text: str) -> Optional[Dict[str, Any]]:
        text = (text or "").strip()
        match = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
        if match:
            text = match.group(1).strip()
        match = re.search(r"\{[\s\S]*\}", text)
        if match:
            try:
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                pass
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return None

    def _heuristic_summary(self, text: str, max_chars: int = 100) -> str:
        text = (text or "").strip()
        if not text:
            return ""
        if len(text) <= max_chars:
            return text
        first = re.split(r"[.!?]\s+", text)[0].strip()
        if len(first) <= max_chars:
            return first
        words = text.split()[:15]
        summary = " ".join(words)
        if len(summary) > max_chars:
            summary = summary[: max_chars - 3].rsplit(maxsplit=1)[0] + "..."
        return summary

    def _heuristic_tipo(
        self,
        text: str,
        tipo_atividade_values: List[str],
    ) -> str:
        if not tipo_atividade_values:
            return ""
        low = text.lower()
        if any(w in low for w in ("bug", "erro", "falha", "incidente", "corrigir")):
            for v in tipo_atividade_values:
                if "bug" in v.lower() or "incidente" in v.lower():
                    return v
        if any(
            w in low
            for w in ("feature", "funcionalidade", "melhoria", "adicionar", "novo")
        ):
            for v in tipo_atividade_values:
                if "novas" in v.lower() or "melhoria" in v.lower():
                    return v
        if any(w in low for w in ("suporte", "dúvida", "ajuda")):
            for v in tipo_atividade_values:
                if "suporte" in v.lower():
                    return v
        return tipo_atividade_values[0]

    def _heuristic_fallback(
        self,
        transcription: str,
        tipo_atividade_values: List[str],
    ) -> Dict[str, Any]:
        summary = (self._heuristic_summary(transcription))[:SUMMARY_MAX_LENGTH]
        return {
            "summary": summary,
            "description": transcription,
            "tipo_atividade": self._heuristic_tipo(
                transcription, tipo_atividade_values
            ),
            "utilizacaoIA": "Não",
        }
