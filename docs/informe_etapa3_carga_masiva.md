# Informe Etapa 3 — Carga masiva determinista

**Proyecto:** Bodegas del Atuel  
**Materia:** Base de Datos  
**Fecha de la corrida:** 2026-11-10  
**Semilla:** 42  
**Fecha de referencia:** 2026-11-10  
**Escala:** 1.0  
**Modo de carga:** `copy`

---

## 1. Resumen ejecutivo

Se implementó una carga masiva determinista para las 30 tablas del esquema,
usando Python 3.13, psycopg 3.3.8, Faker 40.53.0 y SQL escrito a mano. La
corrida real completa, incluyendo los 11 controles y el cálculo de hashes, tardó
**33,15 segundos** en la primera medición y **23,96 segundos** en una repetición
posterior con los mismos parámetros. La fase de carga sin controles (generación,
inserción, `ANALYZE`, `setval` y hash) tardó **26,21 segundos**. Se cargaron
**150.000 comprobantes** y **564.328 renglones de comprobante**, y las 30 tablas
quedaron con datos.

Los 10 controles que deben devolver cero problemas lo hicieron. Las cuatro
evidencias de reproducibilidad (tres cargas y una restauración del dump)
coincidieron en el mismo hash combinado:

```text
5865ce1cc63f998d109af49a3f9e44656ff8935f3a743459ccf1697cb1d01745
```

El dump plano comprimido pesó **6.266.618 bytes (6,0 MiB)** y se restauró en una
base vacía conservando los conteos, los controles y el hash.

---

## 2. Entorno de ejecución

| Componente | Versión / detalle |
|---|---|
| PostgreSQL | 18.6 (`server_version` 180006) |
| Contenedor | `bodegas_del_atuel_etapa3`, imagen `postgres:18` |
| Puerto local | 5433 |
| Base | `bodegas_del_atuel` |
| Sistema anfitrión | Windows |
| Python | 3.13.14 |
| psycopg | 3.3.8 |
| Faker | 40.53.0 (`es_AR`) |
| Migraciones aplicadas | `001` a `007` |

Esta etapa no requirió cambios de esquema ni nuevas migraciones. La conexión se
resuelve con `DATABASE_URL` o con las variables `PG*`; no hay credenciales en el
código.

---

## 3. Diseño de la solución

### 3.1. Determinismo

`random` y `Faker` se inicializan con la misma semilla (`42` por defecto). La
fecha de referencia es fija (`2026-11-10` por defecto) y se pasa a toda la
generación. La escala permite reducir volúmenes sin cambiar la lógica.

La generación se hizo en memoria y luego se cargó en una única transacción. Para
la misma semilla, fecha y escala, los datos son idénticos; las cuatro evidencias
lo confirman.

### 3.2. Catálogos reales

Los catálogos están en `db/seed/catalogos/`:

- 12 cepas reales; la cepa 12 (Semillón) queda sin uso a propósito.
- 8 maridajes; “Carnes rojas” y “Quesos duros” tienen ids 1 y 2.
- 18 localidades de Mendoza con código postal real, incluyendo General Alvear
  (`5620`) y San Rafael (`5600`).
- Tipos de vino (`tinto`, `blanco`, `rosado`, `espumante`) y presentaciones
  (187, 375, 750, 1500 y 3000 ml).

`cepa` y `maridaje` tienen identidad; se cargan con
`INSERT ... OVERRIDING SYSTEM VALUE` para respetar los IDs de los CSV.

### 3.3. Orden de carga

El orden respeta las dependencias del esquema. Las tablas con identidad se
cargan sin la columna identidad y al final se ajustan con `setval`. Las columnas
generadas (`lote.campaña` y `renglon_comprobante.subtotal_renglon`) no se
insertan.

### 3.4. Triggers y restricciones diferidas

Los triggers de usuario se deshabilitan solo dentro de la transacción de carga:

```sql
ALTER TABLE ... DISABLE TRIGGER USER;
```

No se usa `session_replication_role`. Antes de rehabilitar se ejecuta:

