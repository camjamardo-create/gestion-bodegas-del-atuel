-- 99_password_api.sql
-- La migracion 007 crea rol_api con una clave fija de ejemplo. En Docker la
-- clave real se toma de APP_DB_PASSWORD para no dejar credenciales en el repo.
-- El compose exige APP_DB_PASSWORD; si falta, el arranque falla en vez de dejar
-- la clave de ejemplo.

\getenv api_password APP_DB_PASSWORD

ALTER ROLE rol_api PASSWORD :'api_password';
