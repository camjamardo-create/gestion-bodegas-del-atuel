# Informe de la Etapa 5 — Consultas SQL

**TPI Base de Datos · Bodegas del Atuel**
Consignas 8.1 a 8.5 (U1–U6, I1–I6, D1–D6, S1–S12).

---

## 1. Alcance y archivos

La Etapa 5 resuelve las 30 consignas de la sección 8 del enunciado en SQL de
PostgreSQL, con los valores concretos tomados del dataset de la Etapa 3
(150.000 comprobantes, 564.328 renglones, 500 vinos, 24 salas, 20.000
clientes, 1.200 ingresos).

| Archivo | Contenido | Bloques |
|---|---|---|
| `consultas/update.sql` | U1 a U6 | 6 |
| `consultas/insert.sql` | I1 a I6 | 6 |
| `consultas/delete.sql` | D1 a D6 | 6 |
| `consultas/select.sql` | S1 a S12 (S11 y S12 en dos partes) | 14 |

Cada consigna tiene:

1. el código y el enunciado;
2. el SQL comentado;
3. la estrategia de resolución (joins, CTE, subconsultas, funciones de
   ventana, `NOT EXISTS`, división relacional);
4. los parámetros usados y dónde cambiarlos;
5. el resultado obtenido en la corrida de prueba.

Las sentencias que modifican datos se ejecutan entre `BEGIN;` y `ROLLBACK;`,
con un control previo y otro posterior. El `ROLLBACK` deja la base en el
estado de la Etapa 3; para aplicar un cambio de forma definitiva se reemplaza
por `COMMIT;`.

## 2. Cómo ejecutar

Con la base de la Etapa 3 levantada:

```bash
psql -h localhost -p 5433 -U postgres -d bodegas_del_atuel \
     -v ON_ERROR_STOP=1 -f consultas/update.sql
psql -h localhost -p 5433 -U postgres -d bodegas_del_atuel \
     -v ON_ERROR_STOP=1 -f consultas/insert.sql
psql -h localhost -p 5433 -U postgres -d bodegas_del_atuel \
     -v ON_ERROR_STOP=1 -f consultas/delete.sql
psql -h localhost -p 5433 -U postgres -d bodegas_del_atuel \
     -v ON_ERROR_STOP=1 -f consultas/select.sql
```

Los archivos son SQL portable: no usan meta-comandos de `psql` (como
`\gset`) ni variables de sesión. Para encadenar un `INSERT` con su detalle se
usa `currval(pg_get_serial_sequence(...))`, que recupera el id identity
recién generado dentro de la misma transacción.

Tiempos de corrida medidos (con la base cargada):

| Archivo | Tiempo | Errores |
|---|---:|---|
| `update.sql` | 4,3 s | 0 |
| `insert.sql` | 2,4 s | 0 |
| `delete.sql` | 1,1 s | 0 |
| `select.sql` | 0,9 s | 0 |

## 3. Resumen de filas afectadas

### 3.1 UPDATE

| Código | Consigna | Filas | Observación |
|---|---|---:|---|
| U1 | Recalcular totales con el descuento del cliente | 150.000 | Idempotente: 0 inconsistencias antes y después |
| U2 | +20 % salario a empleados con más de 5 años | 44 | De 80 empleados |
| U3 | +13 % precio de los vinos de una bodega | 36 | Genera 36 filas en `auditoria_precio` |
| U4 | Intercambiar cierre lunes ↔ miércoles | 8 | 4 salas de cada día, en una sola sentencia |
| U5 | −15 % a los 10 vinos menos vendidos | 10 | Genera 10 filas en `auditoria_precio` |
| U6 | Descuento 35 % a exportadores con >3 permisos | 304 | Respeta el CHECK 0,30–0,35 |

### 3.2 INSERT

| Código | Consigna | Filas | Observación |
|---|---|---:|---|
| I1 | Cobertura General Alvear ↔ transportista con menos envíos | 1 | Transportista 12 (0 envíos en el trimestre); `ON CONFLICT DO NOTHING` |
| I2 | Maridaje “cordero al disco” para tintos ≥14° | 1 + 122 | 1 maridaje y 122 asociaciones |
| I3 | Comprobante con 3 renglones, cliente 15234, sala 1 | 1 + 3 | Total 154.166,00 calculado por triggers y `fn_total_comprobante()` |
| I4 | Nueva bodega | 1 | CUIT `30999999991`; la tabla pasa de 20 a 21 |
| I5 | Nueva sala de venta | 1 | Id 25, localidad Mendoza (`5500`) |
| I6 | Ingreso en confección de 120 botellas | 1 + 1 | Vino 1 (Malbec Reserva 750 ml), bodega `34100000158`, transportista 1 |

