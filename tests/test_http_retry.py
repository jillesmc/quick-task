"""
Testes para src.utils.http_retry (request_with_retry).
"""

from unittest.mock import MagicMock, patch

import pytest

from src.utils.http_retry import request_with_retry, _get_delay, _parse_retry_after


def _make_response(status_code: int, retry_after: str = None):
    r = MagicMock()
    r.status_code = status_code
    r.headers = {}
    if retry_after is not None:
        r.headers["Retry-After"] = retry_after
    return r


def test_request_with_retry_success_first_call():
    """Sucesso na primeira chamada: callable é chamado uma vez e resultado é retornado."""
    resp = _make_response(200)
    call_count = 0

    def fn():
        nonlocal call_count
        call_count += 1
        return resp

    result = request_with_retry(fn, config={"max_retries": 3})
    assert call_count == 1
    assert result is resp
    assert result.status_code == 200


def test_request_with_retry_429_then_success():
    """429 na primeira, sucesso na segunda: retry e depois retorna o 200."""
    ok_resp = _make_response(200)
    bad_resp = _make_response(429)
    call_count = 0

    def fn():
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return bad_resp
        return ok_resp

    with patch("src.utils.http_retry.time.sleep") as mock_sleep:
        result = request_with_retry(
            fn,
            config={
                "max_retries": 3,
                "base_delay_seconds": 0.1,
                "max_delay_seconds": 60.0,
            },
        )
    assert call_count == 2
    assert result is ok_resp
    mock_sleep.assert_called_once()
    # First retry delay = base_delay * 2^0 = 0.1
    assert mock_sleep.call_args[0][0] == pytest.approx(0.1, rel=1e-6)


def test_request_with_retry_429_retry_after_used():
    """429 com Retry-After: o delay usado deve respeitar Retry-After (limitado por max_delay)."""
    ok_resp = _make_response(200)
    bad_resp = _make_response(429)
    bad_resp.headers["Retry-After"] = "3"
    call_count = 0

    def fn():
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return bad_resp
        return ok_resp

    with patch("src.utils.http_retry.time.sleep") as mock_sleep:
        request_with_retry(
            fn,
            config={
                "max_retries": 3,
                "base_delay_seconds": 1.0,
                "max_delay_seconds": 60.0,
            },
        )
    mock_sleep.assert_called_once()
    assert mock_sleep.call_args[0][0] == 3.0


def test_request_with_retry_429_exhausted_returns_last_response():
    """429 em todas as tentativas: devolve o último response (caller pode tratar 429)."""
    bad_resp = _make_response(429)
    call_count = 0

    def fn():
        nonlocal call_count
        call_count += 1
        return bad_resp

    with patch("src.utils.http_retry.time.sleep"):
        result = request_with_retry(
            fn,
            config={
                "max_retries": 3,
                "base_delay_seconds": 0.01,
                "max_delay_seconds": 60.0,
            },
        )
    assert call_count == 3
    assert result is bad_resp
    assert result.status_code == 429


def test_get_delay_exponential():
    """_get_delay sem Retry-After: backoff exponencial com teto."""
    assert _get_delay(0, 1.0, 60.0, None) == 1.0
    assert _get_delay(1, 1.0, 60.0, None) == 2.0
    assert _get_delay(2, 1.0, 60.0, None) == 4.0
    assert _get_delay(10, 1.0, 60.0, None) == 60.0  # capped


def test_get_delay_retry_after():
    """_get_delay com Retry-After: usa o valor respeitando teto."""
    assert _get_delay(0, 1.0, 60.0, 5.0) == 5.0
    assert _get_delay(0, 1.0, 3.0, 10.0) == 3.0  # capped by max_delay


def test_parse_retry_after():
    """_parse_retry_after extrai segundos do header."""
    r = MagicMock()
    r.headers = {"Retry-After": "12"}
    assert _parse_retry_after(r) == 12.0
    r.headers["Retry-After"] = "0"
    assert _parse_retry_after(r) == 0.0
    assert _parse_retry_after(None) is None
    r2 = MagicMock(spec=[])  # no headers
    assert _parse_retry_after(r2) is None


def test_request_with_retry_logs_on_retry():
    """Cada retry chama debug_log (verificar via mock)."""
    bad_resp = _make_response(503)
    call_count = 0

    def fn():
        nonlocal call_count
        call_count += 1
        if call_count < 2:
            return bad_resp
        return _make_response(200)

    with (
        patch("src.utils.http_retry.time.sleep"),
        patch("src.utils.http_retry.debug_log") as mock_log,
        patch("src.utils.http_retry.is_debug_enabled", return_value=True),
    ):
        request_with_retry(fn, config={"max_retries": 3, "base_delay_seconds": 0.01})
    assert mock_log.called
    assert (
        "retry" in (mock_log.call_args[0][2] or "").lower()
        or "attempt" in (mock_log.call_args[0][2] or "").lower()
    )


def test_request_with_retry_connection_error_then_success():
    """Timeout/ConnectionError na primeira, sucesso na segunda: retry e retorna."""
    try:
        import requests
    except ImportError:
        pytest.skip("requests not installed")
    ok_resp = _make_response(200)
    call_count = 0

    def fn():
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            raise requests.exceptions.Timeout("timed out")
        return ok_resp

    with patch("src.utils.http_retry.time.sleep"):
        result = request_with_retry(
            fn,
            config={
                "max_retries": 3,
                "base_delay_seconds": 0.01,
                "retry_on_connection_errors": True,
            },
        )
    assert call_count == 2
    assert result is ok_resp


def test_request_with_retry_connection_error_no_retry_when_disabled():
    """Quando retry_on_connection_errors=False, exceção de rede é re-lançada."""
    try:
        import requests
    except ImportError:
        pytest.skip("requests not installed")
    call_count = 0

    def fn():
        nonlocal call_count
        call_count += 1
        raise requests.exceptions.ConnectionError("failed")

    with pytest.raises(requests.exceptions.ConnectionError):
        request_with_retry(
            fn, config={"max_retries": 3, "retry_on_connection_errors": False}
        )
    assert call_count == 1
