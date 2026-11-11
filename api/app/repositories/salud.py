"""Comprobacion de conectividad de la base."""

from __future__ import annotations

from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row


def comprobar(conn: Connection) -> dict[str, Any]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute("SELECT 1 AS ok, current_user AS current_user")
        return cur.fetchone()
