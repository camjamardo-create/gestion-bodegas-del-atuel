#!/usr/bin/env bash
# Prueba de regla de negocio en la nube: intenta vender más unidades que el
# stock total y verifica que la API responda 409 sin modificar el stock.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env_if_requested

API_URL="${API_URL:-${API_PUBLIC_URL:-}}"
CLIENTE_ID="${CLIENTE_ID:-1}"
SALA_ID="${SALA_ID:-1}"
VINO_ID="${VINO_ID:-0}"
CANTIDAD="${CANTIDAD:-0}"

while [ $# -gt 0 ]; do
    case "$1" in
        --api-url) API_URL="${2:-}"; shift 2 ;;
        --cliente) CLIENTE_ID="${2:-}"; shift 2 ;;
        --sala) SALA_ID="${2:-}"; shift 2 ;;
        --vino) VINO_ID="${2:-}"; shift 2 ;;
        --cantidad) CANTIDAD="${2:-}"; shift 2 ;;
        -h|--help)
            echo "Uso: $0 --api-url URL [--cliente ID] [--sala ID] [--vino CODIGO] [--cantidad N]"
            exit 0
            ;;
        *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    esac
done

[ -n "$API_URL" ] || { echo "ERROR: definí --api-url o API_PUBLIC_URL." >&2; exit 1; }
API_URL="${API_URL%/}"
command -v curl >/dev/null 2>&1 || { echo "ERROR: se requiere curl." >&2; exit 1; }

PYTHON=""
if [ -x "$ROOT/.venv/Scripts/python.exe" ]; then PYTHON="$ROOT/.venv/Scripts/python.exe"
elif [ -x "$ROOT/.venv/bin/python" ]; then PYTHON="$ROOT/.venv/bin/python"
elif command -v python >/dev/null 2>&1; then PYTHON="python"
elif command -v python3 >/dev/null 2>&1; then PYTHON="python3"
else echo "ERROR: se requiere Python para interpretar JSON." >&2; exit 1
fi

HTTP_STATUS=""
HTTP_BODY=""
call_api() {
    local method="$1" path="$2" data="${3:-}" raw
    # Se evita -o con un archivo temporal: en Git Bash para Windows, curl
    # nativo puede interpretar /tmp de forma distinta a MSYS. El cuerpo y el
    # codigo viajan por stdout y se separan con el ultimo salto de linea.
    if [ -n "$data" ]; then
        raw="$(curl -sS -X "$method" -H 'Accept: application/json' -H 'Content-Type: application/json' \
            --data-binary "$data" --max-time 40 -w $'\n%{http_code}' "$API_URL$path")"
    else
        raw="$(curl -sS -X "$method" -H 'Accept: application/json' --max-time 40 \
            -w $'\n%{http_code}' "$API_URL$path")"
    fi
    HTTP_STATUS="${raw##*$'\n'}"
    HTTP_BODY="${raw%$'\n'*}"
}

json_get() {
    local path="$1"
    printf '%s' "$HTTP_BODY" | "$PYTHON" -c '
import json, sys
path = sys.argv[1].split(".")
try:
    data = json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit
cur = data
for part in path:
    if isinstance(cur, list):
        cur = cur[int(part)]
    elif isinstance(cur, dict):
        cur = cur.get(part)
    else:
        cur = None
        break
print("" if cur is None else cur)
' "$path"
}

get_stock() {
    local codigo="$1"
    call_api GET "/vinos/$codigo"
    if [ "$HTTP_STATUS" != "200" ]; then echo ""; return; fi
    json_get "stock_total"
}

echo "Prueba de regla en $API_URL"
echo

if [ "$VINO_ID" = "0" ]; then
    call_api GET "/vinos?page_size=1"
    if [ "$HTTP_STATUS" != "200" ]; then
        echo "ERROR: no se pudo consultar /vinos (HTTP $HTTP_STATUS)." >&2
        exit 1
    fi
    VINO_ID="$(json_get "items.0.codigo")"
    [ -n "$VINO_ID" ] || { echo "ERROR: no hay vinos para probar." >&2; exit 1; }
fi

STOCK_ANTES="$(get_stock "$VINO_ID")"
[ -n "$STOCK_ANTES" ] || { echo "ERROR: no se pudo leer el vino $VINO_ID." >&2; exit 1; }
if [ "$CANTIDAD" = "0" ]; then CANTIDAD=$((STOCK_ANTES + 1)); fi
[ "$CANTIDAD" -gt 0 ] || CANTIDAD=1

echo "Vino: $VINO_ID · stock total antes: $STOCK_ANTES · cantidad solicitada: $CANTIDAD"
echo "Cliente: $CLIENTE_ID · sala: $SALA_ID"

PAYLOAD="$(printf '{"id_cliente":%s,"id_sala_venta":%s,"renglones":[{"codigo_vino":%s,"cantidad":%s}]}' \
    "$CLIENTE_ID" "$SALA_ID" "$VINO_ID" "$CANTIDAD")"
call_api POST "/comprobantes" "$PAYLOAD"
STOCK_DESPUES="$(get_stock "$VINO_ID")"

MENSAJE=""
if [ -n "$HTTP_BODY" ]; then
    CODIGO="$(json_get "error.codigo")"
    DETALLE="$(json_get "error.mensaje")"
    if [ -n "$CODIGO" ] || [ -n "$DETALLE" ]; then
        MENSAJE="$CODIGO: $DETALLE"
    fi
fi

echo "HTTP: $HTTP_STATUS"
[ -n "$MENSAJE" ] && echo "Respuesta: $MENSAJE"
echo "Stock total después: $STOCK_DESPUES"
echo

if [ "$HTTP_STATUS" = "409" ] && [ "$STOCK_DESPUES" = "$STOCK_ANTES" ]; then
    echo "PASS: la regla rechazó la venta y el stock no cambió."
    exit 0
fi
if [ "$HTTP_STATUS" = "409" ]; then
    echo "FAIL: hubo 409, pero el stock cambió." >&2
elif [ "$HTTP_STATUS" = "201" ]; then
    echo "FAIL: la venta fue aceptada; se creó un comprobante real." >&2
else
    echo "FAIL: se esperaba 409 y se recibió $HTTP_STATUS. Revisá los IDs." >&2
fi
exit 1
