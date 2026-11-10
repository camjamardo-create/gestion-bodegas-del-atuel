# Etapa 4 — Índices y rendimiento

**TPI Bases de Datos · Bodegas del Atuel**

- **Entregable de código:** `db/migrations/008_indices.sql`
- **Consultas medidas:** `db/benchmarks/etapa4/s*.sql`
- **Planes crudos:** `db/benchmarks/etapa4/planes/{antes,despues,descartado}/`
- **Mediciones de escritura:** `db/benchmarks/etapa4/carga/`

---

## 1. Resumen

Se crearon **5 índices**, uno de cada tipo pedido:

| # | Índice | Tipo | Consulta | Tamaño |
|---|---|---|---|---|
| 1 | `idx_comprobante_sala_fecha` | compuesto + `INCLUDE` | S3 | 6.664 kB |
| 2 | `idx_comprobante_fecha_sala_total` | cobertura (`INCLUDE`) | S8 | 5.624 kB |
| 3 | `idx_stock_sala_vino` | clave foránea + `INCLUDE` | S9 | 376 kB |
| 4 | `idx_transferencia_pendientes` | parcial (`WHERE`) | S5 | 16 kB |
| 5 | `idx_vino_nombre_lower` | expresión | catálogo de vinos | 16 kB |

Resultados principales (mediana de 3 corridas, `EXPLAIN (ANALYZE, BUFFERS)`):

| Consulta | Antes | Después | Mejora | Buffers |
|---|---:|---:|---:|---|
| **S3** clientes por tipo en una sala, última semana | 9,753 ms | **0,977 ms** | **10,0×** | 2.163 → 808 |
| **S8** ventas por sala, último trimestre | 15,490 ms | **9,174 ms** | **1,69×** | 1.364 → **137** |
| **S9** ficha de un vino con stock total | 0,637 ms | **0,528 ms** | 1,21× | 98 → **24** |
| S5 transferencias pendientes | 0,292 ms | 0,262 ms | 1,11× | 15 → 10 |
| S1 ranking de vinos | 171,848 ms | 172,388 ms | — | 4.105 → 4.083 |
| S11 ranking por sala | 146,994 ms | 160,905 ms | — | 5.457 → 5.422 |
| S10 kg/ha por parcela | 38,038 ms | 38,161 ms | — | 18 → 18 |
| S12 clientes sin tinto | 220,078 ms | 208,176 ms | — | 5.688 → 5.737 |

**Tres consultas mejoran de forma medida** (S3, S8 y S9), con dos cambios de plan claros: `Seq Scan` → `Index Only Scan` en S3 y S8, y `SubPlan` con 25 búsquedas en la PK → 1 búsqueda en un índice de cobertura en S9.

También se documenta:

- un índice **evaluado y descartado** (`renglon_comprobante (codigo_vino) INCLUDE (cantidad)`), con la medición que lo descarta;
- dos descartes más (BRIN sobre `comprobante.fecha` y `comprobante (id_cliente)`);
- el **costo de escritura** medido: +64 % al cargar 150.000 filas con dos índices;
- dos casos en que **el planificador no usa un índice existente** (S11 y S1) y por qué es la decisión correcta.

---

## 2. Entorno

| Componente | Valor |
|---|---|
| Motor | PostgreSQL 18.6 (Debian) en Docker, puerto 5433 |
| `shared_buffers` | 128 MB (`16384` × 8 kB) |
| `work_mem` | 4 MB |
| `effective_cache_size` | 4 GB |
| `max_parallel_workers_per_gather` | 2 |
| Esquema | migraciones `001`–`007` de `main` |
| Datos | carga de Etapa 3 (`--seed 42`, escala 1.0) |
| Tamaño de la base | 89 MB |
| Tablas grandes | `comprobante` 150.000 filas (26 MB), `renglon_comprobante` 564.328 filas (44 MB) |
| Rango de fechas | 2021-01-01 a 2026-11-10 (`CURRENT_DATE` = 2026-11-10) |

Toda la base entra en `shared_buffers`, así que las mediciones son de caché caliente (el mejor caso para el `Seq Scan`). Las diferencias a favor de los índices son, por lo tanto, conservadoras.

---

## 3. Metodología

1. **Baseline**: base cargada solo con las PK y UNIQUE de `001`/`002`. `ANALYZE` completo antes de medir.
2. Cada consulta se ejecutó **3 veces** con `EXPLAIN (ANALYZE, BUFFERS)` desde el mismo cliente `psql`; se reporta la **mediana** y se guarda el plan de la corrida 2.
3. Se diseñaron los índices a partir de los planes (recorridos secuenciales sobre tablas grandes, ordenamientos, subplanes que recorren la tabla entera).
4. Se aplicó `008_indices.sql`, se ejecutó `ANALYZE` y se repitieron las 3 corridas.
5. Se registraron tiempo de ejecución, tipo de recorrido, filas devueltas por el nodo de scan y **buffers** (`shared hit`), que es la métrica más estable cuando la tabla está en caché.

Los planes completos están en el **Anexo A**. Las 3 corridas crudas de cada consulta y fase están en `planes/antes/` y `planes/despues/`.

---

## 4. Índices creados y justificación

### 4.1 `idx_comprobante_sala_fecha` (compuesto + `INCLUDE`) — S3

```sql
CREATE INDEX idx_comprobante_sala_fecha
    ON comprobante (id_sala_venta, fecha)
    INCLUDE (id_cliente);
```

**Plan antes:** `Parallel Seq Scan on comprobante` sobre las 150.000 filas para devolver 395; 2.163 buffers; 9,753 ms.
**Plan después:** `Index Only Scan` que lee 395 entradas en 6 buffers; 808 buffers en total (el resto lo consume el `Nested Loop` con `cliente`); 0,977 ms.

`INCLUDE (id_cliente)` evita el acceso al heap: la consulta necesita `id_sala_venta`, `fecha` e `id_cliente`, y las tres columnas están en el índice. `Heap Fetches: 0` lo confirma.

### 4.2 `idx_comprobante_fecha_sala_total` (cobertura) — S8

```sql
CREATE INDEX idx_comprobante_fecha_sala_total
    ON comprobante (fecha, id_sala_venta)
    INCLUDE (total);
```

**Plan antes:** `Parallel Seq Scan` de las 150.000 filas; 1.364 buffers; 15,490 ms.
**Plan después:** `Index Only Scan` de las 26.640 filas del trimestre; **137 buffers**; 9,174 ms.

La consulta no tiene igualdad: filtra por rango de fecha (18 % de la tabla) y suma `total` agrupando por sala. Con `fecha` como primera columna el rango es un tramo contiguo del árbol; `id_sala_venta` en la clave y `total` en `INCLUDE` permiten resolver proyección y agregación sin tocar el heap.

### 4.3 `idx_stock_sala_vino` (clave foránea + `INCLUDE`) — S9

```sql
CREATE INDEX idx_stock_sala_vino
    ON stock_sala (codigo_vino)
    INCLUDE (cantidad);
```

PostgreSQL **no indexa las claves foráneas**. La PK de `stock_sala` es `(id_sala, codigo_vino)`, así que `codigo_vino` queda como segunda columna. Antes del índice, el subplan de S9 se resolvía con *skip scan* sobre la PK: **25 búsquedas en el árbol, 77 buffers y 0,155 ms** para devolver 24 filas. Después: **1 búsqueda, 3 buffers y 0,033 ms** (`Index Only Scan`, `Heap Fetches: 0`). El total de la consulta pasa de 98 a 24 buffers.

Además del beneficio de lectura, el índice evita que cada `DELETE`/`UPDATE` de `vino` tenga que verificar la FK con un recorrido secuencial de las 12.000 filas de `stock_sala`.

### 4.4 `idx_transferencia_pendientes` (parcial) — S5

```sql
CREATE INDEX idx_transferencia_pendientes
    ON transferencia (id_sala_venta, fecha_confeccion)
    WHERE estado <> 'procesado';
```

Solo interesan las transferencias no procesadas; el resto no se consulta nunca por esta vía. El plan después usa `Bitmap Index Scan on idx_transferencia_pendientes` y lee **100 filas en 1 buffer** (antes: `Seq Scan` de 1.300 filas, 15 buffers). El índice pesa **16 kB** frente a los 64 kB de la tabla. La ganancia en tiempo es chica (0,292 → 0,262 ms) porque la tabla es diminuta, pero el plan demuestra que el índice parcial se usa y que el costo de mantenerlo es mínimo.

### 4.5 `idx_vino_nombre_lower` (expresión)

```sql
CREATE INDEX idx_vino_nombre_lower
    ON vino (lower(nombre));
```

Soporta búsquedas de catálogo por nombre sin distinguir mayúsculas (`WHERE lower(nombre) = ...`). Un índice común sobre `nombre` no sirve para esa expresión porque el planificador compara la expresión, no la columna. `vino` tiene 500 filas: no hay una consulta de la sección 8 que lo justifique por tiempo, pero el índice cuesta 16 kB y habilita el patrón `lower(nombre) = ?` que usa la aplicación.

---

## 5. Por qué ese orden de columnas en los índices compuestos

Para `idx_comprobante_sala_fecha` el filtro de S3 es:

```sql
WHERE co.id_sala_venta = 4
  AND co.fecha >= CURRENT_DATE - 7
```

- **Igualdad primero (`id_sala_venta`), rango después (`fecha`)**: la igualdad fija una única rama del árbol y el rango queda contiguo dentro de esa rama, así que se recorre como un solo tramo. Con el orden inverso (`fecha`, `id_sala_venta`) el rango de fechas quedaría disperso entre las 24 salas y el recorrido tendría que leer todas las entradas del período para filtrar la sala.
- **`INCLUDE` al final**: las columnas de `INCLUDE` no participan del orden ni de la búsqueda; solo se agregan a la hoja para permitir `Index Only Scan`. Poner `id_cliente` en la clave agrandaría las entradas internas del árbol sin mejorar ninguna búsqueda.
- Para `idx_comprobante_fecha_sala_total` (S8) el criterio se invierte porque **no hay igualdad**: la primera columna debe ser la del rango (`fecha`) para que el tramo sea contiguo.

---

## 6. Tabla comparativa

Mediana de 3 corridas. "Filas leídas" es lo que devuelve/recorre el nodo de scan principal (no las filas del resultado).

