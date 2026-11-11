-- 99_password_api.sql
-- La migracion 007 crea los roles sin clave. Las claves reales se toman de
-- variables de entorno para no dejar credenciales en el repositorio.
--
-- APP_DB_PASSWORD     -> rol_api (lectura/escritura de la API)
-- APP_REPORT_PASSWORD -> rol_reporte (solo lectura de reportes)
--
-- Docker Compose exige ambas variables; si falta una, el arranque falla en vez
-- de dejar un rol con una clave conocida o vacia.

\getenv api_password APP_DB_PASSWORD
\getenv report_password APP_REPORT_PASSWORD

ALTER ROLE rol_api PASSWORD :'api_password';
ALTER ROLE rol_reporte PASSWORD :'report_password';
