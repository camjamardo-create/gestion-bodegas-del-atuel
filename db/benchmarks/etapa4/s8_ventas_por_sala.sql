-- S8. Monto total de ventas por sala en el último trimestre, en orden descendente.
-- Filtra 26.640 comprobantes sobre 150.000 y agrupa por sala.
SELECT s.id AS id_sala,
       s.calle,
       s.numero,
       SUM(co.total) AS monto_total
FROM comprobante co
JOIN sala_venta s ON s.id = co.id_sala_venta
WHERE co.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY s.id, s.calle, s.numero
ORDER BY monto_total DESC;
