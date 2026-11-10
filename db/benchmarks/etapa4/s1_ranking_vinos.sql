-- S1. Ranking de los 10 vinos con mayor cantidad de botellas vendidas en toda la red de salas.
-- Mide una agregación sobre los 564.328 renglones de comprobante (tabla más grande del modelo).
SELECT rc.codigo_vino,
       v.nombre,
       SUM(rc.cantidad) AS botellas_vendidas
FROM renglon_comprobante rc
JOIN vino v ON v.codigo = rc.codigo_vino
GROUP BY rc.codigo_vino, v.nombre
ORDER BY botellas_vendidas DESC
LIMIT 10;
