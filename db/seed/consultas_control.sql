-- consultas_control.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 3: controles de integridad y coherencia de la carga masiva.
--
-- Formato para cargar_datos.py:
--   -- @query: nombre
--   -- @tipo: info | problema
--   SELECT ...
--   ;
--
-- Las consultas de tipo "problema" deben devolver 0 filas.
-- Las de tipo "info" muestran conteos y no se consideran fallas.

-- @query: q01_volumenes_por_tabla
-- @tipo: info
SELECT 'bodega' AS tabla, count(*) AS filas FROM bodega
UNION ALL SELECT 'finca', count(*) FROM finca
UNION ALL SELECT 'cepa', count(*) FROM cepa
UNION ALL SELECT 'maridaje', count(*) FROM maridaje
UNION ALL SELECT 'transportista', count(*) FROM transportista
UNION ALL SELECT 'localidad', count(*) FROM localidad
UNION ALL SELECT 'sala_venta', count(*) FROM sala_venta
UNION ALL SELECT 'empleado', count(*) FROM empleado
UNION ALL SELECT 'transportista_cubre_localidad', count(*) FROM transportista_cubre_localidad
UNION ALL SELECT 'ingreso', count(*) FROM ingreso
UNION ALL SELECT 'cliente', count(*) FROM cliente
UNION ALL SELECT 'cliente_comun', count(*) FROM cliente_comun
UNION ALL SELECT 'socio_club', count(*) FROM socio_club
UNION ALL SELECT 'distribuidor', count(*) FROM distribuidor
UNION ALL SELECT 'exportador', count(*) FROM exportador
UNION ALL SELECT 'permiso', count(*) FROM permiso
UNION ALL SELECT 'parcela', count(*) FROM parcela
UNION ALL SELECT 'lote', count(*) FROM lote
UNION ALL SELECT 'analisis_calidad', count(*) FROM analisis_calidad
UNION ALL SELECT 'vino', count(*) FROM vino
UNION ALL SELECT 'composicion', count(*) FROM composicion
UNION ALL SELECT 'stock_deposito', count(*) FROM stock_deposito
UNION ALL SELECT 'vino_maridaje', count(*) FROM vino_maridaje
UNION ALL SELECT 'renglon_ingreso', count(*) FROM renglon_ingreso
UNION ALL SELECT 'auditoria_precio', count(*) FROM auditoria_precio
UNION ALL SELECT 'stock_sala', count(*) FROM stock_sala
UNION ALL SELECT 'comprobante', count(*) FROM comprobante
UNION ALL SELECT 'renglon_comprobante', count(*) FROM renglon_comprobante
UNION ALL SELECT 'transferencia', count(*) FROM transferencia
UNION ALL SELECT 'renglon_transferencia', count(*) FROM renglon_transferencia
ORDER BY tabla;

-- @query: q02_volumenes_minimos
-- @tipo: problema
WITH conteos AS (
    SELECT 'bodega' AS tabla, count(*) AS filas FROM bodega
    UNION ALL SELECT 'finca', count(*) FROM finca
    UNION ALL SELECT 'cepa', count(*) FROM cepa
    UNION ALL SELECT 'maridaje', count(*) FROM maridaje
    UNION ALL SELECT 'transportista', count(*) FROM transportista
    UNION ALL SELECT 'localidad', count(*) FROM localidad
    UNION ALL SELECT 'sala_venta', count(*) FROM sala_venta
    UNION ALL SELECT 'empleado', count(*) FROM empleado
    UNION ALL SELECT 'transportista_cubre_localidad', count(*) FROM transportista_cubre_localidad
    UNION ALL SELECT 'ingreso', count(*) FROM ingreso
    UNION ALL SELECT 'cliente', count(*) FROM cliente
    UNION ALL SELECT 'cliente_comun', count(*) FROM cliente_comun
    UNION ALL SELECT 'socio_club', count(*) FROM socio_club
    UNION ALL SELECT 'distribuidor', count(*) FROM distribuidor
    UNION ALL SELECT 'exportador', count(*) FROM exportador
    UNION ALL SELECT 'permiso', count(*) FROM permiso
    UNION ALL SELECT 'parcela', count(*) FROM parcela
    UNION ALL SELECT 'lote', count(*) FROM lote
    UNION ALL SELECT 'analisis_calidad', count(*) FROM analisis_calidad
    UNION ALL SELECT 'vino', count(*) FROM vino
    UNION ALL SELECT 'composicion', count(*) FROM composicion
    UNION ALL SELECT 'stock_deposito', count(*) FROM stock_deposito
    UNION ALL SELECT 'vino_maridaje', count(*) FROM vino_maridaje
    UNION ALL SELECT 'renglon_ingreso', count(*) FROM renglon_ingreso
    UNION ALL SELECT 'auditoria_precio', count(*) FROM auditoria_precio
    UNION ALL SELECT 'stock_sala', count(*) FROM stock_sala
    UNION ALL SELECT 'comprobante', count(*) FROM comprobante
    UNION ALL SELECT 'renglon_comprobante', count(*) FROM renglon_comprobante
    UNION ALL SELECT 'transferencia', count(*) FROM transferencia
    UNION ALL SELECT 'renglon_transferencia', count(*) FROM renglon_transferencia
), chequeos AS (
    SELECT 'tabla_sin_filas' AS control, tabla AS detalle, filas AS n
      FROM conteos
     WHERE filas < 1
    UNION ALL
    SELECT 'menos_de_3_tablas_mayores_a_10000', NULL::text, count(*)
      FROM conteos
     WHERE filas > 10000
    HAVING count(*) < 3
    UNION ALL
    SELECT 'sin_tabla_mayor_a_100000', NULL::text, count(*)
      FROM conteos
     WHERE filas > 100000
    HAVING count(*) < 1
)
SELECT * FROM chequeos WHERE n > 0;

