"""Consultas de vinos: catalogo, detalle y mantenimiento."""

from __future__ import annotations

from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row

_COLUMNAS = """
    v.codigo,
    v.nombre,
    v.tipo,
    v."añada" AS anada,
    v.volumen_ml,
    v.graduacion,
    v.precio,
    v.cuit_bodega
"""

_ORDEN = {
    "codigo": "v.codigo",
    "nombre": "v.nombre",
    "precio": "v.precio",
    "anada": 'v."añada"',
    "graduacion": "v.graduacion",
}


def listar(
    conn: Connection,
    *,
    tipo: str | None,
    cepa: str | None,
    bodega: str | None,
    anada: int | None,
    nombre: str | None,
    page: int,
    page_size: int,
    orden: str,
    direccion: str,
) -> tuple[list[dict[str, Any]], int]:
    condiciones: list[str] = []
    parametros: list[Any] = []

    if tipo:
        condiciones.append("v.tipo = %s")
        parametros.append(tipo)
    if bodega:
        condiciones.append("v.cuit_bodega = %s")
        parametros.append(bodega)
    if anada is not None:
        condiciones.append('v."añada" = %s')
        parametros.append(anada)
    if nombre:
        condiciones.append("v.nombre ILIKE %s")
        parametros.append(f"%{nombre}%")
    if cepa:
        condiciones.append(
            """
            EXISTS (
                SELECT 1
                FROM composicion co
                JOIN cepa c ON c.id = co.id_cepa
                WHERE co.codigo_vino = v.codigo
                  AND (lower(c.nombre) = lower(%s) OR c.id::text = %s)
            )
            """
        )
        parametros.extend([cepa, cepa])

    where = f"WHERE {' AND '.join(condiciones)}" if condiciones else ""
    columna_orden = _ORDEN.get(orden, "v.codigo")
    sentido = "DESC" if direccion.lower() == "desc" else "ASC"

    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(f"SELECT COUNT(*) AS total FROM vino v {where}", parametros)
        total = int(cur.fetchone()["total"])

        cur.execute(
            f"""
            SELECT {_COLUMNAS}
            FROM vino v
            {where}
            ORDER BY {columna_orden} {sentido}, v.codigo ASC
            LIMIT %s OFFSET %s
            """,
            [*parametros, page_size, (page - 1) * page_size],
        )
        filas = cur.fetchall()

    return filas, total


def obtener(conn: Connection, codigo: int) -> dict[str, Any] | None:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT
                v.codigo,
                v.nombre,
                v.tipo,
                v."añada" AS anada,
                v.volumen_ml,
                v.graduacion,
                v.precio,
                v.cuit_bodega,
                b.cuit AS bodega_cuit,
                b.razon_social AS bodega_razon_social,
                b.calle AS bodega_calle,
                b.numero AS bodega_numero
            FROM vino v
            JOIN bodega b ON b.cuit = v.cuit_bodega
            WHERE v.codigo = %s
            """,
            (codigo,),
        )
        return cur.fetchone()


def obtener_cepas(conn: Connection, codigo: int) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT c.id, c.nombre, c.tipo, co.porcentaje
            FROM composicion co
            JOIN cepa c ON c.id = co.id_cepa
            WHERE co.codigo_vino = %s
            ORDER BY co.porcentaje DESC, c.id
            """,
            (codigo,),
        )
        return cur.fetchall()


def obtener_maridajes(conn: Connection, codigo: int) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT m.id, m.nombre, m.temperatura_servicio
            FROM vino_maridaje vm
            JOIN maridaje m ON m.id = vm.id_maridaje
            WHERE vm.codigo_vino = %s
            ORDER BY m.nombre, m.id
            """,
            (codigo,),
        )
        return cur.fetchall()


def obtener_stock(conn: Connection, codigo: int) -> dict[str, Any]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT
                COALESCE(
                    (SELECT cantidad FROM stock_deposito WHERE codigo_vino = %s),
                    0
                ) AS stock_deposito,
                COALESCE(
                    (SELECT SUM(cantidad) FROM stock_sala WHERE codigo_vino = %s),
                    0
                ) AS stock_sala
            """,
            (codigo, codigo),
        )
        return cur.fetchone()


def crear(conn: Connection, datos: dict[str, Any]) -> int:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            INSERT INTO vino (
                nombre, tipo, "añada", volumen_ml, graduacion, precio, cuit_bodega
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING codigo
            """,
            (
                datos["nombre"],
                datos["tipo"],
                datos["anada"],
                datos["volumen_ml"],
                datos["graduacion"],
                datos["precio"],
                datos["cuit_bodega"],
            ),
        )
        return int(cur.fetchone()["codigo"])


def actualizar(conn: Connection, codigo: int, datos: dict[str, Any]) -> bool:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE vino
            SET nombre = %s,
                tipo = %s,
                "añada" = %s,
                volumen_ml = %s,
                graduacion = %s,
                precio = %s,
                cuit_bodega = %s
            WHERE codigo = %s
            """,
            (
                datos["nombre"],
                datos["tipo"],
                datos["anada"],
                datos["volumen_ml"],
                datos["graduacion"],
                datos["precio"],
                datos["cuit_bodega"],
                codigo,
            ),
        )
        return cur.rowcount > 0


def eliminar(conn: Connection, codigo: int) -> bool:
    with conn.cursor() as cur:
        cur.execute("DELETE FROM vino WHERE codigo = %s", (codigo,))
        return cur.rowcount > 0


def borrar_composicion(conn: Connection, codigo: int) -> None:
    with conn.cursor() as cur:
        cur.execute("DELETE FROM composicion WHERE codigo_vino = %s", (codigo,))


def insertar_composicion(
    conn: Connection, codigo: int, cepas: list[dict[str, Any]]
) -> None:
    if not cepas:
        return
    with conn.cursor() as cur:
        cur.executemany(
            """
            INSERT INTO composicion (codigo_vino, id_cepa, porcentaje)
            VALUES (%s, %s, %s)
            """,
            [(codigo, cepa["id_cepa"], cepa["porcentaje"]) for cepa in cepas],
        )


def borrar_maridajes(conn: Connection, codigo: int) -> None:
    with conn.cursor() as cur:
        cur.execute("DELETE FROM vino_maridaje WHERE codigo_vino = %s", (codigo,))


def insertar_maridajes(conn: Connection, codigo: int, maridajes: list[int]) -> None:
    if not maridajes:
        return
    with conn.cursor() as cur:
        cur.executemany(
            "INSERT INTO vino_maridaje (codigo_vino, id_maridaje) VALUES (%s, %s)",
            [(codigo, id_maridaje) for id_maridaje in maridajes],
        )
