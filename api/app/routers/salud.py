"""Endpoint de salud."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter

from .. import db
from ..repositories import salud as repo
from ..schemas import SaludOut

router = APIRouter(tags=["Salud"])


@router.get("/salud", response_model=SaludOut)
def salud() -> dict[str, Any]:
    with db.connection() as conn:
        fila = repo.comprobar(conn)
    return {
        "status": "ok",
        "base_de_datos": "ok" if fila["ok"] == 1 else "error",
        "current_user": fila["current_user"],
    }
