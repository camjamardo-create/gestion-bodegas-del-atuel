-- ============================================================================
-- consultas/update.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 5: consignas U1 a U6 de la seccion 8.1
--
-- Cada sentencia se prueba dentro de una transaccion:
--     BEGIN;  ->  control previo  ->  sentencia  ->  control posterior  ->  ROLLBACK;
-- El ROLLBACK deja la base en el estado de la Etapa 3; para aplicar el
-- cambio de forma definitiva se reemplaza el ROLLBACK por COMMIT.
--
-- Al final de cada bloque se indica el resultado obtenido en la corrida de
-- prueba (cantidad de filas afectadas) y las observaciones sobre triggers
-- y constraints.
-- ============================================================================

SET client_encoding = 'UTF8';


-- ============================================================================
-- U1. Recalcular el total de todos los comprobantes aplicando el descuento
--     que corresponde al tipo de cliente.
--
-- Estrategia: se recalcula el subtotal sumando los renglones (en lugar de
--   confiar en el valor almacenado) y se aplica fn_descuento_cliente(), que
--   devuelve la fraccion segun el tipo (comun 0, socio 0.10, distribuidor
--   0.20, exportador 0.30 o su descuento especial). La CTE calcula todo por
--   comprobante y el UPDATE escribe subtotal, descuento_aplicado,
--   descuento_total y total en una sola pasada, respetando el CHECK
--   ck_comprobante_total_calculo (total = subtotal - descuento_total).
--
-- Resultado obtenido: UPDATE 150000 filas. Los valores no cambian porque la
--   carga de la Etapa 3 ya genero los comprobantes con fn_descuento_cliente();
--   la sentencia deja el invariante verificado sobre toda la tabla.
-- ============================================================================
BEGIN;

-- Control previo: totales por tipo de cliente e importe inconsistente.
SELECT c.tipo,
       COUNT(*) AS comprobantes,
       SUM(co.total) AS total,
       SUM(co.descuento_total) AS descuento
FROM comprobante co
JOIN cliente c ON c.id = co.id_cliente
GROUP BY c.tipo
ORDER BY c.tipo;

SELECT COUNT(*) AS inconsistentes
FROM comprobante c
WHERE c.total IS DISTINCT FROM ROUND(c.subtotal * (1 - c.descuento_aplicado), 2)
   OR c.descuento_total IS DISTINCT FROM c.subtotal - c.total;

-- Sentencia
WITH calculo AS (
    SELECT c.numero,
           COALESCE(SUM(rc.subtotal_renglon), 0) AS subtotal,
           fn_descuento_cliente(c.id_cliente) AS descuento
    FROM comprobante c
    LEFT JOIN renglon_comprobante rc ON rc.numero_comprobante = c.numero
    GROUP BY c.numero, c.id_cliente
)
UPDATE comprobante c
SET subtotal = calculo.subtotal,
    descuento_aplicado = calculo.descuento,
    total = ROUND(calculo.subtotal * (1 - calculo.descuento), 2),
    descuento_total = calculo.subtotal
                      - ROUND(calculo.subtotal * (1 - calculo.descuento), 2)
FROM calculo
WHERE c.numero = calculo.numero;

-- Control posterior: mismos totales y verificacion del invariante.
SELECT c.tipo,
       COUNT(*) AS comprobantes,
       SUM(co.total) AS total,
       SUM(co.descuento_total) AS descuento
FROM comprobante co
JOIN cliente c ON c.id = co.id_cliente
GROUP BY c.tipo
ORDER BY c.tipo;

SELECT COUNT(*) AS inconsistentes
FROM comprobante c
WHERE c.total IS DISTINCT FROM ROUND(c.subtotal * (1 - c.descuento_aplicado), 2)
   OR c.descuento_total IS DISTINCT FROM c.subtotal - c.total;

ROLLBACK;


-- ============================================================================
-- U2. Aumentar un 20 % el salario de los empleados con mas de 5 anios de
--     antiguedad.
--
-- Estrategia: se reutiliza fn_antiguedad_anios(fecha_ingreso), que calcula
--   los anios cumplidos contra CURRENT_DATE. El UPDATE afecta solo a los
--   empleados que superan los 5 anios; el CHECK ck_salario_positivo sigue
--   valido porque el salario se multiplica por 1.20.
--
-- Resultado obtenido: UPDATE 44 filas (de 80 empleados).
-- ============================================================================
BEGIN;

