-- ============================================================================
-- consultas/insert.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 5: consignas I1 a I6 de la seccion 8.2
--
-- Cada bloque se prueba dentro de una transaccion:
--     BEGIN;  ->  control previo  ->  sentencia(s)  ->  control posterior  ->  ROLLBACK;
-- El ROLLBACK deja la base como estaba. Para aplicar el cambio de forma
-- definitiva se reemplaza el ROLLBACK por COMMIT.
--
-- Los valores concretos (transportista, cliente, bodega, sala, vino) salen del
-- dataset de la Etapa 3 y se pueden cambiar en cada bloque.
-- ============================================================================

SET client_encoding = 'UTF8';


-- ============================================================================
-- I1. Insertar en la relacion transportista-localidad una nueva cobertura que
--     vincule la localidad de General Alvear con el transportista que menos
--     envios (ingresos trasladados) realizo en el ultimo trimestre.
--
-- Estrategia: subconsulta que cuenta los ingresos de cada transportista en
--   los ultimos 3 meses con LEFT JOIN (un transportista sin envios cuenta 0,
--   no desaparece), ordenada de menor a mayor y desempatada por codigo para
--   que el resultado sea deterministico. El INSERT ... SELECT toma ese codigo
--   y lo combina con el codigo postal de General Alvear ('5620').
--   ON CONFLICT DO NOTHING hace la sentencia idempotente: si la cobertura ya
--   existiera no falla por la PK (codigo_transportista, codigo_postal_localidad).
--
-- Parametros: localidad = '5620' (General Alvear). Cambiar el literal por otro
--   codigo postal de localidad para otra cobertura.
-- Resultado obtenido: INSERT 0 1. El transportista elegido es el 12 (Leiva LLC
--   Transportes), con 0 ingresos en el ultimo trimestre. La cobertura de 5620
--   pasa de 2 a 3 transportistas.
-- ============================================================================
BEGIN;

-- Control previo: ranking del ultimo trimestre y coberturas actuales de 5620.
SELECT t.codigo,
       t.razon_social,
       COUNT(i.codigo) AS envios_ultimo_trimestre
FROM transportista t
LEFT JOIN ingreso i
       ON i.codigo_transportista = t.codigo
      AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY t.codigo, t.razon_social
ORDER BY envios_ultimo_trimestre ASC, t.codigo
LIMIT 5;

SELECT COUNT(*) AS coberturas_5620
FROM transportista_cubre_localidad
WHERE codigo_postal_localidad = '5620';

-- Sentencia
INSERT INTO transportista_cubre_localidad (codigo_transportista, codigo_postal_localidad)
SELECT t.codigo, '5620'
FROM transportista t
LEFT JOIN ingreso i
       ON i.codigo_transportista = t.codigo
      AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY t.codigo
ORDER BY COUNT(i.codigo) ASC, t.codigo
LIMIT 1
ON CONFLICT (codigo_transportista, codigo_postal_localidad) DO NOTHING;

-- Control posterior
SELECT tcl.codigo_transportista, t.razon_social, tcl.codigo_postal_localidad
FROM transportista_cubre_localidad tcl
JOIN transportista t ON t.codigo = tcl.codigo_transportista
WHERE tcl.codigo_postal_localidad = '5620'
ORDER BY tcl.codigo_transportista;

SELECT COUNT(*) AS coberturas_5620
FROM transportista_cubre_localidad
WHERE codigo_postal_localidad = '5620';

ROLLBACK;


-- ============================================================================
-- I2. Si existe algun vino tinto con graduacion de 14 grados o mas, crear el
--     maridaje "cordero al disco" y asociarlo a todos los vinos que cumplan
--     esa condicion.
--
-- Estrategia: una CTE que modifica datos inserta el maridaje solo si todavia no
--   existe (guard con NOT EXISTS) y devuelve su id con RETURNING. Otra CTE
--   arma el id del maridaje (el recien insertado o el existente) y el INSERT
--   final hace un producto cartesiano con los vinos tintos de graduacion
--   >= 14. ON CONFLICT DO NOTHING evita duplicar asociaciones si se repite.
--
-- Parametros: nombre = 'cordero al disco', temperatura = 16 grados,
--   tipo = 'tinto', graduacion >= 14. Cambiar los literales para otro maridaje.
-- Resultado obtenido: INSERT 0 1 en maridaje e INSERT 0 122 en vino_maridaje
--   (122 tintos del dataset cumplen graduacion >= 14).
-- ============================================================================
BEGIN;

-- Control previo: maridaje inexistente y cantidad de tintos que cumplen.
SELECT COUNT(*) AS maridajes_llamados_cordero
FROM maridaje
WHERE lower(nombre) = lower('cordero al disco');

SELECT COUNT(*) AS tintos_graduacion_14_o_mas
FROM vino
WHERE tipo = 'tinto'
  AND graduacion >= 14;

