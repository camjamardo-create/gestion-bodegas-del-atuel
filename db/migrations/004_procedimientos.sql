-- 004_procedimientos.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 2.4: Implementar los procedimientos transaccionales

SET client_encoding = 'UTF8';
BEGIN;

--- ===============================================================================
---  RN-10: Solo un ingreso terminado impacta en el deposito para procesado

CREATE OR REPLACE PROCEDURE p_procesar_ingreso(p_codigo INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado tipo_estado;    -- variable local
BEGIN

    -- Bloqueamos la cabecera para que dos sesiones no procesen el mismo ingreso
    SELECT estado
        INTO v_estado    -- v_estado = estado
        FROM ingreso
        WHERE codigo = p_codigo
            FOR UPDATE;   
        
    -- Si no se encuentra un estado perteneciente al p_codigo
    IF NOT FOUND THEN    
        RAISE EXCEPTION 'El ingreso % no existe', p_codigo;
    END IF;

    -- si el ingreso no tiene estado terminado
    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION
            'El ingreso % no esta terminado (estado actual: %)',
            p_codigo, v_estado;
    END IF;  

    -- No se puede procesar un ingreso con 0 renglones
    IF NOT EXISTS (
        SELECT 1
            FROM renglon_ingreso
            WHERE codigo_ingreso = p_codigo
    ) THEN
        RAISE EXCEPTION 'El ingreso % no tiene renglones', p_codigo;
    END IF;

    -- Sumamos cada renglon al stock del deposito
    -- Si el vino no tiene fila en stock_deposito, la creamos con su cantidad
    INSERT INTO stock_deposito (codigo_vino, cantidad)  -- tabla destino
    SELECT ri.codigo_vino, ri.cantidad   
        FROM renglon_ingreso ri       -- fuente
        WHERE ri.codigo_ingreso = p_codigo
        ORDER BY ri.codigo_vino
    ON CONFLICT (codigo_vino)  -- si el codigo del vino ya esta cargado 
    DO UPDATE                   -- solo actualizamos la cantidad
        SET cantidad = stock_deposito.cantidad + EXCLUDED.cantidad;

    -- Despues de actualizar el stock, se cambia el estado
    UPDATE ingreso
        SET estado = 'procesado'
        WHERE codigo = p_codigo;

END;
$$;


--- ===============================================================================
---  RN-11: solo una transferencia terminada impacta el stock y pasa a procesado

CREATE OR REPLACE PROCEDURE p_procesar_transferencia(p_numero INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado tipo_estado;
    v_id_sala INT;
    v_renglon RECORD;
    v_stock_actual INT;
BEGIN

    -- No se procesa dos veces la misma transferencia (bloqueo de cabecera)
    SELECT estado, id_sala_venta
        INTO v_estado, v_id_sala
        FROM transferencia
        WHERE numero = p_numero
        FOR UPDATE;

    -- Si no se encuentra la transferencia 
    IF NOT FOUND THEN  
        RAISE EXCEPTION 'La transferencia % no existe', p_numero;
    END IF;

    -- Si el estado no es terminado
    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION
            'La transferencia % no esta terminada (estado actual: %)',
            p_numero, v_estado;
    END IF;

    -- Si la transferencia no tiene al menos un renglon
    IF NOT EXISTS (
        SELECT 1
            FROM renglon_transferencia
            WHERE numero_transferencia = p_numero
    ) THEN
        RAISE EXCEPTION 'La transferencia % no tiene renglones', p_numero;
    END IF;

    -- Recorremos los renglones en orden de vino para bloquear siempre en el
    -- mismo orden y reducir el riesgo de deadlocks.
    FOR v_renglon IN
        SELECT codigo_vino, cantidad
            FROM renglon_transferencia
            WHERE numero_transferencia = p_numero
            ORDER BY codigo_vino
    LOOP

        -- Bloquear la fila de stock del deposito para no procesar dos
        -- transferencias sobre el stock sin actualizar
        SELECT cantidad
            INTO v_stock_actual
            FROM stock_deposito
            WHERE codigo_vino = v_renglon.codigo_vino
            FOR UPDATE;

        -- Si el codigo del vino no esta cargado en el deposito
        IF NOT FOUND THEN
            RAISE EXCEPTION
                'El vino % no esta cargado en el stock del deposito',
                v_renglon.codigo_vino;
        END IF;

        -- Si la cantidad del deposito es menor a la que solicita la transferencia
        IF v_stock_actual < v_renglon.cantidad THEN
            RAISE EXCEPTION
                'Stock insuficiente en el deposito para el vino %: disponible %, solicitado %',
                v_renglon.codigo_vino, v_stock_actual, v_renglon.cantidad;
        END IF;

        -- Descontamos la cantidad del stock del deposito
        UPDATE stock_deposito
            SET cantidad = cantidad - v_renglon.cantidad
            WHERE codigo_vino = v_renglon.codigo_vino;

        -- Acreditamos la transferencia a la sala destino
        -- Si no existe la fila, la creamos, y si si, lo manejamos con ON CONFLICT
        INSERT INTO stock_sala (id_sala, codigo_vino, cantidad)
        VALUES (v_id_sala, v_renglon.codigo_vino, v_renglon.cantidad)
        ON CONFLICT (id_sala, codigo_vino)
        DO UPDATE
            SET cantidad = stock_sala.cantidad + EXCLUDED.cantidad;
    END LOOP;

    -- Despues de impactar en el stock del deposito y de la sala, cambia el estado
    UPDATE transferencia
        SET estado = 'procesado'
        WHERE numero = p_numero;

END;
$$;


--- ===============================================================================
---  Procedimiento para dar de alta a clientes (por supertipo y subtipos)

CREATE OR REPLACE PROCEDURE p_crear_cliente(
    p_tipo tipo_cliente,
    p_calle VARCHAR(60),
    p_numero VARCHAR(10),
    p_codigo_postal cp_dominio,
    p_tipo_documento VARCHAR(10),
    p_numero_documento VARCHAR(20),
    p_nombre VARCHAR(60) DEFAULT NULL,
    p_apellido VARCHAR(60) DEFAULT NULL,
    p_razon_social VARCHAR(120) DEFAULT NULL,
    p_zona_cobertura VARCHAR(100) DEFAULT NULL,
    p_numero_habilitacion VARCHAR(20) DEFAULT NULL,
    p_pais_destino VARCHAR(50) DEFAULT NULL,
    p_descuento_especial NUMERIC(3,2) DEFAULT NULL
)

LANGUAGE plpgsql
AS $$
DECLARE
    v_id_cliente INT;
BEGIN

-- validaciones necesarias de los campos
    IF p_tipo IS NULL THEN
        RAISE EXCEPTION 'El tipo de cliente es obligatorio';
    END IF;

    IF p_calle IS NULL OR btrim(p_calle) = ''
       OR p_numero IS NULL OR btrim(p_numero) = '' THEN
        RAISE EXCEPTION 'Calle y numero son obligatorios';
    END IF;

    IF p_codigo_postal IS NULL THEN
        RAISE EXCEPTION 'El codigo postal es obligatorio';
    END IF;

    IF p_tipo_documento IS NULL OR btrim(p_tipo_documento) = ''
       OR p_numero_documento IS NULL OR btrim(p_numero_documento) = '' THEN
        RAISE EXCEPTION 'Tipo y numero de documento son obligatorios';
    END IF;

    -- Validaciones alineadas con ck_cliente_datos
    IF p_tipo IN ('cliente_comun', 'socio_club') THEN
        IF p_nombre IS NULL OR btrim(p_nombre) = ''
           OR p_apellido IS NULL OR btrim(p_apellido) = '' THEN
            RAISE EXCEPTION 'Para el tipo % se requieren nombre y apellido', p_tipo;
        END IF;
    ELSIF p_tipo IN ('distribuidor', 'exportador') THEN
        IF p_razon_social IS NULL OR btrim(p_razon_social) = '' THEN
            RAISE EXCEPTION 'Para el tipo % se requiere razon social', p_tipo;
        END IF;
    END IF;

    -- Validaciones especificas de cada subtipo
    IF p_tipo = 'distribuidor' THEN
        IF p_zona_cobertura IS NULL OR btrim(p_zona_cobertura) = ''
           OR p_numero_habilitacion IS NULL OR btrim(p_numero_habilitacion) = '' THEN
            RAISE EXCEPTION 'Para distribuidor se requieren zona_cobertura y número_habilitación';
        END IF;
    ELSIF p_tipo = 'exportador' THEN
        IF p_pais_destino IS NULL OR btrim(p_pais_destino) = '' THEN
            RAISE EXCEPTION 'Para exportador se requiere país_destino';
        END IF;
        IF p_descuento_especial IS NOT NULL
           AND p_descuento_especial NOT BETWEEN 0.30 AND 0.35 THEN
            RAISE EXCEPTION 'El descuento especial debe estar entre 0.30 y 0.35';
        END IF;
    END IF;

    -- 1) Insertar el supertipo. El alta siempre nace activa
    INSERT INTO cliente (
        tipo, nombre, apellido, razon_social,
        calle, numero, codigo_postal,
        tipo_documento, numero_documento,
        estado_activo
    )
    VALUES (
        p_tipo, p_nombre, p_apellido, p_razon_social,
        p_calle, p_numero, p_codigo_postal,
        p_tipo_documento, p_numero_documento,
        TRUE
    )
    RETURNING id INTO v_id_cliente;  -- recuperamos el id generado del cliente

    -- 2) Insertar la fila del subtipo correspondiente
    IF p_tipo = 'cliente_comun' THEN
        INSERT INTO cliente_comun (id_cliente, tipo)
        VALUES (v_id_cliente, 'cliente_comun');
    ELSIF p_tipo = 'socio_club' THEN
        INSERT INTO socio_club (id_cliente, tipo)
        VALUES (v_id_cliente, 'socio_club');
    ELSIF p_tipo = 'distribuidor' THEN
        INSERT INTO distribuidor (id_cliente, tipo, zona_cobertura, numero_habilitacion)
        VALUES (v_id_cliente, 'distribuidor', p_zona_cobertura, p_numero_habilitacion);
    ELSIF p_tipo = 'exportador' THEN
        INSERT INTO exportador (id_cliente, tipo, pais_destino, descuento_especial)
        VALUES (v_id_cliente, 'exportador', p_pais_destino, p_descuento_especial);
    ELSE
        RAISE EXCEPTION 'Tipo de cliente no soportado: %', p_tipo;
    END IF;

