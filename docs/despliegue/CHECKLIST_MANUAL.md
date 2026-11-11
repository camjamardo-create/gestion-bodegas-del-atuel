# Checklist manual de despliegue en la nube

**Proyecto:** Bodegas del Atuel · TPI Bases de Datos  
**Etapa:** 8 · despliegue  
**Fecha:** 2026-11-10

Este checklist se ejecuta **una vez elegido el proveedor**. No contiene
credenciales reales: los valores se completan en el panel del proveedor o en
un archivo `.env.production` local que está ignorado por Git.

---

## 0. Antes de empezar

- [ ] Elegir el proveedor y la región.
- [ ] Confirmar que el proveedor permite red privada, allowlist de IP o
      deshabilitar el acceso externo a PostgreSQL.
- [ ] Confirmar que el proveedor ofrece TLS para la conexión a la base.
- [ ] Tener un dominio con DNS apuntando al servidor o al servicio del front.
- [ ] Tener Docker/Compose o acceso al runtime del proveedor.
- [ ] Crear `.env.production` a partir de `.env.production.example`.
- [ ] Verificar que `.env.production` no se agregue a Git (`git status`).
- [ ] Confirmar que `.env`, `backups/`, dumps y certificados están ignorados.

Comandos de verificación local:

```bash
git check-ignore -v .env .env.production backups/
git status --short
```

---

## 1. Crear la base y la red

### Opción A: proveedor gestionado (recomendado)

- [ ] Crear PostgreSQL 18 (o la versión compatible más cercana).
- [ ] Elegir la misma región que la API/front.
- [ ] Configurar **red privada** o **allowlist** con la IP/salida de la API.
- [ ] Deshabilitar el acceso público si el proveedor lo permite.
- [ ] Guardar el host interno, puerto, base, usuario propietario y contraseña
      en el gestor de secretos del proveedor.
- [ ] Confirmar que el acceso externo, si existe, exige TLS y solo acepta la
      IP de operaciones.

### Opción B: servidor único con Docker

Usar `docker-compose.production.yml` como referencia. Solo Caddy publica
`80`/`443`; PostgreSQL y la API quedan en la red interna.

- [ ] Crear el servidor y abrir únicamente `22`, `80` y `443`.
- [ ] Instalar Docker y Docker Compose.
- [ ] Copiar el repositorio (sin secretos) al servidor.
- [ ] Crear `.env.production` con los valores reales.
- [ ] Verificar que el puerto `5432` y el `8000` **no** estén publicados.

---

## 2. Credenciales y roles

- [ ] Generar contraseñas aleatorias y distintas para:
  - propietario de la base (`POSTGRES_PASSWORD` / `DB_OWNER_PASSWORD`);
  - `rol_api` (`APP_DB_PASSWORD` / `DB_PASSWORD`);
  - `rol_reporte` (`APP_REPORT_PASSWORD`).
- [ ] Guardar las claves en el gestor de secretos del proveedor.
- [ ] No pegarlas en issues, commits, capturas, logs ni en este checklist.
- [ ] Confirmar que `007_roles.sql` no contiene claves literales.
- [ ] Confirmar que `db/initdb/99_password_api.sql` toma las claves desde
      `APP_DB_PASSWORD` y `APP_REPORT_PASSWORD`.

Variables mínimas del operador:

```text
DB_HOST=<host-interno-o-ip-privada>
DB_PORT=5432
DB_NAME=bodegas_del_atuel
DB_OWNER_USER=<propietario>
DB_OWNER_PASSWORD=<secreto>
DB_USER=rol_api
DB_PASSWORD=<secreto>
APP_DB_PASSWORD=<secreto>
APP_REPORT_PASSWORD=<secreto>
DB_SSLMODE=require
PSQL_MODE=local
```

`PSQL_MODE=local` se usa en una máquina con `psql`. Si se prefiere no instalar
`psql`, dejar `PSQL_MODE=auto` o `docker` y los scripts usarán
`docker run postgres:18`.

---

## 3. Migraciones

