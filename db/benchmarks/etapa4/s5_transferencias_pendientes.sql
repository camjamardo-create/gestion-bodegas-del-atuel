-- S5. Listado de las salas con menor cantidad de transferencias pendientes (no procesadas).
-- Uso del indice parcial idx_transferencia_pendientes.
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
