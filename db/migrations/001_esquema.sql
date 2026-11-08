-- 001_esquema.sql
-- TPI Base de Datos - Bodegas del Atuel
-- Etapa 1: tipos, dominios, tablas, PK y FK

BEGIN; 

-- 1. Dominios y tipos propios

CREATE DOMAIN cuit_dominio AS CHAR(11)
    CHECK (VALUE ~'^[0-9]{11}$');

CREATE DOMAIN cp_dominio AS VARCHAR(8)
    CHECK (VALUE ~ '^[0-9]{4}$' OR VALUE ~'^[A-Z][0-9]{4}[A-Z]{3}$');


CREATE TYPE tipo_vino AS ENUM ('tinto', 'blanco', 'rosado','espumante');

CREATE TYPE tipo_cliente AS ENUM ('cliente_comun','socio_club', 'distribuidor', 'exportador');

CREATE TYPE tipo_cepa AS ENUM ('tinta', 'blanca');

CREATE TYPE tipo_empleado AS ENUM ('empleado_sala', 'encargado_regional');

CREATE TYPE tipo_estado AS ENUM ('en_confeccion', 'terminado', 'procesado');

CREATE TYPE dia_semana AS ENUM ('lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo');

-- 2. Tablas sin dependencias

CREATE TABLE bodega (
    cuit cuit_dominio PRIMARY KEY,
    razon_social VARCHAR(120) NOT NULL,
    calle VARCHAR(60) NOT NULL,
    numero VARCHAR(10) NOT NULL
);

CREATE TABLE finca (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_finca VARCHAR(80) NOT NULL,
    superficie NUMERIC(10,2) NOT NULL,
    provincia VARCHAR(80) NOT NULL,
    nombre_departamento VARCHAR(80) NOT NULL
);

CREATE TABLE cepa (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    tipo tipo_cepa NOT NULL
);

CREATE TABLE maridaje (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    temperatura_servicio SMALLINT NOT NULL
);

CREATE TABLE transportista (
    codigo INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    razon_social VARCHAR(120) NOT NULL,
    cuit cuit_dominio NOT NULL,
    email VARCHAR(100) NOT NULL,
    telefono VARCHAR(20) NOT NULL,
    calle VARCHAR(60) NOT NULL,
    numero VARCHAR(10) NOT NULL
);


-- 3. Tablas que dependen de otras

-- tabla localidad sin la FK al encargado para evitar fallo 
-- en el flujo de creacion de tablas
CREATE TABLE localidad (                   
    codigo_postal cp_dominio PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    provincia VARCHAR (50) NOT NULL,
    tipo_encargado tipo_empleado NOT NULL DEFAULT 'encargado_regional' 
    CHECK (tipo_encargado = 'encargado_regional'),  -- agregamos el check en esta etapa porque no es una regla de negocio, sino que define el mecanismo de la FK
    cuit_encargado cuit_dominio NOT NULL
);

CREATE TABLE sala_venta (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    calle VARCHAR(60) NOT NULL,
    numero VARCHAR(10) NOT NULL,
    dia_cierre dia_semana NOT NULL, 
    codigo_postal cp_dominio NOT NULL,

    CONSTRAINT fk_sala_venta_localidad
        FOREIGN KEY (codigo_postal) REFERENCES localidad (codigo_postal)
);

CREATE TABLE empleado (
    cuit cuit_dominio PRIMARY KEY,
    tipo tipo_empleado NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    salario NUMERIC(12,2) NOT NULL,
    fecha_ingreso DATE NOT NULL,
    id_sala INT NOT NULL,

    CONSTRAINT fk_empleado_sala_venta
        FOREIGN KEY (id_sala) REFERENCES sala_venta (id),
    
    CONSTRAINT uk_empleado_cuit_tipo
        UNIQUE (cuit, tipo) -- UK requerida como destino de la FK (cuit_encargado, tipo_encargado) de localidad
                            -- (no es una regla de negocio)
);

-- agregamos la fk a encargado en la tabla localidad para terminarla
ALTER TABLE localidad 
    ADD CONSTRAINT fk_localidad_encargado
        FOREIGN KEY (cuit_encargado, tipo_encargado) REFERENCES empleado (cuit, tipo)
        DEFERRABLE INITIALLY DEFERRED;


CREATE TABLE transportista_cubre_localidad(
    codigo_transportista INT NOT NULL,
    codigo_postal_localidad cp_dominio NOT NULL,

    PRIMARY KEY (codigo_transportista, codigo_postal_localidad),

    CONSTRAINT fk_transportista_cubre_localidad_transportista
        FOREIGN KEY (codigo_transportista) REFERENCES transportista (codigo),

    CONSTRAINT fk_transportista_cubre_localidad_localidad
        FOREIGN KEY (codigo_postal_localidad) REFERENCES localidad (codigo_postal)
);

