# Notas de auditoría de la Etapa 6

## Alcance revisado

Antes de implementar la API se revisaron:

- `db/migrations/001_esquema.sql` a `008_indices.sql`;
- `db/migrations/003_funciones.sql`;
- `db/migrations/004_procedimientos.sql`;
- `db/migrations/005_triggers.sql`;
- `db/migrations/006_vistas.sql`;
- `db/migrations/007_roles.sql`;
- `db/seed/` y el `docker-compose.yml` existente.

## Elementos obligatorios

No se detectaron elementos obligatorios faltantes en la base. No fue necesario
detener la implementación para pedir correcciones de esquema.

| Elemento | Estado | Evidencia |
| --- | --- | --- |
| Tablas operativas | Presentes | `001_esquema.sql` |
| Restricciones, CHECK y FKs | Presentes | `002_constraints.sql` |
| Funciones de negocio | Presentes | `003_funciones.sql` |
| Procedimientos de ingreso, transferencia y clientes | Presentes | `004_procedimientos.sql` |
| Triggers de stock, totales, estados, composición y auditoría | Presentes | `005_triggers.sql` |
| Vistas | Presentes | `006_vistas.sql` |
| Rol `rol_api` con permisos de lectura/escritura | Presente | `007_roles.sql` |
| Índices de la Etapa 4 | Presentes | `008_indices.sql` |
| PostgreSQL y volumen en Compose | Presentes | `docker-compose.yml` |

## Firmas verificadas

La API usa las firmas reales de los procedimientos:

- `p_procesar_ingreso(p_codigo INT)`.
- `p_procesar_transferencia(p_numero INT)`.
- `p_crear_cliente(...)` con 13 parámetros: tipo, calle, número, código postal,
  tipo y número de documento, nombre, apellido, razón social, zona de cobertura,
  número de habilitación, país destino y descuento especial.
- `p_cambiar_tipo_cliente(...)` con 9 parámetros: id del cliente, nuevo tipo y
  los datos propios del subtipo.

No se usan nombres inventados como `sp_*`. Los procedimientos se invocan con
`CALL` mediante psycopg.

## Decisiones tomadas a partir del esquema real

1. **Clientes:** el alta se hace con `p_crear_cliente`; el cambio de tipo con
   `p_cambiar_tipo_cliente`. El procedimiento de cambio desactiva la versión
   anterior y crea una nueva fila activa con otro `id`; la API devuelve el
   cliente nuevo y conserva el historial en la base.
2. **Ventas:** la API inserta cabecera y renglones. No calcula subtotales,
   descuentos ni totales. Los triggers completan el precio de lista, el
   descuento del cliente, el subtotal, el total y el stock de la sala.
3. **Stock:** los ingresos y transferencias se procesan exclusivamente con
   `p_procesar_ingreso` y `p_procesar_transferencia`; la API no suma ni resta
   cantidades. `terminar` solo cambia el estado y deja que el trigger de
   transición acepte o rechace el cambio.
4. **Precios:** la actualización de `vino.precio` dispara
   `trg_vino_audita_precio`; la API no escribe la auditoría.
5. **Composición:** la suma de porcentajes se valida con un constraint trigger
   diferido. La API debe hacer `COMMIT` dentro de la transacción para que el
   error aparezca y se revierta todo; `db.transaction()` lo contempla.
6. **Trazabilidad S9:** la consulta de la Etapa 5 se expone como ficha del vino
   con cepas, bodega, maridajes y stock. No se crearon tablas de lote adicionales
   porque el esquema disponible no modela esa trazabilidad y no se debía alterar
   la base desde la API.
7. **Exportadores:** el descuento especial válido está entre `0.30` y `0.35`
   según el procedimiento. Las pruebas usan `0.35`; no es un bug de la base.

## Observaciones de seguridad y operación

- `007_roles.sql` crea `rol_api` y `rol_reporte` **sin clave**. Las claves se
  fijan por entorno con `db/initdb/99_password_api.sql` a partir de
  `APP_DB_PASSWORD` y `APP_REPORT_PASSWORD`; no hay credenciales literales en el
  repositorio y el `.env` no se versiona.
- La API rechaza cualquier `DB_USER` distinto de `rol_api`. No se conecta con
  `postgres` ni con el propietario de la base.
- Los scripts de `/docker-entrypoint-initdb.d` solo corren con un volumen vacío.
  Si se reutiliza un volumen anterior a esta etapa, hay que actualizar la clave
  de `rol_api` o recrear el volumen con `docker compose down -v`.
- El compose existente usaba el servicio `postgres`; se mantuvo ese nombre y se
  agregó el alias de red `db` para que la API pueda usar `DB_HOST=db` sin romper
  configuraciones anteriores.

## Cambios locales no incluidos

El archivo `db/migrations/005_triggers.sql` ya tenía una modificación local
antes de comenzar la Etapa 6. No se incluyó en los commits de esta etapa ni se
modificó desde la API. La API funciona con la versión de triggers presente en la
base y con la versión versionada en `origin/main`.

## Conclusión

La base contiene los elementos necesarios para implementar la API sin
compensaciones en la capa HTTP. No se reportaron bugs de esquema ni se modificó
`db/migrations/` ni `db/seed/`; los únicos archivos nuevos de inicialización
están en `db/initdb/`.