-- Sentencia
WITH nuevo_maridaje AS (
    INSERT INTO maridaje (nombre, temperatura_servicio)
    SELECT 'cordero al disco', 16
    WHERE NOT EXISTS (
        SELECT 1 FROM maridaje WHERE lower(nombre) = lower('cordero al disco')
    )
    RETURNING id
), maridaje_usado AS (
    SELECT id FROM nuevo_maridaje
    UNION ALL
    SELECT id FROM maridaje WHERE lower(nombre) = lower('cordero al disco')
)
INSERT INTO vino_maridaje (codigo_vino, id_maridaje)
SELECT v.codigo, m.id
FROM vino v
CROSS JOIN maridaje_usado m
WHERE v.tipo = 'tinto'
  AND v.graduacion >= 14
ON CONFLICT (codigo_vino, id_maridaje) DO NOTHING;

-- Control posterior
SELECT id, nombre, temperatura_servicio
FROM maridaje
WHERE lower(nombre) = lower('cordero al disco');

SELECT COUNT(*) AS vinos_asociados
FROM vino_maridaje vm
JOIN maridaje m ON m.id = vm.id_maridaje
WHERE lower(m.nombre) = lower('cordero al disco');

SELECT COUNT(*) AS asociados_a_tintos_14
FROM vino_maridaje vm
JOIN maridaje m ON m.id = vm.id_maridaje
JOIN vino v ON v.codigo = vm.codigo_vino
WHERE lower(m.nombre) = lower('cordero al disco')
  AND v.tipo = 'tinto'
  AND v.graduacion >= 14;

ROLLBACK;


-- ============================================================================
-- I3. Crear un nuevo comprobante con tres renglones para un cliente dado, en
--     la sala con ID 1, dentro de una transaccion y usando las funciones de
--     calculo.
--
-- Estrategia: se inserta la cabecera con subtotal y total en 0 y con
--   descuento_aplicado = fn_descuento_cliente(15234) (el cliente es comun, le
--   corresponde 0). Los tres renglones se insertan con el numero devuelto por
--   la cabecera; el trigger trg_renglon_comprobante_precio_lista fija
--   precio_unitario desde vino.precio, trg_validar_stock_venta controla el
--   stock de la sala y trg_actualizar_stock_y_totales_venta descuenta stock y
--   recalcula subtotal, descuento_total y total llamando a
--   fn_total_comprobante().
--
-- Parametros: id_cliente = 15234 (Joaquin Chavez, cliente_comun),
--   id_sala_venta = 1, vinos 123, 402 y 408 con cantidad 2 cada uno.
--   Cambiar los literales por otro cliente, sala o vinos con stock.
-- Resultado obtenido: INSERT 0 1 en comprobante (numero 150001) e INSERT 0 3
--   en renglon_comprobante. Total calculado: 154.166,00 (2 x 22.525,00 +
--   2 x 24.630,00 + 2 x 29.928,00), descuento 0. El stock de la sala 1 queda
--   en 278, 276 y 283 botellas para los vinos 123, 402 y 408.
-- ============================================================================
BEGIN;

-- Control previo: stock de los vinos en la sala 1 y ultimo comprobante.
SELECT codigo_vino, cantidad
FROM stock_sala
WHERE id_sala = 1
  AND codigo_vino IN (123, 402, 408)
ORDER BY codigo_vino;

SELECT COUNT(*) AS comprobantes_antes, MAX(numero) AS ultimo_numero
FROM comprobante;

-- Sentencia: cabecera. El descuento sale de la funcion de calculo.
INSERT INTO comprobante (fecha, subtotal, total, descuento_aplicado,
                         descuento_total, id_cliente, id_sala_venta)
VALUES (CURRENT_DATE, 0, 0, fn_descuento_cliente(15234), 0, 15234, 1)
RETURNING numero, fecha, id_cliente, id_sala_venta, descuento_aplicado;

-- Sentencia: tres renglones para el comprobante recien creado.
-- currval() recupera el numero generado por la identity en esta sesion.
INSERT INTO renglon_comprobante (numero_comprobante, codigo_vino, cantidad, precio_unitario)
VALUES (currval(pg_get_serial_sequence('comprobante', 'numero'))::int, 123, 2, 0),
       (currval(pg_get_serial_sequence('comprobante', 'numero'))::int, 402, 2, 0),
       (currval(pg_get_serial_sequence('comprobante', 'numero'))::int, 408, 2, 0);

-- Control posterior: cabecera recalculada por los triggers y funcion de total.
SELECT c.numero, c.fecha, c.subtotal, c.descuento_aplicado,
       c.descuento_total, c.total,
       fn_total_comprobante(c.numero) AS total_segun_funcion
FROM comprobante c
WHERE c.numero = currval(pg_get_serial_sequence('comprobante', 'numero'))::int;

SELECT numero_comprobante, codigo_vino, cantidad, precio_unitario, subtotal_renglon
FROM renglon_comprobante
WHERE numero_comprobante = currval(pg_get_serial_sequence('comprobante', 'numero'))::int
ORDER BY codigo_vino;

SELECT codigo_vino, cantidad
FROM stock_sala
WHERE id_sala = 1
  AND codigo_vino IN (123, 402, 408)
ORDER BY codigo_vino;

ROLLBACK;


