# Guion de la presentación — Etapa 9

**Bodegas del Atuel · TPI Bases de Datos**  
Duración objetivo: 10 a 15 minutos.  
Formato: teoría → código real → evidencia.

---

## Slide 1 — Portada

**La base de datos como motor de reglas**

Bodegas del Atuel · TPI Bases de Datos  
Etapa 9 · Documentación y defensa  
Jamardo, Camila (10842) · Sirotiuk, Juliana (10939)

**Notas:** Buenas. Vamos a mostrar cómo modelamos la bodega y cómo PostgreSQL
hace cumplir las reglas. Cada concepto va acompañado de un fragmento real del
repositorio y de la prueba que lo respalda.

---

## Slide 2 — La idea en una frase

> La API no calcula nada: pide operaciones.  
> PostgreSQL valida, calcula y audita.

Recorrido:

1. Modelo y normalización.
2. Integridad y reglas.
3. Operación y seguridad.
4. Rendimiento y demo.

**Notas:** La presentación sigue el recorrido del dato: primero el modelo,
después las reglas que lo protegen, luego las operaciones y el rendimiento.
Cerramos con una demo de cuatro evidencias.

---

## Slide 3 — Arquitectura: tres capas, una sola fuente de verdad

Navegador → Front Nginx → API FastAPI → PostgreSQL.

- El front presenta y envía operaciones.
- La API valida formato, arma SQL parametrizado y traduce errores.
- PostgreSQL ejecuta las reglas de negocio.

**Notas:** La regla no está duplicada en el front ni en la API. La API no usa
ORM: todo el SQL vive en `api/app/repositories/`. Si una regla se viola, la base
lanza la excepción y la API la convierte en un HTTP claro.

---

## Slide 4 — Del DER al MER

- Entidades principales: cliente, vino, comprobante, stock, ingreso,
  transferencia.
- Relaciones 1:N con FK.
- Relaciones N:M resueltas con tablas puente: `composicion`,
  `vino_maridaje`.
- Jerarquía de clientes: tabla común + subtipos.

**Notas:** El DER es el modelo conceptual; el MER es la traducción a tablas,
claves y relaciones. Las N:M no se guardan como listas: se resuelven con tablas
puente. La jerarquía de clientes evita repetir datos comunes en cada subtipo.

---

## Slide 5 — Normalización aplicada

- **1FN:** atributos atómicos; la dirección se separa en calle y número.
- **2FN:** en `composicion`, `porcentaje` depende de la clave completa
  `(codigo_vino, id_cepa)`.
- **3FN:** `cliente` guarda lo común; `socio_club`, `distribuidor` y
  `exportador` agregan solo lo propio.

Código: `001_esquema.sql` (`cliente`, `socio_club`, `composicion`).

**Notas:** La normalización no es un ejercicio teórico: evita duplicar datos y
anomalías de actualización. En `composicion`, el porcentaje no depende solo del
vino ni solo de la cepa, sino de la combinación. En clientes, el subtipo no
repite nombre, documento ni domicilio.

---

## Slide 6 — Integridad declarativa

```sql
ALTER TABLE vino
  ADD CONSTRAINT ck_vino_precio_positivo
      CHECK (precio > 0),
  ADD CONSTRAINT uk_vino_nombre_añada_volumen
      UNIQUE (nombre, añada, volumen_ml);

ALTER TABLE stock_sala
  ADD CONSTRAINT ck_stock_sala_cantidad_no_negativa
      CHECK (cantidad >= 0);
```

Evidencia: RN-01, RN-09 y RN-15.

**Notas:** Los constraints son la última línea de defensa. Aunque la API o el
front validen, la base rechaza precio negativo, vinos duplicados y stock
negativo. Cualquier cliente que se conecte, incluso `psql`, cumple las mismas
reglas.

---

## Slide 7 — Triggers: la venta se calcula sola

```sql
CREATE TRIGGER trg_renglon_comprobante_actualiza_venta
AFTER INSERT ON renglon_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_actualizar_stock_y_totales_venta();

-- dentro de la función
UPDATE stock_sala
   SET cantidad = cantidad - NEW.cantidad
 WHERE id_sala = v_id_sala
   AND codigo_vino = NEW.codigo_vino;

UPDATE comprobante
   SET subtotal = v_subtotal,
       descuento_total = v_descuento_total,
       total = v_total
 WHERE numero = NEW.numero_comprobante;
```

Evidencia: RN-08 y RN-09.

**Notas:** La API inserta la cabecera y el renglón, pero no manda totales. El
trigger descuenta stock y recalcula subtotal, descuento y total en la misma
transacción. Si el stock no alcanza, lanza una excepción y se revierte todo: no
queda un comprobante a medias.

---

