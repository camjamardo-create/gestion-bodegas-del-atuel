# API REST de Bodegas del Atuel (Etapa 6)

API HTTP sobre la base PostgreSQL construida en las etapas anteriores. Está
implementada con **Python 3.12**, **FastAPI**, **psycopg 3** y
**psycopg_pool**. No usa ORM ni query builders.

La API **no recalcula reglas de negocio**. Los totales, descuentos, subtotales,
movimientos de stock, estados y auditoría de precios se siguen resolviendo con
las funciones, procedimientos y triggers de la base. La API solo valida el
formato de entrada, arma consultas parametrizadas y traduce los errores de
PostgreSQL a HTTP.

## Estructura

```text
api/
├── app/
│   ├── config.py        Variables de entorno y validación del rol
│   ├── db.py            Pool de conexiones y transacciones explícitas
│   ├── errors.py        Traducción centralizada de SQLSTATE a HTTP
│   ├── main.py          Aplicación FastAPI y lifespan del pool
│   ├── schemas.py       Modelos Pydantic de entrada/salida
│   ├── repositories/    Todo el SQL de la API
│   └── routers/         Endpoints HTTP
├── tests/               Pruebas de integración contra PostgreSQL real
├── Dockerfile
├── export_openapi.py
└── requirements.txt
```

Todo el SQL de la aplicación vive en `app/repositories/`. Las consultas usan
parámetros `%s` de psycopg; los únicos fragmentos dinámicos son el orden y la
dirección de `GET /vinos`, elegidos desde una lista blanca.

## Variables de entorno

Copiar `.env.example` a `.env` y completar los valores locales. `.env` está
excluido por `.gitignore`.

| Variable | Uso | Valor por defecto |
| --- | --- | --- |
| `POSTGRES_PASSWORD` | Clave del usuario propietario de PostgreSQL en Compose | Obligatoria |
| `POSTGRES_PORT` | Puerto local de PostgreSQL | `5433` |
| `APP_DB_PASSWORD` | Clave de `rol_api`; se usa en la API y en el init del volumen | Obligatoria |
| `API_PORT` | Puerto local de la API | `8000` |
| `DB_HOST` | Host de PostgreSQL para ejecución local | `localhost` |
| `DB_PORT` | Puerto de PostgreSQL para ejecución local | `5433` |
| `DB_NAME` | Nombre de la base | `bodegas_del_atuel` |
| `DB_USER` | Rol de conexión de la API | `rol_api` |
| `DB_PASSWORD` | Clave de `rol_api` para ejecución local | Obligatoria |
| `DB_POOL_MIN_SIZE` | Conexiones mínimas del pool | `1` |
| `DB_POOL_MAX_SIZE` | Conexiones máximas del pool | `10` |
| `DB_POOL_TIMEOUT` | Segundos de espera por conexión | `10` |

La configuración rechaza cualquier `DB_USER` distinto de `rol_api`. La API nunca
se conecta con `postgres` ni con el propietario de la base.

## Arranque con Docker Compose

Desde la raíz del repositorio:

```powershell
Copy-Item .env.example .env
# Editar .env y definir POSTGRES_PASSWORD y APP_DB_PASSWORD
docker compose up -d --build
```

Servicios:

- PostgreSQL: `localhost:5433` (o `POSTGRES_PORT`).
- API: `localhost:8000` (o `API_PORT`).
- Documentación interactiva: <http://localhost:8000/docs>.
- OpenAPI: <http://localhost:8000/openapi.json>.
- Salud: <http://localhost:8000/salud>.

Verificación rápida:

```powershell
Invoke-RestMethod http://localhost:8000/salud
```

Respuesta esperada:

```json
{"status":"ok","base_de_datos":"ok","current_user":"rol_api"}
```

En un volumen nuevo, PostgreSQL ejecuta automáticamente:

1. `db/initdb/01_migraciones.sql`: aplica `001` a `008`.
2. `db/initdb/02_seed_minimo.sql`: carga un catálogo mínimo para operar y probar.
3. `db/initdb/99_password_api.sql`: reemplaza la clave de ejemplo de `rol_api`
   por `APP_DB_PASSWORD`.

> Los scripts de `/docker-entrypoint-initdb.d` solo se ejecutan si el volumen de
> datos está vacío. Si el volumen ya existía antes de esta etapa, los scripts no
> se vuelven a ejecutar. Para una inicialización limpia (destructiva):
>
> ```bash
> docker compose down -v
> docker compose up -d --build
> ```
>
> Si se conserva un volumen existente, hay que asegurarse de que la clave de
> `rol_api` coincida con `APP_DB_PASSWORD`.

## Arranque local sin Docker para la API

