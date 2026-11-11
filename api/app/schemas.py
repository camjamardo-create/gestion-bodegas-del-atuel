"""Modelos de entrada y salida de la API.

Los importes y porcentajes se mantienen como Decimal. En JSON se serializan
como string para no perder precision ni pasar por float.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import AliasChoices, BaseModel, ConfigDict, Field, PlainSerializer

NumericStr = Annotated[
    Decimal,
    PlainSerializer(lambda valor: str(valor), return_type=str, when_used="json"),
]

TipoVino = Literal["tinto", "blanco", "rosado", "espumante"]
TipoCliente = Literal["cliente_comun", "socio_club", "distribuidor", "exportador"]
TipoEstado = Literal["en_confeccion", "terminado", "procesado"]


class Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class Salida(BaseModel):
    model_config = ConfigDict(from_attributes=True, extra="ignore", populate_by_name=True)


# ---------------------------------------------------------------------------
# Vinos
# ---------------------------------------------------------------------------


class ComposicionIn(Entrada):
    id_cepa: int
    porcentaje: Decimal


class VinoCreate(Entrada):
    nombre: str = Field(min_length=1, max_length=100)
    tipo: TipoVino
    anada: int = Field(
        validation_alias=AliasChoices("anada", "añada"),
        serialization_alias="anada",
    )
    volumen_ml: int
    graduacion: Decimal
    precio: Decimal
    cuit_bodega: str = Field(min_length=11, max_length=11)
    cepas: list[ComposicionIn] = Field(default_factory=list)
    maridajes: list[int] = Field(default_factory=list)


class VinoUpdate(Entrada):
    nombre: str | None = Field(default=None, min_length=1, max_length=100)
    tipo: TipoVino | None = None
    anada: int | None = Field(
        default=None,
        validation_alias=AliasChoices("anada", "añada"),
        serialization_alias="anada",
    )
    volumen_ml: int | None = None
    graduacion: Decimal | None = None
    precio: Decimal | None = None
    cuit_bodega: str | None = Field(default=None, min_length=11, max_length=11)
    cepas: list[ComposicionIn] | None = None
    maridajes: list[int] | None = None


class BodegaOut(Salida):
    cuit: str
    razon_social: str
    calle: str
    numero: str


class CepaOut(Salida):
    id: int
    nombre: str
    tipo: Literal["tinta", "blanca"]
    porcentaje: NumericStr


class MaridajeOut(Salida):
    id: int
    nombre: str
    temperatura_servicio: int


class VinoOut(Salida):
    codigo: int
    nombre: str
    tipo: TipoVino
    anada: int
    volumen_ml: int
    graduacion: NumericStr
    precio: NumericStr
    cuit_bodega: str


class VinoDetalleOut(VinoOut):
    bodega: BodegaOut
    cepas: list[CepaOut]
    maridajes: list[MaridajeOut]
    stock_deposito: int
    stock_sala: int
    stock_total: int


class VinoListaOut(Salida):
    items: list[VinoOut]
    total: int
    page: int
    page_size: int


# ---------------------------------------------------------------------------
# Clientes
# ---------------------------------------------------------------------------


class PermisoIn(Entrada):
    fecha_emision: date
    fecha_vencimiento: date


class PermisoOut(Salida):
    codigo: int
    fecha_emision: date
    fecha_vencimiento: date


class ClienteCreate(Entrada):
    tipo: TipoCliente
    nombre: str | None = Field(default=None, max_length=60)
    apellido: str | None = Field(default=None, max_length=60)
    razon_social: str | None = Field(default=None, max_length=120)
    calle: str = Field(min_length=1, max_length=60)
    numero: str = Field(min_length=1, max_length=10)
    codigo_postal: str = Field(min_length=4, max_length=8)
    tipo_documento: str = Field(min_length=1, max_length=10)
    numero_documento: str = Field(min_length=1, max_length=20)
    zona_cobertura: str | None = Field(default=None, max_length=100)
    numero_habilitacion: str | None = Field(default=None, max_length=20)
    pais_destino: str | None = Field(default=None, max_length=50)
    descuento_especial: Decimal | None = None
    permisos: list[PermisoIn] = Field(default_factory=list)


class ClienteUpdate(Entrada):
    tipo: TipoCliente | None = None
    nombre: str | None = Field(default=None, max_length=60)
    apellido: str | None = Field(default=None, max_length=60)
    razon_social: str | None = Field(default=None, max_length=120)
    calle: str | None = Field(default=None, min_length=1, max_length=60)
    numero: str | None = Field(default=None, min_length=1, max_length=10)
    codigo_postal: str | None = Field(default=None, min_length=4, max_length=8)
    tipo_documento: str | None = Field(default=None, min_length=1, max_length=10)
    numero_documento: str | None = Field(default=None, min_length=1, max_length=20)
    estado_activo: bool | None = None
    zona_cobertura: str | None = Field(default=None, max_length=100)
    numero_habilitacion: str | None = Field(default=None, max_length=20)
    pais_destino: str | None = Field(default=None, max_length=50)
    descuento_especial: Decimal | None = None
    permisos: list[PermisoIn] | None = None


class ClienteOut(Salida):
    id: int
    tipo: TipoCliente
    nombre: str | None
    apellido: str | None
    razon_social: str | None
    calle: str
    numero: str
    codigo_postal: str
    tipo_documento: str
    numero_documento: str
    estado_activo: bool
    fecha_alta: date
    zona_cobertura: str | None = None
    numero_habilitacion: str | None = None
    pais_destino: str | None = None
    descuento_especial: NumericStr | None = None
    permisos: list[PermisoOut] = Field(default_factory=list)


class ClienteListaOut(Salida):
    items: list[ClienteOut]
    total: int
    page: int
    page_size: int


# ---------------------------------------------------------------------------
# Comprobantes
# ---------------------------------------------------------------------------


class RenglonComprobanteIn(Entrada):
    codigo_vino: int
    cantidad: int = Field(ge=1)


class ComprobanteCreate(Entrada):
    id_cliente: int
    id_sala_venta: int
    fecha: date | None = None
    renglones: list[RenglonComprobanteIn] = Field(min_length=1)


class ClienteResumenOut(Salida):
    id: int
    tipo: TipoCliente
    nombre: str | None
    apellido: str | None
    razon_social: str | None


class SalaOut(Salida):
    id: int
    calle: str
    numero: str


class RenglonComprobanteOut(Salida):
    codigo_vino: int
    nombre_vino: str
    cantidad: int
    precio_unitario: NumericStr
    subtotal_renglon: NumericStr


class ComprobanteOut(Salida):
    numero: int
    fecha: date
    subtotal: NumericStr
    descuento_aplicado: NumericStr
    descuento_total: NumericStr
    total: NumericStr
    cliente: ClienteResumenOut
    sala: SalaOut
    renglones: list[RenglonComprobanteOut]


# ---------------------------------------------------------------------------
# Movimientos de stock
# ---------------------------------------------------------------------------


class TransferenciaCreate(Entrada):
    id_sala_venta: int


class IngresoCreate(Entrada):
    codigo_transportista: int
    cuit_bodega: str = Field(min_length=11, max_length=11)


class RenglonMovimientoIn(Entrada):
    codigo_vino: int
    cantidad: int = Field(ge=1)


class RenglonMovimientoOut(Salida):
    codigo_vino: int
    nombre_vino: str
    cantidad: int


class TransferenciaOut(Salida):
    numero: int
    fecha_confeccion: date
    estado: TipoEstado
    id_sala_venta: int
    renglones: list[RenglonMovimientoOut]


class IngresoOut(Salida):
    codigo: int
    fecha: date
    estado: TipoEstado
    codigo_transportista: int
    cuit_bodega: str
    renglones: list[RenglonMovimientoOut]


# ---------------------------------------------------------------------------
# Reportes
# ---------------------------------------------------------------------------


class TopVinoOut(Salida):
    codigo_vino: int
    nombre: str
    botellas_vendidas: int


class VentaSalaOut(Salida):
    id_sala: int
    calle: str
    numero: str
    monto_total: NumericStr


class VinoSinStockOut(Salida):
    codigo: int
    nombre: str
    stock_deposito: int


class TransportistaActivoOut(Salida):
    codigo: int
    razon_social: str
    ingresos: int
    botellas: int


class TrazabilidadOut(Salida):
    codigo: int
    nombre: str
    bodega: str
    cepas: str | None
    maridajes: str | None
    stock_total: int


# ---------------------------------------------------------------------------
# Salud
# ---------------------------------------------------------------------------


class SaludOut(Salida):
    status: str
    base_de_datos: str
    current_user: str
