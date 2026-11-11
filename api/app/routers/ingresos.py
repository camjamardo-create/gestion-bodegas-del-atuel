"""Endpoints de ingresos al deposito central."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter

from .. import db
from ..errors import ApiError
from ..repositories import ingresos as repo
from ..schemas import IngresoCreate, IngresoOut, RenglonMovimientoIn

router = APIRouter(prefix="/ingresos", tags=["Ingresos"])


def _detalle(conn: Any, codigo: int) -> dict[str, Any] | None:
    fila = repo.obtener(conn, codigo)
    if fila is None:
        return None
    return {
        "codigo": fila["codigo"],
        "fecha": fila["fecha"],
        "estado": fila["estado"],
        "codigo_transportista": fila["codigo_transportista"],
        "cuit_bodega": fila["cuit_bodega"],
        "renglones": repo.obtener_renglones(conn, codigo),
    }


def _leer_detalle(codigo: int) -> dict[str, Any]:
    with db.connection() as conn:
        detalle = _detalle(conn, codigo)
    if detalle is None:
        raise ApiError(404, "NO_ENCONTRADO", f"El ingreso {codigo} no existe")
    return detalle


def _normalizar_renglones(
    payload: RenglonMovimientoIn | list[RenglonMovimientoIn],
) -> list[dict[str, Any]]:
    renglones = payload if isinstance(payload, list) else [payload]
    return [renglon.model_dump() for renglon in renglones]


@router.post("", response_model=IngresoOut, status_code=201)
def crear_ingreso(payload: IngresoCreate) -> dict[str, Any]:
    with db.transaction() as conn:
        fila = repo.crear(conn, payload.codigo_transportista, payload.cuit_bodega)
    return _leer_detalle(fila["codigo"])


@router.get("/{codigo}", response_model=IngresoOut)
def obtener_ingreso(codigo: int) -> dict[str, Any]:
    return _leer_detalle(codigo)


@router.post("/{codigo}/renglones", response_model=IngresoOut)
def agregar_renglon(
    codigo: int,
    payload: RenglonMovimientoIn | list[RenglonMovimientoIn],
) -> dict[str, Any]:
    renglones = _normalizar_renglones(payload)
    with db.transaction() as conn:
        if repo.obtener(conn, codigo) is None:
            raise ApiError(404, "NO_ENCONTRADO", f"El ingreso {codigo} no existe")
        repo.insertar_renglones(conn, codigo, renglones)
    return _leer_detalle(codigo)


@router.post("/{codigo}/terminar", response_model=IngresoOut)
def terminar_ingreso(codigo: int) -> dict[str, Any]:
    with db.transaction() as conn:
        if repo.obtener(conn, codigo) is None:
            raise ApiError(404, "NO_ENCONTRADO", f"El ingreso {codigo} no existe")
        repo.cambiar_estado(conn, codigo, "terminado")
    return _leer_detalle(codigo)


@router.post("/{codigo}/procesar", response_model=IngresoOut)
def procesar_ingreso(codigo: int) -> dict[str, Any]:
    with db.transaction() as conn:
        if repo.obtener(conn, codigo) is None:
            raise ApiError(404, "NO_ENCONTRADO", f"El ingreso {codigo} no existe")
        repo.procesar(conn, codigo)
    return _leer_detalle(codigo)
