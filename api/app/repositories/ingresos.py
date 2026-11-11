"""Ingresos de mercaderia al deposito central."""

from __future__ import annotations

from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row


def crear(conn: Connection, codigo_transportista: int, cuit_bodega: str) -> dict[str, Any]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            INSERT INTO ingreso (codigo_transportista, cuit_bodega)
            VALUES (%s, %s)
            RETURNING codigo, fecha, estado, codigo_transportista, cuit_bodega
            """,
            (codigo_transportista, cuit_bodega),
        )
        return cur.fetchone()


def obtener(conn: Connection, codigo: int) -> dict[str, Any] | None:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT codigo, fecha, estado, codigo_transportista, cuit_bodega
            FROM ingreso
            WHERE codigo = %s
            """,
            (codigo,),
        )
        return cur.fetchone()


def insertar_renglones(
    conn: Connection, codigo: int, renglones: list[dict[str, Any]]
) -> None:
    with conn.cursor() as cur:
        cur.executemany(
            """
            INSERT INTO renglon_ingreso (codigo_ingreso, codigo_vino, cantidad)
            VALUES (%s, %s, %s)
            """,
            [
                (codigo, renglon["codigo_vino"], renglon["cantidad"])
                for renglon in renglones
            ],
        )


def obtener_renglones(conn: Connection, codigo: int) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT
                ri.codigo_vino,
                v.nombre AS nombre_vino,
                ri.cantidad
            FROM renglon_ingreso ri
            JOIN vino v ON v.codigo = ri.codigo_vino
            WHERE ri.codigo_ingreso = %s
            ORDER BY ri.codigo_vino
            """,
            (codigo,),
        )
        return cur.fetchall()


def cambiar_estado(conn: Connection, codigo: int, estado: str) -> dict[str, Any] | None:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            UPDATE ingreso
            SET estado = %s
            WHERE codigo = %s
            RETURNING codigo, fecha, estado, codigo_transportista, cuit_bodega
            """,
            (estado, codigo),
        )
        return cur.fetchone()


def procesar(conn: Connection, codigo: int) -> None:
    with conn.cursor() as cur:
        cur.execute("CALL p_procesar_ingreso(%s)", (codigo,))
