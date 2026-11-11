# Pruebas de la base de datos

`tests/db_tests.sql` verifica las reglas de negocio **RN-01 a RN-15** y las
decisiones de diseño de la base de las etapas 2 a 4. Es la suite que respalda
que las restricciones, funciones, procedimientos, triggers y permisos hacen lo
que dicen los informes.

---

## 1. Qué prueba

| Bloque | Regla |
| --- | --- |
| RN-01 | Precio de vino único para toda la red y mayor que cero. |
| RN-02 | Una sala pertenece a una localidad y cada localidad tiene un encargado regional. |
| RN-03 | Cada empleado trabaja en una sola sala. |
| RN-04 | Una parcela tiene una sola cepa y se cosecha una vez por campaña. |
| RN-05 | Los porcentajes de composición suman exactamente 100. |
| RN-06 | Descuento según tipo de cliente; rango válido del exportador. |
| RN-07 | Permisos múltiples por exportador y vencimiento posterior. |
| RN-08 | El total del comprobante se calcula, no se carga a mano. |
| RN-09 | No se vende más que el stock de la sala y el stock no es negativo. |
| RN-10 | Solo un ingreso terminado impacta el depósito y pasa a procesado. |
| RN-11 | Transferencias, fecha de confección y stock. |
| RN-12 | Los documentos fuera de `en_confeccion` no admiten cambios de renglones. |
| RN-13 | Todo cambio de precio queda auditado. |
| RN-14 | No se borran transportistas, bodegas ni vinos con movimientos. |
| RN-15 | Cantidades, superficies, kilos, precios y graduación dentro de rango. |

También cubre decisiones de diseño: alta y cambio de tipo de cliente con
versionado, permisos de los roles, funciones de stock y validaciones de los
procedimientos.

---

## 2. Requisitos

- PostgreSQL 18.
- Una base **vacía creada solo con las migraciones** `001` a `008`.
- `psql` con `ON_ERROR_STOP` (el propio archivo lo activa).

No ejecutar la suite sobre `bodegas_del_atuel` con la carga completa: los tests
insertan datos fijos (por ejemplo, la localidad `5500`) y esperan una base sin
esos registros. La suite corre dentro de una transacción y termina con
`ROLLBACK`, así que tampoco deja datos de prueba.

---

## 3. Cómo ejecutarla con Docker Compose

Desde la raíz del repositorio y con el servicio `postgres` levantado:

```bash
docker compose exec -T postgres dropdb -U postgres --if-exists bodegas_del_atuel_tests
docker compose exec -T postgres createdb -U postgres bodegas_del_atuel_tests
docker compose exec -T postgres psql -U postgres -d bodegas_del_atuel_tests -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/01_migraciones.sql
docker compose cp tests/db_tests.sql postgres:/tmp/db_tests.sql
docker compose exec -T postgres psql -U postgres -d bodegas_del_atuel_tests -v ON_ERROR_STOP=1 -f /tmp/db_tests.sql
docker compose exec -T postgres dropdb -U postgres bodegas_del_atuel_tests
```

Funciona igual en Bash, Git Bash, WSL y PowerShell. El último comando elimina la
base temporal; si algún test falla, ejecutarlo igualmente para limpiar.

Resultado esperado en la última línea:

```text
Todos los tests pasaron. Se ejecuta ROLLBACK para no dejar datos.
```

En la corrida de referencia se imprimieron **133 verificaciones `OK`** y ningún
`FALLO`.

---

## 4. Cómo ejecutarla sin Docker

Con una base temporal ya creada y las migraciones aplicadas:

```bash
psql -h localhost -p 5433 -U postgres -d bodegas_del_atuel_tests \
  -v ON_ERROR_STOP=1 -f tests/db_tests.sql
```

El archivo usa `\set ON_ERROR_STOP on`, `BEGIN` y `ROLLBACK`; no hace falta
envolverlo en otra transacción.

---

## 5. Convenciones del archivo

- `tests.ok(descripcion, sql)`: la sentencia debe ejecutarse sin error.
- `tests.fail(descripcion, sql, sqlstate)`: la sentencia debe fallar con ese
  SQLSTATE (se acepta una lista separada por comas para variantes entre
  versiones de PostgreSQL).
- Cada prueba imprime `NOTICE: OK ...` con la regla y el SQLSTATE obtenido.
- `SET CONSTRAINTS ALL DEFERRED` permite probar los constraint triggers de
  composición y de localidad/encargado al final de la transacción.

SQLSTATE esperados: `23001`, `23502`, `23503`, `23505`, `23514` y `P0001`.

---

## 6. Tests de la API

La suite de la API es independiente y está documentada en
[`api/README.md`](../api/README.md). Usa una base **levantada y cargada** y
verifica la integración HTTP contra PostgreSQL real:

```powershell
.\.venv\Scripts\python.exe -m pip install -r api\requirements-dev.txt
$env:DB_HOST = "localhost"
$env:DB_PORT = "5433"
$env:DB_PASSWORD = "<APP_DB_PASSWORD>"
$env:DB_SSLMODE = "disable"
.\.venv\Scripts\python.exe -m pytest -q api\tests
```

Resultado esperado: `13 passed`.
