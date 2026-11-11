"""Funciones auxiliares para las pruebas de integracion."""

from __future__ import annotations

import uuid
from decimal import Decimal
from typing import Any

from fastapi.testclient import TestClient
from psycopg.rows import dict_row

from app import db

from .conftest import Creados


def sufijo() -> str:
    return uuid.uuid4().hex[:12]


def crear_vino(
    client: TestClient,
    ctx: Creados,
    catalogo: dict[str, Any],
    *,
    nombre: str | None = None,
    precio: str = "1000.00",
    cepas: list[dict[str, Any]] | None = None,
    maridajes: list[int] | None = None,
) -> dict[str, Any]:
    nombre = nombre or f"API TEST {sufijo()}"
    if cepas is None:
        cepas = [
            {"id_cepa": catalogo["cepa_ids"][0], "porcentaje": "60.00"},
            {"id_cepa": catalogo["cepa_ids"][1], "porcentaje": "40.00"},
        ]
    if maridajes is None:
        maridajes = [catalogo["id_maridaje"]] if catalogo["id_maridaje"] else []

    respuesta = client.post(
        "/vinos",
        json={
            "nombre": nombre,
            "tipo": "tinto",
            "anada": 2024,
            "volumen_ml": 750,
            "graduacion": "13.50",
            "precio": precio,
            "cuit_bodega": catalogo["cuit_bodega"],
            "cepas": cepas,
            "maridajes": maridajes,
        },
    )
    assert respuesta.status_code == 201, respuesta.text
    datos = respuesta.json()
    ctx.vinos.append(datos["codigo"])
    return datos


def crear_cliente(
    client: TestClient,
    ctx: Creados,
    catalogo: dict[str, Any],
    *,
    tipo: str = "cliente_comun",
) -> dict[str, Any]:
    documento = f"API-{sufijo()}"
    payload: dict[str, Any] = {
        "tipo": tipo,
        "calle": "Calle Prueba",
        "numero": "123",
        "codigo_postal": catalogo["codigo_postal"],
        "tipo_documento": "DNI",
        "numero_documento": documento,
    }
    if tipo in {"cliente_comun", "socio_club"}:
        payload["nombre"] = "Nombre"
        payload["apellido"] = "Apellido"
    elif tipo == "distribuidor":
        payload["razon_social"] = f"Distribuidora {documento}"
        payload["zona_cobertura"] = "Zona Sur"
        payload["numero_habilitacion"] = "HAB-001"
    elif tipo == "exportador":
        payload["razon_social"] = f"Exportadora {documento}"
        payload["pais_destino"] = "Brasil"
        payload["descuento_especial"] = "0.35"
        payload["permisos"] = [
            {
                "fecha_emision": "2025-01-01",
                "fecha_vencimiento": "2027-12-31",
            }
        ]

    respuesta = client.post("/clientes", json=payload)
    assert respuesta.status_code == 201, respuesta.text
    datos = respuesta.json()
    ctx.clientes.append(datos["id"])
    return datos


def crear_stock(
    client: TestClient,
    ctx: Creados,
    catalogo: dict[str, Any],
    *,
    codigo_vino: int,
    cantidad: int,
) -> None:
    ingreso = client.post(
        "/ingresos",
        json={
            "codigo_transportista": catalogo["codigo_transportista"],
            "cuit_bodega": catalogo["cuit_bodega"],
        },
    )
    assert ingreso.status_code == 201, ingreso.text
    codigo_ingreso = ingreso.json()["codigo"]
    ctx.ingresos.append(codigo_ingreso)

    renglon_ingreso = client.post(
        f"/ingresos/{codigo_ingreso}/renglones",
        json={"codigo_vino": codigo_vino, "cantidad": cantidad},
    )
    assert renglon_ingreso.status_code == 200, renglon_ingreso.text

    terminar_ingreso = client.post(f"/ingresos/{codigo_ingreso}/terminar")
    assert terminar_ingreso.status_code == 200, terminar_ingreso.text

    procesar_ingreso = client.post(f"/ingresos/{codigo_ingreso}/procesar")
    assert procesar_ingreso.status_code == 200, procesar_ingreso.text

    transferencia = client.post(
        "/transferencias", json={"id_sala_venta": catalogo["id_sala"]}
    )
    assert transferencia.status_code == 201, transferencia.text
    numero_transferencia = transferencia.json()["numero"]
    ctx.transferencias.append(numero_transferencia)

    renglon_transferencia = client.post(
        f"/transferencias/{numero_transferencia}/renglones",
        json={"codigo_vino": codigo_vino, "cantidad": cantidad},
    )
    assert renglon_transferencia.status_code == 200, renglon_transferencia.text

    terminar_transferencia = client.post(f"/transferencias/{numero_transferencia}/terminar")
    assert terminar_transferencia.status_code == 200, terminar_transferencia.text

    procesar_transferencia = client.post(f"/transferencias/{numero_transferencia}/procesar")
    assert procesar_transferencia.status_code == 200, procesar_transferencia.text


def stock_sala(id_sala: int, codigo_vino: int) -> int:
    with db.connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT cantidad FROM stock_sala WHERE id_sala = %s AND codigo_vino = %s",
                (id_sala, codigo_vino),
            )
            fila = cur.fetchone()
    return int(fila["cantidad"]) if fila else 0


def stock_deposito(codigo_vino: int) -> int:
    with db.connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT cantidad FROM stock_deposito WHERE codigo_vino = %s",
                (codigo_vino,),
            )
            fila = cur.fetchone()
    return int(fila["cantidad"]) if fila else 0


def contar_comprobantes_cliente(id_cliente: int) -> int:
    with db.connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT COUNT(*) AS total FROM comprobante WHERE id_cliente = %s",
                (id_cliente,),
            )
            return int(cur.fetchone()["total"])


def existe_vino(nombre: str) -> bool:
    with db.connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT 1 AS existe FROM vino WHERE nombre = %s", (nombre,))
            return cur.fetchone() is not None


def total_comprobante_bd(numero: int) -> Decimal:
    with db.connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT fn_total_comprobante(%s) AS total",
                (numero,),
            )
            return cur.fetchone()["total"]
