"""Generador determinista de datos para Bodegas del Atuel (Etapa 3).

No usa ORM ni query builders. Solo construye filas en memoria; la escritura a
PostgreSQL se hace en ``cargador.py`` con SQL escrito a mano.
"""
from __future__ import annotations

import bisect
import csv
import random
import re
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Any, Iterable

from faker import Faker

BASE_DIR = Path(__file__).resolve().parent
CATALOGOS_DIR = BASE_DIR / "catalogos"

FECHA_REF_DEFAULT = date(2026, 11, 10)
DIA_SEMANA = ["lunes", "miercoles", "viernes", "sabado", "martes", "jueves", "domingo"]
TIPOS_VINO = {"tinto", "blanco", "rosado", "espumante"}
PRESENTACIONES = {187, 375, 750, 1500, 3000}
PAISES = [
    "Brasil", "Chile", "Estados Unidos", "Reino Unido", "Canadá", "China",
    "Japón", "Alemania", "Francia", "Países Bajos", "México", "Uruguay",
    "Paraguay", "Bolivia", "Perú", "Colombia",
]

# Orden de columnas para COPY / INSERT. Las columnas identidad y generadas
# se omiten deliberadamente.
COLUMNAS: dict[str, list[str]] = {
    "bodega": ["cuit", "razon_social", "calle", "numero"],
    "finca": ["nombre_finca", "superficie", "provincia", "nombre_departamento"],
    "cepa": ["id", "nombre", "tipo"],
    "maridaje": ["id", "nombre", "temperatura_servicio"],
    "transportista": ["razon_social", "cuit", "email", "telefono", "calle", "numero"],
    "localidad": ["codigo_postal", "nombre", "provincia", "tipo_encargado", "cuit_encargado"],
    "sala_venta": ["calle", "numero", "dia_cierre", "codigo_postal"],
    "empleado": ["cuit", "tipo", "nombre", "apellido", "salario", "fecha_ingreso", "id_sala"],
    "transportista_cubre_localidad": ["codigo_transportista", "codigo_postal_localidad"],
    "ingreso": ["fecha", "estado", "codigo_transportista", "cuit_bodega"],
    "cliente": ["tipo", "nombre", "apellido", "razon_social", "calle", "numero",
                "estado_activo", "codigo_postal", "tipo_documento", "numero_documento",
                "fecha_alta"],
    "cliente_comun": ["id_cliente", "tipo"],
    "socio_club": ["id_cliente", "tipo"],
    "distribuidor": ["id_cliente", "tipo", "zona_cobertura", "numero_habilitacion"],
    "exportador": ["id_cliente", "tipo", "pais_destino", "descuento_especial"],
    "permiso": ["id_exportador", "fecha_emision", "fecha_vencimiento"],
    "parcela": ["numero_parcela", "id_finca", "superficie", "año_plantacion", "id_cepa"],
    "lote": ["fecha", "kg_cosecha", "cuit_bodega", "id_finca", "numero_parcela"],
    "analisis_calidad": ["fecha", "ph", "brix", "acidez", "numero_lote"],
    "vino": ["nombre", "tipo", "añada", "volumen_ml", "graduacion", "precio", "cuit_bodega"],
    "composicion": ["codigo_vino", "id_cepa", "porcentaje"],
    "stock_deposito": ["codigo_vino", "cantidad"],
    "vino_maridaje": ["codigo_vino", "id_maridaje"],
    "renglon_ingreso": ["codigo_ingreso", "codigo_vino", "cantidad"],
    "auditoria_precio": ["usuario", "fecha_hora", "precio_nuevo", "precio_anterior", "codigo_vino"],
    "stock_sala": ["id_sala", "codigo_vino", "cantidad"],
    "comprobante": ["fecha", "subtotal", "total", "descuento_aplicado",
                    "descuento_total", "id_cliente", "id_sala_venta"],
    "renglon_comprobante": ["numero_comprobante", "codigo_vino", "cantidad", "precio_unitario"],
    "transferencia": ["fecha_confeccion", "estado", "id_sala_venta"],
    "renglon_transferencia": ["numero_transferencia", "codigo_vino", "cantidad"],
}

# Orden de carga respetando FKs. localidad va antes de empleado porque su FK
# es DEFERRABLE INITIALLY DEFERRED.
ORDEN_CARGA = [
    "bodega", "finca", "transportista", "localidad", "sala_venta", "empleado",
    "parcela", "lote", "analisis_calidad", "vino", "composicion", "vino_maridaje",
    "cliente", "cliente_comun", "socio_club", "distribuidor", "exportador",
    "permiso", "transportista_cubre_localidad", "ingreso", "renglon_ingreso",
    "transferencia", "renglon_transferencia", "comprobante", "renglon_comprobante",
    "auditoria_precio", "stock_deposito", "stock_sala",
]

TABLAS = list(COLUMNAS.keys())


def _dec(value: Any, places: str = "0.01") -> Decimal:
    return Decimal(str(value)).quantize(Decimal(places), rounding=ROUND_HALF_UP)


def _recortar(value: str, largo: int) -> str:
    return (value or "").strip()[:largo]


