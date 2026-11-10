# Carga masiva — Bodegas del Atuel (Etapa 3)

Script determinista de carga masiva para el esquema de `db/migrations`.
Genera datos coherentes con `random`, `Faker(es_AR)` y SQL escrito a mano
(psycopg 3), sin ORM ni query builder.

> **Uso académico/local.** `--limpiar` trunca todas las tablas, incluidos los
> catálogos. No ejecutar sobre una base con datos reales.

## 1. Requisitos

- PostgreSQL 18 (probado con 18.6).
- Python 3.11 o superior.
- Docker Compose (opcional, recomendado para el entorno local).
- `psql` y `pg_dump` en el `PATH` para migraciones y dump.

Dependencias Python:

```text
psycopg[binary]>=3.2,<4
Faker>=30,<50
```

## 2. Puesta en marcha

### 2.1. Base local con Docker

```bash
cp .env.example .env
# Editar .env y definir POSTGRES_PASSWORD.
docker compose up -d
docker compose ps
```

El contenedor se llama `bodegas_del_atuel_etapa3`, publica PostgreSQL en
`localhost:5433` y usa la base `bodegas_del_atuel`.

### 2.2. Migraciones

Con el puerto y la base del ejemplo:

```bash
export PGPASSWORD='la_clave_local'
for f in db/migrations/*.sql; do
  psql -h localhost -p 5433 -U postgres -d bodegas_del_atuel \
       -v ON_ERROR_STOP=1 -f "$f"
done
```

En PowerShell:

```powershell
$env:PGPASSWORD = 'la_clave_local'
Get-ChildItem db/migrations/*.sql | Sort-Object Name | ForEach-Object {
  psql -h localhost -p 5433 -U postgres -d bodegas_del_atuel `
       -v ON_ERROR_STOP=1 -f $_.FullName
}
```

`007_roles.sql` asume el nombre de base `bodegas_del_atuel`; si se usa otro
nombre, ajustar ese archivo o crear los roles por separado.

### 2.3. Entorno Python

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r db/seed/requirements.txt
```

