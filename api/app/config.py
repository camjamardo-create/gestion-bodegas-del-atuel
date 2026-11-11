"""Configuracion de la API.

Toda la configuracion se toma de variables de entorno. No hay credenciales
escritas en el codigo ni en el repositorio.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache

from psycopg.conninfo import make_conninfo

# El rol creado por db/migrations/007_roles.sql. La API nunca debe conectarse
# con el propietario de la base ni con un superusuario.
ROL_API_ESPERADO = "rol_api"
ROLES_PROHIBIDOS = {"postgres", "supabase_admin", "azure_pg_admin", "rdsadmin"}


def _entero(nombre: str, defecto: int) -> int:
    valor = os.getenv(nombre)
    if valor is None or valor == "":
        return defecto
    try:
        return int(valor)
    except ValueError as exc:
        raise RuntimeError(f"{nombre} debe ser un numero entero") from exc


def _texto(nombre: str, defecto: str | None = None) -> str:
    valor = os.getenv(nombre, defecto)
    if valor is None or valor == "":
        raise RuntimeError(f"Falta la variable de entorno {nombre}")
    return valor


@dataclass(frozen=True)
class Settings:
    db_host: str
    db_port: int
    db_name: str
    db_user: str
    db_password: str
    pool_min_size: int
    pool_max_size: int
    pool_timeout: float

    @classmethod
    def desde_entorno(cls) -> "Settings":
        db_user = os.getenv("DB_USER", ROL_API_ESPERADO)
        if db_user.lower() in ROLES_PROHIBIDOS or db_user != ROL_API_ESPERADO:
            raise RuntimeError(
                "La API solo puede conectarse con el rol de lectura/escritura "
                f"{ROL_API_ESPERADO}. No use el propietario ni un superusuario."
            )
        return cls(
            db_host=os.getenv("DB_HOST", "localhost"),
            db_port=_entero("DB_PORT", 5433),
            db_name=os.getenv("DB_NAME", "bodegas_del_atuel"),
            db_user=db_user,
            db_password=_texto("DB_PASSWORD"),
            pool_min_size=_entero("DB_POOL_MIN_SIZE", 1),
            pool_max_size=_entero("DB_POOL_MAX_SIZE", 10),
            pool_timeout=float(os.getenv("DB_POOL_TIMEOUT", "10")),
        )

    @property
    def conninfo(self) -> str:
        return make_conninfo(
            host=self.db_host,
            port=self.db_port,
            dbname=self.db_name,
            user=self.db_user,
            password=self.db_password,
            connect_timeout=int(self.pool_timeout),
        )

    @property
    def dsn_sin_password(self) -> str:
        return f"postgresql://{self.db_user}@{self.db_host}:{self.db_port}/{self.db_name}"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings.desde_entorno()
