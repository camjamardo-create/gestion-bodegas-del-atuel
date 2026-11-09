-- 002_constraints.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 2.1: UNIQUE, CHECK, DEFAULT y acciones referenciales

SET client_encoding = 'UTF8';
BEGIN;

--- ===============================================================================
---  1. UNIQUE

-- Hay una única combinación de tipo_documento y numero_documento en cliente
ALTER TABLE cliente
    ADD CONSTRAINT uk_cliente_tipo_num_doc
        UNIQUE (tipo_documento, numero_documento);

-- Una parcela se cosecha como maximo una vez por campaña
-- "por cada campaña, hay una unica parcela perteneciente a una finca que genera un lote"
ALTER TABLE lote
    ADD CONSTRAINT uk_lote_parcela_finca_campaña
        UNIQUE (id_finca, numero_parcela, campaña);

-- Un mismo nombre de vino se distingue por su añada y volumen
ALTER TABLE vino
    ADD CONSTRAINT uk_vino_nombre_añada_volumen
        UNIQUE (nombre, añada, volumen_ml);

-- El cuit de cada transportista es unico a nivel global
ALTER TABLE transportista
    ADD CONSTRAINT uk_transportista_cuit
        UNIQUE (cuit);


--- ===============================================================================
---  2.1. CHECK propuestos por el TPI

-- RN-01 -> El precio del vino siempre es mayor que 0
ALTER TABLE vino
    ADD CONSTRAINT ck_vino_precio_positivo
        CHECK (precio > 0),

-- RN-15 -> La graduación alcoholica esta entre 5 y 20
    ADD CONSTRAINT ck_vino_graduacion
        CHECK (graduacion BETWEEN 5 AND 20);

-- RN-15 -> Cantidades, superficies, kilos y precios son siempre positivos.
ALTER TABLE empleado
    ADD CONSTRAINT ck_salario_positivo
        CHECK (salario > 0);

ALTER TABLE comprobante
    ADD CONSTRAINT ck_comprobante_total_no_negativo
        CHECK (total >= 0),

    ADD CONSTRAINT ck_comprobante_subtotal_no_negativo
        CHECK (subtotal >= 0),

    ADD CONSTRAINT ck_comprobante_descuento_total_no_negativo
        CHECK (descuento_total >= 0);

ALTER TABLE auditoria_precio
    ADD CONSTRAINT ck_auditoria_precio_nuevo_positivo
        CHECK (precio_nuevo > 0),

    ADD CONSTRAINT ck_auditoria_precio_anterior_positivo
        CHECK (precio_anterior > 0);

ALTER TABLE renglon_ingreso
    ADD CONSTRAINT ck_renglon_ingreso_cantidad_positiva
        CHECK (cantidad > 0);

ALTER TABLE analisis_calidad
    ADD CONSTRAINT ck_analisis_ph
        CHECK (ph BETWEEN 0 AND 14), -- El pH es una escala de 0 a 14

    ADD CONSTRAINT ck_analisis_brix
        CHECK (brix > 0 AND brix <= 100), -- El grado Brix es un porcentaje de sólidos solubles

    ADD CONSTRAINT ck_analisis_acidez
        CHECK (acidez > 0);

ALTER TABLE lote
    ADD CONSTRAINT ck_lote_kg_cosecha_positivo
        CHECK (kg_cosecha > 0);

ALTER TABLE parcela
    ADD CONSTRAINT ck_parcela_superficie_positiva
        CHECK (superficie > 0);

ALTER TABLE finca
    ADD CONSTRAINT ck_finca_superficie_positiva
        CHECK (superficie > 0);

ALTER TABLE renglon_transferencia
    ADD CONSTRAINT ck_renglon_transferencia_cantidad_positiva
        CHECK (cantidad > 0);

ALTER TABLE renglon_comprobante
    ADD CONSTRAINT ck_renglon_comprobante_cantidad_positiva
        CHECK (cantidad > 0),

    ADD CONSTRAINT ck_renglon_comprobante_precio_positivo
        CHECK (precio_unitario > 0);

-- RN-09 -> El stock nunca es negativo 
ALTER TABLE stock_deposito
    ADD CONSTRAINT ck_stock_deposito_cantidad_no_negativa
        CHECK (cantidad >= 0);

