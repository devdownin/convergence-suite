#!/usr/bin/env bash
# Test de bout en bout de la boucle opérationnelle (compose.e2e.yaml).
#
#   1. le simulateur fait taire une gare ; l'agent lance des cycles de supervision jusqu'à ce que le
#      modèle factice, d'après etat_gare, y voie une gare STALE et propose DECLARE_ANOMALY ;
#   2. la décision attend un humain, avec les arguments proposés (gare, anomalies) ;
#   3. le script l'approuve comme le ferait un opérateur : l'agent appelle declarer_anomalies sur
#      Autoroutes avec son jeton Keycloak, puis relit l'effet par etat_gare ;
#   4. la décision doit finir VERIFIED : la version relue égale l'eventTime de la déclaration.
#
# Usage : scripts/e2e.sh   (lit .env ; COMPOSE_FILE doit contenir auth, actions et e2e)
# Dépendances : bash, curl, jq.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$root/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$root/.env"
  set +a
fi

TIMEOUT="${E2E_TIMEOUT:-600}"
STATION="${E2E_STATION:-GL-BPV-0134}"
AGENT="http://${E2E_HOST:-127.0.0.1}:${KEX_AGENT_PORT:-8081}"
API="$AGENT/api/agent/supervision"
AUTH=(-H "Authorization: Bearer ${KEX_AGENT_API_KEY:-}")

fail() { printf '  \033[31mÉCHEC\033[0m %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "${2:0:1500}"; exit 1; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; }

command -v jq >/dev/null 2>&1 || fail "jq est requis"
modules=":${COMPOSE_FILE:-}:"
for module in auth actions e2e; do
  [[ "$modules" == *":compose.$module.yaml:"* ]] || fail "module $module absent de COMPOSE_FILE ($COMPOSE_FILE)"
done

printf 'Boucle de bout en bout — gare %s\n\n' "$STATION"

deadline=$((SECONDS + TIMEOUT))
until curl -fsS -o /dev/null --max-time 5 "$AGENT/actuator/health" 2>/dev/null; do
  ((SECONDS >= deadline)) && fail "agent indisponible après ${TIMEOUT}s"
  sleep 3
done
ok "agent prêt"

# ─── 1. Détection ────────────────────────────────────────────────────────────────
decision=""
cycles=0
report=""
while [[ -z "$decision" ]]; do
  ((SECONDS >= deadline)) && fail "aucune décision DECLARE_ANOMALY après $cycles cycles (${TIMEOUT}s)" \
    "$(jq -c '[.events[]? | "\(.label) : \(.detail)"]' <<<"${report:-}" 2>/dev/null || echo "${report:-}")"
  report="$(curl -sS --max-time 180 -X POST "${AUTH[@]}" "$API/cycles")"
  cycles=$((cycles + 1))
  printf '  cycle %d : %s\n' "$cycles" \
    "$(jq -r '"\(.anomaliesDetected // 0) anomalie(s), \(.decisionsTaken // 0) décision(s)\(if .failure then " — " + .failure else "" end)"' <<<"$report" 2>/dev/null || echo "${report:0:200}")"
  decision="$(curl -sS --max-time 10 "${AUTH[@]}" "$API/decisions/pending" \
    | jq -c --arg g "$STATION" '[.[] | select(.capability == "DECLARE_ANOMALY" and .actionArguments.gare == $g)][0] // empty')"
  [[ -z "$decision" ]] && sleep 10
done
ok "cycle $cycles : gare $STATION muette détectée"

# ─── 2. Décision gouvernée ───────────────────────────────────────────────────────
id="$(jq -r .id <<<"$decision")"
[[ "$(jq -r .status <<<"$decision")" == PENDING_APPROVAL ]] || fail "la décision n'attend pas d'humain" "$decision"
ok "décision $id en attente de validation humaine"
jq -e '.actionArguments.anomalies | length > 0' <<<"$decision" >/dev/null || fail "anomalies proposées absentes" "$decision"
jq -e '[.observations[]?.value] | any(test("STALE"))' <<<"$decision" >/dev/null \
  || fail "l'observation ne cite pas la mesure STALE" "$decision"
ok "arguments proposés et mesure citée : $(jq -c '.actionArguments' <<<"$decision")"

# ─── 3. Approbation, action et vérification ──────────────────────────────────────
resolved="$(curl -sS --max-time 120 -X POST "${AUTH[@]}" "$API/decisions/$id/approve")"
status="$(jq -r '.status // empty' <<<"$resolved")"
printf '  résultat :\n%s\n' "$(jq -r '.result // empty' <<<"$resolved" | sed 's/^/        /')"
case "$status" in
  VERIFIED) ok "déclaration appliquée par Autoroutes et vérifiée par relecture indépendante" ;;
  "") fail "approbation refusée" "$resolved" ;;
  *) fail "décision terminée en $status au lieu de VERIFIED" "$resolved" ;;
esac

printf '\nBoucle complète en %d s.\n' "$SECONDS"
