-- S3. Cantidad de clientes de cada tipo que compraron en una sala determinada en la última semana.
-- Sala elegida: 4 (la de mayor actividad en los últimos 7 días: 395 comprobantes).
-- Mide el filtro por fecha + sala sobre comprobante (150.000 filas) y el join con cliente (20.000).
SELECT c.tipo,
       COUNT(DISTINCT c.id) AS clientes
FROM comprobante co
JOIN cliente c ON c.id = co.id_cliente
WHERE co.id_sala_venta = 4
  AND co.fecha >= CURRENT_DATE - 7
GROUP BY c.tipo
ORDER BY clientes DESC;
