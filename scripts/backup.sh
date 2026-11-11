#!/usr/bin/env bash
# Genera backup lógico con pg_dump en formato custom (-Fc) y/o SQL comprimido.
# Usa el rol propietario. Los archivos quedan en backups/ y están ignorados por Git.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env_if_requested
init_config
require_env "$OWNER_PASSWORD" "DB_OWNER_PASSWORD o POSTGRES_PASSWORD"

FORMATO="ambos"
DIRECTORIO=""
while [ $# -gt 0 ]; do
    case "$1" in
        --formato) FORMATO="${2:-}"; shift 2 ;;
        --directorio) DIRECTORIO="${2:-}"; shift 2 ;;
        -h|--help)
            echo "Uso: $0 [--formato custom|plain|ambos] [--directorio RUTA]"
            exit 0
            ;;
        *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    esac
done

case "$FORMATO" in
    custom|plain|ambos) ;;
    *) echo "ERROR: --formato debe ser custom, plain o ambos." >&2; exit 2 ;;
esac

if [ -n "$DIRECTORIO" ]; then
    case "$DIRECTORIO" in
        /*|[A-Za-z]:*) BACKUP_DIR="$DIRECTORIO" ;;
        *) BACKUP_DIR="$ROOT/$DIRECTORIO" ;;
    esac
else
    BACKUP_DIR="$ROOT/backups"
fi
mkdir -p "$BACKUP_DIR"

STAMP="$(date +%Y%m%d_%H%M%S)"
BASE="${DB_NAME}_${STAMP}"
DUMP_HOST="$DB_HOST"
if [ "$USE_DOCKER" -eq 1 ]; then DUMP_HOST="$(docker_db_host)"; fi
CREADOS=()

export PGPASSWORD="$OWNER_PASSWORD"
export PGSSLMODE="$DB_SSLMODE"
export PGCONNECT_TIMEOUT="10"

echo "Backup de $DB_NAME en $DB_HOST:$DB_PORT como $OWNER_USER"
echo "SSL: $DB_SSLMODE · destino: $BACKUP_DIR"
echo

if [ "$FORMATO" = "custom" ] || [ "$FORMATO" = "ambos" ]; then
    echo ">> pg_dump -Fc $BASE.dump"
    if [ "$USE_DOCKER" -eq 1 ]; then
        docker run --rm -i \
            --add-host=host.docker.internal:host-gateway \
            -v "$(docker_path "$BACKUP_DIR"):/backups" \
            -e PGPASSWORD -e PGSSLMODE -e PGCONNECT_TIMEOUT \
            "$DOCKER_IMAGE" pg_dump \
            -h "$DUMP_HOST" -p "$DB_PORT" -U "$OWNER_USER" -d "$DB_NAME" \
            --format=custom --no-owner --no-privileges \
            --file="/backups/$BASE.dump"
    else
        command -v pg_dump >/dev/null 2>&1 || { echo "ERROR: no se encontró pg_dump local." >&2; exit 1; }
        pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$OWNER_USER" -d "$DB_NAME" \
            --format=custom --no-owner --no-privileges \
            --file="$BACKUP_DIR/$BASE.dump"
    fi
    [ -s "$BACKUP_DIR/$BASE.dump" ] || { echo "ERROR: no se generó $BASE.dump" >&2; exit 1; }
    CREADOS+=("$BACKUP_DIR/$BASE.dump")
fi

if [ "$FORMATO" = "plain" ] || [ "$FORMATO" = "ambos" ]; then
    echo ">> pg_dump --format=plain | gzip -9 $BASE.sql.gz"
    if [ "$USE_DOCKER" -eq 1 ]; then
        docker run --rm -i \
            --add-host=host.docker.internal:host-gateway \
            -v "$(docker_path "$BACKUP_DIR"):/backups" \
            -e PGHOST="$DUMP_HOST" -e PGPORT="$DB_PORT" -e PGUSER="$OWNER_USER" \
            -e PGDATABASE="$DB_NAME" -e PGPASSWORD -e PGSSLMODE -e PGCONNECT_TIMEOUT \
            -e BACKUP_FILE="$BASE.sql.gz" \
            "$DOCKER_IMAGE" sh -c \
            'pg_dump --format=plain --no-owner --no-privileges | gzip -9 > "/backups/$BACKUP_FILE"'
    else
        command -v pg_dump >/dev/null 2>&1 || { echo "ERROR: no se encontró pg_dump local." >&2; exit 1; }
        command -v gzip >/dev/null 2>&1 || { echo "ERROR: no se encontró gzip local." >&2; exit 1; }
        pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$OWNER_USER" -d "$DB_NAME" \
            --format=plain --no-owner --no-privileges \
            --file="$BACKUP_DIR/$BASE.sql"
        gzip -9 -f "$BACKUP_DIR/$BASE.sql"
    fi
    [ -s "$BACKUP_DIR/$BASE.sql.gz" ] || { echo "ERROR: no se generó $BASE.sql.gz" >&2; exit 1; }
    CREADOS+=("$BACKUP_DIR/$BASE.sql.gz")
fi

echo
echo "Backup generado:"
for archivo in "${CREADOS[@]}"; do
    ls -lh "$archivo"
done
echo "No se imprimieron credenciales. Verificá la restauración con scripts/restaurar_y_verificar.sh."
