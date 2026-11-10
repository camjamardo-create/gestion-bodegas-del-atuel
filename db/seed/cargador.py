"""Carga, controles, hashes y benchmark para Bodegas del Atuel (Etapa 3)."""
from __future__ import annotations

import csv
import hashlib
import json
import os
import time
from datetime import date
from pathlib import Path
from typing import Any, Iterable

import psycopg
from psycopg import sql

from generador import COLUMNAS, ORDEN_CARGA, TABLAS, DataGenerator

BASE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR.parent.parent
BATCH_SIZE = 5_000

# Tablas con columnas identidad que hay que reajustar con setval.
IDENTIDADES = [
    ("finca", "id"),
    ("cepa", "id"),
    ("maridaje", "id"),
    ("transportista", "codigo"),
    ("sala_venta", "id"),
    ("ingreso", "codigo"),
    ("cliente", "id"),
    ("permiso", "codigo"),
    ("lote", "numero_lote"),
    ("analisis_calidad", "id"),
    ("vino", "codigo"),
    ("auditoria_precio", "id"),
    ("comprobante", "numero"),
    ("transferencia", "numero"),
]

ORDEN_HASH = {
    "bodega": "cuit",
    "finca": "id",
    "cepa": "id",
    "maridaje": "id",
    "transportista": "codigo",
    "localidad": "codigo_postal",
    "sala_venta": "id",
    "empleado": "cuit",
    "transportista_cubre_localidad": "codigo_transportista, codigo_postal_localidad",
    "ingreso": "codigo",
    "cliente": "id",
    "cliente_comun": "id_cliente",
    "socio_club": "id_cliente",
    "distribuidor": "id_cliente",
    "exportador": "id_cliente",
    "permiso": "codigo",
    "parcela": "id_finca, numero_parcela",
    "lote": "numero_lote",
    "analisis_calidad": "id",
    "vino": "codigo",
    "composicion": "codigo_vino, id_cepa",
    "stock_deposito": "codigo_vino",
    "vino_maridaje": "codigo_vino, id_maridaje",
    "renglon_ingreso": "codigo_ingreso, codigo_vino",
    "auditoria_precio": "id",
    "stock_sala": "id_sala, codigo_vino",
    "comprobante": "numero",
    "renglon_comprobante": "numero_comprobante, codigo_vino",
    "transferencia": "numero",
    "renglon_transferencia": "numero_transferencia, codigo_vino",
}


# ---------------------------------------------------------------------------
# Conexión y entorno
# ---------------------------------------------------------------------------
def _load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def cargar_entorno() -> None:
    _load_dotenv(PROJECT_ROOT / ".env")
    if Path.cwd() != PROJECT_ROOT:
        _load_dotenv(Path.cwd() / ".env")


def conectar() -> psycopg.Connection:
    cargar_entorno()
    dsn = os.environ.get("DATABASE_URL")
    if dsn:
        return psycopg.connect(dsn)
    return psycopg.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ.get("PGPASSWORD"),
        dbname=os.environ.get("PGDATABASE", "bodegas_del_atuel"),
    )


def descripcion_conexion(conn: psycopg.Connection) -> str:
    info = conn.info
    return f"{info.dbname} en {info.host}:{info.port} como {info.user} (server {info.server_version})"


# ---------------------------------------------------------------------------
# Triggers
# ---------------------------------------------------------------------------
def deshabilitar_triggers(conn: psycopg.Connection) -> None:
    with conn.cursor() as cur:
        for tabla in TABLAS:
            cur.execute(sql.SQL("ALTER TABLE {} DISABLE TRIGGER USER").format(sql.Identifier(tabla)))


def habilitar_triggers(conn: psycopg.Connection) -> None:
    with conn.cursor() as cur:
        for tabla in TABLAS:
            cur.execute(sql.SQL("ALTER TABLE {} ENABLE TRIGGER USER").format(sql.Identifier(tabla)))