| Consulta | Antes (ms) | Después (ms) | Mejora | Recorrido antes | Recorrido después | Filas leídas antes → después | Buffers antes → después |
|---|---:|---:|---:|---|---|---|---|
| **S3** | 9,753 | **0,977** | **10,0×** | `Parallel Seq Scan` sobre `comprobante` | `Index Only Scan` (`idx_comprobante_sala_fecha`) | 150.000 → 395 | 2.163 → 808 |
| **S8** | 15,490 | **9,174** | **1,69×** | `Parallel Seq Scan` sobre `comprobante` | `Index Only Scan` (`idx_comprobante_fecha_sala_total`) | 150.000 → 26.640 | 1.364 → **137** |
| **S9** | 0,637 | **0,528** | 1,21× | `SubPlan` con skip scan sobre `stock_sala_pkey` | `Index Only Scan` (`idx_stock_sala_vino`) | 25 búsquedas / 77 buffers → 1 búsqueda / 3 buffers | 98 → **24** |
| S5 | 0,292 | 0,262 | 1,11× | `Seq Scan` sobre `transferencia` | `Bitmap Index Scan` (índice parcial) | 1.300 → 100 | 15 → 10 |
| S1 | 171,848 | 172,388 | — | `Seq Scan` sobre `renglon_comprobante` | `Seq Scan` (sin cambios) | 564.328 → 564.328 | 4.105 → 4.083 |
| S11 | 146,994 | 160,905 | — | `Parallel Seq Scan` | `Parallel Seq Scan` (sin cambios) | 564.328 + 150.000 | 5.457 → 5.422 |
| S10 | 38,038 | 38,161 | — | CTE sobre `lote`/`parcela` | igual | 900 / 600 | 18 → 18 |
| S12 | 220,078 | 208,176 | — | `Hash Join` + `Hash Anti Join` | igual | 564.328 + 150.000 | 5.688 → 5.737 |

> S1, S11, S10 y S12 se incluyen a propósito: muestran que un índice no ayuda cuando hay que leer la tabla completa o cuando las tablas son chicas. La diferencia de S11 (–9 %) y S12 (+5 %) es ruido de plan paralelo, no efecto de los índices.

---

## 7. Lectura de los planes que mejoran

### S3 — de 150.000 filas a 395

Antes (extracto):

```
->  Nested Loop
      ->  Parallel Seq Scan on comprobante co
            Filter: ((id_sala_venta = 4) AND (fecha >= (CURRENT_DATE - 7)))
            Rows Removed by Filter: ...
```

Después (extracto):

```
->  Index Only Scan using idx_comprobante_sala_fecha on comprobante co
      Index Cond: ((id_sala_venta = 4) AND (fecha >= (CURRENT_DATE - 7)))
      Heap Fetches: 0
      Index Searches: 1
      rows=395  Buffers: shared hit=6
```

El `Nested Loop` contra `cliente` (395 iteraciones) sigue costando ~800 buffers porque busca cada cliente por PK; el cuello de botella pasó de la tabla de 150.000 filas al acceso puntual de 395 clientes.

### S8 — de 1.364 a 137 buffers

Antes (extracto):

```
->  Parallel Seq Scan on comprobante co
      Filter: (fecha >= (CURRENT_DATE - '3 mons'::interval))
```

Después (extracto):

```
->  Index Only Scan using idx_comprobante_fecha_sala_total on comprobante co
      Index Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
      Heap Fetches: 0
      rows=26640  Buffers: shared hit=133
```

La mejora es de 10× en buffers porque el índice solo contiene `fecha`, `id_sala_venta` y `total`: no se lee ninguna de las 1.339 páginas del heap.

### S9 — el subplan de stock

Antes (extracto):

```
SubPlan 4
  ->  Aggregate
        ->  Index Scan using stock_sala_pkey on stock_sala
              Index Cond: (codigo_vino = v.codigo)
              Index Searches: 25          <-- skip scan
              rows=24  Buffers: shared hit=77
```

Después (extracto):

```
SubPlan 4
  ->  Aggregate
        ->  Index Only Scan using idx_stock_sala_vino on stock_sala
              Index Cond: (codigo_vino = v.codigo)
              Heap Fetches: 0
              Index Searches: 1
              rows=24  Buffers: shared hit=3
```

---

## 8. Índice evaluado y descartado

### 8.1 `renglon_comprobante (codigo_vino) INCLUDE (cantidad)`

**Hipótesis.** S1 y S11 agrupan por `codigo_vino` sobre los 564.328 renglones. Un índice de cobertura ordenado por `codigo_vino` debería permitir `Index Only Scan` + `GroupAggregate` y evitar leer las 4.096 páginas del heap.

**Medición (creado el índice y `ANALYZE`):**

| Escenario | Tiempo | Plan |
|---|---:|---|
| S1 sin el índice | 171,848 ms | `Seq Scan` (4.096 buffers) |
| S1 con el índice, planificador libre | 176,6 / 171,4 / 193,0 ms | **sigue eligiendo `Seq Scan`** |
| S1 forzado con `enable_seqscan = off` | 185,201 ms | `Index Only Scan` (1.540 buffers) + `HashAggregate` |

**Por qué se descarta.** La consulta necesita **el 100 % de las filas**: agrupa los 564.328 renglones por vino. El recorrido secuencial lee 4.096 páginas contiguas a ~24 ms; el `Index Only Scan` lee 1.540 páginas de índice pero además recorre 564.328 tuplas de índice con más CPU por tupla, y tarda ~54 ms. El planificador lo detecta y **no usa el índice** (ver §10). El índice solo agrega 12 MB y costo de mantenimiento.

### 8.2 BRIN sobre `comprobante.fecha`

Se probó `CREATE INDEX ... USING brin (fecha) WITH (pages_per_range = 32)`.

| Índice | Tamaño | S8 (mediana) | Buffers |
|---|---:|---:|---:|
| BRIN sobre `fecha` | **24 kB** | 10,886 ms | 297 |
| B-tree `(fecha, id_sala_venta) INCLUDE (total)` | 5.624 kB | **9,174 ms** | **137** |

El BRIN es 230× más chico, pero S8 pide el 18 % de la tabla: el `Bitmap Heap Scan` termina visitando 293 páginas del heap. El b-tree de cobertura gana porque no toca el heap. Se descarta el BRIN para esta consulta (sería razonable para rangos de <1 % o para tablas históricas mucho más grandes).

### 8.3 `comprobante (id_cliente) INCLUDE (numero)`

Se probó porque `id_cliente` es FK sin índice y S12 (anti-join) recorre los 20.000 clientes. Resultado: **208,7 ms contra 220,1 ms**, con el mismo plan de `Hash Join` + `Hash Anti Join`; el planificador no lo usa. S12 necesita el 69 % de los renglones (los tintos), así que no hay selectividad que explotar. Se descartó.

---

## 9. Costo de escritura

### 9.1 Experimento controlado (aislado de Python)

La carga completa del *seeder* tarda 18,6 / 18,0 / 17,6 s con y sin índices: **no sirve para medir el costo de escritura** porque el tiempo está dominado por Python (generación con Faker y cálculo de hashes), no por la base.

Para aislarlo se crearon dos tablas equivalentes a `comprobante` (mismas columnas, CHECK y PK) y se insertaron las 150.000 filas con `INSERT ... SELECT`:

| Tabla | Índices | Run 1 | Run 2 | Run 3 | **Mediana** | Tamaño |
|---|---|---:|---:|---:|---:|---:|
| `bench_sin` | PK | 447,1 ms | 654,8 ms | 516,8 ms | **516,8 ms** | 14 MB |
| `bench_con` | PK + 2 índices de `comprobante` | 930,6 ms | 846,9 ms | 776,8 ms | **846,9 ms** | 26 MB |

**Costo: +330 ms (+64 %) y +12 MB** para cargar 150.000 filas con los dos índices de `comprobante` (≈ 2,2 µs extra por fila). Las tablas de prueba se eliminaron al terminar; la salida cruda está en `carga/costo_escritura_comprobante.txt`.

### 9.2 Interpretación

- Cada `INSERT`, `UPDATE` y `DELETE` paga el mantenimiento de **todos** los índices de la tabla. En `comprobante` son dos índices de cobertura que duplican el ancho de la clave (incluyen `id_cliente`/`total`), por eso el +64 %.
- El costo medido es el **mejor caso**: la carga inserta en orden de `numero`, que correlaciona con `fecha`, así que las entradas se agregan al final del árbol. Con inserciones desordenadas el costo sería mayor.
- Los índices se construyeron sobre la tabla cargada y después se recargaron los datos tres veces para esta medición; por eso `idx_comprobante_sala_fecha` quedó en 6.664 kB (la primera construcción ocupaba 4.640 kB). En producción conviene cargar primero y crear los índices después: se obtiene un árbol más compacto y se paga una sola vez la construcción.

Balance: S3 pasa de 9,7 ms a 1 ms y S8 de 15,5 a 9,2 ms, sobre una tabla que se lee mucho más de lo que se escribe. El costo de escritura se justifica.

---

## 10. Casos en que el planificador no usa un índice existente

### 10.1 S11 con `idx_comprobante_sala_fecha` disponible

S11 agrupa los 564.328 renglones por sala y vino y calcula `RANK()`. Existe un índice sobre `(id_sala_venta, fecha)`, pero el planificador elige `Parallel Seq Scan` sobre `renglon_comprobante` y `comprobante` (160,9 ms, 5.422 buffers) porque la consulta necesita **todas** las filas de ambas tablas.

Forzando el índice:

```sql
SET enable_seqscan = off;
-- S11 -> 172,629 ms
```

El plan forzado usa `Parallel Index Scan` sobre las PK de `renglon_comprobante` y `comprobante` y **es 7 % más lento** (172,6 ms contra 160,9 ms). El planificador tiene razón: con selectividad del 100 %, recorrer el heap secuencialmente (y en paralelo) es más barato que saltar por el árbol.

### 10.2 S1 con el índice descartado

Con `idx_renglon_comprobante_vino_cantidad` creado, el planificador **siguió usando `Seq Scan`** (171–193 ms). Forzado con `enable_seqscan = off`, el `Index Only Scan` tarda 185,2 ms: el índice no aporta cuando hay que leer todas las filas.

### 10.3 Estadísticas

Todas las mediciones se hicieron después de `ANALYZE`. Sin estadísticas frescas (por ejemplo, justo después de una carga masiva) el planificador puede subestimar la selectividad y elegir un índice que no conviene, o al revés. Por eso `008` se aplica y se sigue de `ANALYZE`, y la carga de la Etapa 3 ya lo ejecuta al final.