-- Control previo
SELECT COUNT(*) FILTER (WHERE fn_antiguedad_anios(fecha_ingreso) > 5) AS con_mas_5,
       SUM(salario) AS total_salarios,
       ROUND(AVG(salario), 2) AS salario_promedio
FROM empleado;

-- Sentencia
UPDATE empleado
SET salario = ROUND(salario * 1.20, 2)
WHERE fn_antiguedad_anios(fecha_ingreso) > 5;

-- Control posterior
SELECT COUNT(*) FILTER (WHERE fn_antiguedad_anios(fecha_ingreso) > 5) AS con_mas_5,
       SUM(salario) AS total_salarios,
       ROUND(AVG(salario), 2) AS salario_promedio
FROM empleado;

SELECT cuit, nombre, apellido, fecha_ingreso, salario
FROM empleado
WHERE fn_antiguedad_anios(fecha_ingreso) > 5
ORDER BY salario DESC
LIMIT 5;

ROLLBACK;


-- ============================================================================
-- U3. Incrementar un 13 % el precio de los vinos elaborados por una bodega
--     determinada.
--
-- Parametro: cuit_bodega = '34100000158' (Malbec Reserva y otras 35
--   etiquetas). Cambiar el literal para otra bodega.
-- Estrategia: UPDATE con filtro por clave foranea, redondeando a 2 decimales
--   para respetar la escala de precio NUMERIC(10,2). El trigger
--   trg_vino_audita_precio registra cada cambio en auditoria_precio.
--
-- Resultado obtenido: UPDATE 36 filas; se insertaron 36 filas en
--   auditoria_precio (de 132 a 168), una por cada precio modificado.
-- ============================================================================
BEGIN;

-- Control previo
SELECT COUNT(*) AS vinos,
       MIN(precio) AS precio_min,
       ROUND(AVG(precio), 2) AS precio_promedio,
       MAX(precio) AS precio_max
FROM vino
WHERE cuit_bodega = '34100000158';

SELECT COUNT(*) AS auditoria_antes FROM auditoria_precio;

-- Sentencia
UPDATE vino
SET precio = ROUND(precio * 1.13, 2)
WHERE cuit_bodega = '34100000158';

-- Control posterior
SELECT COUNT(*) AS vinos,
       MIN(precio) AS precio_min,
       ROUND(AVG(precio), 2) AS precio_promedio,
       MAX(precio) AS precio_max
FROM vino
WHERE cuit_bodega = '34100000158';

SELECT COUNT(*) AS auditoria_despues FROM auditoria_precio;

-- Detalle de la auditoria generada por el trigger.
SELECT usuario, fecha_hora, precio_anterior, precio_nuevo, codigo_vino
FROM auditoria_precio
ORDER BY id DESC
LIMIT 5;

ROLLBACK;


-- ============================================================================
-- U4. En las salas cuyo dia de cierre es lunes cambiarlo a miercoles y
--     viceversa, en una sola sentencia.
--
-- Estrategia: un unico UPDATE con CASE que intercambia los dos valores del
--   enum dia_semana. El WHERE limita las filas a esos dos dias para no
--   reescribir las demas.
--
-- Resultado obtenido: UPDATE 8 filas (4 salas que cerraban lunes pasan a
--   miercoles y 4 que cerraban miercoles pasan a lunes).
-- ============================================================================
BEGIN;

-- Control previo
SELECT dia_cierre, COUNT(*) AS salas
FROM sala_venta
GROUP BY dia_cierre
ORDER BY dia_cierre;

-- Sentencia
UPDATE sala_venta
SET dia_cierre = CASE dia_cierre
                     WHEN 'lunes' THEN 'miercoles'::dia_semana
                     WHEN 'miercoles' THEN 'lunes'::dia_semana
                 END
WHERE dia_cierre IN ('lunes', 'miercoles');

