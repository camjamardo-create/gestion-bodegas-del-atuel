-- 007_roles.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 2: Integridad y logica en la base de datos
-- Descripcion: roles y privilegios de la etapa 2
--- ===============================================================================

SET client_encoding = 'UTF8';
BEGIN;

--- ===============================================================================

-- 1. CREAR LOS ROLES
-- Los roles se crean sin clave. La clave se fija fuera de la migracion, desde
-- APP_DB_PASSWORD y APP_REPORT_PASSWORD, mediante db/initdb/99_password_api.sql
-- o scripts/aplicar_migraciones. Asi no hay credenciales en el repositorio ni
-- en el historial de Git.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_api') THEN 
        EXECUTE 'CREATE ROLE rol_api LOGIN';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_reporte') THEN
        EXECUTE 'CREATE ROLE rol_reporte LOGIN';
    END IF;
END
$$;

--- ===============================================================================
-- 2. QUITAR LOS PRIVILEGIOS QUE PUBLIC TIENE POR DEFECTO
 REVOKE ALL ON SCHEMA public FROM PUBLIC;
 REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
 REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
 REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
 REVOKE ALL ON ALL PROCEDURES IN SCHEMA public FROM PUBLIC;

 DO $$
 BEGIN
     EXECUTE format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', current_database());
 END
 $$;

 --- ===============================================================================
 -- 3. ACCESO BASICO AL ESQUEMA

 GRANT USAGE ON SCHEMA public TO rol_api, rol_reporte;

 --- ===============================================================================
 -- 4. rol_api: LECTURA Y ESCRITURA (API)
 -- las 29 tablas operativas de 001_esquema.sql

 GRANT SELECT, INSERT, UPDATE, DELETE ON
    bodega, finca, cepa, maridaje, transportista, localidad, sala_venta, empleado,
    transportista_cubre_localidad, ingreso, cliente, cliente_comun, socio_club,
    distribuidor, exportador, permiso, parcela, lote, analisis_calidad, vino,
    composicion, stock_deposito, vino_maridaje, renglon_ingreso, stock_sala,
    comprobante, renglon_comprobante, transferencia, renglon_transferencia
TO rol_api;

-- la auditoria solo se inserta y se lee; no se modifica ni se borra
-- lo hace el trigger 
GRANT SELECT, INSERT ON auditoria_precio TO rol_api;

-- secuencias de las columnas IDENTITY (en 001_esquema.sql)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO rol_api;

-- funciones y procedimientos de la etapa 2
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO rol_api;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO rol_api;

--- ===============================================================================
--5. rol_reporte y rol_api solo lectura de las vistas

GRANT SELECT ON
    vista_stock_total_por_vino,
    vista_ventas_mensuales_por_sala,
    vista_documentos_pendientes
TO rol_reporte;

GRANT SELECT ON
    vista_stock_total_por_vino,
    vista_ventas_mensuales_por_sala,
    vista_documentos_pendientes
TO rol_api;

--- ===============================================================================
--6. PERMISO DE CONEXION PARA LOS DOS ROLES

DO $$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO rol_api, rol_reporte', current_database());
END
$$;

--- ===============================================================================
-- 7. PERMISOS POR DEFECTO PARA OBJETOS FUTUROS


ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO rol_api;

-- global a proposito: el REVOKE por esquema no tiene efecto
ALTER DEFAULT PRIVILEGES
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO rol_api;


COMMIT;