---

## 11. Otros candidatos evaluados y no creados

| Candidato | Por qué no se creó |
|---|---|
| `lote (id_finca, numero_parcela)` | Redundante: `uk_lote_parcela_finca_campaña UNIQUE (id_finca, numero_parcela, "campaña")` ya cubre ese prefijo. S10 se resuelve con 18 buffers sobre 900 filas. |
| `vino (tipo)` | Solo 347 de 500 vinos son tintos (69 %). No hay selectividad; S12 no lo usaría. |
| `comprobante (id_sala_venta, fecha)` sin `INCLUDE` | Sería un `Index Scan` con acceso al heap para `id_cliente`; el `INCLUDE` evita 6 buffers por fila. |
| `transferencia (estado)` completo | El parcial pesa 16 kB y solo indexa las pendientes; el completo indexaría 1.200 filas que nunca se filtran por estado. |

> **S6** (vinos sin stock en sala con stock en depósito) se midió en 0,37–0,49 ms, pero en este dataset devuelve 0 filas para la sala elegida; no se usa como evidencia. Sus planes quedaron en `planes/antes/`.

---

## 12. Reproducción

```powershell
# 1. Base y esquema
docker compose up -d
$env:PGPASSWORD = '<password de .env>'
psql -h localhost -p 5433 -U postgres -d bodegas_del_atuel -f db/migrations/001_esquema.sql
# ... 002 a 007 ...
python db/seed/cargar_datos.py --limpiar --hash-out db/seed/.hash.json

# 2. Baseline (solo PK/UNIQUE)
psql -h localhost -p 5433 -U postgres -d bodegas_del_atuel -c "ANALYZE;"
# por cada consulta de db/benchmarks/etapa4/*.sql:
#   (echo "EXPLAIN (ANALYZE, BUFFERS)"; type <consulta>.sql) | psql ... > planes/antes/<consulta>_runN.txt

# 3. Índices y medición final
psql -h localhost -p 5433 -U postgres -d bodegas_del_atuel -f db/migrations/008_indices.sql
psql -h localhost -p 5433 -U postgres -d bodegas_del_atuel -c "ANALYZE;"
# repetir el paso 2 guardando en planes/despues/
```

El hash de la carga debe ser `5865ce1c…d01745`, idéntico al de `db/seed/evidencias/hashes_run1.json`.

---

## 13. Conclusiones

1. Los índices rinden cuando la consulta es **selectiva**: S3 (0,26 % de la tabla) mejora 10× y S8 (18 %) mejora 1,7× con 10× menos buffers.
2. `INCLUDE` es lo que convierte un buen índice en un `Index Only Scan`: en S8 elimina por completo el acceso al heap.
3. Un índice **no** ayuda cuando hay que leer todas las filas (S1, S11): el `Seq Scan` secuencial y paralelo gana, y el planificador lo elige.
4. Las tablas chicas (`stock_sala` 12.000 filas, `transferencia` 1.300, `lote` 900) no mejoran por tiempo, pero el índice de FK evita recorridos en el mantenimiento referencial y el parcial demuestra el patrón con 16 kB.
5. El costo de escritura es real y medible: **+64 %** al cargar 150.000 filas y **+12 MB**. Se acepta porque el sistema lee mucho más de lo que escribe.
6. Medir antes/después con `BUFFERS` permite distinguir una mejora real de una variación de ruido: S11 “empeora” 9 % sin cambiar de plan, y S12 mejora 5 % sin usar ningún índice.

---

## Anexo A — Planes completos

Los bloques siguientes son la salida literal de `EXPLAIN (ANALYZE, BUFFERS)` (corrida 2 de 3).

### S1 — Ranking de vinos por botellas — antes

```text
                                                                       QUERY PLAN                                                                        
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=17363.68..17363.71 rows=10 width=31) (actual time=170.857..170.860 rows=10.00 loops=1)
   Buffers: shared hit=4105
   ->  Sort  (cost=17363.68..17512.43 rows=59500 width=31) (actual time=170.856..170.858 rows=10.00 loops=1)
         Sort Key: (sum(rc.cantidad)) DESC
         Sort Method: top-N heapsort  Memory: 26kB
         Buffers: shared hit=4105
         ->  HashAggregate  (cost=15482.91..16077.91 rows=59500 width=31) (actual time=170.669..170.788 rows=500.00 loops=1)
               Group Key: rc.codigo_vino, v.nombre
               Batches: 1  Memory Usage: 1081kB
               Buffers: shared hit=4102
               ->  Hash Join  (cost=17.25..11250.45 rows=564328 width=27) (actual time=0.159..95.517 rows=564328.00 loops=1)
                     Hash Cond: (rc.codigo_vino = v.codigo)
                     Buffers: shared hit=4102
                     ->  Seq Scan on renglon_comprobante rc  (cost=0.00..9739.28 rows=564328 width=8) (actual time=0.026..23.743 rows=564328.00 loops=1)
                           Buffers: shared hit=4096
                     ->  Hash  (cost=11.00..11.00 rows=500 width=23) (actual time=0.108..0.108 rows=500.00 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 37kB
                           Buffers: shared hit=6
                           ->  Seq Scan on vino v  (cost=0.00..11.00 rows=500 width=23) (actual time=0.006..0.037 rows=500.00 loops=1)
                                 Buffers: shared hit=6
 Planning:
   Buffers: shared hit=189
 Planning Time: 0.665 ms
 Execution Time: 171.848 ms
(24 filas)
```

### S1 — Ranking de vinos por botellas — despues

```text
                                                                       QUERY PLAN                                                                        
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=17341.68..17341.71 rows=10 width=31) (actual time=171.491..171.495 rows=10.00 loops=1)
   Buffers: shared hit=4083
   ->  Sort  (cost=17341.68..17490.43 rows=59500 width=31) (actual time=171.489..171.492 rows=10.00 loops=1)
         Sort Key: (sum(rc.cantidad)) DESC
         Sort Method: top-N heapsort  Memory: 26kB
         Buffers: shared hit=4083
         ->  HashAggregate  (cost=15460.91..16055.91 rows=59500 width=31) (actual time=171.305..171.421 rows=500.00 loops=1)
               Group Key: rc.codigo_vino, v.nombre
               Batches: 1  Memory Usage: 1081kB
               Buffers: shared hit=4080
               ->  Hash Join  (cost=17.25..11228.45 rows=564328 width=27) (actual time=0.150..96.403 rows=564328.00 loops=1)
                     Hash Cond: (rc.codigo_vino = v.codigo)
                     Buffers: shared hit=4080
                     ->  Seq Scan on renglon_comprobante rc  (cost=0.00..9717.28 rows=564328 width=8) (actual time=0.019..23.586 rows=564328.00 loops=1)
                           Buffers: shared hit=4074
                     ->  Hash  (cost=11.00..11.00 rows=500 width=23) (actual time=0.104..0.104 rows=500.00 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 37kB
                           Buffers: shared hit=6
                           ->  Seq Scan on vino v  (cost=0.00..11.00 rows=500 width=23) (actual time=0.010..0.040 rows=500.00 loops=1)
                                 Buffers: shared hit=6
 Planning:
   Buffers: shared hit=204
 Planning Time: 0.716 ms
 Execution Time: 172.388 ms
(24 filas)
```

### S3 — Clientes por tipo en una sala (última semana) — antes

```text
                                                                              QUERY PLAN                                                                              
----------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=4396.37..4396.38 rows=4 width=12) (actual time=7.359..9.719 rows=4.00 loops=1)
   Sort Key: (count(DISTINCT c.id)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=2163
   ->  GroupAggregate  (cost=4352.75..4396.33 rows=4 width=12) (actual time=7.295..9.698 rows=4.00 loops=1)
         Group Key: c.tipo
         Buffers: shared hit=2160
         ->  Gather Merge  (cost=4352.75..4394.46 rows=366 width=8) (actual time=7.223..9.645 rows=395.00 loops=1)
               Workers Planned: 1
               Workers Launched: 1
               Buffers: shared hit=2160
               ->  Sort  (cost=3352.74..3353.28 rows=215 width=8) (actual time=4.749..4.757 rows=197.50 loops=2)
                     Sort Key: c.tipo, c.id
                     Sort Method: quicksort  Memory: 28kB
                     Buffers: shared hit=2160
                     Worker 0:  Sort Method: quicksort  Memory: 30kB
                     ->  Nested Loop  (cost=0.29..3344.41 rows=215 width=8) (actual time=3.824..4.662 rows=197.50 loops=2)
                           Buffers: shared hit=2145
                           ->  Parallel Seq Scan on comprobante co  (cost=0.00..3116.71 rows=215 width=4) (actual time=3.779..4.132 rows=197.50 loops=2)
                                 Filter: ((id_sala_venta = 4) AND (fecha >= (CURRENT_DATE - 7)))
                                 Rows Removed by Filter: 74802
                                 Buffers: shared hit=1352
                           ->  Index Only Scan using uk_cliente_id_tipo on cliente c  (cost=0.29..1.06 rows=1 width=8) (actual time=0.002..0.002 rows=1.00 loops=395)
                                 Index Cond: (id = co.id_cliente)
                                 Heap Fetches: 0
                                 Index Searches: 395
                                 Buffers: shared hit=793
 Planning:
   Buffers: shared hit=196
 Planning Time: 0.712 ms
 Execution Time: 9.819 ms
(31 filas)
```

### S3 — Clientes por tipo en una sala (última semana) — despues

