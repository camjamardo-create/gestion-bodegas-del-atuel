"""Punto de entrada de la API REST de Bodegas del Atuel."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from psycopg import Error as PsycopgError
from psycopg_pool import PoolTimeout
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import __version__, db
from .config import cors_origins_desde_entorno
from .errors import (
    ApiError,
    manejar_api_error,
    manejar_http,
    manejar_inesperado,
    manejar_pool_timeout,
    manejar_psycopg,
    manejar_validacion,
)
from .routers import clientes, comprobantes, ingresos, reportes, salud, transferencias, vinos

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("bodegas.api")


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    logger.info("Abriendo pool de conexiones")
    db.open_pool()
    logger.info("Pool de conexiones listo")
    try:
        yield
    finally:
        logger.info("Cerrando pool de conexiones")
        db.close_pool()


app = FastAPI(
    title="Bodegas del Atuel API",
    description=(
        "API REST de la Etapa 6 sobre PostgreSQL. La API usa SQL parametrizado, "
        "un pool de conexiones y transacciones explicitas. Las reglas de negocio "
        "(stock, totales, descuentos, estados y auditoria) siguen viviendo en la base."
    ),
    version=__version__,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=list(cors_origins_desde_entorno()),
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
    max_age=600,
)

app.add_exception_handler(ApiError, manejar_api_error)
app.add_exception_handler(RequestValidationError, manejar_validacion)
app.add_exception_handler(StarletteHTTPException, manejar_http)
app.add_exception_handler(PsycopgError, manejar_psycopg)
app.add_exception_handler(PoolTimeout, manejar_pool_timeout)
app.add_exception_handler(Exception, manejar_inesperado)

app.include_router(salud.router)
app.include_router(vinos.router)
app.include_router(clientes.router)
app.include_router(comprobantes.router)
app.include_router(transferencias.router)
app.include_router(ingresos.router)
app.include_router(reportes.router)


@app.get("/", tags=["Raiz"])
def raiz() -> dict[str, str]:
    return {
        "servicio": "Bodegas del Atuel API",
        "version": __version__,
        "documentacion": "/docs",
        "openapi": "/openapi.json",
        "salud": "/salud",
    }