-- Control posterior
SELECT dia_cierre, COUNT(*) AS salas
FROM sala_venta
GROUP BY dia_cierre
ORDER BY dia_cierre;

SELECT id, calle, numero, dia_cierre
FROM sala_venta
WHERE dia_cierre IN ('lunes', 'miercoles')
ORDER BY id;

ROLLBACK;


-- ============================================================================
-- U5. Aplicar un 15 % de descuento de precio a los 10 vinos menos vendidos
--     de toda la red.
--
-- Estrategia: CTE "ventas" que suma las botellas vendidas por vino usando
--   LEFT JOIN (un vino sin ventas cuenta 0, no desaparece); CTE
--   "menos_vendidos" ordena por botellas y desempata por codigo para que el
--   resultado sea determinista; el UPDATE aplica el 85 % del precio.
--   Cada cambio dispara trg_vino_audita_precio.
--
-- Resultado obtenido: UPDATE 10 filas; 10 filas nuevas en auditoria_precio.
-- ============================================================================
BEGIN;

-- Control previo: los 10 vinos menos vendidos.
SELECT v.codigo, v.nombre, v.precio, COALESCE(SUM(rc.cantidad), 0) AS botellas
FROM vino v
LEFT JOIN renglon_comprobante rc ON rc.codigo_vino = v.codigo
GROUP BY v.codigo, v.nombre, v.precio
ORDER BY botellas ASC, v.codigo
LIMIT 10;

-- Sentencia
WITH ventas AS (
    SELECT v.codigo, COALESCE(SUM(rc.cantidad), 0) AS botellas
    FROM vino v
    LEFT JOIN renglon_comprobante rc ON rc.codigo_vino = v.codigo
    GROUP BY v.codigo
), menos_vendidos AS (
    SELECT codigo
    FROM ventas
    ORDER BY botellas ASC, codigo
    LIMIT 10
)
UPDATE vino v
SET precio = ROUND(v.precio * 0.85, 2)
FROM menos_vendidos m
WHERE v.codigo = m.codigo;

-- Control posterior: los mismos 10 vinos con el precio nuevo.
SELECT v.codigo, v.nombre, v.precio, COALESCE(SUM(rc.cantidad), 0) AS botellas
FROM vino v
LEFT JOIN renglon_comprobante rc ON rc.codigo_vino = v.codigo
WHERE v.codigo IN (
    SELECT codigo
    FROM (
        SELECT v2.codigo, COALESCE(SUM(rc2.cantidad), 0) AS botellas
        FROM vino v2
        LEFT JOIN renglon_comprobante rc2 ON rc2.codigo_vino = v2.codigo
        GROUP BY v2.codigo
    ) t
    ORDER BY botellas ASC, codigo
    LIMIT 10
)
GROUP BY v.codigo, v.nombre, v.precio
ORDER BY botellas ASC, v.codigo;

ROLLBACK;


-- ============================================================================
-- U6. A los exportadores con mas de 3 permisos de exportacion, subirles el
--     descuento al 35 %.
--
-- Estrategia: subconsulta escalar correlacionada que cuenta los permisos de
--   cada exportador; el UPDATE fija descuento_especial = 0.35, valor que
--   respeta el CHECK ck_exportador_descuento_rango (0.30 a 0.35).
--
-- Resultado obtenido: UPDATE 304 filas.
-- ============================================================================
BEGIN;

-- Control previo
SELECT descuento_especial, COUNT(*) AS exportadores
FROM exportador
GROUP BY descuento_especial
ORDER BY descuento_especial NULLS FIRST;

SELECT COUNT(*) AS con_mas_de_3_permisos
FROM exportador e
WHERE (SELECT COUNT(*) FROM permiso p WHERE p.id_exportador = e.id_cliente) > 3;

-- Sentencia
UPDATE exportador e
SET descuento_especial = 0.35
WHERE (SELECT COUNT(*) FROM permiso p WHERE p.id_exportador = e.id_cliente) > 3;

-- Control posterior
SELECT descuento_especial, COUNT(*) AS exportadores
FROM exportador
GROUP BY descuento_especial
ORDER BY descuento_especial NULLS FIRST;

ROLLBACK;