```text
                                                                                   QUERY PLAN                                                                                   
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=376.84..376.85 rows=4 width=12) (actual time=0.812..0.813 rows=4.00 loops=1)
   Sort Key: (count(DISTINCT c.id)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=808
   ->  GroupAggregate  (cost=373.96..376.80 rows=4 width=12) (actual time=0.770..0.792 rows=4.00 loops=1)
         Group Key: c.tipo
         Buffers: shared hit=805
         ->  Sort  (cost=373.96..374.89 rows=374 width=8) (actual time=0.750..0.762 rows=395.00 loops=1)
               Sort Key: c.tipo, c.id
               Sort Method: quicksort  Memory: 34kB
               Buffers: shared hit=805
               ->  Nested Loop  (cost=0.71..357.98 rows=374 width=8) (actual time=0.029..0.591 rows=395.00 loops=1)
                     Buffers: shared hit=797
                     ->  Index Only Scan using idx_comprobante_sala_fecha on comprobante co  (cost=0.42..15.91 rows=374 width=4) (actual time=0.014..0.043 rows=395.00 loops=1)
                           Index Cond: ((id_sala_venta = 4) AND (fecha >= (CURRENT_DATE - 7)))
                           Heap Fetches: 0
                           Index Searches: 1
                           Buffers: shared hit=6
                     ->  Index Only Scan using uk_cliente_id_tipo on cliente c  (cost=0.29..0.91 rows=1 width=8) (actual time=0.001..0.001 rows=1.00 loops=395)
                           Index Cond: (id = co.id_cliente)
                           Heap Fetches: 0
                           Index Searches: 395
                           Buffers: shared hit=791
 Planning:
   Buffers: shared hit=256
 Planning Time: 0.779 ms
 Execution Time: 0.886 ms
(27 filas)
```

### S5 — Transferencias pendientes por sala — antes

```text
                                                             QUERY PLAN                                                             
------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=27.39..27.45 rows=24 width=28) (actual time=0.184..0.186 rows=24.00 loops=1)
   Sort Key: (count(t.numero)), s.id
   Sort Method: quicksort  Memory: 26kB
   Buffers: shared hit=15
   ->  HashAggregate  (cost=26.60..26.84 rows=24 width=28) (actual time=0.134..0.137 rows=24.00 loops=1)
         Group Key: s.id
         Batches: 1  Memory Usage: 32kB
         Buffers: shared hit=9
         ->  Hash Right Join  (cost=1.54..26.10 rows=100 width=24) (actual time=0.099..0.119 rows=100.00 loops=1)
               Hash Cond: (t.id_sala_venta = s.id)
               Buffers: shared hit=9
               ->  Seq Scan on transferencia t  (cost=0.00..24.25 rows=100 width=8) (actual time=0.056..0.062 rows=100.00 loops=1)
                     Filter: (estado <> 'procesado'::tipo_estado)
                     Rows Removed by Filter: 1200
                     Buffers: shared hit=8
               ->  Hash  (cost=1.24..1.24 rows=24 width=20) (actual time=0.028..0.028 rows=24.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 10kB
                     Buffers: shared hit=1
                     ->  Seq Scan on sala_venta s  (cost=0.00..1.24 rows=24 width=20) (actual time=0.010..0.011 rows=24.00 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=146
 Planning Time: 0.493 ms
 Execution Time: 0.273 ms
(24 filas)
```

### S5 — Transferencias pendientes por sala — despues

```text
                                                                          QUERY PLAN                                                                          
--------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=21.05..21.11 rows=24 width=28) (actual time=0.146..0.149 rows=24.00 loops=1)
   Sort Key: (count(t.numero)), s.id
   Sort Method: quicksort  Memory: 26kB
   Buffers: shared hit=10
   ->  HashAggregate  (cost=20.26..20.50 rows=24 width=28) (actual time=0.109..0.112 rows=24.00 loops=1)
         Group Key: s.id
         Batches: 1  Memory Usage: 32kB
         Buffers: shared hit=4
         ->  Hash Right Join  (cost=10.21..19.76 rows=100 width=24) (actual time=0.073..0.093 rows=100.00 loops=1)
               Hash Cond: (t.id_sala_venta = s.id)
               Buffers: shared hit=4
               ->  Bitmap Heap Scan on transferencia t  (cost=8.67..17.92 rows=100 width=8) (actual time=0.031..0.036 rows=100.00 loops=1)
                     Recheck Cond: (estado <> 'procesado'::tipo_estado)
                     Heap Blocks: exact=2
                     Buffers: shared hit=3
                     ->  Bitmap Index Scan on idx_transferencia_pendientes  (cost=0.00..8.64 rows=100 width=0) (actual time=0.012..0.013 rows=100.00 loops=1)
                           Index Searches: 1
                           Buffers: shared hit=1
               ->  Hash  (cost=1.24..1.24 rows=24 width=20) (actual time=0.027..0.027 rows=24.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 10kB
                     Buffers: shared hit=1
                     ->  Seq Scan on sala_venta s  (cost=0.00..1.24 rows=24 width=20) (actual time=0.012..0.014 rows=24.00 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=176
 Planning Time: 0.641 ms
 Execution Time: 0.262 ms
(27 filas)
```

### S8 — Ventas por sala (último trimestre) — antes

```text
                                                                             QUERY PLAN                                                                             
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=4030.86..4030.92 rows=24 width=52) (actual time=12.665..15.342 rows=24.00 loops=1)
   Sort Key: (sum(co.total)) DESC
   Sort Method: quicksort  Memory: 26kB
   Buffers: shared hit=1364
   ->  Finalize GroupAggregate  (cost=4025.03..4030.31 rows=24 width=52) (actual time=12.595..15.311 rows=24.00 loops=1)
         Group Key: s.id
         Buffers: shared hit=1361
         ->  Gather Merge  (cost=4025.03..4029.71 rows=41 width=52) (actual time=12.589..15.276 rows=48.00 loops=1)
               Workers Planned: 1
               Workers Launched: 1
               Buffers: shared hit=1361
               ->  Sort  (cost=3025.02..3025.08 rows=24 width=52) (actual time=10.113..10.116 rows=24.00 loops=2)
                     Sort Key: s.id
                     Sort Method: quicksort  Memory: 27kB
                     Buffers: shared hit=1361
                     Worker 0:  Sort Method: quicksort  Memory: 27kB
                     ->  Partial HashAggregate  (cost=3024.17..3024.47 rows=24 width=52) (actual time=10.073..10.080 rows=24.00 loops=2)
                           Group Key: s.id
                           Batches: 1  Memory Usage: 32kB
                           Buffers: shared hit=1354
                           Worker 0:  Batches: 1  Memory Usage: 32kB
                           ->  Hash Join  (cost=1.54..2945.97 rows=15641 width=28) (actual time=1.958..8.348 rows=13320.00 loops=2)
                                 Hash Cond: (co.id_sala_venta = s.id)
                                 Buffers: shared hit=1354
                                 ->  Parallel Seq Scan on comprobante co  (cost=0.00..2896.12 rows=15641 width=12) (actual time=1.916..6.560 rows=13320.00 loops=2)
                                       Filter: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                                       Rows Removed by Filter: 61680
                                       Buffers: shared hit=1352
                                 ->  Hash  (cost=1.24..1.24 rows=24 width=20) (actual time=0.020..0.021 rows=24.00 loops=2)
                                       Buckets: 1024  Batches: 1  Memory Usage: 10kB
                                       Buffers: shared hit=2
                                       ->  Seq Scan on sala_venta s  (cost=0.00..1.24 rows=24 width=20) (actual time=0.011..0.012 rows=24.00 loops=2)
                                             Buffers: shared hit=2
 Planning:
   Buffers: shared hit=175
 Planning Time: 0.695 ms
 Execution Time: 15.478 ms
(37 filas)
```

### S8 — Ventas por sala (último trimestre) — despues

```text
                                                                                      QUERY PLAN                                                                                      
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=1218.18..1218.24 rows=24 width=52) (actual time=8.685..8.687 rows=24.00 loops=1)
   Sort Key: (sum(co.total)) DESC
   Sort Method: quicksort  Memory: 26kB
   Buffers: shared hit=137
   ->  HashAggregate  (cost=1217.33..1217.63 rows=24 width=52) (actual time=8.637..8.643 rows=24.00 loops=1)
         Group Key: s.id
         Batches: 1  Memory Usage: 32kB
         Buffers: shared hit=134
         ->  Hash Join  (cost=1.97..1080.67 rows=27331 width=28) (actual time=0.080..5.211 rows=26640.00 loops=1)
               Hash Cond: (co.id_sala_venta = s.id)
               Buffers: shared hit=134
               ->  Index Only Scan using idx_comprobante_fecha_sala_total on comprobante co  (cost=0.42..994.72 rows=27331 width=12) (actual time=0.041..2.045 rows=26640.00 loops=1)
                     Index Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                     Heap Fetches: 0
                     Index Searches: 1
                     Buffers: shared hit=133
               ->  Hash  (cost=1.24..1.24 rows=24 width=20) (actual time=0.023..0.023 rows=24.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 10kB
                     Buffers: shared hit=1
                     ->  Seq Scan on sala_venta s  (cost=0.00..1.24 rows=24 width=20) (actual time=0.006..0.008 rows=24.00 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=234
 Planning Time: 0.800 ms
 Execution Time: 8.763 ms
(25 filas)
```

### S9 — Ficha de un vino con stock total — antes

