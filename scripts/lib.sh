#!/usr/bin/env bash
# Utilidades compartidas por los scripts bash de la Etapa 8.
# No imprime credenciales. Las claves se pasan por entorno.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_IMAGE="${DOCKER_IMAGE:-postgres:18}"

# Docker en Windows necesita rutas del host para los montajes, pero los
# argumentos internos del contenedor (-w /repo, -f /repo/...) deben quedar
# intactos. cygpath solo existe en Git Bash/MSYS.
if command -v cygpath >/dev/null 2>&1; then
    DOCKER_ROOT="$(cygpath -w "$ROOT")"
    export MSYS_NO_PATHCONV=1
else
    DOCKER_ROOT="$ROOT"
fi

docker_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

env_value() {
    local name="$1" default="${2:-}"
    local value="${!name:-}"
    if [ -z "$value" ]; then
        printf '%s' "$default"
    else
        printf '%s' "$value"
    fi
}

load_env_file() {
    local path="$1" line key value
    [ -f "$path" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        case "$line" in
            ""|\#*) continue ;;
        esac
        case "$line" in
            export\ *) line="${line#export }" ;;
        esac
        case "$line" in
            *=*) ;;
            *) continue ;;
        esac
        key="${line%%=*}"
        value="${line#*=}"
        key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        value="${value%\"}"; value="${value#\"}"
        value="${value%\'}"; value="${value#\'}"
        if [ -n "$key" ] && [ -z "${!key:-}" ]; then
            export "$key=$value"
        fi
    done < "$path"
}

load_env_if_requested() {
    if [ -n "${ENV_FILE:-}" ]; then
        case "$ENV_FILE" in
            /*|[A-Za-z]:*) ;;
            *) ENV_FILE="$(pwd)/$ENV_FILE" ;;
        esac
        load_env_file "$ENV_FILE"
    fi
}

init_config() {
    DB_HOST="$(env_value DB_HOST localhost)"
    DB_PORT="$(env_value DB_PORT 5432)"
    DB_NAME="$(env_value DB_NAME bodegas_del_atuel)"
    DB_SSLMODE="$(env_value DB_SSLMODE require)"

    OWNER_USER="$(env_value DB_OWNER_USER "$(env_value POSTGRES_USER postgres)")"
    OWNER_PASSWORD="$(env_value DB_OWNER_PASSWORD "$(env_value POSTGRES_PASSWORD "")")"
    API_USER="$(env_value DB_USER rol_api)"
    API_PASSWORD="$(env_value DB_PASSWORD "$(env_value APP_DB_PASSWORD "")")"
    REPORT_PASSWORD="$(env_value APP_REPORT_PASSWORD "")"
    API_PUBLIC_URL="$(env_value API_PUBLIC_URL "")"

    PSQL_MODE="$(env_value PSQL_MODE auto)"
    USE_DOCKER=0
    if [ "$PSQL_MODE" != "local" ] && command -v docker >/dev/null 2>&1; then
        USE_DOCKER=1
    elif command -v psql >/dev/null 2>&1; then
        USE_DOCKER=0
    else
        echo "ERROR: no se encontró docker ni psql. Instalá Docker Desktop o PostgreSQL." >&2
        exit 1
    fi
}

require_env() {
    local value="$1" name="$2"
    if [ -z "$value" ]; then
        echo "ERROR: falta la variable de entorno obligatoria $name." >&2
        exit 1
    fi
}

require_identifier() {
    local value="$1"
    if ! printf '%s' "$value" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
        echo "ERROR: identificador inválido: $value" >&2
        exit 1
    fi
}

docker_db_host() {
    case "$DB_HOST" in
        localhost|127.0.0.1|::1) printf '%s' "host.docker.internal" ;;
        *) printf '%s' "$DB_HOST" ;;
    esac
}

psql_relative_file() {
    local file="$1" full relative
    case "$file" in
        /*|[A-Za-z]:*) full="$file" ;;
        *) full="$ROOT/$file" ;;
    esac
    if [ ! -f "$full" ]; then
        echo "ERROR: no existe el archivo SQL: $full" >&2
        exit 1
    fi
    relative="${full#"$ROOT"/}"
    if [ "$relative" = "$full" ]; then
        echo "ERROR: el archivo SQL debe estar dentro del repositorio: $full" >&2
        exit 1
    fi
    printf '/repo/%s' "${relative//\\//}"
}

export_pg_env() {
    local user="$1" password="$2" sslmode="$3"
    export PGPASSWORD="$password"
    export PGSSLMODE="$sslmode"
    export APP_DB_PASSWORD="$API_PASSWORD"
    export APP_REPORT_PASSWORD="$REPORT_PASSWORD"
    export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"
}

invoke_psql() {
    local database="${1:-$DB_NAME}"
    local user="${2:-$OWNER_USER}"
    local password="${3:-$OWNER_PASSWORD}"
    local sslmode="${4:-$DB_SSLMODE}"
    shift 4 2>/dev/null || true

    require_env "$password" "la clave de conexión de $user"
    export_pg_env "$user" "$password" "$sslmode"

    local host psql_args
    if [ "$USE_DOCKER" -eq 1 ]; then
        host="$(docker_db_host)"
    else
        host="$DB_HOST"
    fi
    psql_args=(-X -q -v ON_ERROR_STOP=1 -h "$host" -p "$DB_PORT" -U "$user" -d "$database")

    if [ "$USE_DOCKER" -eq 1 ]; then
        docker run --rm -i \
            --add-host=host.docker.internal:host-gateway \
            -v "$DOCKER_ROOT:/repo:ro" \
            -w /repo \
            -e PGPASSWORD -e PGSSLMODE -e APP_DB_PASSWORD -e APP_REPORT_PASSWORD -e PGCONNECT_TIMEOUT \
            "$DOCKER_IMAGE" psql "${psql_args[@]}" "$@"
    else
        psql "${psql_args[@]}" "$@"
    fi
}

run_docker_tool() {
    local environment="$1"; shift
    local mounts="$1"; shift
    local args=()
    local mount key
    for key in $environment; do
        args+=(-e "$key")
    done
    for mount in $mounts; do
        args+=(-v "$mount")
    done
    docker run --rm -i \
        --add-host=host.docker.internal:host-gateway \
        "${args[@]}" \
        -e PGPASSWORD -e PGSSLMODE -e PGCONNECT_TIMEOUT \
        "$DOCKER_IMAGE" "$@"
}
