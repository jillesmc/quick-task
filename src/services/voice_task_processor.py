"""
Processador de transcrição de voz para campos estruturados de issue Jira.
Usa Ollama (LLM local) quando disponível; fallback por heurísticas.
"""

import json
import re
from typing import Any, Dict, List, Optional

try:
    import requests

    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

OLLAMA_BASE = "http://localhost:11434"
OLLAMA_TIMEOUT = 60


class VoiceTaskProcessor:
    """
    Converte texto transcrito em campos estruturados (summary, description, tipo_atividade).
    Se Ollama estiver disponível, usa LLM; senão usa heurísticas.
    """

    def __init__(self, ollama_model: str = "llama3.2", ollama_base: str = OLLAMA_BASE):
        self._ollama_model = ollama_model
        self._ollama_base = ollama_base.rstrip("/")

    def _ollama_available(self) -> bool:
        if not REQUESTS_AVAILABLE:
            return False
        try:
            r = requests.get(f"{self._ollama_base}/api/tags", timeout=5)
            return r.status_code == 200
        except Exception:
            return False

    def _call_ollama(self, prompt: str) -> Optional[str]:
        if not REQUESTS_AVAILABLE:
            return None
        try:
            r = requests.post(
                f"{self._ollama_base}/api/generate",
                json={"model": self._ollama_model, "prompt": prompt, "stream": False},
                timeout=OLLAMA_TIMEOUT,
            )
            if r.status_code != 200:
                return None
            data = r.json()
            return data.get("response", "").strip()
        except Exception:
            return None

    def _extract_json_from_response(self, text: str) -> Optional[Dict[str, Any]]:
        """Tenta extrair um objeto JSON da resposta do LLM (pode vir com markdown)."""
        text = text.strip()
        # Remover blocos de código markdown
        match = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
        if match:
            text = match.group(1).strip()
        # Procurar por { ... }
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
        """Primeiras N palavras ou primeira frase como summary."""
        text = text.strip()
        if not text:
            return ""
        if len(text) <= max_chars:
            return text
        first_sentence = re.split(r"[.!?]\s+", text)[0].strip()
        if len(first_sentence) <= max_chars:
            return first_sentence
        words = text.split()[:15]
        summary = " ".join(words)
        if len(summary) > max_chars:
            summary = summary[: max_chars - 3].rsplit(maxsplit=1)[0] + "..."
        return summary

    def _heuristic_tipo_atividade(
        self, text: str, tipo_atividade_values: List[str]
    ) -> str:
        """Inferir tipo de atividade por palavras-chave."""
        if not tipo_atividade_values:
            return ""
        text_lower = text.lower()
        # Bugs/Incidentes
        if any(
            w in text_lower
            for w in ("bug", "erro", "erro 500", "falha", "incidente", "corrigir")
        ):
            for v in tipo_atividade_values:
                if "bug" in v.lower() or "incidente" in v.lower():
                    return v
        # Novas funcionalidades
        if any(
            w in text_lower
            for w in ("feature", "funcionalidade", "melhoria", "adicionar", "novo")
        ):
            for v in tipo_atividade_values:
                if "novas" in v.lower() or "melhoria" in v.lower():
                    return v
        # Suporte
        if any(w in text_lower for w in ("suporte", "dúvida", "ajuda")):
            for v in tipo_atividade_values:
                if "suporte" in v.lower():
                    return v
        return tipo_atividade_values[0]

    def process_transcription(
        self,
        transcription: str,
        tipo_atividade_values: List[str],
    ) -> Dict[str, Any]:
        """
        Processa texto transcrito e retorna dict com summary, description, tipo_atividade,
        utilizacaoIA (Sim/Não). tipo_atividade será um dos valores da lista.
        """
        transcription = (transcription or "").strip()
        if not tipo_atividade_values:
            tipo_atividade_values = ["Suporte Dúvidas/Suporte uso incorreto"]

        if self._ollama_available():
            prompt = self._build_ollama_prompt(transcription, tipo_atividade_values)
            response = self._call_ollama(prompt)
            if response:
                parsed = self._extract_json_from_response(response)
                if parsed:
                    summary = (parsed.get("summary") or "").strip()[:255]
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

        # Fallback heurístico
        summary = self._heuristic_summary(transcription)
        tipo = self._heuristic_tipo_atividade(transcription, tipo_atividade_values)
        return {
            "summary": summary,
            "description": transcription,
            "tipo_atividade": tipo,
            "utilizacaoIA": "Não",
        }

    def _build_ollama_prompt(
        self, transcription: str, tipo_atividade_values: List[str]
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
