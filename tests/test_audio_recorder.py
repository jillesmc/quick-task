"""Testes para AudioRecorder. Saltam quando sounddevice/scipy não estão instalados."""

import pytest

try:
    from src.services.audio_recorder import (
        AudioRecorder,
        AUDIO_DEPS_AVAILABLE,
        _RecordingWorker,
    )
except ImportError:
    AudioRecorder = None
    AUDIO_DEPS_AVAILABLE = False
    _RecordingWorker = None

pytestmark = pytest.mark.skipif(
    not AUDIO_DEPS_AVAILABLE,
    reason="sounddevice/scipy/numpy not installed (voice deps optional)",
)


@pytest.fixture
def audio_recorder(qtbot):
    """Fixture que fornece AudioRecorder com duração máxima curta para testes."""
    rec = AudioRecorder(sample_rate=16000, max_duration_seconds=2)
    # AudioRecorder é QObject, não QWidget; não usar add_widget
    return rec


def test_is_available_when_deps_present():
    """Quando deps estão instaladas, is_available retorna True."""
    assert AudioRecorder().is_available() is True


def test_is_recording_initially_false(audio_recorder):
    """Antes de iniciar, is_recording é False."""
    assert audio_recorder.is_recording is False


def test_stop_recording_when_not_recording_no_op(audio_recorder):
    """Chamar stop_recording quando não está gravando não deve falhar."""
    audio_recorder.stop_recording()