### 3.3 DELETE

| Código | Consigna | Filas | Cascada / observación |
|---|---|---:|---|
| D1 | Comprobantes >5 años de socios | 7.450 | 27.862 renglones en cascada (564.328 → 536.466) |
| D2 | Cepas sin composición ni parcela | 1 | Cepa 12 “Semillón”; las FK RESTRICT no se violan |
| D3 | Empleados con <2 años de la sala de Junín | 2 | El encargado regional (6 años) no se borra |
| D4 | Socios sin compras con alta >5 años | 102 | 102 filas de `socio_club` en cascada |
| D5 | Ingresos procesados de hace >365 días | 657 | 1.378 renglones en cascada (3.767 → 2.389) |
| D6 | Socios sin compras de San Rafael | 16 | Sin filtro de antigüedad (13 se solapan con D4) |

### 3.4 SELECT

| Código | Consulta | Filas |
|---|---|---:|
| S1 | Top 10 vinos por botellas vendidas | 10 |
| S2 | Vinos vendidos en todas las salas (división) | 499 |
| S3 | Clientes por tipo en la sala 4, última semana | 4 |
| S4 | Top 5 salas por transferencias del vino 395, 15 días | 1 |
| S5 | Salas con menos transferencias pendientes | 24 |
| S6 | Vinos sin stock en sala 1 pero con stock en depósito | 1 |
| S7 | Transportista con mayor actividad del último mes | 1 |
| S8 | Ventas por sala del último trimestre | 24 |
| S9 | Ficha del vino 1 (cepas, bodega, maridajes, stock) | 1 |
| S10 | Parcelas con rendimiento bajo el promedio de su finca | 624 |
| S11.a | Ranking de vinos dentro de cada sala | 11.999 |
| S11.b | Ventas acumuladas mensuales por sala | 1.704 |
| S12.a | Clientes que compraron todos los vinos de una bodega | 0 |
| S12.b | Clientes que nunca compraron un tinto | 232 |

## 4. Estrategias por consigna

### 4.1 UPDATE

- **U1** — CTE `calculo` que suma `subtotal_renglon` por comprobante y llama a
  `fn_descuento_cliente(id_cliente)`; el `UPDATE ... FROM` escribe subtotal,
  descuento aplicado, descuento total y total en una sola pasada. Se recalcula
  el subtotal desde los renglones para no confiar en el valor almacenado.
  Como la carga de la Etapa 3 ya usó la misma función, los importes no
  cambian: la sentencia verifica el invariante
  `total = subtotal − descuento_total` sobre las 150.000 filas.
- **U2** — `UPDATE` con `fn_antiguedad_anios(fecha_ingreso) > 5`; el salario se
  multiplica por 1,20 y se redondea a 2 decimales.
- **U3** — `UPDATE` filtrando por `cuit_bodega = '34100000158'`; el trigger
  `trg_vino_audita_precio` registra precio anterior y nuevo.
- **U4** — Un único `UPDATE` con `CASE` que intercambia los dos valores del
  enum `dia_semana`; el `WHERE` limita a las filas de lunes y miércoles.
- **U5** — CTE `ventas` con `LEFT JOIN` (un vino sin ventas cuenta 0) y CTE
  `menos_vendidos` con `ORDER BY botellas, codigo LIMIT 10`; el `UPDATE` aplica
  el 85 % del precio.
- **U6** — Subconsulta escalar correlacionada que cuenta los permisos de cada
  exportador; el `UPDATE` fija `descuento_especial = 0.35`.

### 4.2 INSERT

- **I1** — `LEFT JOIN` transportista–ingreso restringido al último trimestre,
  ordenado por cantidad de envíos y desempatado por código; el
  `INSERT ... SELECT ... ON CONFLICT DO NOTHING` agrega la cobertura de
  General Alvear (`5620`).
- **I2** — CTE que inserta el maridaje solo si no existe (`NOT EXISTS`) y
  devuelve su id con `RETURNING`; el `INSERT` final cruza ese id con los vinos
  `tipo = 'tinto' AND graduacion >= 14` y usa `ON CONFLICT DO NOTHING`.
- **I3** — Cabecera con `descuento_aplicado = fn_descuento_cliente(15234)` y
  tres renglones insertados con el número devuelto por la identity. Los
  triggers fijan el precio de lista, validan stock, descuentan stock y
  recalculan los totales con `fn_total_comprobante()`.
