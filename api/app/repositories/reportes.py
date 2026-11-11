"""Consultas de reportes S1, S6, S7, S8 y S9 de la Etapa 5.

Se reutiliza la logica de consultas/select.sql, parametrizando solo los
valores que en el archivo original eran literales.
"""

from __future__ import annotations

from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row


def top_vinos(conn: Connection) -> list[dict[str, Any]]:
    """S1: ranking de los 10 vinos con mas botellas vendidas."""
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT rc.codigo_vino,
                   v.nombre,
                   SUM(rc.cantidad) AS botellas_vendidas
            FROM renglon_comprobante rc
            JOIN vino v ON v.codigo = rc.codigo_vino
            GROUP BY rc.codigo_vino, v.nombre
            ORDER BY botellas_vendidas DESC
            LIMIT 10
            """
        )
        return cur.fetchall()


def ventas_por_sala(conn: Connection) -> list[dict[str, Any]]:
    """S8: monto total de ventas por sala en el ultimo trimestre."""
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT s.id AS id_sala,
                   s.calle,
                   s.numero,
                   SUM(co.total) AS monto_total
            FROM comprobante co
            JOIN sala_venta s ON s.id = co.id_sala_venta
            WHERE co.fecha >= CURRENT_DATE - INTERVAL '3 months'
            GROUP BY s.id, s.calle, s.numero
            ORDER BY monto_total DESC
            """
        )
        return cur.fetchall()


def vinos_sin_stock(conn: Connection, id_sala: int) -> list[dict[str, Any]]:
    """S6: vinos sin stock en una sala pero con stock en el deposito."""
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT v.codigo,
                   v.nombre,
                   sd.cantidad AS stock_deposito
            FROM vino v
            JOIN stock_deposito sd ON sd.codigo_vino = v.codigo
            LEFT JOIN stock_sala ss
                   ON ss.codigo_vino = v.codigo
                  AND ss.id_sala = %s
            WHERE sd.cantidad > 0
              AND COALESCE(ss.cantidad, 0) = 0
            ORDER BY v.codigo
            """,
            (id_sala,),
        )
        return cur.fetchall()


def transportista_activo(conn: Connection) -> dict[str, Any] | None:
    """S7: transportista con mayor actividad en el ultimo mes."""
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT t.codigo,
                   t.razon_social,
                   COUNT(DISTINCT i.codigo) AS ingresos,
                   COALESCE(SUM(ri.cantidad), 0) AS botellas
            FROM transportista t
            JOIN ingreso i ON i.codigo_transportista = t.codigo
            LEFT JOIN renglon_ingreso ri ON ri.codigo_ingreso = i.codigo
            WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
            GROUP BY t.codigo, t.razon_social
            ORDER BY ingresos DESC, botellas DESC, t.codigo
            LIMIT 1
            """
        )
        return cur.fetchone()


def trazabilidad_vino(conn: Connection, codigo: int) -> dict[str, Any] | None:
    """S9: ficha del vino con cepas, bodega, maridajes y stock total."""
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT v.codigo,
                   v.nombre,
                   b.razon_social AS bodega,
                   (SELECT STRING_AGG(c.nombre || ' ' || co.porcentaje || '%%', ', '
                                      ORDER BY co.porcentaje DESC)
                      FROM composicion co
                      JOIN cepa c ON c.id = co.id_cepa
                     WHERE co.codigo_vino = v.codigo) AS cepas,
                   (SELECT STRING_AGG(m.nombre, ', ' ORDER BY m.nombre)
                      FROM vino_maridaje vm
                      JOIN maridaje m ON m.id = vm.id_maridaje
                     WHERE vm.codigo_vino = v.codigo) AS maridajes,
                   (SELECT COALESCE(SUM(cantidad), 0)
                      FROM stock_deposito
                     WHERE codigo_vino = v.codigo)
                 + (SELECT COALESCE(SUM(cantidad), 0)
                      FROM stock_sala
                     WHERE codigo_vino = v.codigo) AS stock_total
            FROM vino v
            JOIN bodega b ON b.cuit = v.cuit_bodega
            WHERE v.codigo = %s
            """,
            (codigo,),
        )
        return cur.fetchone()