```text
                                                                              QUERY PLAN                                                                               
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Hash Join  (cost=8.30..120.49 rows=1 width=120) (actual time=0.416..0.420 rows=1.00 loops=1)
   Hash Cond: ((b.cuit)::bpchar = (v.cuit_bodega)::bpchar)
   Buffers: shared hit=98
   ->  Seq Scan on bodega b  (cost=0.00..1.20 rows=20 width=37) (actual time=0.006..0.007 rows=20.00 loops=1)
         Buffers: shared hit=1
   ->  Hash  (cost=8.29..8.29 rows=1 width=35) (actual time=0.030..0.030 rows=1.00 loops=1)
         Buckets: 1024  Batches: 1  Memory Usage: 9kB
         Buffers: shared hit=3
         ->  Index Scan using vino_pkey on vino v  (cost=0.27..8.29 rows=1 width=35) (actual time=0.019..0.020 rows=1.00 loops=1)
               Index Cond: (codigo = 1)
               Index Searches: 1
               Buffers: shared hit=3
   SubPlan 1
     ->  Aggregate  (cost=10.17..10.18 rows=1 width=32) (actual time=0.086..0.087 rows=1.00 loops=1)
           Buffers: shared hit=7
           ->  Sort  (cost=10.14..10.14 rows=2 width=15) (actual time=0.081..0.082 rows=2.00 loops=1)
                 Sort Key: co.porcentaje DESC
                 Sort Method: quicksort  Memory: 25kB
                 Buffers: shared hit=7
                 ->  Hash Join  (cost=5.56..10.13 rows=2 width=15) (actual time=0.047..0.048 rows=2.00 loops=1)
                       Hash Cond: (co.id_cepa = c.id)
                       Buffers: shared hit=4
                       ->  Bitmap Heap Scan on composicion co  (cost=4.29..8.85 rows=2 width=9) (actual time=0.016..0.016 rows=2.00 loops=1)
                             Recheck Cond: (codigo_vino = v.codigo)
                             Heap Blocks: exact=1
                             Buffers: shared hit=3
                             ->  Bitmap Index Scan on composicion_pkey  (cost=0.00..4.29 rows=2 width=0) (actual time=0.003..0.003 rows=2.00 loops=1)
                                   Index Cond: (codigo_vino = v.codigo)
                                   Index Searches: 1
                                   Buffers: shared hit=2
                       ->  Hash  (cost=1.12..1.12 rows=12 width=14) (actual time=0.012..0.012 rows=12.00 loops=1)
                             Buckets: 1024  Batches: 1  Memory Usage: 9kB
                             Buffers: shared hit=1
                             ->  Seq Scan on cepa c  (cost=0.00..1.12 rows=12 width=14) (actual time=0.004..0.006 rows=12.00 loops=1)
                                   Buffers: shared hit=1
   SubPlan 2
     ->  Aggregate  (cost=5.52..5.53 rows=1 width=32) (actual time=0.090..0.091 rows=1.00 loops=1)
           Buffers: shared hit=7
           ->  Sort  (cost=5.51..5.51 rows=2 width=15) (actual time=0.089..0.089 rows=2.00 loops=1)
                 Sort Key: m.nombre
                 Sort Method: quicksort  Memory: 25kB
                 Buffers: shared hit=7
                 ->  Hash Join  (cost=1.46..5.50 rows=2 width=15) (actual time=0.059..0.060 rows=2.00 loops=1)
                       Hash Cond: (vm.id_maridaje = m.id)
                       Buffers: shared hit=4
                       ->  Index Only Scan using vino_maridaje_pkey on vino_maridaje vm  (cost=0.28..4.31 rows=2 width=4) (actual time=0.029..0.029 rows=2.00 loops=1)
                             Index Cond: (codigo_vino = v.codigo)
                             Heap Fetches: 0
                             Index Searches: 1
                             Buffers: shared hit=3
                       ->  Hash  (cost=1.08..1.08 rows=8 width=19) (actual time=0.011..0.011 rows=8.00 loops=1)
                             Buckets: 1024  Batches: 1  Memory Usage: 9kB
                             Buffers: shared hit=1
                             ->  Seq Scan on maridaje m  (cost=0.00..1.08 rows=8 width=19) (actual time=0.002..0.003 rows=8.00 loops=1)
                                   Buffers: shared hit=1
   SubPlan 3
     ->  Aggregate  (cost=8.29..8.30 rows=1 width=8) (actual time=0.021..0.021 rows=1.00 loops=1)
           Buffers: shared hit=3
           ->  Index Scan using stock_deposito_pkey on stock_deposito  (cost=0.27..8.29 rows=1 width=4) (actual time=0.020..0.020 rows=1.00 loops=1)
                 Index Cond: (codigo_vino = v.codigo)
                 Index Searches: 1
                 Buffers: shared hit=3
   SubPlan 4
     ->  Aggregate  (cost=86.90..86.91 rows=1 width=8) (actual time=0.155..0.155 rows=1.00 loops=1)
           Buffers: shared hit=77
           ->  Index Scan using stock_sala_pkey on stock_sala  (cost=0.29..86.84 rows=24 width=4) (actual time=0.022..0.153 rows=24.00 loops=1)
                 Index Cond: (codigo_vino = v.codigo)
                 Index Searches: 25
                 Buffers: shared hit=77
 Planning:
   Buffers: shared hit=531
 Planning Time: 1.526 ms
 Execution Time: 0.619 ms
(73 filas)
```

### S9 — Ficha de un vino con stock total — despues

```text
                                                                              QUERY PLAN                                                                               
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Hash Join  (cost=8.30..38.36 rows=1 width=120) (actual time=0.314..0.318 rows=1.00 loops=1)
   Hash Cond: ((b.cuit)::bpchar = (v.cuit_bodega)::bpchar)
   Buffers: shared hit=24
   ->  Seq Scan on bodega b  (cost=0.00..1.20 rows=20 width=37) (actual time=0.011..0.013 rows=20.00 loops=1)
         Buffers: shared hit=1
   ->  Hash  (cost=8.29..8.29 rows=1 width=35) (actual time=0.027..0.027 rows=1.00 loops=1)
         Buckets: 1024  Batches: 1  Memory Usage: 9kB
         Buffers: shared hit=3
         ->  Index Scan using vino_pkey on vino v  (cost=0.27..8.29 rows=1 width=35) (actual time=0.020..0.020 rows=1.00 loops=1)
               Index Cond: (codigo = 1)
               Index Searches: 1
               Buffers: shared hit=3
   SubPlan 1
     ->  Aggregate  (cost=10.17..10.18 rows=1 width=32) (actual time=0.087..0.088 rows=1.00 loops=1)
           Buffers: shared hit=7
           ->  Sort  (cost=10.14..10.14 rows=2 width=15) (actual time=0.081..0.083 rows=2.00 loops=1)
                 Sort Key: co.porcentaje DESC
                 Sort Method: quicksort  Memory: 25kB
                 Buffers: shared hit=7
                 ->  Hash Join  (cost=5.56..10.13 rows=2 width=15) (actual time=0.052..0.053 rows=2.00 loops=1)
                       Hash Cond: (co.id_cepa = c.id)
                       Buffers: shared hit=4
                       ->  Bitmap Heap Scan on composicion co  (cost=4.29..8.85 rows=2 width=9) (actual time=0.015..0.016 rows=2.00 loops=1)
                             Recheck Cond: (codigo_vino = v.codigo)
                             Heap Blocks: exact=1
                             Buffers: shared hit=3
                             ->  Bitmap Index Scan on composicion_pkey  (cost=0.00..4.29 rows=2 width=0) (actual time=0.003..0.003 rows=2.00 loops=1)
                                   Index Cond: (codigo_vino = v.codigo)
                                   Index Searches: 1
                                   Buffers: shared hit=2
                       ->  Hash  (cost=1.12..1.12 rows=12 width=14) (actual time=0.014..0.014 rows=12.00 loops=1)
                             Buckets: 1024  Batches: 1  Memory Usage: 9kB
                             Buffers: shared hit=1
                             ->  Seq Scan on cepa c  (cost=0.00..1.12 rows=12 width=14) (actual time=0.002..0.004 rows=12.00 loops=1)
                                   Buffers: shared hit=1
   SubPlan 2
     ->  Aggregate  (cost=5.52..5.53 rows=1 width=32) (actual time=0.106..0.107 rows=1.00 loops=1)
           Buffers: shared hit=7
           ->  Sort  (cost=5.51..5.51 rows=2 width=15) (actual time=0.105..0.105 rows=2.00 loops=1)
                 Sort Key: m.nombre
                 Sort Method: quicksort  Memory: 25kB
                 Buffers: shared hit=7
                 ->  Hash Join  (cost=1.46..5.50 rows=2 width=15) (actual time=0.065..0.066 rows=2.00 loops=1)
                       Hash Cond: (vm.id_maridaje = m.id)
                       Buffers: shared hit=4
                       ->  Index Only Scan using vino_maridaje_pkey on vino_maridaje vm  (cost=0.28..4.31 rows=2 width=4) (actual time=0.027..0.027 rows=2.00 loops=1)
                             Index Cond: (codigo_vino = v.codigo)
                             Heap Fetches: 0
                             Index Searches: 1
                             Buffers: shared hit=3
                       ->  Hash  (cost=1.08..1.08 rows=8 width=19) (actual time=0.016..0.016 rows=8.00 loops=1)
                             Buckets: 1024  Batches: 1  Memory Usage: 9kB
                             Buffers: shared hit=1
                             ->  Seq Scan on maridaje m  (cost=0.00..1.08 rows=8 width=19) (actual time=0.002..0.003 rows=8.00 loops=1)
                                   Buffers: shared hit=1
   SubPlan 3
     ->  Aggregate  (cost=8.29..8.30 rows=1 width=8) (actual time=0.020..0.020 rows=1.00 loops=1)
           Buffers: shared hit=3
           ->  Index Scan using stock_deposito_pkey on stock_deposito  (cost=0.27..8.29 rows=1 width=4) (actual time=0.018..0.019 rows=1.00 loops=1)
                 Index Cond: (codigo_vino = v.codigo)
                 Index Searches: 1
                 Buffers: shared hit=3
   SubPlan 4
     ->  Aggregate  (cost=4.76..4.77 rows=1 width=8) (actual time=0.033..0.033 rows=1.00 loops=1)
           Buffers: shared hit=3
           ->  Index Only Scan using idx_stock_sala_vino on stock_sala  (cost=0.29..4.71 rows=24 width=4) (actual time=0.030..0.031 rows=24.00 loops=1)
                 Index Cond: (codigo_vino = v.codigo)
                 Heap Fetches: 0
                 Index Searches: 1
                 Buffers: shared hit=3
 Planning:
   Buffers: shared hit=546
 Planning Time: 1.666 ms
 Execution Time: 0.522 ms
(74 filas)
```

### S10 — kg/ha por parcela y campaña — antes

