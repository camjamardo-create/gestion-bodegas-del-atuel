-- ============================================================================
-- consultas/select.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 5: consultas de la seccion 8.4 (S1 a S8) y 8.5 (S9 a S12)
--
-- Base: carga de la Etapa 3 (150.000 comprobantes, 564.328 renglones,
-- 500 vinos, 24 salas, 20.000 clientes). Los valores concretos (sala, vino,
-- bodega, localidad) se indican en cada consulta y se pueden cambiar.
--
-- Las consultas se resuelven en SQL de PostgreSQL. Las fechas relativas
-- ("ultima semana", "ultimo trimestre", "ultimo mes") se calculan con
-- CURRENT_DATE, no con fechas fijas.
-- ============================================================================

SET client_encoding = 'UTF8';


-- ============================================================================
-- S1. Ranking de los 10 vinos con mayor cantidad de botellas vendidas en
--     toda la red de salas.
-- Estrategia: agregacion con SUM sobre la tabla de mayor volumen
--   (renglon_comprobante), GROUP BY por vino y join por PK con vino para
--   obtener el nombre. ORDER BY ... DESC + LIMIT 10 para el top.
-- ============================================================================
SELECT rc.codigo_vino,
       v.nombre,
       SUM(rc.cantidad) AS botellas_vendidas
FROM renglon_comprobante rc
JOIN vino v ON v.codigo = rc.codigo_vino
GROUP BY rc.codigo_vino, v.nombre
ORDER BY botellas_vendidas DESC
LIMIT 10;


-- ============================================================================
-- S2. Codigos y nombres de los vinos que se vendieron en todas las salas
--     (division relacional).
-- Estrategia: se agrupa por vino y se comparan las salas distintas en las
--   que aparecio contra el total de salas. Es la version agregada de la
--   division: un vino pertenece al resultado si COUNT(DISTINCT sala) es
--   igual a la cardinalidad de sala_venta.
--   Equivalente con doble NOT EXISTS (mas costoso, 500 x 24 subconsultas):
--       WHERE NOT EXISTS (SELECT 1 FROM sala_venta s
--                         WHERE NOT EXISTS (... rc.codigo_vino = v.codigo ...))
-- ============================================================================
SELECT v.codigo,
       v.nombre
FROM vino v
JOIN (
    SELECT rc.codigo_vino
    FROM renglon_comprobante rc
    JOIN comprobante co ON co.numero = rc.numero_comprobante
    GROUP BY rc.codigo_vino
    HAVING COUNT(DISTINCT co.id_sala_venta) = (SELECT COUNT(*) FROM sala_venta)
) vendidos ON vendidos.codigo_vino = v.codigo
ORDER BY v.codigo;


-- ============================================================================
-- S3. Cantidad de clientes de cada tipo que compraron en una sala
--     determinada en la ultima semana.
-- Parametro: id_sala_venta = 4 (la sala con mas actividad en los ultimos 7
--   dias: 395 comprobantes). Cambiar el literal para otra sala.
-- Estrategia: filtro por igualdad (sala) y rango (fecha) sobre comprobante,
--   join con cliente por PK y COUNT(DISTINCT id) agrupado por tipo.
--   La consulta usa el indice idx_comprobante_sala_fecha (Etapa 4).
-- ============================================================================
SELECT c.tipo,
       COUNT(DISTINCT c.id) AS clientes
FROM comprobante co
JOIN cliente c ON c.id = co.id_cliente
WHERE co.id_sala_venta = 4
  AND co.fecha >= CURRENT_DATE - 7
GROUP BY c.tipo
ORDER BY clientes DESC;


-- ============================================================================
-- S4. Top 5 de las salas que solicitaron mayor cantidad de un vino
--     determinado mediante transferencias en los ultimos 15 dias.
-- Parametro: codigo_vino = 395 (unico vino transferido en los ultimos 15
--   dias en el dataset). Cambiar el literal para otro vino.
-- Estrategia: join transferencia -> renglon_transferencia (detalle) ->
--   sala_venta, filtro por vino y rango de fecha_confeccion, SUM(cantidad)
--   por sala y LIMIT 5.
-- Nota: en el dataset cargado hay una sola transferencia en los ultimos 15
--   dias, por eso el resultado tiene una fila; la consulta esta escrita para
--   cualquier volumen.
-- ============================================================================
SELECT t.id_sala_venta,
       s.calle,
       s.numero,
       SUM(rt.cantidad) AS botellas
FROM transferencia t
JOIN renglon_transferencia rt ON rt.numero_transferencia = t.numero
JOIN sala_venta s ON s.id = t.id_sala_venta
WHERE rt.codigo_vino = 395
  AND t.fecha_confeccion >= CURRENT_DATE - 15
GROUP BY t.id_sala_venta, s.calle, s.numero
ORDER BY botellas DESC, t.id_sala_venta
LIMIT 5;