-- @query: q03_stock_coherente
-- @tipo: problema
WITH ingresos_proc AS (
    SELECT ri.codigo_vino, sum(ri.cantidad) AS cantidad
      FROM renglon_ingreso ri
      JOIN ingreso i ON i.codigo = ri.codigo_ingreso
     WHERE i.estado = 'procesado'
     GROUP BY ri.codigo_vino
), transferencias_proc AS (
    SELECT rt.codigo_vino, sum(rt.cantidad) AS cantidad
      FROM renglon_transferencia rt
      JOIN transferencia t ON t.numero = rt.numero_transferencia
     WHERE t.estado = 'procesado'
     GROUP BY rt.codigo_vino
), esperado_deposito AS (
    SELECT v.codigo AS codigo_vino,
           coalesce(i.cantidad, 0) - coalesce(t.cantidad, 0) AS cantidad
      FROM vino v
      LEFT JOIN ingresos_proc i ON i.codigo_vino = v.codigo
      LEFT JOIN transferencias_proc t ON t.codigo_vino = v.codigo
), ventas_por_sala AS (
    SELECT c.id_sala_venta AS id_sala, rc.codigo_vino, sum(rc.cantidad) AS cantidad
      FROM comprobante c
      JOIN renglon_comprobante rc ON rc.numero_comprobante = c.numero
     GROUP BY c.id_sala_venta, rc.codigo_vino
), transferencias_por_sala AS (
    SELECT t.id_sala_venta AS id_sala, rt.codigo_vino, sum(rt.cantidad) AS cantidad
      FROM transferencia t
      JOIN renglon_transferencia rt ON rt.numero_transferencia = t.numero
     WHERE t.estado = 'procesado'
     GROUP BY t.id_sala_venta, rt.codigo_vino
), esperado_sala AS (
    SELECT s.id AS id_sala, v.codigo AS codigo_vino,
           coalesce(t.cantidad, 0) - coalesce(vt.cantidad, 0) AS cantidad
      FROM sala_venta s
      CROSS JOIN vino v
      LEFT JOIN transferencias_por_sala t
             ON t.id_sala = s.id AND t.codigo_vino = v.codigo
      LEFT JOIN ventas_por_sala vt
             ON vt.id_sala = s.id AND vt.codigo_vino = v.codigo
), chequeos AS (
    SELECT 'stock_deposito_negativo' AS control, count(*) AS n
      FROM stock_deposito WHERE cantidad < 0
    UNION ALL
    SELECT 'stock_sala_negativo', count(*)
      FROM stock_sala WHERE cantidad < 0
    UNION ALL
    SELECT 'vino_sin_stock_deposito', count(*)
      FROM vino v
     WHERE NOT EXISTS (
           SELECT 1 FROM stock_deposito sd WHERE sd.codigo_vino = v.codigo
     )
    UNION ALL
    SELECT 'stock_deposito_incoherente', count(*)
      FROM stock_deposito sd
      JOIN esperado_deposito e ON e.codigo_vino = sd.codigo_vino
     WHERE sd.cantidad <> e.cantidad
    UNION ALL
    SELECT 'stock_sala_incoherente', count(*)
      FROM stock_sala ss
      JOIN esperado_sala e ON e.id_sala = ss.id_sala AND e.codigo_vino = ss.codigo_vino
     WHERE ss.cantidad <> e.cantidad
    UNION ALL
    SELECT 'sin_stock_cero_en_sala_con_deposito_positivo',
           CASE WHEN EXISTS (
                SELECT 1
                  FROM stock_sala ss
                  JOIN stock_deposito sd ON sd.codigo_vino = ss.codigo_vino
                 WHERE ss.cantidad = 0 AND sd.cantidad > 0
           ) THEN 0 ELSE 1 END
)
SELECT * FROM chequeos WHERE n > 0;

