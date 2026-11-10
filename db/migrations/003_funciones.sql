-- 003_funciones.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 2: Integridad y logica en la base de datos
-- -- Descripcion: funciones requeridas por el TPI y funciones auxiliares de validacion
--- ===============================================================================
SET client_encoding = 'UTF8';

BEGIN;

-- fn_descuento_cliente
-- proposito: devolver el descuento efectivo (fraccion) que le corresponde a un cliente
--            *cliente_comun: 0.00
--            *socio_club:    0.10
--            *distribuidor:  0.20
--            *exportador: exportador.descuento_especial (o 0.30 si es NULL)
-- RN-06
-- parámetro: p_id_cliente (integer): id del cliente
-- retorna: numeric 
--volatilidad: STABLE (lee cliente y exportador, no los modifica)

--- ===============================================================================
DROP FUNCTION IF EXISTS fn_descuento_cliente(tipo_cliente);

CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_id_cliente integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    -- si no se encuentra el cliente, se devuelve el valor final 0.00
    SELECT COALESCE(
        -- subconsulta que busca el tipo del cliente
        (SELECT CASE c.tipo
                   WHEN 'cliente_comun' THEN 0.00
                   WHEN 'socio_club' THEN 0.10
                   WHEN 'distribuidor' THEN 0.20
                   WHEN 'exportador' THEN COALESCE(e.descuento_especial, 0.30)
                END
            -- busca en la tabla cliente
            FROM cliente c
            -- trae la fila de exportador de ese cliente.
            -- left permite que los otros tipos no se piernas
            LEFT JOIN exportador e ON e.id_cliente = c.id
            -- filtra solo el cliente pedido
            WHERE c.id = p_id_cliente), 0.00);

$$;

COMMENT ON FUNCTION fn_descuento_cliente(integer) IS
'devuelve el porcentaje de descuento segun tipo de cliente';

--- ===============================================================================

--fn_total_comprobante
--proposito: calcular el total de un comprobante a partir de sus renglones y del descuento aplicado
--RN-08
--parametro: p_numero_comprobante(integer): numero del comprobante
--retorna: numeric (importe total con descuento, 2 decimales)
--volatilidad: STABLE (lee datos, no los modifica)

--- ===============================================================================
CREATE OR REPLACE FUNCTION fn_total_comprobante(p_numero_comprobante integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT ROUND(
        -- suma los subtotales de todos los renglones del comprobante, si la suma da NULL usa 0
        COALESCE(SUM(rc.subtotal_renglon), 0)
        -- se multiplica el subtotal por el factor de descuento
        * (1 - COALESCE(
            (SELECT c.descuento_aplicado --subconsulta
               from comprobante c
               --filtra el comprobante
               where c.numero = p_numero_comprobante), 0)
        ), 2)
    --indica de que tabla salen las filas que se van a sumar
    FROM renglon_comprobante rc
    --limita la suma a los renglones de ese comprobante
    WHERE rc.numero_comprobante = p_numero_comprobante;
$$;

COMMENT ON FUNCTION fn_total_comprobante(integer) IS
'Calcula el total del comprobante con descuento aplicado';

--- ===============================================================================

--fn_stock_sala
--proposito: devolver la cantidad de stock de un vino en una sala de venta
--RN-09
-- parametros: p_id_sale (integer): id de la sala
--             p_codigo_vino (integer): codigo del vino
--retorna: integer (cantidad disponibles; 0 si no existe la fila)
--volatilidad: STABLE (lee datos, no los modifica)

--- ===============================================================================
CREATE OR REPLACE FUNCTION fn_stock_sala(p_id_sala integer, p_codigo_vino integer)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
   -- devuelve el valor de la subconsulta
    SELECT COALESCE(
        -- subconsuta escalar: trae un solo valor, la cantidad
        (SELECT s.cantidad
           FROM stock_sala s -- se busca en la tabla de stock
           -- filtra por la sala y vino recibido
           WHERE s.id_sala = p_id_sala
           AND s.codigo_vino = p_codigo_vino), 0);
$$;

COMMENT ON FUNCTION fn_stock_sala(integer,integer) IS
'Devuelve el stock de un vino en una sala (0 si no existe la fila)';

--- ===============================================================================

-- fn_antiguedad_anios
-- proposito: calcular la antiguedad en anios cumplidos desde una fecha dada
--            sirve tanto para cliente.fecha_alta como para vino.anhada.
-- parametro: p_fecha (date): fecha desde la cual se calcula la antiguedad
-- retorna: integer (anios cumplidos a la fecha actual)
-- volatilidad: STABLE (depende de CURRENT_DATE, por eso no es IMMUTABLE)

--- ===============================================================================

CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_fecha date)
RETURNS integer
LANGUAGE sql
STABLE 
AS $$ 
-- calcula la diferencia entre hoy y la fecha recibida. devuelve un intervalo, ejemplo '2020-05-10'
   SELECT EXTRACT(YEAR FROM AGE(CURRENT_DATE, p_fecha))::integer;
