# Bodegas del Atuel — TPI Bases de Datos
Modelado y desarrollo de la base de datos de **Bodegas del Atuel**, una empresa
vitivinícola ficticia que integra la producción de uva y vino con su distribución
y venta a través de una red de salas de venta.


## Descripción del proyecto

El objetivo es construir el corazón de un sistema de gestión para una bodega:
un modelo de datos normalizado, implementado en PostgreSQL, que garantice las
reglas de negocio dentro de la propia base y que luego sea consumido por una API
REST y un front.

El sistema cubre, entre otros procesos:

- **Red comercial:** localidades, salas de venta, empleados y encargados regionales.
- **Producción:** fincas, parcelas, cepas, campañas, lotes de uva y análisis de calidad.
- **Producto:** bodegas, vinos, composición de cepas, maridajes y precios.
- **Ventas:** clientes (socios, distribuidores, exportadores), comprobantes y renglones.
- **Logística y stock:** depósito central, ingresos, transferencias y stock por sala.
- **Auditoría:** historial de cambios de precio de los vinos.

La base se implementa con **SQL escrito a mano**. No se permite ORM ni
herramientas que oculten el SQL.

---

## Integrantes

|   Integrante   |   Legajo   |   GitHub   |
|   ----------   |   ------   |   ------   |
| Jamardo, Camila | 10842 | [@camjamardo-create](https://github.com/camjamardo-create) |
| Sirotiuk, Juliana | 10939 | [@julisirotiuk](https://github.com/julisirotiuk) |
 
---

## Requisitos
Para trabajar con el proyecto en local:

- [PostgreSQL 14+](https://www.postgresql.org/download/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- Cliente SQL: `psql`, DBeaver o pgAdmin
- [draw.io](https://app.diagrams.net/) para editar el DER
- Python 3.11+ (Etapa 3, carga masiva)
- Git

---

## Guía completa para levantar y usar la app

Esta es la forma recomendada de probar el proyecto completo: PostgreSQL, API y
front. Todo se levanta con Docker Compose; no hace falta instalar PostgreSQL en
la máquina.

### 1. Requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) con Docker Compose.
- Git.
- Puertos libres: `5433` (PostgreSQL), `8000` (API) y `8080` (front).
- Opcional: Python 3.11+ (probado con 3.12) para ejecutar la carga masiva y los
  tests desde la máquina.

Verificar que Docker esté funcionando:

```bash
docker --version
docker compose version
```

### 2. Preparar las variables de entorno

Copiar la plantilla:

**PowerShell:**

```powershell
Copy-Item .env.example .env
```

**Bash / Git Bash / WSL:**

```bash
cp .env.example .env
```

Editar `.env` y reemplazar **todos** los valores `definir_en_local` por valores
reales. En particular:

```text
POSTGRES_PASSWORD=<clave-del-propietario>
APP_DB_PASSWORD=<clave-de-rol_api>
APP_REPORT_PASSWORD=<clave-de-rol_reporte>
DB_PASSWORD=<la misma clave que APP_DB_PASSWORD>
```

`DB_PASSWORD` debe coincidir con `APP_DB_PASSWORD`: la API y los scripts de
migración usan esa entrada. `POSTGRES_PASSWORD` y `APP_REPORT_PASSWORD` deben
ser distintas. Si se usa `DATABASE_URL`, actualizar también la clave del
propietario en esa cadena; los scripts de carga la reemplazan por las variables
`PG*`, pero otros comandos pueden usarla directamente.

Para desarrollo local dejar:

```text
DB_SSLMODE=disable
CORS_ORIGINS=http://localhost:8080
API_BASE_URL=/api
```

`.env` está ignorado por Git: no se debe commitear ni compartir. El repositorio
solo versiona `.env.example` y `.env.production.example` con placeholders.

### 3. Levantar la aplicación

Desde la raíz del repositorio:

```bash
docker compose up -d --build
```

La primera vez, el volumen nuevo de PostgreSQL ejecuta automáticamente las
migraciones `001` a `008` y carga un catálogo mínimo para que la API tenga datos.

> Si ya existe un volumen de una prueba anterior, `db/initdb` **no** se ejecuta
> otra vez. Para una prueba limpia hay que hacer backup y usar
> `docker compose down -v` (borra los datos) antes de volver a levantar.

Verificar el estado:

```bash
docker compose ps
```

Los servicios `postgres`, `api` y `front` deben aparecer como `healthy` o
`running`. Si todavía están iniciando, esperar unos segundos y repetir.

### 4. Abrir el front

| Servicio | URL |
|---|---|
| Front | <http://localhost:8080> |
| API (directa) | <http://localhost:8000/salud> |
| Documentación interactiva de la API | <http://localhost:8000/docs> |
| Salud de la API a través del front | <http://localhost:8080/api/salud> |

El front es un panel de gestión sin login. Sus secciones son:

- **Inicio:** indicadores generales, ranking de vinos y estado de la API.
- **Vinos:** catálogo con filtros por nombre, tipo y añada; la ficha muestra
  bodega, cepas, maridajes y stock.
- **Clientes:** búsqueda y ficha de clientes.
- **Ventas:** registro de una venta con cliente, sala y renglones. Si el stock
  es insuficiente, la operación se rechaza y no se modifica el stock.
- **Stock:** consulta, ingreso y transferencia entre depósito y salas.
- **Reportes:** ranking de vinos, ventas por sala, alertas de stock y
  trazabilidad.

El indicador de estado del encabezado consulta `/salud`; si la API o la base no
responden, el panel lo muestra como fuera de línea.

### 5. Verificar que todo responde

**PowerShell:**

```powershell
Invoke-RestMethod http://localhost:8080/api/salud |
  ConvertTo-Json -Compress
```

**Bash / Git Bash / WSL:**

```bash
curl -fsS http://localhost:8080/api/salud
```

Resultado esperado:

```json
{"status":"ok","base_de_datos":"ok","current_user":"rol_api"}
```

También se puede comprobar el front:

```bash
curl -fsS http://localhost:8080/healthz
```

Debe responder `ok`.

### 6. Cargar los datos completos

El volumen nuevo arranca con un catálogo mínimo. Para cargar el volumen completo
de la Etapa 3 (30 tablas y aproximadamente 796.000 filas), primero crear el
entorno de Python e instalar las dependencias de carga:

**PowerShell:**

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r db\seed\requirements.txt
```

**Bash / Git Bash / WSL:**

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r db/seed/requirements.txt
```

Después ejecutar la carga completa:

**PowerShell:**

```powershell
$env:ENV_FILE = ".env"
.\scripts\cargar_datos.ps1 -Modo full
```

**Bash / Git Bash / WSL:**

```bash
ENV_FILE=.env bash scripts/cargar_datos.sh --modo full
```

Para una prueba rápida se puede usar una carga reducida:

```powershell
$env:ENV_FILE = ".env"
.\scripts\cargar_datos.ps1 -Modo reducida -Escala 0.05
```

> La carga trunca y vuelve a cargar las tablas. No ejecutarla sobre una base con
> datos que se quieran conservar sin hacer un backup antes.

Ejecutar las consultas de control:

**PowerShell:**

```powershell
$env:ENV_FILE = ".env"
.\scripts\consultas_control.ps1
```

**Bash / Git Bash / WSL:**

```bash
ENV_FILE=.env bash scripts/consultas_control.sh
```

### 7. Probar backup y restauración

Generar un backup en formato custom y en SQL comprimido:

**PowerShell:**

```powershell
$env:ENV_FILE = ".env"
.\scripts\backup.ps1
```

**Bash / Git Bash / WSL:**

```bash
ENV_FILE=.env bash scripts/backup.sh --formato ambos
```

El resultado queda en `backups/`. Restaurar el backup en una base temporal y
comparar conteos:

**PowerShell:**

```powershell
$env:ENV_FILE = ".env"
.\scripts\restaurar_y_verificar.ps1 `
  -BackupFile "backups\<archivo>.dump" `
  -EliminarRestaurada
```

**Bash / Git Bash / WSL:**

```bash
ENV_FILE=.env bash scripts/restaurar_y_verificar.sh \
  --backup backups/<archivo>.dump \
  --eliminar
```

La restauración no toca la base original: crea una base
`bodegas_del_atuel_restore_*`, compara las 30 tablas y la elimina al finalizar.

### 8. Probar la regla de negocio y el acceso a la base

Probar que una venta sin stock suficiente sea rechazada:

**PowerShell:**

```powershell
$env:ENV_FILE = ".env"
$env:API_PUBLIC_URL = "http://localhost:8080/api"
.\scripts\probar_regla_en_nube.ps1
```

**Bash / Git Bash / WSL:**

```bash
ENV_FILE=.env API_PUBLIC_URL="http://localhost:8080/api" \
  bash scripts/probar_regla_en_nube.sh
```

Resultado esperado: **HTTP 409**, stock antes y después igual, sin comprobante
nuevo.

Probar el acceso a PostgreSQL:

**PowerShell:**

```powershell
$env:ENV_FILE = ".env"
.\scripts\probar_acceso_no_autorizado.ps1
```

**Bash / Git Bash / WSL:**

```bash
ENV_FILE=.env bash scripts/probar_acceso_no_autorizado.sh
```

En local, PostgreSQL no publica TLS: `require` será rechazado y `disable` será
aceptado; eso es esperado en desarrollo. En un despliegue con TLS, ambos deben
ser rechazados o quedar restringidos por la allowlist/red privada del proveedor.

### 9. Ejecutar los tests de la base y de la API (opcional)

Los tests SQL insertan datos fijos (por ejemplo, la localidad `5500`), por lo que
deben ejecutarse sobre una base **vacía creada solo con las migraciones**, no
sobre `bodegas_del_atuel` con datos cargados. Crear una base temporal, aplicar
las migraciones y ejecutar los tests:

```bash
docker compose exec -T postgres dropdb -U postgres --if-exists bodegas_del_atuel_tests
docker compose exec -T postgres createdb -U postgres bodegas_del_atuel_tests
docker compose exec -T postgres psql -U postgres -d bodegas_del_atuel_tests -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/01_migraciones.sql
docker compose cp tests/db_tests.sql postgres:/tmp/db_tests.sql
docker compose exec -T postgres psql -U postgres -d bodegas_del_atuel_tests -v ON_ERROR_STOP=1 -f /tmp/db_tests.sql
docker compose exec -T postgres dropdb -U postgres bodegas_del_atuel_tests
```

Estos comandos funcionan igual en Bash, Git Bash, WSL y PowerShell. El último
elimina la base temporal; si algún test falla, ejecutar igualmente el `dropdb`
para limpiar. Resultado esperado: `Todos los tests pasaron. Se ejecuta ROLLBACK`.

Tests de integración de la API desde la máquina: usar la base principal ya
levantada y cargada, instalar las dependencias de desarrollo y definir las
variables de conexión locales (usar la clave real de `APP_DB_PASSWORD`, sin
imprimirla):

```powershell
.\.venv\Scripts\python.exe -m pip install -r api\requirements-dev.txt
$env:DB_HOST = "localhost"
$env:DB_PORT = "5433"
$env:DB_PASSWORD = "<APP_DB_PASSWORD>"
$env:DB_SSLMODE = "disable"
.\.venv\Scripts\python.exe -m pytest -q api\tests
```

```bash
.venv/bin/python -m pip install -r api/requirements-dev.txt
DB_HOST=localhost DB_PORT=5433 DB_PASSWORD='<APP_DB_PASSWORD>' \
  DB_SSLMODE=disable .venv/bin/python -m pytest -q api/tests
```

Resultado esperado: `13 passed`.

### 10. Detener, reiniciar y resetear

```bash
docker compose stop          # detener sin borrar datos
docker compose up -d         # volver a levantar
docker compose logs -f api   # ver logs de la API
docker compose down          # detener y eliminar contenedores, conservar datos
docker compose down -v       # borrar también el volumen de PostgreSQL
```

> `docker compose down -v` elimina todos los datos. Usarlo solo para volver a
> probar desde cero. Después de `down -v`, la siguiente ejecución de
> `docker compose up -d --build` vuelve a aplicar las migraciones y el seed
> mínimo.

### 11. Problemas comunes

| Problema | Qué revisar |
|---|---|
| El front muestra `502` o “API no disponible” | `docker compose ps`; esperar el healthcheck y revisar `docker compose logs --tail=100 api`. |
| “Port is already allocated” | Cambiar en `.env` `FRONT_PORT`, `API_PORT` o `POSTGRES_PORT` y volver a levantar. Si cambia `POSTGRES_PORT`, actualizar también `DB_PORT`. |
| La app abre pero no hay vinos | La base tiene solo el seed mínimo; ejecutar la carga completa del paso 6. |
| No se aplican las migraciones | `db/initdb` solo corre en un volumen vacío. Hacer backup y usar `docker compose down -v` para reiniciar desde cero. |
| La API o el front reinician con `exec ... no such file or directory` | Los `.sh` quedaron con fin de línea CRLF. El repo incluye `.gitattributes` (`*.sh text eol=lf`); renormalizar con `git add --renormalize .` y reconstruir con `docker compose up -d --build`. |
| `psql` no está instalado | Los scripts usan `docker run postgres:18` por defecto; dejar `PSQL_MODE=auto` o usar `PSQL_MODE=docker`. |
| Error de comillas o rutas en Git Bash | Ejecutar desde la raíz del repositorio y usar `ENV_FILE=.env bash scripts/...`. |
| La API responde pero el front no | Verificar `API_BASE_URL=/api` y que `http://localhost:8080/api/salud` responda. |

### 12. Despliegue en la nube

Para publicar la app se usa `docker-compose.production.yml`, que agrega Caddy
como proxy HTTPS, ejecuta PostgreSQL con TLS y no publica los puertos de la base
ni de la API. La guía paso a paso, la comparación de proveedores y el checklist
manual están en:

- [`docs/despliegue/CHECKLIST_MANUAL.md`](docs/despliegue/CHECKLIST_MANUAL.md)
- [`docs/despliegue/NOTAS_AUDITORIA.md`](docs/despliegue/NOTAS_AUDITORIA.md)
- [`docs/informe/08_despliegue.md`](docs/informe/08_despliegue.md)

---

## Alternativa: base de datos local sin Docker

Si preferís usar una instalación local de PostgreSQL en lugar de Docker, seguí
estos pasos. Si ya levantaste la app con Docker, esta sección no es necesaria.

Ejecutar desde la raíz del repositorio.

### 1. Crear la base

```bash
dropdb -U postgres --if-exists bodegas_del_atuel
createdb -U postgres -E UTF8 -T template0 bodegas_del_atuel
```

> **Atención:** `dropdb` elimina todos los datos de la base. Usarlo solo en desarrollo o hacer un backup antes.

### 2. Aplicar todas las migraciones

Las migraciones deben ejecutarse en orden, desde `001` hasta `008`. No alcanza con ejecutar solo `001_esquema.sql`.

**Bash / Git Bash / WSL:**

```bash
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/001_esquema.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/002_constraints.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/003_funciones.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/004_procedimientos.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/005_triggers.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/006_vistas.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/007_roles.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/008_indices.sql"
```

### 3. Ejecutar los tests

El archivo `tests/db_tests.sql` verifica las reglas de negocio RN-01 a RN-15 y los mecanismos de integridad de las migraciones.

```bash
psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f tests/db_tests.sql
```

El script:

- Corre dentro de una transacción y termina con `ROLLBACK`, por lo que no deja datos de prueba.
- Muestra un `NOTICE: OK ...` por cada caso que pasa.
- Se detiene con un error si algún caso negativo no falla como se espera.
- Solo es válido sobre una base **vacía creada únicamente con las migraciones**. Si ya se cargaron el seed mínimo o los datos completos, usar una base temporal como se explica en el paso 9 de la guía principal; los datos fijos de los tests chocan con una base cargada.
- Sobre una base vacía puede volver a ejecutarse, porque termina con `ROLLBACK`.

Al finalizar correctamente debe mostrarse:

```text
Todos los tests pasaron. Se ejecuta ROLLBACK para no dejar datos.
ROLLBACK
```

> **Importante:** el archivo usa metacomandos de `psql` (`\set` y `\echo`). Ejecutarlo con `psql`, no desde el editor de consultas de DBeaver o pgAdmin.

### Cómo saber que la base quedó bien

Las migraciones corren con `ON_ERROR_STOP=1`: si aparece un `ERROR`, la ejecución se detiene y no se aplica la migración incompleta.

Conectarse a la base:

```bash
psql -U postgres -d bodegas_del_atuel
```

y verificar:

| Comando | Qué debe mostrar |
|---|---|
| `\dt` | Las 30 tablas del esquema |
| `\d bodega` | Columnas, tipos y constraints de la tabla (se puede repetir con cualquier otra, por ejemplo `\d finca`) |
| `\dD` | Los dominios: `cuit_dominio` y `cp_dominio` |
| `\dT` | Los tipos: `tipo_vino`, `tipo_cliente`, `tipo_cepa`, `tipo_empleado`, `tipo_estado` y `dia_semana` (también aparecen los dominios) |

Salir de `psql` con `\q`.

---

## Nota académica

Proyecto desarrollado para la cátedra **Bases de Datos** de la carrera
**Ingeniería en Sistemas de Información** de la **UTN Facultad Regional San Rafael**,
ciclo lectivo 2026.

«Bodegas del Atuel» es una empresa ficticia. Los datos utilizados son generados
con fines exclusivamente académicos.

---

## Producción

El archivo `docker-compose.production.yml` es la configuración de referencia
para publicar la app en un servidor o proveedor con Docker:

- Caddy publica únicamente `80` y `443` y obtiene HTTPS para el dominio.
- PostgreSQL y la API quedan en una red interna, sin puertos publicados.
- PostgreSQL usa TLS y un `pg_hba.conf` que rechaza conexiones TCP sin cifrado.
- La API se conecta con `rol_api`; las migraciones se ejecutan con el rol
  propietario.

Pasos resumidos:

```bash
cp .env.production.example .env.production
# completar todos los placeholders en .env.production; no commitearlo
docker compose --env-file .env.production \
  -f docker-compose.production.yml up -d --build
```

Antes de publicar:

- elegir un proveedor y una región;
- restringir PostgreSQL por red privada, allowlist o deshabilitando el acceso
  externo;
- usar `DB_SSLMODE=require` como mínimo, o `verify-full` con la CA del
  proveedor;
- configurar `CORS_ORIGINS` con el origen HTTPS real del front;
- rotar las credenciales que hayan estado expuestas y verificar que las
  anteriores ya no funcionen;
- ejecutar las pruebas de aceptación del checklist.

Documentación detallada:

- [`docs/despliegue/CHECKLIST_MANUAL.md`](docs/despliegue/CHECKLIST_MANUAL.md)
- [`docs/despliegue/NOTAS_AUDITORIA.md`](docs/despliegue/NOTAS_AUDITORIA.md)
- [`docs/informe/08_despliegue.md`](docs/informe/08_despliegue.md)

> **Importante:** el repositorio no incluye credenciales reales. `.env`,
> `.env.production`, `backups/` y los dumps están ignorados por Git. Si se
> reutiliza una credencial que estuvo en el historial, debe rotarse.