Con PostgreSQL ya levantado:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r api/requirements.txt

Set-Location api
$env:DB_HOST = "localhost"
$env:DB_PORT = "5433"
$env:DB_NAME = "bodegas_del_atuel"
$env:DB_USER = "rol_api"
$env:DB_PASSWORD = "<clave_de_rol_api_definida_en_.env>"
..\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
```

## Endpoints

| Método | Ruta | Descripción |
| --- | --- | --- |
| `GET` | `/salud` | Estado de la API y de la conexión; incluye `current_user`. |
| `GET` | `/vinos` | Listado paginado con filtros `tipo`, `cepa`, `bodega`, `anada`, `nombre`, `orden` y `direccion`. |
| `GET` | `/vinos/{codigo}` | Ficha del vino, bodega, cepas, maridajes y stock. |
| `POST` | `/vinos` | Alta de vino y su composición/maridajes. |
| `PUT` | `/vinos/{codigo}` | Actualización parcial; el precio se audita por trigger. |
| `DELETE` | `/vinos/{codigo}` | Baja; la base rechaza si hay stock o ventas asociadas. |
| `GET` | `/clientes` | Listado paginado con filtros `tipo`, `estado_activo` y `documento`. |
| `GET` | `/clientes/{id}` | Detalle de los cuatro subtipos; incluye permisos del exportador. |
| `POST` | `/clientes` | Alta mediante `p_crear_cliente`. |
| `PUT` | `/clientes/{id}` | Actualización; el cambio de tipo usa `p_cambiar_tipo_cliente`. |
| `DELETE` | `/clientes/{id}` | Baja; la base rechaza si tiene comprobantes. |
| `POST` | `/comprobantes` | Venta: cabecera y renglones. Los totales y el stock los calculan los triggers. |
| `GET` | `/comprobantes/{numero}` | Comprobante con totales, descuento, cliente, sala y renglones. |
| `POST` | `/transferencias` | Crea una transferencia en estado `en_confeccion`. |
| `GET` | `/transferencias/{numero}` | Detalle con renglones. |
| `POST` | `/transferencias/{numero}/renglones` | Agrega uno o varios renglones. |
| `POST` | `/transferencias/{numero}/terminar` | Pasa a `terminado`; el trigger valida la transición. |
| `POST` | `/transferencias/{numero}/procesar` | Ejecuta `p_procesar_transferencia` y mueve stock. |
| `POST` | `/ingresos` | Crea un ingreso al depósito. |
| `GET` | `/ingresos/{codigo}` | Detalle con renglones. |
| `POST` | `/ingresos/{codigo}/renglones` | Agrega uno o varios renglones. |
| `POST` | `/ingresos/{codigo}/terminar` | Pasa a `terminado`; el trigger valida la transición. |
| `POST` | `/ingresos/{codigo}/procesar` | Ejecuta `p_procesar_ingreso` y suma stock al depósito. |
| `GET` | `/reportes/top-vinos` | S1: vinos más vendidos. |
| `GET` | `/reportes/ventas-por-sala` | S8: ventas por sala en el último trimestre. |
| `GET` | `/reportes/vinos-sin-stock?sala={id}` | S6: vinos sin stock en una sala pero con stock en depósito. |
| `GET` | `/reportes/transportista-activo` | S7: transportista con más actividad en el último mes. |
| `GET` | `/reportes/trazabilidad/{codigo}` | S9: ficha/trazabilidad del vino con cepas, bodega, maridajes y stock. |

Los importes y porcentajes de tipo `NUMERIC` se devuelven como string JSON para
no perder precisión. Por ejemplo, `"precio": "12500.00"`.

## Errores

El manejador central de `app/errors.py` traduce los SQLSTATE más relevantes:

| SQLSTATE | HTTP | Caso |
| --- | --- | --- |
| `P0001` | `409 Conflict` | Regla de negocio lanzada por función, trigger o procedimiento. Se conserva el mensaje original. |
| `23505` | `409 Conflict` | Restricción `UNIQUE`. |
| `23503` | `422 Unprocessable Entity` | Referencia a una fila inexistente. Si la fila todavía tiene dependientes, `409`. |
| `23514` | `422 Unprocessable Entity` | Restricción `CHECK`. |
| `23502` | `422 Unprocessable Entity` | Columna `NOT NULL`. |
| `22P02`, `22001`, `22003` | `400 Bad Request` | Formato o longitud inválida. |
| `40001`, `40P01` | `503 Service Unavailable` | Serialización o deadlock; se sugiere reintentar. |
| `08*`, `53300`, `57P03` | `503 Service Unavailable` | Base caída o saturada. |
| `PoolTimeout` | `503 Service Unavailable` | No hay conexiones disponibles en el pool. |

Formato de error:

```json
{
  "error": {
    "codigo": "P0001",
    "mensaje": "Stock insuficiente del vino 123 en la sala 4: disponible 0, solicitado 1"
  }
}
```

Cuando PostgreSQL informa el nombre de una restricción (`constraint_name`), se
agrega además la clave `regla`.

## Pruebas automáticas

Las pruebas usan `pytest`, `TestClient` y una conexión real a PostgreSQL. No
mockean la base: verifican triggers, funciones, procedimientos, restricciones y
transacciones.

Con Docker Compose levantado:

```powershell
Set-Location api
$env:DB_HOST = "localhost"
$env:DB_PORT = "5433"
$env:DB_NAME = "bodegas_del_atuel"
$env:DB_USER = "rol_api"
$env:DB_PASSWORD = "<clave_de_rol_api_definida_en_.env>"
..\.venv\Scripts\python.exe -m pytest -q
```

También se puede ejecutar contra un volumen nuevo; el seed mínimo provee los
catálogos necesarios.

Cobertura actual (13 pruebas):

- salud y verificación de que la conexión usa `rol_api`;
- listado, filtros y reportes;
- alta, consulta, modificación y baja de vinos;
- alta de los cuatro subtipos de cliente, permisos de exportador y baja;
- cambio de tipo de cliente: desactiva la versión anterior y crea una nueva
  versión activa;
- precio negativo rechazado por `CHECK` (`23514`);
- composición que no suma 100: el trigger diferido falla al `COMMIT` y la
  transacción completa se revierte;
- venta sin stock: `409`, sin cabecera de comprobante residual;
- venta exitosa con subtotal, descuento de socio, total y stock calculados por la
  base;
- transferencia procesada sin estar terminada: `409`;
- transferencia sin stock en depósito: `409`, sin modificar stock;
- intento de inyección SQL en filtros: se trata como texto, no altera datos;
- referencia foránea inexistente: `422`.

Resultado de la última ejecución:

```text
13 passed
```

## Demostración de inyección SQL

El filtro `nombre` de `/vinos` se pasa como parámetro a psycopg. Un valor como
`' OR 1=1 --` no se concatena al SQL: se busca literalmente como parte del
nombre.