- **I4** — `INSERT` simple sobre `bodega`; el CUIT respeta el dominio de 11
  dígitos.
- **I5** — `INSERT` simple sobre `sala_venta` con una localidad existente
  (`5500`, Mendoza).
- **I6** — Cabecera de ingreso en `en_confeccion` y renglón con 120 botellas
  del vino 1. La fecha la fuerza `trg_fijar_fecha_documento` a `CURRENT_DATE`;
  el ingreso queda listo para `p_procesar_ingreso()`.

### 4.3 DELETE

- **D1** — `DELETE` por rango de fecha y `IN (SELECT id_cliente FROM
  socio_club)`; los renglones caen por `ON DELETE CASCADE`.
- **D2** — `DELETE` con dos `NOT EXISTS` correlacionados (composición y
  parcela).
- **D3** — `DELETE ... USING sala_venta` filtrando por código postal de Junín
  (`5573`) y `fn_antiguedad_anios(fecha_ingreso) < 2`.
- **D4** — `DELETE` de socios con `fecha_alta` vieja y `NOT EXISTS` sobre
  comprobante.
- **D5** — `DELETE` de ingresos `procesado` con fecha anterior a
  `CURRENT_DATE - 365`; los renglones caen en cascada.
- **D6** — Igual que D4 pero sin filtro de antigüedad y con
  `codigo_postal = '5600'` (San Rafael).

### 4.4 SELECT

- **S1** — `SUM(cantidad)` agrupado por vino, join por PK con `vino`,
  `ORDER BY ... DESC LIMIT 10`.
- **S2** — División relacional por agregación: `COUNT(DISTINCT id_sala_venta)`
  igual a la cantidad total de salas. Se documenta la versión equivalente con
  doble `NOT EXISTS`.
- **S3** — Filtro por sala (4) y `fecha >= CURRENT_DATE - 7`, join con cliente
  y `COUNT(DISTINCT c.id)` por tipo. Usa `idx_comprobante_sala_fecha`.
- **S4** — Join transferencia → renglón → sala, filtro por vino 395 y
  `fecha_confeccion >= CURRENT_DATE - 15`, `SUM(cantidad)` por sala y
  `LIMIT 5`.
- **S5** — `LEFT JOIN` sala–transferencia con la condición
  `estado <> 'procesado'` en el `ON` para no perder salas sin pendientes;
  orden ascendente. Coincide con el índice parcial
  `idx_transferencia_pendientes`.
- **S6** — `LEFT JOIN` de `stock_deposito` con `stock_sala` restringido a la
  sala; se conservan las filas sin registro o con cantidad 0
  (`COALESCE(ss.cantidad, 0) = 0`).
- **S7** — Join ingreso–transportista, `LEFT JOIN` con renglones para sumar
  botellas, filtro del último mes, `COUNT(DISTINCT i.codigo)` para no
  multiplicar cabeceras y `LIMIT 1`.
- **S8** — `SUM(total)` por sala con `fecha >= CURRENT_DATE - INTERVAL '3
  months'`. Usa el índice de cobertura `idx_comprobante_fecha_sala_total`.
- **S9** — Subconsultas escalares correlacionadas con `STRING_AGG` para cepas
  y maridajes; el stock total suma depósito y salas.
- **S10** — CTE `rendimiento` (kg de cosecha / superficie por parcela y
  campaña) y subconsulta correlacionada que compara cada fila con el promedio
  de su finca.
- **S11.a** — `RANK() OVER (PARTITION BY sala ORDER BY SUM(cantidad) DESC)`.
- **S11.b** — `SUM(SUM(total)) OVER (PARTITION BY sala ORDER BY mes)` sobre
  la agregación mensual con `date_trunc`.
- **S12.a** — División relacional por agregación: clientes cuyo
  `COUNT(DISTINCT vino)` de la bodega elegida iguala el total de vinos de esa
  bodega.
- **S12.b** — Anti-join `NOT EXISTS` sobre comprobante → renglón → vino con
  `tipo = 'tinto'`.

## 5. Triggers y constraints involucrados

