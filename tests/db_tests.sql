-- tests/db_tests.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Pruebas de las reglas de negocio RN-01 a RN-15 y de las decisiones de diseno
--
-- Requisitos:
--   * Base creada desde cero con 001_esquema.sql a 007_roles.sql.
--   * Ejecutar con psql:
--       psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f tests/db_tests.sql
--
-- Convencion:
--   * tests.ok(descripcion, sql)      -> la sentencia debe ejecutarse sin error.
--   * tests.fail(descripcion, sql, sqlstate) -> la sentencia debe fallar con ese SQLSTATE.
--   * Todo corre en una transaccion que termina con ROLLBACK: no deja datos de prueba.
--
-- SQLSTATE usados:
--   23001 = restrict_violation (ON DELETE RESTRICT; PostgreSQL puede devolver 23503 en versiones viejas)
--   23502 = not_null_violation
--   23503 = foreign_key_violation
--   23505 = unique_violation
--   23514 = check_violation
--   P0001 = raise_exception (triggers/procedimientos)
--
-- Para los borrados con ON DELETE RESTRICT se acepta 23001 o 23503 segun la version
-- de PostgreSQL. El helper recibe una lista separada por comas.

-- Frenar la ejecucion al primer error
\set ON_ERROR_STOP on

BEGIN;

SET client_encoding = 'UTF8';
SET CONSTRAINTS ALL DEFERRED;

CREATE SCHEMA IF NOT EXISTS tests;

-- ============================================================================
-- TEST QUE DEBE FUNCIONAR

