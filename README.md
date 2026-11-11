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

## Base de datos local

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
- Puede volver a ejecutarse sobre la misma base sin limpiar datos.

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

## Despliegue local y en la nube (Etapas 7 y 8)

El repositorio incluye una API FastAPI, un front estático servido por Nginx y
una configuración de referencia para desplegar el conjunto sin publicar la base
de datos ni la API.

### Front y API en local

1. Copiar `.env.example` a `.env` y completar los valores locales.
2. Construir y levantar los servicios:

```bash
docker compose up -d --build
```

3. Abrir `http://localhost:8080`. El front usa `API_BASE_URL=/api` y Nginx
   proxya las llamadas a la API.
4. Verificar la salud de la API:

```bash
curl http://localhost:8080/api/salud
```

El resultado debe incluir `"current_user":"rol_api"` y `"base_de_datos":"ok"`.
En local PostgreSQL no publica TLS; por eso `.env` usa `DB_SSLMODE=disable`.
En la nube se debe usar `require` o `verify-full`.

### Scripts de operación

Los scripts están en `scripts/` y tienen equivalentes PowerShell y Bash:

```powershell
$env:ENV_FILE = ".env"
.\scripts\aplicar_migraciones.ps1
.\scripts\cargar_datos.ps1 -Modo full
.\scripts\consultas_control.ps1
.\scripts\backup.ps1
.\scripts\restaurar_y_verificar.ps1 -BackupFile "backups\<archivo>.dump" -EliminarRestaurada
.\scripts\probar_regla_en_nube.ps1
.\scripts\probar_acceso_no_autorizado.ps1
```

```bash
ENV_FILE=.env bash scripts/aplicar_migraciones.sh
ENV_FILE=.env bash scripts/cargar_datos.sh --modo full
ENV_FILE=.env bash scripts/consultas_control.sh
ENV_FILE=.env bash scripts/backup.sh --formato ambos
ENV_FILE=.env bash scripts/restaurar_y_verificar.sh --backup backups/<archivo>.dump --eliminar
ENV_FILE=.env bash scripts/probar_regla_en_nube.sh
ENV_FILE=.env bash scripts/probar_acceso_no_autorizado.sh
```

Las migraciones se aplican con el rol propietario. La API se conecta siempre
con `rol_api`. Las claves se pasan por entorno y no se imprimen.

### Despliegue de referencia con TLS

El archivo `docker-compose.production.yml` levanta Caddy, el front, la API y
PostgreSQL en una red interna. Solo Caddy publica `80` y `443`; la base y la
API no tienen puertos publicados.

```bash
cp .env.production.example .env.production
# completar los valores reales en .env.production, sin commitearlo
docker compose --env-file .env.production -f docker-compose.production.yml up -d --build
```

Antes de desplegar:

- elegir un proveedor y una región;
- restringir PostgreSQL por red privada, allowlist o deshabilitando el acceso
  externo;
- usar `DB_SSLMODE=require` como mínimo (o `verify-full` con la CA del
  proveedor);
- configurar `CORS_ORIGINS` con el origen HTTPS real;
- rotar las credenciales y verificar que las antiguas ya no funcionen.

La guía completa, la comparación de proveedores y el checklist manual están en:

- [`docs/despliegue/CHECKLIST_MANUAL.md`](docs/despliegue/CHECKLIST_MANUAL.md)
- [`docs/despliegue/NOTAS_AUDITORIA.md`](docs/despliegue/NOTAS_AUDITORIA.md)
- [`docs/informe/08_despliegue.md`](docs/informe/08_despliegue.md)

> **Importante:** el repositorio no incluye credenciales reales. `.env`,
> `.env.production`, `backups/` y los dumps están ignorados por Git. Si se
> reutiliza una credencial que estuvo en el historial, debe rotarse.
