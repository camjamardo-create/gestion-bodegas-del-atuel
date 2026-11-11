#!/bin/sh
set -eu

# Genera un certificado autofirmado para el PostgreSQL interno si todavia no
# existe. No se versiona ningun certificado ni clave. El volumen de datos
# conserva el certificado entre reinicios.
SSL_DIR="${PGSSL_DIR:-/var/lib/postgresql/ssl}"

mkdir -p "$SSL_DIR"

if [ ! -s "$SSL_DIR/server.crt" ] || [ ! -s "$SSL_DIR/server.key" ]; then
    echo "Generando certificado TLS interno para PostgreSQL..."
    openssl req -x509 -newkey rsa:2048 -nodes \
        -days 825 \
        -subj "/CN=postgres" \
        -keyout "$SSL_DIR/server.key" \
        -out "$SSL_DIR/server.crt" >/dev/null 2>&1
fi

chown -R postgres:postgres "$SSL_DIR"
chmod 700 "$SSL_DIR"
chmod 600 "$SSL_DIR/server.key"
chmod 644 "$SSL_DIR/server.crt"

exec docker-entrypoint.sh "$@"
