-- ============================================================================
-- consultas/delete.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 5: consignas D1 a D6 de la seccion 8.3
--
-- Cada bloque se prueba dentro de una transaccion:
--     BEGIN;  ->  control previo  ->  sentencia  ->  control posterior  ->  ROLLBACK;
-- El ROLLBACK deja la base como estaba. Para aplicar el cambio de forma
-- definitiva se reemplaza el ROLLBACK por COMMIT.
--
-- En cada bloque se anotan las acciones referenciales en cascada y los
-- triggers que intervienen.
-- ============================================================================

SET client_encoding = 'UTF8';


-- ============================================================================
-- D1. Borrar los comprobantes con mas de 5 anios de antiguedad asociados a
--     clientes socios del club.
--
-- Estrategia: DELETE con dos condiciones: rango de fecha (fecha < CURRENT_DATE
--   - 5 years) y pertenencia al subtipo socio_club mediante IN sobre
--   socio_club. El borrado de los renglones es automatico por la FK
--   fk_renglon_comprobante_comprobante ON DELETE CASCADE. No hay triggers de
--   DELETE sobre comprobante ni sobre renglon_comprobante, por lo que la
--   sentencia no se bloquea. Importante: el stock de las salas no se repone
--   (la base solo descuenta stock al vender, no al borrar ventas).
--
-- Parametros: antiguedad = 5 years. Cambiar el intervalo para otra ventana.
-- Resultado obtenido: DELETE 7450 comprobantes y 27862 renglones borrados en
--   cascada (verificado con los controles de conteo).
-- ============================================================================
BEGIN;

-- Control previo
SELECT COUNT(*) AS comprobantes_a_borrar,
       COALESCE(SUM(c.total), 0) AS monto_total
FROM comprobante c
WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
  AND c.id_cliente IN (SELECT id_cliente FROM socio_club);

SELECT COUNT(*) AS renglones_a_borrar
FROM renglon_comprobante rc
JOIN comprobante c ON c.numero = rc.numero_comprobante
WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
  AND c.id_cliente IN (SELECT id_cliente FROM socio_club);

SELECT COUNT(*) AS comprobantes_antes,
       (SELECT COUNT(*) FROM renglon_comprobante) AS renglones_antes
FROM comprobante;

-- Sentencia
DELETE FROM comprobante c
WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
  AND c.id_cliente IN (SELECT id_cliente FROM socio_club);

-- Control posterior
SELECT COUNT(*) AS comprobantes_despues,
       (SELECT COUNT(*) FROM renglon_comprobante) AS renglones_despues
FROM comprobante;

SELECT COUNT(*) AS quedan_comprobantes_viejos_de_socios
FROM comprobante c
WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
  AND c.id_cliente IN (SELECT id_cliente FROM socio_club);

ROLLBACK;


-- ============================================================================
-- D2. Eliminar las cepas que no componen ningun vino ni estan plantadas en
--     ninguna parcela.
--
-- Estrategia: DELETE con dos anti-joins NOT EXISTS correlacionados, uno sobre
--   composicion y otro sobre parcela. Es la forma directa de expresar "no
--   referenciada por ninguna de las dos". Las FK fk_composicion_cepa y
--   fk_parcela_cepa son ON DELETE RESTRICT, pero no se violan porque las
--   cepas borradas no tienen filas en ninguna de las dos tablas.
--
-- Resultado obtenido: DELETE 1 (cepa 12, "Semillon", tipo blanca).
-- ============================================================================
BEGIN;

-- Control previo
SELECT c.id, c.nombre, c.tipo
FROM cepa c
WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id)
  AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id);

SELECT COUNT(*) AS cepas_antes FROM cepa;

-- Sentencia
DELETE FROM cepa c
WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id)
  AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id);

-- Control posterior
SELECT COUNT(*) AS cepas_despues FROM cepa;

SELECT COUNT(*) AS cepas_libres_restantes
FROM cepa c
WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id)
  AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id);

ROLLBACK;


