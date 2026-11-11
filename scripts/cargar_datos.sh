#!/usr/bin/env bash
# Carga masiva completa o reducida. La carga usa el rol propietario, nunca
# rol_api. Al terminar se pueden ejecutar los controles de la Etapa 3.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env_if_requested
init_config
require_env "$OWNER_PASSWORD" "DB_OWNER_PASSWORD o POSTGRES_PASSWORD"

MODO="full"
ESCALA="0"
CON_CONTROL=0
SIN_CONTROL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --modo) MODO="${2:-}"; shift 2 ;;
        --escala) ESCALA="${2:-}"; shift 2 ;;
        --con-control) CON_CONTROL=1; shift ;;
        --sin-control) SIN_CONTROL=1; shift ;;
        -h|--help)
            echo "Uso: $0 [--modo full|reducida] [--escala N] [--con-control] [--sin-control]"
            exit 0
            ;;
        *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    esac
done

case "$MODO" in
    full|reducida) ;;
    *) echo "ERROR: --modo debe ser full o reducida." >&2; exit 2 ;;
esac

if [ -x "$ROOT/.venv/Scripts/python.exe" ]; then
    PYTHON="$ROOT/.venv/Scripts/python.exe"
elif [ -x "$ROOT/.venv/bin/python" ]; then
    PYTHON="$ROOT/.venv/bin/python"
elif command -v python >/dev/null 2>&1; then
    PYTHON="python"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON="python3"
else
    echo "ERROR: no se encontró Python. Creá .venv o instalá Python 3.12." >&2
    exit 1
fi

export DATABASE_URL=""
export PGHOST="$DB_HOST"
export PGPORT="$DB_PORT"
export PGUSER="$OWNER_USER"
export PGPASSWORD="$OWNER_PASSWORD"
export PGDATABASE="$DB_NAME"
export PGSSLMODE="$DB_SSLMODE"
export PGCONNECT_TIMEOUT="30"
export APP_DB_PASSWORD="$API_PASSWORD"
export APP_REPORT_PASSWORD="$REPORT_PASSWORD"

ARGS=(db/seed/cargar_datos.py --limpiar)
if [ "$MODO" = "reducida" ]; then
    if [ "$ESCALA" = "0" ]; then ESCALA="0.1"; fi
    ARGS+=(--escala "$ESCALA")
    if [ "$CON_CONTROL" -eq 0 ]; then ARGS+=(--sin-control); fi
elif [ "$ESCALA" != "0" ]; then
    ARGS+=(--escala "$ESCALA")
fi
if [ "$SIN_CONTROL" -eq 1 ]; then ARGS+=(--sin-control); fi

echo "Carga $MODO sobre $DB_NAME en $DB_HOST:$DB_PORT como $OWNER_USER"
echo "SSL: $DB_SSLMODE"
echo

"$PYTHON" "${ARGS[@]}"

if [ "$CON_CONTROL" -eq 1 ] && [ "$MODO" = "reducida" ]; then
    echo
    echo "Ejecutando consultas de control de la Etapa 3..."
    if [ "$USE_DOCKER" -eq 1 ]; then
        invoke_psql "$DB_NAME" "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -f /repo/db/seed/consultas_control.sql
    else
        invoke_psql "$DB_NAME" "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -f "$ROOT/db/seed/consultas_control.sql"
    fi
fi

echo
echo "Carga finalizada correctamente."