## Slide 8 — Procedimientos: una sola puerta de entrada

```sql
CREATE PROCEDURE p_procesar_ingreso(p_codigo INT)
...
SELECT estado FROM ingreso
 WHERE codigo = p_codigo
 FOR UPDATE;

IF v_estado <> 'terminado' THEN
  RAISE EXCEPTION 'El ingreso % no esta terminado';
END IF;

INSERT INTO stock_deposito (codigo_vino, cantidad)
SELECT codigo_vino, cantidad
  FROM renglon_ingreso
 WHERE codigo_ingreso = p_codigo
ON CONFLICT (codigo_vino) DO UPDATE
  SET cantidad = stock_deposito.cantidad
               + EXCLUDED.cantidad;
```

Evidencia: RN-10 y RN-11.

**Notas:** El procedimiento bloquea la cabecera con `FOR UPDATE`, valida el
estado, verifica que haya renglones y actualiza el depósito. La API solo hace
`CALL`. Así dos sesiones no procesan el mismo ingreso y el stock no se suma dos
veces.

---

## Slide 9 — Vistas: una definición, muchos consumidores

```sql
CREATE VIEW vista_stock_total_por_vino AS
SELECT v.codigo, v.nombre,
       COALESCE(d.cantidad, 0) AS stock_deposito,
       COALESCE(s.cantidad, 0) AS stock_sala,
       COALESCE(d.cantidad, 0)
       + COALESCE(s.cantidad, 0) AS stock_total
FROM vino v
LEFT JOIN stock_deposito d
       ON d.codigo_vino = v.codigo
LEFT JOIN (
    SELECT codigo_vino, SUM(cantidad) AS cantidad
    FROM stock_sala
    GROUP BY codigo_vino
) s ON s.codigo_vino = v.codigo;
```

**Notas:** La vista encapsula el join y la suma de stock. El consumidor pide
`stock_total` y no repite la lógica. El `LEFT JOIN` es importante: un vino sin
stock en depósito o en salas sigue apareciendo con cero. La usan la ficha del
vino y los reportes.

---

## Slide 10 — Roles: privilegio mínimo

```sql
CREATE ROLE rol_api LOGIN;
CREATE ROLE rol_reporte LOGIN;

GRANT SELECT, INSERT, UPDATE, DELETE
   ON <tablas operativas> TO rol_api;
GRANT SELECT, INSERT
   ON auditoria_precio TO rol_api;
GRANT EXECUTE ON ALL PROCEDURES
   IN SCHEMA public TO rol_api;
GRANT SELECT
   ON vista_stock_total_por_vino, ... TO rol_reporte;
```

**Notas:** La API se conecta como `rol_api`, nunca como propietario ni
superusuario. `rol_reporte` solo lee vistas. Las claves se fijan por entorno en
`db/initdb/99_password_api.sql`: no hay credenciales literales en el repositorio.

---

## Slide 11 — Índices: menos buffers, no más código

| Consulta | Antes | Después | Mejora |
|---|---:|---:|---:|
| S3 | 9,753 ms | 0,977 ms | 10,0× |
| S8 | 15,490 ms | 9,174 ms | 1,69× |
| S9 | 77 buffers | 3 buffers | 25,7× |

```sql
CREATE INDEX idx_comprobante_sala_fecha
  ON comprobante (id_sala_venta, fecha)
  INCLUDE (id_cliente);

CREATE INDEX idx_comprobante_fecha_sala_total
  ON comprobante (fecha, id_sala_venta)
  INCLUDE (total);
```

**Notas:** El orden de columnas importa: primero la igualdad o el rango, después
el resto. `INCLUDE` permite un `Index Only Scan` sin visitar el heap. No todos
los índices ayudan: S1, S11 y S12 siguen con `Seq Scan` porque leen casi toda la
tabla. Eso también se documentó.

---

## Slide 12 — Demo en vivo

1. Venta exitosa: totales y stock calculados por la base.
2. Venta sin stock: HTTP `409`, stock intacto, sin comprobante.
3. Transferencia: crear, terminar y procesar.
4. `EXPLAIN ANALYZE`: `Index Only Scan` con pocos buffers.

**Notas:** La demo sigue el mismo orden que la presentación. Si la red o la nube
fallan, usar las capturas de respaldo. Mostrar siempre el antes y el después del
stock, y el plan de ejecución.

---

## Slide 13 — Cierre

- Modelo normalizado y trazable.
- Reglas ejecutadas por la base, no por la aplicación.
- Rendimiento medido, no supuesto.

**¿Preguntas?**

**Notas:** Cierre: el TPI demuestra que la base no es un depósito de datos, es
el motor de reglas del sistema. Quedamos para preguntas sobre cualquier parte
del trabajo.
