"""Endpoints de vinos."""

from __future__ import annotations

from typing import Any, Literal

from fastapi import APIRouter, Query, Response

from .. import db
from ..errors import ApiError
from ..repositories import vinos as repo
from ..schemas import TipoVino, VinoCreate, VinoDetalleOut, VinoListaOut, VinoUpdate

router = APIRouter(prefix="/vinos", tags=["Vinos"])


def _detalle(conn: Any, codigo: int) -> dict[str, Any] | None:
    fila = repo.obtener(conn, codigo)
    if fila is None:
        return None
    stock = repo.obtener_stock(conn, codigo)
    return {
        "codigo": fila["codigo"],
        "nombre": fila["nombre"],
        "tipo": fila["tipo"],
        "anada": fila["anada"],
        "volumen_ml": fila["volumen_ml"],
        "graduacion": fila["graduacion"],
        "precio": fila["precio"],
        "cuit_bodega": fila["cuit_bodega"],
        "bodega": {
            "cuit": fila["bodega_cuit"],
            "razon_social": fila["bodega_razon_social"],
            "calle": fila["bodega_calle"],
            "numero": fila["bodega_numero"],
        },
        "cepas": repo.obtener_cepas(conn, codigo),
        "maridajes": repo.obtener_maridajes(conn, codigo),
        "stock_deposito": stock["stock_deposito"],
        "stock_sala": stock["stock_sala"],
        "stock_total": stock["stock_deposito"] + stock["stock_sala"],
    }


def _leer_detalle(codigo: int) -> dict[str, Any]:
    with db.connection() as conn:
        detalle = _detalle(conn, codigo)
    if detalle is None:
        raise ApiError(404, "NO_ENCONTRADO", f"El vino {codigo} no existe")
    return detalle


@router.get("", response_model=VinoListaOut)
def listar_vinos(
    tipo: TipoVino | None = Query(default=None),
    cepa: str | None = Query(default=None, description="Nombre o id de cepa"),
    bodega: str | None = Query(default=None, description="CUIT de la bodega"),
    anada: int | None = Query(default=None),
    nombre: str | None = Query(default=None),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    orden: Literal["codigo", "nombre", "precio", "anada", "graduacion"] = Query(
        default="codigo"
    ),
    direccion: Literal["asc", "desc"] = Query(default="asc"),
) -> dict[str, Any]:
    with db.connection() as conn:
        filas, total = repo.listar(
            conn,
            tipo=tipo,
            cepa=cepa,
            bodega=bodega,
            anada=anada,
            nombre=nombre,
            page=page,
            page_size=page_size,
            orden=orden,
            direccion=direccion,
        )
    return {"items": filas, "total": total, "page": page, "page_size": page_size}


@router.get("/{codigo}", response_model=VinoDetalleOut)
def obtener_vino(codigo: int) -> dict[str, Any]:
    return _leer_detalle(codigo)


@router.post("", response_model=VinoDetalleOut, status_code=201)
def crear_vino(payload: VinoCreate) -> dict[str, Any]:
    datos = payload.model_dump(exclude={"cepas", "maridajes"})
    with db.transaction() as conn:
        codigo = repo.crear(conn, datos)
        repo.insertar_composicion(conn, codigo, [c.model_dump() for c in payload.cepas])
        repo.insertar_maridajes(conn, codigo, payload.maridajes)
    return _leer_detalle(codigo)


@router.put("/{codigo}", response_model=VinoDetalleOut)
def actualizar_vino(codigo: int, payload: VinoUpdate) -> dict[str, Any]:
    with db.transaction() as conn:
        actual = repo.obtener(conn, codigo)
        if actual is None:
            raise ApiError(404, "NO_ENCONTRADO", f"El vino {codigo} no existe")

        datos = {
            "nombre": actual["nombre"],
            "tipo": actual["tipo"],
            "anada": actual["anada"],
            "volumen_ml": actual["volumen_ml"],
            "graduacion": actual["graduacion"],
            "precio": actual["precio"],
            "cuit_bodega": actual["cuit_bodega"],
        }
        datos.update(payload.model_dump(exclude_none=True, exclude={"cepas", "maridajes"}))
        repo.actualizar(conn, codigo, datos)

        if payload.cepas is not None:
            repo.borrar_composicion(conn, codigo)
            repo.insertar_composicion(
                conn, codigo, [c.model_dump() for c in payload.cepas]
            )
        if payload.maridajes is not None:
            repo.borrar_maridajes(conn, codigo)
            repo.insertar_maridajes(conn, codigo, payload.maridajes)

    return _leer_detalle(codigo)


@router.delete("/{codigo}", status_code=204)
def eliminar_vino(codigo: int) -> Response:
    with db.transaction() as conn:
        if not repo.eliminar(conn, codigo):
            raise ApiError(404, "NO_ENCONTRADO", f"El vino {codigo} no existe")
    return Response(status_code=204)