```text
                                                              QUERY PLAN                                                              
--------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=18346.34..18347.09 rows=300 width=42) (actual time=49.269..49.296 rows=624.00 loops=1)
   Sort Key: r.id_finca, r."campaña", r.numero_parcela
   Sort Method: quicksort  Memory: 49kB
   Buffers: shared hit=18
   CTE rendimiento
     ->  HashAggregate  (cost=52.00..67.75 rows=900 width=48) (actual time=0.900..1.147 rows=900.00 loops=1)
           Group Key: p.id_finca, l.numero_parcela, l."campaña", p.superficie
           Batches: 1  Memory Usage: 609kB
           Buffers: shared hit=12
           ->  Hash Join  (cost=19.00..40.75 rows=900 width=24) (actual time=0.148..0.371 rows=900.00 loops=1)
                 Hash Cond: ((l.id_finca = p.id_finca) AND (l.numero_parcela = p.numero_parcela))
                 Buffers: shared hit=12
                 ->  Seq Scan on lote l  (cost=0.00..17.00 rows=900 width=18) (actual time=0.008..0.062 rows=900.00 loops=1)
                       Buffers: shared hit=8
                 ->  Hash  (cost=10.00..10.00 rows=600 width=14) (actual time=0.123..0.124 rows=600.00 loops=1)
                       Buckets: 1024  Batches: 1  Memory Usage: 37kB
                       Buffers: shared hit=4
                       ->  Seq Scan on parcela p  (cost=0.00..10.00 rows=600 width=14) (actual time=0.007..0.043 rows=600.00 loops=1)
                             Buffers: shared hit=4
   ->  CTE Scan on rendimiento r  (cost=0.00..18266.25 rows=300 width=42) (actual time=1.337..48.849 rows=624.00 loops=1)
         Filter: (kg_ha < (SubPlan 2))
         Rows Removed by Filter: 276
         Storage: Memory  Maximum Storage: 66kB
         Buffers: shared hit=12
         SubPlan 2
           ->  Aggregate  (cost=20.26..20.27 rows=1 width=32) (actual time=0.053..0.053 rows=1.00 loops=900)
                 ->  CTE Scan on rendimiento r2  (cost=0.00..20.25 rows=4 width=32) (actual time=0.002..0.049 rows=30.85 loops=900)
                       Filter: (id_finca = r.id_finca)
                       Rows Removed by Filter: 869
                       Storage: Memory  Maximum Storage: 66kB
 Planning:
   Buffers: shared hit=176
 Planning Time: 0.684 ms
 Execution Time: 49.548 ms
(34 filas)
```

### S10 — kg/ha por parcela y campaña — despues

```text
                                                              QUERY PLAN                                                              
--------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=18346.34..18347.09 rows=300 width=42) (actual time=37.920..37.944 rows=624.00 loops=1)
   Sort Key: r.id_finca, r."campaña", r.numero_parcela
   Sort Method: quicksort  Memory: 49kB
   Buffers: shared hit=18
   CTE rendimiento
     ->  HashAggregate  (cost=52.00..67.75 rows=900 width=48) (actual time=0.834..1.077 rows=900.00 loops=1)
           Group Key: p.id_finca, l.numero_parcela, l."campaña", p.superficie
           Batches: 1  Memory Usage: 609kB
           Buffers: shared hit=12
           ->  Hash Join  (cost=19.00..40.75 rows=900 width=24) (actual time=0.143..0.351 rows=900.00 loops=1)
                 Hash Cond: ((l.id_finca = p.id_finca) AND (l.numero_parcela = p.numero_parcela))
                 Buffers: shared hit=12
                 ->  Seq Scan on lote l  (cost=0.00..17.00 rows=900 width=18) (actual time=0.007..0.042 rows=900.00 loops=1)
                       Buffers: shared hit=8
                 ->  Hash  (cost=10.00..10.00 rows=600 width=14) (actual time=0.120..0.121 rows=600.00 loops=1)
                       Buckets: 1024  Batches: 1  Memory Usage: 37kB
                       Buffers: shared hit=4
                       ->  Seq Scan on parcela p  (cost=0.00..10.00 rows=600 width=14) (actual time=0.006..0.040 rows=600.00 loops=1)
                             Buffers: shared hit=4
   ->  CTE Scan on rendimiento r  (cost=0.00..18266.25 rows=300 width=42) (actual time=1.269..37.694 rows=624.00 loops=1)
         Filter: (kg_ha < (SubPlan 2))
         Rows Removed by Filter: 276
         Storage: Memory  Maximum Storage: 66kB
         Buffers: shared hit=12
         SubPlan 2
           ->  Aggregate  (cost=20.26..20.27 rows=1 width=32) (actual time=0.041..0.041 rows=1.00 loops=900)
                 ->  CTE Scan on rendimiento r2  (cost=0.00..20.25 rows=4 width=32) (actual time=0.001..0.038 rows=30.85 loops=900)
                       Filter: (id_finca = r.id_finca)
                       Rows Removed by Filter: 869
                       Storage: Memory  Maximum Storage: 66kB
 Planning:
   Buffers: shared hit=176
 Planning Time: 0.758 ms
 Execution Time: 38.161 ms
(34 filas)
```

### S11 — Ranking de vinos por sala — antes

```text
                                                                                        QUERY PLAN                                                                                         
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Incremental Sort  (cost=18074.69..18970.68 rows=12000 width=24) (actual time=168.896..181.604 rows=11999.00 loops=1)
   Sort Key: s.id, (rank() OVER w1)
   Presorted Key: s.id
   Full-sort Groups: 24  Sort Method: quicksort  Average Memory: 27kB  Peak Memory: 27kB
   Pre-sorted Groups: 24  Sort Method: quicksort  Average Memory: 44kB  Peak Memory: 44kB
   Buffers: shared hit=5457
   ->  WindowAgg  (cost=18042.27..18282.25 rows=12000 width=24) (actual time=168.435..179.102 rows=11999.00 loops=1)
         Window: w1 AS (PARTITION BY s.id ORDER BY (sum(rc.cantidad)) ROWS UNBOUNDED PRECEDING)
         Storage: Memory  Maximum Storage: 17kB
         Buffers: shared hit=5451
         ->  Sort  (cost=18042.25..18072.25 rows=12000 width=16) (actual time=168.413..173.322 rows=11999.00 loops=1)
               Sort Key: s.id, (sum(rc.cantidad)) DESC
               Sort Method: quicksort  Memory: 759kB
               Buffers: shared hit=5451
               ->  Finalize HashAggregate  (cost=17109.21..17229.21 rows=12000 width=16) (actual time=160.839..166.403 rows=11999.00 loops=1)
                     Group Key: s.id, rc.codigo_vino
                     Batches: 1  Memory Usage: 793kB
                     Buffers: shared hit=5451
                     ->  Gather  (cost=13893.21..16893.21 rows=28800 width=16) (actual time=141.096..152.209 rows=35988.00 loops=1)
                           Workers Planned: 2
                           Workers Launched: 2
                           Buffers: shared hit=5451
                           ->  Partial HashAggregate  (cost=12893.21..13013.21 rows=12000 width=16) (actual time=137.462..140.174 rows=11996.00 loops=3)
                                 Group Key: s.id, rc.codigo_vino
                                 Batches: 1  Memory Usage: 793kB
                                 Buffers: shared hit=5451
                                 Worker 0:  Batches: 1  Memory Usage: 793kB
                                 Worker 1:  Batches: 1  Memory Usage: 793kB
                                 ->  Hash Join  (cost=3338.83..11129.68 rows=235137 width=12) (actual time=16.949..96.899 rows=188109.33 loops=3)
                                       Hash Cond: (co.id_sala_venta = s.id)
                                       Buffers: shared hit=5451
                                       ->  Parallel Hash Join  (cost=3337.29..10401.91 rows=235137 width=12) (actual time=16.912..71.002 rows=188109.33 loops=3)
                                             Hash Cond: (rc.numero_comprobante = co.numero)
                                             Buffers: shared hit=5448
                                             ->  Parallel Seq Scan on renglon_comprobante rc  (cost=0.00..6447.37 rows=235137 width=12) (actual time=0.019..11.310 rows=188109.33 loops=3)
                                                   Buffers: shared hit=4096
                                             ->  Parallel Hash  (cost=2234.35..2234.35 rows=88235 width=8) (actual time=15.867..15.869 rows=50000.00 loops=3)
                                                   Buckets: 262144  Batches: 1  Memory Usage: 8000kB
                                                   Buffers: shared hit=1352
                                                   ->  Parallel Seq Scan on comprobante co  (cost=0.00..2234.35 rows=88235 width=8) (actual time=0.015..4.383 rows=50000.00 loops=3)
                                                         Buffers: shared hit=1352
                                       ->  Hash  (cost=1.24..1.24 rows=24 width=4) (actual time=0.019..0.020 rows=24.00 loops=3)
                                             Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                             Buffers: shared hit=3
                                             ->  Seq Scan on sala_venta s  (cost=0.00..1.24 rows=24 width=4) (actual time=0.011..0.013 rows=24.00 loops=3)
                                                   Buffers: shared hit=3
 Planning:
   Buffers: shared hit=188
 Planning Time: 0.803 ms
 Execution Time: 182.994 ms
(50 filas)
```

### S11 — Ranking de vinos por sala — despues

```text
                                                                                        QUERY PLAN                                                                                         
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Incremental Sort  (cost=18039.69..18935.68 rows=12000 width=24) (actual time=162.994..171.942 rows=11999.00 loops=1)
   Sort Key: s.id, (rank() OVER w1)
   Presorted Key: s.id
   Full-sort Groups: 24  Sort Method: quicksort  Average Memory: 27kB  Peak Memory: 27kB
   Pre-sorted Groups: 24  Sort Method: quicksort  Average Memory: 44kB  Peak Memory: 44kB
   Buffers: shared hit=5422
   ->  WindowAgg  (cost=18007.27..18247.25 rows=12000 width=24) (actual time=162.712..170.204 rows=11999.00 loops=1)
         Window: w1 AS (PARTITION BY s.id ORDER BY (sum(rc.cantidad)) ROWS UNBOUNDED PRECEDING)
         Storage: Memory  Maximum Storage: 17kB
         Buffers: shared hit=5416
         ->  Sort  (cost=18007.25..18037.25 rows=12000 width=16) (actual time=162.704..166.617 rows=11999.00 loops=1)
               Sort Key: s.id, (sum(rc.cantidad)) DESC
               Sort Method: quicksort  Memory: 759kB
               Buffers: shared hit=5416
               ->  Finalize HashAggregate  (cost=17074.21..17194.21 rows=12000 width=16) (actual time=157.809..162.207 rows=11999.00 loops=1)
                     Group Key: s.id, rc.codigo_vino
                     Batches: 1  Memory Usage: 793kB
                     Buffers: shared hit=5416
                     ->  Gather  (cost=13858.21..16858.21 rows=28800 width=16) (actual time=143.515..152.963 rows=35987.00 loops=1)
                           Workers Planned: 2
                           Workers Launched: 2
                           Buffers: shared hit=5416
                           ->  Partial HashAggregate  (cost=12858.21..12978.21 rows=12000 width=16) (actual time=139.883..141.484 rows=11995.67 loops=3)
                                 Group Key: s.id, rc.codigo_vino
                                 Batches: 1  Memory Usage: 793kB
                                 Buffers: shared hit=5416
                                 Worker 0:  Batches: 1  Memory Usage: 793kB
                                 Worker 1:  Batches: 1  Memory Usage: 793kB
                                 ->  Hash Join  (cost=3325.83..11094.68 rows=235137 width=12) (actual time=16.313..98.970 rows=188109.33 loops=3)
                                       Hash Cond: (co.id_sala_venta = s.id)
                                       Buffers: shared hit=5416
                                       ->  Parallel Hash Join  (cost=3324.29..10366.91 rows=235137 width=12) (actual time=16.272..71.242 rows=188109.33 loops=3)
                                             Hash Cond: (rc.numero_comprobante = co.numero)
                                             Buffers: shared hit=5413
                                             ->  Parallel Seq Scan on renglon_comprobante rc  (cost=0.00..6425.37 rows=235137 width=12) (actual time=0.014..11.630 rows=188109.33 loops=3)
                                                   Buffers: shared hit=4074
                                             ->  Parallel Hash  (cost=2221.35..2221.35 rows=88235 width=8) (actual time=15.292..15.293 rows=50000.00 loops=3)
                                                   Buckets: 262144  Batches: 1  Memory Usage: 7968kB
                                                   Buffers: shared hit=1339
                                                   ->  Parallel Seq Scan on comprobante co  (cost=0.00..2221.35 rows=88235 width=8) (actual time=0.012..4.233 rows=50000.00 loops=3)
                                                         Buffers: shared hit=1339
                                       ->  Hash  (cost=1.24..1.24 rows=24 width=4) (actual time=0.021..0.022 rows=24.00 loops=3)
                                             Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                             Buffers: shared hit=3
                                             ->  Seq Scan on sala_venta s  (cost=0.00..1.24 rows=24 width=4) (actual time=0.012..0.014 rows=24.00 loops=3)
                                                   Buffers: shared hit=3
 Planning:
   Buffers: shared hit=246
 Planning Time: 0.965 ms
 Execution Time: 173.256 ms
(50 filas)
```

