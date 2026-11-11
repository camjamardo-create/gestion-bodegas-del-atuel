#!/usr/bin/env bash
# Ejecuta las consultas de control de la Etapa 3 contra la base indicada.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env_if_requested
init_config
require_env "$OWNER_PASSWORD" "DB_OWNER_PASSWORD o POSTGRES_PASSWORD"

echo "Controles sobre $DB_NAME en $DB_HOST:$DB_PORT como $OWNER_USER"
echo "SSL: $DB_SSLMODE"
echo

if [ "$USE_DOCKER" -eq 1 ]; then
    invoke_psql "$DB_NAME" "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -f /repo/db/seed/consultas_control.sql
else
    invoke_psql "$DB_NAME" "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -f "$ROOT/db/seed/consultas_control.sql"
fi

echo
echo "Controles ejecutados. Revisá que las consultas marcadas como problema devuelvan 0 filas."
