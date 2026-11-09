-- 002_constraints.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 2.1: UNIQUE, CHECK, DEFAULT y acciones referenciales
--
-- Criterio general para las acciones referenciales:
--   * ON DELETE RESTRICT en datos maestros y en movimientos con historia
--     (no se borra un maestro que todavia tiene dependencias).
--   * ON DELETE CASCADE solo en filas de detalle que no existen sin su
--     cabecera (renglones, subtipos, composiciones, stock, coberturas).
--   * ON UPDATE CASCADE en claves naturales (cuit, codigo_postal, numero de
--     parcela) para propagar correcciones.
--   * ON UPDATE RESTRICT en claves subrogadas (IDENTITY), que no se corrigen
--     a mano.

SET client_encoding = 'UTF8';

BEGIN;

-- ============================================================================
-- 1. Acciones referenciales (ON UPDATE / ON DELETE) de cada FK
-- ============================================================================

-- No se elimina una localidad con salas de venta asociadas.
-- Si cambia el codigo postal, se propaga a sus salas.
ALTER TABLE sala_venta
    DROP CONSTRAINT fk_sala_venta_localidad,
    ADD CONSTRAINT fk_sala_venta_localidad
        FOREIGN KEY (codigo_postal) REFERENCES localidad (codigo_postal)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;

