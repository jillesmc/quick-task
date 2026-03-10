"""
Retry com backoff exponencial para chamadas HTTP externas.

Evita falhas por HTTP 429 (rate limit), 503, 502 e erros de rede/timeout.
Respeita o header Retry-After quando o servidor enviar (429).
"""

import time
from typing import Any, Callable, Dict, List, Optional

try:
    import requests
except ImportError:
    requests = None  # type: ignore[assignment]

from src.utils.debug import debug_log, is_debug_enabled

_DEFAULT_CONFIG: Dict[str, Any] = {
    "max_retries": 3,
    "base_delay_seconds": 1.0,
    "max_delay_seconds": 60.0,
    "retry_on_status": [429, 503, 502],
    "retry_on_connection_errors": True,
}

# Exceções consideradas "erro de rede" para retry
_CONNECTION_EXCEPTIONS: tuple = ()
if requests is not None:
    _CONNECTION_EXCEPTIONS = (
        requests.exceptions.Timeout,
        requests.exceptions.ConnectionError,
        requests.exceptions.RequestException,
    )


def _get_delay(
    attempt: int,
    base_delay: float,
    max_delay: float,
    retry_after_seconds: Optional[float] = None,
) -> float:
    """Calcula delay em segundos: Retry-After se fornecido, senão backoff exponencial."""
    if retry_after_seconds is not None and retry_after_seconds > 0:
        return min(float(retry_after_seconds), max_delay)
    delay = base_delay * (2**attempt)
    return min(delay, max_delay)


def _parse_retry_after(response: Any) -> Optional[float]:
    """Extrai Retry-After do response em segundos (inteiro ou delay em segundos)."""
    if response is None or not hasattr(response, "headers"):
        return None
    raw = response.headers.get("Retry-After")
    if raw is None:
        return None
    try:
        return float(raw)
    except (TypeError, ValueError):
        return None


def request_with_retry(
    request_fn: Callable[[], Any],
    config: Optional[Dict[str, Any]] = None,
) -> Any:
    """
    Executa request_fn com retry e backoff exponencial.

    - Em HTTP 429: usa header Retry-After como delay quando presente.
    - Em outros status em retry_on_status (503, 502) ou em timeout/connection error:
      backoff exponencial: min(base_delay_seconds * 2^attempt, max_delay_seconds).

    Args:
        request_fn: Callable sem argumentos que faz uma requisição e devolve
            um objeto com .status_code e .headers (ex.: requests.Response), ou lança.
        config: Dict com max_retries, base_delay_seconds, max_delay_seconds e
            opcionalmente retry_on_status (lista de códigos), retry_on_connection_errors (bool).
            Se None, usa defaults (_DEFAULT_CONFIG).

    Returns:
        O resultado de request_fn() quando bem-sucedido (status não retentável)
            ou após esgotar tentativas (devolve o último response para o caller tratar).

    Raises:
        Re-lança a exceção quando esgota tentativas e a última falha foi exceção (ex.: timeout).
    """
    cfg = dict(_DEFAULT_CONFIG)
    if config:
        cfg.update({k: v for k, v in config.items() if k in cfg})

    max_retries = max(1, int(cfg.get("max_retries", 3)))
    base_delay = max(0.1, float(cfg.get("base_delay_seconds", 1.0)))
    max_delay = max(1.0, float(cfg.get("max_delay_seconds", 60.0)))
    retry_on_status: List[int] = list(cfg.get("retry_on_status", [429, 503, 502]))
    retry_on_connection_errors = bool(cfg.get("retry_on_connection_errors", True))

    last_response: Optional[Any] = None
    last_exception: Optional[Exception] = None

    for attempt in range(max_retries):
        try:
            response = request_fn()
            last_response = response
            last_exception = None
            status = getattr(response, "status_code", None)
            if status is not None and status in retry_on_status:
                if attempt < max_retries - 1:
                    retry_after = (
                        _parse_retry_after(response) if status == 429 else None
                    )
                    delay = _get_delay(attempt, base_delay, max_delay, retry_after)
                    if is_debug_enabled():
                        debug_log(
                            "http_retry",
                            "request_with_retry",
                            "HTTP retry attempt %d/%d (status=%s), waiting %.1fs",
                            attempt + 1,
                            max_retries,
                            status,
                            delay,
                        )
                    time.sleep(delay)
                    continue
            return response
        except _CONNECTION_EXCEPTIONS as e:
            last_exception = e
            last_response = None
            if not retry_on_connection_errors or attempt >= max_retries - 1:
                raise
            delay = _get_delay(attempt, base_delay, max_delay, None)
            if is_debug_enabled():
                debug_log(
                    "http_retry",
                    "request_with_retry",
                    "HTTP retry attempt %d/%d (exception=%s), waiting %.1fs",
                    attempt + 1,
                    max_retries,
                    type(e).__name__,
                    delay,
                )
            time.sleep(delay)
        except Exception:
            raise

    if last_exception is not None:
        raise last_exception
    return last_response
