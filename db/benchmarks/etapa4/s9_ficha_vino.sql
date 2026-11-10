-- S9. Ficha de un vino: cepas con sus porcentajes, bodega elaboradora, maridajes
-- y stock total (deposito mas salas). Vino elegido: codigo 1.
-- Recorre stock_sala (12.000 filas) para sumar el stock del vino en las salas.
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