```sql
SET CONSTRAINTS ALL IMMEDIATE;
```

Esto es necesario porque la FK diferible `localidad → empleado` deja eventos de
trigger pendientes y PostgreSQL no permite `ALTER TABLE ... ENABLE TRIGGER USER`
mientras existan. Después se rehabilitan los triggers y se verifica
`pg_trigger.tgenabled = 'O'` para los 16 triggers de usuario. La habilitación
ocurre antes del `COMMIT`; además hay un `try/finally` de seguridad.

### 3.5. Stock, totales y precios históricos

Como los triggers de stock, totales, precios y fechas están deshabilitados, el
generador reproduce sus efectos en Python:

- `stock_deposito = Σ ingresos procesados − Σ transferencias procesadas`.
- `stock_sala = Σ transferencias procesadas − Σ ventas`.
- `subtotal = Σ(cantidad × precio_unitario)`.
- `total = round(subtotal × (1 − descuento_aplicado), 2)`.
- `descuento_total = subtotal − total`.
- El precio de cada renglón es el vigente a la fecha de la venta.
- Los cambios de precio se registran manualmente en `auditoria_precio`.

No se llaman los procedimientos de la API. Es una decisión deliberada para que
la carga sea autónoma; el riesgo se documenta en la sección 7.

### 3.6. Controles

`db/seed/consultas_control.sql` contiene 11 controles. El script los ejecuta
después de `ANALYZE` y `setval`, y falla si alguno de los controles de problema
devuelve filas. La variable de sesión `app.fecha_referencia` se setea con
`--fecha-ref`, de modo que los controles de ventanas de venta no dependen del
día en que se ejecute la validación.

---

## 4. Volúmenes reales

Corrida con `--seed 42 --fecha-ref 2026-11-10 --escala 1.0 --modo copy`:

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

Se cumplen los mínimos:

- Las 30 tablas tienen al menos 1 fila.
- **5 tablas** superan las 10.000 filas: `renglon_comprobante` (564.328),
  `comprobante` (150.000), `cliente` (20.000), `renglon_transferencia`
  (12.255) y `stock_sala` (12.000).
- **2 tablas** superan las 100.000 filas: `renglon_comprobante` y
  `comprobante`.

La carga reducida (`--escala 0.1`) generó 2.000 clientes, 15.000 comprobantes y
57.377 renglones; se usó solo para depurar el flujo, no para validar los mínimos.

---

## 5. Resultados de la corrida real

### 5.1. Tiempos

La generación en memoria, medida de forma aislada, tardó **12,71 s**. La corrida
de carga sin controles medida con `Stopwatch` tardó **26,21 s**, incluyendo
generación, conexión, carga, `ANALYZE`, `setval` y cálculo de hashes. La primera
corrida final con los 11 controles y el hash tardó **33,15 s**; una repetición
posterior con los mismos parámetros tardó **23,96 s**. La diferencia es esperable
por la caché del sistema y del contenedor.

Tiempos de inserción de las tablas principales en la corrida medida:

| Tabla | Filas | Tiempo |
|---|---:|---:|
| `cepa` | 12 | 0,04 s |
| `maridaje` | 8 | 0,05 s |
| `parcela` | 600 | 0,06 s |
| `lote` | 900 | 0,07 s |
| `analisis_calidad` | 3.180 | 0,03 s |
| `vino` | 500 | 0,05 s |
| `composicion` | 946 | 0,06 s |
| `cliente` | 20.000 | 0,23 s |
| `comprobante` | 150.000 | 2,23 s |
| `renglon_comprobante` | 564.328 | 7,00 s |
| `renglon_transferencia` | 12.255 | 0,18 s |
| `stock_sala` | 12.000 | 0,20 s |

La suma de los tiempos de inserción medidos por tabla es aproximadamente
**10,9 s**. La primera corrida en frío había tardado 4,88 s para `comprobante` y
21,24 s para `renglon_comprobante`; la diferencia muestra la influencia de la
caché y del estado del contenedor.

