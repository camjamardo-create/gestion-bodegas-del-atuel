"""Fixtures y limpieza de las pruebas de la API."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Iterator

import pytest
from fastapi.testclient import TestClient
from psycopg.rows import dict_row

from app import db
from app.main import app


@dataclass
class Creados:
    vinos: list[int] = field(default_factory=list)
    clientes: list[int] = field(default_factory=list)
    comprobantes: list[int] = field(default_factory=list)
    transferencias: list[int] = field(default_factory=list)
    ingresos: list[int] = field(default_factory=list)


@pytest.fixture(scope="session")
def client() -> Iterator[TestClient]:
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture(scope="session")
def catalogo(client: TestClient) -> dict[str, Any]:
    with db.connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT
                    (SELECT cuit FROM bodega ORDER BY cuit LIMIT 1) AS cuit_bodega,
                    (SELECT codigo FROM transportista ORDER BY codigo LIMIT 1) AS codigo_transportista,
                    (SELECT id FROM sala_venta ORDER BY id LIMIT 1) AS id_sala,
                    (SELECT codigo_postal FROM localidad ORDER BY codigo_postal LIMIT 1) AS codigo_postal
                """
            )
            base = cur.fetchone()

            cur.execute("SELECT id FROM cepa ORDER BY id LIMIT 2")
            cepas = [fila["id"] for fila in cur.fetchall()]

            cur.execute("SELECT id FROM maridaje ORDER BY id LIMIT 1")
            maridaje = cur.fetchone()

    if not base or not all(
        [base["cuit_bodega"], base["codigo_transportista"], base["id_sala"], base["codigo_postal"]]
    ):
        pytest.skip("Falta el catalogo minimo: ejecute docker compose up para inicializar la base")
    if len(cepas) < 2:
        pytest.skip("Se necesitan al menos dos cepas para probar la composicion de vinos")

    return {
        "cuit_bodega": base["cuit_bodega"],
        "codigo_transportista": base["codigo_transportista"],
        "id_sala": base["id_sala"],
        "codigo_postal": base["codigo_postal"],
        "cepa_ids": cepas,
        "id_maridaje": maridaje["id"] if maridaje else None,
    }


@pytest.fixture
def creados() -> Iterator[Creados]:
    ctx = Creados()
    try:
        yield ctx
    finally:
        limpiar(ctx)


def limpiar(ctx: Creados) -> None:
    """Borra solo las filas creadas por la prueba, respetando las FKs."""
    with db.transaction() as conn:
        with conn.cursor() as cur:
            if ctx.comprobantes:
                cur.execute(
                    "DELETE FROM comprobante WHERE numero = ANY(%s)",
                    (ctx.comprobantes,),
                )
            if ctx.transferencias:
                cur.execute(
                    "DELETE FROM transferencia WHERE numero = ANY(%s)",
                    (ctx.transferencias,),
                )
            if ctx.ingresos:
                cur.execute(
                    "DELETE FROM ingreso WHERE codigo = ANY(%s)",
                    (ctx.ingresos,),
                )
            if ctx.vinos:
                cur.execute(
                    "DELETE FROM stock_sala WHERE codigo_vino = ANY(%s)",
                    (ctx.vinos,),
                )
                cur.execute(
                    "DELETE FROM stock_deposito WHERE codigo_vino = ANY(%s)",
                    (ctx.vinos,),
                )
                cur.execute("DELETE FROM vino WHERE codigo = ANY(%s)", (ctx.vinos,))
            if ctx.clientes:
                cur.execute("DELETE FROM cliente WHERE id = ANY(%s)", (ctx.clientes,))
