-- S6. Para una sala determinada (4), los vinos sin stock en la sala pero con stock
-- en el deposito central.
-- Recorre stock_sala (12.000 filas) buscando la fila del vino en esa sala.
SELECT v.codigo,
       v.nombre,
       sd.cantidad AS stock_deposito
FROM vino v
JOIN stock_deposito sd ON sd.codigo_vino = v.codigo
LEFT JOIN stock_sala ss
       ON ss.codigo_vino = v.codigo
      AND ss.id_sala = 4
WHERE sd.cantidad > 0
  AND COALESCE(ss.cantidad, 0) = 0
ORDER BY v.codigo;