### 5.2. Controles

Resultado de la corrida real:

| Control | Resultado |
|---|---|
| `q01_volumenes_por_tabla` | 30 filas (informativo) |
| `q02_volumenes_minimos` | 0 problemas |
| `q03_stock_coherente` | 0 problemas |
| `q04_totales_comprobantes` | 0 problemas |
| `q05_composicion_vinos` | 0 problemas |
| `q06_fechas_logicas_y_ventanas` | 0 problemas |
| `q07_clientes_descuentos_y_permisos` | 0 problemas |
| `q08_cobertura_comercial` | 0 problemas |
| `q09_estados_de_documentos` | 0 problemas |
| `q10_precios_y_presentaciones` | 0 problemas |
| `q11_secuencias_identidad` | 0 problemas |

`q11` verificó las 14 secuencias identidad: `finca`, `cepa`, `maridaje`,
`transportista`, `sala_venta`, `ingreso`, `cliente`, `permiso`, `lote`,
`analisis_calidad`, `vino`, `auditoria_precio`, `comprobante` y
`transferencia`.

### 5.3. Reproducibilidad

Se conservaron como evidencia tres cargas completas y una restauración del dump.
Las cuatro evidencias tienen el mismo hash combinado:

| Evidencia | Meta | Hash combinado |
|---|---|---|
| `hashes_run1.json` | carga 1 | `5865ce1c...d01745` |
| `hashes_run2.json` | carga 2 | `5865ce1c...d01745` |
| `hashes_run3.json` | carga 3 (medida) | `5865ce1c...d01745` |
| `hashes_restore.json` | restauración | `5865ce1c...d01745` |

Hash completo:

```text
5865ce1cc63f998d109af49a3f9e44656ff8935f3a743459ccf1697cb1d01745
```

El hash se calcula con `COPY (SELECT * FROM tabla ORDER BY clave) TO STDOUT`, de
modo que incluye todas las columnas y no depende del orden físico de las filas.

### 5.4. Benchmark de `cliente`

Se cargaron 10.000 clientes con cuatro estrategias sobre una tabla temporal sin
log:

| Modo | Segundos | Filas/s | Respecto de COPY |
|---|---:|---:|---:|
| COPY | 0,072 | 138.017,5 | 1,00x |
| Lotes de 5.000 | 0,653 | 15.306,1 | 9,02x |
| Fila por fila, 1 transacción | 5,028 | 1.988,9 | 69,39x |
| Fila por fila, commit por fila | 5,140 | 1.945,5 | 70,94x |

COPY fue la opción más rápida. El commit por fila no fue mucho más lento que la
transacción única en este entorno local, pero en la primera corrida fue ~71
veces más lento que COPY. Los valores son relativos a esta máquina y a este
contenedor.

Una segunda corrida de 10.000 filas dio COPY 0,079 s, lotes 0,476 s, fila por
fila 4,319 s y commit por fila 4,569 s. La variación entre corridas es esperable
por la caché y la carga del contenedor; la conclusión cualitativa se mantiene:
COPY es el modo más rápido y el commit por fila el más costoso.

### 5.5. Dump y restauración

`db/seed/generar_dump.sh` generó:

```text
db/seed/dump_completo.sql.gz
6.266.618 bytes (6,0 MiB)
```

El dump es texto plano, sin dueño ni privilegios, comprimido con gzip. Se
restauró en `bodegas_del_atuel_restore` sin errores. La base restaurada:

- Pasó los 11 controles con 0 problemas.
- Conservó los 30 conteos de tabla.
- Dio el mismo hash combinado que la carga original.

El dump no incluye roles; si se necesitan, hay que ejecutar `007_roles.sql` o
crearlos aparte.

---

## 6. Verificación de casos obligatorios

### 6.1. Malbec Reserva obligatorio

El vino código 1 cumple exactamente lo pedido:

| Campo | Valor |
|---|---|
| Nombre | Malbec Reserva |
| Tipo | tinto |
| Añada | 2021 |
| Volumen | 750 ml |
| Graduación | 14,00° |
| Precio | $12.500,00 |
| Bodega | Soria LLC Bodega |

Composición: Malbec 85 % + Cabernet Sauvignon 15 %.  
Maridajes: “Carnes rojas” y “Quesos duros”.

### 6.2. General Alvear y San Rafael

| Localidad | Código postal | Salas | Comprobantes | Botellas vendidas |
|---|---:|---:|---:|---:|
| General Alvear | 5620 | 1 | 6.339 | 46.867 |
| San Rafael | 5600 | 2 | 12.407 | 92.091 |

### 6.3. Stock y cobertura

Flujos reales:

| Flujo | Botellas |
|---|---:|
| Ingresos procesados | 8.271.361 |
| Transferencias procesadas | 3.599.700 |
| Ventas | 1.116.236 |
| Stock de depósito final | 4.671.661 |
| Stock de sala final | 2.483.464 |

Verificación: 8.271.361 − 3.599.700 = 4.671.661 y
3.599.700 − 1.116.236 = 2.483.464.

Se generaron 500 vinos × 24 salas = 12.000 pares vino/sala. Todos tienen fila de
stock y todos se vendieron al menos una vez salvo el par excluido a propósito
(sala 1, vino 1):

| Sala | Vino | Stock sala | Stock depósito | Vino |
|---:|---:|---:|---:|---|
| 1 | 1 | 0 | 8.510 | Malbec Reserva |

### 6.4. Ventanas de venta

Con corte al 2026-11-10:

| Ventana | Comprobantes |
|---|---:|
| Últimos 7 días | 8.587 |
| Últimos 15 días | 10.240 |
| Últimos 30 días | 13.538 |
| Últimos 90 días | 26.518 |
| Más de 5 años | 18.934 |

Los 150.000 comprobantes tienen en promedio 3,76 renglones y 1,98 botellas por
renglón.

### 6.5. Clientes y permisos

| Tipo de cliente | Cantidad |
|---|---:|
| Común | 8.000 |
| Socio del club | 8.000 |
| Distribuidor | 2.400 |
| Exportador | 1.600 |

- 102 socios con alta de hace más de 5 años no tienen compras; 100 se
  reservaron a propósito y 2 aparecieron por azar.
- 7.450 comprobantes corresponden a socios con fecha anterior a los últimos 5
  años.
- 1.600 exportadores, 3.937 permisos, 304 exportadores con más de 3 permisos y
  437 con exactamente 1 permiso.
- Los exportadores con descuento especial usan el valor cargado; el resto usa el
  30 % por defecto de `fn_descuento_cliente`.

### 6.6. Documentos y estados

| Documento | Estado | Cantidad |
|---|---|---:|
| Ingreso | `en_confeccion` | 200 |
| Ingreso | `terminado` | 300 |
| Ingreso | `procesado` | 700 |
| Transferencia | `en_confeccion` | 50 |
| Transferencia | `terminado` | 50 |
| Transferencia | `procesado` | 1.200 |

Hay permisos vencidos y vigentes, y ventas en distintos años.

### 6.7. Precios históricos

- 37.571 renglones tienen un `precio_unitario` distinto del precio actual del
  vino (6,66 % de los 564.328 renglones).
- 132 filas de `auditoria_precio`, con altas entre 2022-01-01 y 2026-06-01.
- Los cambios de precio se hicieron en fechas lógicas y las ventas usan el
  precio vigente a su fecha.

### 6.8. Composición y cepa sin uso

- Los 500 vinos tienen composición.
- Todas las composiciones suman 100 %.
- Los tintos usan solo cepas tintas y los blancos solo cepas blancas.
- Semillón (cepa 12) tiene 0 parcelas y 0 composiciones.
- Hay 886 pares vino/maridaje.

---

## 7. Riesgos y limitaciones