-- ============================================================================
-- D3. La sala de una localidad determinada fue dada de baja: eliminar los
--     empleados de esa sala que trabajaron menos de dos anios.
--
-- Estrategia: DELETE ... USING con join a sala_venta para ubicar la sala por
--   el codigo postal de la localidad (Junin, '5573'), y filtro por
--   fn_antiguedad_anios(fecha_ingreso) < 2. La funcion calcula los anios
--   cumplidos contra CURRENT_DATE. Se usa la funcion para no repetir la
--   formula de edad.
--
-- Parametros: codigo_postal = '5573' (Junin), antiguedad < 2 anios.
-- Resultado obtenido: DELETE 2 (los empleados de sala Juan Cruz Martinez y
--   Emilia Garcia, ambos con 0 anios). El encargado regional de la localidad
--   (Lucas Sanchez, 6 anios) no se toca: no cumple el filtro y ademas esta
--   referenciado por localidad.cuit_encargado (FK ON DELETE RESTRICT).
-- ============================================================================
BEGIN;

-- Control previo
SELECT e.cuit, e.tipo, e.nombre, e.apellido,
       fn_antiguedad_anios(e.fecha_ingreso) AS anios
FROM empleado e
JOIN sala_venta s ON s.id = e.id_sala
WHERE s.codigo_postal = '5573'
ORDER BY e.cuit;

SELECT COUNT(*) AS empleados_antes FROM empleado;

-- Sentencia
DELETE FROM empleado e
USING sala_venta s
WHERE e.id_sala = s.id
  AND s.codigo_postal = '5573'
  AND fn_antiguedad_anios(e.fecha_ingreso) < 2;

-- Control posterior
SELECT e.cuit, e.tipo, e.nombre, e.apellido,
       fn_antiguedad_anios(e.fecha_ingreso) AS anios
FROM empleado e
JOIN sala_venta s ON s.id = e.id_sala
WHERE s.codigo_postal = '5573'
ORDER BY e.cuit;

SELECT COUNT(*) AS empleados_despues FROM empleado;

ROLLBACK;


-- ============================================================================
-- D4. Borrar los clientes socios que nunca compraron y se dieron de alta hace
--     mas de 5 anios.
--
-- Estrategia: DELETE sobre cliente con tres condiciones: tipo = 'socio_club',
--   fecha_alta anterior a CURRENT_DATE - 5 years y anti-join NOT EXISTS sobre
--   comprobante. Al borrar la fila de cliente, la FK
--   fk_socio_club_cliente (ON DELETE CASCADE) borra la fila de socio_club.
--   El trigger diferido trg_cliente_subtipo_total / trg_socio_club_subtipo_total
--   valida al final de la transaccion que no queden clientes sin subtipo; la
--   funcion fn_validar_subtipo_cliente() retorna sin error cuando el cliente
--   ya no existe, por lo que el borrado en cascada es correcto.
--
-- Parametros: antiguedad = 5 years. Cambiar el intervalo para otra ventana.
-- Resultado obtenido: DELETE 102 clientes (y sus 102 filas de socio_club en
--   cascada).
-- ============================================================================
BEGIN;

-- Control previo
SELECT COUNT(*) AS socios_a_borrar
FROM cliente c
WHERE c.tipo = 'socio_club'
  AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id);

SELECT COUNT(*) AS clientes_antes,
       (SELECT COUNT(*) FROM socio_club) AS socios_antes
FROM cliente;

-- Sentencia
DELETE FROM cliente c
WHERE c.tipo = 'socio_club'
  AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id);

-- Control posterior (el trigger diferido se valida al hacer ROLLBACK/COMMIT;
-- dentro de la transaccion las filas de socio_club ya se borraron en cascada).
SELECT COUNT(*) AS clientes_despues,
       (SELECT COUNT(*) FROM socio_club) AS socios_despues
FROM cliente;

SELECT COUNT(*) AS socios_sin_compras_viejos_restantes
FROM cliente c
WHERE c.tipo = 'socio_club'
  AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id);

-- Fuerza la validacion de los triggers diferidos antes del ROLLBACK.
SET CONSTRAINTS ALL IMMEDIATE;

