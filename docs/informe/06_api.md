# Etapa 6 · API REST

**Proyecto:** Bodegas del Atuel · TPI Bases de Datos  
**Rama:** `etapa-6-api`  
**Fecha del informe:** 2026-11-10  
**Alcance:** API HTTP sobre PostgreSQL, sin ORM, con las reglas de negocio
resueltas en la base.

---

## 1. Objetivo

Exponer la base construida en las etapas anteriores mediante una API REST que
pueda consumir el front de la Etapa 7 y publicarse en la nube en la Etapa 8.

La API **no duplica reglas de negocio**. Los totales, descuentos, subtotales,
movimientos de stock, estados de documentos y auditoría de precios siguen
resolviéndose con las funciones, procedimientos y triggers de PostgreSQL. La
capa HTTP solo valida el formato de entrada, arma consultas parametrizadas y
traduce los errores de la base a códigos HTTP.

---

## 2. Arquitectura

```text
Front / cliente HTTP
        │ JSON
        ▼
FastAPI (Python 3.12)
   ├── routers/        Endpoints y validación de entrada
   ├── schemas.py      Modelos Pydantic
   ├── repositories/   Todo el SQL parametrizado
   ├── errors.py       Traducción SQLSTATE → HTTP
   └── db.py           Pool de conexiones y transacciones
        │ psycopg 3
        ▼
PostgreSQL 18 (rol_api)
```

Decisiones principales:

- **Sin ORM ni query builder.** El SQL vive en `api/app/repositories/` y usa
  parámetros `%s` de psycopg. Los únicos fragmentos dinámicos son el orden y la
  dirección de `GET /vinos`, elegidos desde una lista blanca.
- **Transacciones explícitas.** `db.transaction()` confirma o revierte el bloque
  completo. Es obligatorio para que los constraint triggers diferidos, como la
  composición de vinos, se evalúen al `COMMIT`.
- **Pool de conexiones.** `psycopg_pool` con mínimo, máximo y timeout
  configurables por entorno.
- **Un solo rol de aplicación.** La configuración rechaza cualquier `DB_USER`
  distinto de `rol_api`; nunca se conecta como `postgres` ni como propietario.

---

## 3. Endpoints

La API expone 23 rutas agrupadas por recurso.

| Método | Ruta | Descripción |
| --- | --- | --- |
| `GET` | `/salud` | Estado de la API y de la conexión; incluye `current_user`. |
| `GET` | `/vinos` | Listado paginado con filtros `tipo`, `cepa`, `bodega`, `anada`, `nombre`, `orden` y `direccion`. |
| `GET` | `/vinos/{codigo}` | Ficha del vino, bodega, cepas, maridajes y stock. |
| `POST` | `/vinos` | Alta de vino y su composición/maridajes. |
| `PUT` | `/vinos/{codigo}` | Actualización parcial; el precio se audita por trigger. |
| `DELETE` | `/vinos/{codigo}` | Baja; la base rechaza si hay stock o ventas asociadas. |
| `GET` | `/clientes` | Listado paginado con filtros `tipo`, `estado_activo` y `documento`. |
| `GET` | `/clientes/{id}` | Detalle de los cuatro subtipos; incluye permisos del exportador. |
| `POST` | `/clientes` | Alta mediante `p_crear_cliente`. |
| `PUT` | `/clientes/{id}` | Actualización; el cambio de tipo usa `p_cambiar_tipo_cliente`. |
| `DELETE` | `/clientes/{id}` | Baja; la base rechaza si tiene comprobantes. |
| `POST` | `/comprobantes` | Venta: cabecera y renglones. Los totales y el stock los calculan los triggers. |
| `GET` | `/comprobantes/{numero}` | Comprobante con totales, descuento, cliente, sala y renglones. |
| `POST` | `/transferencias` | Crea una transferencia en estado `en_confeccion`. |
| `GET` | `/transferencias/{numero}` | Detalle con renglones. |
| `POST` | `/transferencias/{numero}/renglones` | Agrega uno o varios renglones. |
| `POST` | `/transferencias/{numero}/terminar` | Pasa a `terminado`; el trigger valida la transición. |
| `POST` | `/transferencias/{numero}/procesar` | Ejecuta `p_procesar_transferencia` y mueve stock. |
| `POST` | `/ingresos` | Crea un ingreso al depósito. |
| `GET` | `/ingresos/{codigo}` | Detalle con renglones. |
| `POST` | `/ingresos/{codigo}/renglones` | Agrega uno o varios renglones. |
| `POST` | `/ingresos/{codigo}/terminar` | Pasa a `terminado`; el trigger valida la transición. |
| `POST` | `/ingresos/{codigo}/procesar` | Ejecuta `p_procesar_ingreso` y suma stock al depósito. |
| `GET` | `/reportes/top-vinos` | S1: vinos más vendidos. |
| `GET` | `/reportes/ventas-por-sala` | S8: ventas por sala en el último trimestre. |
| `GET` | `/reportes/vinos-sin-stock?sala={id}` | S6: vinos sin stock en una sala pero con stock en depósito. |
| `GET` | `/reportes/transportista-activo` | S7: transportista con más actividad en el último mes. |
| `GET` | `/reportes/trazabilidad/{codigo}` | S9: ficha/trazabilidad del vino con cepas, bodega, maridajes y stock. |

Los importes y porcentajes `NUMERIC` se serializan como string JSON para no
perder precisión (`"precio": "12500.00"`). Los listados devuelven
`items`, `total`, `page`, `page_size` y `pages`.

El contrato completo está en [`docs/api/openapi.json`](../api/openapi.json) y se
puede regenerar con `api/export_openapi.py`.

---

## 4. Delegación de reglas en la base