@dataclass
class VinoMeta:
    codigo: int
    nombre: str
    tipo: str
    anio: int
    volumen_ml: int
    graduacion: Decimal
    precio: Decimal
    cuit_bodega: str
    disponibilidad: date
    price_dates: list[date]
    prices: list[Decimal]
    cepas: list[tuple[int, Decimal]]
    maridajes: list[int]

    def precio_en(self, fecha: date) -> Decimal:
        idx = bisect.bisect_right(self.price_dates, fecha) - 1
        if idx < 0:
            idx = 0
        return self.prices[idx]


@dataclass
class ClienteMeta:
    id: int
    tipo: str
    nombre: str | None
    apellido: str | None
    razon_social: str | None
    calle: str
    numero: str
    codigo_postal: str
    tipo_documento: str
    numero_documento: str
    fecha_alta: date
    descuento: Decimal
    reservado: bool = False
    zona_cobertura: str | None = None
    numero_habilitacion: str | None = None
    pais_destino: str | None = None
    descuento_especial: Decimal | None = None


@dataclass
class DataGenerator:
    seed: int = 42
    fecha_ref: date = FECHA_REF_DEFAULT
    escala: float = 1.0
    n_clientes_override: int | None = None

    def __post_init__(self) -> None:
        if self.escala <= 0:
            raise ValueError("La escala debe ser mayor que 0")
        self.rng = random.Random(self.seed)
        self.fake = Faker("es_AR")
        Faker.seed(self.seed)
        self.rows: dict[str, list[tuple[Any, ...]]] = {t: [] for t in TABLAS}

        self.cepas: list[dict[str, Any]] = []
        self.maridajes: list[dict[str, Any]] = []
        self.localidades: list[dict[str, Any]] = []
        self.tipos_vino: set[str] = set()
        self.presentaciones: set[int] = set()

        self.bodegas: list[dict[str, Any]] = []
        self.fincas: list[dict[str, Any]] = []
        self.transportistas: list[dict[str, Any]] = []
        self.salas: list[dict[str, Any]] = []
        self.salas_por_localidad: dict[str, list[int]] = {}
        self.empleados: list[dict[str, Any]] = []
        self.parcelas: list[dict[str, Any]] = []
        self.lotes: list[dict[str, Any]] = []
        self.vinos: list[VinoMeta] = []
        self.clientes: list[ClienteMeta] = []
        self.selectable_clients: list[ClienteMeta] = []
        self.exportadores: list[ClienteMeta] = []
        self.stock_deposito: dict[int, int] = {}
        self.stock_sala: dict[tuple[int, int], int] = {}

        self._cuits: set[str] = set()
        self._documentos: set[tuple[str, str]] = set()
        self._dni_seq = 30_000_000
        self._cuit_seq = 10_000_000
        self._vino_keys: set[tuple[str, int, int]] = set()

        # Volúmenes base (escala 1.0). Con escala 0.1 se reducen, manteniendo
        # los mínimos necesarios para que todas las tablas tengan filas.
        self.n_bodegas = self._scaled(20, 2)
        self.n_fincas = self._scaled(30, 3)
        self.n_transportistas = self._scaled(12, 2)
        self.n_salas = max(18, self._scaled(24, 18))
        self.n_empleados = max(18, self._scaled(80, 18))
        self.parcelas_por_finca = max(1, int(round(20 * self.escala)))
        self.n_parcelas = self.n_fincas * self.parcelas_por_finca
        self.n_lotes = min(self._scaled(900, 30), self.n_parcelas * 5)
        self.n_vinos = self._scaled(500, 50)
        self.n_clientes = (
            self.n_clientes_override
            if self.n_clientes_override is not None
            else self._scaled(20_000, 2_000)
        )
        self.n_comprobantes = self._scaled(150_000, 15_000)

        self.n_ingresos_semilla = self.n_vinos
        self.n_ingresos_procesados_extra = self._scaled(200, 20)
        self.n_ingresos_terminados = self._scaled(300, 30)
        self.n_ingresos_en_confeccion = self._scaled(200, 20)
        self.n_ingresos = (
            self.n_ingresos_semilla
            + self.n_ingresos_procesados_extra
            + self.n_ingresos_terminados
            + self.n_ingresos_en_confeccion
        )
        self.n_transferencias_no_procesadas = self._scaled(100, 10)

    def _scaled(self, base: int, minimo: int) -> int:
        return max(minimo, int(round(base * self.escala)))

    # ------------------------------------------------------------------
    # Catálogos
    # ------------------------------------------------------------------
    def load_catalogs(self) -> None:
        with (CATALOGOS_DIR / "cepas.csv").open(encoding="utf-8", newline="") as fh:
            self.cepas = [
                {"id": int(r["id"]), "nombre": r["nombre"], "tipo": r["tipo"]}
                for r in csv.DictReader(fh)
            ]
        with (CATALOGOS_DIR / "maridajes.csv").open(encoding="utf-8", newline="") as fh:
            self.maridajes = [
                {"id": int(r["id"]), "nombre": r["nombre"],
                 "temperatura_servicio": int(r["temperatura_servicio"])}
                for r in csv.DictReader(fh)
            ]
        with (CATALOGOS_DIR / "localidades.csv").open(encoding="utf-8", newline="") as fh:
            self.localidades = [
                {"codigo_postal": r["codigo_postal"], "nombre": r["nombre"],
                 "provincia": r["provincia"], "departamento": r["departamento"]}
                for r in csv.DictReader(fh)
            ]
        with (CATALOGOS_DIR / "tipos_vino.csv").open(encoding="utf-8", newline="") as fh:
            self.tipos_vino = {r["tipo"] for r in csv.DictReader(fh)}
        with (CATALOGOS_DIR / "presentaciones.csv").open(encoding="utf-8", newline="") as fh:
            self.presentaciones = {int(r["volumen_ml"]) for r in csv.DictReader(fh)}

        if not self.cepas or not self.maridajes or not self.localidades:
            raise RuntimeError("Los catálogos CSV están vacíos")

        # Los catálogos con identidad se cargan con INSERT ... OVERRIDING
        # SYSTEM VALUE para respetar los IDs declarados en el CSV.
        self.rows["cepa"] = [
            (c["id"], c["nombre"], c["tipo"]) for c in self.cepas
        ]
        self.rows["maridaje"] = [
            (m["id"], m["nombre"], m["temperatura_servicio"]) for m in self.maridajes
        ]
        if self.tipos_vino != TIPOS_VINO:
            raise RuntimeError(f"tipos_vino.csv inesperado: {self.tipos_vino}")
        if self.presentaciones != PRESENTACIONES:
            raise RuntimeError(f"presentaciones.csv inesperado: {self.presentaciones}")
        cps = {l["codigo_postal"] for l in self.localidades}
        if "5620" not in cps or "5600" not in cps:
            raise RuntimeError("Faltan General Alvear (5620) o San Rafael (5600)")

    # ------------------------------------------------------------------
    # Utilidades
    # ------------------------------------------------------------------
    def _fecha(self, inicio: date, fin: date) -> date:
        if fin < inicio:
            inicio, fin = fin, inicio
        return inicio + timedelta(days=self.rng.randint(0, (fin - inicio).days))

    def _nuevo_cuit(self, prefijos: Iterable[int] = (20, 23, 24, 27)) -> str:
        prefijos = list(prefijos)
        while True:
            self._cuit_seq += 1
            dni = f"{self._cuit_seq % 100_000_000:08d}"
            pref = str(self.rng.choice(prefijos)).zfill(2)
            base = pref + dni
            pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]
            suma = sum(int(d) * p for d, p in zip(base, pesos))
            check = 11 - (suma % 11)
            if check == 11:
                check = 0
            elif check == 10:
                check = 9
            cuit = base + str(check)
            if cuit not in self._cuits:
                self._cuits.add(cuit)
                return cuit

    def _nuevo_dni(self) -> str:
        while True:
            self._dni_seq += 1
            dni = f"{self._dni_seq:08d}"
            if ("DNI", dni) not in self._documentos:
                self._documentos.add(("DNI", dni))
                return dni

    def _partir_100(self, k: int) -> list[int]:
        if k == 1:
            return [100]
        cortes = sorted(self.rng.sample(range(1, 100), k - 1))
        valores = [cortes[0]]
        valores += [cortes[i] - cortes[i - 1] for i in range(1, len(cortes))]
        valores.append(100 - cortes[-1])
        return valores

    def _agregar(self, tabla: str, fila: tuple[Any, ...]) -> None:
        self.rows[tabla].append(fila)

    # ------------------------------------------------------------------
    # Entidades maestras
    # ------------------------------------------------------------------
    def generate_bodegas(self) -> None:
        for _ in range(self.n_bodegas):
            cuit = self._nuevo_cuit((30, 33, 34))
            razon = _recortar(self.fake.company() + " Bodega", 120)
            calle = _recortar(self.fake.street_name(), 60)
            numero = _recortar(self.fake.building_number(), 10)
            self._agregar("bodega", (cuit, razon, calle, numero))
            self.bodegas.append({"cuit": cuit, "razon_social": razon})

    def generate_fincas(self) -> None:
        for i in range(self.n_fincas):
            nombre = _recortar(self.fake.company() + " Finca", 80)
            superficie = _dec(self.rng.uniform(100, 500))
            depto = self.rng.choice(self.localidades)["departamento"]
            self._agregar("finca", (nombre, superficie, "Mendoza", depto))
            self.fincas.append({"id": i + 1, "nombre": nombre, "departamento": depto})

    def generate_transportistas(self) -> None:
        for i in range(self.n_transportistas):
            razon = _recortar(self.fake.company() + " Transportes", 120)
            cuit = self._nuevo_cuit((30, 33, 34))
            email = _recortar(self.fake.email(), 100)
            telefono = self.fake.numerify("+54 9 261 ####-####")[:20]
            calle = _recortar(self.fake.street_name(), 60)
            numero = _recortar(self.fake.building_number(), 10)
            self._agregar("transportista", (razon, cuit, email, telefono, calle, numero))
            self.transportistas.append({"codigo": i + 1, "cuit": cuit})

    def generate_salas_y_empleados(self) -> None:
        # Salas: una por localidad y el resto distribuidas.
        for i in range(self.n_salas):
            if i < len(self.localidades):
                cp = self.localidades[i]["codigo_postal"]
            else:
                cp = self.rng.choice(self.localidades)["codigo_postal"]
            calle = _recortar(self.fake.street_name(), 60)
            numero = _recortar(self.fake.building_number(), 10)
            dia = DIA_SEMANA[i % len(DIA_SEMANA)]
            sala_id = i + 1
            self._agregar("sala_venta", (calle, numero, dia, cp))
            self.salas.append({"id": sala_id, "codigo_postal": cp})
            self.salas_por_localidad.setdefault(cp, []).append(sala_id)

        # Empleados: un encargado regional por localidad.
        for loc in self.localidades:
            cuit = self._nuevo_cuit((20, 23, 24, 27))
            nombre = _recortar(self.fake.first_name(), 100)
            apellido = _recortar(self.fake.last_name(), 100)
            salario = _dec(self.rng.randint(800_000, 2_500_000))
            fecha_ingreso = self._fecha(date(2015, 1, 1), date(2020, 12, 31))
            id_sala = self.salas_por_localidad[loc["codigo_postal"]][0]
            self._agregar("empleado", (cuit, "encargado_regional", nombre, apellido,
                                       salario, fecha_ingreso, id_sala))
            self.empleados.append({"cuit": cuit, "tipo": "encargado_regional", "id_sala": id_sala})
            loc["tipo_encargado"] = "encargado_regional"
            loc["cuit_encargado"] = cuit

        # Empleados de sala restantes.
        while len(self.empleados) < self.n_empleados:
            cuit = self._nuevo_cuit((20, 23, 24, 27))
            nombre = _recortar(self.fake.first_name(), 100)
            apellido = _recortar(self.fake.last_name(), 100)
            salario = _dec(self.rng.randint(700_000, 1_800_000))
            u = self.rng.random()
            if u < 0.30:
                fecha_ingreso = self._fecha(date(2015, 1, 1), date(2020, 12, 31))
            elif u < 0.50:
                fecha_ingreso = self._fecha(self.fecha_ref - timedelta(days=730), self.fecha_ref)
            else:
                fecha_ingreso = self._fecha(date(2021, 1, 1), date(2024, 12, 31))
            id_sala = self.rng.randint(1, self.n_salas)
            self._agregar("empleado", (cuit, "empleado_sala", nombre, apellido,
                                       salario, fecha_ingreso, id_sala))
            self.empleados.append({"cuit": cuit, "tipo": "empleado_sala", "id_sala": id_sala})

        # Localidades ya con su encargado.
        for loc in self.localidades:
            self._agregar("localidad", (
                loc["codigo_postal"], loc["nombre"], loc["provincia"],
                loc["tipo_encargado"], loc["cuit_encargado"],
            ))

    # ------------------------------------------------------------------
    # Viñedos y elaboración
    # ------------------------------------------------------------------
    def generate_parcelas_lotes_analisis(self) -> None:
        for finca in self.fincas:
            for p in range(1, self.parcelas_por_finca + 1):
                id_cepa = self.rng.randint(1, 11)  # Semillón (12) queda sin uso
                superficie = _dec(self.rng.uniform(1, 20))
                anio = self.rng.randint(1990, 2020)
                self._agregar("parcela", (p, finca["id"], superficie, anio, id_cepa))
                self.parcelas.append({"id_finca": finca["id"],
                                      "numero_parcela": p, "id_cepa": id_cepa})

        campanias = [2021, 2022, 2023, 2024, 2025]
        base, resto = divmod(self.n_lotes, len(campanias))
        for idx, campania in enumerate(campanias):
            cantidad = base + (1 if idx < resto else 0)
            if cantidad <= 0:
                continue
            elegidas = self.rng.sample(self.parcelas, cantidad)
            for parcela in elegidas:
                fecha = date(campania, self.rng.randint(2, 4), self.rng.randint(1, 28))
                kg = _dec(self.rng.uniform(1000, 20000))
                cuit_bodega = self.rng.choice(self.bodegas)["cuit"]
                numero_lote = len(self.lotes) + 1
                self._agregar("lote", (fecha, kg, cuit_bodega,
                                       parcela["id_finca"], parcela["numero_parcela"]))
                self.lotes.append({"numero_lote": numero_lote, "fecha": fecha,
                                   "campaña": campania,
                                   "id_finca": parcela["id_finca"],
                                   "numero_parcela": parcela["numero_parcela"]})

        for lote in self.lotes:
            cantidad = 4 if self.rng.random() < 0.5 else 3
            for _ in range(cantidad):
                fecha = lote["fecha"] + timedelta(days=self.rng.randint(1, 60))
                ph = _dec(self.rng.uniform(3.0, 3.8))
                brix = _dec(self.rng.uniform(18, 26), "0.1")
                acidez = _dec(self.rng.uniform(4, 9))
                self._agregar("analisis_calidad",
                              (fecha, ph, brix, acidez, lote["numero_lote"]))

    def _agregar_vino(self, vino: VinoMeta) -> None:
        self.vinos.append(vino)
        self._agregar("vino", (vino.nombre, vino.tipo, vino.anio, vino.volumen_ml,
                               vino.graduacion, vino.precio, vino.cuit_bodega))
        for id_cepa, pct in vino.cepas:
            self._agregar("composicion", (vino.codigo, id_cepa, pct))
        for id_maridaje in vino.maridajes:
            self._agregar("vino_maridaje", (vino.codigo, id_maridaje))

    def generate_vinos(self) -> None:
        # Vino obligatorio del enunciado.
        malbec = VinoMeta(
            codigo=1, nombre="Malbec Reserva", tipo="tinto", anio=2021,
            volumen_ml=750, graduacion=Decimal("14.00"), precio=Decimal("12500.00"),
            cuit_bodega=self.rng.choice(self.bodegas)["cuit"],
            disponibilidad=date(2021, 6, 1),
            price_dates=[date(2021, 6, 1)], prices=[Decimal("12500.00")],
            cepas=[(1, Decimal("85.00")), (2, Decimal("15.00"))],
            maridajes=[1, 2],
        )
        self._agregar_vino(malbec)
        self._vino_keys.add((malbec.nombre, malbec.anio, malbec.volumen_ml))

        rangos = {
            "tinto": (12.0, 15.0, [1, 2, 3, 4, 5, 6, 7]),
            "blanco": (11.0, 14.0, [8, 9, 10, 11]),
            "rosado": (10.5, 13.5, [1, 2, 3, 4, 5, 6, 7]),
            "espumante": (10.0, 12.5, [8, 9, 10, 11]),
        }
        sufijos = {
            "tinto": ["Joven", "Reserva", "Gran Reserva", "Selección", "Roble"],
            "blanco": ["Joven", "Reserva", "Tardío", "Selección"],
            "rosado": ["Joven", "Rosé", "Selección"],
            "espumante": ["Extra Brut", "Brut Nature", "Tradicional"],
        }
        pesos_tipo = [0.68, 0.20, 0.06, 0.06]
        tipos = ["tinto", "blanco", "rosado", "espumante"]

        for i in range(2, self.n_vinos + 1):
            tipo = self.rng.choices(tipos, weights=pesos_tipo, k=1)[0]
            anio = self.rng.randint(2018, 2025)
            volumen = self.rng.choices([187, 375, 750, 1500, 3000],
                                       weights=[5, 15, 60, 15, 5], k=1)[0]
            gmin, gmax, cepas_validas = rangos[tipo]
            graduacion = _dec(self.rng.uniform(gmin, gmax))
            base_price = _dec(self.rng.randint(3500, 30000))
            disponibilidad = max(date(2021, 1, 1), date(anio, 6, 1))
            price_dates = [disponibilidad]
            prices = [base_price]
            auditorias: list[tuple[Any, ...]] = []

            force_change = (i == 2)
            cambio1 = force_change or self.rng.random() < 0.25
            if cambio1:
                d1 = disponibilidad + timedelta(days=365)
                if d1 <= self.fecha_ref:
                    nuevo = _dec(prices[-1] * Decimal(str(1 + self.rng.uniform(0.05, 0.20))))
                    price_dates.append(d1)
                    prices.append(nuevo)
                    auditorias.append(("carga_masiva", datetime.combine(d1, time(12, 0)),
                                       nuevo, prices[-2], i))
                    if (not force_change) and self.rng.random() < 0.15:
                        d2 = disponibilidad + timedelta(days=730)
                        if d2 <= self.fecha_ref:
                            nuevo2 = _dec(prices[-1] * Decimal(str(1 + self.rng.uniform(0.05, 0.20))))
                            price_dates.append(d2)
                            prices.append(nuevo2)
                            auditorias.append(("carga_masiva", datetime.combine(d2, time(12, 0)),
                                               nuevo2, prices[-2], i))

            k = self.rng.choices([1, 2, 3], weights=[0.30, 0.50, 0.20], k=1)[0]
            cepas_elegidas = self.rng.sample(cepas_validas, k)
            porcentajes = self._partir_100(k)
            cepas = [(c, Decimal(str(p))) for c, p in zip(cepas_elegidas, porcentajes)]

            k_mar = self.rng.choices([1, 2, 3], weights=[0.40, 0.40, 0.20], k=1)[0]
            maridajes = self.rng.sample(range(1, 9), k_mar)

            primaria = self.cepas[cepas[0][0] - 1]["nombre"]
            sufijo = self.rng.choice(sufijos[tipo])
            nombre_base = f"{primaria} {sufijo}"
            nombre = nombre_base
            n = 2
            while (nombre, anio, volumen) in self._vino_keys:
                nombre = f"{nombre_base} {n}"
                n += 1
            nombre = nombre[:100]
            self._vino_keys.add((nombre, anio, volumen))

            vino = VinoMeta(
                codigo=i, nombre=nombre, tipo=tipo, anio=anio, volumen_ml=volumen,
                graduacion=graduacion, precio=prices[-1],
                cuit_bodega=self.rng.choice(self.bodegas)["cuit"],
                disponibilidad=disponibilidad, price_dates=price_dates, prices=prices,
                cepas=cepas, maridajes=maridajes,
            )
            self._agregar_vino(vino)
            for aud in auditorias:
                self._agregar("auditoria_precio", aud)

    # ------------------------------------------------------------------
    # Clientes y jerarquía
    # ------------------------------------------------------------------
    def generate_clientes(self) -> None:
        n = self.n_clientes
        c_comun = int(n * 0.40)
        c_socio = int(n * 0.40)
        c_dist = int(n * 0.12)
        c_exp = n - c_comun - c_socio - c_dist
        tipos = (["cliente_comun"] * c_comun + ["socio_club"] * c_socio
                 + ["distribuidor"] * c_dist + ["exportador"] * c_exp)
        self.rng.shuffle(tipos)

        for i, tipo in enumerate(tipos, start=1):
            loc = self.rng.choice(self.localidades)
            calle = _recortar(self.fake.street_name(), 60)
            numero = _recortar(self.fake.building_number(), 10)
            if self.rng.random() < 0.10:
                fecha_alta = self._fecha(date(2021, 1, 1), self.fecha_ref)
            else:
                fecha_alta = self._fecha(date(2010, 1, 1), date(2020, 12, 31))

            if tipo in ("cliente_comun", "socio_club"):
                nombre = _recortar(self.fake.first_name(), 60)
                apellido = _recortar(self.fake.last_name(), 60)
                razon = None
                tipo_doc = "DNI"
                num_doc = self._nuevo_dni()
                descuento = Decimal("0.00") if tipo == "cliente_comun" else Decimal("0.10")
                zona = hab = pais = None
                desc_esp = None
            else:
                nombre = apellido = None
                razon = _recortar(self.fake.company(), 120)
                tipo_doc = "CUIT"
                num_doc = self._nuevo_cuit((30, 33, 34))
                self._documentos.add((tipo_doc, num_doc))
                if tipo == "distribuidor":
                    descuento = Decimal("0.20")
                    zona = _recortar(
                        f"{self.rng.choice(self.localidades)['departamento']}, "
                        f"{self.rng.choice(self.localidades)['departamento']}", 100)
                    hab = f"HAB-{i:05d}"
                    pais = None
                    desc_esp = None
                else:
                    pais = self.rng.choice(PAISES)
                    desc_esp = None
                    if self.rng.random() < 0.30:
                        desc_esp = _dec(self.rng.uniform(0.30, 0.35))
                    descuento = desc_esp if desc_esp is not None else Decimal("0.30")
                    zona = hab = None

            self.clientes.append(ClienteMeta(
                id=i, tipo=tipo, nombre=nombre, apellido=apellido, razon_social=razon,
                calle=calle, numero=numero, codigo_postal=loc["codigo_postal"],
                tipo_documento=tipo_doc, numero_documento=num_doc,
                fecha_alta=fecha_alta, descuento=descuento,
                zona_cobertura=zona, numero_habilitacion=hab,
                pais_destino=pais, descuento_especial=desc_esp,
            ))

        # Socios sin compras, con alta de más de 5 años.
        socios = [c for c in self.clientes if c.tipo == "socio_club"]
        k_reservados = min(self._scaled(100, 10), len(socios))
        for c in socios[:k_reservados]:
            c.fecha_alta = self._fecha(date(2015, 1, 1), date(2020, 12, 31))
            c.reservado = True

        # Filas de cliente y subtipos.
        for c in self.clientes:
            self._agregar("cliente", (
                c.tipo, c.nombre, c.apellido, c.razon_social, c.calle, c.numero,
                True, c.codigo_postal, c.tipo_documento, c.numero_documento, c.fecha_alta,
            ))
            if c.tipo == "cliente_comun":
                self._agregar("cliente_comun", (c.id, c.tipo))
            elif c.tipo == "socio_club":
                self._agregar("socio_club", (c.id, c.tipo))
            elif c.tipo == "distribuidor":
                self._agregar("distribuidor", (c.id, c.tipo, c.zona_cobertura,
                                               c.numero_habilitacion))
            else:
                self._agregar("exportador", (c.id, c.tipo, c.pais_destino,
                                             c.descuento_especial))
                self.exportadores.append(c)

        self.selectable_clients = sorted(
            [c for c in self.clientes if not c.reservado],
            key=lambda c: (c.fecha_alta, c.id),
        )

    def generate_permisos(self) -> None:
        for exp in self.exportadores:
            if self.rng.random() < 0.20:
                cantidad = self.rng.randint(4, 5)
            else:
                cantidad = self.rng.randint(1, 3)
            for _ in range(cantidad):
                emision = self._fecha(date(2018, 1, 1),
                                      self.fecha_ref - timedelta(days=365))
                vencimiento = emision + timedelta(days=365 * self.rng.randint(1, 5))
                self._agregar("permiso", (exp.id, emision, vencimiento))

    def generate_transportista_cobertura(self) -> None:
        cps = [l["codigo_postal"] for l in self.localidades]
        for t in self.transportistas:
            for cp in self.rng.sample(cps, self.rng.randint(2, 5)):
                self._agregar("transportista_cubre_localidad", (t["codigo"], cp))

    # ------------------------------------------------------------------
    # Ingresos y transferencias
    # ------------------------------------------------------------------
    def _vinos_por_bodega(self, cuit: str) -> list[VinoMeta]:
        return [v for v in self.vinos if v.cuit_bodega == cuit]

    def generate_ingresos(self) -> None:
        self.stock_deposito = {v.codigo: 0 for v in self.vinos}
        n_ingresos = self.n_ingresos
        transportistas: list[int] = []
        for j in range(n_ingresos):
            if j == n_ingresos - 1 and self.n_transportistas >= 2:
                transportistas.append(self.n_transportistas)
            else:
                transportistas.append(self.rng.randint(1, max(1, self.n_transportistas - 1)))

        # Ingresos semilla: uno por vino, antes de las transferencias.
        for vino in self.vinos:
            codigo = len(self.rows["ingreso"]) + 1
            fecha = date(2020, 11, 1)
            self._agregar("ingreso", (fecha, "procesado",
                                      transportistas[codigo - 1], vino.cuit_bodega))
            cantidad = 10_000
            self._agregar("renglon_ingreso", (codigo, vino.codigo, cantidad))
            self.stock_deposito[vino.codigo] += cantidad

        def crear_ingreso(estado: str, fecha: date, k: int) -> None:
            bodega = self.rng.choice(self.bodegas)
            vinos = self._vinos_por_bodega(bodega["cuit"])
            if not vinos:
                vinos = self.vinos
            k = min(k, len(vinos))
            elegidos = self.rng.sample(vinos, k)
            codigo = len(self.rows["ingreso"]) + 1
            self._agregar("ingreso", (fecha, estado,
                                      transportistas[codigo - 1], bodega["cuit"]))
            for vino in elegidos:
                if estado == "procesado":
                    cantidad = self.rng.randint(1000, 5000)
                    self.stock_deposito[vino.codigo] += cantidad
                elif estado == "terminado":
                    cantidad = self.rng.randint(1000, 5000)
                else:
                    cantidad = self.rng.randint(1, 100)
                self._agregar("renglon_ingreso", (codigo, vino.codigo, cantidad))

        for _ in range(self.n_ingresos_procesados_extra):
            crear_ingreso("procesado", self._fecha(date(2021, 1, 1), self.fecha_ref),
                          self.rng.randint(3, 8))
        for _ in range(self.n_ingresos_terminados):
            crear_ingreso("terminado", self._fecha(date(2021, 1, 1), self.fecha_ref),
                          self.rng.randint(3, 8))
        for _ in range(self.n_ingresos_en_confeccion):
            k = self.rng.randint(0, 5)
            if k == 0:
                bodega = self.rng.choice(self.bodegas)
                codigo = len(self.rows["ingreso"]) + 1
                self._agregar("ingreso", (self._fecha(date(2021, 1, 1), self.fecha_ref),
                                          "en_confeccion", transportistas[codigo - 1],
                                          bodega["cuit"]))
            else:
                crear_ingreso("en_confeccion",
                              self._fecha(date(2021, 1, 1), self.fecha_ref), k)

    def generate_transferencias(self) -> None:
        self.stock_sala = {(s, v.codigo): 0
                           for s in range(1, self.n_salas + 1)
                           for v in self.vinos}
        excluido = (1, 1)

        # Transferencias procesadas: cubren todos los pares menos el excluido.
        for sala in range(1, self.n_salas + 1):
            vinos_sala = [v.codigo for v in self.vinos
                          if (sala, v.codigo) != excluido]
            for chunk_idx, inicio in enumerate(range(0, len(vinos_sala), 10)):
                chunk = vinos_sala[inicio:inicio + 10]
                fecha = date(2020, 11, 2) + timedelta(days=(sala * 3 + chunk_idx) % 60)
                numero = len(self.rows["transferencia"]) + 1
                self._agregar("transferencia", (fecha, "procesado", sala))
                for v in chunk:
                    cantidad = 300
                    self._agregar("renglon_transferencia", (numero, v, cantidad))
                    self.stock_sala[(sala, v)] += cantidad
                    self.stock_deposito[v] -= cantidad

        # Transferencias no procesadas: no afectan stock.
        for j in range(self.n_transferencias_no_procesadas):
            estado = "terminado" if j < self.n_transferencias_no_procesadas // 2 else "en_confeccion"
            sala = self.rng.randint(1, self.n_salas)
            fecha = self._fecha(date(2021, 1, 1), self.fecha_ref)
            numero = len(self.rows["transferencia"]) + 1
            self._agregar("transferencia", (fecha, estado, sala))
            k = self.rng.randint(1, 5) if estado == "terminado" else self.rng.randint(0, 5)
            if k:
                for v in self.rng.sample(range(1, self.n_vinos + 1), min(k, self.n_vinos)):
                    self._agregar("renglon_transferencia",
                                  (numero, v, self.rng.randint(10, 100)))

    # ------------------------------------------------------------------
    # Ventas
    # ------------------------------------------------------------------
    def generate_comprobantes(self) -> None:
        excluido = (1, 1)
        eventos: list[dict[str, Any]] = []

        for sala in range(1, self.n_salas + 1):
            for vino in self.vinos:
                if (sala, vino.codigo) == excluido:
                    continue
                inicio = vino.disponibilidad
                if vino.anio <= 2020 and self.rng.random() < 0.20:
                    fin = date(2021, 11, 9)
                    if inicio <= fin:
                        fecha = self._fecha(max(inicio, date(2021, 1, 1)), fin)
                    else:
                        fecha = self._fecha(inicio, self.fecha_ref)
                else:
                    fecha = self._fecha(inicio, self.fecha_ref)
                eventos.append({"kind": "coverage", "date": fecha,
                                "sala": sala, "vino": vino.codigo})

        n_random = self.n_comprobantes - len(eventos)
        if n_random < 0:
            raise RuntimeError("n_comprobantes es menor que la cobertura mínima")
        for _ in range(n_random):
            u = self.rng.random()
            if u < 0.05:
                inicio = self.fecha_ref - timedelta(days=7)
            elif u < 0.15:
                inicio = self.fecha_ref - timedelta(days=90)
            else:
                inicio = date(2021, 1, 1)
            fecha = self._fecha(inicio, self.fecha_ref)
            eventos.append({"kind": "random", "date": fecha})

        eventos.sort(key=lambda e: (e["date"], 0 if e["kind"] == "coverage" else 1,
                                    e.get("sala", 0), e.get("vino", 0)))

        self._client_fechas = [c.fecha_alta for c in self.selectable_clients]
        vinos_ordenados = sorted(self.vinos, key=lambda v: (v.disponibilidad, v.codigo))
        disponible_ptr = 0
        disponibles: list[int] = []

        for evento in eventos:
            fecha = evento["date"]
            while (disponible_ptr < len(vinos_ordenados)
                   and vinos_ordenados[disponible_ptr].disponibilidad <= fecha):
                disponibles.append(vinos_ordenados[disponible_ptr].codigo)
                disponible_ptr += 1

            pos = bisect.bisect_right(self._client_fechas, fecha) - 1
            if pos < 0:
                raise RuntimeError(f"No hay clientes con alta <= {fecha}")
            cliente = self.selectable_clients[self.rng.randint(0, pos)]
            descuento = cliente.descuento
            numero = len(self.rows["comprobante"]) + 1
            sala = evento.get("sala")
            renglones: list[tuple[int, int, Decimal]] = []

            if evento["kind"] == "coverage":
                vino = self.vinos[evento["vino"] - 1]
                if self.stock_sala.get((sala, vino.codigo), 0) < 1:
                    raise RuntimeError(f"Sin stock para cobertura ({sala}, {vino.codigo})")
                self.stock_sala[(sala, vino.codigo)] -= 1
                renglones.append((vino.codigo, 1, vino.precio_en(fecha)))
            else:
                sala = self.rng.randint(1, self.n_salas)
                k = self.rng.randint(2, 6)
                k = min(k, len(disponibles))
                if k <= 0:
                    raise RuntimeError(f"No hay vinos disponibles al {fecha}")
                elegidos: list[int] | None = None
                for _ in range(30):
                    intento = self.rng.sample(disponibles, k)
                    if all(self.stock_sala.get((sala, v), 0) >= 3 for v in intento):
                        elegidos = intento
                        break
                if elegidos is None:
                    candidatos = [v for v in disponibles
                                  if self.stock_sala.get((sala, v), 0) >= 1]
                    if len(candidatos) < k:
                        k = len(candidatos)
                    if k <= 0:
                        raise RuntimeError(f"Sin stock suficiente en sala {sala}")
                    elegidos = self.rng.sample(candidatos, k)
                for v in sorted(elegidos):
                    stock = self.stock_sala.get((sala, v), 0)
                    cantidad = self.rng.randint(1, min(3, stock))
                    self.stock_sala[(sala, v)] -= cantidad
                    renglones.append((v, cantidad, self.vinos[v - 1].precio_en(fecha)))

            subtotal = sum((Decimal(cant) * precio for _, cant, precio in renglones),
                           Decimal("0.00")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
            total = (subtotal * (Decimal("1.00") - descuento)).quantize(
                Decimal("0.01"), rounding=ROUND_HALF_UP)
            desc_total = (subtotal - total).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
            self._agregar("comprobante", (fecha, subtotal, total, descuento,
                                          desc_total, cliente.id, sala))
            for v, cant, precio in renglones:
                self._agregar("renglon_comprobante", (numero, v, cant, precio))

    def generate_stock_final(self) -> None:
        for v in self.vinos:
            self._agregar("stock_deposito", (v.codigo, self.stock_deposito[v.codigo]))
        for (sala, vino), cantidad in sorted(self.stock_sala.items()):
            self._agregar("stock_sala", (sala, vino, cantidad))

    # __METODOS__

    def generate_all(self) -> None:
        self.load_catalogs()
        self.generate_bodegas()
        self.generate_fincas()
        self.generate_transportistas()
        self.generate_salas_y_empleados()
        self.generate_parcelas_lotes_analisis()
        self.generate_vinos()
        self.generate_clientes()
        self.generate_permisos()
        self.generate_transportista_cobertura()
        self.generate_ingresos()
        self.generate_transferencias()
        self.generate_comprobantes()
        self.generate_stock_final()
        self.validate_bundle()

    def validate_bundle(self) -> None:
        for tabla in TABLAS:
            if not self.rows[tabla]:
                raise RuntimeError(f"La tabla {tabla} quedó sin filas")
        if len(self.rows["comprobante"]) != self.n_comprobantes:
            raise RuntimeError("Cantidad de comprobantes inesperada")
        if len(self.rows["renglon_comprobante"]) < 500_000 * self.escala * 0.95:
            raise RuntimeError("Muy pocos renglones de comprobante")
        if any(v < 0 for v in self.stock_deposito.values()):
            raise RuntimeError("Stock de depósito negativo")
        if any(v < 0 for v in self.stock_sala.values()):
            raise RuntimeError("Stock de sala negativo")
        if self.stock_sala.get((1, 1), 0) != 0:
            raise RuntimeError("El par excluido (sala 1, vino 1) debe tener stock 0")
        if not self.rows["auditoria_precio"]:
            raise RuntimeError("auditoria_precio quedó vacía")
        # Semillón (id 12) no debe aparecer en parcelas ni composiciones.
        if any(int(f[4]) == 12 for f in self.rows["parcela"]):
            raise RuntimeError("La cepa 12 (Semillón) aparece en una parcela")
        if any(int(f[1]) == 12 for f in self.rows["composicion"]):
            raise RuntimeError("La cepa 12 (Semillón) aparece en una composición")
