-- 005_triggers.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 2.5: Implementar los triggers o disparadores (9)

SET client_encoding = 'UTF8';
BEGIN;

-- ============================================================================
-- 1. RN-09: validar stock ANTES de vender

CREATE OR REPLACE FUNCTION trg_validar_stock_venta()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_sala INT;
    v_stock INT;
BEGIN
    -- Bloqueamos la cabecera para evitar que dos transacciones
    -- procesen el mismo comprobante a la vez
    SELECT id_sala_venta
        INTO v_id_sala
        FROM comprobante
        WHERE numero = NEW.numero_comprobante
        FOR UPDATE;

    -- si no se encuentra el comprobante
    IF NOT FOUND THEN
        RAISE EXCEPTION
            'El comprobante % no existe', NEW.numero_comprobante;
    END IF;

    -- Bloqueamos la fila de stock para evitar que dos ventas validen
    -- el stock sin actualizar
    SELECT cantidad
        INTO v_stock
        FROM stock_sala
        WHERE id_sala = v_id_sala
        AND codigo_vino = NEW.codigo_vino
        FOR UPDATE;

    -- si no encontramos la fila correspondiente al vino buscado en
    -- el stock de la sala
    IF NOT FOUND THEN
        v_stock := 0;  -- le designamos 0 (localmente) al stock de sala
    END IF;

    -- si el stock de la sala es menor a la cantidad solicitada por el 
    -- comprobante (o si no se encontro el vino)
    IF v_stock < NEW.cantidad THEN
        RAISE EXCEPTION
            'Stock insuficiente del vino % en la sala %: disponible %, solicitado %',
            NEW.codigo_vino, v_id_sala, v_stock, NEW.cantidad;
    END IF;

    RETURN NEW; -- devolvemos los datos NEW (los que se quieren ingresar) para que se inserten
END;
$$;

COMMENT ON FUNCTION trg_validar_stock_venta() IS
'RN-09: rechaza la venta si no hay stock suficiente en la sala';

CREATE TRIGGER trg_renglon_comprobante_valida_stock
BEFORE INSERT ON renglon_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_validar_stock_venta();


-- ============================================================================
-- 2. RN-08 / RN-09: descontar stock DESPUES de vender y recalcular totales del comprobante

CREATE OR REPLACE FUNCTION trg_actualizar_stock_y_totales_venta()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_sala INT;
    v_id_cliente INT;
    v_descuento NUMERIC(3,2);
    v_subtotal NUMERIC(14,2);
    v_descuento_total NUMERIC(14,2);
    v_total NUMERIC(14,2);
BEGIN
    SELECT id_sala_venta, id_cliente
        INTO v_id_sala, v_id_cliente
        FROM comprobante
        WHERE numero = NEW.numero_comprobante;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'El comprobante % no existe (RN-08)', NEW.numero_comprobante;
    END IF;

    -- si el comprobante paso adecuadamente, se actualiza el stock de la sala
    UPDATE stock_sala
        SET cantidad = cantidad - NEW.cantidad
        WHERE id_sala = v_id_sala
        AND codigo_vino = NEW.codigo_vino;

    -- segunda validacion del stock existente en la sala
    IF NOT FOUND THEN
        RAISE EXCEPTION
            'No existe stock del vino % en la sala % (RN-09)',
            NEW.codigo_vino, v_id_sala;
    END IF;

    -- llamamos a fn_descuento_cliente y le mandamos el id del cliente
    -- la funcion devuelve el descuento del cliente segun su tipo
    SELECT fn_descuento_cliente(v_id_cliente)
        INTO v_descuento;  -- guardamos su descuento

    -- si no se encuentra el cliente
    IF NOT EXISTS (SELECT 1 FROM cliente WHERE id = v_id_cliente) THEN
        RAISE EXCEPTION 'El cliente % no existe (RN-06)', v_id_cliente;
    END IF;

    -- sumamos todos los subtotales de los renglones pertenecientes 
    -- al comprobante. Si no hay renglon cargado (porque recien se crea
    -- la cabecera del comprobante) el subtotal vale 0
    SELECT COALESCE(SUM(subtotal_renglon), 0)
        INTO v_subtotal  -- guardamos el subtotal del comprobante
        FROM renglon_comprobante
        WHERE numero_comprobante = NEW.numero_comprobante;

    -- fn_total_comprobante lee comprobante.descuento_aplicado
    -- Por eso primero guardamos el descuento.
    UPDATE comprobante
        SET descuento_aplicado = v_descuento
        WHERE numero = NEW.numero_comprobante;

    -- calculamos el total con la funcion
    v_total := fn_total_comprobante(NEW.numero_comprobante);
    v_descuento_total := v_subtotal - v_total;

    -- ahora si podemos finalizar con la insercion del comprobante
    UPDATE comprobante
       SET subtotal = v_subtotal,
           descuento_total = v_descuento_total,
           total = v_total
     WHERE numero = NEW.numero_comprobante;

    RETURN NULL; -- ya se hizo la insercion asi que no se deuvuelve nada