Ejecutar desde la raíz del repositorio, con el rol propietario:

### PowerShell

```powershell
$env:ENV_FILE = ".env.production"
$env:PSQL_MODE = "local"
.\scripts\aplicar_migraciones.ps1
```

### Bash / Git Bash / WSL

```bash
ENV_FILE=.env.production PSQL_MODE=local bash scripts/aplicar_migraciones.sh
```

- [ ] Se aplicaron `001` a `008` en orden.
- [ ] El proceso terminó con `EXIT 0`.
- [ ] Se fijaron las claves de `rol_api` y `rol_reporte`.
- [ ] La API no se conecta con el propietario.

Verificación:

```bash
psql "host=$DB_HOST port=$DB_PORT dbname=$DB_NAME user=$DB_OWNER_USER sslmode=require" \
  -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';"
```

Resultado esperado: `30` tablas.

---

## 4. Carga de datos

### Carga completa (entrega)

```powershell
$env:ENV_FILE = ".env.production"
$env:PSQL_MODE = "local"
.\scripts\cargar_datos.ps1 -Modo full
```

```bash
ENV_FILE=.env.production PSQL_MODE=local bash scripts/cargar_datos.sh --modo full
```

### Carga reducida (demostración rápida)

```powershell
$env:ENV_FILE = ".env.production"
.\scripts\cargar_datos.ps1 -Modo reducida -Escala 0.05
```

- [ ] La carga terminó sin errores.
- [ ] No se usó `rol_api` para la carga; se usó el propietario.
- [ ] Se registraron los conteos obtenidos.

Controles:

```powershell
$env:ENV_FILE = ".env.production"
.\scripts\consultas_control.ps1
```

```bash
ENV_FILE=.env.production PSQL_MODE=local bash scripts/consultas_control.sh
```

- [ ] Las consultas marcadas como problema devuelven 0 filas.

---

## 5. Backup y restauración

### Backup

```powershell
$env:ENV_FILE = ".env.production"
.\scripts\backup.ps1
```

```bash
ENV_FILE=.env.production PSQL_MODE=local bash scripts/backup.sh --formato ambos
```

- [ ] Se generó un `.dump` con `pg_dump -Fc`.
- [ ] Se generó un `.sql.gz` con `pg_dump --format=plain | gzip`.
- [ ] Ambos archivos tienen tamaño mayor que cero.
- [ ] Los archivos quedaron fuera de Git (`backups/` ignorado).

### Restauración de prueba

```powershell
$env:ENV_FILE = ".env.production"
.\scripts\restaurar_y_verificar.ps1 -BackupFile "backups\<archivo>.dump" -EliminarRestaurada
```

```bash
ENV_FILE=.env.production PSQL_MODE=local \
  bash scripts/restaurar_y_verificar.sh --backup backups/<archivo>.dump --eliminar
```

- [ ] La restauración se hizo en una base temporal, no en la base productiva.
- [ ] Los conteos de las 30 tablas coinciden.
- [ ] La base temporal se eliminó o se conservó de forma controlada.

---

## 6. API

Variables de la API:

```text
DB_HOST=<host-interno>
DB_PORT=5432
DB_NAME=bodegas_del_atuel
DB_USER=rol_api
DB_PASSWORD=<secreto>
DB_SSLMODE=require          # o verify-full con la CA del proveedor
CORS_ORIGINS=https://<dominio-del-front>
DB_POOL_MIN_SIZE=1
DB_POOL_MAX_SIZE=10
DB_POOL_TIMEOUT=10
```

- [ ] `DB_USER` es exactamente `rol_api`.
- [ ] `DB_SSLMODE` no es `disable`.
- [ ] `CORS_ORIGINS` contiene solo el origen HTTPS real del front.
- [ ] La API no publica el puerto de PostgreSQL.
- [ ] La imagen de la API corre con usuario no root.
- [ ] La imagen no contiene `pytest` ni dependencias de desarrollo.
- [ ] `/salud` responde `status: ok`, `base_de_datos: ok` y
      `current_user: rol_api`.