ROLLBACK;


-- ============================================================================
-- D5. Eliminar los ingresos en estado procesado de hace mas de 365 dias.
--
-- Estrategia: DELETE con filtro por estado y fecha. Los renglones se borran
--   en cascada por fk_renglon_ingreso_ingreso (ON DELETE CASCADE). El trigger
--   trg_renglon_ingreso_bloqueo, en TG_OP = 'DELETE', consulta la cabecera y
--   si ya no existe (caso cascade) permite el borrado; por eso no bloquea la
--   operacion. Al igual que en D1, el stock del deposito no se revierte: los
--   ingresos procesados ya habian sumado stock y la base no tiene trigger de
--   reversion al borrar.
--
-- Parametros: estado = 'procesado', antiguedad > 365 dias.
-- Resultado obtenido: DELETE 657 ingresos y 1378 renglones borrados en
--   cascada.
-- ============================================================================
BEGIN;

-- Control previo
SELECT COUNT(*) AS ingresos_a_borrar
FROM ingreso i
WHERE i.estado = 'procesado'
  AND i.fecha < CURRENT_DATE - 365;

SELECT COUNT(*) AS renglones_a_borrar
FROM renglon_ingreso ri
JOIN ingreso i ON i.codigo = ri.codigo_ingreso
WHERE i.estado = 'procesado'
  AND i.fecha < CURRENT_DATE - 365;

SELECT COUNT(*) AS ingresos_antes,
       (SELECT COUNT(*) FROM renglon_ingreso) AS renglones_antes
FROM ingreso;

-- Sentencia
DELETE FROM ingreso i
WHERE i.estado = 'procesado'
  AND i.fecha < CURRENT_DATE - 365;

-- Control posterior
SELECT COUNT(*) AS ingresos_despues,
       (SELECT COUNT(*) FROM renglon_ingreso) AS renglones_despues
FROM ingreso;

SELECT COUNT(*) AS ingresos_viejos_procesados_restantes
FROM ingreso i
WHERE i.estado = 'procesado'
  AND i.fecha < CURRENT_DATE - 365;

ROLLBACK;


-- ============================================================================
-- D6. Borrar los clientes socios sin compras que viven en una localidad
--     especifica.
--
-- Estrategia: DELETE sobre cliente con tipo = 'socio_club', codigo_postal de
--   la localidad elegida y anti-join NOT EXISTS sobre comprobante. La consigna
--   no pide antiguedad, por eso no se filtra fecha_alta (a diferencia de D4).
--   La fila de socio_club se borra en cascada por fk_socio_club_cliente.
--
-- Parametros: codigo_postal = '5600' (San Rafael).
-- Resultado obtenido: DELETE 16 clientes socios de San Rafael sin compras
--   (13 de ellos tienen ademas mas de 5 anios de alta, por lo que se solapan
--   con D4; los otros 3 son socios nuevos sin compras).
-- ============================================================================
BEGIN;

-- Control previo
SELECT COUNT(*) AS socios_san_rafael_sin_compras
FROM cliente c
WHERE c.tipo = 'socio_club'
  AND c.codigo_postal = '5600'
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id);

SELECT c.id, c.nombre, c.apellido, c.fecha_alta
FROM cliente c
WHERE c.tipo = 'socio_club'
  AND c.codigo_postal = '5600'
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id)
ORDER BY c.id;

-- Sentencia
DELETE FROM cliente c
WHERE c.tipo = 'socio_club'
  AND c.codigo_postal = '5600'
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id);

-- Control posterior
SELECT COUNT(*) AS socios_san_rafael_sin_compras_restantes
FROM cliente c
WHERE c.tipo = 'socio_club'
  AND c.codigo_postal = '5600'
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id);

SELECT COUNT(*) AS clientes_despues,
       (SELECT COUNT(*) FROM socio_club) AS socios_despues
FROM cliente;

-- Fuerza la validacion de los triggers diferidos antes del ROLLBACK.
SET CONSTRAINTS ALL IMMEDIATE;

ROLLBACK;