| Operación | Quién la resuelve | Evidencia |
| --- | --- | --- |
| Totales, subtotales y descuento de una venta | Triggers de `comprobante` y `renglon_comprobante` | `005_triggers.sql` |
| Stock de sala al vender | Trigger de venta | `005_triggers.sql` |
| Ingresos y transferencias | `p_procesar_ingreso` / `p_procesar_transferencia` | `004_procedimientos.sql` |
| Alta y cambio de tipo de cliente | `p_crear_cliente` / `p_cambiar_tipo_cliente` | `004_procedimientos.sql` |
| Validación de composición de vinos | Constraint trigger diferido | `005_triggers.sql` |
| Auditoría de precios | `trg_vino_audita_precio` | `005_triggers.sql` |
| Estados de documentos | Triggers de transición | `005_triggers.sql` |
| Reglas de borrado | FKs `RESTRICT` / cascadas | `002_constraints.sql` |

La API no escribe auditoría, no recalcula precios y no ajusta stock por su
cuenta. Si una regla se viola, PostgreSQL lanza la excepción y la API la
traduce.

---

## 5. Errores y seguridad

`api/app/errors.py` centraliza la traducción de SQLSTATE:

| SQLSTATE | HTTP | Caso |
| --- | --- | --- |
| `P0001` | `409 Conflict` | Regla de negocio lanzada por función, trigger o procedimiento. |
| `23505` | `409 Conflict` | Restricción `UNIQUE`. |
| `23503` | `422` o `409` | Referencia inexistente o fila con dependientes. |
| `23514` | `422 Unprocessable Entity` | Restricción `CHECK`. |
| `23502` | `422 Unprocessable Entity` | Columna `NOT NULL`. |
| `22P02`, `22001`, `22003` | `400 Bad Request` | Formato o longitud inválida. |
| `40001`, `40P01` | `503 Service Unavailable` | Serialización o deadlock; se sugiere reintentar. |
| `08*`, `53300`, `57P03` | `503 Service Unavailable` | Base caída o saturada. |
| `PoolTimeout` | `503 Service Unavailable` | No hay conexiones disponibles. |

Formato uniforme:

```json
{
  "error": {
    "codigo": "P0001",
    "mensaje": "Stock insuficiente del vino 123 en la sala 4: disponible 0, solicitado 1"
  }
}
```

Medidas de seguridad aplicadas:

- consultas parametrizadas en todos los filtros y cuerpos;
- `tipo` de vino tipado como literal cerrado;
- CORS restringido por entorno;
- credenciales solo por variables de entorno, sin claves en el repositorio;
- conexión exclusiva como `rol_api`;
- errores de base traducidos sin exponer el SQL interno.

La prueba de inyección con `nombre=' OR 1=1 --` devuelve `0` resultados y no
altera datos: el valor se busca literalmente.

---

## 6. Validación ejecutada

La validación se hizo contra PostgreSQL real con la carga completa de la Etapa
3 y las credenciales nuevas del `.env` local.

| Prueba | Resultado |
| --- | --- |
| `/salud` | `{"status":"ok","base_de_datos":"ok","current_user":"rol_api"}` |
| Tests de API (`pytest`) | **13 passed** |
| Regla de negocio por el front | Venta sin stock → `409`, stock intacto, sin comprobante nuevo |
| Conteos tras los tests | 150.000 comprobantes, 564.328 renglones, 20.000 clientes |
| `openapi.json` | 23 rutas exportadas |

Cobertura de las 13 pruebas:

- salud y verificación del rol `rol_api`;
- listados, filtros y reportes;
- alta, consulta, modificación y baja de vinos;
- alta de los cuatro subtipos de cliente, permisos de exportador y baja;
- cambio de tipo con versionado y nuevo cliente activo;
- precio negativo rechazado por `CHECK`;
- composición que no suma 100 revertida al `COMMIT`;
- venta sin stock: `409` sin cabecera residual;
- venta exitosa con totales y stock calculados por la base;
- transferencia sin terminar o sin stock: `409`;
- intento de inyección SQL tratado como texto;
- referencia foránea inexistente: `422`.

Para ejecutar las pruebas:

```powershell
Set-Location api
$env:DB_HOST = "localhost"
$env:DB_PORT = "5433"
$env:DB_NAME = "bodegas_del_atuel"
$env:DB_USER = "rol_api"
$env:DB_PASSWORD = "<clave_de_rol_api>"
..\.venv\Scripts\python.exe -m pytest -q
```

---

## 7. Supuestos y limitaciones

1. **Trazabilidad S9.** Se expone como ficha del vino (cepas, bodega, maridajes
   y stock), la entidad disponible en el esquema. No se inventaron tablas de lote
   que el modelo no tiene.
2. **Importes como string.** Es una decisión deliberada para conservar la
   precisión de `NUMERIC`; el front los formatea sin convertirlos a `float`.
3. **Sin autenticación de usuarios.** El alcance de la Etapa 6 es la API sobre
   `rol_api`; la autenticación de personas no estaba en el enunciado y queda
   como trabajo futuro.
4. **Sin claves literales.** Las claves de `rol_api` y `rol_reporte` se fijan
   por entorno. La observación histórica sobre una clave fija en
   `007_roles.sql` ya no aplica.
5. **La API no modifica migraciones ni seed.** Todos los cambios de la etapa
   están en `api/` y en la configuración de despliegue.

---

## 8. Conclusión

La API cubre las operaciones de vinos, clientes, ventas, ingresos,
transferencias y reportes sin duplicar reglas de negocio. La base sigue siendo
la única fuente de verdad, los errores se traducen de forma uniforme y las 13
pruebas de integración pasan contra la carga completa.