END;
$$;

COMMENT ON FUNCTION trg_actualizar_stock_y_totales_venta() IS
'RN-08/RN-09: descuenta stock de la sala y recalcula los importes del comprobante';

CREATE TRIGGER trg_renglon_comprobante_actualiza_venta
AFTER INSERT ON renglon_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_actualizar_stock_y_totales_venta();


-- ============================================================================
-- 3. RN-10 / RN-11: transiciones de estado de ingreso y transferencia

CREATE OR REPLACE FUNCTION trg_validar_estado_documento()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    -- si se intenta hacer un insert (trigger operation) en ingreso 
    -- o transferencia con un estado distinto a 'en_confeccion'
    IF TG_OP = 'INSERT' THEN
        IF NEW.estado IS DISTINCT FROM 'en_confeccion' THEN
            RAISE EXCEPTION
                'El documento debe crearse en estado en_confeccion (estado: %) (RN-10/RN-11)',
                NEW.estado;
        END IF;
        RETURN NEW;
    END IF;

    -- si TG_OP no es INSERT, se intenta hacer un UPDATE
    -- llamamos a la funcion
    IF fn_transicion_valida(OLD.estado, NEW.estado) THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION
        'Transicion de estado invalida: % -> % (RN-10/RN-11)',
        OLD.estado, NEW.estado;
END;
$$;

COMMENT ON FUNCTION trg_validar_estado_documento() IS
'RN-10/RN-11: solo permite en_confeccion -> terminado -> procesado';

CREATE TRIGGER trg_ingreso_estado_valido
BEFORE INSERT OR UPDATE OF estado ON ingreso
FOR EACH ROW
EXECUTE FUNCTION trg_validar_estado_documento();

CREATE TRIGGER trg_transferencia_estado_valido
BEFORE INSERT OR UPDATE OF estado ON transferencia
FOR EACH ROW
EXECUTE FUNCTION trg_validar_estado_documento();


-- ============================================================================
-- 4. RN-12: bloquear renglones de documentos que no estan en confeccion

CREATE OR REPLACE FUNCTION trg_bloquear_renglon_ingreso()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado tipo_estado;
BEGIN

    -- si se intenta actualizar o borrar un renglon del ingreso
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT estado
            INTO v_estado  -- capturamos su estado
            FROM ingreso
            WHERE codigo = OLD.codigo_ingreso; 

        -- si no encontramos la fila en la tabla ingreso que es dueña del
        -- renglon, es porque se borro la cabecera
        IF NOT FOUND THEN
            -- Si estamos borrando el renglon (porque se disparo el CASCADE),
            -- permitimos que el borrado continue
            IF TG_OP = 'DELETE' THEN
                RETURN OLD;  
            END IF;
            -- Si por alguna razon estuviera actualizandose un renglon huerfano,
            -- dejamos pasar el registro para que la FK lo rechace
            RETURN NEW;  -- 
        END IF;

        IF v_estado <> 'en_confeccion' THEN
            RAISE EXCEPTION
                'No se pueden agregar, modificar ni quitar renglones de un ingreso en estado % (RN-12)',
                v_estado;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        SELECT estado
            INTO v_estado
            FROM ingreso
            WHERE codigo = NEW.codigo_ingreso;

        -- si no encontramos la cabecera el renglon es huerfano
        IF NOT FOUND THEN
            RETURN NEW;  -- la FK lo va a rechazar (SRP)
        END IF;

        IF v_estado <> 'en_confeccion' THEN
            RAISE EXCEPTION
                'No se pueden agregar, modificar ni quitar renglones de un ingreso en estado % (RN-12)',
                v_estado;
        END IF;
    END IF;

    -- si el renglon que se quiere borrar tiene su ingreso padre y 
    -- esta 'en_confeccion', permitimos el borrado
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    -- si es UPDATE o INSERT y cumple con todo, permitimos la TG_OP
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trg_bloquear_renglon_ingreso() IS
'RN-12: impide cambiar renglones de un ingreso que no esta en_confeccion';