CREATE TABLE ingreso (
    codigo INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha DATE NOT NULL,
    estado tipo_estado NOT NULL,
    codigo_transportista INT NOT NULL,
    cuit_bodega cuit_dominio NOT NULL,

    CONSTRAINT fk_ingreso_transportista
        FOREIGN KEY (codigo_transportista) REFERENCES transportista (codigo),

    CONSTRAINT fk_ingreso_bodega
        FOREIGN KEY (cuit_bodega) REFERENCES bodega (cuit)
);

CREATE TABLE cliente (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo tipo_cliente NOT NULL,
    nombre VARCHAR(60),
    apellido VARCHAR(60),
    razon_social VARCHAR(120),
    calle VARCHAR(60) NOT NULL,
    numero VARCHAR(10) NOT NULL,
    codigo_postal cp_dominio NOT NULL,
    tipo_documento VARCHAR(10) NOT NULL,
    numero_documento VARCHAR(20) NOT NULL,
    fecha_alta DATE NOT NULL,

    CONSTRAINT uk_cliente_id_tipo
        UNIQUE (id, tipo),
    
    CONSTRAINT fk_cliente_localidad
        FOREIGN KEY (codigo_postal) REFERENCES localidad (codigo_postal)  
);

CREATE TABLE cliente_comun (
    id_cliente INT PRIMARY KEY,
    tipo tipo_cliente NOT NULL,

    CONSTRAINT fk_cliente_comun_cliente
        FOREIGN KEY (id_cliente, tipo) REFERENCES cliente (id,tipo)
);

CREATE TABLE socio_club (
    id_cliente INT PRIMARY KEY,
    tipo tipo_cliente NOT NULL,

    CONSTRAINT fk_socio_club_cliente
        FOREIGN KEY (id_cliente, tipo) REFERENCES cliente (id,tipo)
);

CREATE TABLE distribuidor (
    id_cliente INT PRIMARY KEY,
    tipo tipo_cliente NOT NULL,
    zona_cobertura VARCHAR(100) NOT NULL,
    numero_habilitacion VARCHAR(20) NOT NULL,

    CONSTRAINT fk_distribuidor_cliente
        FOREIGN KEY (id_cliente, tipo) REFERENCES cliente (id,tipo)
);

CREATE TABLE exportador (
    id_cliente INT PRIMARY KEY,
    tipo tipo_cliente NOT NULL,
    pais_destino VARCHAR(50) NOT NULL,
    descuento_especial NUMERIC(3,2),

    CONSTRAINT fk_exportador_cliente
        FOREIGN KEY (id_cliente, tipo) REFERENCES cliente (id,tipo)
);

CREATE TABLE permiso (
    codigo INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_exportador INT NOT NULL,
    fecha_emision DATE NOT NULL,
    fecha_vencimiento DATE NOT NULL,

    CONSTRAINT fk_permiso_exportador
        FOREIGN KEY (id_exportador) REFERENCES exportador (id_cliente)
);

CREATE TABLE parcela (
    numero_parcela INT NOT NULL,
    id_finca INT NOT NULL, 
    superficie NUMERIC(10,2) NOT NULL,
    año_plantacion SMALLINT NOT NULL,
    id_cepa INT NOT NULL,

    PRIMARY KEY (id_finca, numero_parcela),

    CONSTRAINT fk_parcela_finca
        FOREIGN KEY (id_finca) REFERENCES finca (id),

    CONSTRAINT fk_parcela_cepa
        FOREIGN KEY (id_cepa) REFERENCES cepa (id)
);

CREATE TABLE lote (
    numero_lote INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha DATE NOT NULL,
    campaña SMALLINT GENERATED ALWAYS AS (EXTRACT(YEAR FROM fecha)::SMALLINT) STORED NOT NULL,  -- atributo derivado de fecha y almacenado 
    kg_cosecha NUMERIC(10,2) NOT NULL,
    cuit_bodega cuit_dominio NOT NULL,
    id_finca INT NOT NULL,
    numero_parcela INT NOT NULL,

    CONSTRAINT fk_lote_bodega
        FOREIGN KEY (cuit_bodega) REFERENCES bodega (cuit),
    
    CONSTRAINT fk_lote_parcela
        FOREIGN KEY (id_finca, numero_parcela) REFERENCES parcela (id_finca, numero_parcela)
);

CREATE TABLE analisis_calidad (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha DATE NOT NULL,
    ph NUMERIC(4,2) NOT NULL,
    brix NUMERIC(4,1) NOT NULL,
    acidez NUMERIC(5,2) NOT NULL,
    numero_lote INT NOT NULL,

    CONSTRAINT fk_analisis_calidad_lote
        FOREIGN KEY (numero_lote) REFERENCES lote (numero_lote)
);