-- ============================================================================
-- S5. Listado de las salas con menor cantidad de transferencias pendientes
--     (no procesadas).
-- Estrategia: LEFT JOIN para no perder salas sin pendientes, con la
--   condicion estado <> 'procesado' en el ON (no en el WHERE, para que el
--   LEFT JOIN no se convierta en INNER). COUNT(t.numero) y orden ascendente.
--   La condicion coincide con el indice parcial idx_transferencia_pendientes.
-- ============================================================================
SELECT s.id AS id_sala,
       s.calle,
       s.numero,
       COUNT(t.numero) AS pendientes
FROM sala_venta s
LEFT JOIN transferencia t
       ON t.id_sala_venta = s.id
      AND t.estado <> 'procesado'
GROUP BY s.id, s.calle, s.numero
ORDER BY pendientes ASC, s.id;


-- ============================================================================
-- S6. Para una sala determinada, los vinos sin stock en la sala pero con
--     stock en el deposito central.
-- Parametro: id_sala = 1. Cambiar el literal para otra sala.
-- Estrategia: partir de vino y stock_deposito (stock > 0) y hacer LEFT JOIN
--   con stock_sala restringido a la sala; se conservan las filas donde no
--   hay registro de stock en la sala o la cantidad es 0 (COALESCE).
-- ============================================================================
SELECT v.codigo,
       v.nombre,
       sd.cantidad AS stock_deposito
FROM vino v
JOIN stock_deposito sd ON sd.codigo_vino = v.codigo
LEFT JOIN stock_sala ss
       ON ss.codigo_vino = v.codigo
      AND ss.id_sala = 1
WHERE sd.cantidad > 0
  AND COALESCE(ss.cantidad, 0) = 0
ORDER BY v.codigo;


-- ============================================================================
-- S7. Empresa de transporte con mayor actividad en el ultimo mes.
-- Estrategia: join ingreso -> transportista, LEFT JOIN con renglon_ingreso
--   para medir botellas ademas de envios, filtro por fecha del ultimo mes,
--   GROUP BY por transportista y orden por cantidad de ingresos (actividad)
--   y botellas. LIMIT 1.
-- Se cuentan ingresos distintos porque el LEFT JOIN con renglones
--   multiplicaria las filas de la cabecera.
-- ============================================================================
SELECT t.codigo,
       t.razon_social,
       COUNT(DISTINCT i.codigo) AS ingresos,
       COALESCE(SUM(ri.cantidad), 0) AS botellas
FROM transportista t
JOIN ingreso i ON i.codigo_transportista = t.codigo
LEFT JOIN renglon_ingreso ri ON ri.codigo_ingreso = i.codigo
WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
GROUP BY t.codigo, t.razon_social
ORDER BY ingresos DESC, botellas DESC, t.codigo
LIMIT 1;


-- ============================================================================
-- S8. Monto total de ventas por sala en el ultimo trimestre, en orden
--     descendente.
-- Estrategia: filtro por rango de fecha sobre comprobante, join con
--   sala_venta por PK, SUM(total) agrupado por sala y orden descendente.
--   La consulta usa el indice de cobertura idx_comprobante_fecha_sala_total.
-- ============================================================================
SELECT s.id AS id_sala,
       s.calle,
       s.numero,
       SUM(co.total) AS monto_total
FROM comprobante co
JOIN sala_venta s ON s.id = co.id_sala_venta
WHERE co.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY s.id, s.calle, s.numero
ORDER BY monto_total DESC;


-- ============================================================================
-- S9. Ficha de un vino: cepas con sus porcentajes, bodega elaboradora,
--     maridajes y stock total (deposito mas salas).
-- Parametro: codigo de vino = 1 ("Malbec Reserva", 750 ml, 2021).
-- Estrategia: subconsultas escalares correlacionadas para las tres
--   colecciones (cepas, maridajes y stock), con STRING_AGG para devolver
--   varias filas como una lista. El stock total suma deposito y salas.
--   La suma de stock en salas usa idx_stock_sala_vino (Etapa 4).
-- ============================================================================
SELECT v.codigo,
       v.nombre,
       b.razon_social AS bodega,
       (SELECT STRING_AGG(c.nombre || ' ' || co.porcentaje || '%', ', ' ORDER BY co.porcentaje DESC)
          FROM composicion co
          JOIN cepa c ON c.id = co.id_cepa
         WHERE co.codigo_vino = v.codigo) AS cepas,
       (SELECT STRING_AGG(m.nombre, ', ' ORDER BY m.nombre)
          FROM vino_maridaje vm
          JOIN maridaje m ON m.id = vm.id_maridaje
         WHERE vm.codigo_vino = v.codigo) AS maridajes,
       (SELECT COALESCE(SUM(cantidad), 0) FROM stock_deposito WHERE codigo_vino = v.codigo)
     + (SELECT COALESCE(SUM(cantidad), 0) FROM stock_sala WHERE codigo_vino = v.codigo) AS stock_total
FROM vino v
JOIN bodega b ON b.cuit = v.cuit_bodega
WHERE v.codigo = 1;


