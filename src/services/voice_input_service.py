"""
Serviço de entrada por voz: orquestra gravação (AudioRecorder), transcrição e
processamento (LocalAI no host) e preenchimento do IssueModel.
Dependências opcionais: sounddevice, scipy (áudio); requests (já em base).
"""

from typing import Any, Optional

from PySide6.QtCore import QObject, Signal, Slot  # type: ignore[import]


def _load_voice_components():
    try:
        from src.services.audio_recorder import AudioRecorder, AUDIO_DEPS_AVAILABLE
        from src.services.localai_client import LocalAIClient
        return AudioRecorder, LocalAIClient, AUDIO_DEPS_AVAILABLE
    except ImportError:
        return None, None, False


class VoiceInputService(QObject):
    """
    Orquestra AudioRecorder e LocalAIClient; preenche IssueModel com os campos
    extraídos e emite fieldsFilled(). Transcrição e LLM ficam no LocalAI no host.
    """

    recordingStarted = Signal()
    recordingStopped = Signal()
    recordingProgress = Signal(float)  # seconds
    transcriptionReady = Signal(str)
    fieldsFilled = Signal()
    commentTextImproved = Signal(str)
    error = Signal(str)

    def __init__(
        self,
        issue_model: Any,
        config_manager: Any,
        editing_issue_model: Optional[Any] = None,
        parent=None,
    ):
        super().__init__(parent)
        self._issue_model = issue_model
        self._editing_issue_model = editing_issue_model
        self._config = config_manager
        self._last_expand_for_editing = False
        AudioRecorderCls, ClientCls, audio_ok = _load_voice_components()
        self._AudioRecorderCls = AudioRecorderCls
        self._ClientCls = ClientCls
        self._audio_ok = audio_ok

        self._recorder: Optional[Any] = None
        self._client: Optional[Any] = None

        if self._AudioRecorderCls and self._config:
            max_sec = self._config.get_voice_input_max_recording_seconds()
            device = self._config.get_voice_input_microphone_device()
            self._recorder = self._AudioRecorderCls(
                sample_rate=16000,
                max_duration_seconds=max_sec,
                device=device if device != "default" else None,
                parent=self,
            )
            self._recorder.recordingStarted.connect(self.recordingStarted.emit)
            self._recorder.recordingStopped.connect(self._on_recording_stopped)
            self._recorder.recordingProgress.connect(self.recordingProgress.emit)
            self._recorder.error.connect(self.error.emit)

        if self._ClientCls and self._config:
            base_url = self._config.get_localai_base_url()
            whisper_model = self._config.get_localai_whisper_model()
            llm_model = self._config.get_localai_llm_model()
            self._client = self._ClientCls(
                base_url=base_url,
                whisper_model=whisper_model,
                llm_model=llm_model,
                parent=self,
            )
            self._client.transcriptionComplete.connect(self._on_transcription_complete)
            self._client.processingComplete.connect(self._on_processing_complete)
            self._client.commentTextImproved.connect(self.commentTextImproved.emit)
            self._client.error.connect(self.error.emit)

    def _on_recording_stopped(self, path: str) -> None:
        self.recordingStopped.emit()
        if path and self._client:
            self._client.transcribe_audio(path)
        elif not path:
            pass  # error already emitted by recorder

    def _on_transcription_complete(self, text: str) -> None:
        self.transcriptionReady.emit(text or "")
        if self._config and self._config.get_voice_input_auto_process_after_stop():
            self.processTranscription(text or "")

    def _on_processing_complete(self, result: dict) -> None:
        target = (
            self._editing_issue_model
            if (self._last_expand_for_editing and self._editing_issue_model)
            else self._issue_model
        )
        if not target:
            return
        tipo_values = []
        if self._config:
            tipo_values = self._config.get_tipo_atividade_values()
        if not tipo_values:
            tipo_values = getattr(target, "tipoAtividadeValues", []) or []
        if not tipo_values:
            tipo_values = ["Suporte Dúvidas/Suporte uso incorreto"]
        target.summary = result.get("summary", "")
        target.description = result.get("description", "")
        target.tipoAtividade = result.get(
            "tipo_atividade", tipo_values[0] if tipo_values else ""
        )
        target.utilizacaoIA = result.get("utilizacaoIA", "Sim")
        self.fieldsFilled.emit()

    @Slot(result=bool)
    def isAvailable(self) -> bool:
        """True se gravação (áudio) e LocalAI no host estão disponíveis."""
        return bool(
            self._audio_ok
            and self._recorder
            and self._recorder.is_available()
            and self._client
            and self._client.check_connection()
        )

    @Slot()
    def startRecording(self) -> None:
        """Inicia gravação do microfone."""
        if self._recorder:
            self._recorder.start_recording()
        else:
            self.error.emit("Gravação não disponível")

    @Slot()
    def stopRecording(self) -> None:
        """Para a gravação e inicia transcrição via LocalAI ao concluir."""
        if self._recorder:
            self._recorder.stop_recording()

    @Slot(str)
    def processTranscription(self, text: str) -> None:
        """
        Processa o texto transcrito com LLM (LocalAI) e preenche o IssueModel.
        Emite fieldsFilled() ao terminar.
        """
        if not self._issue_model or not self._client:
            self.error.emit("Serviço não inicializado")
            return
        self._last_expand_for_editing = False
        tipo_values = []
        if self._config:
            tipo_values = self._config.get_tipo_atividade_values()
        if not tipo_values:
            tipo_values = getattr(self._issue_model, "tipoAtividadeValues", []) or []
        if not tipo_values:
            tipo_values = ["Suporte Dúvidas/Suporte uso incorreto"]
        task_prompt = None
        if self._config:
            task_prompt = self._config.get_localai_task_system_prompt()
        self._client.process_task_from_voice(
            (text or "").strip(), tipo_values, task_system_prompt=task_prompt
        )

    @Slot(str, str, bool)
    def expandFromSummaryAndDescription(
        self, summary: str, description: str, for_editing: bool
    ) -> None:
        """
        Expande summary (e opcionalmente description) com IA e preenche o modelo
        de criação (for_editing=False) ou o de edição (for_editing=True).
        Emite error(str) se o texto for vazio; fieldsFilled() ao terminar.
        """
        text = (summary or "").strip()
        if (description or "").strip():
            text = f"{text}\n\n{(description or '').strip()}" if text else (description or "").strip()
        if not text:
            self.error.emit("Resumo ou descrição são necessários para expandir")
            return
        if not self._client:
            self.error.emit("Serviço não inicializado")
            return
        target = self._editing_issue_model if for_editing else self._issue_model
        if not target:
            self.error.emit("Modelo de issue não disponível")
            return
        self._last_expand_for_editing = for_editing
        tipo_values = []
        if self._config:
            tipo_values = self._config.get_tipo_atividade_values()
        if not tipo_values:
            tipo_values = getattr(target, "tipoAtividadeValues", []) or []
        if not tipo_values:
            tipo_values = ["Suporte Dúvidas/Suporte uso incorreto"]
        task_prompt = None
        if self._config:
            task_prompt = self._config.get_localai_task_system_prompt()
        self._client.process_task_from_voice(
            text, tipo_values, task_system_prompt=task_prompt
        )

    @Slot(str)
    def improveCommentText(self, text: str) -> None:
        """
        Melhora o texto do comentário via LocalAI (assíncrono).
        Emite commentTextImproved(str) com o texto melhorado.
        """
        if not self._client:
            self.error.emit("Serviço não inicializado")
            return
        comment_prompt = None
        if self._config:
            comment_prompt = self._config.get_localai_comment_improvement_prompt()
        self._client.improve_comment_text(text, comment_improvement_prompt=comment_prompt)