En Linux/macOS:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r db/seed/requirements.txt
```

### 2.4. Conexión

El script usa las variables de entorno y completa las que falten desde `.env` de
la raíz del proyecto (si existe). Se puede usar una cadena completa:

```powershell
$env:DATABASE_URL = 'postgresql://postgres:CLAVE@localhost:5433/bodegas_del_atuel'
```

o las variables `PG*`:

```powershell
$env:PGHOST = 'localhost'
$env:PGPORT = '5433'
$env:PGUSER = 'postgres'
$env:PGPASSWORD = 'CLAVE'
$env:PGDATABASE = 'bodegas_del_atuel'
```

No hay credenciales en el código. `.env` está en `.gitignore`.

## 3. Ejecución

Carga completa con los valores por defecto (`seed=42`,
`fecha-ref=2026-11-10`, `escala=1.0`, `modo=copy`):

```bash
python db/seed/cargar_datos.py --limpiar
```

El script:

1. Genera todos los datos en memoria.
2. Verifica que la base esté vacía (o trunca con `--limpiar`).
3. Deshabilita únicamente triggers de usuario con
   `ALTER TABLE ... DISABLE TRIGGER USER`.
4. Carga catálogos con IDs explícitos y el resto con el modo elegido.
5. Fuerza las restricciones diferidas con `SET CONSTRAINTS ALL IMMEDIATE`.
6. Rehabilita los triggers antes del `COMMIT` y verifica
   `pg_trigger.tgenabled = 'O'`.
7. Ejecuta `ANALYZE` sobre las 30 tablas y ajusta las 14 secuencias identidad
   con `setval`.
8. Corre las consultas de control y falla si alguna consulta de problema
   devuelve filas.

### 3.1. Opciones

| Opción | Descripción |
|---|---|
| `--seed N` | Semilla para `random` y `Faker` (default `42`). |
| `--fecha-ref YYYY-MM-DD` | Fecha de referencia fija (default `2026-11-10`). |
| `--escala X` | Escala de volúmenes (default `1.0`). `0.1` sirve para pruebas rápidas. |
| `--modo copy\|lotes\|fila-por-fila` | Método de inserción (default `copy`). |
| `--limpiar` | `TRUNCATE ... RESTART IDENTITY CASCADE` de las 30 tablas y recarga. |
| `--sin-control` | No ejecuta `consultas_control.sql`. |
| `--hash-out ARCHIVO` | Guarda conteos y SHA-256 por tabla en JSON. |
| `--compare-hashes A B` | Compara dos JSON de `--hash-out` y sale. |
| `--benchmark` | Ejecuta solo el benchmark de `cliente` y sale. |
| `--benchmark-filas N` | Filas del benchmark (default `10000`). |

`--limpiar` también trunca `cepa`, `maridaje` y `localidad`; los catálogos se
recargan desde `db/seed/catalogos/*.csv`. Sin `--limpiar`, si alguna tabla tiene
filas el script aborta antes de modificar nada.

Para una prueba rápida:

```bash
python db/seed/cargar_datos.py --limpiar --escala 0.1 --sin-control
```

Los controles de volumen (`q02`) exigen la escala completa: con `0.1` no se
alcanzan las 3 tablas de más de 10.000 filas ni la tabla de más de 100.000.

### 3.2. Modos de carga

- `copy` (default): `COPY ... FROM STDIN` con psycopg 3.
- `lotes`: `executemany` en lotes de 5.000 filas.
- `fila-por-fila`: `execute` por fila, una sola transacción.

Los catálogos `cepa` y `maridaje` siempre usan `INSERT ... OVERRIDING SYSTEM
VALUE` para respetar los IDs de los CSV.

## 4. Catálogos CSV

Están en `db/seed/catalogos/`, en UTF-8 y separados por coma.

| Archivo | Contenido |
|---|---|
| `cepas.csv` | 12 cepas reales. La cepa 12 (Semillón) queda sin uso a propósito. |
| `maridajes.csv` | 8 maridajes; ids 1 y 2 son “Carnes rojas” y “Quesos duros”. |
| `localidades.csv` | 18 localidades de Mendoza con código postal real; incluye General Alvear (`5620`) y San Rafael (`5600`). |
| `tipos_vino.csv` | `tinto`, `blanco`, `rosado`, `espumante` (ENUM). |
| `presentaciones.csv` | 187, 375, 750, 1500 y 3000 ml. |

El vino obligatorio es el código 1: **Malbec Reserva**, añada 2021, 750 ml,
14,00°, $12.500, Malbec 85 % + Cabernet Sauvignon 15 %, maridajes “Carnes
rojas” y “Quesos duros”.

## 5. Volúmenes

Con `--escala 1.0` y `--seed 42` la corrida real generó:

| Tabla | Filas | Tabla | Filas |
|---|---:|---|---:|
| `bodega` | 20 | `cliente` | 20.000 |
| `finca` | 30 | `cliente_comun` | 8.000 |
| `cepa` | 12 | `socio_club` | 8.000 |
| `maridaje` | 8 | `distribuidor` | 2.400 |
| `transportista` | 12 | `exportador` | 1.600 |
| `localidad` | 18 | `permiso` | 3.937 |
| `sala_venta` | 24 | `parcela` | 600 |
| `empleado` | 80 | `lote` | 900 |
| `transportista_cubre_localidad` | 46 | `analisis_calidad` | 3.180 |
| `ingreso` | 1.200 | `vino` | 500 |
| `renglon_ingreso` | 3.767 | `composicion` | 946 |
| `transferencia` | 1.300 | `stock_deposito` | 500 |
| `renglon_transferencia` | 12.255 | `vino_maridaje` | 886 |
| `comprobante` | 150.000 | `auditoria_precio` | 132 |
| `renglon_comprobante` | 564.328 | `stock_sala` | 12.000 |

Se cumplen los mínimos: las 30 tablas tienen al menos 1 fila, 5 tablas superan
las 10.000 filas y 2 superan las 100.000.

Con `--escala 0.1` se generan 2.000 clientes, 15.000 comprobantes y 57.377
renglones; sirve para probar el flujo, no para validar los mínimos de volumen.

## 6. Coherencia y triggers

Los triggers de usuario se deshabilitan solo durante la transacción de carga:

```sql
ALTER TABLE ... DISABLE TRIGGER USER;
-- carga
SET CONSTRAINTS ALL IMMEDIATE;  -- resuelve la FK diferible localidad -> empleado
ALTER TABLE ... ENABLE TRIGGER USER;
```

No se usa `session_replication_role`. La habilitación se hace antes del
`COMMIT`; además hay un `try/finally` que vuelve a habilitar y verificar si algo
falla. Al final se comprueba que los 16 triggers de usuario tengan
`tgenabled = 'O'`.

Como los triggers de stock, totales, precios históricos y fechas están
deshabilitados, el generador calcula en Python:

- `stock_deposito = Σ ingresos procesados − Σ transferencias procesadas`.
- `stock_sala = Σ transferencias procesadas − Σ ventas`.
- `subtotal = Σ(cantidad × precio_unitario)`.
- `total = round(subtotal × (1 − descuento_aplicado), 2)`.
- `descuento_total = subtotal − total`.
- El precio de cada renglón es el vigente a la fecha de la venta.
- Los cambios de precio se registran a mano en `auditoria_precio`.

No se llaman los procedimientos de la API (`p_procesar_ingreso`,
`p_procesar_transferencia`, etc.). Es una decisión deliberada para que el
script sea autónomo; el riesgo es que un cambio futuro en esos procedimientos
deje las fórmulas de Python desactualizadas. Los controles detectan las
inconsistencias principales.

## 7. Consultas de control

`db/seed/consultas_control.sql` contiene 11 controles:

| Control | Qué verifica |
|---|---|
| `q01` | Conteo informativo de las 30 tablas. |
| `q02` | Todas las tablas con filas; ≥3 tablas >10.000 y ≥1 >100.000. |
| `q03` | Stock no negativo, todos los vinos con stock de depósito, stock final igual al flujo y un par vino/sala en cero con depósito positivo. |
| `q04` | Subtotales, totales y descuentos de comprobantes. |
| `q05` | Composición suma 100; tintos solo con tintas, blancos solo con blancas; Semillón sin uso. |
| `q06` | Fechas lógicas, ingreso antiguo, ventas en la última semana/mes/trimestre y ventas >5 años. |
| `q07` | Un subtipo por cliente, descuentos, permisos de exportadores, socios antiguos sin compras y ventas >5 años. |
| `q08` | Cobertura: 1 par vino/sala sin vender, el par (sala 1, vino 1), y todas las filas de `stock_sala`. |
| `q09` | Estados de ingresos y transferencias, y permisos vencidos. |
| `q10` | Precios, graduación, volumen, porcentajes y al menos un precio histórico distinto del actual. |
| `q11` | Secuencias identidad alineadas con el máximo de cada tabla. |

Las consultas usan la variable de sesión `app.fecha_referencia`, que el script
setea con `--fecha-ref`. Si se ejecuta el archivo a mano, la variable no existe
y se usa `CURRENT_DATE` como respaldo.

Salida esperada: `q01` muestra 30 filas; `q02` a `q11` devuelven 0 filas.

## 8. Reproducibilidad

La carga es determinista para la misma semilla, fecha y escala. El script puede
guardar un hash por tabla:

```bash
python db/seed/cargar_datos.py --limpiar --seed 42 --fecha-ref 2026-11-10 \
  --hash-out db/seed/evidencias/hashes_run1.json

python db/seed/cargar_datos.py --limpiar --seed 42 --fecha-ref 2026-11-10 \
  --hash-out db/seed/evidencias/hashes_run2.json

python db/seed/cargar_datos.py \
  --compare-hashes db/seed/evidencias/hashes_run1.json \
                   db/seed/evidencias/hashes_run2.json
```

El hash se calcula con `COPY (SELECT * FROM tabla ORDER BY clave) TO STDOUT`.
En la corrida real, las cuatro evidencias (`run1`, `run2`, `run3` y la base
restaurada) dieron el mismo hash combinado:

```text
5865ce1cc63f998d109af49a3f9e44656ff8935f3a743459ccf1697cb1d01745
```

Ver `db/seed/evidencias/README.md`.

## 9. Benchmark

```bash
python db/seed/cargar_datos.py --benchmark --benchmark-filas 10000
```

La corrida real en el PostgreSQL 18 local (Docker, puerto 5433) dio:

| Modo | Segundos | Filas/s | Respecto de COPY |
|---|---:|---:|---:|
| COPY | 0,072 | 138.017,5 | 1,00x |
| Lotes de 5.000 | 0,653 | 15.306,1 | 9,02x |
| Fila por fila, 1 transacción | 5,028 | 1.988,9 | 69,39x |
| Fila por fila, commit por fila | 5,140 | 1.945,5 | 70,94x |

Los tiempos son de una máquina local y sirven para comparar los modos entre sí,
no como benchmark absoluto. Una segunda corrida de 10.000 filas dio COPY
0,079 s, lotes 0,476 s, fila por fila 4,319 s y commit por fila 4,569 s; la
variación es esperable por la caché y la carga del contenedor.

## 10. Dump y restauración

```bash
export DATABASE_URL='postgresql://postgres:CLAVE@localhost:5433/bodegas_del_atuel'
./db/seed/generar_dump.sh
```

El script usa:

```text
pg_dump --format=plain --no-owner --no-privileges --clean --if-exists \
        --encoding=UTF8
gzip -9
```

Salida por defecto: `db/seed/dump_completo.sql.gz` (ignorado por git). En la
corrida real pesó 6.266.618 bytes (6,0 MiB).

Restauración en una base vacía:

```bash
createdb -h localhost -p 5433 -U postgres bodegas_del_atuel_restore
gunzip -c db/seed/dump_completo.sql.gz | \
  psql -h localhost -p 5433 -U postgres \
       -d bodegas_del_atuel_restore -v ON_ERROR_STOP=1
```

El dump no incluye roles. Si se necesitan, ejecutar `007_roles.sql` o crearlos
aparte. Como se usa `--clean --if-exists`, restaurar sobre una base existente
elimina y recrea los objetos.

La restauración real se validó con los 11 controles (0 problemas) y con el
mismo hash combinado de la carga original.

## 11. Archivos

```text
db/seed/
  cargar_datos.py          # CLI
  cargador.py              # conexión, COPY/lotes/filas, triggers, controles, hashes
  generador.py             # generación determinista y cálculos de coherencia
  consultas_control.sql    # 11 controles
  generar_dump.sh          # dump plano + gzip
  requirements.txt
  catalogos/*.csv
  evidencias/*.json
  README.md
```

El informe con los números de la corrida real está en
`docs/informe_etapa3_carga_masiva.md`.
