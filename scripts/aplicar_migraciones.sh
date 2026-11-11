#!/usr/bin/env bash
# Aplica 001..008 con el rol propietario y fija las claves de rol_api y
# rol_reporte desde variables de entorno. No usa credenciales en argumentos.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env_if_requested
init_config

require_env "$OWNER_PASSWORD" "DB_OWNER_PASSWORD o POSTGRES_PASSWORD"
require_env "$API_PASSWORD" "APP_DB_PASSWORD o DB_PASSWORD"
require_env "$REPORT_PASSWORD" "APP_REPORT_PASSWORD"

echo "Aplicando migraciones sobre $DB_NAME en $DB_HOST:$DB_PORT como $OWNER_USER"
if [ "$USE_DOCKER" -eq 1 ]; then
    echo "Modo de cliente: docker run $DOCKER_IMAGE"
else
    echo "Modo de cliente: psql local"
fi
echo "SSL: $DB_SSLMODE"
echo

for numero in 001 002 003 004 005 006 007 008; do
    archivo="$(find "$ROOT/db/migrations" -maxdepth 1 -type f -name "${numero}_*.sql" | head -n 1)"
    if [ -z "$archivo" ]; then
        echo "ERROR: no se encontró la migración $numero." >&2
        exit 1
    fi
    echo ">> Aplicando $(basename "$archivo")"
    if [ "$USE_DOCKER" -eq 1 ]; then
        invoke_psql "$DB_NAME" "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -f "/repo/db/migrations/$(basename "$archivo")"
    else
        invoke_psql "$DB_NAME" "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -f "$archivo"
    fi
done

echo ">> Fijando claves de rol_api y rol_reporte"
if [ "$USE_DOCKER" -eq 1 ]; then
    invoke_psql "$DB_NAME" "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -f /repo/db/initdb/99_password_api.sql
else
    invoke_psql "$DB_NAME" "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -f "$ROOT/db/initdb/99_password_api.sql"
fi

echo
echo "Migraciones aplicadas. No se imprimieron claves."