-- no pueden haber dos clientes activos con el mismo numero y tipo de documento
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION
            'Ya existe un cliente activo con tipo_documento % y numero_documento %',
            p_tipo_documento, p_numero_documento
            USING ERRCODE = '23505';
END;
$$;

--- ===============================================================================
---  Procedimiento para cambiarle el tipo a un cliente
---  Versionado de cliente para cambiar el tipo sin perder el historial
---  Desactiva el cliente actual y crea uno nuevo activo con el mismo documento

CREATE OR REPLACE PROCEDURE p_cambiar_tipo_cliente(
    p_id_cliente INT,
    p_nuevo_tipo tipo_cliente,
    p_nombre VARCHAR(60) DEFAULT NULL,
    p_apellido VARCHAR(60) DEFAULT NULL,
    p_razon_social VARCHAR(120) DEFAULT NULL,
    p_zona_cobertura VARCHAR(100) DEFAULT NULL,
    p_numero_habilitacion VARCHAR(20) DEFAULT NULL,
    p_pais_destino VARCHAR(50) DEFAULT NULL,
    p_descuento_especial NUMERIC(3,2) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cliente cliente%ROWTYPE;  -- registro estructurado que contiene las mimas columnas y tipos de dato que cliente
BEGIN
    IF p_id_cliente IS NULL THEN
        RAISE EXCEPTION 'El id del cliente es obligatorio';
    END IF;

    IF p_nuevo_tipo IS NULL THEN
        RAISE EXCEPTION 'El nuevo tipo de cliente es obligatorio';
    END IF;

    -- Bloqueamos al cliente para que dos cambios de tipo no compitan
    SELECT *
      INTO v_cliente
      FROM cliente
     WHERE id = p_id_cliente
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El cliente % no existe', p_id_cliente;
    END IF;

    IF NOT v_cliente.estado_activo THEN
        RAISE EXCEPTION 'El cliente % no esta activo', p_id_cliente;
    END IF;

    IF v_cliente.tipo = p_nuevo_tipo THEN
        RAISE EXCEPTION
            'El cliente % ya es de tipo %', p_id_cliente, p_nuevo_tipo;
    END IF;

    -- Versionado: el registro viejo queda inactivo y libera la unicidad
    -- parcial del documento
    UPDATE cliente
       SET estado_activo = FALSE
     WHERE id = p_id_cliente;

    -- Se reutiliza el alta de clientes para crear el nuevo registro activo
    -- con otro id y el nuevo tipo.
    CALL p_crear_cliente(
        p_nuevo_tipo,
        v_cliente.calle,
        v_cliente.numero,
        v_cliente.codigo_postal,
        v_cliente.tipo_documento,
        v_cliente.numero_documento,
        COALESCE(p_nombre, v_cliente.nombre),
        COALESCE(p_apellido, v_cliente.apellido),
        COALESCE(p_razon_social, v_cliente.razon_social),
        p_zona_cobertura,
        p_numero_habilitacion,
        p_pais_destino,
        p_descuento_especial
    );
END;
$$;


COMMIT;