CREATE TRIGGER trg_renglon_ingreso_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_ingreso
FOR EACH ROW
EXECUTE FUNCTION trg_bloquear_renglon_ingreso();

-- mismo razonamiento para las transferencias
CREATE OR REPLACE FUNCTION trg_bloquear_renglon_transferencia()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado tipo_estado;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT estado
            INTO v_estado
            FROM transferencia
            WHERE numero = OLD.numero_transferencia;

        IF NOT FOUND THEN
            IF TG_OP = 'DELETE' THEN
                RETURN OLD;
            END IF;
            RETURN NEW;
        END IF;

        IF v_estado <> 'en_confeccion' THEN
            RAISE EXCEPTION
                'No se pueden agregar, modificar ni quitar renglones de una transferencia en estado % (RN-12)',
                v_estado;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        SELECT estado
            INTO v_estado
            FROM transferencia
            WHERE numero = NEW.numero_transferencia;

        IF NOT FOUND THEN
            RETURN NEW;
        END IF;

        IF v_estado <> 'en_confeccion' THEN
            RAISE EXCEPTION
                'No se pueden agregar, modificar ni quitar renglones de una transferencia en estado % (RN-12)',
                v_estado;
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trg_bloquear_renglon_transferencia() IS
'RN-12: impide cambiar renglones de una transferencia que no esta en_confeccion';

CREATE TRIGGER trg_renglon_transferencia_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_transferencia
FOR EACH ROW
EXECUTE FUNCTION trg_bloquear_renglon_transferencia();


-- ============================================================================
-- 5. RN-11: fecha de confeccion de la transferencia y los ingresos

CREATE OR REPLACE FUNCTION trg_fijar_fecha_documento()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_TABLE_NAME = 'ingreso' THEN
        IF TG_OP = 'INSERT' THEN
            -- La fecha la pone la base, no el cliente de la API
            NEW.fecha := CURRENT_DATE;
        ELSIF NEW.fecha IS DISTINCT FROM OLD.fecha THEN
            RAISE EXCEPTION
                'La fecha de confeccion del ingreso no se puede modificar (RN-11)';
        END IF;

    ELSIF TG_TABLE_NAME = 'transferencia' THEN
        IF TG_OP = 'INSERT' THEN
            NEW.fecha_confeccion := CURRENT_DATE;
        ELSIF NEW.fecha_confeccion IS DISTINCT FROM OLD.fecha_confeccion THEN
            RAISE EXCEPTION
                'La fecha de confeccion de la transferencia no se puede modificar (RN-11)';
        END IF;

    ELSE
        RAISE EXCEPTION
            'Trigger de fecha no soportado para la tabla %', TG_TABLE_NAME;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trg_fijar_fecha_documento() IS
'RN-11: fuerza la fecha actual al insertar y prohibe modificarla en ingresos y transferencias';

CREATE TRIGGER trg_ingreso_fecha
BEFORE INSERT OR UPDATE OF fecha ON ingreso
FOR EACH ROW
EXECUTE FUNCTION trg_fijar_fecha_documento();

CREATE TRIGGER trg_transferencia_fecha_confeccion
BEFORE INSERT OR UPDATE OF fecha_confeccion ON transferencia
FOR EACH ROW
EXECUTE FUNCTION trg_fijar_fecha_documento();


