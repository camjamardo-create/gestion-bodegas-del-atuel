-- 02_seed_minimo.sql
-- Catalogo minimo para que la API tenga datos en un volumen nuevo.
-- No reemplaza la carga de la Etapa 3; solo permite probar y demostrar la API.

SET client_encoding = 'UTF8';

BEGIN;

INSERT INTO bodega (cuit, razon_social, calle, numero)
VALUES ('30999999991', 'Bodega API', 'Ruta 143', '100')
ON CONFLICT (cuit) DO NOTHING;

INSERT INTO transportista (razon_social, cuit, email, telefono, calle, numero)
SELECT 'Transportes API', '30777777771', 'api@example.com', '2604000000', 'San Martin', '50'
WHERE NOT EXISTS (
    SELECT 1 FROM transportista WHERE cuit = '30777777771'
);

INSERT INTO cepa (nombre, tipo)
SELECT 'Malbec', 'tinta'
WHERE NOT EXISTS (SELECT 1 FROM cepa WHERE lower(nombre) = 'malbec' AND tipo = 'tinta');

INSERT INTO cepa (nombre, tipo)
SELECT 'Cabernet Sauvignon', 'tinta'
WHERE NOT EXISTS (
    SELECT 1 FROM cepa WHERE lower(nombre) = 'cabernet sauvignon' AND tipo = 'tinta'
);

INSERT INTO maridaje (nombre, temperatura_servicio)
SELECT 'Queso y fiambres', 16
WHERE NOT EXISTS (SELECT 1 FROM maridaje WHERE lower(nombre) = 'queso y fiambres');

-- La FK localidad -> empleado es diferible, por eso se puede insertar primero
-- la localidad, luego la sala y por ultimo el encargado.
INSERT INTO localidad (codigo_postal, nombre, provincia, cuit_encargado)
VALUES ('5500', 'Ciudad de Mendoza', 'Mendoza', '20222222223')
ON CONFLICT (codigo_postal) DO NOTHING;

INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
SELECT 'San Martin', '100', 'lunes', '5500'
WHERE NOT EXISTS (SELECT 1 FROM sala_venta)
  AND EXISTS (SELECT 1 FROM localidad WHERE codigo_postal = '5500');

INSERT INTO empleado (cuit, tipo, nombre, apellido, salario, fecha_ingreso, id_sala)
SELECT '20222222223', 'encargado_regional', 'Encargado', 'API', 1000000, CURRENT_DATE, s.id
FROM sala_venta s
WHERE s.codigo_postal = '5500'
  AND NOT EXISTS (SELECT 1 FROM empleado WHERE cuit = '20222222223');

COMMIT;

DO $$
DECLARE
    v_bodega VARCHAR(11);
    v_sala INT;
    v_cepa1 INT;
    v_cepa2 INT;
    v_maridaje INT;
    v_vino INT;
BEGIN
    IF EXISTS (SELECT 1 FROM vino) THEN
        RETURN;
    END IF;

    SELECT cuit INTO v_bodega FROM bodega ORDER BY cuit LIMIT 1;
    SELECT id INTO v_sala FROM sala_venta ORDER BY id LIMIT 1;
    SELECT id INTO v_cepa1 FROM cepa WHERE lower(nombre) = 'malbec' ORDER BY id LIMIT 1;
    SELECT id INTO v_cepa2 FROM cepa WHERE lower(nombre) = 'cabernet sauvignon' ORDER BY id LIMIT 1;
    SELECT id INTO v_maridaje FROM maridaje ORDER BY id LIMIT 1;

    IF v_bodega IS NULL OR v_cepa1 IS NULL OR v_cepa2 IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO vino (nombre, tipo, "añada", volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Malbec API', 'tinto', 2024, 750, 13.50, 10000.00, v_bodega)
    RETURNING codigo INTO v_vino;

    INSERT INTO composicion (codigo_vino, id_cepa, porcentaje)
    VALUES (v_vino, v_cepa1, 60), (v_vino, v_cepa2, 40);

    IF v_maridaje IS NOT NULL THEN
        INSERT INTO vino_maridaje (codigo_vino, id_maridaje)
        VALUES (v_vino, v_maridaje);
    END IF;

    INSERT INTO stock_deposito (codigo_vino, cantidad)
    VALUES (v_vino, 100);

    IF v_sala IS NOT NULL THEN
        INSERT INTO stock_sala (id_sala, codigo_vino, cantidad)
        VALUES (v_sala, v_vino, 10);
    END IF;
END
$$;