### S12 — Clientes que nunca compraron tinto — antes

```text
                                                                       QUERY PLAN                                                                        
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=22818.13..22821.96 rows=1533 width=19) (actual time=216.121..216.135 rows=232.00 loops=1)
   Sort Key: c.id
   Sort Method: quicksort  Memory: 33kB
   Buffers: shared hit=5688
   ->  Hash Right Anti Join  (cost=5446.59..22737.02 rows=1533 width=19) (actual time=215.723..216.053 rows=232.00 loops=1)
         Hash Cond: (co.id_cliente = c.id)
         Buffers: shared hit=5685
         ->  Hash Join  (cost=4730.59..16969.89 rows=391644 width=4) (actual time=37.919..171.194 rows=386850.00 loops=1)
               Hash Cond: (rc.numero_comprobante = co.numero)
               Buffers: shared hit=5419
               ->  Hash Join  (cost=16.59..11227.79 rows=391644 width=4) (actual time=0.114..74.327 rows=386850.00 loops=1)
                     Hash Cond: (rc.codigo_vino = v.codigo)
                     Buffers: shared hit=4080
                     ->  Seq Scan on renglon_comprobante rc  (cost=0.00..9717.28 rows=564328 width=8) (actual time=0.007..20.360 rows=564328.00 loops=1)
                           Buffers: shared hit=4074
                     ->  Hash  (cost=12.25..12.25 rows=347 width=4) (actual time=0.082..0.083 rows=347.00 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 21kB
                           Buffers: shared hit=6
                           ->  Seq Scan on vino v  (cost=0.00..12.25 rows=347 width=4) (actual time=0.011..0.045 rows=347.00 loops=1)
                                 Filter: (tipo = 'tinto'::tipo_vino)
                                 Rows Removed by Filter: 153
                                 Buffers: shared hit=6
               ->  Hash  (cost=2839.00..2839.00 rows=150000 width=8) (actual time=36.456..36.456 rows=150000.00 loops=1)
                     Buckets: 262144  Batches: 1  Memory Usage: 7908kB
                     Buffers: shared hit=1339
                     ->  Seq Scan on comprobante co  (cost=0.00..2839.00 rows=150000 width=8) (actual time=0.016..10.772 rows=150000.00 loops=1)
                           Buffers: shared hit=1339
         ->  Hash  (cost=466.00..466.00 rows=20000 width=19) (actual time=4.341..4.344 rows=20000.00 loops=1)
               Buckets: 32768  Batches: 1  Memory Usage: 1215kB
               Buffers: shared hit=266
               ->  Seq Scan on cliente c  (cost=0.00..466.00 rows=20000 width=19) (actual time=0.015..1.942 rows=20000.00 loops=1)
                     Filter: estado_activo
                     Buffers: shared hit=266
 Planning:
   Buffers: shared hit=415
 Planning Time: 1.395 ms
 Execution Time: 216.573 ms
(37 filas)
```

### S12 — Clientes que nunca compraron tinto — despues

```text
                                                                       QUERY PLAN                                                                        
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=22829.10..22833.54 rows=1775 width=19) (actual time=249.007..249.021 rows=232.00 loops=1)
   Sort Key: c.id
   Sort Method: quicksort  Memory: 33kB
   Buffers: shared hit=5737
   ->  Hash Right Anti Join  (cost=5473.59..22733.31 rows=1775 width=19) (actual time=248.574..248.939 rows=232.00 loops=1)
         Hash Cond: (co.id_cliente = c.id)
         Buffers: shared hit=5734
         ->  Hash Join  (cost=4743.59..17004.89 rows=391644 width=4) (actual time=54.486..197.588 rows=386850.00 loops=1)
               Hash Cond: (rc.numero_comprobante = co.numero)
               Buffers: shared hit=5454
               ->  Hash Join  (cost=16.59..11249.79 rows=391644 width=4) (actual time=0.176..78.478 rows=386850.00 loops=1)
                     Hash Cond: (rc.codigo_vino = v.codigo)
                     Buffers: shared hit=4102
                     ->  Seq Scan on renglon_comprobante rc  (cost=0.00..9739.28 rows=564328 width=8) (actual time=0.019..24.493 rows=564328.00 loops=1)
                           Buffers: shared hit=4096
                     ->  Hash  (cost=12.25..12.25 rows=347 width=4) (actual time=0.112..0.113 rows=347.00 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 21kB
                           Buffers: shared hit=6
                           ->  Seq Scan on vino v  (cost=0.00..12.25 rows=347 width=4) (actual time=0.012..0.060 rows=347.00 loops=1)
                                 Filter: (tipo = 'tinto'::tipo_vino)
                                 Rows Removed by Filter: 153
                                 Buffers: shared hit=6
               ->  Hash  (cost=2852.00..2852.00 rows=150000 width=8) (actual time=52.314..52.314 rows=150000.00 loops=1)
                     Buckets: 262144  Batches: 1  Memory Usage: 7908kB
                     Buffers: shared hit=1352
                     ->  Seq Scan on comprobante co  (cost=0.00..2852.00 rows=150000 width=8) (actual time=0.022..16.529 rows=150000.00 loops=1)
                           Buffers: shared hit=1352
         ->  Hash  (cost=480.00..480.00 rows=20000 width=19) (actual time=4.847..4.851 rows=20000.00 loops=1)
               Buckets: 32768  Batches: 1  Memory Usage: 1215kB
               Buffers: shared hit=280
               ->  Seq Scan on cliente c  (cost=0.00..480.00 rows=20000 width=19) (actual time=0.015..2.020 rows=20000.00 loops=1)
                     Filter: estado_activo
                     Buffers: shared hit=280
 Planning:
   Buffers: shared hit=392
 Planning Time: 1.906 ms
 Execution Time: 249.483 ms
(37 filas)
```

## Anexo B — Experimentos descartados

### S1 con `idx_renglon_comprobante_vino_cantidad` (planificador libre)

```text
                                                                       QUERY PLAN                                                                        
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=17363.68..17363.71 rows=10 width=31) (actual time=170.401..170.405 rows=10.00 loops=1)
   Buffers: shared hit=4105
   ->  Sort  (cost=17363.68..17512.43 rows=59500 width=31) (actual time=170.399..170.402 rows=10.00 loops=1)
         Sort Key: (sum(rc.cantidad)) DESC
         Sort Method: top-N heapsort  Memory: 26kB
         Buffers: shared hit=4105
         ->  HashAggregate  (cost=15482.91..16077.91 rows=59500 width=31) (actual time=170.153..170.273 rows=500.00 loops=1)
               Group Key: rc.codigo_vino, v.nombre
               Batches: 1  Memory Usage: 1081kB
               Buffers: shared hit=4102
               ->  Hash Join  (cost=17.25..11250.45 rows=564328 width=27) (actual time=0.183..94.846 rows=564328.00 loops=1)
                     Hash Cond: (rc.codigo_vino = v.codigo)
                     Buffers: shared hit=4102
                     ->  Seq Scan on renglon_comprobante rc  (cost=0.00..9739.28 rows=564328 width=8) (actual time=0.036..27.103 rows=564328.00 loops=1)
                           Buffers: shared hit=4096
                     ->  Hash  (cost=11.00..11.00 rows=500 width=23) (actual time=0.108..0.109 rows=500.00 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 37kB
                           Buffers: shared hit=6
                           ->  Seq Scan on vino v  (cost=0.00..11.00 rows=500 width=23) (actual time=0.011..0.039 rows=500.00 loops=1)
                                 Buffers: shared hit=6
 Planning:
   Buffers: shared hit=227
 Planning Time: 0.838 ms
 Execution Time: 171.439 ms
(24 filas)
```

### S1 forzado con `enable_seqscan = off`

