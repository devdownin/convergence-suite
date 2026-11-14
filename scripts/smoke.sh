#!/usr/bin/env bash
# Test de fumée de la suite (tâche 1.4 du plan Convergence).
#
# Vérifie, pour les modules actifs dans COMPOSE_FILE :
#   1. la santé HTTP de chaque application ;
#   2. le catalogue MCP de chaque serveur (initialize → notifications/initialized → tools/list) ;
#   3. que KafkaExplorer voit le topic métier toll-events (critère de la tâche 1.2) ;
#   4. que l'agent a bien enregistré ses connexions MCP ;
#   5. que le proxy TLS sert KafkaExplorer et que son /mcp répond sans 426 (critère de la tâche 1.3).
#
# Usage : scripts/smoke.sh            (lit .env à la racine du dépôt)
#         SMOKE_TIMEOUT=600 scripts/smoke.sh
# Dépendances : bash, curl, grep.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$root/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$root/.env"
  set +a
fi

TIMEOUT="${SMOKE_TIMEOUT:-300}"
HOST="${SMOKE_HOST:-127.0.0.1}"
EXPLORER="http://$HOST:${EXPLORER_PORT:-8080}"
AGENT="http://$HOST:${KEX_AGENT_PORT:-8081}"
AR_UI="http://$HOST:${AUTOROUTES_UI_PORT:-8084}"
AR_API="http://$HOST:${AUTOROUTES_API_PORT:-8085}"
AR_MCP="http://$HOST:${AUTOROUTES_MCP_PORT:-8090}"
SPECTRA="http://$HOST:${SPECTRA_API_PORT:-8089}"
GRAFANA="http://$HOST:${GRAFANA_PORT:-3000}"
KEYCLOAK="http://$HOST:${KEYCLOAK_PORT:-8180}"
PROXY_PORT="${PROXY_HTTPS_PORT:-8443}"
PROTOCOL_VERSION="2025-06-18"
modules=":${COMPOSE_FILE:-compose.yaml}:"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
passed=0
failed=0

ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; passed=$((passed + 1)); }
ko()   { printf '  \033[31mÉCHEC\033[0m %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "${2:0:400}"; failed=$((failed + 1)); }
step() { printf '\n%s\n' "$1"; }
has_module() { [[ "$modules" == *":compose.$1.yaml:"* ]]; }

# Attend qu'une URL réponde 2xx, au plus TIMEOUT secondes. Les autres arguments vont à curl.
wait_http() {
  local name="$1" url="$2"
  shift 2
  local deadline=$((SECONDS + TIMEOUT))
  until curl -fsS -o /dev/null --max-time 5 "$@" "$url" 2>/dev/null; do
    if ((SECONDS >= deadline)); then
      ko "$name ($url)" "pas de réponse 2xx en ${TIMEOUT}s"
      return 1
    fi
    sleep 3
  done
  ok "$name"
}

# ─── Client MCP minimal (Streamable HTTP) ────────────────────────────────────────
# mcp_open URL "En-tête: valeur"  → ouvre une session ; MCP_SESSION reçoit son identifiant.
# mcp_rpc  URL "En-tête: valeur" JSON → affiche le corps de la réponse (JSON ou SSE).
MCP_SESSION=""

mcp_rpc() {
  local url="$1" auth="$2" body="$3"
  local args=(-sS --max-time 60 -o "$work/body" -D "$work/headers" -w '%{http_code}'
    -H 'Content-Type: application/json'
    -H 'Accept: application/json, text/event-stream'
    -H "MCP-Protocol-Version: $PROTOCOL_VERSION")
  [[ -n "$auth" ]] && args+=(-H "$auth")
  [[ -n "$MCP_SESSION" ]] && args+=(-H "Mcp-Session-Id: $MCP_SESSION")
  # curl écrit déjà 000 quand la connexion échoue : ne rien ajouter.
  MCP_STATUS="$(curl "${args[@]}" --data "$body" "$url" 2>/dev/null)" || true
  cat "$work/body" 2>/dev/null
}

mcp_open() {
  local url="$1" auth="$2"
  MCP_SESSION=""
  mcp_rpc "$url" "$auth" '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"'"$PROTOCOL_VERSION"'","capabilities":{},"clientInfo":{"name":"convergence-smoke","version":"1"}}}' >/dev/null
  [[ "$MCP_STATUS" == 200 ]] || return 1
  MCP_SESSION="$(grep -i '^mcp-session-id:' "$work/headers" | head -1 | cut -d' ' -f2 | tr -d '\r')"
  mcp_rpc "$url" "$auth" '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null
  return 0
}

# check_catalog NOM URL "En-tête" outil1 outil2…
check_catalog() {
  local name="$1" url="$2" auth="$3"
  shift 3
  if ! mcp_open "$url" "$auth"; then
    ko "$name : initialize" "HTTP $MCP_STATUS — $(head -c 300 "$work/body" 2>/dev/null)"
    return 1
  fi
  local tools
  tools="$(mcp_rpc "$url" "$auth" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')"
  printf '%s\n' "$tools" >"$work/tools.${name// /_}"
  local missing=()
  for tool in "$@"; do
    grep -q "\"$tool\"" <<<"$tools" || missing+=("$tool")
  done
  if ((${#missing[@]} == 0)); then
    ok "$name : $# outils attendus présents"
  else
    ko "$name : outils absents" "${missing[*]}"
    return 1
  fi
}

printf 'Suite Convergence — test de fumée (modules : %s)\n' "${COMPOSE_FILE:-compose.yaml}"

# ─── 1. Santé ────────────────────────────────────────────────────────────────────
step "1. Santé des applications"
wait_http "KafkaExplorer" "$EXPLORER/actuator/health"
wait_http "Kex-anHarness" "$AGENT/actuator/health"
wait_http "Autoroutes — backend" "$AR_API/actuator/health"
wait_http "Autoroutes — interface" "$AR_UI/healthz"
wait_http "Autoroutes — MCP" "$AR_MCP/actuator/health"
if has_module docs; then
  wait_http "SpectraLLM — API" "$SPECTRA/actuator/health/readiness"
fi
if has_module monitoring; then
  wait_http "Grafana" "$GRAFANA/api/health"
fi
if has_module auth; then
  wait_http "Keycloak — royaume supervision" "$KEYCLOAK/realms/supervision/.well-known/openid-configuration"
fi

# ─── 2. Catalogues MCP ───────────────────────────────────────────────────────────
step "2. Catalogues MCP"
check_catalog "KafkaExplorer" "$EXPLORER/mcp" "Authorization: Bearer ${EXPLORER_MCP_AUTH_TOKEN:-}" \
  kex_list_topics kex_describe_topic kex_consumer_lag kex_dlq_diagnosis kex_run_audit kex_trace_key
check_catalog "Autoroutes" "$AR_MCP/mcp" "" \
  rechercher_gares consulter_anomalies declarer_anomalies lever_anomalies
if has_module docs; then
  check_catalog "SpectraLLM" "$SPECTRA/mcp" "X-API-Key: ${SPECTRA_KEX_CALLER_KEY:-}" \
    spectra_search spectra_list_documents spectra_preview_document
fi

# Aucun nom d'outil ne doit exister dans deux catalogues : l'agent les voit tous ensemble.
if command -v jq >/dev/null 2>&1; then
  duplicates="$(for f in "$work"/tools.*; do
    grep -E '^(data: )?\{' "$f" | sed 's/^data: //' | jq -r '.result.tools[]?.name' 2>/dev/null
  done | sort | uniq -d)"
  if [[ -z "$duplicates" ]]; then
    ok "aucun nom d'outil en double entre les catalogues"
  else
    ko "noms d'outils en double" "$duplicates"
  fi
else
  printf '  (jq absent : unicité des noms non vérifiée)\n'
fi

# ─── 3. Broker unique ────────────────────────────────────────────────────────────
step "3. KafkaExplorer voit le flux métier"
if mcp_open "$EXPLORER/mcp" "Authorization: Bearer ${EXPLORER_MCP_AUTH_TOKEN:-}"; then
  result="$(mcp_rpc "$EXPLORER/mcp" "Authorization: Bearer ${EXPLORER_MCP_AUTH_TOKEN:-}" \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"kex_describe_topic","arguments":{"topic":"toll-events"}}}')"
  # isError : échec d'exécution de l'outil ; "error": { … } : refus au niveau du protocole.
  if grep -Eq '"isError"[[:space:]]*:[[:space:]]*true|"error"[[:space:]]*:[[:space:]]*\{' <<<"$result"; then
    ko "kex_describe_topic sur toll-events" "$result"
  elif [[ "$result" == *toll-events* ]]; then
    ok "kex_describe_topic répond sur toll-events"
  else
    ko "kex_describe_topic sur toll-events" "réponse inattendue : ${result:0:300}"
  fi
else
  ko "kex_describe_topic sur toll-events" "session MCP impossible (HTTP $MCP_STATUS)"
fi

# ─── 4. Connexions de l'agent ────────────────────────────────────────────────────
step "4. Connexions MCP enregistrées par l'agent"
servers="$(curl -sS --max-time 30 -H "Authorization: Bearer ${KEX_AGENT_API_KEY:-}" "$AGENT/api/agent/mcp/servers" 2>/dev/null)"
expected=(kafka-explorer mcpautoroute)
has_module docs && expected+=(spectrallm)
for connection in "${expected[@]}"; do
  if grep -q "\"$connection\"" <<<"$servers"; then
    ok "connexion $connection déclarée"
  else
    ko "connexion $connection absente de /api/agent/mcp/servers" "${servers:0:300}"
  fi
done

# ─── 5. Proxy TLS ────────────────────────────────────────────────────────────────
step "5. Proxy TLS"
# Certificat de l'autorité locale de Caddy : -k ici, la confiance est l'affaire de l'hôte.
tls=(-k --resolve "explorer.localhost:$PROXY_PORT:$HOST")
wait_http "https://explorer.localhost:$PROXY_PORT" "https://explorer.localhost:$PROXY_PORT/actuator/health" "${tls[@]}"
status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "${tls[@]}" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -H "Authorization: Bearer ${EXPLORER_MCP_AUTH_TOKEN:-}" \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"'"$PROTOCOL_VERSION"'","capabilities":{},"clientInfo":{"name":"convergence-smoke","version":"1"}}}' \
  "https://explorer.localhost:$PROXY_PORT/mcp" 2>/dev/null)" || true
if [[ "$status" == 200 ]]; then
  ok "/mcp de KafkaExplorer via le proxy (HTTP 200)"
else
  ko "/mcp de KafkaExplorer via le proxy" "HTTP $status"
fi

# ─── Bilan ───────────────────────────────────────────────────────────────────────
printf '\nBilan : %d réussi(s), %d échec(s).\n' "$passed" "$failed"
((failed == 0))
