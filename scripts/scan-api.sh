#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
zap=${ZAP_SH:-zap.sh}
tmp=$(mktemp -d)
api_pid=
zap_pid=
cleanup() {
  [[ -z "$zap_pid" ]] || kill "$zap_pid" 2>/dev/null || true
  [[ -z "$api_pid" ]] || kill "$api_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
export JWT_SECRET=$(openssl rand -hex 32)
zap_key=$(openssl rand -hex 16)
api=http://127.0.0.1:3000
proxy=http://127.0.0.1:8090
node api/server.js > "$tmp/api.log" 2>&1 &
api_pid=$!
"$zap" -daemon -silent -dir "$tmp/zap" -host 127.0.0.1 -port 8090 \
  -config start.checkForUpdates=false -config "api.key=$zap_key" > "$tmp/zap.log" 2>&1 &
zap_pid=$!
zap_api() {
  curl -fsS --noproxy '*' -G "$proxy/JSON/$1/" -H "X-ZAP-API-Key: $zap_key" "${@:2}"
}
ready() {
  for attempt in {1..60}; do
    if "$@" 2>/dev/null; then return; fi
    sleep 1
  done
  cat "$tmp/api.log" >&2
  sed "s/$zap_key/[redactado]/g" "$tmp/zap.log" | tail -30 >&2
  return 1
}
ready curl -fsS --noproxy '*' "$api/health"
printf '\n'
ready zap_api core/view/version
printf '\n'
probe() {
  local label=$1 expected=$2 status
  shift 2
  status=$(curl -sS --noproxy '' --proxy "$proxy" -o /dev/null -w '%{http_code}' "$@" "$api/api/admin")
  printf '%s: %s (esperado %s)\n' "$label" "$status" "$expected"
  [[ "$status" == "$expected" ]]
}
probe 'Sin token' 401
probe 'JWT inválido' 401 -H 'Authorization: Bearer invalid'
probe 'JWT de usuario' 403 -H "Authorization: Bearer $(node api/token.js user)"
probe 'JWT de administrador' 200 -H "Authorization: Bearer $(node api/token.js admin)"
mkdir -p evidence
for path in health api/admin; do
  if [[ "$path" == health ]]; then
    curl -fsS --noproxy '' --proxy "$proxy" "$api/$path" >/dev/null
  fi
  scan=$(zap_api ascan/action/scan --data-urlencode "url=$api/$path" --data-urlencode recurse=false |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["scan"])')
  for attempt in {1..180}; do
    progress=$(zap_api ascan/view/status --data-urlencode "scanId=$scan" |
      python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')
    [[ "$progress" != 100 ]] || break
    sleep 1
  done
  [[ "$progress" == 100 ]]
  printf 'Escaneo activo /%s: %s%%\n' "$path" "$progress"
done
for attempt in {1..60}; do
  queued=$(zap_api pscan/view/recordsToScan | python3 -c 'import json,sys; print(json.load(sys.stdin)["recordsToScan"])')
  [[ "$queued" != 0 ]] || break
  sleep 1
done
[[ "$queued" == 0 ]]
zap_api alert/view/alertsSummary --data-urlencode "baseurl=$api" | tee evidence/zap-resumen.txt
printf '\n'
curl -fsS --noproxy '*' "$proxy/OTHER/core/other/htmlreport/" -H "X-ZAP-API-Key: $zap_key" -o evidence/zap-reporte.html