```text
                                                                                                 QUERY PLAN                                                                                                  
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=22407.52..22407.55 rows=10 width=31) (actual time=183.978..183.982 rows=10.00 loops=1)
   Buffers: shared hit=17 read=1540 written=429
   ->  Sort  (cost=22407.52..22556.27 rows=59500 width=31) (actual time=183.976..183.979 rows=10.00 loops=1)
         Sort Key: (sum(rc.cantidad)) DESC
         Sort Method: top-N heapsort  Memory: 26kB
         Buffers: shared hit=17 read=1540 written=429
         ->  HashAggregate  (cost=20526.75..21121.75 rows=59500 width=31) (actual time=183.743..183.887 rows=500.00 loops=1)
               Group Key: rc.codigo_vino, v.nombre
               Batches: 1  Memory Usage: 1081kB
               Buffers: shared hit=14 read=1540 written=429
               ->  Hash Join  (cost=39.45..16294.29 rows=564328 width=27) (actual time=0.230..114.308 rows=564328.00 loops=1)
                     Hash Cond: (rc.codigo_vino = v.codigo)
                     Buffers: shared hit=14 read=1540 written=429
                     ->  Index Only Scan using idx_renglon_comprobante_vino_cantidad on renglon_comprobante rc  (cost=0.42..14761.34 rows=564328 width=8) (actual time=0.028..53.725 rows=564328.00 loops=1)
                           Heap Fetches: 0
                           Index Searches: 1
                           Buffers: shared hit=5 read=1540 written=429
                     ->  Hash  (cost=32.77..32.77 rows=500 width=23) (actual time=0.172..0.173 rows=500.00 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 37kB
                           Buffers: shared hit=9
                           ->  Index Scan using vino_pkey on vino v  (cost=0.27..32.77 rows=500 width=23) (actual time=0.021..0.088 rows=500.00 loops=1)
                                 Index Searches: 1
                                 Buffers: shared hit=9
 Planning:
   Buffers: shared hit=227
 Planning Time: 1.058 ms
 Execution Time: 185.201 ms
(27 filas)
```

### S8 con BRIN sobre `comprobante.fecha` (sin el b-tree de cobertura)

```text
                                                                           QUERY PLAN                                                                           
----------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=2078.34..2078.40 rows=24 width=52) (actual time=10.800..10.802 rows=24.00 loops=1)
   Sort Key: (sum(co.total)) DESC
   Sort Method: quicksort  Memory: 26kB
   Buffers: shared hit=297
   ->  HashAggregate  (cost=2077.49..2077.79 rows=24 width=52) (actual time=10.740..10.746 rows=24.00 loops=1)
         Group Key: s.id
         Batches: 1  Memory Usage: 32kB
         Buffers: shared hit=294
         ->  Hash Join  (cost=20.31..1943.47 rows=26804 width=28) (actual time=0.270..7.244 rows=26640.00 loops=1)
               Hash Cond: (co.id_sala_venta = s.id)
               Buffers: shared hit=294
               ->  Bitmap Heap Scan on comprobante co  (cost=18.77..1859.14 rows=26804 width=12) (actual time=0.233..3.773 rows=26640.00 loops=1)
                     Recheck Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                     Rows Removed by Index Recheck: 4952
                     Heap Blocks: lossy=288
                     Buffers: shared hit=293
                     ->  Bitmap Index Scan on idx_brin_comprobante_fecha  (cost=0.00..12.07 rows=27907 width=0) (actual time=0.054..0.054 rows=2880.00 loops=1)
                           Index Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                           Index Searches: 1
                           Buffers: shared hit=5
               ->  Hash  (cost=1.24..1.24 rows=24 width=20) (actual time=0.015..0.015 rows=24.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 10kB
                     Buffers: shared hit=1
                     ->  Seq Scan on sala_venta s  (cost=0.00..1.24 rows=24 width=20) (actual time=0.007..0.008 rows=24.00 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=228
 Planning Time: 0.816 ms
 Execution Time: 10.886 ms
(29 filas)
```

### S11 forzado con `enable_seqscan = off`

```text
                                                                                                         QUERY PLAN                                                                                                          
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Incremental Sort  (cost=34899.12..35795.11 rows=12000 width=24) (actual time=162.466..171.337 rows=11999.00 loops=1)
   Sort Key: s.id, (rank() OVER w1)
   Presorted Key: s.id
   Full-sort Groups: 24  Sort Method: quicksort  Average Memory: 27kB  Peak Memory: 27kB
   Pre-sorted Groups: 24  Sort Method: quicksort  Average Memory: 44kB  Peak Memory: 44kB
   Buffers: shared hit=8915 read=386 written=70
   ->  WindowAgg  (cost=34866.70..35106.68 rows=12000 width=24) (actual time=162.198..169.645 rows=11999.00 loops=1)
         Window: w1 AS (PARTITION BY s.id ORDER BY (sum(rc.cantidad)) ROWS UNBOUNDED PRECEDING)
         Storage: Memory  Maximum Storage: 17kB
         Buffers: shared hit=8909 read=386 written=70
         ->  Sort  (cost=34866.68..34896.68 rows=12000 width=16) (actual time=162.187..166.133 rows=11999.00 loops=1)
               Sort Key: s.id, (sum(rc.cantidad)) DESC
               Sort Method: quicksort  Memory: 759kB
               Buffers: shared hit=8909 read=386 written=70
               ->  Finalize HashAggregate  (cost=33933.64..34053.64 rows=12000 width=16) (actual time=157.372..161.926 rows=11999.00 loops=1)
                     Group Key: s.id, rc.codigo_vino
                     Batches: 1  Memory Usage: 793kB
                     Buffers: shared hit=8909 read=386 written=70
                     ->  Gather  (cost=30717.64..33717.64 rows=28800 width=16) (actual time=144.082..153.538 rows=35986.00 loops=1)
                           Workers Planned: 2
                           Workers Launched: 2
                           Buffers: shared hit=8909 read=386 written=70
                           ->  Partial HashAggregate  (cost=29717.64..29837.64 rows=12000 width=16) (actual time=140.581..142.095 rows=11995.33 loops=3)
                                 Group Key: s.id, rc.codigo_vino
                                 Batches: 1  Memory Usage: 793kB
                                 Buffers: shared hit=8909 read=386 written=70
                                 Worker 0:  Batches: 1  Memory Usage: 793kB
                                 Worker 1:  Batches: 1  Memory Usage: 793kB
                                 ->  Hash Join  (cost=5759.93..27954.11 rows=235137 width=12) (actual time=20.331..107.693 rows=188109.33 loops=3)
                                       Hash Cond: (co.id_sala_venta = s.id)
                                       Buffers: shared hit=8909 read=386 written=70
                                       ->  Parallel Hash Join  (cost=5747.14..27215.09 rows=235137 width=12) (actual time=20.274..83.628 rows=188109.33 loops=3)
                                             Hash Cond: (rc.numero_comprobante = co.numero)
                                             Buffers: shared hit=8901 read=386 written=70
                                             ->  Parallel Index Scan using renglon_comprobante_pkey on renglon_comprobante rc  (cost=0.42..20851.12 rows=235137 width=12) (actual time=0.087..26.634 rows=188109.33 loops=3)
                                                   Index Searches: 1
                                                   Buffers: shared hit=6761 read=386 written=70
                                             ->  Parallel Hash  (cost=4643.77..4643.77 rows=88235 width=8) (actual time=19.254..19.256 rows=50000.00 loops=3)
                                                   Buckets: 262144  Batches: 1  Memory Usage: 7968kB
                                                   Buffers: shared hit=2140
                                                   ->  Parallel Index Scan using comprobante_pkey on comprobante co  (cost=0.42..4643.77 rows=88235 width=8) (actual time=0.025..8.237 rows=50000.00 loops=3)
                                                         Index Searches: 1
                                                         Buffers: shared hit=2140
                                       ->  Hash  (cost=12.50..12.50 rows=24 width=4) (actual time=0.036..0.037 rows=24.00 loops=3)
                                             Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                             Buffers: shared hit=8
                                             ->  Index Only Scan using sala_venta_pkey on sala_venta s  (cost=0.14..12.50 rows=24 width=4) (actual time=0.026..0.029 rows=24.00 loops=3)
                                                   Heap Fetches: 72
                                                   Index Searches: 3
                                                   Buffers: shared hit=8
 Planning:
   Buffers: shared hit=255 read=4
 Planning Time: 1.026 ms
 Execution Time: 172.629 ms
(54 filas)
```

### S12 con `comprobante (id_cliente) INCLUDE (numero)`

```text
                                                                       QUERY PLAN                                                                        
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=22819.56..22823.37 rows=1524 width=19) (actual time=208.225..208.237 rows=232.00 loops=1)
   Sort Key: c.id
   Sort Method: quicksort  Memory: 33kB
   Buffers: shared hit=5688
   ->  Hash Right Anti Join  (cost=5446.59..22738.99 rows=1524 width=19) (actual time=207.798..208.149 rows=232.00 loops=1)
         Hash Cond: (co.id_cliente = c.id)
         Buffers: shared hit=5685
         ->  Hash Join  (cost=4730.59..16969.89 rows=391644 width=4) (actual time=30.725..163.938 rows=386850.00 loops=1)
               Hash Cond: (rc.numero_comprobante = co.numero)
               Buffers: shared hit=5419
               ->  Hash Join  (cost=16.59..11227.79 rows=391644 width=4) (actual time=0.126..75.181 rows=386850.00 loops=1)
                     Hash Cond: (rc.codigo_vino = v.codigo)
                     Buffers: shared hit=4080
                     ->  Seq Scan on renglon_comprobante rc  (cost=0.00..9717.28 rows=564328 width=8) (actual time=0.008..20.174 rows=564328.00 loops=1)
                           Buffers: shared hit=4074
                     ->  Hash  (cost=12.25..12.25 rows=347 width=4) (actual time=0.081..0.082 rows=347.00 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 21kB
                           Buffers: shared hit=6
                           ->  Seq Scan on vino v  (cost=0.00..12.25 rows=347 width=4) (actual time=0.010..0.043 rows=347.00 loops=1)
                                 Filter: (tipo = 'tinto'::tipo_vino)
                                 Rows Removed by Filter: 153
                                 Buffers: shared hit=6
               ->  Hash  (cost=2839.00..2839.00 rows=150000 width=8) (actual time=29.240..29.240 rows=150000.00 loops=1)
                     Buckets: 262144  Batches: 1  Memory Usage: 7908kB
                     Buffers: shared hit=1339
                     ->  Seq Scan on comprobante co  (cost=0.00..2839.00 rows=150000 width=8) (actual time=0.017..10.781 rows=150000.00 loops=1)
                           Buffers: shared hit=1339
         ->  Hash  (cost=466.00..466.00 rows=20000 width=19) (actual time=4.375..4.376 rows=20000.00 loops=1)
               Buckets: 32768  Batches: 1  Memory Usage: 1215kB
               Buffers: shared hit=266
               ->  Seq Scan on cliente c  (cost=0.00..466.00 rows=20000 width=19) (actual time=0.010..1.914 rows=20000.00 loops=1)
                     Filter: estado_activo
                     Buffers: shared hit=266
 Planning:
   Buffers: shared hit=439
 Planning Time: 1.494 ms
 Execution Time: 208.708 ms
(37 filas)
```