-- ============================================================================
-- S10. Rendimiento en kg por hectarea de cada parcela y campana, e
--      identificacion de las parcelas que rinden menos que el promedio de
--      su finca.
-- Estrategia: CTE "rendimiento" que agrupa los lotes por parcela y campana
--   y divide kg_cosecha por la superficie de la parcela; luego una
--   subconsulta correlacionada que compara cada fila con el promedio de su
--   finca (AVG sobre la misma CTE).
-- ============================================================================
WITH rendimiento AS (
    SELECT p.id_finca,
           l.numero_parcela,
           l.campaña,
           SUM(l.kg_cosecha) / NULLIF(p.superficie, 0) AS kg_ha
    FROM lote l
    JOIN parcela p
      ON p.id_finca = l.id_finca
     AND p.numero_parcela = l.numero_parcela
    GROUP BY p.id_finca, l.numero_parcela, l.campaña, p.superficie
)
SELECT r.id_finca,
       r.numero_parcela,
       r.campaña,
       ROUND(r.kg_ha, 2) AS kg_ha
FROM rendimiento r
WHERE r.kg_ha < (
        SELECT AVG(r2.kg_ha)
        FROM rendimiento r2
        WHERE r2.id_finca = r.id_finca
      )
ORDER BY r.id_finca, r.campaña, r.numero_parcela;


-- ============================================================================
-- S11.a. Ranking de vinos dentro de cada sala por botellas vendidas.
-- Estrategia: join comprobante -> renglon_comprobante -> sala_venta,
--   GROUP BY sala y vino, y funcion de ventana RANK() OVER (PARTITION BY
--   sala ORDER BY SUM(cantidad) DESC). El orden final por sala y puesto deja
--   el resultado legible.
-- ============================================================================
SELECT s.id AS id_sala,
       rc.codigo_vino,
       SUM(rc.cantidad) AS botellas,
       RANK() OVER (PARTITION BY s.id ORDER BY SUM(rc.cantidad) DESC) AS puesto
FROM comprobante co
JOIN renglon_comprobante rc ON rc.numero_comprobante = co.numero
JOIN sala_venta s ON s.id = co.id_sala_venta
GROUP BY s.id, rc.codigo_vino
ORDER BY s.id, puesto;


-- ============================================================================
-- S11.b. Ventas acumuladas mensuales por sala.
-- Estrategia: se agrupa por sala y mes con date_trunc y luego se aplica
--   SUM(SUM(total)) OVER (PARTITION BY sala ORDER BY mes) para la suma
--   acumulada. La funcion de ventana se calcula sobre el resultado agregado.
-- ============================================================================
SELECT co.id_sala_venta AS id_sala,
       date_trunc('month', co.fecha)::date AS mes,
       SUM(co.total) AS ventas_mes,
       SUM(SUM(co.total)) OVER (
           PARTITION BY co.id_sala_venta
           ORDER BY date_trunc('month', co.fecha)
       ) AS acumulado
FROM comprobante co
GROUP BY co.id_sala_venta, date_trunc('month', co.fecha)
ORDER BY co.id_sala_venta, mes;


-- ============================================================================
-- S12.a. Clientes que compraron todos los vinos de una bodega determinada.
-- Parametro: cuit_bodega = '30100000209' (Cordoba-Lopez Bodega, 15 vinos).
--   Cambiar el literal por otra bodega.
-- Estrategia: division relacional con agregacion: agrupar los comprobantes
--   del cliente por los vinos de esa bodega y quedarse con los que tienen
--   COUNT(DISTINCT vino) igual al total de vinos de la bodega.
-- ============================================================================
SELECT c.id,
       c.nombre,
       c.apellido,
       c.razon_social
FROM cliente c
JOIN (
    SELECT co.id_cliente
    FROM comprobante co
    JOIN renglon_comprobante rc ON rc.numero_comprobante = co.numero
    JOIN vino v ON v.codigo = rc.codigo_vino
    WHERE v.cuit_bodega = '30100000209'
    GROUP BY co.id_cliente
    HAVING COUNT(DISTINCT rc.codigo_vino) = (
        SELECT COUNT(*) FROM vino WHERE cuit_bodega = '30100000209'
    )
) compradores ON compradores.id_cliente = c.id
ORDER BY c.id;


-- ============================================================================
-- S12.b. Clientes que nunca compraron ningun vino tinto (anti-join).
-- Estrategia: NOT EXISTS correlacionado sobre comprobante -> renglon ->
--   vino, filtrando tipo = 'tinto'. Se parte de los clientes activos.
-- Nota: la version con doble NOT EXISTS equivalente es la division de S2;
--   aqui el anti-join se resuelve con NOT EXISTS como pide la consigna.
-- ============================================================================
SELECT c.id,
       c.nombre,
       c.apellido
FROM cliente c
WHERE c.estado_activo
  AND NOT EXISTS (
        SELECT 1
        FROM comprobante co
        JOIN renglon_comprobante rc ON rc.numero_comprobante = co.numero
        JOIN vino v ON v.codigo = rc.codigo_vino
        WHERE co.id_cliente = c.id
          AND v.tipo = 'tinto'
      )
ORDER BY c.id;
