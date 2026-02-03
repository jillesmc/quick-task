"""
Serviço de gravação de áudio do microfone para entrada por voz.
Grava em thread para não bloquear a UI. Depende de sounddevice e scipy.
"""

import tempfile
import time
from pathlib import Path
from typing import List, Optional

from PySide6.QtCore import QObject, Signal, QThread, Slot  # type: ignore[import]

# Dependências opcionais: import apenas se disponíveis
try:
    import numpy as np
    import sounddevice as sd
    from scipy.io import wavfile

    AUDIO_DEPS_AVAILABLE = True
except ImportError:
    np = None
    sd = None
    wavfile = None
    AUDIO_DEPS_AVAILABLE = False


class _RecordingWorker(QThread):
    """Thread que executa a gravação e salva o WAV."""

    recording_started = Signal()
    recording_stopped = Signal(str)  # path
    recording_progress = Signal(float)  # seconds
    error_occurred = Signal(str)

    def __init__(
        self,
        sample_rate: int = 16000,
        max_duration_seconds: int = 120,
        device: Optional[str] = None,
        parent=None,
    ):
        super().__init__(parent)
        self._sample_rate = sample_rate
        self._max_duration = max_duration_seconds
        self._device = device
        self._chunks: List[np.ndarray] = [] if np is not None else []
        self._stream = None
        self._stop_requested = False
        self._start_time: Optional[float] = None
        self._progress_interval = 1.0  # emit progress every second

    def _audio_callback(self, indata, frames, time_info, status):
        if status:
            self.error_occurred.emit(str(status))
            return
        if np is not None and indata is not None and len(indata) > 0:
            self._chunks.append(indata.copy())

    def run(self) -> None:
        if not AUDIO_DEPS_AVAILABLE:
            self.error_occurred.emit(
                "Dependências de áudio não disponíveis (sounddevice, scipy, numpy)"
            )
            return
        self._stop_requested = False
        self._chunks = []
        self._start_time = time.monotonic()
        last_progress = 0.0
        try:
            device_id = self._device if self._device and self._device != "default" else None
            self._stream = sd.InputStream(
                samplerate=self._sample_rate,
                channels=1,
                dtype="float32",
                callback=self._audio_callback,
                device=device_id,
            )
            self._stream.start()
            self.recording_started.emit()
            while not self._stop_requested:
                elapsed = time.monotonic() - self._start_time
                if elapsed >= self._max_duration:
                    break
                if int(elapsed) > last_progress:
                    last_progress = int(elapsed)
                    self.recording_progress.emit(elapsed)
                self.msleep(200)
            self._stream.stop()
            self._stream.close()
            self._stream = None
        except Exception as e:
            self.error_occurred.emit(str(e))
            if self._stream is not None:
                try:
                    self._stream.close()
                except Exception:
                    pass
                self._stream = None
            return
        elapsed = time.monotonic() - self._start_time
        self.recording_progress.emit(elapsed)
        if not self._chunks:
            self.recording_stopped.emit("")
            return
        try:
            audio_data = np.concatenate(self._chunks, axis=0).squeeze()
            # Converter float32 para int16 para WAV
            audio_int16 = (audio_data * 32767).astype(np.int16)
            fd, path = tempfile.mkstemp(suffix=".wav", prefix="jira-quick-task-voice-")
            try:
                import os

                os.close(fd)
                wavfile.write(path, self._sample_rate, audio_int16)
                self.recording_stopped.emit(path)
            except Exception as e:
                self.error_occurred.emit(str(e))
                self.recording_stopped.emit("")
        except Exception as e:
            self.error_occurred.emit(str(e))
            self.recording_stopped.emit("")

    def request_stop(self) -> None:
        self._stop_requested = True


class AudioRecorder(QObject):
    """
    Grava áudio do microfone em thread. Emite sinais para a UI.
    Dependências: sounddevice, scipy, numpy (opcionais).
    """

    recordingStarted = Signal()
    recordingStopped = Signal(str)  # audio file path
    recordingProgress = Signal(float)  # seconds
    error = Signal(str)

    def __init__(
        self,
        sample_rate: int = 16000,
        max_duration_seconds: int = 120,
        device: Optional[str] = None,
        parent=None,
    ):
        super().__init__(parent)
        self._sample_rate = sample_rate
        self._max_duration = max_duration_seconds
        self._device = device
        self._worker: Optional[_RecordingWorker] = None

    @property
    def is_recording(self) -> bool:
        return self._worker is not None and self._worker.isRunning()

    def is_available(self) -> bool:
        """Retorna True se as dependências de áudio estão instaladas."""
        return AUDIO_DEPS_AVAILABLE

    @Slot()
    def start_recording(self) -> None:
        """Inicia a gravação em uma thread. Emite recordingStarted quando o stream abrir."""
        if not AUDIO_DEPS_AVAILABLE:
            self.error.emit("Dependências de áudio não disponíveis")
            return
        if self._worker is not None and self._worker.isRunning():
            self.error.emit("Gravação já em andamento")
            return
        self._worker = _RecordingWorker(
            sample_rate=self._sample_rate,
            max_duration_seconds=self._max_duration,
            device=self._device,
            parent=self,
        )
        self._worker.recording_started.connect(self._on_started)
        self._worker.recording_stopped.connect(self._on_stopped)
        self._worker.recording_progress.connect(self.recordingProgress.emit)
        self._worker.error_occurred.connect(self.error.emit)
        self._worker.finished.connect(self._on_worker_finished)
        self._worker.start()

    def _on_started(self) -> None:
        self.recordingStarted.emit()

    def _on_stopped(self, path: str) -> None:
        self.recordingStopped.emit(path)

    def _on_worker_finished(self) -> None:
        self._worker = None

    @Slot()
    def stop_recording(self) -> None:
        """Solicita parada da gravação. recordingStopped será emitido com o caminho do WAV."""
        if self._worker is not None and self._worker.isRunning():
            self._worker.request_stop()