-- ============================================================================
-- I4. Insertar una nueva bodega.
--
-- Estrategia: INSERT simple sobre bodega. La PK es el CUIT, con el dominio
--   cuit_dominio (11 digitos). No se repite ningun CUIT existente.
--
-- Parametros: cuit = '30999999991', razon_social, calle y numero. Cambiar los
--   literales para otra bodega.
-- Resultado obtenido: INSERT 0 1. La tabla pasa de 20 a 21 bodegas.
-- ============================================================================
BEGIN;

-- Control previo
SELECT COUNT(*) AS bodegas_antes FROM bodega;
SELECT COUNT(*) AS cuit_ya_existe FROM bodega WHERE cuit = '30999999991';

-- Sentencia
INSERT INTO bodega (cuit, razon_social, calle, numero)
VALUES ('30999999991', 'Bodega Viña del Plata S.A.', 'Ruta Provincial 15', '2450');

-- Control posterior
SELECT cuit, razon_social, calle, numero
FROM bodega
WHERE cuit = '30999999991';

SELECT COUNT(*) AS bodegas_despues FROM bodega;

ROLLBACK;


-- ============================================================================
-- I5. Insertar una nueva sala de venta.
--
-- Estrategia: INSERT simple sobre sala_venta. La FK codigo_postal exige una
--   localidad existente; se usa '5500' (Mendoza), que ya esta cargada.
--   La PK id es identity y se genera sola.
--
-- Parametros: calle = 'Calle Nueva', numero = '123', dia_cierre = 'jueves',
--   codigo_postal = '5500'. Cambiar los literales para otra sala.
-- Resultado obtenido: INSERT 0 1 con id 25. La tabla pasa de 24 a 25 salas.
-- ============================================================================
BEGIN;

-- Control previo
SELECT COUNT(*) AS salas_antes, MAX(id) AS ultima_sala FROM sala_venta;
SELECT codigo_postal, nombre FROM localidad WHERE codigo_postal = '5500';

-- Sentencia
INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
VALUES ('Calle Nueva', '123', 'jueves', '5500')
RETURNING id, calle, numero, dia_cierre, codigo_postal;

-- Control posterior
SELECT COUNT(*) AS salas_despues, MAX(id) AS ultima_sala FROM sala_venta;

ROLLBACK;


-- ============================================================================
-- I6. Crear un ingreso en confeccion de 120 botellas de un vino determinado
--     (por ejemplo "Malbec Reserva" de 750 ml), elaborado por una bodega dada
--     y trasladado por un transportista dado.
--
-- Estrategia: se inserta la cabecera de ingreso en estado 'en_confeccion'
--   (el trigger trg_validar_estado_documento exige que nazca en ese estado y
--   trg_fijar_fecha_documento fuerza fecha = CURRENT_DATE). Luego se inserta
--   el renglon con el codigo devuelto por la identity. Asi el ingreso queda
--   listo para que el procedimiento p_procesar_ingreso() lo pase a
--   'procesado' y sume stock al deposito.
--
-- Parametros: codigo_vino = 1 (Malbec Reserva, 750 ml, bodega 34100000158),
--   cantidad = 120, codigo_transportista = 1, cuit_bodega = '34100000158'.
--   Cambiar los literales por otro vino, bodega o transportista.
-- Resultado obtenido: INSERT 0 1 en ingreso e INSERT 0 1 en renglon_ingreso.
--   La fecha queda en CURRENT_DATE por el trigger. El ingreso queda en
--   'en_confeccion' con 120 botellas del vino 1.
-- ============================================================================
BEGIN;

-- Control previo: vino, bodega y transportista elegidos.
SELECT v.codigo, v.nombre, v.volumen_ml, v.cuit_bodega, t.codigo AS transportista
FROM vino v
CROSS JOIN transportista t
WHERE v.codigo = 1
  AND t.codigo = 1;

SELECT COUNT(*) AS ingresos_antes, MAX(codigo) AS ultimo_ingreso FROM ingreso;

-- Sentencia: cabecera del ingreso.
INSERT INTO ingreso (fecha, estado, codigo_transportista, cuit_bodega)
VALUES (CURRENT_DATE, 'en_confeccion', 1, '34100000158')
RETURNING codigo, fecha, estado, codigo_transportista, cuit_bodega;

-- Sentencia: renglon con las 120 botellas.
INSERT INTO renglon_ingreso (codigo_ingreso, codigo_vino, cantidad)
VALUES (currval(pg_get_serial_sequence('ingreso', 'codigo'))::int, 1, 120);

-- Control posterior
SELECT i.codigo, i.fecha, i.estado, i.codigo_transportista, i.cuit_bodega,
       ri.codigo_vino, ri.cantidad
FROM ingreso i
JOIN renglon_ingreso ri ON ri.codigo_ingreso = i.codigo
WHERE i.codigo = currval(pg_get_serial_sequence('ingreso', 'codigo'))::int;

SELECT COUNT(*) AS ingresos_despues, MAX(codigo) AS ultimo_ingreso FROM ingreso;

ROLLBACK;
