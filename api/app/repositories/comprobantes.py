"""Ventas: cabecera y renglones de comprobante.

La API no calcula subtotales, descuentos, totales ni stock. Solo inserta la
cabecera y los renglones; los triggers y funciones de la base hacen el resto.
"""

from __future__ import annotations

from datetime import date
from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row


def crear_cabecera(
    conn: Connection,
    *,
    id_cliente: int,
    id_sala_venta: int,
    fecha: date | None,
) -> int:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            INSERT INTO comprobante (fecha, id_cliente, id_sala_venta)
            VALUES (COALESCE(%s, CURRENT_DATE), %s, %s)
            RETURNING numero
            """,
            (fecha, id_cliente, id_sala_venta),
        )
        return int(cur.fetchone()["numero"])


def insertar_renglones(
    conn: Connection, numero: int, renglones: list[dict[str, Any]]
) -> None:
    with conn.cursor() as cur:
        cur.executemany(
            """
            INSERT INTO renglon_comprobante (numero_comprobante, codigo_vino, cantidad)
            VALUES (%s, %s, %s)
            """,
            [
                (numero, renglon["codigo_vino"], renglon["cantidad"])
                for renglon in renglones
            ],
        )


def obtener(conn: Connection, numero: int) -> dict[str, Any] | None:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT
                c.numero,
                c.fecha,
                c.subtotal,
                c.descuento_aplicado,
                c.descuento_total,
                c.total,
                cl.id AS cliente_id,
                cl.tipo AS cliente_tipo,
                cl.nombre AS cliente_nombre,
                cl.apellido AS cliente_apellido,
                cl.razon_social AS cliente_razon_social,
                s.id AS sala_id,
                s.calle AS sala_calle,
                s.numero AS sala_numero
            FROM comprobante c
            JOIN cliente cl ON cl.id = c.id_cliente
            JOIN sala_venta s ON s.id = c.id_sala_venta
            WHERE c.numero = %s
            """,
            (numero,),
        )
        return cur.fetchone()


def obtener_renglones(conn: Connection, numero: int) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT
                rc.codigo_vino,
                v.nombre AS nombre_vino,
                rc.cantidad,
                rc.precio_unitario,
                rc.subtotal_renglon
            FROM renglon_comprobante rc
            JOIN vino v ON v.codigo = rc.codigo_vino
            WHERE rc.numero_comprobante = %s
            ORDER BY rc.codigo_vino
            """,
            (numero,),
        )
        return cur.fetchall()
