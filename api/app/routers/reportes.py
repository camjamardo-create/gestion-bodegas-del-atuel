"""Endpoints de reportes basados en las consultas de la Etapa 5."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query

from .. import db
from ..errors import ApiError
from ..repositories import reportes as repo
from ..schemas import (
    TopVinoOut,
    TrazabilidadOut,
    TransportistaActivoOut,
    VentaSalaOut,
    VinoSinStockOut,
)

router = APIRouter(prefix="/reportes", tags=["Reportes"])


@router.get("/top-vinos", response_model=list[TopVinoOut])
def top_vinos() -> list[dict[str, Any]]:
    with db.connection() as conn:
        return repo.top_vinos(conn)


@router.get("/ventas-por-sala", response_model=list[VentaSalaOut])
def ventas_por_sala() -> list[dict[str, Any]]:
    with db.connection() as conn:
        return repo.ventas_por_sala(conn)


@router.get("/vinos-sin-stock", response_model=list[VinoSinStockOut])
def vinos_sin_stock(
    sala: int = Query(..., description="id de la sala de venta"),
) -> list[dict[str, Any]]:
    with db.connection() as conn:
        return repo.vinos_sin_stock(conn, sala)


@router.get("/transportista-activo", response_model=TransportistaActivoOut | None)
def transportista_activo() -> dict[str, Any] | None:
    with db.connection() as conn:
        return repo.transportista_activo(conn)


@router.get("/trazabilidad/{codigo}", response_model=TrazabilidadOut)
def trazabilidad(codigo: int) -> dict[str, Any]:
    with db.connection() as conn:
        fila = repo.trazabilidad_vino(conn, codigo)
    if fila is None:
        raise ApiError(404, "NO_ENCONTRADO", f"El vino {codigo} no existe")
    return fila
