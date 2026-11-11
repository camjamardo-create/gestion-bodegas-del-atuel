# Notas de auditoría de la Etapa 8

**Proyecto:** Bodegas del Atuel · TPI Bases de Datos  
**Rama de trabajo:** `etapa-8-nube`  
**Base de la rama:** `origin/main` en `49c5570`  
**Fecha de revisión:** 2026-11-10  
**Alcance:** secretos, credenciales, despliegue, base de datos, API y front.

---

## 1. Resumen ejecutivo

La Etapa 8 se preparó para desplegar la API y el front en la nube sin publicar
la base de datos ni la API, usando TLS en la conexión a PostgreSQL y roles con
privilegios mínimos.

La auditoría de secretos encontró credenciales históricas en archivos del
repositorio. Se eligió la **Opción B**: rotar las credenciales y dejar de usar
valores literales, sin reescribir el historial de Git. Por ese motivo el
criterio “sin secretos en el repositorio, incluido su historial” **no puede
marcarse como CUMPLIDO** hasta completar la rotación en el proveedor cloud y
confirmar que las credenciales antiguas ya no son válidas.

En el entorno local sí se rotaron las claves de `postgres`, `rol_api` y
`rol_reporte`. Las claves nuevas no se imprimieron, no se guardaron en Git y
solo viven en el archivo `.env` local, que está ignorado.

---

## 2. Hallazgos de la auditoría de secretos

Se revisaron los 133 commits del historial, las ramas y los stashes, además del
árbol de trabajo. Los hallazgos relevantes fueron:

| Archivo / ubicación | Hallazgo | Tratamiento |
|---|---|---|
| `db/migrations/007_roles.sql` (versiones anteriores) | Contraseñas literales para `rol_api` y `rol_reporte` | Se eliminaron del archivo actual; los roles se crean sin clave y las claves se fijan desde variables de entorno. |
| `api/README.md` (historial) | Ejemplos con una credencial concreta | Se reemplazaron por marcadores genéricos en la versión actual. |
| `.env` local | Claves reales del entorno de desarrollo | Está ignorado por Git; no se commitea. |
| `.env.production` | Variables reales del futuro despliegue | Está ignorado por Git; solo se versiona `.env.production.example` con placeholders. |
| `backups/` y dumps | Copias con datos y posibles secretos de conexión | Están ignorados; no se incluyen en el commit. |

### 2.1. Decisión: Opción B

No se reescribió el historial porque el repositorio ya fue compartido y porque
la consigna permite rotar credenciales. La consecuencia es explícita:

- El historial todavía contiene valores antiguos.
- Esos valores deben considerarse comprometidos.
- La rotación en el proveedor cloud es un paso manual obligatorio antes de
  declarar el criterio como cumplido.
- No se deben publicar capturas, logs ni salidas que muestren las claves.

### 2.2. Rotación local realizada

Se rotaron las claves de:

- `postgres` / propietario local.
- `rol_api`.
- `rol_reporte`.

Las claves nuevas son aleatorias, de 48 caracteres hexadecimales, y no se
imprimieron en la consola ni se incluyeron en este documento. La API local se
recreó y `/salud` confirmó que conecta como `rol_api`.

### 2.3. Estado del criterio

| Criterio | Estado | Observación |
|---|---|---|
| Sin secretos en el árbol de trabajo | CUMPLIDO | Solo hay placeholders y variables de entorno. |
| `.env` y `.env.production` ignorados | CUMPLIDO | Verificado en `.gitignore`. |
| Sin secretos en el historial de Git | NO CUMPLIDO | Historial no reescrito por decisión Opción B. |
| Rotación de credenciales locales | CUMPLIDO | Claves nuevas fuera de Git. |
| Rotación de credenciales cloud | PREPARADO / PENDIENTE | Requiere acceso al proveedor elegido. |

---

## 3. Cambios de seguridad aplicados

### 3.1. Base de datos

- `db/migrations/007_roles.sql` crea `rol_api` y `rol_reporte` sin contraseña
  literal.
- Las contraseñas se fijan desde `APP_DB_PASSWORD` y `APP_REPORT_PASSWORD` en
  `db/initdb/99_password_api.sql` o en `scripts/aplicar_migraciones.*`.
- La API solo acepta conectarse como `rol_api`; rechaza propietarios y
  superusuarios.
- `db/initdb/01_migraciones.sql` aplica las migraciones `001` a `008` en orden,
  con `ON_ERROR_STOP`.
- El compose de producción usa TLS interno y un `pg_hba.conf` que rechaza
  conexiones TCP sin cifrado.
- La base de producción no publica el puerto `5432`; solo queda en la red
  interna del compose o en la red privada/allowlist del proveedor.

### 3.2. API

