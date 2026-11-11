"""Transferencias de stock entre deposito y salas."""

from __future__ import annotations

from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row


def crear(conn: Connection, id_sala_venta: int) -> dict[str, Any]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            INSERT INTO transferencia (id_sala_venta)
            VALUES (%s)
            RETURNING numero, fecha_confeccion, estado, id_sala_venta
            """,
            (id_sala_venta,),
        )
        return cur.fetchone()


def obtener(conn: Connection, numero: int) -> dict[str, Any] | None:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT numero, fecha_confeccion, estado, id_sala_venta
            FROM transferencia
            WHERE numero = %s
            """,
            (numero,),
        )
        return cur.fetchone()


def insertar_renglones(
    conn: Connection, numero: int, renglones: list[dict[str, Any]]
) -> None:
    with conn.cursor() as cur:
        cur.executemany(
            """
            INSERT INTO renglon_transferencia (numero_transferencia, codigo_vino, cantidad)
            VALUES (%s, %s, %s)
            """,
            [
                (numero, renglon["codigo_vino"], renglon["cantidad"])
                for renglon in renglones
            ],
        )


def obtener_renglones(conn: Connection, numero: int) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT
                rt.codigo_vino,
                v.nombre AS nombre_vino,
                rt.cantidad
            FROM renglon_transferencia rt
            JOIN vino v ON v.codigo = rt.codigo_vino
            WHERE rt.numero_transferencia = %s
            ORDER BY rt.codigo_vino
            """,
            (numero,),
        )
        return cur.fetchall()


def cambiar_estado(conn: Connection, numero: int, estado: str) -> dict[str, Any] | None:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            UPDATE transferencia
            SET estado = %s
            WHERE numero = %s
            RETURNING numero, fecha_confeccion, estado, id_sala_venta
            """,
            (estado, numero),
        )
        return cur.fetchone()


def procesar(conn: Connection, numero: int) -> None:
    with conn.cursor() as cur:
        cur.execute("CALL p_procesar_transferencia(%s)", (numero,))