-- ============================================================================
-- 6. RN-13: auditoria de cambios de precio de vino

CREATE OR REPLACE FUNCTION trg_auditar_precio_vino()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- insertamos la fila que audita el cambio
    INSERT INTO auditoria_precio (
        usuario,
        fecha_hora,
        precio_nuevo,
        precio_anterior,
        codigo_vino
    ) VALUES (
        CURRENT_USER,
        CURRENT_TIMESTAMP,
        NEW.precio,
        OLD.precio,
        NEW.codigo
    );

    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION trg_auditar_precio_vino() IS
'RN-13: registra usuario, fecha, precio anterior y precio nuevo';

CREATE TRIGGER trg_vino_audita_precio
AFTER UPDATE OF precio ON vino
FOR EACH ROW
WHEN (OLD.precio IS DISTINCT FROM NEW.precio)
EXECUTE FUNCTION trg_auditar_precio_vino();
    

-- ============================================================================
-- 7. RN-05: la composicion de cada vino suma exactamente 100

CREATE OR REPLACE FUNCTION trg_validar_composicion_100()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM fn_validar_composicion_vino(OLD.codigo_vino);

    ELSIF TG_OP = 'UPDATE' THEN
        PERFORM fn_validar_composicion_vino(OLD.codigo_vino);

        IF NEW.codigo_vino IS DISTINCT FROM OLD.codigo_vino THEN
            PERFORM fn_validar_composicion_vino(NEW.codigo_vino);
        END IF;

    ELSE
        PERFORM fn_validar_composicion_vino(NEW.codigo_vino);
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_composicion_suma_100
AFTER INSERT OR UPDATE OR DELETE ON composicion
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_validar_composicion_100();


-- ============================================================================
-- 8. Precio de lista en la venta la linea de venta debe usar el precio 
-- actual del vino, no un valor que mande el cliente de la API

CREATE OR REPLACE FUNCTION trg_fijar_precio_lista_venta()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_precio NUMERIC(10,2);
BEGIN
    SELECT precio
      INTO v_precio
      FROM vino
     WHERE codigo = NEW.codigo_vino;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El vino % no existe (RN-01)', NEW.codigo_vino;
    END IF;

    NEW.precio_unitario := v_precio;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trg_fijar_precio_lista_venta() IS
'Recomendado: la venta usa el precio de lista actual del vino';

CREATE TRIGGER trg_renglon_comprobante_precio_lista
BEFORE INSERT ON renglon_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_fijar_precio_lista_venta();


-- ============================================================================
-- 9. Totalidad de la jerarquia cliente

CREATE OR REPLACE FUNCTION trg_validar_subtipo_cliente()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- si se borra un cliente de su subtipo, no puede quedar sin otro tipo
        PERFORM fn_validar_subtipo_cliente(OLD.id_cliente);

    ELSIF TG_TABLE_NAME = 'cliente' THEN
        PERFORM fn_validar_subtipo_cliente(NEW.id);

    ELSE
        PERFORM fn_validar_subtipo_cliente(NEW.id_cliente);
    END IF;

    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION trg_validar_subtipo_cliente() IS
'Constraint trigger diferido de totalidad de la jerarquia cliente';

CREATE CONSTRAINT TRIGGER trg_cliente_subtipo_total
AFTER INSERT OR UPDATE ON cliente
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_validar_subtipo_cliente();

CREATE CONSTRAINT TRIGGER trg_cliente_comun_subtipo_total
AFTER INSERT OR UPDATE OR DELETE ON cliente_comun
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_validar_subtipo_cliente();

CREATE CONSTRAINT TRIGGER trg_socio_club_subtipo_total
AFTER INSERT OR UPDATE OR DELETE ON socio_club
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_validar_subtipo_cliente();

CREATE CONSTRAINT TRIGGER trg_distribuidor_subtipo_total
AFTER INSERT OR UPDATE OR DELETE ON distribuidor
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_validar_subtipo_cliente();

CREATE CONSTRAINT TRIGGER trg_exportador_subtipo_total
AFTER INSERT OR UPDATE OR DELETE ON exportador
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_validar_subtipo_cliente();

COMMIT;

