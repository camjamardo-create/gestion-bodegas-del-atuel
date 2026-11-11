#!/usr/bin/env bash
# Restaura un backup en una base temporal y compara los conteos de todas las
# tablas contra la base original. No toca la base original.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env_if_requested
init_config
require_env "$OWNER_PASSWORD" "DB_OWNER_PASSWORD o POSTGRES_PASSWORD"
require_identifier "$OWNER_USER"

BACKUP_FILE=""
RESTORE_DB=""
FORZAR=0
ELIMINAR=0
while [ $# -gt 0 ]; do
    case "$1" in
        --backup) BACKUP_FILE="${2:-}"; shift 2 ;;
        --db) RESTORE_DB="${2:-}"; shift 2 ;;
        --forzar) FORZAR=1; shift ;;
        --eliminar) ELIMINAR=1; shift ;;
        -h|--help)
            echo "Uso: $0 [--backup ARCHIVO] [--db NOMBRE] [--forzar] [--eliminar]"
            exit 0
            ;;
        *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$BACKUP_FILE" ]; then
    shopt -s nullglob
    candidatos=("$ROOT"/backups/*.dump "$ROOT"/backups/*.backup "$ROOT"/backups/*.sql "$ROOT"/backups/*.sql.gz)
    shopt -u nullglob
    if [ "${#candidatos[@]}" -eq 0 ]; then
        echo "ERROR: no hay backups en backups/. Indicá --backup." >&2
        exit 1
    fi
    BACKUP_FILE="$(ls -t "${candidatos[@]}" | head -n 1)"
elif [ "${BACKUP_FILE#/}" = "$BACKUP_FILE" ] && [ "${BACKUP_FILE#*:}" = "$BACKUP_FILE" ]; then
    BACKUP_FILE="$ROOT/$BACKUP_FILE"
fi
[ -s "$BACKUP_FILE" ] || { echo "ERROR: no existe o está vacío el backup $BACKUP_FILE" >&2; exit 1; }

BACKUP_DIR="$(cd "$(dirname "$BACKUP_FILE")" && pwd)"
BACKUP_NAME="$(basename "$BACKUP_FILE")"

if [ -z "$RESTORE_DB" ]; then
    RESTORE_DB="${DB_NAME}_restore_$(date +%Y%m%d_%H%M%S)"
fi
require_identifier "$RESTORE_DB"

DUMP_HOST="$DB_HOST"
if [ "$USE_DOCKER" -eq 1 ]; then DUMP_HOST="$(docker_db_host)"; fi

echo "Restauración de prueba"
echo "  Backup: $BACKUP_FILE"
echo "  Base original: $DB_NAME en $DB_HOST:$DB_PORT"
echo "  Base restaurada: $RESTORE_DB"
echo "  SSL: $DB_SSLMODE"
echo

EXISTE="$(invoke_psql postgres "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -t -A -c "SELECT 1 FROM pg_database WHERE datname = '$RESTORE_DB'")"
if [ "$(printf '%s' "$EXISTE" | tr -d '[:space:]')" = "1" ]; then
    if [ "$FORZAR" -ne 1 ]; then
        echo "ERROR: la base $RESTORE_DB ya existe. Usá --forzar o elegí otro nombre." >&2
        exit 1
    fi
    echo ">> Eliminando base existente $RESTORE_DB"
    invoke_psql postgres "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -c "DROP DATABASE \"$RESTORE_DB\""
fi

echo ">> Creando $RESTORE_DB"
invoke_psql postgres "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -c "CREATE DATABASE \"$RESTORE_DB\" OWNER \"$OWNER_USER\""

case "$BACKUP_NAME" in
    *.dump|*.backup)
        echo ">> pg_restore $BACKUP_NAME"
        if [ "$USE_DOCKER" -eq 1 ]; then
            docker run --rm -i \
                --add-host=host.docker.internal:host-gateway \
                -v "$(docker_path "$BACKUP_DIR"):/backups:ro" \
                -e PGPASSWORD -e PGSSLMODE -e PGCONNECT_TIMEOUT \
                "$DOCKER_IMAGE" pg_restore \
                --no-owner --no-privileges --exit-on-error \
                -h "$DUMP_HOST" -p "$DB_PORT" -U "$OWNER_USER" -d "$RESTORE_DB" \
                "/backups/$BACKUP_NAME"
        else
            command -v pg_restore >/dev/null 2>&1 || { echo "ERROR: no se encontró pg_restore." >&2; exit 1; }
            export PGPASSWORD="$OWNER_PASSWORD" PGSSLMODE="$DB_SSLMODE"
            pg_restore --no-owner --no-privileges --exit-on-error \
                -h "$DB_HOST" -p "$DB_PORT" -U "$OWNER_USER" -d "$RESTORE_DB" "$BACKUP_FILE"
        fi
        ;;
    *.sql.gz)
        echo ">> gunzip | psql $BACKUP_NAME"
        if [ "$USE_DOCKER" -eq 1 ]; then
            docker run --rm -i \
                --add-host=host.docker.internal:host-gateway \
                -v "$(docker_path "$BACKUP_DIR"):/backups:ro" \
                -e PGHOST="$DUMP_HOST" -e PGPORT="$DB_PORT" -e PGUSER="$OWNER_USER" \
                -e PGDATABASE_RESTORE="$RESTORE_DB" -e BACKUP_FILE="$BACKUP_NAME" \
                -e PGPASSWORD -e PGSSLMODE -e PGCONNECT_TIMEOUT \
                "$DOCKER_IMAGE" sh -c \
                'gunzip -c "/backups/$BACKUP_FILE" | psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE_RESTORE"'
        else
            command -v gzip >/dev/null 2>&1 || { echo "ERROR: no se encontró gzip." >&2; exit 1; }
            export PGPASSWORD="$OWNER_PASSWORD" PGSSLMODE="$DB_SSLMODE"
            gzip -dc "$BACKUP_FILE" | psql -X -q -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$OWNER_USER" -d "$RESTORE_DB"
        fi
        ;;
    *.sql)
        echo ">> psql $BACKUP_NAME"
        if [ "$USE_DOCKER" -eq 1 ]; then
            docker run --rm -i \
                --add-host=host.docker.internal:host-gateway \
                -v "$(docker_path "$BACKUP_DIR"):/backups:ro" \
                -e PGPASSWORD -e PGSSLMODE -e PGCONNECT_TIMEOUT \
                "$DOCKER_IMAGE" psql -X -q -v ON_ERROR_STOP=1 \
                -h "$DUMP_HOST" -p "$DB_PORT" -U "$OWNER_USER" -d "$RESTORE_DB" \
                -f "/backups/$BACKUP_NAME"
        else
            export PGPASSWORD="$OWNER_PASSWORD" PGSSLMODE="$DB_SSLMODE"
            psql -X -q -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$OWNER_USER" -d "$RESTORE_DB" -f "$BACKUP_FILE"
        fi
        ;;
    *)
        echo "ERROR: formato de backup no soportado: $BACKUP_NAME" >&2
        exit 1
        ;;
esac

get_conteos() {
    local db="$1" file
    if [ "$USE_DOCKER" -eq 1 ]; then
        file="$(psql_relative_file scripts/sql/conteos_todas_tablas.sql)"
        invoke_psql "$db" "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -t -A -f "$file"
    else
        invoke_psql "$db" "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -t -A -f "$ROOT/scripts/sql/conteos_todas_tablas.sql"
    fi
}

echo
echo ">> Comparando conteos"
ORIGINAL="$(get_conteos "$DB_NAME")"
RESTAURADA="$(get_conteos "$RESTORE_DB")"

TMP_ORIG="$(mktemp)"
TMP_REST="$(mktemp)"
trap 'rm -f "$TMP_ORIG" "$TMP_REST"' EXIT
printf '%s\n' "$ORIGINAL" | sed '/^[[:space:]]*$/d' | sort > "$TMP_ORIG"
printf '%s\n' "$RESTAURADA" | sed '/^[[:space:]]*$/d' | sort > "$TMP_REST"
TABLAS="$(wc -l < "$TMP_ORIG" | tr -d ' ')"
TOTAL="$(awk -F'|' '{s+=$2} END {printf "%d", s}' "$TMP_ORIG")"

CODIGO=0
if ! diff -u "$TMP_ORIG" "$TMP_REST"; then
    echo "Diferencias encontradas en los conteos." >&2
    CODIGO=1
else
    echo "OK: $TABLAS tablas y $TOTAL filas coinciden."
fi

if [ "$ELIMINAR" -eq 1 ]; then
    echo ">> Eliminando base restaurada $RESTORE_DB"
    invoke_psql postgres "$OWNER_USER" "$OWNER_PASSWORD" "$DB_SSLMODE" -c "DROP DATABASE \"$RESTORE_DB\""
else
    echo "Base restaurada conservada: $RESTORE_DB"
fi

if [ "$CODIGO" -ne 0 ]; then exit 1; fi
echo "Restauración y verificación completadas."