def triggers_pendientes(conn: psycopg.Connection) -> int:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT count(*)
              FROM pg_trigger t
              JOIN pg_class c ON c.oid = t.tgrelid
              JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE NOT t.tgisinternal
               AND n.nspname = 'public'
               AND t.tgenabled <> 'O'
            """
        )
        return int(cur.fetchone()[0])


def verificar_triggers(conn: psycopg.Connection) -> None:
    pendientes = triggers_pendientes(conn)
    if pendientes:
        raise RuntimeError(f"Quedaron {pendientes} triggers de usuario sin re-habilitar")
    print("Triggers de usuario verificados: todos en tgenabled = 'O'.")


def asegurar_triggers(conn: psycopg.Connection) -> None:
    """Red de seguridad fuera de la transacción de carga."""
    try:
        conn.rollback()
        if triggers_pendientes(conn) == 0:
            return
        with conn.transaction():
            habilitar_triggers(conn)
        verificar_triggers(conn)
        print("Se re-habilitaron triggers como medida de seguridad.")
    except Exception as exc:  # pragma: no cover - solo diagnóstico
        print(f"ADVERTENCIA: no se pudieron verificar los triggers: {exc}")


# ---------------------------------------------------------------------------
# Limpieza / verificación de tablas
# ---------------------------------------------------------------------------
def truncar_todo(conn: psycopg.Connection) -> None:
    print("ADVERTENCIA: --limpiar truncará TODAS las tablas, incluidos los catálogos.")
    print("Los catálogos se recargan desde db/seed/catalogos/*.csv.")
    with conn.cursor() as cur:
        cur.execute(
            "TRUNCATE TABLE "
            + ", ".join(TABLAS)
            + " RESTART IDENTITY CASCADE"
        )
    conn.commit()


def verificar_vacias(conn: psycopg.Connection) -> None:
    no_vacias: list[tuple[str, int]] = []
    with conn.cursor() as cur:
        for tabla in TABLAS:
            cur.execute(sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(tabla)))
            n = int(cur.fetchone()[0])
            if n:
                no_vacias.append((tabla, n))
    if no_vacias:
        detalle = ", ".join(f"{t}={n}" for t, n in no_vacias)
        raise RuntimeError(
            "La base no está vacía. Usá --limpiar para truncar y recargar. "
            f"Tablas con filas: {detalle}"
        )
    conn.rollback()


# ---------------------------------------------------------------------------
# Inserción
# ---------------------------------------------------------------------------
def _insert_sql(tabla: str, columnas: list[str], overriding: bool = False) -> str:
    cols = ", ".join(columnas)
    placeholders = ", ".join(["%s"] * len(columnas))
    extra = " OVERRIDING SYSTEM VALUE" if overriding else ""
    return f"INSERT INTO {tabla} ({cols}){extra} VALUES ({placeholders})"


def cargar_tabla(conn: psycopg.Connection, tabla: str, filas: list[tuple[Any, ...]],
                 modo: str) -> None:
    if not filas:
        raise RuntimeError(f"La tabla {tabla} no tiene filas generadas")
    columnas = COLUMNAS[tabla]
    inicio = time.perf_counter()

    if tabla in ("cepa", "maridaje"):
        # Catálogos con IDs fijos: se respetan los IDs del CSV.
        with conn.cursor() as cur:
            cur.executemany(_insert_sql(tabla, columnas, overriding=True), filas)
    elif modo == "copy":
        # psycopg3 Copy.write_row() escribe en formato texto (tabulado).
        copy_sql = (
            f"COPY {tabla} ({', '.join(columnas)}) FROM STDIN "
            "WITH (FORMAT text, NULL '\\N')"
        )
        with conn.cursor() as cur:
            with cur.copy(copy_sql) as copy:
                for fila in filas:
                    copy.write_row(fila)
    elif modo == "lotes":
        insert_sql = _insert_sql(tabla, columnas)
        with conn.cursor() as cur:
            for i in range(0, len(filas), BATCH_SIZE):
                cur.executemany(insert_sql, filas[i:i + BATCH_SIZE])
    elif modo == "fila-por-fila":
        insert_sql = _insert_sql(tabla, columnas)
        with conn.cursor() as cur:
            for fila in filas:
                cur.execute(insert_sql, fila)
    else:
        raise ValueError(f"Modo desconocido: {modo}")

    segundos = time.perf_counter() - inicio
    print(f"  {tabla:<32} {len(filas):>8} filas  {segundos:7.2f} s")


def cargar_todo(conn: psycopg.Connection, rows: dict[str, list[tuple[Any, ...]]],
                modo: str) -> None:
    try:
        with conn.transaction():
            print("Deshabilitando triggers de usuario...")
            deshabilitar_triggers(conn)
            print("Cargando catálogos con IDs explícitos...")
            cargar_tabla(conn, "cepa", rows["cepa"], modo)
            cargar_tabla(conn, "maridaje", rows["maridaje"], modo)
            print(f"Cargando datos en modo {modo}...")
            for tabla in ORDEN_CARGA:
                cargar_tabla(conn, tabla, rows[tabla], modo)
            # Las FK diferibles (por ejemplo localidad -> empleado) dejan
            # eventos de trigger pendientes. Hay que forzarlas antes de
            # re-habilitar los triggers de usuario.
            print("Forzando restricciones diferidas...")
            conn.execute("SET CONSTRAINTS ALL IMMEDIATE")
            print("Re-habilitando triggers de usuario...")
            habilitar_triggers(conn)
            verificar_triggers(conn)
    except Exception:
        conn.rollback()
        raise
    finally:
        asegurar_triggers(conn)


# ---------------------------------------------------------------------------
# ANALYZE y setval
# ---------------------------------------------------------------------------
def analizar_y_setval(conn: psycopg.Connection) -> None:
    with conn.transaction():
        print("Ejecutando ANALYZE...")
        for tabla in TABLAS:
            conn.execute(sql.SQL("ANALYZE {}").format(sql.Identifier(tabla)))
        print("Ajustando secuencias identidad con setval...")
        for tabla, columna in IDENTIDADES:
            with conn.cursor() as cur:
                cur.execute("SELECT pg_get_serial_sequence(%s, %s)", (tabla, columna))
                fila = cur.fetchone()
                secuencia = fila[0] if fila else None
                if not secuencia:
                    continue
                consulta = sql.SQL(
                    "SELECT setval(%s, COALESCE((SELECT MAX({col}) FROM {tabla}), 1), "
                    "(SELECT EXISTS (SELECT 1 FROM {tabla})))"
                ).format(col=sql.Identifier(columna), tabla=sql.Identifier(tabla))
                cur.execute(consulta, (secuencia,))
    print("ANALYZE y setval completados.")


# ---------------------------------------------------------------------------
# Consultas de control
# ---------------------------------------------------------------------------
def _parsear_consultas(path: Path) -> list[dict[str, Any]]:
    consultas: list[dict[str, Any]] = []
    actual: dict[str, Any] | None = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        linea = raw.rstrip()
        if linea.startswith("-- @query:"):
            if actual:
                consultas.append(actual)
            actual = {"nombre": linea.split(":", 1)[1].strip(), "tipo": "problema", "sql": []}
        elif linea.startswith("-- @tipo:"):
            if actual:
                actual["tipo"] = linea.split(":", 1)[1].strip()
        elif actual is not None:
            actual["sql"].append(linea)
    if actual:
        consultas.append(actual)
    for c in consultas:
        c["sql"] = "\n".join(c["sql"]).strip()
    return [c for c in consultas if c["sql"]]


def ejecutar_controles(conn: psycopg.Connection, path: Path,
                       fecha_ref: date | None = None) -> None:
    if not path.exists():
        raise FileNotFoundError(f"No existe el archivo de controles: {path}")
    consultas = _parsear_consultas(path)
    if not consultas:
        raise RuntimeError(f"No se encontraron consultas en {path}")

    if fecha_ref is not None:
        # Las consultas usan esta fecha en lugar de CURRENT_DATE para que los
        # controles sigan siendo válidos aunque se ejecuten otro día.
        conn.execute(
            "SELECT set_config('app.fecha_referencia', %s, true)",
            (fecha_ref.isoformat(),),
        )

    problemas: list[str] = []
    print("\n=== Consultas de control ===")
    for c in consultas:
        with conn.cursor() as cur:
            cur.execute(c["sql"])
            filas = cur.fetchall()
            headers = [d.name for d in (cur.description or [])]
        if c["tipo"] == "info":
            print(f"\n[INFO] {c['nombre']} ({len(filas)} filas)")
            if headers:
                print("  " + " | ".join(headers))
            for fila in filas[:60]:
                print("  " + " | ".join("" if v is None else str(v) for v in fila))
            if len(filas) > 60:
                print(f"  ... {len(filas) - 60} filas más")
        else:
            if filas:
                problemas.append(c["nombre"])
                print(f"\n[PROBLEMA] {c['nombre']}: {len(filas)} filas")
                if headers:
                    print("  " + " | ".join(headers))
                for fila in filas[:30]:
                    print("  " + " | ".join("" if v is None else str(v) for v in fila))
            else:
                print(f"[OK] {c['nombre']} -> 0 problemas")
    conn.rollback()
    if problemas:
        raise RuntimeError("Controles con problemas: " + ", ".join(problemas))
    print("\nTodos los controles de problema devolvieron 0 filas.")


# ---------------------------------------------------------------------------
# Hashes de reproducibilidad
# ---------------------------------------------------------------------------
def _hash_tabla(conn: psycopg.Connection, tabla: str) -> str:
    orden = ORDEN_HASH[tabla]
    h = hashlib.sha256()
    with conn.cursor() as cur:
        with cur.copy(
            f"COPY (SELECT * FROM {tabla} ORDER BY {orden}) TO STDOUT WITH (FORMAT csv)"
        ) as copy:
            for data in copy:
                if isinstance(data, str):
                    data = data.encode("utf-8")
                h.update(data)
    return h.hexdigest()


def calcular_hashes(conn: psycopg.Connection, meta: dict[str, Any],
                    salida: Path) -> dict[str, Any]:
    resultado: dict[str, Any] = {
        "meta": meta,
        "tablas": {},
        "combined": "",
    }
    combinado = hashlib.sha256()
    for tabla in TABLAS:
        with conn.cursor() as cur:
            cur.execute(sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(tabla)))
            cantidad = int(cur.fetchone()[0])
        huella = _hash_tabla(conn, tabla)
        resultado["tablas"][tabla] = {"filas": cantidad, "sha256": huella}
        combinado.update(f"{tabla}:{huella}\n".encode("utf-8"))
    resultado["combined"] = combinado.hexdigest()
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text(json.dumps(resultado, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
    print(f"Hash combinado: {resultado['combined']}")
    print(f"Hashes escritos en {salida}")
    return resultado


def comparar_hashes(path_a: Path, path_b: Path) -> bool:
    a = json.loads(path_a.read_text(encoding="utf-8"))
    b = json.loads(path_b.read_text(encoding="utf-8"))
    print(f"A: {path_a} -> {a.get('combined')}")
    print(f"B: {path_b} -> {b.get('combined')}")
    if a.get("combined") == b.get("combined"):
        print("RESULTADO: hashes idénticos (carga reproducible).")
        return True
    print("RESULTADO: hashes distintos.")
    tablas_a = a.get("tablas", {})
    tablas_b = b.get("tablas", {})
    for tabla in sorted(set(tablas_a) | set(tablas_b)):
        ha = (tablas_a.get(tabla) or {}).get("sha256")
        hb = (tablas_b.get(tabla) or {}).get("sha256")
        if ha != hb:
            print(f"  Diferencia en {tabla}: {ha} != {hb}")
    return False


# ---------------------------------------------------------------------------
# Benchmark de cliente
# ---------------------------------------------------------------------------
def _crear_tabla_bench(conn: psycopg.Connection) -> None:
    with conn.cursor() as cur:
        cur.execute("DROP TABLE IF EXISTS bench_cliente")
        cur.execute(
            """
            CREATE UNLOGGED TABLE bench_cliente (
                tipo tipo_cliente NOT NULL,
                nombre VARCHAR(60),
                apellido VARCHAR(60),
                razon_social VARCHAR(120),
                calle VARCHAR(60) NOT NULL,
                numero VARCHAR(10) NOT NULL,
                estado_activo BOOLEAN NOT NULL,
                codigo_postal cp_dominio NOT NULL,
                tipo_documento VARCHAR(10) NOT NULL,
                numero_documento VARCHAR(20) NOT NULL,
                fecha_alta DATE NOT NULL
            )
            """
        )
        cur.execute(
            "CREATE UNIQUE INDEX bench_cliente_uk ON bench_cliente "
            "(tipo_documento, numero_documento) WHERE estado_activo"
        )
    conn.commit()


def _truncar_bench(conn: psycopg.Connection) -> None:
    conn.execute("TRUNCATE bench_cliente")
    conn.commit()


def ejecutar_benchmark(conn: psycopg.Connection, seed: int, filas: int,
                       fecha_ref: date = date(2026, 11, 10)) -> None:
    print("\n=== Benchmark de carga de cliente ===")
    gen = DataGenerator(seed=seed, fecha_ref=fecha_ref, escala=1.0,
                        n_clientes_override=filas)
    gen.load_catalogs()
    gen.generate_clientes()
    datos = gen.rows["cliente"][:filas]
    if len(datos) != filas:
        raise RuntimeError("No se generaron suficientes filas para el benchmark")
    columnas = COLUMNAS["cliente"]
    insert_sql = _insert_sql("bench_cliente", columnas)
    _crear_tabla_bench(conn)
    resultados: list[tuple[str, float]] = []

    # 1) COPY
    _truncar_bench(conn)
    inicio = time.perf_counter()
    copy_sql = ("COPY bench_cliente (" + ", ".join(columnas) + ") FROM STDIN "
                "WITH (FORMAT text, NULL '\\N')")
    with conn.transaction():
        with conn.cursor() as cur:
            with cur.copy(copy_sql) as copy:
                for fila in datos:
                    copy.write_row(fila)
    resultados.append(("COPY", time.perf_counter() - inicio))

    # 2) Lotes de 5.000
    _truncar_bench(conn)
    inicio = time.perf_counter()
    with conn.transaction():
        with conn.cursor() as cur:
            for i in range(0, len(datos), BATCH_SIZE):
                cur.executemany(insert_sql, datos[i:i + BATCH_SIZE])
    resultados.append(("lotes 5.000", time.perf_counter() - inicio))

    # 3) Fila por fila, una sola transacción
    _truncar_bench(conn)
    inicio = time.perf_counter()
    with conn.transaction():
        with conn.cursor() as cur:
            for fila in datos:
                cur.execute(insert_sql, fila)
    resultados.append(("fila por fila (1 tx)", time.perf_counter() - inicio))

    # 4) Fila por fila, commit por fila
    _truncar_bench(conn)
    conn.autocommit = True
    inicio = time.perf_counter()
    try:
        with conn.cursor() as cur:
            for fila in datos:
                cur.execute(insert_sql, fila)
    finally:
        conn.autocommit = False
    resultados.append(("fila por fila (commit por fila)", time.perf_counter() - inicio))

    with conn.cursor() as cur:
        cur.execute("DROP TABLE bench_cliente")
    conn.commit()

    print(f"Filas benchmark: {filas}")
    print(f"{'Modo':<38} {'Segundos':>10} {'Filas/s':>12}")
    for nombre, segundos in resultados:
        print(f"{nombre:<38} {segundos:>10.3f} {filas / segundos:>12.1f}")
    base = next(s for n, s in resultados if n == "COPY")
    print("\nRespecto de COPY:")
    for nombre, segundos in resultados:
        if nombre != "COPY":
            print(f"  {nombre}: {segundos / base:.2f}x")