Con PowerShell:

```powershell
$antes = Invoke-RestMethod "http://localhost:8000/vinos?page_size=1"
$inyeccion = Invoke-RestMethod "http://localhost:8000/vinos?nombre=%27%20OR%201%3D1%20--"
$despues = Invoke-RestMethod "http://localhost:8000/vinos?page_size=1"

"Total antes: $($antes.total)"
"Resultados de la inyección: $($inyeccion.total)"
"Total después: $($despues.total)"
```

Resultado esperado (el total inicial depende de los datos cargados):

```text
Total antes: N
Resultados de la inyección: 0
Total después: N
```

Con `curl`:

```bash
curl --get "http://localhost:8000/vinos" \
  --data-urlencode "nombre=' OR 1=1 --"
```

La consulta sigue devolviendo `200 OK`, pero no filtra todo el catálogo ni
modifica la base. Además, `tipo` está tipado como un literal cerrado
(`tinto`, `blanco`, `rosado`, `espumante`), por lo que un valor como
`tinto' OR '1'='1` se rechaza con `422` antes de llegar al SQL.

## OpenAPI

El contrato se exporta a `docs/api/openapi.json`:

```powershell
Set-Location api
..\.venv\Scripts\python.exe export_openapi.py
```

El archivo generado incluye los 23 paths de la API y los esquemas de Pydantic.
También está disponible en ejecución en `/openapi.json` y `/docs`.

## Supuestos y notas

- La trazabilidad S9 se expone como ficha/trazabilidad del **vino** (cepas,
  bodega, maridajes y stock), que es la entidad disponible en el esquema de la
  Etapa 3. No se inventaron tablas ni columnas para una trazabilidad de lote que
  no existe en el modelo.
- La API llama a `p_crear_cliente` y `p_cambiar_tipo_cliente`; el cambio de tipo
  genera una nueva versión activa del cliente y deja la anterior inactiva, tal
  como define el procedimiento.
- `terminar` actualiza el estado directamente; el trigger de transición es el
  que decide si el cambio es válido. `procesar` siempre pasa por los
  procedimientos de la base.
- La clave hardcodeada de `rol_api` en `007_roles.sql` queda reemplazada en
  Docker por `APP_DB_PASSWORD`. No se versiona ningún `.env`.
- No se modificaron `db/migrations/` ni `db/seed/` en esta etapa. Los scripts de
  inicialización nuevos están en `db/initdb/`.