Prueba:

```bash
curl -fsS "https://<dominio>/api/salud"
```

---

## 7. Front

Variables:

```text
API_BASE_URL=/api
```

o una URL absoluta si el front y la API están en dominios distintos:

```text
API_BASE_URL=https://api.<dominio>
```

- [ ] La misma imagen se usa en local y en la nube.
- [ ] `API_BASE_URL` se resuelve en tiempo de ejecución, no en el build.
- [ ] El front se sirve por HTTPS.
- [ ] El proxy `/api` o la URL absoluta llegan a la API.
- [ ] Se probaron inicio, vinos, clientes, ventas, stock y reportes.
- [ ] No hay errores de consola ni recursos bloqueados por CSP.

---

## 8. Pruebas de aceptación en la nube

### 8.1. Regla de negocio

```powershell
$env:ENV_FILE = ".env.production"
$env:API_PUBLIC_URL = "https://<dominio>/api"
.\scripts\probar_regla_en_nube.ps1
```

```bash
ENV_FILE=.env.production API_PUBLIC_URL="https://<dominio>/api" \
  bash scripts/probar_regla_en_nube.sh
```

- [ ] La API devuelve HTTP 409.
- [ ] El stock antes y después es el mismo.
- [ ] No se creó un comprobante real.

### 8.2. Acceso no autorizado

Ejecutar desde una máquina o red **no incluida** en la allowlist:

```powershell
$env:ENV_FILE = ".env.production"
.\scripts\probar_acceso_no_autorizado.ps1
```

```bash
ENV_FILE=.env.production PSQL_MODE=local bash scripts/probar_acceso_no_autorizado.sh
```

- [ ] `require` es rechazado (por red/allowlist o por TLS).
- [ ] `disable` es rechazado.
- [ ] La base no acepta conexiones TCP sin cifrado.
- [ ] Se guardó la evidencia sin mostrar claves.

### 8.3. Healthchecks

```bash
curl -fsS https://<dominio>/healthz
curl -fsS https://<dominio>/api/salud
```

- [ ] El front responde `ok`.
- [ ] La API responde con base `ok` y usuario `rol_api`.

---

## 9. Evidencia para la entrega

Guardar en un archivo local **sin secretos**:

- [ ] Fecha, proveedor, región y URL pública.
- [ ] Versión de PostgreSQL.
- [ ] Salida de migraciones (`001` a `008`) sin credenciales.
- [ ] Conteos de las 30 tablas.
- [ ] Resultado de controles (0 filas problemáticas).
- [ ] Tamaño de `.dump` y `.sql.gz`.
- [ ] Resultado de restauración y comparación.
- [ ] Salida de `/salud`.
- [ ] Resultado de `probar_regla_en_nube` (409).
- [ ] Resultado de `probar_acceso_no_autorizado` (ambos rechazos).
- [ ] Captura del front sin datos sensibles.

No adjuntar `.env`, cadenas de conexión, capturas del panel de secretos ni
salidas que incluyan contraseñas.

---

## 10. Rollback

Si falla el despliegue:

1. No borrar el volumen de datos ni la base productiva.
2. Detener el front o Caddy para dejar de recibir tráfico.
3. Restaurar el backup verificado en una base temporal y validar conteos.
4. Si es necesario, recrear el servicio de API/front con la imagen anterior.
5. Documentar el incidente y rotar cualquier credencial que haya podido
   quedar expuesta.

---

## 11. Criterio de cierre

El despliegue se considera cerrado cuando:

- [ ] Las migraciones `001`–`008` están aplicadas.
- [ ] La API usa `rol_api` y TLS.
- [ ] La base no es accesible públicamente.
- [ ] El front funciona con `API_BASE_URL` en tiempo de ejecución.
- [ ] `/salud` verifica la base.
- [ ] La regla de stock devuelve 409 sin modificar datos.
- [ ] El acceso no autorizado es rechazado.
- [ ] El backup y la restauración fueron verificados.
- [ ] Las credenciales fueron rotadas y no están en Git.