-- @query: q04_totales_comprobantes
-- @tipo: problema
WITH renglones AS (
    SELECT numero_comprobante, sum(subtotal_renglon) AS subtotal
      FROM renglon_comprobante
     GROUP BY numero_comprobante
), chequeos AS (
    SELECT 'comprobante_sin_renglones' AS control, count(*) AS n
      FROM comprobante c
     WHERE NOT EXISTS (
           SELECT 1 FROM renglon_comprobante rc WHERE rc.numero_comprobante = c.numero
     )
    UNION ALL
    SELECT 'subtotal_incoherente', count(*)
      FROM comprobante c
      JOIN renglones r ON r.numero_comprobante = c.numero
     WHERE c.subtotal <> r.subtotal
    UNION ALL
    SELECT 'total_incoherente', count(*)
      FROM comprobante c
      JOIN renglones r ON r.numero_comprobante = c.numero
     WHERE c.total <> round(r.subtotal * (1 - c.descuento_aplicado), 2)
    UNION ALL
    SELECT 'descuento_total_incoherente', count(*)
      FROM comprobante
     WHERE descuento_total <> subtotal - total
)
SELECT * FROM chequeos WHERE n > 0;

-- @query: q05_composicion_vinos
-- @tipo: problema
WITH suma_composicion AS (
    SELECT codigo_vino
      FROM composicion
     GROUP BY codigo_vino
    HAVING sum(porcentaje) <> 100
), chequeos AS (
    SELECT 'vino_sin_composicion' AS control, count(*) AS n
      FROM vino v
     WHERE NOT EXISTS (SELECT 1 FROM composicion c WHERE c.codigo_vino = v.codigo)
    UNION ALL
    SELECT 'composicion_no_suma_100', count(*) FROM suma_composicion
    UNION ALL
    SELECT 'tinto_con_cepa_blanca', count(*)
      FROM composicion co
      JOIN vino v ON v.codigo = co.codigo_vino
      JOIN cepa c ON c.id = co.id_cepa
     WHERE v.tipo = 'tinto' AND c.tipo <> 'tinta'
    UNION ALL
    SELECT 'blanco_con_cepa_tinta', count(*)
      FROM composicion co
      JOIN vino v ON v.codigo = co.codigo_vino
      JOIN cepa c ON c.id = co.id_cepa
     WHERE v.tipo = 'blanco' AND c.tipo <> 'blanca'
    UNION ALL
    SELECT 'cepa_semillon_usada', (
        SELECT count(*) FROM parcela WHERE id_cepa = 12
    ) + (
        SELECT count(*) FROM composicion WHERE id_cepa = 12
    )
)
SELECT * FROM chequeos WHERE n > 0;