1. **Fórmulas duplicadas en Python.** Al no llamar a los procedimientos de la
   API, el cálculo de stock, totales y precios históricos vive también en
   `generador.py`. Si esos procedimientos cambian, hay que actualizar el
   generador. Los controles cubren los casos principales, pero no reemplazan una
   prueba de integración contra la API.
2. **Triggers deshabilitados durante la carga.** La deshabilitación es
   transaccional y se revierte si la carga falla. La habilitación se hace antes
   del `COMMIT` y se verifica. Aun así, una carga con triggers deshabilitados no
   valida todas las reglas en el momento de inserción; la validación posterior
   depende de los controles.
3. **`--limpiar` trunca catálogos.** Es adecuado para un entorno de práctica,
   pero no para producción. Los catálogos se recargan desde los CSV.
4. **Escala reducida.** `--escala 0.1` no cumple los mínimos de volumen; el
   control `q02` falla a propósito. Para validar la entrega hay que usar
   `--escala 1.0`.
5. **Fecha de referencia.** Las consultas usan `app.fecha_referencia`; si se
   ejecuta el archivo SQL a mano sin setearla, se usa `CURRENT_DATE` como
   respaldo. Con una fecha de referencia muy distinta, los controles de ventanas
   pueden no representar la realidad de la carga.
6. **Dump sin roles.** El dump usa `--no-owner --no-privileges` y no incluye
   roles. La restauración de datos funciona, pero los roles y permisos deben
   recrearse si se necesitan.
7. **Benchmark local.** Los tiempos dependen de la máquina, del contenedor y de
   la caché. Sirven para comparar COPY, lotes y fila por fila, no como valores
   absolutos.
8. **Datos ficticios.** Faker genera nombres y razones sociales ficticias. Los
   CUIT tienen formato y dígito verificador válidos, pero no corresponden a
   personas o empresas reales.
9. **Volumen de lotes.** Se usaron 900 lotes, el valor planificado para la escala
   1.0. El rango recomendado era 3.000–15.000; los mínimos obligatorios de
   volumen se cumplen con `comprobante` y `renglon_comprobante`. Si se necesita
   el rango completo, se puede aumentar `n_lotes` en `generador.py` y regenerar
   la evidencia.

---

## 8. Conclusiones

La carga cumple los objetivos de la Etapa 3:

- Es determinista y reproducible para la misma semilla, fecha y escala.
- Usa catálogos CSV reales y genera datos coherentes con las reglas del dominio.
- Respeta los volúmenes mínimos y deja las 30 tablas pobladas.
- Mantiene stock, totales, descuentos y precios históricos consistentes sin
  llamar a la API.
- Deshabilita y rehabilita triggers de usuario de forma controlada y verificada.
- Ejecuta `ANALYZE` y ajusta las secuencias identidad.
- Pasa los 10 controles de problema con 0 filas.
- Genera un dump restaurable y verifica la restauración con el mismo hash.

La evidencia principal está en `db/seed/evidencias/` y las instrucciones de
operación en `db/seed/README.md`.

---

## Apéndice A — Comandos de la corrida

```bash
# Carga completa con hashes
python db/seed/cargar_datos.py --limpiar --seed 42 --fecha-ref 2026-11-10 \
  --escala 1.0 --modo copy \
  --hash-out db/seed/evidencias/hashes_run1.json

# Benchmark
python db/seed/cargar_datos.py --benchmark --benchmark-filas 10000

# Dump
export DATABASE_URL='postgresql://postgres:CLAVE@localhost:5433/bodegas_del_atuel'
./db/seed/generar_dump.sh

# Restauración
createdb -h localhost -p 5433 -U postgres bodegas_del_atuel_restore
gunzip -c db/seed/dump_completo.sql.gz | \
  psql -h localhost -p 5433 -U postgres \
       -d bodegas_del_atuel_restore -v ON_ERROR_STOP=1
```

## Apéndice B — Evidencias

```text
db/seed/evidencias/hashes_run1.json
db/seed/evidencias/hashes_run2.json
db/seed/evidencias/hashes_run3.json
db/seed/evidencias/hashes_restore.json
db/seed/evidencias/README.md
```
