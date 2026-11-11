#!/bin/sh
set -eu

# El puerto interno es configurable para plataformas que inyectan PORT.
# En el compose de referencia se mantiene 8000 porque Nginx y Caddy usan ese
# puerto en la red interna.
PORT="${PORT:-8000}"
case "$PORT" in
    ''|*[!0-9]*)
        echo "ERROR: PORT debe ser un numero entero." >&2
        exit 1
        ;;
esac

exec uvicorn app.main:app \
    --host 0.0.0.0 \
    --port "$PORT" \
    --proxy-headers \
    --forwarded-allow-ips='*'
