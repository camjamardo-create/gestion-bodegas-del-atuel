"""Endpoints de transferencias de stock."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter

from .. import db
from ..errors import ApiError
from ..repositories import transferencias as repo
from ..schemas import RenglonMovimientoIn, TransferenciaCreate, TransferenciaOut

router = APIRouter(prefix="/transferencias", tags=["Transferencias"])


def _detalle(conn: Any, numero: int) -> dict[str, Any] | None:
    fila = repo.obtener(conn, numero)
    if fila is None:
        return None
    return {
        "numero": fila["numero"],
        "fecha_confeccion": fila["fecha_confeccion"],
        "estado": fila["estado"],
        "id_sala_venta": fila["id_sala_venta"],
        "renglones": repo.obtener_renglones(conn, numero),
    }


def _leer_detalle(numero: int) -> dict[str, Any]:
    with db.connection() as conn:
        detalle = _detalle(conn, numero)
    if detalle is None:
        raise ApiError(404, "NO_ENCONTRADO", f"La transferencia {numero} no existe")
    return detalle


def _normalizar_renglones(
    payload: RenglonMovimientoIn | list[RenglonMovimientoIn],
) -> list[dict[str, Any]]:
    renglones = payload if isinstance(payload, list) else [payload]
    return [renglon.model_dump() for renglon in renglones]


@router.post("", response_model=TransferenciaOut, status_code=201)
def crear_transferencia(payload: TransferenciaCreate) -> dict[str, Any]:
    with db.transaction() as conn:
        fila = repo.crear(conn, payload.id_sala_venta)
    return _leer_detalle(fila["numero"])


@router.get("/{numero}", response_model=TransferenciaOut)
def obtener_transferencia(numero: int) -> dict[str, Any]:
    return _leer_detalle(numero)


@router.post("/{numero}/renglones", response_model=TransferenciaOut)
def agregar_renglon(
    numero: int,
    payload: RenglonMovimientoIn | list[RenglonMovimientoIn],
) -> dict[str, Any]:
    renglones = _normalizar_renglones(payload)
    with db.transaction() as conn:
        if repo.obtener(conn, numero) is None:
            raise ApiError(404, "NO_ENCONTRADO", f"La transferencia {numero} no existe")
        repo.insertar_renglones(conn, numero, renglones)
    return _leer_detalle(numero)


@router.post("/{numero}/terminar", response_model=TransferenciaOut)
def terminar_transferencia(numero: int) -> dict[str, Any]:
    with db.transaction() as conn:
        if repo.obtener(conn, numero) is None:
            raise ApiError(404, "NO_ENCONTRADO", f"La transferencia {numero} no existe")
        repo.cambiar_estado(conn, numero, "terminado")
    return _leer_detalle(numero)


@router.post("/{numero}/procesar", response_model=TransferenciaOut)
def procesar_transferencia(numero: int) -> dict[str, Any]:
    with db.transaction() as conn:
        if repo.obtener(conn, numero) is None:
            raise ApiError(404, "NO_ENCONTRADO", f"La transferencia {numero} no existe")
        repo.procesar(conn, numero)
    return _leer_detalle(numero)
