# Etapa 8 · Despliegue en la nube

**Proyecto:** Bodegas del Atuel · TPI Bases de Datos  
**Rama:** `etapa-8-nube`  
**Base:** `origin/main` en `49c5570`  
**Fecha del informe:** 2026-11-10  
**Alcance:** despliegue de la API y el front, base PostgreSQL, TLS, backups y
pruebas de aceptación.

---

## 1. Objetivo

Dejar preparada una arquitectura reproducible para publicar el sistema en la
nube sin exponer PostgreSQL ni la API, usando una conexión cifrada a la base,
roles de privilegios mínimos y evidencia de backup/restauración.

La entrega incluye:

- scripts de migración, carga, control, backup, restauración y pruebas;
- Dockerfiles de producción para API y front;
- un compose de referencia con Caddy, front, API y PostgreSQL;
- plantillas de variables sin secretos;
- comparación de proveedores con fuentes oficiales;
- checklist manual para completar el despliegue real.

No se usaron cuentas, CLIs ni credenciales de proveedores cloud. Por eso el
despliegue efectivo queda como paso manual y no se declara como ejecutado.

---

## 2. Arquitectura de referencia

```text
Internet
   │ HTTPS 443
   ▼
Caddy  ──────────────►  Front Nginx :8080
   │                         │
   │ /api/*                  │ /api (mismo origen)
   ▼                         ▼
API FastAPI :8000  ◄──────  proxy interno
   │
   │ TLS 5432 (red interna)
   ▼
PostgreSQL 18
   └── volumen persistente + backups fuera del repositorio
```

Reglas de la arquitectura:

- Solo Caddy publica `80`/`443`.
- PostgreSQL y la API no publican puertos al host.
- La base se alcanza por la red interna del compose o por la red
  privada/allowlist del proveedor.
- La API se conecta como `rol_api`, nunca como propietario ni superusuario.
- Las migraciones y la carga se ejecutan con el rol propietario.
- El front usa `API_BASE_URL=/api` en el compose de referencia y puede usar una
  URL absoluta si se separa en otro dominio.
- La misma imagen del front sirve para local y nube; la URL de la API se
  resuelve en tiempo de ejecución.

Archivos principales:

| Archivo | Función |
|---|---|
| `docker-compose.production.yml` | Compose de referencia con Caddy, API, front y PostgreSQL TLS. |
| `deploy/Caddyfile` | HTTPS automático, proxy `/api` y headers. |
| `deploy/postgres/` | Imagen de PostgreSQL con TLS y `pg_hba.conf` que exige cifrado. |
| `front/Dockerfile` | Nginx no root, healthcheck y `API_BASE_URL` runtime. |
| `api/Dockerfile` | FastAPI no root, solo dependencias de ejecución. |
| `.env.production.example` | Placeholders de todas las variables. |
| `scripts/` | Migraciones, carga, controles, backup, restauración y pruebas. |

---

## 3. Comparación de proveedores

Se compararon tres alternativas con documentación oficial consultada el
**2026-11-10**. El criterio principal fue la posibilidad de restringir el
acceso a PostgreSQL.

