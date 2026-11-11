"""Endpoints de clientes con los cuatro subtipos del diseno."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query, Response

from .. import db
from ..errors import ApiError
from ..repositories import clientes as repo
from ..schemas import (
    ClienteCreate,
    ClienteListaOut,
    ClienteOut,
    ClienteUpdate,
    TipoCliente,
)

router = APIRouter(prefix="/clientes", tags=["Clientes"])


def _detalle(conn: Any, id_cliente: int) -> dict[str, Any] | None:
    fila = repo.obtener(conn, id_cliente)
    if fila is None:
        return None
    fila = dict(fila)
    if fila["tipo"] == "exportador":
        fila["permisos"] = repo.obtener_permisos(conn, id_cliente)
    else:
        fila["permisos"] = []
    return fila


def _leer_detalle(id_cliente: int) -> dict[str, Any]:
    with db.connection() as conn:
        detalle = _detalle(conn, id_cliente)
    if detalle is None:
        raise ApiError(404, "NO_ENCONTRADO", f"El cliente {id_cliente} no existe")
    return detalle


def _validar_permisos(tipo: str, permisos: list[Any]) -> None:
    if permisos and tipo != "exportador":
        raise ApiError(
            422,
            "VALIDACION",
            "Solo un cliente exportador puede tener permisos de exportacion",
        )


@router.get("", response_model=ClienteListaOut)
def listar_clientes(
    tipo: TipoCliente | None = Query(default=None),
    estado_activo: bool | None = Query(default=None),
    documento: str | None = Query(default=None),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
) -> dict[str, Any]:
    with db.connection() as conn:
        filas, total = repo.listar(
            conn,
            tipo=tipo,
            estado_activo=estado_activo,
            documento=documento,
            page=page,
            page_size=page_size,
        )
    return {"items": filas, "total": total, "page": page, "page_size": page_size}


@router.get("/{id_cliente}", response_model=ClienteOut)
def obtener_cliente(id_cliente: int) -> dict[str, Any]:
    return _leer_detalle(id_cliente)


@router.post("", response_model=ClienteOut, status_code=201)
def crear_cliente(payload: ClienteCreate) -> dict[str, Any]:
    _validar_permisos(payload.tipo, payload.permisos)
    datos = payload.model_dump(exclude={"permisos"})
    with db.transaction() as conn:
        repo.crear_con_procedimiento(conn, datos)
        id_cliente = repo.id_creado(conn)
        repo.insertar_permisos(
            conn, id_cliente, [p.model_dump() for p in payload.permisos]
        )
    return _leer_detalle(id_cliente)


@router.put("/{id_cliente}", response_model=ClienteOut)
def actualizar_cliente(id_cliente: int, payload: ClienteUpdate) -> dict[str, Any]:
    with db.transaction() as conn:
        actual = repo.obtener(conn, id_cliente)
        if actual is None:
            raise ApiError(404, "NO_ENCONTRADO", f"El cliente {id_cliente} no existe")

        nuevo_tipo = payload.tipo or actual["tipo"]
        _validar_permisos(nuevo_tipo, payload.permisos or [])
        permisos = None if payload.permisos is None else [p.model_dump() for p in payload.permisos]

        if nuevo_tipo != actual["tipo"]:
            datos_cambio = {
                "id_cliente": id_cliente,
                "tipo": nuevo_tipo,
                "nombre": payload.nombre if payload.nombre is not None else actual["nombre"],
                "apellido": payload.apellido if payload.apellido is not None else actual["apellido"],
                "razon_social": (
                    payload.razon_social
                    if payload.razon_social is not None
                    else actual["razon_social"]
                ),
                "zona_cobertura": (
                    payload.zona_cobertura
                    if payload.zona_cobertura is not None
                    else actual["zona_cobertura"]
                ),
                "numero_habilitacion": (
                    payload.numero_habilitacion
                    if payload.numero_habilitacion is not None
                    else actual["numero_habilitacion"]
                ),
                "pais_destino": (
                    payload.pais_destino
                    if payload.pais_destino is not None
                    else actual["pais_destino"]
                ),
                "descuento_especial": (
                    payload.descuento_especial
                    if payload.descuento_especial is not None
                    else actual["descuento_especial"]
                ),
            }
            repo.cambiar_tipo_con_procedimiento(conn, datos_cambio)
            nuevo_id = repo.id_creado(conn)

            # El procedimiento copia los datos base del cliente anterior. Si el
            # PUT trae correcciones de calle, documento o estado, se aplican
            # sobre la fila nueva dentro de la misma transaccion.
            repo.actualizar_base(
                conn,
                nuevo_id,
                {
                    "nombre": payload.nombre,
                    "apellido": payload.apellido,
                    "razon_social": payload.razon_social,
                    "calle": payload.calle,
                    "numero": payload.numero,
                    "codigo_postal": payload.codigo_postal,
                    "tipo_documento": payload.tipo_documento,
                    "numero_documento": payload.numero_documento,
                    "estado_activo": payload.estado_activo,
                },
            )
            if permisos is not None:
                repo.borrar_permisos(conn, nuevo_id)
                repo.insertar_permisos(conn, nuevo_id, permisos)
            id_cliente = nuevo_id
        else:
            repo.actualizar_base(
                conn,
                id_cliente,
                {
                    "nombre": payload.nombre,
                    "apellido": payload.apellido,
                    "razon_social": payload.razon_social,
                    "calle": payload.calle,
                    "numero": payload.numero,
                    "codigo_postal": payload.codigo_postal,
                    "tipo_documento": payload.tipo_documento,
                    "numero_documento": payload.numero_documento,
                    "estado_activo": payload.estado_activo,
                },
            )
            if nuevo_tipo == "distribuidor":
                repo.actualizar_distribuidor(
                    conn,
                    id_cliente,
                    {
                        "zona_cobertura": payload.zona_cobertura,
                        "numero_habilitacion": payload.numero_habilitacion,
                    },
                )
            elif nuevo_tipo == "exportador":
                repo.actualizar_exportador(
                    conn,
                    id_cliente,
                    {
                        "pais_destino": payload.pais_destino,
                        "descuento_especial": payload.descuento_especial,
                    },
                )
            if permisos is not None:
                repo.borrar_permisos(conn, id_cliente)
                repo.insertar_permisos(conn, id_cliente, permisos)

    return _leer_detalle(id_cliente)


@router.delete("/{id_cliente}", status_code=204)
def eliminar_cliente(id_cliente: int) -> Response:
    with db.transaction() as conn:
        if not repo.eliminar(conn, id_cliente):
            raise ApiError(404, "NO_ENCONTRADO", f"El cliente {id_cliente} no existe")
    return Response(status_code=204)
