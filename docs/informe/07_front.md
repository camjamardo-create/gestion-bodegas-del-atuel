# Etapa 7 · Front web

**Proyecto:** Bodegas del Atuel · TPI Bases de Datos  
**Rama:** `etapa-7-front`  
**Fecha del informe:** 2026-11-10  
**Alcance:** panel web que consume la API de la Etapa 6 y se publica como
contenedor Nginx en la Etapa 8.

---

## 1. Objetivo

Dar una interfaz operativa al sistema: consultar el catálogo, revisar clientes,
registrar ventas, mover stock y ver reportes, sin duplicar reglas de negocio. El
front solo presenta datos y envía operaciones; la base sigue validando todo.

Se eligió una implementación **sin framework ni build step**: HTML, CSS y
JavaScript moderno servidos como archivos estáticos. Esto reduce dependencias,
facilita el despliegue y mantiene la misma imagen para local y nube.

---

## 2. Arquitectura

```text
Navegador
   │ HTTPS
   ▼
Nginx (front)
   ├── /            index.html + assets estáticos
   ├── /config.js   URL de la API generada al arrancar
   ├── /healthz     healthcheck del contenedor
   └── /api/*       proxy same-origin hacia la API FastAPI
                        │
                        ▼
                   API :8000 ──► PostgreSQL
```

Componentes:

| Archivo | Rol |
| --- | --- |
| `front/public/index.html` | Estructura del panel, navegación y regiones accesibles. |
| `front/public/assets/app.js` | Ruteo por hash, llamadas a la API y render de vistas. |
| `front/public/assets/styles.css` | Diseño responsive, estados y componentes. |
| `front/public/config.js` | Valor por defecto de la URL de la API. |
| `front/docker-entrypoint.sh` | Genera `config.js` en tiempo de ejecución desde `API_BASE_URL`. |
| `front/nginx.conf` | Archivos estáticos, proxy `/api/`, headers de seguridad y gzip. |
| `front/Dockerfile` | Imagen `nginx:1.27-alpine`, usuario `nginx`, healthcheck. |

Decisiones principales:

- **Ruteo por hash** (`#/vinos?codigo=1`): no requiere configuración especial de
  servidor y permite enlaces profundos a fichas y comprobantes.
- **Sin build step.** No hay `node_modules` ni bundler; el contenedor solo copia
  archivos y arranca Nginx.
- **Configuración en runtime.** La misma imagen sirve en local (`/api`) y en la
  nube (URL absoluta o `/api` detrás de Caddy). El entrypoint valida que
  `API_BASE_URL` sea `/...` o `http(s)://...`.
- **Proxy same-origin.** En local, Nginx enruta `/api/*` a `api:8000`, así el
  navegador no necesita CORS ni conoce el host interno de la API.
- **Usuario no root.** Nginx corre como `nginx`; los archivos se copian con ese
  propietario.

---

## 3. Vistas

| Ruta | Contenido |
| --- | --- |
| `#/inicio` | Indicadores de catálogo, clientes y ventas; estado de la API y la base; ranking de vinos y accesos rápidos. |
| `#/vinos` | Catálogo paginado con filtros por nombre, tipo y añada; ficha con bodega, cepas, maridajes, precio y stock (depósito, salas y total). |
| `#/clientes` | Listado paginado con filtros; ficha con documento, domicilio, estado, permisos de exportador y accesos para vender o dar de baja. |
| `#/ventas` | Formulario de venta con selección de cliente, sala y renglones; muestra el comprobante con totales, descuento y stock calculados por la base. |
| `#/comprobantes/{numero}` | Detalle de un comprobante con cabecera, cliente, sala, totales y renglones. |
| `#/stock` | Alta de ingreso al depósito y transferencia a sala en cuatro pasos: crear, agregar renglón, terminar y procesar. |
| `#/reportes` | Ranking de vinos, ventas por sala, transportista activo, vinos sin stock por sala y trazabilidad de un vino. |

Comportamientos destacados:

- **Venta sin stock.** La API devuelve `409` con el mensaje de la base; el front
  lo muestra y no inventa un comprobante. El stock queda intacto.
- **Pasos de stock.** Ingresos y transferencias muestran el avance paso a paso;
  si uno falla, se informa cuál y se conserva lo ya registrado.
- **Importes.** Se muestran como texto formateado, respetando la precisión que
  entrega PostgreSQL; no se convierten a `float`.
- **Estados.** Se usan badges para stock, estados de cliente y resultados de
  operaciones, con `aria-live` para anunciar cambios.

---

## 4. Seguridad y accesibilidad

Headers que agrega Nginx:

- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=()`
- `Content-Security-Policy` con `default-src 'self'`, scripts propios y
  `connect-src 'self' http: https:` para permitir la API configurada.
- `server_tokens off`
- `Cache-Control: no-store` para `config.js`, para no fijar una URL vieja de la
  API.

Accesibilidad:

- enlace “Saltar al contenido”;
- navegación con `aria-label`;
- región principal con `tabindex="-1"`;
- mensajes de estado con `aria-live`;
- etiquetas explícitas en todos los formularios;
- foco visible y contraste alto;
- alternativa `noscript`.

El front no guarda credenciales ni tokens: solo conoce la URL pública de la API.

---

## 5. Validación ejecutada

Se probó el panel en un navegador real contra el stack local completo
(PostgreSQL + API + front), con la carga de 150.000 comprobantes.

| Vista / flujo | Resultado |
| --- | --- |
| Inicio | Indicadores y ranking con datos reales; estado “API y base OK · rol_api”. |
| Vinos | Filtros y paginación; ficha del vino 1 con bodega, cepas, maridajes y stock 12.850. |
| Clientes | Listado y ficha del cliente 1 con documento, domicilio, estado y permisos. |
| Ventas | Alta de venta y detalle de comprobante con totales de la base. |
| Stock | Ingreso y transferencia procesados; stock actualizado por la base. |
| Reportes | Ranking, ventas por sala, transportista, vinos sin stock y trazabilidad. |
| Regla de negocio | Venta sin stock → `409`, stock sin cambios, sin comprobante nuevo. |
| Consola del navegador | Sin errores en todas las vistas y fichas. |
| Proxy | `http://localhost:8081/api/salud` responde con `rol_api`. |
| Healthcheck | `http://localhost:8081/healthz` devuelve `ok`. |

> En el entorno local de esta máquina el front quedó publicado en el puerto
> **8081** porque el 8080 estaba ocupado por otro proyecto. El compose permite
> cambiarlo con `FRONT_PORT`; el puerto interno del contenedor sigue siendo
> 8080.

---

## 6. Supuestos y limitaciones

1. **Sin autenticación de usuarios.** El panel asume una red operativa interna;
   el control de acceso a personas no estaba en el alcance de la etapa.
2. **Sin edición masiva.** Las altas y bajas se hacen de a una operación; no hay
   importación de archivos desde el front.
3. **Dependencia de la API.** Si la API o la base no responden, las vistas
   muestran el error traducido y no datos inventados.
4. **Datos sensibles.** El front no muestra claves ni cadenas de conexión; solo
   la URL de la API y los datos de negocio.
5. **Misma imagen en local y nube.** La diferencia es solo `API_BASE_URL` y el
   proxy del borde; no hay builds distintos.

---

## 7. Conclusión

El front cubre las seis secciones operativas y las fichas de vino, cliente y
comprobante. Consume la API sin duplicar reglas, funciona con la misma imagen en
local y nube, y se validó de punta a punta contra la base completa sin errores
de consola.
