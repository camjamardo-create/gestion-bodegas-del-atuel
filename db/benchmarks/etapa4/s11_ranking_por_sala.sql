-- S11. Ranking de vinos dentro de cada sala por botellas vendidas.
-- Ventana RANK() sobre 564.328 renglones agrupados por sala y vino (12.000 combinaciones).
SELECT s.id AS id_sala,
       rc.codigo_vino,
       SUM(rc.cantidad) AS botellas,
       RANK() OVER (PARTITION BY s.id ORDER BY SUM(rc.cantidad) DESC) AS puesto
FROM comprobante co
JOIN renglon_comprobante rc ON rc.numero_comprobante = co.numero
JOIN sala_venta s ON s.id = co.id_sala_venta
GROUP BY s.id, rc.codigo_vino
ORDER BY s.id, puesto;
