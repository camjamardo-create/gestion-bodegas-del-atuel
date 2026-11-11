#!/bin/sh
set -eu

# API_BASE_URL se resuelve en tiempo de ejecucion. La misma imagen sirve para
# local (por defecto /api) y para la nube (URL publica de la API o /api detras
# del proxy HTTPS).
API_BASE_URL="${API_BASE_URL:-/api}"

case "$API_BASE_URL" in
    http://*|https://*|/*) ;;
    *)
        echo "ERROR: API_BASE_URL debe ser /api o una URL http(s) absoluta." >&2
        exit 1
        ;;
esac

ESCAPED_BASE=$(printf '%s' "$API_BASE_URL" | sed 's/\\/\\\\/g; s/"/\\"/g')

cat > /usr/share/nginx/html/config.js <<EOF
window.__APP_CONFIG__ = {
  apiBaseUrl: "${ESCAPED_BASE}"
};
EOF

exec "$@"