-- No se elimina una sala con empleados asociados.
-- No se actualiza manualmente el id de sala de venta.
ALTER TABLE empleado
    DROP CONSTRAINT fk_empleado_sala_venta,
    ADD CONSTRAINT fk_empleado_sala_venta
        FOREIGN KEY (id_sala) REFERENCES sala_venta (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se puede eliminar un encargado con una localidad a su cargo.
-- Si se modifica el cuit del empleado, se propaga a localidad.
-- Si se modifica el tipo de empleado, el CHECK de localidad lo rechaza.
ALTER TABLE localidad
    DROP CONSTRAINT fk_localidad_encargado,
    ADD CONSTRAINT fk_localidad_encargado
        FOREIGN KEY (cuit_encargado, tipo_encargado) REFERENCES empleado (cuit, tipo)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

-- Si se elimina un transportista, se eliminan sus coberturas.
-- No se actualiza manualmente el codigo de transportista (IDENTITY).
ALTER TABLE transportista_cubre_localidad
    DROP CONSTRAINT fk_transportista_cubre_localidad_transportista,
    ADD CONSTRAINT fk_transportista_cubre_localidad_transportista
        FOREIGN KEY (codigo_transportista) REFERENCES transportista (codigo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- Si se elimina una localidad, se eliminan las coberturas sobre ella.
-- Si cambia el codigo postal de localidad, se propaga a las coberturas.
ALTER TABLE transportista_cubre_localidad
    DROP CONSTRAINT fk_transportista_cubre_localidad_localidad,
    ADD CONSTRAINT fk_transportista_cubre_localidad_localidad
        FOREIGN KEY (codigo_postal_localidad) REFERENCES localidad (codigo_postal)
        ON DELETE CASCADE
        ON UPDATE CASCADE;

-- No se elimina un transportista con ingresos asociados (RN-14).
-- No se actualiza manualmente el codigo de transportista (IDENTITY).
ALTER TABLE ingreso
    DROP CONSTRAINT fk_ingreso_transportista,
    ADD CONSTRAINT fk_ingreso_transportista
        FOREIGN KEY (codigo_transportista) REFERENCES transportista (codigo)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se elimina una bodega con ingresos asociados.
-- Si cambia el cuit de bodega, se propaga a sus ingresos.
ALTER TABLE ingreso
    DROP CONSTRAINT fk_ingreso_bodega,
    ADD CONSTRAINT fk_ingreso_bodega
        FOREIGN KEY (cuit_bodega) REFERENCES bodega (cuit)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;

-- No se elimina una localidad con clientes asociados.
-- Si cambia el codigo postal de localidad, se propaga a sus clientes.
ALTER TABLE cliente
    DROP CONSTRAINT fk_cliente_localidad,
    ADD CONSTRAINT fk_cliente_localidad
        FOREIGN KEY (codigo_postal) REFERENCES localidad (codigo_postal)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;

-- Si se elimina un cliente, se elimina su fila de subtipo.
-- No se actualiza manualmente el id de cliente ni se cambia su tipo.
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

-- Si se elimina un exportador, se eliminan sus permisos.
-- Si se corrige el id de un exportador, se propaga a sus permisos.
ALTER TABLE permiso
    DROP CONSTRAINT fk_permiso_exportador,
    ADD CONSTRAINT fk_permiso_exportador
        FOREIGN KEY (id_exportador) REFERENCES exportador (id_cliente)
        ON DELETE CASCADE
        ON UPDATE CASCADE;

-- Una parcela no existe sin su finca (entidad debil).
-- No se actualiza manualmente el id de finca (IDENTITY).
ALTER TABLE parcela
    DROP CONSTRAINT fk_parcela_finca,
    ADD CONSTRAINT fk_parcela_finca
        FOREIGN KEY (id_finca) REFERENCES finca (id)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- No se elimina una cepa plantada en alguna parcela.
-- No se actualiza manualmente el id de cepa (IDENTITY).
ALTER TABLE parcela
    DROP CONSTRAINT fk_parcela_cepa,
    ADD CONSTRAINT fk_parcela_cepa
        FOREIGN KEY (id_cepa) REFERENCES cepa (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se elimina una bodega con lotes entregados.
-- Si cambia el cuit de bodega, se propaga a sus lotes.
ALTER TABLE lote
    DROP CONSTRAINT fk_lote_bodega,
    ADD CONSTRAINT fk_lote_bodega
        FOREIGN KEY (cuit_bodega) REFERENCES bodega (cuit)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;

-- No se elimina una parcela con lotes cosechados.
-- Si se corrige el numero de parcela, se propaga a sus lotes.
ALTER TABLE lote
    DROP CONSTRAINT fk_lote_parcela,
    ADD CONSTRAINT fk_lote_parcela
        FOREIGN KEY (id_finca, numero_parcela) REFERENCES parcela (id_finca, numero_parcela)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;

-- Si se elimina un lote, se eliminan sus analisis de calidad.
-- No se actualiza manualmente el numero de lote (IDENTITY).
ALTER TABLE analisis_calidad
    DROP CONSTRAINT fk_analisis_calidad_lote,
    ADD CONSTRAINT fk_analisis_calidad_lote
        FOREIGN KEY (numero_lote) REFERENCES lote (numero_lote)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- No se elimina una bodega con vinos asociados (RN-14).
-- Si cambia el cuit de bodega, se propaga a sus vinos.
ALTER TABLE vino
    DROP CONSTRAINT fk_vino_bodega,
    ADD CONSTRAINT fk_vino_bodega
        FOREIGN KEY (cuit_bodega) REFERENCES bodega (cuit)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;

-- Si se elimina un vino, su composicion pierde sentido y se elimina.
-- No se actualiza manualmente el codigo de vino (IDENTITY).
ALTER TABLE composicion
    DROP CONSTRAINT fk_composicion_vino,
    ADD CONSTRAINT fk_composicion_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- No se elimina una cepa que compone uno o mas vinos.
-- No se actualiza manualmente el id de cepa (IDENTITY).
ALTER TABLE composicion
    DROP CONSTRAINT fk_composicion_cepa,
    ADD CONSTRAINT fk_composicion_cepa
        FOREIGN KEY (id_cepa) REFERENCES cepa (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- Si se elimina un vino, su fila de stock del deposito pierde sentido.
-- No se actualiza manualmente el codigo de vino (IDENTITY).
ALTER TABLE stock_deposito
    DROP CONSTRAINT fk_stock_deposito_vino,
    ADD CONSTRAINT fk_stock_deposito_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- Si se elimina un vino, se eliminan sus maridajes recomendados.
-- No se actualiza manualmente el codigo de vino (IDENTITY).
ALTER TABLE vino_maridaje
    DROP CONSTRAINT fk_vino_maridaje_vino,
    ADD CONSTRAINT fk_vino_maridaje_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- No se elimina un maridaje que este recomendado para algun vino.
-- No se actualiza manualmente el id de maridaje (IDENTITY).
ALTER TABLE vino_maridaje
    DROP CONSTRAINT fk_vino_maridaje_maridaje,
    ADD CONSTRAINT fk_vino_maridaje_maridaje
        FOREIGN KEY (id_maridaje) REFERENCES maridaje (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se elimina un vino con movimientos de ingreso (RN-14).
-- No se actualiza manualmente el codigo de vino (IDENTITY).
ALTER TABLE renglon_ingreso
    DROP CONSTRAINT fk_renglon_ingreso_vino,
    ADD CONSTRAINT fk_renglon_ingreso_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- Si se elimina un ingreso, se eliminan sus renglones.
-- No se actualiza manualmente el codigo de ingreso (IDENTITY).
ALTER TABLE renglon_ingreso
    DROP CONSTRAINT fk_renglon_ingreso_ingreso,
    ADD CONSTRAINT fk_renglon_ingreso_ingreso
        FOREIGN KEY (codigo_ingreso) REFERENCES ingreso (codigo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- La auditoria de precio se conserva: no se elimina un vino auditado.
-- No se actualiza manualmente el codigo de vino (IDENTITY).
ALTER TABLE auditoria_precio
    DROP CONSTRAINT fk_auditoria_precio_vino,
    ADD CONSTRAINT fk_auditoria_precio_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- Si se elimina una sala, se elimina su stock.
-- No se actualiza manualmente el id de sala (IDENTITY).
ALTER TABLE stock_sala
    DROP CONSTRAINT fk_stock_sala_sala,
    ADD CONSTRAINT fk_stock_sala_sala
        FOREIGN KEY (id_sala) REFERENCES sala_venta (id)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- Si se elimina un vino, su stock en salas pierde sentido.
-- No se actualiza manualmente el codigo de vino (IDENTITY).
ALTER TABLE stock_sala
    DROP CONSTRAINT fk_stock_sala_vino,
    ADD CONSTRAINT fk_stock_sala_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- No se elimina un cliente con comprobantes asociados.
-- No se actualiza manualmente el id de cliente (IDENTITY).
ALTER TABLE comprobante
    DROP CONSTRAINT fk_comprobante_cliente,
    ADD CONSTRAINT fk_comprobante_cliente
        FOREIGN KEY (id_cliente) REFERENCES cliente (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se elimina una sala con comprobantes asociados.
-- No se actualiza manualmente el id de sala (IDENTITY).
ALTER TABLE comprobante
    DROP CONSTRAINT fk_comprobante_sala,
    ADD CONSTRAINT fk_comprobante_sala
        FOREIGN KEY (id_sala_venta) REFERENCES sala_venta (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- Si se elimina un comprobante, se eliminan sus renglones.
-- No se actualiza manualmente el numero de comprobante (IDENTITY).
ALTER TABLE renglon_comprobante
    DROP CONSTRAINT fk_renglon_comprobante_comprobante,
    ADD CONSTRAINT fk_renglon_comprobante_comprobante
        FOREIGN KEY (numero_comprobante) REFERENCES comprobante (numero)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- No se elimina un vino con movimientos de venta (RN-14).
-- No se actualiza manualmente el codigo de vino (IDENTITY).
ALTER TABLE renglon_comprobante
    DROP CONSTRAINT fk_renglon_comprobante_vino,
    ADD CONSTRAINT fk_renglon_comprobante_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- No se elimina una sala con transferencias asociadas.
-- No se actualiza manualmente el id de sala (IDENTITY).
ALTER TABLE transferencia
    DROP CONSTRAINT fk_transferencia_sala_venta,
    ADD CONSTRAINT fk_transferencia_sala_venta
        FOREIGN KEY (id_sala_venta) REFERENCES sala_venta (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- Si se elimina una transferencia, se eliminan sus renglones.
-- No se actualiza manualmente el numero de transferencia (IDENTITY).
ALTER TABLE renglon_transferencia
    DROP CONSTRAINT fk_renglon_transferencia_transferencia,
    ADD CONSTRAINT fk_renglon_transferencia_transferencia
        FOREIGN KEY (numero_transferencia) REFERENCES transferencia (numero)
        ON DELETE CASCADE
        ON UPDATE RESTRICT;

-- No se elimina un vino con movimientos de transferencia (RN-14).
-- No se actualiza manualmente el codigo de vino (IDENTITY).
ALTER TABLE renglon_transferencia
    DROP CONSTRAINT fk_renglon_transferencia_vino,
    ADD CONSTRAINT fk_renglon_transferencia_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT;

-- ============================================================================
-- 2. Restricciones UNIQUE adicionales a las claves primarias
-- ============================================================================

-- Un mismo nombre de vino se distingue por añada y presentacion.
ALTER TABLE vino
    ADD CONSTRAINT uk_vino_nombre_anada_volumen
        UNIQUE (nombre, añada, volumen_ml);

-- Una parcela se cosecha como maximo una vez por campaña (RN-04).
ALTER TABLE lote
    ADD CONSTRAINT uk_lote_parcela_campana
        UNIQUE (id_finca, numero_parcela, campaña);

-- El CUIT identifica al transportista aunque su PK sea el codigo subrogado.
ALTER TABLE transportista
    ADD CONSTRAINT uk_transportista_cuit
        UNIQUE (cuit);

-- El nombre de la cepa es unico dentro del catalogo real.
ALTER TABLE cepa
    ADD CONSTRAINT uk_cepa_nombre
        UNIQUE (nombre);

-- El nombre del maridaje es unico dentro del catalogo.
ALTER TABLE maridaje
    ADD CONSTRAINT uk_maridaje_nombre
        UNIQUE (nombre);

-- ============================================================================
-- 3. Restricciones CHECK
-- ============================================================================

-- El precio de venta es unico para la red y siempre positivo (RN-01).
ALTER TABLE vino
    ADD CONSTRAINT chk_vino_precio_positivo
        CHECK (precio > 0);

-- La graduacion alcoholica esta entre 5 y 20 grados (RN-15).
ALTER TABLE vino
    ADD CONSTRAINT chk_vino_graduacion_rango
        CHECK (graduacion BETWEEN 5 AND 20);

-- La presentacion y la añada son valores validos.
ALTER TABLE vino
    ADD CONSTRAINT chk_vino_volumen_positivo
        CHECK (volumen_ml > 0);

ALTER TABLE vino
    ADD CONSTRAINT chk_vino_anada_rango
        CHECK (añada BETWEEN 1900 AND 2100);

-- Superficies, kilos y cantidades siempre positivos (RN-15).
ALTER TABLE finca
    ADD CONSTRAINT chk_finca_superficie_positiva
        CHECK (superficie > 0);

ALTER TABLE parcela
    ADD CONSTRAINT chk_parcela_superficie_positiva
        CHECK (superficie > 0);

ALTER TABLE lote
    ADD CONSTRAINT chk_lote_kg_positivo
        CHECK (kg_cosecha > 0);

-- Valores fisicamente posibles para un analisis de calidad.
ALTER TABLE analisis_calidad
    ADD CONSTRAINT chk_analisis_ph_rango
        CHECK (ph BETWEEN 0 AND 14);

ALTER TABLE analisis_calidad
    ADD CONSTRAINT chk_analisis_brix_positivo
        CHECK (brix >= 0);

ALTER TABLE analisis_calidad
    ADD CONSTRAINT chk_analisis_acidez_positiva
        CHECK (acidez > 0);

-- El permiso vence despues de su emision (RN-07, CHECK entre columnas).
ALTER TABLE permiso
    ADD CONSTRAINT chk_permiso_fechas
        CHECK (fecha_vencimiento > fecha_emision);

-- Cada cepa aporta un porcentaje de corte positivo y a lo sumo 100.
ALTER TABLE composicion
    ADD CONSTRAINT chk_composicion_porcentaje
        CHECK (porcentaje > 0 AND porcentaje <= 100);

-- El stock nunca es negativo (RN-09).
ALTER TABLE stock_deposito
    ADD CONSTRAINT chk_stock_deposito_cantidad
        CHECK (cantidad >= 0);

ALTER TABLE stock_sala
    ADD CONSTRAINT chk_stock_sala_cantidad
        CHECK (cantidad >= 0);

-- Las cantidades de renglones son positivas (RN-15).
ALTER TABLE renglon_ingreso
    ADD CONSTRAINT chk_renglon_ingreso_cantidad
        CHECK (cantidad > 0);

ALTER TABLE renglon_transferencia
    ADD CONSTRAINT chk_renglon_transferencia_cantidad
        CHECK (cantidad > 0);

ALTER TABLE renglon_comprobante
    ADD CONSTRAINT chk_renglon_comprobante_cantidad
        CHECK (cantidad > 0);

ALTER TABLE renglon_comprobante
    ADD CONSTRAINT chk_renglon_comprobante_precio
        CHECK (precio_unitario > 0);

-- Importes no negativos y descuento dentro del rango [0, 1].
ALTER TABLE comprobante
    ADD CONSTRAINT chk_comprobante_importes
        CHECK (subtotal >= 0 AND total >= 0 AND descuento_total >= 0);

ALTER TABLE comprobante
    ADD CONSTRAINT chk_comprobante_descuento_aplicado
        CHECK (descuento_aplicado BETWEEN 0 AND 1);

-- El descuento total nunca supera al subtotal (CHECK entre columnas).
ALTER TABLE comprobante
    ADD CONSTRAINT chk_comprobante_descuento_total
        CHECK (descuento_total <= subtotal);

-- El salario es positivo.
ALTER TABLE empleado
    ADD CONSTRAINT chk_empleado_salario_positivo
        CHECK (salario > 0);

-- La temperatura de servicio es un valor razonable.
ALTER TABLE maridaje
    ADD CONSTRAINT chk_maridaje_temperatura
        CHECK (temperatura_servicio BETWEEN -10 AND 40);

-- El descuento especial del exportador esta en el rango [0, 1] (RN-06).
ALTER TABLE exportador
    ADD CONSTRAINT chk_exportador_descuento
        CHECK (descuento_especial BETWEEN 0 AND 1);

-- ============================================================================
-- 4. Valores por defecto
-- ============================================================================

-- Todo ingreso y toda transferencia nacen en confeccion (RN-10, RN-11).
ALTER TABLE ingreso
    ALTER COLUMN estado SET DEFAULT 'en_confeccion';

ALTER TABLE transferencia
    ALTER COLUMN estado SET DEFAULT 'en_confeccion';

-- La transferencia se confecciona con la fecha actual (RN-11).
ALTER TABLE transferencia
    ALTER COLUMN fecha_confeccion SET DEFAULT CURRENT_DATE;

-- El alta de un cliente se registra con la fecha actual.
ALTER TABLE cliente
    ALTER COLUMN fecha_alta SET DEFAULT CURRENT_DATE;

-- El stock arranca en cero hasta que se registren movimientos.
ALTER TABLE stock_deposito
    ALTER COLUMN cantidad SET DEFAULT 0;

ALTER TABLE stock_sala
    ALTER COLUMN cantidad SET DEFAULT 0;

COMMIT;
