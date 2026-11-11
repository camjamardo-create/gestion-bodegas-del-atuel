#!/usr/bin/env bash
# Prueba de acceso a la base con y sin SSL. Debe ejecutarse desde una IP NO
# autorizada para documentar el rechazo. No imprime claves.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env_if_requested
init_config
require_env "$API_PASSWORD" "DB_PASSWORD o APP_DB_PASSWORD"

echo "Prueba de acceso a $DB_NAME en $DB_HOST:$DB_PORT como $API_USER"
echo "Ejecutá esta prueba desde una IP NO permitida por el firewall/allowlist."
echo

RESULTADO_REQUIRE=""
RESULTADO_DISABLE=""
for modo in require disable; do
    set +e
    SALIDA="$(invoke_psql "$DB_NAME" "$API_USER" "$API_PASSWORD" "$modo" -t -A -c "SELECT current_user, current_database()" 2>&1)"
    CODIGO=$?
    set -e
    if [ "$CODIGO" -eq 0 ]; then
        RESULTADO="ACEPTADO"
        DETALLE="conexión aceptada: $(printf '%s' "$SALIDA" | head -n 1)"
    else
        RESULTADO="RECHAZADO"
        DETALLE="conexión rechazada: $(printf '%s' "$SALIDA" | head -n 1)"
    fi
    printf '%-8s %-10s %s\n' "$modo" "$RESULTADO" "$DETALLE"
    if [ "$modo" = "require" ]; then RESULTADO_REQUIRE="$RESULTADO"; else RESULTADO_DISABLE="$RESULTADO"; fi
done

echo
if [ "$RESULTADO_DISABLE" = "ACEPTADO" ]; then
    echo "ADVERTENCIA: la base aceptó una conexión sin SSL. Revisá pg_hba.conf."
fi
if [ "$RESULTADO_REQUIRE" = "ACEPTADO" ] && [ "$RESULTADO_DISABLE" = "ACEPTADO" ]; then
    echo "ADVERTENCIA: desde esta IP se aceptan ambos modos. Si la IP no está autorizada, revisá el firewall."
elif [ "$RESULTADO_DISABLE" = "RECHAZADO" ]; then
    echo "OK: SSL obligatorio y conexión sin SSL rechazada."
else
    echo "Resultado registrado. Desde una IP no autorizada se esperan ambos rechazos."
fi