| Objeto | Consignas | Comportamiento observado |
|---|---|---|
| `trg_vino_audita_precio` | U3, U5 | Inserta una fila en `auditoria_precio` por cada `UPDATE` de precio. U3: 132 → 168 filas; U5: 10 filas más. |
| `trg_fijar_fecha_documento` | I6 | Fuerza `fecha = CURRENT_DATE` en ingresos (y `fecha_confeccion` en transferencias). |
| `trg_validar_estado_documento` | I6 | Exige que el ingreso nazca en `en_confeccion`. |
| `trg_bloquear_renglon_ingreso` | I6, D5 | Bloquea renglones si la cabecera no está `en_confeccion`; en `DELETE` por cascada permite el borrado cuando la cabecera ya no existe. |
| `trg_renglon_comprobante_precio_lista` | I3 | Fija `precio_unitario` desde `vino.precio` (los valores enviados en 0 se reemplazan por el precio de lista). |
| `trg_validar_stock_venta` | I3 | Valida que la sala tenga stock suficiente antes de vender. |
| `trg_actualizar_stock_y_totales_venta` | I3 | Descuenta stock y recalcula subtotal, descuento y total con `fn_total_comprobante()`. |
| `trg_cliente_subtipo_total` / `trg_socio_club_subtipo_total` (diferidos) | D4, D6 | Validan que cada cliente conserve exactamente una fila de subtipo; `fn_validar_subtipo_cliente()` retorna sin error si el cliente ya fue borrado. Se fuerza la validación con `SET CONSTRAINTS ALL IMMEDIATE`. |
| FK `ON DELETE CASCADE` de renglones | D1, D5 | Borra 27.862 y 1.378 renglones respectivamente. |
| FK `ON DELETE RESTRICT` de cepas | D2 | No se viola porque las cepas borradas no están referenciadas. |
| FK `localidad.cuit_encargado` | D3 | El encargado regional de Junín no cumple el filtro de antigüedad y no se borra. |
| `ck_exportador_descuento_rango` | U6 | El valor 0.35 está dentro del rango permitido (0,30–0,35). |
| `ck_comprobante_total_calculo` | U1, I3 | Se respeta porque los totales se recalculan de forma consistente. |
| `uk_cliente_tipo_num_doc_activo` | I4/I5 | No interviene; las claves nuevas no colisionan. |

## 6. Decisiones y observaciones

1. **Parámetros elegidos del dataset.** Todos los literales salen de una
   corrida de reconocimiento: sala 4 para S3, vino 395 para S4, sala 1 para
   S6, bodega `34100000158` para U3 e I6, bodega `30100000209` para S12.a,
   localidad `5573` (Junín) para D3 y `5600` (San Rafael) para D6.
2. **S12.a devuelve 0 filas.** Ningún cliente compró los 15 vinos de
   Cordoba-Lopez Bodega. Es un resultado válido del dataset, no un error de la
   consulta; la división relacional está escrita para cualquier bodega.
3. **S4 devuelve 1 fila.** En los últimos 15 días hay una sola transferencia
   (vino 395 a la sala 14, 95 botellas). La consulta mantiene `LIMIT 5` para
   cualquier otro período.
4. **S6 devuelve 1 fila.** La sala 1 es la única con un vino sin stock en la
   sala y con stock en depósito; otras salas no cumplen ambas condiciones.
5. **U1 no cambia importes.** La carga de la Etapa 3 ya aplicó
   `fn_descuento_cliente()`; la sentencia deja el invariante verificado sobre
   toda la tabla y es idempotente.
6. **Borrados y stock.** D1 y D5 eliminan ventas e ingresos históricos, pero no
   revierten stock: la base solo actualiza stock al vender (`trg_actualizar_stock_y_totales_venta`)
   y al procesar ingresos (`p_procesar_ingreso`). Se documenta como decisión de
   negocio: son datos históricos y el stock actual no se reconstruye hacia
   atrás.
7. **ROLLBACK por defecto.** Todos los bloques de modificación terminan en
   `ROLLBACK` para poder correr los archivos repetidamente sin alterar el
   dataset de la Etapa 3. La aplicación definitiva se hace cambiando
   `ROLLBACK` por `COMMIT`.
8. **Sin cambios en migraciones ni tests.** La Etapa 5 solo agrega la carpeta
   `consultas/` y este informe; no modifica `001`–`008` ni `tests/`.
9. **Fecha y zona horaria.** Los conteos de D1 y D5 dependen de `CURRENT_DATE`.
   La base del entorno de prueba usa `TimeZone = Etc/UTC`; para reproducir los
   valores de este informe (D1 = 7.450) hay que ejecutar con la zona local:

   ```bash
   PGTZ=America/Argentina/Mendoza psql ... -f consultas/delete.sql
   ```

   Ejecutado en UTC después de las 21:00 de Argentina, `CURRENT_DATE` ya es el
   día siguiente y D1 elimina 7.466 filas. La diferencia es de calendario, no
   de la consulta.
