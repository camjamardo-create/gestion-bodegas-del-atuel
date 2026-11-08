-- 002_constraints.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 2.1: UNIQUE, CHECK, DEFAULT y acciones referenciales

BEGIN;

-- 1. Acciones referenciales a los eventos ON UPDATE, ON DELETE en cada FK


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

-- Si se elimina un transportista se borra su 

COMMIT;