CREATE OR REPLACE FUNCTION tests.ok(p_descripcion text, p_sql text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE p_sql;  -- se ejecuta la sentencia sql a probar
    RAISE NOTICE 'OK  %', p_descripcion;  -- si todo sale bien
EXCEPTION 
    -- si algo sale mal
    WHEN OTHERS THEN
        RAISE EXCEPTION 'FALLO %: se esperaba exito, pero dio SQLSTATE %: %',
            p_descripcion, SQLSTATE, SQLERRM;
END;
$$;

-- ============================================================================
-- TEST QUE DEBE FALLAR

CREATE OR REPLACE FUNCTION tests.fail(p_descripcion text, p_sql text, p_sqlstate text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;  -- se ejecuta la sentencia sql a probar
        -- si la sentencia funciona inesperadamente
        RAISE EXCEPTION 'FALLO %: se esperaba un error y la sentencia funciono', p_descripcion
            USING ERRCODE = 'P0001'; -- como la sentencia funciono, generamos un error 
    
    -- si en la ejecucion ocurre una excepcion
    EXCEPTION
        WHEN OTHERS THEN 
            -- si el error es el que generamos recien (P0001), falla el test
            IF SQLERRM LIKE 'FALLO %: se esperaba un error%' THEN
                RAISE; -- devuelve el mismo error
            END IF;

            -- si el error no es P0001, y tampoco es uno de los que esperabamos, el test falla
            IF p_sqlstate IS NOT NULL
               AND SQLSTATE <> ALL (string_to_array(p_sqlstate, ',')) THEN
                RAISE EXCEPTION 'FALLO %: se esperaba SQLSTATE %, se obtuvo %: %',
                    p_descripcion, p_sqlstate, SQLSTATE, SQLERRM;
            END IF;

            -- en otro caso, el error es el esperado, el test salio bien
            RAISE NOTICE 'OK  % [SQLSTATE %] %', p_descripcion, SQLSTATE, SQLERRM;
    END;
END;
$$;

-- ============================================================================
-- TEST QUE VERIFICA SI UNA CONDICION SE CUMPLE

CREATE OR REPLACE FUNCTION tests.assert(p_descripcion text, p_condicion boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_condicion IS DISTINCT FROM TRUE THEN  -- Si es false o null
        RAISE EXCEPTION 'FALLO %: la condicion no se cumple', p_descripcion;
    END IF;
    -- si la condicion se cumple el test funciona
    RAISE NOTICE 'OK  %', p_descripcion;
END;
$$;


-- ============================================================================
-- INSERTAMOS DATOS MINIMOS PARA HACER LAS PRUEBAS
-- Se usan IDs altos para no chocar con las secuencias IDENTITY que empiezan en 1

INSERT INTO bodega (cuit, razon_social, calle, numero)
VALUES ('20123456789', 'Bodega Test', 'Calle Bodega', '100');

INSERT INTO finca (id, nombre_finca, superficie, provincia, nombre_departamento)
OVERRIDING SYSTEM VALUE
VALUES (1001, 'Finca Test', 50.00, 'Mendoza', 'San Rafael');

INSERT INTO cepa (id, nombre, tipo)
OVERRIDING SYSTEM VALUE
VALUES (2001, 'Malbec', 'tinta'),
       (2002, 'Chardonnay', 'blanca');

INSERT INTO maridaje (id, nombre, temperatura_servicio)
OVERRIDING SYSTEM VALUE
VALUES (3001, 'Carnes rojas', 17);

INSERT INTO transportista (codigo, razon_social, cuit, email, telefono, calle, numero)
OVERRIDING SYSTEM VALUE
VALUES (4001, 'Transporte Test', '20987654321', 'transporte@test.com', '2604000000', 'Calle Transporte', '200');

-- La FK de localidad hacia empleado es diferible: se inserta antes el encargado
INSERT INTO localidad (codigo_postal, nombre, provincia, tipo_encargado, cuit_encargado)
VALUES ('5500', 'San Rafael', 'Mendoza', 'encargado_regional', '20111111111'),
       ('5501', 'San Rafael Norte', 'Mendoza', 'encargado_regional', '20111111111');

INSERT INTO sala_venta (id, calle, numero, dia_cierre, codigo_postal)
OVERRIDING SYSTEM VALUE
VALUES (5001, 'Sala Centro', '10', 'lunes', '5500'),
       (5002, 'Sala Norte', '20', 'martes', '5500');

INSERT INTO empleado (cuit, tipo, nombre, apellido, salario, fecha_ingreso, id_sala)
VALUES ('20111111111', 'encargado_regional', 'Ana', 'Perez', 150000.00, '2020-01-10', 5001);

-- Empleado de sala usado para probar que una localidad solo acepta encargados regionales
INSERT INTO empleado (cuit, tipo, nombre, apellido, salario, fecha_ingreso, id_sala)
VALUES ('20222222222', 'empleado_sala', 'Luis', 'Sala', 100000.00, '2021-02-01', 5001);

-- Clientes de los cuatro tipos. El subtipo se inserta a continuacion
INSERT INTO cliente (id, tipo, nombre, apellido, razon_social, calle, numero, estado_activo,
                     codigo_postal, tipo_documento, numero_documento)
OVERRIDING SYSTEM VALUE
VALUES (1001, 'cliente_comun', 'Juan', 'Perez', NULL, 'Calle Cliente', '1', TRUE,
        '5500', 'DNI', '11111111'),
       (1002, 'socio_club', 'Maria', 'Gomez', NULL, 'Calle Cliente', '2', TRUE,
        '5500', 'DNI', '22222222'),
       (1003, 'distribuidor', NULL, NULL, 'Distribuidora Test', 'Calle Cliente', '3', TRUE,
        '5500', 'CUIT', '33333333'),
       (1004, 'exportador', NULL, NULL, 'Exportadora Test', 'Calle Cliente', '4', TRUE,
        '5500', 'CUIT', '44444444'),
       (1005, 'exportador', NULL, NULL, 'Exportadora Premium', 'Calle Cliente', '5', TRUE,
        '5500', 'CUIT', '55555555'),
       (1006, 'cliente_comun', 'Cambio', 'Tipo', NULL, 'Calle Cliente', '6', TRUE,
        '5500', 'DNI', '66666666');

INSERT INTO cliente_comun (id_cliente, tipo)
VALUES (1001, 'cliente_comun'),
       (1006, 'cliente_comun');

INSERT INTO socio_club (id_cliente, tipo)
VALUES (1002, 'socio_club');

INSERT INTO distribuidor (id_cliente, tipo, zona_cobertura, numero_habilitacion)
VALUES (1003, 'distribuidor', 'Zona Sur', 'HAB-001');

INSERT INTO exportador (id_cliente, tipo, pais_destino, descuento_especial)
VALUES (1004, 'exportador', 'Chile', NULL),
       (1005, 'exportador', 'Brasil', 0.35);

-- Vinos de trabajo. Todos tienen composicion valida (la valida el trigger diferido).
INSERT INTO vino (codigo, nombre, tipo, añada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (2001, 'Malbec Test', 'tinto', 2020, 750, 14.00, 100.00, '20123456789'),
       (2002, 'Vino Composicion', 'tinto', 2021, 750, 13.00, 80.00, '20123456789'),
       (2003, 'Vino Ingreso', 'tinto', 2022, 750, 12.00, 70.00, '20123456789'),
       (2004, 'Vino Auditoria', 'blanco', 2023, 375, 11.00, 50.00, '20123456789'),
       (2005, 'Vino Venta', 'rosado', 2024, 1500, 10.00, 200.00, '20123456789'),
       (2006, 'Vino Stock', 'tinto', 2025, 750, 13.50, 10.00, '20123456789');

INSERT INTO composicion (codigo_vino, id_cepa, porcentaje)
VALUES (2001, 2001, 60.00), (2001, 2002, 40.00),
       (2002, 2001, 100.00),
       (2003, 2001, 100.00),
       (2004, 2002, 100.00),
       (2005, 2001, 100.00),
       (2006, 2001, 100.00);

INSERT INTO stock_deposito (codigo_vino, cantidad)
VALUES (2001, 1000),
       (2002, 0),
       (2003, 0),
       (2005, 50),
       (2006, 20);

INSERT INTO stock_sala (id_sala, codigo_vino, cantidad)
VALUES (5001, 2001, 100),
       (5001, 2005, 20),
       (5001, 2006, 10),
       (5002, 2001, 5);

-- Ingreso en confeccion con un renglon: sirve para RN-12 y RN-14.
INSERT INTO ingreso (codigo, fecha, estado, codigo_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (4001, CURRENT_DATE, 'en_confeccion', 4001, '20123456789');

INSERT INTO renglon_ingreso (codigo_ingreso, codigo_vino, cantidad)
VALUES (4001, 2001, 10);

-- Transferencia en confeccion con un renglon: sirve para RN-12 y RN-14.
INSERT INTO transferencia (numero, fecha_confeccion, estado, id_sala_venta)
OVERRIDING SYSTEM VALUE
VALUES (5001, CURRENT_DATE, 'en_confeccion', 5001);

INSERT INTO renglon_transferencia (numero_transferencia, codigo_vino, cantidad)
VALUES (5001, 2001, 5);

-- Comprobante de venta base. El trigger calcula totales y descuenta stock.
INSERT INTO comprobante (numero, fecha, id_cliente, id_sala_venta)
OVERRIDING SYSTEM VALUE
VALUES (6001, CURRENT_DATE, 1001, 5001);

INSERT INTO renglon_comprobante (numero_comprobante, codigo_vino, cantidad, precio_unitario)
VALUES (6001, 2001, 2, 100.00);

-- Permiso valido del exportador 1004.
INSERT INTO permiso (codigo, id_exportador, fecha_emision, fecha_vencimiento)
OVERRIDING SYSTEM VALUE
VALUES (7001, 1004, CURRENT_DATE - 10, CURRENT_DATE + 10);

-- Parcela y lote base para RN-04 y RN-14.
INSERT INTO parcela (numero_parcela, id_finca, superficie, año_plantacion, id_cepa)
VALUES (1, 1001, 5.00, 2010, 2001);

INSERT INTO lote (numero_lote, fecha, kg_cosecha, cuit_bodega, id_finca, numero_parcela)
OVERRIDING SYSTEM VALUE
VALUES (9001, '2026-01-10', 1000.00, '20123456789', 1001, 1);


-- ============================================================================
-- RN-01: precio de vino unico para toda la red y mayor que cero

-- Espera: 23514 (check_violation) por ck_vino_precio_positivo.
SELECT tests.fail(
    'RN-01: rechaza vino con precio 0',
    $sql$INSERT INTO vino (nombre, tipo, añada, volumen_ml, graduacion, precio, cuit_bodega)
         VALUES ('Vino Precio Cero', 'tinto', 2020, 750, 13.00, 0, '20123456789')$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_vino_precio_positivo.
SELECT tests.fail(
    'RN-01: rechaza vino con precio negativo',
    $sql$INSERT INTO vino (nombre, tipo, añada, volumen_ml, graduacion, precio, cuit_bodega)
         VALUES ('Vino Precio Negativo', 'tinto', 2020, 750, 13.00, -1, '20123456789')$sql$,
    '23514'
);

-- Espera: exito. La venta usa el precio del vino aunque la API mande otro precio
INSERT INTO comprobante (numero, fecha, id_cliente, id_sala_venta)
OVERRIDING SYSTEM VALUE  -- para poder forzar el valor del numero de comprobante
VALUES (6006, CURRENT_DATE, 1001, 5002);

SELECT tests.ok(
    'RN-01: la venta desde otra sala usa el precio de lista del vino',
    $sql$INSERT INTO renglon_comprobante (numero_comprobante, codigo_vino, cantidad, precio_unitario)
         VALUES (6006, 2001, 1, 1.00)$sql$
);

SELECT tests.assert(
    'RN-01: precio_unitario quedo en 100 aunque se envio 1',
    (SELECT precio_unitario = 100.00 FROM renglon_comprobante
      WHERE numero_comprobante = 6006 AND codigo_vino = 2001)
);

-- Espera: 23505 (unique_violation) por uk_vino_nombre_añada_volumen.
SELECT tests.fail(
    'RN-01: un vino se distingue por nombre, añada y volumen',
    $sql$INSERT INTO vino (nombre, tipo, añada, volumen_ml, graduacion, precio, cuit_bodega)
         VALUES ('Malbec Test', 'tinto', 2020, 750, 13.00, 100.00, '20123456789')$sql$,
    '23505'
);


-- ============================================================================
-- RN-02: una sala pertenece a una localidad y cada localidad tiene un encargado

-- Espera: 23503 (foreign_key_violation) por fk_sala_venta_localidad.
SELECT tests.fail(
    'RN-02: rechaza sala con localidad inexistente',
    $sql$INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
         VALUES ('Sala Fantasma', '1', 'lunes', '9999')$sql$,
    '23503'
);

-- Espera: 23505 (unique_violation) porque codigo_postal es PK de localidad.
SELECT tests.fail(
    'RN-02: no se duplica una localidad',
    $sql$INSERT INTO localidad (codigo_postal, nombre, provincia, tipo_encargado, cuit_encargado)
         VALUES ('5500', 'San Rafael Duplicada', 'Mendoza', 'encargado_regional', '20111111111')$sql$,
    '23505'
);

-- Espera: exito. Una misma localidad puede tener varias salas.
SELECT tests.assert(
    'RN-02: una localidad puede tener varias salas',
    (SELECT COUNT(*) = 2 FROM sala_venta WHERE codigo_postal = '5500')
);

-- Espera: error diferido (P0001) porque el empleado 20222222222 es empleado_sala,
-- no encargado_regional
DO $$
BEGIN
    BEGIN
        INSERT INTO localidad (codigo_postal, nombre, provincia, tipo_encargado, cuit_encargado)
        VALUES ('5600', 'Localidad Invalida', 'Mendoza', 'encargado_regional', '20222222222');

        SET CONSTRAINTS fk_localidad_encargado IMMEDIATE;  -- forzamos el chequeo inmediato (no diferido)

        -- si por algun problema la restriccion no se chequea inmediatamente
        -- lanzamos un error
        RAISE EXCEPTION 'FALLO RN-02: se acepto un encargado que no es encargado_regional';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'FALLO RN-02:%' THEN
                RAISE;
            END IF;
            -- si el error no fue por la FK del empleado a su tipo, falla
            IF SQLSTATE <> '23503' THEN
                RAISE EXCEPTION 'FALLO RN-02: se esperaba SQLSTATE 23503, se obtuvo %: %', SQLSTATE, SQLERRM;
            END IF;
            -- si el error es por FK entonces el test funciona
            RAISE NOTICE 'OK  RN-02: localidad rechaza encargado no regional [SQLSTATE %]', SQLSTATE;
    END;
END;
$$;

-- Espera: 23001/23503 (restrict/foreign_key) por fk_sala_venta_localidad al borrar
SELECT tests.fail(
    'RN-02: no se borra una localidad con salas',
    $sql$DELETE FROM localidad WHERE codigo_postal = '5500'$sql$,
    '23001,23503'
);


-- ============================================================================
-- RN-03: cada empleado trabaja en una sola sala

-- Espera: 23502 (not_null_violation) porque id_sala es NOT NULL.
SELECT tests.fail(
    'RN-03: rechaza empleado sin sala',
    $sql$INSERT INTO empleado (cuit, tipo, nombre, apellido, salario, fecha_ingreso, id_sala)
         VALUES ('20333333333', 'empleado_sala', 'Sin', 'Sala', 1000.00, CURRENT_DATE, NULL)$sql$,
    '23502'
);

-- Espera: 23503 (foreign_key_violation) por fk_empleado_sala_venta.
SELECT tests.fail(
    'RN-03: rechaza empleado con sala inexistente',
    $sql$INSERT INTO empleado (cuit, tipo, nombre, apellido, salario, fecha_ingreso, id_sala)
         VALUES ('20333333333', 'empleado_sala', 'Sala', 'Fantasma', 1000.00, CURRENT_DATE, 9999)$sql$,
    '23503'
);

-- Espera: 23001/23503 (restrict/foreign_key) por fk_empleado_sala_venta al borrar la sala.
SELECT tests.fail(
    'RN-03: no se borra una sala con empleados',
    $sql$DELETE FROM sala_venta WHERE id = 5001$sql$,
    '23001,23503'
);


-- ============================================================================
-- RN-04: una parcela tiene una sola cepa y se cosecha una vez por campana

-- Espera: 23505 (unique_violation) por uk_lote_parcela_finca_campaña.
SELECT tests.fail(
    'RN-04: rechaza dos lotes de la misma parcela en la misma campana',
    $sql$INSERT INTO lote (fecha, kg_cosecha, cuit_bodega, id_finca, numero_parcela)
         VALUES ('2026-02-01', 500.00, '20123456789', 1001, 1)$sql$,
    '23505'
);

-- Espera: exito. La misma parcela puede cosecharse en otra campana.
SELECT tests.ok(
    'RN-04: permite cosechar la misma parcela en otra campana',
    $sql$INSERT INTO lote (fecha, kg_cosecha, cuit_bodega, id_finca, numero_parcela)
         VALUES ('2027-02-01', 500.00, '20123456789', 1001, 1)$sql$
);

-- Espera: 23505 (unique_violation) porque la PK de parcela es (id_finca, numero_parcela).
SELECT tests.fail(
    'RN-04: no se duplica la parcela dentro de la finca',
    $sql$INSERT INTO parcela (numero_parcela, id_finca, superficie, año_plantacion, id_cepa)
         VALUES (1, 1001, 3.00, 2011, 2002)$sql$,
    '23505'
);

-- Espera: 23503 (foreign_key_violation) por fk_parcela_cepa.
SELECT tests.fail(
    'RN-04: rechaza parcela con cepa inexistente',
    $sql$INSERT INTO parcela (numero_parcela, id_finca, superficie, año_plantacion, id_cepa)
         VALUES (99, 1001, 3.00, 2011, 9999)$sql$,
    '23503'
);

-- Espera: 23001/23503 (restrict/foreign_key) por fk_parcela_cepa al borrar la cepa.
SELECT tests.fail(
    'RN-04: no se borra una cepa usada por una parcela',
    $sql$DELETE FROM cepa WHERE id = 2001$sql$,
    '23001,23503'
);

-- ============================================================================
-- RN-05: los porcentajes de composicion suman exactamente 100

-- Espera: P0001 al forzar el constraint trigger diferido.
DO $$
BEGIN
    BEGIN
        INSERT INTO vino (codigo, nombre, tipo, añada, volumen_ml, graduacion, precio, cuit_bodega)
        OVERRIDING SYSTEM VALUE
        VALUES (2010, 'Vino Composicion Invalida', 'tinto', 2020, 750, 13.00, 50.00, '20123456789');

        INSERT INTO composicion (codigo_vino, id_cepa, porcentaje)
        VALUES (2010, 2001, 60.00), (2010, 2002, 30.00);

        SET CONSTRAINTS trg_composicion_suma_100 IMMEDIATE; -- forzamos el chequeo inmediato

        -- si salio mal el chequeo
        RAISE EXCEPTION 'FALLO RN-05: se acepto una composicion que suma 90';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'FALLO RN-05:%' THEN
                RAISE;
            END IF;
            -- si el fallo capturado es otro
            IF SQLSTATE <> 'P0001' THEN
                RAISE EXCEPTION 'FALLO RN-05: se esperaba SQLSTATE P0001, se obtuvo %: %', SQLSTATE, SQLERRM;
            END IF;
            RAISE NOTICE 'OK  RN-05: rechaza composicion que suma 90 [SQLSTATE %]', SQLSTATE;
    END;
END;
$$;

-- Espera: exito. 60 + 40 = 100.
DO $$
BEGIN
    INSERT INTO vino (codigo, nombre, tipo, añada, volumen_ml, graduacion, precio, cuit_bodega)
    OVERRIDING SYSTEM VALUE
    VALUES (2011, 'Vino Composicion Valida', 'tinto', 2020, 750, 13.00, 50.00, '20123456789');

    INSERT INTO composicion (codigo_vino, id_cepa, porcentaje)
    VALUES (2011, 2001, 60.00), (2011, 2002, 40.00);

    SET CONSTRAINTS trg_composicion_suma_100 IMMEDIATE;
    SET CONSTRAINTS trg_composicion_suma_100 DEFERRED;

    RAISE NOTICE 'OK  RN-05: acepta composicion que suma 100';
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'FALLO RN-05: no acepto la composicion valida: % (%)', SQLERRM, SQLSTATE;
END;
$$;

-- Espera: P0001 al borrar una fila y dejar la composicion en 60.
DO $$
BEGIN
    BEGIN
        DELETE FROM composicion
        WHERE codigo_vino = 2011 AND id_cepa = 2002;

        SET CONSTRAINTS trg_composicion_suma_100 IMMEDIATE;

        RAISE EXCEPTION 'FALLO RN-05: se acepto una composicion que quedo en 60';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'FALLO RN-05:%' THEN
                RAISE;
            END IF;
            IF SQLSTATE <> 'P0001' THEN
                RAISE EXCEPTION 'FALLO RN-05: se esperaba SQLSTATE P0001, se obtuvo %: %', SQLSTATE, SQLERRM;
            END IF;
            RAISE NOTICE 'OK  RN-05: rechaza borrar una fila y quedar en incompleto [SQLSTATE %]', SQLSTATE;
    END;
END;
$$;


-- ============================================================================
-- RN-06: descuento segun tipo de cliente

SELECT tests.assert('RN-06: cliente comun tiene 0%', fn_descuento_cliente(1001) = 0.00);
SELECT tests.assert('RN-06: socio club tiene 10%', fn_descuento_cliente(1002) = 0.10);
SELECT tests.assert('RN-06: distribuidor tiene 20%', fn_descuento_cliente(1003) = 0.20);
SELECT tests.assert('RN-06: exportador sin descuento especial tiene 30%', fn_descuento_cliente(1004) = 0.30);
SELECT tests.assert('RN-06: exportador con descuento especial tiene 35%', fn_descuento_cliente(1005) = 0.35);

-- Espera: 23514 (check_violation) por ck_exportador_descuento_rango.
DO $$
BEGIN
    BEGIN
        INSERT INTO cliente (id, tipo, razon_social, calle, numero, estado_activo,
                             codigo_postal, tipo_documento, numero_documento)
        OVERRIDING SYSTEM VALUE
        VALUES (1008, 'exportador', 'Exportadora Invalida', 'Calle', '8', TRUE,
                '5500', 'CUIT', '88888888');

        INSERT INTO exportador (id_cliente, tipo, pais_destino, descuento_especial)
        VALUES (1008, 'exportador', 'Chile', 0.40);

        RAISE EXCEPTION 'FALLO RN-06: se acepto descuento especial 0.40';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'FALLO RN-06:%' THEN
                RAISE;
            END IF;
            IF SQLSTATE <> '23514' THEN
                RAISE EXCEPTION 'FALLO RN-06: se esperaba SQLSTATE 23514, se obtuvo %: %', SQLSTATE, SQLERRM;
            END IF;
            RAISE NOTICE 'OK  RN-06: rechaza descuento especial 0.40 [SQLSTATE %]', SQLSTATE;
    END;
END;
$$;

-- Espera: P0001. p_crear_cliente valida el rango antes de insertar.
SELECT tests.fail(
    'RN-06: p_crear_cliente rechaza descuento especial 0.40',
    $sql$CALL p_crear_cliente('exportador', 'Calle', '9', '5500', 'CUIT', '99999999',
                              NULL, NULL, 'Exportadora Invalida', NULL, NULL, 'Chile', 0.40)$sql$,
    'P0001'
);

-- Espera: 23505 (unique_violation) por el indice parcial de documento activo.
SELECT tests.fail(
    'RN-06: no se puede repetir documento de un cliente activo',
    $sql$CALL p_crear_cliente('cliente_comun', 'Calle', '10', '5500', 'DNI', '11111111',
                              'Otro', 'Cliente', NULL, NULL, NULL, NULL, NULL)$sql$,
    '23505'
);

-- Espera: exito. Alta completa de un cliente y su subtipo.
SELECT tests.ok(
    'RN-06: p_crear_cliente crea supertipo y subtipo',
    $sql$CALL p_crear_cliente('cliente_comun', 'Calle', '11', '5500', 'DNI', '77777777',
                              'Nuevo', 'Cliente', NULL, NULL, NULL, NULL, NULL)$sql$
);

SELECT tests.assert(
    'RN-06: el cliente creado tiene exactamente una fila de subtipo',
    (SELECT COUNT(*) = 1
       FROM cliente c
       JOIN cliente_comun cc ON cc.id_cliente = c.id
      WHERE c.numero_documento = '77777777' AND c.estado_activo)
);

-- Espera: exito. Cambio de tipo con versionado: el anterior queda inactivo.
SELECT tests.ok(
    'RN-06: p_cambiar_tipo_cliente versiona el cliente',
    $sql$CALL p_cambiar_tipo_cliente(1006, 'distribuidor',
                                     NULL, NULL, 'Distribuidora Cambio',
                                     'Zona Centro', 'HAB-002', NULL, NULL)$sql$
);

SELECT tests.assert(
    'RN-06: el cliente 1006 quedo inactivo',
    (SELECT NOT estado_activo FROM cliente WHERE id = 1006)
);

SELECT tests.assert(
    'RN-06: existe un unico cliente activo con el documento 66666666 y es distribuidor',
    (SELECT COUNT(*) = 1
       FROM cliente c
       JOIN distribuidor d ON d.id_cliente = c.id
      WHERE c.numero_documento = '66666666'
        AND c.estado_activo
        AND c.tipo = 'distribuidor')
);

-- Espera: P0001. No se puede volver a cambiar un cliente inactivo.
SELECT tests.fail(
    'RN-06: p_cambiar_tipo_cliente rechaza cliente inactivo',
    $sql$CALL p_cambiar_tipo_cliente(1006, 'socio_club',
                                     'Cambio', 'Tipo', NULL, NULL, NULL, NULL, NULL)$sql$,
    'P0001'
);

-- Espera: P0001. No se puede cambiar al mismo tipo.
SELECT tests.fail(
    'RN-06: p_cambiar_tipo_cliente rechaza el mismo tipo',
    $sql$CALL p_cambiar_tipo_cliente(1005, 'exportador',
                                     NULL, NULL, 'Exportadora Premium',
                                     NULL, NULL, 'Brasil', 0.35)$sql$,
    'P0001'
);

-- Espera: P0001 al forzar el constraint trigger de totalidad de la jerarquia.
DO $$
BEGIN
    BEGIN
        INSERT INTO cliente (id, tipo, nombre, apellido, calle, numero, estado_activo,
                             codigo_postal, tipo_documento, numero_documento)
        OVERRIDING SYSTEM VALUE
        VALUES (1009, 'cliente_comun', 'Sin', 'Subtipo', 'Calle', '12', TRUE,
                '5500', 'DNI', '99999999');

        SET CONSTRAINTS trg_cliente_subtipo_total IMMEDIATE;

        RAISE EXCEPTION 'FALLO RN-06: se acepto un cliente sin fila de subtipo';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'FALLO RN-06:%' THEN
                RAISE;
            END IF;
            IF SQLSTATE <> 'P0001' THEN
                RAISE EXCEPTION 'FALLO RN-06: se esperaba SQLSTATE P0001, se obtuvo %: %', SQLSTATE, SQLERRM;
            END IF;
            RAISE NOTICE 'OK  RN-06: rechaza cliente sin subtipo [SQLSTATE %]', SQLSTATE;
    END;
END;
$$;


-- ============================================================================
-- RN-07: un exportador puede tener varios permisos y el vencimiento es posterior

-- Espera: 23514 (check_violation) por ck_permiso_fechas.
SELECT tests.fail(
    'RN-07: rechaza permiso con vencimiento igual a la emision',
    $sql$INSERT INTO permiso (id_exportador, fecha_emision, fecha_vencimiento)
         VALUES (1004, CURRENT_DATE, CURRENT_DATE)$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_permiso_fechas.
SELECT tests.fail(
    'RN-07: rechaza permiso con vencimiento anterior a la emision',
    $sql$INSERT INTO permiso (id_exportador, fecha_emision, fecha_vencimiento)
         VALUES (1004, CURRENT_DATE, CURRENT_DATE - 1)$sql$,
    '23514'
);

-- Espera: exito. Un exportador puede tener varios permisos.
SELECT tests.ok(
    'RN-07: permite un segundo permiso al mismo exportador',
    $sql$INSERT INTO permiso (id_exportador, fecha_emision, fecha_vencimiento)
         VALUES (1004, CURRENT_DATE, CURRENT_DATE + 30)$sql$
);

SELECT tests.ok(
    'RN-07: permite un tercer permiso al mismo exportador',
    $sql$INSERT INTO permiso (id_exportador, fecha_emision, fecha_vencimiento)
         VALUES (1004, CURRENT_DATE + 1, CURRENT_DATE + 60)$sql$
);


-- ============================================================================
-- RN-08: el total del comprobante se calcula, no se carga a mano

SELECT tests.assert(
    'RN-08: el comprobante base 6001 quedo con total 200',
    (SELECT total = 200.00 AND subtotal = 200.00 AND descuento_total = 0.00
       FROM comprobante WHERE numero = 6001)
);

-- Espera: exito. Venta a socio con 10% de descuento.
INSERT INTO comprobante (numero, fecha, id_cliente, id_sala_venta)
OVERRIDING SYSTEM VALUE
VALUES (6002, CURRENT_DATE, 1002, 5001);

SELECT tests.ok(
    'RN-08: carga un renglon a un socio',
    $sql$INSERT INTO renglon_comprobante (numero_comprobante, codigo_vino, cantidad, precio_unitario)
         VALUES (6002, 2001, 1, 100.00)$sql$
);

SELECT tests.assert(
    'RN-08: el socio obtiene subtotal 100, descuento 10 y total 90',
    (SELECT subtotal = 100.00 AND descuento_aplicado = 0.10
            AND descuento_total = 10.00 AND total = 90.00
       FROM comprobante WHERE numero = 6002)
);

SELECT tests.assert(
    'RN-08: fn_total_comprobante devuelve 90 para el comprobante 6002',
    fn_total_comprobante(6002) = 90.00
);

-- Espera: exito. Aunque la API mande precio 1, el trigger usa el precio de lista.
INSERT INTO comprobante (numero, fecha, id_cliente, id_sala_venta)
OVERRIDING SYSTEM VALUE
VALUES (6003, CURRENT_DATE, 1001, 5001);

SELECT tests.ok(
    'RN-08: ignora el precio enviado por la API',
    $sql$INSERT INTO renglon_comprobante (numero_comprobante, codigo_vino, cantidad, precio_unitario)
         VALUES (6003, 2001, 1, 1.00)$sql$
);

SELECT tests.assert(
    'RN-08: el renglon uso precio 100 y el total quedo en 100',
    (SELECT rc.precio_unitario = 100.00 AND c.total = 100.00
       FROM renglon_comprobante rc
       JOIN comprobante c ON c.numero = rc.numero_comprobante
      WHERE rc.numero_comprobante = 6003 AND rc.codigo_vino = 2001)
);

-- Espera: 23514 (check_violation) por ck_comprobante_total_calculo.
SELECT tests.fail(
    'RN-08: rechaza un total cargado a mano que no cierra',
    $sql$INSERT INTO comprobante (numero, fecha, subtotal, total, descuento_aplicado, descuento_total,
                                   id_cliente, id_sala_venta)
         OVERRIDING SYSTEM VALUE
         VALUES (6004, CURRENT_DATE, 100.00, 999.00, 0.00, 0.00, 1001, 5001)$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_comprobante_descuento_aplicado.
SELECT tests.fail(
    'RN-08: rechaza descuento aplicado fuera de 0..1',
    $sql$INSERT INTO comprobante (numero, fecha, subtotal, total, descuento_aplicado, descuento_total,
                                   id_cliente, id_sala_venta)
         OVERRIDING SYSTEM VALUE
         VALUES (6005, CURRENT_DATE, 0.00, 0.00, 1.50, 0.00, 1001, 5001)$sql$,
    '23514'
);

-- ============================================================================
-- RN-09: no se vende mas que el stock de la sala y el stock no es negativo

-- Espera: exito. Venta de 3 unidades del vino 2006 en la sala 5001.
INSERT INTO comprobante (numero, fecha, id_cliente, id_sala_venta)
OVERRIDING SYSTEM VALUE
VALUES (6010, CURRENT_DATE, 1001, 5001);

SELECT tests.ok(
    'RN-09: vende 3 unidades con stock suficiente',
    $sql$INSERT INTO renglon_comprobante (numero_comprobante, codigo_vino, cantidad, precio_unitario)
         VALUES (6010, 2006, 3, 10.00)$sql$
);

SELECT tests.assert(
    'RN-09: el stock de la sala bajo de 10 a 7',
    fn_stock_sala(5001, 2006) = 7
);

-- Cabecera valida para probar la sobreventa.
INSERT INTO comprobante (numero, fecha, id_cliente, id_sala_venta)
OVERRIDING SYSTEM VALUE
VALUES (6011, CURRENT_DATE, 1001, 5001);

-- Espera: P0001 por trg_validar_stock_venta.
SELECT tests.fail(
    'RN-09: rechaza vender mas que el stock de la sala',
    $sql$INSERT INTO renglon_comprobante (numero_comprobante, codigo_vino, cantidad, precio_unitario)
         VALUES (6011, 2006, 9999, 10.00)$sql$,
    'P0001'
);

SELECT tests.assert(
    'RN-09: el stock no cambio tras el intento de sobreventa',
    fn_stock_sala(5001, 2006) = 7
);

-- Espera: 23514 (check_violation) por ck_stock_sala_cantidad_no_negativa.
SELECT tests.fail(
    'RN-09: rechaza stock de sala negativo',
    $sql$UPDATE stock_sala SET cantidad = -1 WHERE id_sala = 5001 AND codigo_vino = 2006$sql$,
    '23514'
);

-- Espera: P0001. La transferencia pide mas que el stock del deposito.
INSERT INTO transferencia (numero, fecha_confeccion, estado, id_sala_venta)
OVERRIDING SYSTEM VALUE
VALUES (5010, CURRENT_DATE, 'en_confeccion', 5001);

INSERT INTO renglon_transferencia (numero_transferencia, codigo_vino, cantidad)
VALUES (5010, 2006, 9999);

UPDATE transferencia SET estado = 'terminado' WHERE numero = 5010;

SELECT tests.fail(
    'RN-09: la transferencia no puede dejar stock de deposito negativo',
    $sql$CALL p_procesar_transferencia(5010)$sql$,
    'P0001'
);

SELECT tests.assert(
    'RN-09: el deposito no se modifico tras la transferencia fallida',
    (SELECT cantidad = 20 FROM stock_deposito WHERE codigo_vino = 2006)
);


-- ============================================================================
-- RN-10: solo un ingreso terminado impacta el deposito y pasa a procesado

-- Espera: P0001 por trg_ingreso_estado_valido.
SELECT tests.fail(
    'RN-10: un ingreso no puede nacer terminado',
    $sql$INSERT INTO ingreso (fecha, estado, codigo_transportista, cuit_bodega)
         VALUES (CURRENT_DATE, 'terminado', 4001, '20123456789')$sql$,
    'P0001'
);

-- Espera: P0001. No se puede saltar de en_confeccion a procesado.
SELECT tests.fail(
    'RN-10: rechaza transicion en_confeccion -> procesado',
    $sql$UPDATE ingreso SET estado = 'procesado' WHERE codigo = 4001$sql$,
    'P0001'
);

-- Espera: exito. Transicion permitida en_confeccion -> terminado.
SELECT tests.ok(
    'RN-10: permite transicion en_confeccion -> terminado',
    $sql$UPDATE ingreso SET estado = 'terminado' WHERE codigo = 4001$sql$
);

-- Espera: P0001. El ingreso 4011 sigue en confeccion.
INSERT INTO ingreso (codigo, fecha, estado, codigo_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (4011, CURRENT_DATE, 'en_confeccion', 4001, '20123456789');

INSERT INTO renglon_ingreso (codigo_ingreso, codigo_vino, cantidad)
VALUES (4011, 2003, 1);

SELECT tests.fail(
    'RN-10: p_procesar_ingreso rechaza un ingreso no terminado',
    $sql$CALL p_procesar_ingreso(4011)$sql$,
    'P0001'
);

-- Espera: exito. Ingreso terminado con 7 unidades del vino 2003.
INSERT INTO ingreso (codigo, fecha, estado, codigo_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (4012, CURRENT_DATE, 'en_confeccion', 4001, '20123456789');

INSERT INTO renglon_ingreso (codigo_ingreso, codigo_vino, cantidad)
VALUES (4012, 2003, 7);

UPDATE ingreso SET estado = 'terminado' WHERE codigo = 4012;

SELECT tests.ok(
    'RN-10: procesa un ingreso terminado',
    $sql$CALL p_procesar_ingreso(4012)$sql$
);

SELECT tests.assert(
    'RN-10: el ingreso 4012 quedo procesado',
    (SELECT estado = 'procesado' FROM ingreso WHERE codigo = 4012)
);

SELECT tests.assert(
    'RN-10: el deposito del vino 2003 subio a 7',
    (SELECT cantidad = 7 FROM stock_deposito WHERE codigo_vino = 2003)
);

-- Espera: P0001. No se procesa dos veces.
SELECT tests.fail(
    'RN-10: rechaza procesar dos veces el mismo ingreso',
    $sql$CALL p_procesar_ingreso(4012)$sql$,
    'P0001'
);

-- Espera: P0001. Un ingreso terminado sin renglones no se procesa.
INSERT INTO ingreso (codigo, fecha, estado, codigo_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (4013, CURRENT_DATE, 'en_confeccion', 4001, '20123456789');

UPDATE ingreso SET estado = 'terminado' WHERE codigo = 4013;

SELECT tests.fail(
    'RN-10: rechaza procesar un ingreso sin renglones',
    $sql$CALL p_procesar_ingreso(4013)$sql$,
    'P0001'
);

-- Espera: P0001. No se retrocede de procesado a en_confeccion.
SELECT tests.fail(
    'RN-10: rechaza retroceder de procesado a en_confeccion',
    $sql$UPDATE ingreso SET estado = 'en_confeccion' WHERE codigo = 4012$sql$,
    'P0001'
);

-- Espera: P0001. Ingreso inexistente.
SELECT tests.fail(
    'RN-10: p_procesar_ingreso rechaza un ingreso inexistente',
    $sql$CALL p_procesar_ingreso(99999)$sql$,
    'P0001'
);


-- ============================================================================
-- RN-11: transferencias, fecha de confeccion y stock

-- Espera: P0001 por trg_transferencia_estado_valido.
SELECT tests.fail(
    'RN-11: una transferencia no puede nacer terminada',
    $sql$INSERT INTO transferencia (fecha_confeccion, estado, id_sala_venta)
         VALUES (CURRENT_DATE, 'terminado', 5001)$sql$,
    'P0001'
);

-- Espera: exito. La fecha enviada por la API se reemplaza por la actual.
INSERT INTO transferencia (numero, fecha_confeccion, estado, id_sala_venta)
OVERRIDING SYSTEM VALUE
VALUES (5021, '2000-01-01', 'en_confeccion', 5001);

SELECT tests.assert(
    'RN-11: la fecha de confeccion se fuerza a la actual',
    (SELECT fecha_confeccion = CURRENT_DATE FROM transferencia WHERE numero = 5021)
);

-- Espera: P0001 por trg_transferencia_fecha_confeccion.
SELECT tests.fail(
    'RN-11: no se puede modificar la fecha de confeccion',
    $sql$UPDATE transferencia SET fecha_confeccion = CURRENT_DATE - 1 WHERE numero = 5021$sql$,
    'P0001'
);

-- Espera: P0001. No se puede saltar de en_confeccion a procesado.
SELECT tests.fail(
    'RN-11: rechaza transicion en_confeccion -> procesado',
    $sql$UPDATE transferencia SET estado = 'procesado' WHERE numero = 5021$sql$,
    'P0001'
);

-- Espera: P0001. La transferencia 5021 sigue en confeccion.
SELECT tests.fail(
    'RN-11: p_procesar_transferencia rechaza una transferencia no terminada',
    $sql$CALL p_procesar_transferencia(5021)$sql$,
    'P0001'
);

-- Espera: exito. Transferencia terminada de 2 unidades del vino 2003.
INSERT INTO transferencia (numero, fecha_confeccion, estado, id_sala_venta)
OVERRIDING SYSTEM VALUE
VALUES (5022, CURRENT_DATE, 'en_confeccion', 5001);

INSERT INTO renglon_transferencia (numero_transferencia, codigo_vino, cantidad)
VALUES (5022, 2003, 2);

UPDATE transferencia SET estado = 'terminado' WHERE numero = 5022;

SELECT tests.ok(
    'RN-11: procesa una transferencia terminada',
    $sql$CALL p_procesar_transferencia(5022)$sql$
);

SELECT tests.assert(
    'RN-11: la transferencia 5022 quedo procesada',
    (SELECT estado = 'procesado' FROM transferencia WHERE numero = 5022)
);

SELECT tests.assert(
    'RN-11: el deposito del vino 2003 bajo de 7 a 5',
    (SELECT cantidad = 5 FROM stock_deposito WHERE codigo_vino = 2003)
);

SELECT tests.assert(
    'RN-11: la sala 5001 recibio 2 unidades del vino 2003',
    fn_stock_sala(5001, 2003) = 2
);

-- Espera: P0001. No se procesa dos veces.
SELECT tests.fail(
    'RN-11: rechaza procesar dos veces la misma transferencia',
    $sql$CALL p_procesar_transferencia(5022)$sql$,
    'P0001'
);

-- Espera: P0001. Transferencia terminada sin renglones.
INSERT INTO transferencia (numero, fecha_confeccion, estado, id_sala_venta)
OVERRIDING SYSTEM VALUE
VALUES (5023, CURRENT_DATE, 'en_confeccion', 5001);

UPDATE transferencia SET estado = 'terminado' WHERE numero = 5023;

SELECT tests.fail(
    'RN-11: rechaza procesar una transferencia sin renglones',
    $sql$CALL p_procesar_transferencia(5023)$sql$,
    'P0001'
);

-- Espera: P0001. No se retrocede de procesado a en_confeccion.
SELECT tests.fail(
    'RN-11: rechaza retroceder de procesado a en_confeccion',
    $sql$UPDATE transferencia SET estado = 'en_confeccion' WHERE numero = 5022$sql$,
    'P0001'
);

-- Espera: P0001. Transferencia inexistente.
SELECT tests.fail(
    'RN-11: p_procesar_transferencia rechaza una transferencia inexistente',
    $sql$CALL p_procesar_transferencia(99999)$sql$,
    'P0001'
);

-- ============================================================================
-- RN-12: documentos que no estan en confeccion no admiten cambios de renglones

-- Espera: P0001. El ingreso 4001 ya esta terminado.
SELECT tests.fail(
    'RN-12: no agrega renglon a un ingreso terminado',
    $sql$INSERT INTO renglon_ingreso (codigo_ingreso, codigo_vino, cantidad)
         VALUES (4001, 2005, 1)$sql$,
    'P0001'
);

-- Espera: P0001. El ingreso 4012 ya esta procesado.
SELECT tests.fail(
    'RN-12: no modifica renglon de un ingreso procesado',
    $sql$UPDATE renglon_ingreso SET cantidad = 2
         WHERE codigo_ingreso = 4012 AND codigo_vino = 2003$sql$,
    'P0001'
);

-- Espera: P0001. El ingreso 4001 ya esta terminado.
SELECT tests.fail(
    'RN-12: no borra renglon de un ingreso terminado',
    $sql$DELETE FROM renglon_ingreso
         WHERE codigo_ingreso = 4001 AND codigo_vino = 2001$sql$,
    'P0001'
);

-- Espera: exito. El ingreso 4011 sigue en confeccion.
SELECT tests.ok(
    'RN-12: permite agregar renglon a un ingreso en confeccion',
    $sql$INSERT INTO renglon_ingreso (codigo_ingreso, codigo_vino, cantidad)
         VALUES (4011, 2005, 2)$sql$
);

-- Espera: P0001. La transferencia 5022 esta procesada.
SELECT tests.fail(
    'RN-12: no agrega renglon a una transferencia procesada',
    $sql$INSERT INTO renglon_transferencia (numero_transferencia, codigo_vino, cantidad)
         VALUES (5022, 2005, 1)$sql$,
    'P0001'
);

-- Espera: P0001. La transferencia 5022 esta procesada.
SELECT tests.fail(
    'RN-12: no modifica renglon de una transferencia procesada',
    $sql$UPDATE renglon_transferencia SET cantidad = 3
         WHERE numero_transferencia = 5022 AND codigo_vino = 2003$sql$,
    'P0001'
);

-- Espera: P0001. La transferencia 5022 esta procesada.
SELECT tests.fail(
    'RN-12: no borra renglon de una transferencia procesada',
    $sql$DELETE FROM renglon_transferencia
         WHERE numero_transferencia = 5022 AND codigo_vino = 2003$sql$,
    'P0001'
);

-- Espera: exito. La transferencia 5021 sigue en confeccion.
SELECT tests.ok(
    'RN-12: permite agregar renglon a una transferencia en confeccion',
    $sql$INSERT INTO renglon_transferencia (numero_transferencia, codigo_vino, cantidad)
         VALUES (5021, 2005, 2)$sql$
);


-- ============================================================================
-- RN-13: todo cambio de precio queda auditado

-- Espera: exito. Cambia el precio de 50 a 60.
SELECT tests.ok(
    'RN-13: actualiza el precio del vino 2004',
    $sql$UPDATE vino SET precio = 60.00 WHERE codigo = 2004$sql$
);

SELECT tests.assert(
    'RN-13: la auditoria registra precio anterior, nuevo y usuario',
    (SELECT COUNT(*) = 1
       FROM auditoria_precio
      WHERE codigo_vino = 2004
        AND precio_anterior = 50.00
        AND precio_nuevo = 60.00
        AND usuario = current_user)
);

-- Espera: exito. Actualizar al mismo precio no genera otra fila.
SELECT tests.ok(
    'RN-13: actualizar al mismo precio no audita',
    $sql$UPDATE vino SET precio = 60.00 WHERE codigo = 2004$sql$
);

SELECT tests.assert(
    'RN-13: sigue habiendo una sola fila de auditoria para el vino 2004',
    (SELECT COUNT(*) = 1 FROM auditoria_precio WHERE codigo_vino = 2004)
);

-- Espera: exito. Cambiar otro atributo no audita precio.
SELECT tests.ok(
    'RN-13: cambiar el nombre no audita precio',
    $sql$UPDATE vino SET nombre = 'Vino Auditoria Renombrado' WHERE codigo = 2004$sql$
);

SELECT tests.assert(
    'RN-13: el cambio de nombre no genero auditoria de precio',
    (SELECT COUNT(*) = 1 FROM auditoria_precio WHERE codigo_vino = 2004)
);

-- Espera: 23514 (check_violation) por ck_vino_precio_positivo.
SELECT tests.fail(
    'RN-13: un precio invalido no se audita',
    $sql$UPDATE vino SET precio = 0 WHERE codigo = 2004$sql$,
    '23514'
);

SELECT tests.assert(
    'RN-13: la auditoria conserva una sola fila',
    (SELECT COUNT(*) = 1 FROM auditoria_precio WHERE codigo_vino = 2004)
);


-- ============================================================================
-- RN-14: no se borran transportistas, bodegas ni vinos con movimientos


-- Espera: 23001/23503 (restrict/foreign_key) por fk_ingreso_transportista.
SELECT tests.fail(
    'RN-14: no se borra un transportista con ingresos',
    $sql$DELETE FROM transportista WHERE codigo = 4001$sql$,
    '23001,23503'
);

-- Espera: 23001/23503 (restrict/foreign_key) por fk_ingreso_bodega / fk_vino_bodega / fk_lote_bodega.
SELECT tests.fail(
    'RN-14: no se borra una bodega con movimientos',
    $sql$DELETE FROM bodega WHERE cuit = '20123456789'$sql$,
    '23001,23503'
);

-- Espera: 23001/23503 (restrict/foreign_key) por stock o renglones del vino 2001.
SELECT tests.fail(
    'RN-14: no se borra un vino con stock o renglones',
    $sql$DELETE FROM vino WHERE codigo = 2001$sql$,
    '23001,23503'
);

-- Espera: 23001/23503 (restrict/foreign_key) por stock_deposito o renglon_ingreso del vino 2003.
SELECT tests.fail(
    'RN-14: no se borra un vino con renglon de ingreso',
    $sql$DELETE FROM vino WHERE codigo = 2003$sql$,
    '23001,23503'
);

-- Espera: exito. El vino 2004 no tiene stock ni renglones; solo auditoria y composicion
-- que se eliminan en cascada.
SELECT tests.ok(
    'RN-14: se puede borrar un vino sin movimientos',
    $sql$DELETE FROM vino WHERE codigo = 2004$sql$
);

-- Espera: 23001/23503 (restrict/foreign_key) por fk_parcela_cepa.
SELECT tests.fail(
    'RN-14: no se borra una cepa usada en parcelas',
    $sql$DELETE FROM cepa WHERE id = 2001$sql$,
    '23001,23503'
);

-- Espera: 23001/23503 (restrict/foreign_key) por fk_lote_parcela / fk_lote_bodega.
SELECT tests.fail(
    'RN-14: no se borra una finca con lotes',
    $sql$DELETE FROM finca WHERE id = 1001$sql$,
    '23001,23503'
);


-- ============================================================================
-- RN-15: cantidades, superficies, kilos, precios y graduacion

-- Espera: 23514 (check_violation) por ck_vino_graduacion.
SELECT tests.fail(
    'RN-15: rechaza graduacion menor a 5',
    $sql$INSERT INTO vino (nombre, tipo, añada, volumen_ml, graduacion, precio, cuit_bodega)
         VALUES ('Vino Graduacion Baja', 'tinto', 2020, 750, 4.99, 50.00, '20123456789')$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_vino_graduacion.
SELECT tests.fail(
    'RN-15: rechaza graduacion mayor a 20',
    $sql$INSERT INTO vino (nombre, tipo, añada, volumen_ml, graduacion, precio, cuit_bodega)
         VALUES ('Vino Graduacion Alta', 'tinto', 2020, 750, 20.01, 50.00, '20123456789')$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_vino_volumen.
SELECT tests.fail(
    'RN-15: rechaza volumen de vino no permitido',
    $sql$INSERT INTO vino (nombre, tipo, añada, volumen_ml, graduacion, precio, cuit_bodega)
         VALUES ('Vino Volumen Invalido', 'tinto', 2020, 1000, 13.00, 50.00, '20123456789')$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_vino_añada.
SELECT tests.fail(
    'RN-15: rechaza añada fuera de rango',
    $sql$INSERT INTO vino (nombre, tipo, añada, volumen_ml, graduacion, precio, cuit_bodega)
         VALUES ('Vino Anada Invalida', 'tinto', 1989, 750, 13.00, 50.00, '20123456789')$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_renglon_ingreso_cantidad_positiva.
SELECT tests.fail(
    'RN-15: rechaza cantidad 0 en renglon de ingreso',
    $sql$INSERT INTO renglon_ingreso (codigo_ingreso, codigo_vino, cantidad)
         VALUES (4011, 2001, 0)$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_renglon_transferencia_cantidad_positiva.
SELECT tests.fail(
    'RN-15: rechaza cantidad 0 en renglon de transferencia',
    $sql$INSERT INTO renglon_transferencia (numero_transferencia, codigo_vino, cantidad)
         VALUES (5021, 2001, 0)$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_renglon_comprobante_cantidad_positiva.
SELECT tests.fail(
    'RN-15: rechaza cantidad 0 en renglon de comprobante',
    $sql$INSERT INTO renglon_comprobante (numero_comprobante, codigo_vino, cantidad, precio_unitario)
         VALUES (6001, 2005, 0, 200.00)$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_finca_superficie_positiva.
SELECT tests.fail(
    'RN-15: rechaza finca con superficie 0',
    $sql$INSERT INTO finca (nombre_finca, superficie, provincia, nombre_departamento)
         VALUES ('Finca Sin Superficie', 0, 'Mendoza', 'San Rafael')$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_parcela_superficie_positiva.
SELECT tests.fail(
    'RN-15: rechaza parcela con superficie 0',
    $sql$INSERT INTO parcela (numero_parcela, id_finca, superficie, año_plantacion, id_cepa)
         VALUES (98, 1001, 0, 2011, 2001)$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_parcela_año_plantacion.
SELECT tests.fail(
    'RN-15: rechaza parcela con año de plantacion fuera de rango',
    $sql$INSERT INTO parcela (numero_parcela, id_finca, superficie, año_plantacion, id_cepa)
         VALUES (97, 1001, 3.00, 1989, 2001)$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_lote_kg_cosecha_positivo.
SELECT tests.fail(
    'RN-15: rechaza lote con kilos 0',
    $sql$INSERT INTO lote (fecha, kg_cosecha, cuit_bodega, id_finca, numero_parcela)
         VALUES ('2028-01-10', 0, '20123456789', 1001, 1)$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_salario_positivo.
SELECT tests.fail(
    'RN-15: rechaza empleado con salario 0',
    $sql$INSERT INTO empleado (cuit, tipo, nombre, apellido, salario, fecha_ingreso, id_sala)
         VALUES ('20444444444', 'empleado_sala', 'Salario', 'Cero', 0, CURRENT_DATE, 5001)$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_analisis_ph.
SELECT tests.fail(
    'RN-15: rechaza pH fuera de 0..14',
    $sql$INSERT INTO analisis_calidad (fecha, ph, brix, acidez, numero_lote)
         VALUES (CURRENT_DATE, 15, 20, 5, 9001)$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_analisis_brix.
SELECT tests.fail(
    'RN-15: rechaza brix 0',
    $sql$INSERT INTO analisis_calidad (fecha, ph, brix, acidez, numero_lote)
         VALUES (CURRENT_DATE, 7, 0, 5, 9001)$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_analisis_acidez.
SELECT tests.fail(
    'RN-15: rechaza acidez 0',
    $sql$INSERT INTO analisis_calidad (fecha, ph, brix, acidez, numero_lote)
         VALUES (CURRENT_DATE, 7, 20, 0, 9001)$sql$,
    '23514'
);

-- Espera: 23514 (check_violation) por ck_composicion_porcentaje_rango.
SELECT tests.fail(
    'RN-15: rechaza porcentaje de composicion 0',
    $sql$UPDATE composicion SET porcentaje = 0
         WHERE codigo_vino = 2011 AND id_cepa = 2001$sql$,
    '23514'
);


-- ============================================================================
-- PRUEBAS ADICIONALES DE DISENO

SELECT tests.assert(
    'DISENO: fn_antiguedad_anios calcula años cumplidos',
    fn_antiguedad_anios((CURRENT_DATE - INTERVAL '2 years')::date) = 2
);

SELECT tests.assert(
    'DISENO: fn_transicion_valida acepta solo el circuito',
    fn_transicion_valida('en_confeccion', 'terminado')
    AND fn_transicion_valida('terminado', 'procesado')
    AND NOT fn_transicion_valida('terminado', 'en_confeccion')
    AND NOT fn_transicion_valida('en_confeccion', 'procesado')
);

SELECT tests.assert(
    'DISENO: vista_stock_total_por_vino incluye vinos sin stock',
    EXISTS (SELECT 1 FROM vista_stock_total_por_vino
             WHERE codigo = 2011 AND stock_deposito = 0 AND stock_sala = 0 AND stock_total = 0)
);

SELECT tests.assert(
    'DISENO: vista_ventas_mensuales_por_sala muestra ventas de la sala 5001',
    EXISTS (SELECT 1 FROM vista_ventas_mensuales_por_sala
             WHERE id_sala = 5001 AND cantidad_comprobantes >= 1)
);

SELECT tests.assert(
    'DISENO: vista_documentos_pendientes incluye el ingreso 4011',
    EXISTS (SELECT 1 FROM vista_documentos_pendientes
             WHERE tipo_documento = 'ingreso' AND numero = 4011 AND estado = 'en_confeccion')
);

SELECT tests.assert(
    'DISENO: rol_api puede leer vino',
    has_table_privilege('rol_api', 'vino', 'SELECT')
);

SELECT tests.assert(
    'DISENO: rol_api puede insertar auditoria pero no borrarla',
    has_table_privilege('rol_api', 'auditoria_precio', 'INSERT')
    AND NOT has_table_privilege('rol_api', 'auditoria_precio', 'DELETE')
);

SELECT tests.assert(
    'DISENO: rol_reporte no puede escribir vino',
    NOT has_table_privilege('rol_reporte', 'vino', 'INSERT')
);

SELECT tests.assert(
    'DISENO: rol_reporte puede leer las vistas',
    has_table_privilege('rol_reporte', 'vista_stock_total_por_vino', 'SELECT')
    AND has_table_privilege('rol_reporte', 'vista_ventas_mensuales_por_sala', 'SELECT')
    AND has_table_privilege('rol_reporte', 'vista_documentos_pendientes', 'SELECT')
);

SELECT tests.assert(
    'DISENO: rol_api puede ejecutar fn_stock_sala',
    has_function_privilege('rol_api', 'fn_stock_sala(integer,integer)', 'EXECUTE')
);

SELECT tests.assert(
    'DISENO: ambos roles pueden conectarse a la base actual',
    has_database_privilege('rol_api', current_database(), 'CONNECT')
    AND has_database_privilege('rol_reporte', current_database(), 'CONNECT')
);

-- Espera: P0001. p_crear_cliente exige nombre y apellido para cliente_comun.
SELECT tests.fail(
    'DISENO: p_crear_cliente rechaza cliente comun sin nombre',
    $sql$CALL p_crear_cliente('cliente_comun', 'Calle', '13', '5500', 'DNI', '10101010',
                              NULL, NULL, NULL, NULL, NULL, NULL, NULL)$sql$,
    'P0001'
);

-- Espera: P0001. p_crear_cliente exige zona y habilitacion para distribuidor.
SELECT tests.fail(
    'DISENO: p_crear_cliente rechaza distribuidor sin zona',
    $sql$CALL p_crear_cliente('distribuidor', 'Calle', '14', '5500', 'CUIT', '20202020',
                              NULL, NULL, 'Distribuidora Sin Zona', NULL, NULL, NULL, NULL)$sql$,
    'P0001'
);

-- Espera: P0001. Cliente inexistente en p_cambiar_tipo_cliente.
SELECT tests.fail(
    'DISENO: p_cambiar_tipo_cliente rechaza cliente inexistente',
    $sql$CALL p_cambiar_tipo_cliente(99999, 'socio_club',
                                     'No', 'Existe', NULL, NULL, NULL, NULL, NULL)$sql$,
    'P0001'
);

\echo 'Todos los tests pasaron. Se ejecuta ROLLBACK para no dejar datos.'
ROLLBACK;
