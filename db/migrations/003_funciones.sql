-- 003_funciones.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 2: Integridad y logica en la base de datos
-- Descripcion: 4 funciones requeridas en el TPI
--- ===============================================================================

-- fn_descuento_cliente
-- proposito: devolver el porcentaje de descuento según el tipo de cliente.
-- RN - 06 
-- utilizamos como parámetros: p_tipo_cliente (tipo_cliente): tipo del cliente
-- returna: numeric (fraccion del descuento: 0.10, 0.20, 0.30 o 0.0)
-- volatilidad: INMUTABLE (no lee ni escribe en la base de datos)

--- ===============================================================================
CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_tipo_cliente tipo_cliente)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    CASE p_tipo_cliente
        WHEN 'cliente_comun' THEN RETURN 0.00;
        WHEN 'socio_club' THEN RETURN 0.10;
        WHEN 'distribuidor' THEN RETURN 0.20;
        WHEN 'exportador' THEN RETURN 0.30;
    END CASE;
END;
$$;

