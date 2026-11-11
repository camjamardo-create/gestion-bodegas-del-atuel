"""Endpoints de comprobantes de venta."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter

from .. import db
from ..errors import ApiError
from ..repositories import comprobantes as repo
from ..schemas import ComprobanteCreate, ComprobanteOut

router = APIRouter(prefix="/comprobantes", tags=["Comprobantes"])


def _detalle(conn: Any, numero: int) -> dict[str, Any] | None:
    fila = repo.obtener(conn, numero)
    if fila is None:
        return None
    return {
        "numero": fila["numero"],
        "fecha": fila["fecha"],
        "subtotal": fila["subtotal"],
        "descuento_aplicado": fila["descuento_aplicado"],
        "descuento_total": fila["descuento_total"],
        "total": fila["total"],
        "cliente": {
            "id": fila["cliente_id"],
            "tipo": fila["cliente_tipo"],
            "nombre": fila["cliente_nombre"],
            "apellido": fila["cliente_apellido"],
            "razon_social": fila["cliente_razon_social"],
        },
        "sala": {
            "id": fila["sala_id"],
            "calle": fila["sala_calle"],
            "numero": fila["sala_numero"],
        },
        "renglones": repo.obtener_renglones(conn, numero),
    }


def _leer_detalle(numero: int) -> dict[str, Any]:
    with db.connection() as conn:
        detalle = _detalle(conn, numero)
    if detalle is None:
        raise ApiError(404, "NO_ENCONTRADO", f"El comprobante {numero} no existe")
    return detalle


@router.post("", response_model=ComprobanteOut, status_code=201)
def crear_comprobante(payload: ComprobanteCreate) -> dict[str, Any]:
    with db.transaction() as conn:
        numero = repo.crear_cabecera(
            conn,
            id_cliente=payload.id_cliente,
            id_sala_venta=payload.id_sala_venta,
            fecha=payload.fecha,
        )
        repo.insertar_renglones(
            conn, numero, [r.model_dump() for r in payload.renglones]
        )
    return _leer_detalle(numero)


@router.get("/{numero}", response_model=ComprobanteOut)
def obtener_comprobante(numero: int) -> dict[str, Any]:
    return _leer_detalle(numero)