ALTER TABLE stock_sala
    ADD CONSTRAINT ck_stock_sala_cantidad_no_negativa
        CHECK (cantidad >= 0);

-- RN-06 -> El descuento especial es una fraccion entre 0.3 y 0.35.
-- NULL significa "usar el descuento base del tipo"
ALTER TABLE exportador
    ADD CONSTRAINT ck_exportador_descuento_rango
        CHECK (descuento_especial IS NULL OR descuento_especial=0.35);

-- RN-07 -> El vencimiento de un permiso es posterior a la emisión
ALTER TABLE permiso
    ADD CONSTRAINT ck_permiso_fechas
        CHECK (fecha_vencimiento > fecha_emision);


---  2.2. CHECK de nuestro diseño

-- Volumenes de vino restringidos
ALTER TABLE vino
    ADD CONSTRAINT ck_vino_volumen
        CHECK (volumen_ml IN (187, 375, 750, 1500, 3000)),

-- Añada controlada
    ADD CONSTRAINT ck_vino_añada
        CHECK (añada BETWEEN 1990 AND 2100);

-- Año plantacion parcela controlado
ALTER TABLE parcela
    ADD CONSTRAINT ck_parcela_año_plantacion
        CHECK (año_plantacion BETWEEN 1990 AND 2100);

-- Composicion positiva y a lo sumo 100 (la suma igual a 100 va en un trigger)
ALTER TABLE composicion
    ADD CONSTRAINT ck_composicion_porcentaje_rango
        CHECK (porcentaje > 0 AND porcentaje <= 100);

-- Check total de comprobante (se calcula en un trigger pero chequeamos)
ALTER TABLE comprobante
    ADD CONSTRAINT ck_comprobante_total_calculo
        CHECK (total = subtotal - descuento_total);

-- RN-06 -> El descuento aplicado es una fraccion entre 0 y 1
ALTER TABLE comprobante
    ADD CONSTRAINT ck_comprobante_descuento_aplicado
        CHECK (descuento_aplicado BETWEEN 0 AND 1);

-- Cliente con nombre y apellido o con razon social
ALTER TABLE cliente
    ADD CONSTRAINT ck_cliente_datos
        CHECK (
            (tipo IN ('cliente_comun','socio_club')
                AND nombre IS NOT NULL AND apellido IS NOT NULL)
            OR
            (tipo IN ('distribuidor','exportador')
                AND razon_social IS NOT NULL)
        );

-- Cada subtabla fija su tipo: garantiza la disyuncion de la jerarquia
ALTER TABLE cliente_comun
    ADD CONSTRAINT ck_cliente_comun_tipo
        CHECK (tipo = 'cliente_comun');

ALTER TABLE socio_club
    ADD CONSTRAINT ck_socio_club_tipo
        CHECK (tipo = 'socio_club');

ALTER TABLE distribuidor
    ADD CONSTRAINT ck_distribuidor_tipo
        CHECK (tipo = 'distribuidor');

ALTER TABLE exportador
    ADD CONSTRAINT ck_exportador_tipo
        CHECK (tipo = 'exportador');


--- ===============================================================================
--- 3. Valores por defecto (DEFAULT)

-- RN-10 / RN-11 -> Todo ingreso y toda transferencia nacen en confeccion
ALTER TABLE ingreso
    ALTER COLUMN estado SET DEFAULT 'en_confeccion';

ALTER TABLE transferencia
    ALTER COLUMN estado SET DEFAULT 'en_confeccion';

-- RN-11 -> La transferencia se confecciona con la fecha actual
ALTER TABLE transferencia
    ALTER COLUMN fecha_confeccion SET DEFAULT CURRENT_DATE;

-- El alta del cliente se registra con la fecha actual
ALTER TABLE cliente
    ALTER COLUMN fecha_alta SET DEFAULT CURRENT_DATE;

-- El stock arranca en cero hasta que se registren movimientos
ALTER TABLE stock_deposito
    ALTER COLUMN cantidad SET DEFAULT 0;

ALTER TABLE stock_sala
    ALTER COLUMN cantidad SET DEFAULT 0;