-- @query: q06_fechas_logicas_y_ventanas
-- @tipo: problema
WITH primer_ingreso_proc AS (
    SELECT ri.codigo_vino, min(i.fecha) AS fecha
      FROM renglon_ingreso ri
      JOIN ingreso i ON i.codigo = ri.codigo_ingreso
     WHERE i.estado = 'procesado'
     GROUP BY ri.codigo_vino
), primera_transferencia_proc AS (
    SELECT rt.codigo_vino, min(t.fecha_confeccion) AS fecha
      FROM renglon_transferencia rt
      JOIN transferencia t ON t.numero = rt.numero_transferencia
     WHERE t.estado = 'procesado'
     GROUP BY rt.codigo_vino
), primera_compra AS (
    SELECT id_cliente, min(fecha) AS fecha
      FROM comprobante
     GROUP BY id_cliente
), chequeos AS (
    SELECT 'vino_transferido_sin_ingreso_previo' AS control, count(*) AS n
      FROM primera_transferencia_proc t
     WHERE NOT EXISTS (
           SELECT 1 FROM primer_ingreso_proc i
            WHERE i.codigo_vino = t.codigo_vino AND i.fecha < t.fecha
     )
    UNION ALL
    SELECT 'transferencia_procesada_posterior_a_venta', count(*)
      FROM transferencia t
     WHERE t.estado = 'procesado'
       AND EXISTS (
           SELECT 1 FROM comprobante c
            WHERE c.id_sala_venta = t.id_sala_venta
              AND c.fecha < t.fecha_confeccion
       )
    UNION ALL
    SELECT 'compra_antes_de_alta_cliente', count(*)
      FROM primera_compra pc
      JOIN cliente c ON c.id = pc.id_cliente
     WHERE c.fecha_alta > pc.fecha
    UNION ALL
    SELECT 'venta_posterior_a_fecha_referencia', count(*)
      FROM comprobante
     WHERE fecha > COALESCE(current_setting('app.fecha_referencia', true)::date, CURRENT_DATE)
    UNION ALL
    SELECT 'sin_ingreso_procesado_mayor_a_365_dias',
           CASE WHEN EXISTS (
                SELECT 1 FROM ingreso
                 WHERE estado = 'procesado'
                   AND fecha < COALESCE(current_setting('app.fecha_referencia', true)::date, CURRENT_DATE) - INTERVAL '365 days'
           ) THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_venta_ultimo_trimestre',
           CASE WHEN EXISTS (
                SELECT 1 FROM comprobante
                 WHERE fecha >= COALESCE(current_setting('app.fecha_referencia', true)::date, CURRENT_DATE) - INTERVAL '90 days'
           ) THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_venta_ultimo_mes',
           CASE WHEN EXISTS (
                SELECT 1 FROM comprobante
                 WHERE fecha >= COALESCE(current_setting('app.fecha_referencia', true)::date, CURRENT_DATE) - INTERVAL '30 days'
           ) THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_venta_ultimos_15_dias',
           CASE WHEN EXISTS (
                SELECT 1 FROM comprobante
                 WHERE fecha >= COALESCE(current_setting('app.fecha_referencia', true)::date, CURRENT_DATE) - INTERVAL '15 days'
           ) THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_venta_ultima_semana',
           CASE WHEN EXISTS (
                SELECT 1 FROM comprobante
                 WHERE fecha >= COALESCE(current_setting('app.fecha_referencia', true)::date, CURRENT_DATE) - INTERVAL '7 days'
           ) THEN 0 ELSE 1 END
)
SELECT * FROM chequeos WHERE n > 0;

-- @query: q07_clientes_descuentos_y_permisos
-- @tipo: problema
WITH subtipos AS (
    SELECT c.id,
           (SELECT count(*) FROM cliente_comun cc WHERE cc.id_cliente = c.id)
         + (SELECT count(*) FROM socio_club sc WHERE sc.id_cliente = c.id)
         + (SELECT count(*) FROM distribuidor d WHERE d.id_cliente = c.id)
         + (SELECT count(*) FROM exportador e WHERE e.id_cliente = c.id) AS n
      FROM cliente c
), chequeos AS (
    SELECT 'cliente_sin_subtipo_o_con_varios' AS control, count(*) AS n
      FROM subtipos WHERE n <> 1
    UNION ALL
    SELECT 'descuento_aplicado_incoherente', count(*)
      FROM comprobante c
     WHERE c.descuento_aplicado <> fn_descuento_cliente(c.id_cliente)
    UNION ALL
    SELECT 'descuento_fuera_rango', count(*)
      FROM comprobante
     WHERE descuento_aplicado < 0 OR descuento_aplicado > 0.35
    UNION ALL
    SELECT 'exportador_sin_permiso', count(*)
      FROM exportador e
     WHERE NOT EXISTS (SELECT 1 FROM permiso p WHERE p.id_exportador = e.id_cliente)
    UNION ALL
    SELECT 'sin_exportador_con_mas_de_3_permisos',
           CASE WHEN EXISTS (
                SELECT 1 FROM permiso GROUP BY id_exportador HAVING count(*) > 3
           ) THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_exportador_con_descuento_especial',
           CASE WHEN EXISTS (
                SELECT 1 FROM exportador WHERE descuento_especial IS NOT NULL
           ) THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_socio_antiguo_sin_compras',
           CASE WHEN EXISTS (
                SELECT 1
                  FROM socio_club sc
                  JOIN cliente c ON c.id = sc.id_cliente
                 WHERE c.fecha_alta < COALESCE(current_setting('app.fecha_referencia', true)::date, CURRENT_DATE) - INTERVAL '5 years'
                   AND NOT EXISTS (
                       SELECT 1 FROM comprobante co WHERE co.id_cliente = sc.id_cliente
                   )
           ) THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_venta_a_socio_mayor_a_5_anios',
           CASE WHEN EXISTS (
                SELECT 1
                  FROM comprobante co
                  JOIN socio_club sc ON sc.id_cliente = co.id_cliente
                 WHERE co.fecha < COALESCE(current_setting('app.fecha_referencia', true)::date, CURRENT_DATE) - INTERVAL '5 years'
           ) THEN 0 ELSE 1 END
)
SELECT * FROM chequeos WHERE n > 0;

