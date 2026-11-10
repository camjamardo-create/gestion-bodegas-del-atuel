-- S12 (segunda parte). Clientes que nunca compraron ningun vino tinto.
-- Anti-join NOT EXISTS sobre 20.000 clientes y 150.000 comprobantes.
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
