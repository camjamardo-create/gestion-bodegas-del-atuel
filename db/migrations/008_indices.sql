-- 008_indices.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 4: indices y rendimiento
--
-- Criterio general: cada indice responde a un plan medido con
-- EXPLAIN (ANALYZE, BUFFERS) sobre la base cargada por la Etapa 3
-- (150.000 comprobantes, 564.328 renglones de comprobante).
-- Los planes antes/despues y la tabla comparativa estan en
-- docs/informe_etapa4_indices.md y db/benchmarks/etapa4/planes/.

SET client_encoding = 'UTF8';
BEGIN;

--- ===============================================================================
--- 1. INDICE COMPUESTO + INCLUDE: comprobante por sala y fecha
-- Consulta: S3 (clientes por tipo que compraron en una sala en la ultima semana).
-- El filtro es igualdad por id_sala_venta y rango por fecha, en ese orden:
-- la columna de igualdad va primero para que el rango quede contiguo en el
-- arbol y se pueda recorrer como un unico tramo.
-- INCLUDE (id_cliente) permite resolver la consulta con Index Only Scan,
-- sin visitar el heap de comprobante (150.000 filas).
CREATE INDEX idx_comprobante_sala_fecha
    ON comprobante (id_sala_venta, fecha)
    INCLUDE (id_cliente);

--- ===============================================================================
--- 2. INDICE DE COBERTURA: comprobante por fecha (S8)
-- Consulta: S8 (monto total de ventas por sala en el ultimo trimestre).
-- Aqui no hay igualdad: el filtro es un rango de fecha que devuelve el 18 %
-- de la tabla. Se pone fecha primero (columna de rango) para que el tramo del
-- arbol sea contiguo, e id_sala_venta segundo para agrupar sin volver al heap.
-- INCLUDE (total) evita el acceso al heap para sumar el monto: el Index Only
-- Scan lee 26.640 filas en 137 buffers, contra 1.364 buffers del recorrido
-- secuencial paralelo sobre las 150.000 filas.
CREATE INDEX idx_comprobante_fecha_sala_total
    ON comprobante (fecha, id_sala_venta)
    INCLUDE (total);

--- ===============================================================================
--- 3. CLAVE FORANEA SIN INDICE: stock_sala.codigo_vino
-- PostgreSQL no indexa automaticamente las claves foraneas. La PK de
-- stock_sala es (id_sala, codigo_vino), de modo que codigo_vino solo queda
-- como segunda columna y no sirve para buscar por vino: el planificador de
-- PostgreSQL 18 solo puede resolverlo con skip scan (SubPlan 4 de S9 hacia
-- 25 busquedas en el arbol y 77 buffers para devolver 24 filas).
-- Consulta: S9 (ficha de un vino, stock total en salas).
-- INCLUDE (cantidad) permite Index Only Scan de una sola busqueda y cubre la
-- suma de stock sin visitar el heap.
-- Ademas, sin este indice cada DELETE o UPDATE de vino obliga a verificar la
-- FK con un recorrido secuencial de las 12.000 filas de stock_sala.
CREATE INDEX idx_stock_sala_vino
    ON stock_sala (codigo_vino)
    INCLUDE (cantidad);

--- ===============================================================================
--- 4. INDICE PARCIAL: transferencias pendientes
-- Consulta: S5 (salas con menor cantidad de transferencias pendientes).
-- Solo interesan las filas con estado distinto de 'procesado'; el resto
-- (la mayoria de las 1.300 transferencias) no se consulta nunca por esta via.
-- El WHERE deja en el indice unicamente las pendientes, con lo que el
-- indice pesa mucho menos y se mantiene mas barato en cada UPDATE de estado.
CREATE INDEX idx_transferencia_pendientes
    ON transferencia (id_sala_venta, fecha_confeccion)
    WHERE estado <> 'procesado';

--- ===============================================================================
--- 5. INDICE DE EXPRESION: busqueda de vinos por nombre
-- Uso: catalogo de vinos (Etapa 6), filtros por nombre sin distinguir
-- mayusculas/minusculas. Un indice comun sobre nombre no sirve para
-- WHERE lower(nombre) = ... porque el planificador compara la expresion.
CREATE INDEX idx_vino_nombre_lower
    ON vino (lower(nombre));

COMMIT;
