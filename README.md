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

Las migraciones deben ejecutarse en orden, desde `001` hasta `007`. No alcanza con ejecutar solo `001_esquema.sql`.

**Bash / Git Bash / WSL:**

```bash
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/001_esquema.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/002_constraints.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/003_funciones.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/004_procedimientos.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/005_triggers.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/006_vistas.sql"
    psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f "db/migrations/007_roles.sql"
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