| Proveedor | Restricción de acceso a la base | TLS | Observación para este TPI | Fuente oficial |
|---|---|---|---|---|
| **Supabase** | Network Restrictions con rangos CIDR para Postgres y pooler; las conexiones no incluidas se rechazan antes de llegar a la base. | SSL enforcement configurable; recomienda `verify-full` con su CA. | Muy buen encaje si se prioriza una allowlist explícita. Hay que descargar la CA para `verify-full` y separar el pooler del acceso directo. | [Network Restrictions](https://supabase.com/docs/guides/platform/network-restrictions) · [SSL Enforcement](https://supabase.com/docs/guides/platform/ssl-enforcement) |
| **Render** | URL interna para servicios de la misma región/red privada; allowlist de IP o deshabilitación del acceso externo por CIDR. | TLS en conexiones externas; en la interna permite `sslmode=require` con certificado autofirmado. | Es la opción más directa para API + base en la misma plataforma: se usa la URL interna y se desactiva el acceso externo. | [Postgres: conexión y acceso](https://render.com/docs/postgresql-creating-connecting) · [Private Services](https://render.com/docs/private-services) |
| **Railway** | La base se despliega privada por defecto; el acceso externo se habilita opcionalmente con Public Access/TCP Proxy. Red privada entre servicios del proyecto. | Imagen PostgreSQL SSL-enabled; la conexión interna usa la red privada. | Cómodo para una demo, pero hay que verificar el costo de egress si se publica la base y configurar backups. | [PostgreSQL en Railway](https://docs.railway.com/guides/postgresql) · [Private Networking](https://docs.railway.com/reference/private-networking) |

### 3.1. Lectura de la comparación

- **Prioridad del TPI:** que PostgreSQL no quede expuesto a Internet. Render y
  Supabase permiten cumplirlo de forma explícita; Railway lo cumple por defecto
  mientras no se habilite Public Access.
- **Si se elige Render:** crear la base y la API en la misma región, usar la
  URL interna, deshabilitar el acceso externo y ejecutar las migraciones desde
  una máquina autorizada por la allowlist.
- **Si se elige Supabase:** crear la allowlist con la IP de salida de la API y
  la de operaciones, activar SSL enforcement y evaluar `verify-full` con la CA
  del proyecto.
- **Si se elige Railway:** no habilitar Public Access salvo para la ventana de
  migración, usar `*.railway.internal` y mantener backups.
- **Neon** también es una alternativa válida por su TLS obligatorio y sus
  niveles `require`, `verify-ca` y `verify-full` ([documentación de conexión
  segura](https://neon.com/docs/connect/connect-securely)); no se incluyó en la
  tabla principal porque en esta revisión no se relevó su mecanismo de
  allowlist con el mismo nivel de detalle.

No se eligió un proveedor definitivo porque la consigna no autoriza usar
cuentas ni credenciales reales en esta entrega.

---

## 4. Implementación

### 4.1. Base de datos y migraciones

- `db/migrations/001_esquema.sql` a `008_indices.sql` se aplican en orden con
  `ON_ERROR_STOP=1`.
- `db/initdb/01_migraciones.sql` aplica las ocho migraciones en un volumen
  nuevo.
- `db/initdb/99_password_api.sql` fija las claves de `rol_api` y
  `rol_reporte` desde `APP_DB_PASSWORD` y `APP_REPORT_PASSWORD`.
- `007_roles.sql` crea los roles sin clave literal y usa
  `current_database()` para los `GRANT`/`REVOKE` de conexión.
- La API valida en `config.py` que el usuario sea exactamente `rol_api` y
  rechaza propietarios/superusuarios.

### 4.2. API

Variables principales:

| Variable | Uso |
|---|---|
| `DB_HOST`, `DB_PORT`, `DB_NAME` | Destino de la base. |
| `DB_USER` | Debe ser `rol_api`. |
| `DB_PASSWORD` | Clave del rol de la API. |
| `DB_SSLMODE` | `require` en nube; `disable` solo en local. |
| `CORS_ORIGINS` | Origen HTTPS del front, separado por comas. |
| `DB_POOL_MIN_SIZE`, `DB_POOL_MAX_SIZE`, `DB_POOL_TIMEOUT` | Pool y timeouts. |

`/salud` ejecuta una consulta real y devuelve `current_user`; no es un
healthcheck vacío.

### 4.3. Front

- Nginx no root en el puerto `8080`.
- `config.js` se genera al arrancar desde `API_BASE_URL`.
- La misma imagen se usa en local y en la nube.
- El proxy `/api` permite el modo mismo origen; también se admite una URL
  absoluta.
- `/healthz` responde `ok`.
- Headers: CSP, `X-Content-Type-Options`, `X-Frame-Options`,
  `Referrer-Policy`, `Permissions-Policy`.

### 4.4. Seguridad de red

- Compose de producción: PostgreSQL escucha solo en la red interna.
- `deploy/postgres/pg_hba.conf` acepta `hostssl` con `scram-sha-256` y rechaza
  `hostnossl`.
- Caddy obtiene HTTPS para el dominio y elimina el header `Server`.
- Las imágenes de API y front no corren como root.
- La API no tiene dependencias de desarrollo en la imagen.

### 4.5. Scripts

| Script | Uso |
|---|---|
| `scripts/aplicar_migraciones.ps1` / `.sh` | Aplica `001`–`008` y fija claves de roles. |
| `scripts/cargar_datos.ps1` / `.sh` | Carga full o reducida. |
| `scripts/consultas_control.ps1` / `.sh` | Ejecuta controles de la Etapa 3. |
| `scripts/backup.ps1` / `.sh` | Genera `.dump` (`-Fc`) y `.sql.gz`. |
| `scripts/restaurar_y_verificar.ps1` / `.sh` | Restaura en base temporal y compara conteos. |
| `scripts/probar_regla_en_nube.ps1` / `.sh` | Intenta vender más que el stock y espera 409. |
| `scripts/probar_acceso_no_autorizado.ps1` / `.sh` | Prueba SSL y acceso desde red no autorizada. |

Los scripts no imprimen claves. Toman las credenciales desde variables de
entorno o desde `ENV_FILE`, y pueden usar `psql` local o
`docker run postgres:18`.

---

## 5. Validación ejecutada

Todas las pruebas se hicieron en local contra PostgreSQL 18 en Docker. No se
usaron datos ni credenciales de producción.

### 5.1. Migraciones e inicialización

| Prueba | Resultado |
|---|---|
| `aplicar_migraciones.ps1` sobre base vacía | `001`–`008` aplicadas; `rol_api` pudo consultar. |
| `aplicar_migraciones.sh` sobre base vacía | `001`–`008` aplicadas; `rol_api` pudo consultar. |
| Inicialización con `db/initdb/01_migraciones.sql` | 30 tablas y 41 índices; `rol_api` con acceso. |
| Claves de roles | `rol_api` y `rol_reporte` con `rolpassword` no nulo. |

### 5.2. Carga y controles

| Prueba | Resultado |
|---|---|
| Carga reducida (`-Modo reducida -Escala 0.05`) | Completada sin errores. |
| Carga full | 30 tablas, 796.681 filas en total. |
| Controles de la Etapa 3 (PowerShell y Bash) | 0 filas en todas las consultas problemáticas. |

### 5.3. Backup y restauración

| Prueba | Resultado |
|---|---|
| `pg_dump -Fc` | `.dump` de 6.408.033 bytes. |
| `pg_dump --format=plain \| gzip -9` | `.sql.gz` de 6.265.169 bytes. |
| Restauración de `.dump` | 30 tablas y 796.681 filas coinciden. |
| Restauración de `.sql.gz` | 30 tablas y 796.681 filas coinciden. |
| Restauración con scripts Bash | 30 tablas y 796.681 filas coinciden. |

Las restauraciones se hicieron en bases temporales
`bodegas_del_atuel_restore_*`, que se eliminaron al finalizar.

### 5.4. API y regla de negocio

| Prueba | Resultado |
|---|---|
| `GET /salud` | `{"status":"ok","base_de_datos":"ok","current_user":"rol_api"}` |
| `GET /api/salud` a través del front | Mismo resultado. |
| `pytest api/tests` | 13 pruebas aprobadas. |
| `probar_regla_en_nube` | HTTP 409, stock antes/después igual, sin comprobante nuevo. |

### 5.5. Front

Se probó en navegador con la API y la base locales:

- Inicio con indicadores y ranking.
- Catálogo de vinos con filtros y paginación.
- Ficha de vino con composición, maridajes y stock.
- Clientes con filtros y ficha.
- Formulario de venta con búsqueda de cliente.
- Stock: ingreso y transferencia.
- Reportes: ranking, ventas por sala y alertas.

No se observaron errores de consola ni recursos bloqueados.

### 5.6. Contenedores y compose

| Prueba | Resultado |
|---|---|
| `docker compose config --quiet` | Válido. |
| `docker compose --env-file .env.production.example -f docker-compose.production.yml config --quiet` | Válido; solo Caddy publica `80`/`443`. |
| `caddy validate` | Configuración válida. |
| API no root | `uid=10001(app)`. |
| Front no root | `uid=101(nginx)`. |
| Dependencias de desarrollo en API | `pytest` no instalado. |
| PostgreSQL de producción con TLS | `sslmode=require` conectó con TLSv1.3. |
| PostgreSQL de producción sin TLS | `sslmode=disable` rechazado por `pg_hba.conf`. |

---

## 6. Matriz de criterios

| Criterio | Estado | Evidencia / observación |
|---|---|---|
| Scripts de migraciones `001`–`008` | **CUMPLIDO** | Probados en PowerShell y Bash sobre bases nuevas. |
| Carga completa y reducida | **CUMPLIDO** | Carga full con 796.681 filas y reducida sin errores. |
| Consultas de control | **CUMPLIDO** | 0 filas problemáticas en local. |
| Backup `-Fc` + SQL comprimido | **CUMPLIDO** | Dos archivos no vacíos y verificados. |
| Restauración y comparación de conteos | **CUMPLIDO** | 30 tablas y 796.681 filas coinciden. |
| Prueba de regla de negocio en nube | **PREPARADO** | Probada en local con HTTP 409; falta ejecutarla contra el dominio real. |
| Prueba de acceso no autorizado | **PREPARADO** | Configuración TLS de producción rechaza `disable`; falta probar la allowlist del proveedor real. |
| Dockerfiles de producción | **CUMPLIDO** | API y front no root, sin dependencias de desarrollo ni secretos. |
| API configurable por entorno | **CUMPLIDO** | `DB_SSLMODE`, `CORS_ORIGINS`, puerto y pool por variables. |
| `/salud` verifica la base | **CUMPLIDO** | Consulta real y devuelve `rol_api`. |
| Front con `API_BASE_URL` runtime | **CUMPLIDO** | Misma imagen para local/nube. |
| Plantillas de entorno sin secretos | **CUMPLIDO** | `.env.example` y `.env.production.example` con placeholders. |
| `.env` y `.env.production` ignorados | **CUMPLIDO** | Verificado en `.gitignore`. |
| Sin secretos en el árbol de trabajo | **CUMPLIDO** | Auditoría local; no se imprimieron valores. |
| Sin secretos en el historial de Git | **NO CUMPLIDO** | Historial no reescrito por la Opción B. Requiere rotación cloud. |
| Rotación de credenciales locales | **CUMPLIDO** | Claves nuevas fuera de Git. |
| Rotación de credenciales cloud | **PREPARADO** | Requiere acceso al proveedor; no se usaron cuentas reales. |
| Comparación de proveedores | **CUMPLIDO** | Supabase, Render y Railway con fuentes oficiales. |
| Documentación de despliegue | **CUMPLIDO** | Este informe, notas de auditoría y checklist manual. |
| Despliegue cloud efectivo | **NO CUMPLIDO** | No se crearon recursos reales; queda el checklist manual. |

---

## 7. Riesgos y limitaciones

1. **Historial de Git:** las credenciales antiguas siguen en commits
   anteriores. La Opción B exige rotarlas en el proveedor y verificar que ya no
   funcionen.
2. **Sin proveedor real:** no se probó DNS, emisión de certificados de Caddy en
   un dominio público, firewall del proveedor ni latencia real.
3. **TLS autofirmado de referencia:** el compose usa un certificado generado
   fuera del repositorio. En un proveedor gestionado se debe usar su CA y
   preferir `verify-full`.
4. **Allowlist:** el compose de referencia protege por red interna y ausencia
   de puertos publicados. En el proveedor hay que configurar allowlist/red
   privada explícitamente.
5. **Datos:** los datos de la carga son generados con fines académicos; no hay
   datos personales reales.
6. **`005_triggers.sql`:** había una modificación local ajena a la Etapa 8; se
   excluyó del commit de esta rama.

---

## 8. Conclusión

La Etapa 8 queda **preparada y validada en local** para desplegarse en un
proveedor cloud. La base, la API y el front funcionan con la configuración de
referencia, el backup y la restauración están verificados, y las pruebas de
regla de negocio y TLS se comportan como se espera.

No se declara un despliegue cloud real porque no se utilizaron cuentas ni
credenciales de proveedores. Antes de la entrega final se debe elegir el
proveedor, ejecutar el checklist manual, rotar las credenciales cloud y
conservar la evidencia sin secretos.