-- @query: q08_cobertura_comercial
-- @tipo: problema
WITH pares AS (
    SELECT s.id AS id_sala, v.codigo AS codigo_vino
      FROM sala_venta s
      CROSS JOIN vino v
), vendidos AS (
    SELECT DISTINCT c.id_sala_venta AS id_sala, rc.codigo_vino
      FROM comprobante c
      JOIN renglon_comprobante rc ON rc.numero_comprobante = c.numero
), faltantes AS (
    SELECT * FROM pares
    EXCEPT
    SELECT * FROM vendidos
), chequeos AS (
    SELECT 'cantidad_de_pares_no_vendidos_distinta_de_1' AS control,
           CASE WHEN count(*) <> 1 THEN count(*) ELSE 0 END AS n
      FROM faltantes
    UNION ALL
    SELECT 'par_no_vendido_distinto_de_sala_1_vino_1', count(*)
      FROM faltantes
     WHERE NOT (id_sala = 1 AND codigo_vino = 1)
    UNION ALL
    SELECT 'par_sin_fila_de_stock_sala', count(*)
      FROM pares p
      LEFT JOIN stock_sala ss
             ON ss.id_sala = p.id_sala AND ss.codigo_vino = p.codigo_vino
     WHERE ss.codigo_vino IS NULL
)
SELECT * FROM chequeos WHERE n > 0;

-- @query: q09_estados_de_documentos
-- @tipo: problema
WITH chequeos AS (
    SELECT 'ingreso_con_estado_invalido' AS control, count(*) AS n
      FROM ingreso
     WHERE estado NOT IN ('en_confeccion', 'terminado', 'procesado')
    UNION ALL
    SELECT 'transferencia_con_estado_invalido', count(*)
      FROM transferencia
     WHERE estado NOT IN ('en_confeccion', 'terminado', 'procesado')
    UNION ALL
    SELECT 'sin_ingreso_procesado',
           CASE WHEN EXISTS (SELECT 1 FROM ingreso WHERE estado = 'procesado')
                THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_ingreso_terminado',
           CASE WHEN EXISTS (SELECT 1 FROM ingreso WHERE estado = 'terminado')
                THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_ingreso_en_confeccion',
           CASE WHEN EXISTS (SELECT 1 FROM ingreso WHERE estado = 'en_confeccion')
                THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_transferencia_procesada',
           CASE WHEN EXISTS (SELECT 1 FROM transferencia WHERE estado = 'procesado')
                THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_transferencia_terminada',
           CASE WHEN EXISTS (SELECT 1 FROM transferencia WHERE estado = 'terminado')
                THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_transferencia_en_confeccion',
           CASE WHEN EXISTS (SELECT 1 FROM transferencia WHERE estado = 'en_confeccion')
                THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sin_permiso_vencido',
           CASE WHEN EXISTS (
                SELECT 1 FROM permiso WHERE fecha_vencimiento < COALESCE(current_setting('app.fecha_referencia', true)::date, CURRENT_DATE)
           ) THEN 0 ELSE 1 END
)
SELECT * FROM chequeos WHERE n > 0;

