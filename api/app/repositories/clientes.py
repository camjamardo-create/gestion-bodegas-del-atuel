"""Consultas de clientes y de su jerarquia supertipo/subtipos."""

from __future__ import annotations

from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row

_CAMPOS = """
    c.id,
    c.tipo,
    c.nombre,
    c.apellido,
    c.razon_social,
    c.calle,
    c.numero,
    c.codigo_postal,
    c.tipo_documento,
    c.numero_documento,
    c.estado_activo,
    c.fecha_alta,
    d.zona_cobertura,
    d.numero_habilitacion,
    e.pais_destino,
    e.descuento_especial
"""

_JOINS = """
    LEFT JOIN cliente_comun cc ON cc.id_cliente = c.id
    LEFT JOIN socio_club sc ON sc.id_cliente = c.id
    LEFT JOIN distribuidor d ON d.id_cliente = c.id
    LEFT JOIN exportador e ON e.id_cliente = c.id
"""


def listar(
    conn: Connection,
    *,
    tipo: str | None,
    estado_activo: bool | None,
    documento: str | None,
    page: int,
    page_size: int,
) -> tuple[list[dict[str, Any]], int]:
    condiciones: list[str] = []
    parametros: list[Any] = []

    if tipo:
        condiciones.append("c.tipo = %s")
        parametros.append(tipo)
    if estado_activo is not None:
        condiciones.append("c.estado_activo = %s")
        parametros.append(estado_activo)
    if documento:
        condiciones.append("c.numero_documento ILIKE %s")
        parametros.append(f"%{documento}%")

    where = f"WHERE {' AND '.join(condiciones)}" if condiciones else ""

    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(f"SELECT COUNT(*) AS total FROM cliente c {where}", parametros)
        total = int(cur.fetchone()["total"])

        cur.execute(
            f"""
            SELECT {_CAMPOS}
            FROM cliente c
            {_JOINS}
            {where}
            ORDER BY c.id
            LIMIT %s OFFSET %s
            """,
            [*parametros, page_size, (page - 1) * page_size],
        )
        filas = cur.fetchall()
    return filas, total


def obtener(conn: Connection, id_cliente: int) -> dict[str, Any] | None:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            f"""
            SELECT {_CAMPOS}
            FROM cliente c
            {_JOINS}
            WHERE c.id = %s
            """,
            (id_cliente,),
        )
        return cur.fetchone()


def obtener_permisos(conn: Connection, id_cliente: int) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT codigo, fecha_emision, fecha_vencimiento
            FROM permiso
            WHERE id_exportador = %s
            ORDER BY codigo
            """,
            (id_cliente,),
        )
        return cur.fetchall()


def crear_con_procedimiento(conn: Connection, datos: dict[str, Any]) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            CALL p_crear_cliente(
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
            )
            """,
            (
                datos["tipo"],
                datos["calle"],
                datos["numero"],
                datos["codigo_postal"],
                datos["tipo_documento"],
                datos["numero_documento"],
                datos["nombre"],
                datos["apellido"],
                datos["razon_social"],
                datos["zona_cobertura"],
                datos["numero_habilitacion"],
                datos["pais_destino"],
                datos["descuento_especial"],
            ),
        )


def cambiar_tipo_con_procedimiento(conn: Connection, datos: dict[str, Any]) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            CALL p_cambiar_tipo_cliente(
                %s, %s, %s, %s, %s, %s, %s, %s, %s
            )
            """,
            (
                datos["id_cliente"],
                datos["tipo"],
                datos["nombre"],
                datos["apellido"],
                datos["razon_social"],
                datos["zona_cobertura"],
                datos["numero_habilitacion"],
                datos["pais_destino"],
                datos["descuento_especial"],
            ),
        )


def id_creado(conn: Connection) -> int:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            "SELECT currval(pg_get_serial_sequence('cliente', 'id')) AS id"
        )
        return int(cur.fetchone()["id"])


def insertar_permisos(
    conn: Connection, id_exportador: int, permisos: list[dict[str, Any]]
) -> None:
    if not permisos:
        return
    with conn.cursor() as cur:
        cur.executemany(
            """
            INSERT INTO permiso (id_exportador, fecha_emision, fecha_vencimiento)
            VALUES (%s, %s, %s)
            """,
            [
                (
                    id_exportador,
                    permiso["fecha_emision"],
                    permiso["fecha_vencimiento"],
                )
                for permiso in permisos
            ],
        )


def borrar_permisos(conn: Connection, id_exportador: int) -> None:
    with conn.cursor() as cur:
        cur.execute("DELETE FROM permiso WHERE id_exportador = %s", (id_exportador,))


def actualizar_base(conn: Connection, id_cliente: int, datos: dict[str, Any]) -> bool:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE cliente
            SET nombre = COALESCE(%s, nombre),
                apellido = COALESCE(%s, apellido),
                razon_social = COALESCE(%s, razon_social),
                calle = COALESCE(%s, calle),
                numero = COALESCE(%s, numero),
                codigo_postal = COALESCE(%s, codigo_postal),
                tipo_documento = COALESCE(%s, tipo_documento),
                numero_documento = COALESCE(%s, numero_documento),
                estado_activo = COALESCE(%s, estado_activo)
            WHERE id = %s
            """,
            (
                datos["nombre"],
                datos["apellido"],
                datos["razon_social"],
                datos["calle"],
                datos["numero"],
                datos["codigo_postal"],
                datos["tipo_documento"],
                datos["numero_documento"],
                datos["estado_activo"],
                id_cliente,
            ),
        )
        return cur.rowcount > 0


def actualizar_distribuidor(
    conn: Connection, id_cliente: int, datos: dict[str, Any]
) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE distribuidor
            SET zona_cobertura = COALESCE(%s, zona_cobertura),
                numero_habilitacion = COALESCE(%s, numero_habilitacion)
            WHERE id_cliente = %s
            """,
            (
                datos["zona_cobertura"],
                datos["numero_habilitacion"],
                id_cliente,
            ),
        )


def actualizar_exportador(
    conn: Connection, id_cliente: int, datos: dict[str, Any]
) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE exportador
            SET pais_destino = COALESCE(%s, pais_destino),
                descuento_especial = COALESCE(%s, descuento_especial)
            WHERE id_cliente = %s
            """,
            (
                datos["pais_destino"],
                datos["descuento_especial"],
                id_cliente,
            ),
        )


def eliminar(conn: Connection, id_cliente: int) -> bool:
    with conn.cursor() as cur:
        cur.execute("DELETE FROM cliente WHERE id = %s", (id_cliente,))
        return cur.rowcount > 0