CREATE TABLE vino (
    codigo INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    tipo tipo_vino NOT NULL,
    añada SMALLINT NOT NULL,
    volumen_ml INT NOT NULL,
    graduacion NUMERIC(4,2) NOT NULL,
    precio NUMERIC(10,2) NOT NULL,
    cuit_bodega cuit_dominio NOT NULL,

    CONSTRAINT fk_vino_bodega
        FOREIGN KEY (cuit_bodega) REFERENCES bodega (cuit)
);

CREATE TABLE composicion (
    codigo_vino INT NOT NULL,
    id_cepa INT NOT NULL,
    porcentaje NUMERIC(5,2) NOT NULL,

    PRIMARY KEY (codigo_vino, id_cepa),
    
    CONSTRAINT fk_composicion_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo),
    
    CONSTRAINT fk_composicion_cepa
        FOREIGN KEY (id_cepa) REFERENCES cepa (id)
);

CREATE TABLE stock_deposito (
    codigo_vino INT NOT NULL,
    cantidad INT NOT NULL,

    PRIMARY KEY (codigo_vino),

    CONSTRAINT fk_stock_deposito_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
);

CREATE TABLE vino_maridaje (
    codigo_vino INT NOT NULL,
    id_maridaje INT NOT NULL,

    PRIMARY KEY (codigo_vino, id_maridaje),

    CONSTRAINT fk_vino_maridaje_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo),

    CONSTRAINT fk_vino_maridaje_maridaje
        FOREIGN KEY (id_maridaje) REFERENCES maridaje (id)
);

CREATE TABLE renglon_ingreso (
    codigo_ingreso INT NOT NULL,
    codigo_vino INT NOT NULL,
    cantidad INT NOT NULL,

    PRIMARY KEY (codigo_ingreso, codigo_vino),

    CONSTRAINT fk_renglon_ingreso_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo),

    CONSTRAINT fk_renglon_ingreso_ingreso
        FOREIGN KEY (codigo_ingreso) REFERENCES ingreso (codigo)
);

CREATE TABLE auditoria_precio (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario VARCHAR(60) NOT NULL,
    fecha_hora TIMESTAMP NOT NULL,
    precio_nuevo NUMERIC(10,2) NOT NULL,
    precio_anterior NUMERIC(10,2) NOT NULL,
    codigo_vino INT NOT NULL,

    CONSTRAINT fk_auditoria_precio_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
);

CREATE TABLE stock_sala (
    id_sala INT NOT NULL,
    codigo_vino INT NOT NULL,
    cantidad INT NOT NULL,

    PRIMARY KEY (id_sala, codigo_vino),

    CONSTRAINT fk_stock_sala_sala
        FOREIGN KEY (id_sala) REFERENCES sala_venta (id),

    CONSTRAINT fk_stock_sala_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
);

CREATE TABLE comprobante (
    numero INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha DATE NOT NULL,
    subtotal NUMERIC(14,2) NOT NULL,
    total NUMERIC(14,2) NOT NULL,
    descuento_aplicado NUMERIC(3,2) NOT NULL,
    descuento_total NUMERIC(14,2) NOT NULL,
    id_cliente INT NOT NULL,
    id_sala_venta INT NOT NULL,

    CONSTRAINT fk_comprobante_cliente
        FOREIGN KEY (id_cliente) REFERENCES cliente (id),
    
    CONSTRAINT fk_comprobante_sala
        FOREIGN KEY (id_sala_venta) REFERENCES sala_venta (id)
);

CREATE TABLE renglon_comprobante (
    numero_comprobante INT NOT NULL,
    codigo_vino INT NOT NULL,
    cantidad INT NOT NULL,
    precio_unitario NUMERIC(10,2) NOT NULL,
    subtotal_renglon NUMERIC(14,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED NOT NULL,
    -- atributo generado derivado y almacenado

    PRIMARY KEY (numero_comprobante, codigo_vino), 

    CONSTRAINT fk_renglon_comprobante_comprobante
        FOREIGN KEY (numero_comprobante) REFERENCES comprobante (numero),
    
    CONSTRAINT fk_renglon_comprobante_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
);

CREATE TABLE transferencia (
    numero INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_confeccion DATE NOT NULL,
    estado tipo_estado NOT NULL,
    id_sala_venta INT NOT NULL,

    CONSTRAINT fk_transferencia_sala_venta
        FOREIGN KEY (id_sala_venta) REFERENCES sala_venta (id)
);

CREATE TABLE renglon_transferencia (
    numero_transferencia INT NOT NULL,
    codigo_vino INT NOT NULL,
    cantidad INT NOT NULL,

    PRIMARY KEY (numero_transferencia, codigo_vino),

    CONSTRAINT fk_renglon_transferencia_transferencia
        FOREIGN KEY (numero_transferencia) REFERENCES transferencia (numero),

    CONSTRAINT fk_renglon_transferencia_vino
        FOREIGN KEY (codigo_vino) REFERENCES vino (codigo)
);

COMMIT;