-- Se registra quien hizo el cambio de precio (lo hace el trigger pero se garantiza)
ALTER TABLE auditoria_precio
    ALTER COLUMN usuario SET DEFAULT current_user;

-- Subtotal, descuento y total del comprobante inician en 0. Se cumple el check desde el primer momento
ALTER TABLE comprobante
    ALTER COLUMN subtotal SET DEFAULT 0,
    ALTER COLUMN descuento_aplicado SET DEFAULT 0,
    ALTER COLUMN descuento_total SET DEFAULT 0,
    ALTER COLUMN total SET DEFAULT 0;


--- ===============================================================================
------- 4. Acciones referenciales a los eventos ON UPDATE, ON DELETE en cada FK


-- No se elimina una localidad con salas de venta asociadas
-- Si cambia el codigo postal, se propaga en sus salas
ALTER TABLE sala_venta
    DROP CONSTRAINT fk_sala_venta_localidad,
    ADD CONSTRAINT fk_sala_venta_localidad
        FOREIGN KEY (codigo_postal) REFERENCES localidad (codigo_postal)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;

-- No se elimina una sala con empleados asociados
-- No se actualiza manualmente el id de sala de venta
ALTER TABLE empleado
    DROP CONSTRAINT fk_empleado_sala_venta,
    ADD CONSTRAINT fk_empleado_sala_venta
        FOREIGN KEY (id_sala) REFERENCES sala_venta (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se puede eliminar un encargado con una localidad a su cargo
-- Si se modifica el cuit de empleado, se propaga a localidad
-- Si se modifica el tipo de empleado, CHECK de localidad lo rechaza
ALTER TABLE localidad
    DROP CONSTRAINT fk_localidad_encargado,
    ADD CONSTRAINT fk_localidad_encargado
        FOREIGN KEY (cuit_encargado, tipo_encargado) REFERENCES empleado (cuit, tipo)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

-- Si se elimina un transportista, se eliminan sus coberturas
-- No se actualiza manualmente el código de transportista (columna GENERATED ALWAYS)
ALTER TABLE transportista_cubre_localidad
    DROP CONSTRAINT fk_transportista_cubre_localidad_transportista,
    ADD CONSTRAINT fk_transportista_cubre_localidad_transportista
        FOREIGN KEY (codigo_transportista) REFERENCES transportista (codigo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT,

-- Si se elimina una localidad, se eliminan las coberturas sobre ella
-- Si cambia el código postal de localidad, se propaga a las coberturas
    DROP CONSTRAINT fk_transportista_cubre_localidad_localidad,
    ADD CONSTRAINT fk_transportista_cubre_localidad_localidad
        FOREIGN KEY (codigo_postal_localidad) REFERENCES localidad (codigo_postal)
        ON DELETE CASCADE
        ON UPDATE CASCADE;

-- No se elimina un transportista con ingresos asociados
-- No se actualiza el codigo de transportista
ALTER TABLE ingreso
    DROP CONSTRAINT fk_ingreso_transportista,
    ADD CONSTRAINT fk_ingreso_transportista
        FOREIGN KEY (codigo_transportista) REFERENCES transportista (codigo)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se elimina una bodega con ingresos asociados
-- Si cambia el cuit de la bodega (clave natural), se propaga a sus ingresos
ALTER TABLE ingreso
    DROP CONSTRAINT fk_ingreso_bodega,
    ADD CONSTRAINT fk_ingreso_bodega
        FOREIGN KEY (cuit_bodega) REFERENCES bodega (cuit)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;

-- No se elimina una localidad con clientes asociados
-- Si cambia el codigo postal de localidad, se propaga a sus clientes
ALTER TABLE cliente
    DROP CONSTRAINT fk_cliente_localidad,
    ADD CONSTRAINT fk_cliente_localidad
        FOREIGN KEY (codigo_postal) REFERENCES localidad (codigo_postal)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;

-- Si se elimina un cliente, se elimina su fila de subtipo
-- No se actualiza el id de cliente ni se cambia su tipo
ALTER TABLE cliente_comun
    DROP CONSTRAINT fk_cliente_comun_cliente,
    ADD CONSTRAINT fk_cliente_comun_cliente
        FOREIGN KEY (id_cliente, tipo) REFERENCES cliente (id, tipo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

ALTER TABLE socio_club
    DROP CONSTRAINT fk_socio_club_cliente,
    ADD CONSTRAINT fk_socio_club_cliente
        FOREIGN KEY (id_cliente, tipo) REFERENCES cliente (id, tipo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

ALTER TABLE distribuidor
    DROP CONSTRAINT fk_distribuidor_cliente,
    ADD CONSTRAINT fk_distribuidor_cliente
        FOREIGN KEY (id_cliente, tipo) REFERENCES cliente (id, tipo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

ALTER TABLE exportador
    DROP CONSTRAINT fk_exportador_cliente,
    ADD CONSTRAINT fk_exportador_cliente
        FOREIGN KEY (id_cliente, tipo) REFERENCES cliente (id, tipo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- Si se elimina un exportador, se eliminan sus permisos
-- Si se corrige el id de un exportador, se propaga a sus permisos
ALTER TABLE permiso
    DROP CONSTRAINT fk_permiso_exportador,
    ADD CONSTRAINT fk_permiso_exportador
        FOREIGN KEY (id_exportador) REFERENCES exportador (id_cliente)
        ON DELETE CASCADE
        ON UPDATE CASCADE;


-- Una parcela no existe sin su finca (entidad debil)
-- No se actualiza manualmente el id de finca (clave subrogada)
ALTER TABLE parcela
    DROP CONSTRAINT fk_parcela_finca,
    ADD CONSTRAINT fk_parcela_finca
        FOREIGN KEY (id_finca) REFERENCES finca (id)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- No se elimina una cepa plantada en alguna parcela
-- No se actualiza manualmente el id de cepa (clave subrogada)
ALTER TABLE parcela
    DROP CONSTRAINT fk_parcela_cepa,
    ADD CONSTRAINT fk_parcela_cepa
        FOREIGN KEY (id_cepa) REFERENCES cepa (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se elimina una bodega con lotes entregados
-- Si cambia el cuit de bodega, se propaga a sus lotes
ALTER TABLE lote
    DROP CONSTRAINT fk_lote_bodega,
    ADD CONSTRAINT fk_lote_bodega
        FOREIGN KEY (cuit_bodega) REFERENCES bodega (cuit)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;

-- No se elimina una parcela con lotes cosechados
-- Si se corrige el numero de parcela, se propaga a sus lotes
ALTER TABLE lote
    DROP CONSTRAINT fk_lote_parcela,
    ADD CONSTRAINT fk_lote_parcela
        FOREIGN KEY (id_finca, numero_parcela) REFERENCES parcela (id_finca, numero_parcela)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;

-- Si se elimina un lote se eliminan sus analisis asociados
-- No se actualiza manualmente el numero de lote (clave subrogada)
ALTER TABLE analisis_calidad
    DROP CONSTRAINT fk_analisis_calidad_lote,
    ADD CONSTRAINT fk_analisis_calidad_lote
        FOREIGN KEY (numero_lote) REFERENCES lote (numero_lote)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- No se elimina una bodega con vinos asociados
-- Si cambia el cuit de bodega, se propaga a sus vinos
ALTER TABLE vino
    DROP CONSTRAINT fk_vino_bodega,
    ADD CONSTRAINT fk_vino_bodega
        FOREIGN KEY (cuit_bodega) REFERENCES bodega (cuit)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;

-- Si se elimina un vino, se eliminan sus filas de composicion
-- No se actualiza manualmente el codigo de vino
ALTER TABLE composicion
    DROP CONSTRAINT fk_composicion_vino,
    ADD CONSTRAINT fk_composicion_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT,

-- No se elimina una cepa que compone algun vino
    DROP CONSTRAINT fk_composicion_cepa,
    ADD CONSTRAINT fk_composicion_cepa
        FOREIGN KEY (id_cepa) REFERENCES cepa (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se elimina un vino con registro de stock en el depósito
-- No se actualiza el codigo de vino
ALTER TABLE stock_deposito
    DROP CONSTRAINT fk_stock_deposito_vino,
    ADD CONSTRAINT fk_stock_deposito_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- Si se elimina un vino, se eliminan sus asociaciones con maridajes
-- No se actualiza el codigo de vino
ALTER TABLE vino_maridaje
    DROP CONSTRAINT fk_vino_maridaje_vino,
    ADD CONSTRAINT fk_vino_maridaje_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT,

-- No se elimina un maridaje asociado a algun vino
-- No se actualiza el id de maridaje
    DROP CONSTRAINT fk_vino_maridaje_maridaje,
    ADD CONSTRAINT fk_vino_maridaje_maridaje
        FOREIGN KEY (id_maridaje) REFERENCES maridaje (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se elimina un vino con renglones de ingreso asociados
-- No se actualiza el codigo de vino
ALTER TABLE renglon_ingreso
    DROP CONSTRAINT fk_renglon_ingreso_vino,
    ADD CONSTRAINT fk_renglon_ingreso_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- Los renglones no existen sin su ingreso: se eliminan con el
-- No se actualiza el codigo de ingreso
ALTER TABLE renglon_ingreso
    DROP CONSTRAINT fk_renglon_ingreso_ingreso,
    ADD CONSTRAINT fk_renglon_ingreso_ingreso
        FOREIGN KEY (codigo_ingreso) REFERENCES ingreso (codigo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- Si se elimina un vino, se eliminan sus registros de auditoria
-- No se actualiza el codigo de vino
ALTER TABLE auditoria_precio
    DROP CONSTRAINT fk_auditoria_precio_vino,
    ADD CONSTRAINT fk_auditoria_precio_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- Una sala no se elimina si tiene registros de stock
-- No se actualiza el id de sala
ALTER TABLE stock_sala
    DROP CONSTRAINT fk_stock_sala_sala,
    ADD CONSTRAINT fk_stock_sala_sala
        FOREIGN KEY (id_sala) REFERENCES sala_venta (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

-- No se elimina un vino con registros de stock en alguna sala
    DROP CONSTRAINT fk_stock_sala_vino,
    ADD CONSTRAINT fk_stock_sala_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se elimina un cliente con comprobantes asociados
-- No se actualiza el id de cliente
ALTER TABLE comprobante
    DROP CONSTRAINT fk_comprobante_cliente,
    ADD CONSTRAINT fk_comprobante_cliente
        FOREIGN KEY (id_cliente) REFERENCES cliente (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se elimina una sala con comprobantes asociados
-- No se actualiza el id de sala
ALTER TABLE comprobante
    DROP CONSTRAINT fk_comprobante_sala,
    ADD CONSTRAINT fk_comprobante_sala
        FOREIGN KEY (id_sala_venta) REFERENCES sala_venta (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- Si se elimina un comprobante, se eliminan sus renglones
-- No se actualiza el numero de comprobante
ALTER TABLE renglon_comprobante
    DROP CONSTRAINT fk_renglon_comprobante_comprobante,
    ADD CONSTRAINT fk_renglon_comprobante_comprobante
        FOREIGN KEY (numero_comprobante) REFERENCES comprobante (numero)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- No se elimina un vino con renglones de comprobante asociados
-- No se actualiza el codigo de vino
ALTER TABLE renglon_comprobante
    DROP CONSTRAINT fk_renglon_comprobante_vino,
    ADD CONSTRAINT fk_renglon_comprobante_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se elimina una sala de venta con transferencias asociadas
-- No se actualiza el id de sala
ALTER TABLE transferencia
    DROP CONSTRAINT fk_transferencia_sala_venta,
    ADD CONSTRAINT fk_transferencia_sala_venta
        FOREIGN KEY (id_sala_venta) REFERENCES sala_venta (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- Si se elimina una transferencia, se eliminan sus renglones
-- No se actualiza el numero de transferencia
ALTER TABLE renglon_transferencia
    DROP CONSTRAINT fk_renglon_transferencia_transferencia,
    ADD CONSTRAINT fk_renglon_transferencia_transferencia
        FOREIGN KEY (numero_transferencia) REFERENCES transferencia (numero)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- No se elimina un vino con renglones de transferencia asociados
-- No se actualiza el codigo de vino
ALTER TABLE renglon_transferencia
    DROP CONSTRAINT fk_renglon_transferencia_vino,
    ADD CONSTRAINT fk_renglon_transferencia_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;







COMMIT;