- Configuración por entorno: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`,
  `DB_PASSWORD`, `DB_SSLMODE`, `CORS_ORIGINS`, tamaños del pool y timeouts.
- `DB_SSLMODE=require` es el valor por defecto de la configuración; en local se
  usa `disable` porque el PostgreSQL de Compose no publica TLS.
- `CORS_ORIGINS` se toma de entorno y no se abre a cualquier origen.
- La imagen se ejecuta como UID `10001` (usuario `app`), no como root.
- Solo se instalan dependencias de ejecución; `requirements-dev.txt` queda para
  el entorno de desarrollo y no entra en la imagen.
- No hay credenciales en el Dockerfile ni en el código.
- `/salud` consulta la base y devuelve el usuario efectivo de la conexión.

### 3.3. Front

- La misma imagen Nginx se usa en local y en la nube.
- `API_BASE_URL` se resuelve en tiempo de ejecución mediante `config.js`.
- Nginx corre como usuario `nginx`, no como root.
- El proxy `/api` permite usar el mismo origen en el compose local.
- Se agregaron headers de seguridad y un endpoint `/healthz`.

### 3.4. Red y TLS

- Compose local: solo para desarrollo; PostgreSQL no tiene TLS y por eso
  `DB_SSLMODE=disable` es aceptado únicamente en local.
- Compose de producción: Caddy publica `80`/`443`; la base y la API no
  publican puertos al host.
- PostgreSQL de producción genera un certificado autofirmado fuera del
  repositorio y usa `ssl=on`.
- `pg_hba.conf` de producción acepta `hostssl` con `scram-sha-256` y rechaza
  `hostnossl`.
- En un proveedor gestionado se debe usar su CA y evaluar
  `DB_SSLMODE=verify-full`; `require` sigue siendo el mínimo aceptable.

---

## 4. Evidencia de validación local

Todas las pruebas se ejecutaron contra PostgreSQL 18 en Docker. No se
incluyeron valores de credenciales en las salidas.

| Prueba | Comando / método | Resultado |
|---|---|---|
| Migraciones `001`–`008` desde cero | `scripts/aplicar_migraciones.ps1` y `.sh` sobre un contenedor nuevo | 8 migraciones aplicadas; `rol_api` pudo consultar `vino`. |
| Inicialización tipo producción | `db/initdb/01_migraciones.sql`, `02_seed_minimo.sql`, `99_password_api.sql` | 30 tablas, 41 índices, `rol_api` con acceso. |
| Carga reducida | `scripts/cargar_datos.ps1 -Modo reducida -Escala 0.05` | Carga completa sin errores. |
| Carga full | `scripts/cargar_datos.ps1 -Modo full` | 30 tablas; 796.681 filas en total. |
| Controles de la Etapa 3 | `scripts/consultas_control.ps1` y `.sh` | Todas las consultas de control devolvieron 0 filas problemáticas. |
| Backup custom | `scripts/backup.ps1` | `.dump` de 6.408.033 bytes. |
| Backup SQL comprimido | `scripts/backup.ps1` | `.sql.gz` de 6.265.169 bytes. |
| Restauración `.dump` | `scripts/restaurar_y_verificar.ps1 -BackupFile ... -EliminarRestaurada` | 30 tablas y 796.681 filas coinciden. |
| Restauración `.sql.gz` | `scripts/restaurar_y_verificar.ps1 -BackupFile ... -EliminarRestaurada` | 30 tablas y 796.681 filas coinciden. |
| API local | `GET http://localhost:8080/api/salud` | `{"status":"ok","base_de_datos":"ok","current_user":"rol_api"}` |
| Regla de stock | `scripts/probar_regla_en_nube.ps1` y `.sh` | HTTP 409; stock antes y después igual. |
| TLS de producción | Contenedor con `ssl=on` y `pg_hba.conf` de producción | `sslmode=require` conectó con TLSv1.3; `sslmode=disable` fue rechazado. |
| Front | Navegador sobre `http://localhost:8080` | Inicio, vinos, ficha, clientes, ventas, stock y reportes sin errores de consola. |
| Pruebas de API | `pytest api/tests` | 13 pruebas aprobadas. |
| Imágenes no root | `docker run --entrypoint id ...` | API `uid=10001(app)`; front `uid=101(nginx)`. |
| Dependencias de desarrollo | `importlib.util.find_spec('pytest')` en la imagen API | `False`. |
| Compose local | `docker compose config --quiet` | Configuración válida. |
| Compose de producción | `docker compose --env-file .env.production.example -f docker-compose.production.yml config --quiet` | Configuración válida; solo Caddy publica `80`/`443`. |
| Caddyfile | `caddy validate --config /etc/caddy/Caddyfile` | Configuración válida. |

La prueba de acceso no autorizado en local muestra un resultado esperado para
desarrollo: `require` es rechazado porque el PostgreSQL local no tiene TLS y
`disable` es aceptado. En producción el mismo script debe ejecutarse desde una
IP no autorizada y deben rechazarse ambos modos (por `pg_hba`/TLS y por la
allowlist o red privada del proveedor).

---

## 5. Riesgos y pendientes

1. **Historial de Git:** contiene credenciales antiguas. No se reescribió por la
   Opción B. Rotar en el proveedor y verificar que las claves viejas ya no
   funcionan.
2. **Proveedor cloud:** no se eligió proveedor ni se crearon recursos reales en
   esta entrega. El despliegue efectivo queda como checklist manual.
3. **Certificado TLS:** el compose de referencia usa un certificado
   autofirmado. En un proveedor gestionado se debe usar su CA y evaluar
   `verify-full`.
4. **Restricción por IP:** en el compose de referencia la protección es la red
   interna de Docker y la ausencia de puertos publicados. En un proveedor se
   debe configurar allowlist, red privada o deshabilitar el acceso externo.
5. **Cambio local ajeno:** `db/migrations/005_triggers.sql` tenía una
   modificación previa en el árbol de trabajo. No forma parte de la Etapa 8 y
   no se incluye en el commit de esta rama.
6. **`007_roles.sql`:** el nombre de la base se resolvió con
   `current_database()` para no hardcodear `bodegas_del_atuel`. Si se cambia el
   nombre del rol o del esquema, revisar los `GRANT`/`REVOKE`.

---

## 6. Conclusión de auditoría

La implementación local y la configuración de referencia están preparadas y
probadas. La entrega no declara un despliegue cloud real porque no se usaron
cuentas ni credenciales de proveedores. Antes de publicar en la nube se debe
completar el checklist manual, rotar las credenciales del proveedor y ejecutar
las pruebas de acceso desde una IP no autorizada.
