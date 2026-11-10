-- 006_vistas.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 2: Integridad y logica en la base de datos
-- Descripcion: 3 vistas requeridas en el TPI

--- ===============================================================================

SET client_encoding = 'UTF8';
BEGIN;

--- ===============================================================================

-- vista: stock total por vino 
-- esta vista tiene como proposito mostrar, para cada vino, el stock de deposito, el stock 
-- en salas y el total. Incluye vinos sin stock -> muestra 0
-- RN-09

CREATE OR REPLACE VIEW vista_stock_total_por_vino AS
SELECT v.codigo,
       v.nombre,
       v.añada, --codigo, nombre y añada del vino
       -- muestra la cantidad en deposito y stock
       COALESCE(d.cantidad, 0) AS stock_deposito,
       COALESCE(s.cantidad, 0) AS stock_sala,
       -- suma dep + salas
       COALESCE(d.cantidad, 0) + COALESCE(s.cantidad, 0) AS stock_total
FROM vino v
-- pega el stock del deposito con left para que un vino sin stock no desaparezca
LEFT JOIN stock_deposito d
       ON d.codigo_vino = v.codigo
LEFT JOIN ( -- suma de todas las salas
-- suma stock de todas las salas por vino
    SELECT codigo_vino, SUM(cantidad) AS cantidad
    FROM stock_sala
    GROUP BY codigo_vino)
    s ON s.codigo_vino = v.codigo;

--- ===============================================================================

--vista: ventas mensuales por sala
-- esta vista tiene como proposito mostras por sala y por mes, la cantidad
-- de comprobantes y los importes vendidos
-- RN-08

CREATE OR REPLACE VIEW vista_ventas_mensuales_por_sala AS
SELECT sv.id AS id_sala,
       sv.calle,
       sv.numero,
       -- convierte la fecha al 1er dia del mes (::date quita la hora)
       DATE_TRUNC('month', c.fecha)::date AS mes, 
       COUNT(*) AS cantidad_comprobantes,
       SUM(c.subtotal) AS subtotal,
       SUM(c.descuento_total) AS descuento_total,
       SUM(c.total) AS total_vendido
FROM comprobante c
-- une cada comprobante con su sala
JOIN sala_venta sv ON sv.id = c.id_sala_venta
-- agrupa por sala y por mes
GROUP BY sv.id, sv.calle, sv.numero, DATE_TRUNC('month', c.fecha)::date;

--- ===============================================================================

-- vista: documentos pendientes
-- esta vista tiene como proposito listar los ingresos y transferencia que todavia 
-- no fueron procesados, con los dias transcurridos desde su fecha
-- RN-10, RN-11

CREATE OR REPLACE VIEW vista_documentos_pendientes AS
-- agrega una columna y dice de que docs se trata
SELECT 'ingreso'::text AS tipo_documento, 
       i.codigo AS numero,
       i.fecha,
       i.estado,
       -- devuelve un entero de cuantos dias pasaron desde esa fecha
       CURRENT_DATE - i.fecha AS dias_pendiente
FROM ingreso i --tabla de ingresos
WHERE i.estado <> 'procesado' -- deja los que no estan procesados

--pega el res de ingresos con el de transferencias en una sola tabla
UNION ALL
-- lo mismo para las transferencias
SELECT 'transferencia'::text,
       t.numero,
       t.fecha_confeccion,
       t.estado,
       CURRENT_DATE - t.fecha_confeccion
FROM transferencia t
WHERE t.estado <> 'procesado';

COMMIT;