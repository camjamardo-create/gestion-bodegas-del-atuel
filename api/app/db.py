"""Pool de conexiones y manejo explicito de transacciones."""

from __future__ import annotations

from contextlib import contextmanager
from typing import Iterator

from psycopg import Connection
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .config import get_settings

_pool: ConnectionPool | None = None


def open_pool() -> None:
    """Abre el pool. Se llama desde el lifespan de FastAPI."""
    global _pool
    if _pool is not None:
        return

    settings = get_settings()
    _pool = ConnectionPool(
        conninfo=settings.conninfo,
        min_size=settings.pool_min_size,
        max_size=settings.pool_max_size,
        timeout=settings.pool_timeout,
        kwargs={"row_factory": dict_row},
        open=True,
    )
    # Falla temprano si la base no responde, en lugar de fallar en el primer
    # request. El compose ya espera el healthcheck de PostgreSQL.
    _pool.wait(timeout=settings.pool_timeout)


def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


def _get_pool() -> ConnectionPool:
    if _pool is None:
        raise RuntimeError("El pool de conexiones no esta abierto")
    return _pool


@contextmanager
def connection() -> Iterator[Connection]:
    """Conexion del pool para lecturas; se devuelve al pool al salir."""
    with _get_pool().connection() as conn:
        yield conn


@contextmanager
def transaction() -> Iterator[Connection]:
    """Transaccion explicita: BEGIN al entrar, COMMIT al salir bien y ROLLBACK
    ante cualquier error.

    psycopg emite el BEGIN al abrir ``conn.transaction()``. El COMMIT tambien
    queda dentro del contexto: los constraint triggers diferidos de PostgreSQL
    pueden fallar recien al confirmar (por ejemplo, la suma de composiciones de
    un vino). En ese caso psycopg hace ROLLBACK y la excepcion sube al manejador
    central de errores.
    """
    with _get_pool().connection() as conn:
        with conn.transaction():
            yield conn
