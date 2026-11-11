"""Traduccion centralizada de errores de PostgreSQL a respuestas HTTP."""

from __future__ import annotations

import logging
from typing import Any

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from psycopg import Error as PsycopgError
from psycopg_pool import PoolTimeout
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger("bodegas.api")


class ApiError(Exception):
    """Error de negocio o de recurso no encontrado, ya traducido a HTTP."""

    def __init__(
        self,
        status_code: int,
        codigo: str,
        mensaje: str,
        regla: str | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(mensaje)
        self.status_code = status_code
        self.codigo = codigo
        self.mensaje = mensaje
        self.regla = regla
        self.headers = headers


def _respuesta(
    status_code: int,
    codigo: str,
    mensaje: str,
    regla: str | None = None,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    contenido: dict[str, Any] = {
        "error": {
            "codigo": codigo,
            "mensaje": mensaje,
        }
    }
    if regla:
        contenido["error"]["regla"] = regla
    return JSONResponse(status_code=status_code, content=contenido, headers=headers)


def _datos_diagnostico(exc: PsycopgError) -> tuple[str, str | None, str | None]:
    diag = exc.diag
    if diag is None:
        return "", None, None
    lineas = str(exc).splitlines()
    mensaje = diag.message_primary or (lineas[0] if lineas else "")
    detalle = diag.message_detail
    restriccion = diag.constraint_name
    return mensaje, detalle, restriccion


def manejar_api_error(_: Request, exc: ApiError) -> JSONResponse:
    return _respuesta(exc.status_code, exc.codigo, exc.mensaje, exc.regla, exc.headers)


def manejar_validacion(_: Request, exc: RequestValidationError) -> JSONResponse:
    errores = []
    for error in exc.errors():
        ubicacion = ".".join(str(parte) for parte in error.get("loc", ()))
        errores.append({"campo": ubicacion, "detalle": error.get("msg", "valor invalido")})
    return _respuesta(
        422,
        "VALIDACION",
        "La solicitud no cumple el formato esperado",
        regla="; ".join(f"{e['campo']}: {e['detalle']}" for e in errores) or None,
    )


def manejar_http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    if exc.status_code == 404:
        return _respuesta(404, "NO_ENCONTRADO", "Recurso no encontrado")
    return _respuesta(exc.status_code, f"HTTP_{exc.status_code}", str(exc.detail))


def manejar_psycopg(_: Request, exc: PsycopgError) -> JSONResponse:
    codigo = exc.sqlstate or "ERROR_BD"
    mensaje, detalle, restriccion = _datos_diagnostico(exc)

    # 23505: violacion de UNIQUE
    if codigo == "23505":
        return _respuesta(
            409,
            codigo,
            mensaje or "Ya existe un registro con ese valor unico",
            restriccion,
        )

    # 23503: FK. Se distingue el dato referenciado inexistente (422) de una
    # fila que todavia tiene dependientes y no se puede borrar (409).
    if codigo == "23503":
        detalle_lower = (detalle or "").lower()
        if "is not present" in detalle_lower or "no esta presente" in detalle_lower:
            return _respuesta(422, codigo, mensaje or "El dato referenciado no existe", restriccion)
        return _respuesta(409, codigo, mensaje or "La operacion viola una clave foranea", restriccion)

    # 23514: CHECK
    if codigo == "23514":
        return _respuesta(422, codigo, mensaje or "El valor viola una regla de la base", restriccion)

    # 23502: NOT NULL
    if codigo == "23502":
        return _respuesta(422, codigo, mensaje or "Falta un dato obligatorio", restriccion)

    # 22P02 / 22001: formato o longitud invalida
    if codigo in {"22P02", "22001", "22003"}:
        return _respuesta(400, codigo, mensaje or "Formato de dato invalido", restriccion)

    # P0001: RAISE EXCEPTION de funciones, triggers y procedimientos.
    # Se devuelve el mensaje original de la regla, sin reemplazarlo.
    if codigo == "P0001":
        return _respuesta(409, codigo, mensaje or str(exc), restriccion)

    # Serializacion / deadlock: se puede reintentar.
    if codigo in {"40001", "40P01"}:
        return _respuesta(
            503,
            codigo,
            "La operacion compitio con otra transaccion. Reintente en unos segundos.",
            restriccion,
            headers={"Retry-After": "1"},
        )

    # Caida o saturacion de la base.
    if codigo.startswith("08") or codigo in {"53300", "57P03"}:
        return _respuesta(
            503,
            codigo,
            "La base de datos no esta disponible en este momento.",
            restriccion,
            headers={"Retry-After": "5"},
        )

    # Cualquier otro error de PostgreSQL es inesperado: no se filtra el detalle.
    logger.error(
        "Error de PostgreSQL no traducido",
        exc_info=(type(exc), exc, exc.__traceback__),
    )
    return _respuesta(500, "ERROR_INTERNO", "Error interno del servidor")


def manejar_pool_timeout(_: Request, exc: PoolTimeout) -> JSONResponse:
    logger.warning("Timeout esperando conexion del pool: %s", exc)
    return _respuesta(
        503,
        "POOL_TIMEOUT",
        "No hay conexiones disponibles. Reintente en unos segundos.",
        headers={"Retry-After": "2"},
    )


def manejar_inesperado(_: Request, exc: Exception) -> JSONResponse:
    logger.error(
        "Error inesperado",
        exc_info=(type(exc), exc, exc.__traceback__),
    )
    return _respuesta(500, "ERROR_INTERNO", "Error interno del servidor")
