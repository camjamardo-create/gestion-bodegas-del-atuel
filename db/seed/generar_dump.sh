#!/usr/bin/env bash
# generar_dump.sh
# TPI Base de Datos - Bodegas del Atuel
# Genera un dump de texto plano, sin dueño ni privilegios, comprimido con gzip.
#
# Uso:
#   ./db/seed/generar_dump.sh [salida.sql.gz] [base]
#
# Conexión:
#   - Si existe DATABASE_URL, se usa esa cadena.
#   - Si no, se usa la base indicada (o PGDATABASE / bodegas_del_atuel) y las
#     variables PGHOST, PGPORT, PGUSER, PGPASSWORD.
#
# Ejemplo:
#   DATABASE_URL='postgresql://postgres:clave@localhost:5433/bodegas_del_atuel' \
#     ./db/seed/generar_dump.sh
set -euo pipefail

SALIDA="${1:-db/seed/dump_completo.sql.gz}"
BASE="${2:-${PGDATABASE:-bodegas_del_atuel}}"
PGDUMP="${PGDUMP:-pg_dump}"

if [ -n "${DATABASE_URL:-}" ]; then
    CONEXION="$DATABASE_URL"
else
    CONEXION="$BASE"
fi

if ! command -v "$PGDUMP" >/dev/null 2>&1 && [ ! -x "$PGDUMP" ]; then
    echo "ERROR: no se encontró $PGDUMP en PATH." >&2
    echo "Sugerencia: exportá PGDUMP=/ruta/a/pg_dump" >&2
    exit 1
fi

mkdir -p "$(dirname "$SALIDA")"
TMP="${SALIDA%.gz}"
if [ "$TMP" = "$SALIDA" ]; then
    TMP="${SALIDA}.sql"
fi

echo "Generando dump de la base ${BASE}..."
"$PGDUMP" "$CONEXION" \
    --format=plain \
    --no-owner \
    --no-privileges \
    --clean \
    --if-exists \
    --encoding=UTF8 \
    --file="$TMP"

if [ ! -s "$TMP" ]; then
    echo "ERROR: el dump quedó vacío." >&2
    rm -f "$TMP"
    exit 1
fi

gzip -9 -f "$TMP"
gzip -t "$SALIDA"
echo "Dump generado: $SALIDA"
ls -lh "$SALIDA"

echo
echo "Restauración sugerida (base vacía):"
echo "  createdb -h localhost -p 5433 -U postgres bodegas_del_atuel_restore"
echo "  gunzip -c $SALIDA | psql -h localhost -p 5433 -U postgres -d bodegas_del_atuel_restore -v ON_ERROR_STOP=1"