-- @query: q10_precios_y_presentaciones
-- @tipo: problema
WITH chequeos AS (
    SELECT 'precio_de_vino_no_positivo' AS control, count(*) AS n
      FROM vino WHERE precio <= 0
    UNION ALL
    SELECT 'precio_unitario_no_positivo', count(*)
      FROM renglon_comprobante WHERE precio_unitario <= 0
    UNION ALL
    SELECT 'graduacion_fuera_de_rango', count(*)
      FROM vino WHERE graduacion <= 0 OR graduacion > 20
    UNION ALL
    SELECT 'volumen_ml_invalido', count(*)
      FROM vino WHERE volumen_ml NOT IN (187, 375, 750, 1500, 3000)
    UNION ALL
    SELECT 'porcentaje_de_composicion_invalido', count(*)
      FROM composicion WHERE porcentaje <= 0 OR porcentaje > 100
    UNION ALL
    SELECT 'sin_venta_con_precio_historico_distinto',
           CASE WHEN EXISTS (
                SELECT 1
                  FROM renglon_comprobante rc
                  JOIN vino v ON v.codigo = rc.codigo_vino
                 WHERE rc.precio_unitario <> v.precio
           ) THEN 0 ELSE 1 END
)
SELECT * FROM chequeos WHERE n > 0;

-- @query: q11_secuencias_identidad
-- @tipo: problema
WITH esperado(tabla, columna, secuencia, max_id) AS (
    SELECT 'finca', 'id', pg_get_serial_sequence('finca', 'id'), max(id)::bigint FROM finca
    UNION ALL SELECT 'cepa', 'id', pg_get_serial_sequence('cepa', 'id'), max(id)::bigint FROM cepa
    UNION ALL SELECT 'maridaje', 'id', pg_get_serial_sequence('maridaje', 'id'), max(id)::bigint FROM maridaje
    UNION ALL SELECT 'transportista', 'codigo', pg_get_serial_sequence('transportista', 'codigo'), max(codigo)::bigint FROM transportista
    UNION ALL SELECT 'sala_venta', 'id', pg_get_serial_sequence('sala_venta', 'id'), max(id)::bigint FROM sala_venta
    UNION ALL SELECT 'ingreso', 'codigo', pg_get_serial_sequence('ingreso', 'codigo'), max(codigo)::bigint FROM ingreso
    UNION ALL SELECT 'cliente', 'id', pg_get_serial_sequence('cliente', 'id'), max(id)::bigint FROM cliente
    UNION ALL SELECT 'permiso', 'codigo', pg_get_serial_sequence('permiso', 'codigo'), max(codigo)::bigint FROM permiso
    UNION ALL SELECT 'lote', 'numero_lote', pg_get_serial_sequence('lote', 'numero_lote'), max(numero_lote)::bigint FROM lote
    UNION ALL SELECT 'analisis_calidad', 'id', pg_get_serial_sequence('analisis_calidad', 'id'), max(id)::bigint FROM analisis_calidad
    UNION ALL SELECT 'vino', 'codigo', pg_get_serial_sequence('vino', 'codigo'), max(codigo)::bigint FROM vino
    UNION ALL SELECT 'auditoria_precio', 'id', pg_get_serial_sequence('auditoria_precio', 'id'), max(id)::bigint FROM auditoria_precio
    UNION ALL SELECT 'comprobante', 'numero', pg_get_serial_sequence('comprobante', 'numero'), max(numero)::bigint FROM comprobante
    UNION ALL SELECT 'transferencia', 'numero', pg_get_serial_sequence('transferencia', 'numero'), max(numero)::bigint FROM transferencia
), chequeos AS (
    SELECT 'secuencia_no_encontrada' AS control, count(*) AS n
      FROM esperado e
      LEFT JOIN pg_sequences p
             ON p.schemaname = 'public'
            AND p.sequencename = split_part(e.secuencia, '.', 2)
     WHERE p.sequencename IS NULL
    UNION ALL
    SELECT 'secuencia_desfasada', count(*)
      FROM esperado e
      JOIN pg_sequences p
        ON p.schemaname = 'public'
       AND p.sequencename = split_part(e.secuencia, '.', 2)
     WHERE p.last_value < e.max_id
)
SELECT * FROM chequeos WHERE n > 0;