$$;

COMMENT ON FUNCTION fn_antiguedad_anios(date) IS
'Calcula la antiguedad en anios cumplidos desde una fecha';

--- ===============================================================================
-- fn_transicion_valida
--proposito: valodad que un documento pase de un estado a otro respetando el circuito
--           en_confeccion -> terminado -> procesado
--           * mismo estado: valido (no hay transicion)
--           * en_confeccion -> terminado: valido
--           * terminado -> procesado: valido
--           * cualq otro cambio: invalido
-- RN-10
-- parametros: p_anterior (tipo_estado): estado actual
--             p_nuevo (tipo_estado): estado al que se quiere pasar
-- retorna: boolean (true si la transicion es valida)
-- volatilidad: IMMUTABLE (solo compara sus parametros)

--- ===============================================================================

CREATE OR REPLACE FUNCTION fn_transicion_valida(p_anterior tipo_estado, p_nuevo tipo_estado)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        -- si el estado no cambia, es válido
        WHEN p_anterior = p_nuevo THEN TRUE
        -- primer paso del circuito
        WHEN p_anterior = 'en_confeccion' AND p_nuevo = 'terminado' THEN TRUE
        -- segundo paso del circuito
        WHEN p_anterior = 'terminado' AND p_nuevo = 'procesado' THEN TRUE
        ELSE FALSE
    END;
$$;

COMMENT ON FUNCTION fn_transicion_valida(tipo_estado, tipo_estado) IS
'valida el circuito de estados en_confeccion -> terminado -> procesado';

--- ==================================================================================
-- La suma de los porcentajes que componen la cepa debe ser 100

CREATE OR REPLACE FUNCTION fn_validar_composicion_vino(p_codigo_vino INT)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_suma NUMERIC;
BEGIN
    -- Si el vino ya fue eliminado, sus filas de composicion se borraron en
    -- cascada. No tiene sentido exigir una suma sobre un vino inexistente
    IF NOT EXISTS (SELECT 1 FROM vino WHERE codigo = p_codigo_vino) THEN
        RETURN;
    END IF;

    SELECT COALESCE(SUM(porcentaje), 0)
        INTO v_suma
        FROM composicion
        WHERE codigo_vino = p_codigo_vino;

    IF v_suma <> 100 THEN
        RAISE EXCEPTION
            'La composicion del vino % suma %, debe sumar exactamente 100 (RN-05)',
            p_codigo_vino, v_suma;
    END IF;
END;
$$;

COMMENT ON FUNCTION fn_validar_composicion_vino(integer) IS
'RN-05: valida que la composicion de un vino sume 100';

--- ======================================================================================
-- Cada fila de cliente debe tener exactamente una fila en su subtipo.

CREATE OR REPLACE FUNCTION fn_validar_subtipo_cliente(p_id_cliente INT)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_tipo tipo_cliente;
    v_cantidad INT;
BEGIN
    SELECT tipo
      INTO v_tipo
      FROM cliente
     WHERE id = p_id_cliente;

    -- Si el cliente fue eliminado, las filas de subtipo se borraron en
    -- cascada; no hay nada que validar
    IF NOT FOUND THEN
        RETURN;
    END IF;

    CASE v_tipo
        WHEN 'cliente_comun' THEN
            SELECT COUNT(*) INTO v_cantidad
              FROM cliente_comun WHERE id_cliente = p_id_cliente;
        WHEN 'socio_club' THEN
            SELECT COUNT(*) INTO v_cantidad
              FROM socio_club WHERE id_cliente = p_id_cliente;
        WHEN 'distribuidor' THEN
            SELECT COUNT(*) INTO v_cantidad
              FROM distribuidor WHERE id_cliente = p_id_cliente;
        WHEN 'exportador' THEN
            SELECT COUNT(*) INTO v_cantidad
              FROM exportador WHERE id_cliente = p_id_cliente;
    END CASE;

    IF v_cantidad <> 1 THEN
        RAISE EXCEPTION
            'El cliente % de tipo % debe tener exactamente una fila en su subtipo (encontradas: %)',
            p_id_cliente, v_tipo, v_cantidad;
    END IF;
END;
$$;

COMMENT ON FUNCTION fn_validar_subtipo_cliente(integer) IS
'Valida la totalidad de la jerarquia cliente';


COMMIT;