#!/usr/bin/env bash
# Crée les métriques de péage dans KafkaExplorer puis approuve leurs séries pour TimesFM et Timestral (tâche 3.1).
#
# Prérequis : module forecast (compose.forecast.yaml). Sans lui, la préparation le dit et le script
# s'arrête avant d'écrire quoi que ce soit.
#
# Ce que ce script mesure — et ce qu'il ne mesure pas :
#   - débit du topic toll-events (offsets produits, prévus comme un taux) ;
#   - débit des rejets (même mesure sur le topic de rejets) ;
#   - taux de rejet, rapport des deux calculé par Explorer (TOPIC_COUNT_DELTA compté par offsets).
#     Prévisible à partir de KafkaExplorer #567 ; avant, chacun de ses points est « portée limitée ».
# Les entrées/sorties par gare et le taux d'ANOMALY_REPORT demandent du SQL Flink sur le contenu des
# messages : le gabarit SQL brut n'est pas éligible à la prévision (portée non vérifiable), donc ils
# restent hors de ce script.
#
# Usage : scripts/seed-forecasts.sh          crée et approuve, puis rend la main
#         scripts/seed-forecasts.sh --wait   attend TimesFM et, si activé, Timestral sur chaque série
#
# Relançable : une métrique ou une série déjà présente est gardée telle quelle.
set -euo pipefail

wait_forecast=false
case "${1:-}" in
  "") ;;
  --wait) wait_forecast=true ;;
  *) echo "Usage : $0 [--wait]" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
[[ -f "$root/.env" ]] && { set -a; source "$root/.env"; set +a; }
explorer="${EXPLORER_URL:-http://localhost:${EXPLORER_PORT:-8080}}"
environment="${FORECAST_ENVIRONMENT:-local}"
rejected_topic="${REJECTED_TOPIC:-toll-events.rejected}"
horizon="${FORECAST_HORIZON:-10}"
wait_timeout="${FORECAST_WAIT_TIMEOUT:-3600}"
shadow_enabled="${TIMESTRAL_SHADOW_ENABLED:-true}"

# Une réponse en erreur est recopiée sur stderr : Explorer y dit pourquoi il refuse.
api() {
  local out rc=0
  out="$(curl -sS --fail-with-body --max-time 60 -H 'Content-Type: application/json' "$@")" || rc=$?
  if (( rc != 0 )); then
    echo "requête refusée (${*: -1}) : ${out:-sans corps}" >&2
    return "$rc"
  fi
  printf '%s' "$out"
}

# Explorer démarre après TimesFM : au premier lancement, le temps de télécharger le modèle.
for _ in $(seq 1 60); do
  curl -fsS -o /dev/null --max-time 5 "$explorer/api/metrics" 2>/dev/null && break
  sleep 5
done

# 1. PostgreSQL et TimesFM répondent-ils ? Les autres contrôles (séries, MCP…) ne bloquent pas ici.
readiness="$(api -X POST "$explorer/api/forecasts/preparation/probe")"
blocking="$(jq -r '.checks[]? | select((.id == "postgres" or .id == "timesfm") and .state != "READY")
  | "  \(.state)  \(.id) — \(.detail // "")\(if .action then " → " + .action else "" end)"' <<<"$readiness")"
if [[ -n "$blocking" ]]; then
  echo "pile de prévision indisponible (module forecast actif ?) :" >&2
  echo "$blocking" >&2
  exit 1
fi

# id | nom (format Prometheus, exigé par Explorer) | description | paramètres du gabarit (JSON) | gabarit
metrics=(
  "peage-evenements-produits|peage_evenements_produits|Péage : offsets produits sur toll-events|{\"measurement\":\"PRODUCED_OFFSETS\",\"topic\":\"toll-events\"}|KAFKA_CLUSTER_COUNT"
  "peage-rejets-produits|peage_rejets_produits|Péage : offsets produits sur ${rejected_topic}|{\"measurement\":\"PRODUCED_OFFSETS\",\"topic\":\"${rejected_topic}\"}|KAFKA_CLUSTER_COUNT"
  "peage-taux-rejets|peage_taux_rejets|Péage : offsets de ${rejected_topic} rapportés à ceux de toll-events|{\"leftTopic\":\"${rejected_topic}\",\"rightTopic\":\"toll-events\",\"countBy\":\"OFFSETS\",\"operation\":\"RATIO\"}|TOPIC_COUNT_DELTA"
)
ids=()

existing="$(api "$explorer/api/metrics")"
for entry in "${metrics[@]}"; do
  IFS='|' read -r id name description params template <<<"$entry"
  ids+=("$id")
  if jq -e --arg id "$id" 'any(.[]?; .id == $id)' <<<"$existing" >/dev/null 2>&1; then
    echo "métrique déjà présente : $id"
    continue
  fi
  body="$(jq -n --arg id "$id" --arg name "$name" --arg d "$description" --arg t "$template" --argjson p "$params" \
    '{id:$id, name:$name, type:"GAUGE", description:$d, templateType:$t, templateParams:$p}')"
  api -X POST --data "$body" "$explorer/api/metrics" >/dev/null
  echo "métrique créée : $id"
done

# 2. Une métrique n'est candidate qu'après une collecte sans erreur : on attend qu'elles le soient toutes.
echo "attente de l'éligibilité des métriques (jusqu'à 3 min)…"
ids_json="$(printf '%s\n' "${ids[@]}" | jq -R . | jq -s .)"
candidates=""
for _ in $(seq 1 18); do
  candidates="$(api "$explorer/api/forecasts/candidates")"
  jq -e --argjson ids "$ids_json" \
    '[.metrics[]? | select(.metricId as $m | $ids | index($m)) | select(.eligible)] | length == ($ids | length)' \
    <<<"$candidates" >/dev/null 2>&1 && break
  sleep 10
done
if [[ "$(jq -r '.applyUnavailable // empty' <<<"$candidates")" != "" ]]; then
  echo "approbation impossible : $(jq -r .applyUnavailable <<<"$candidates")" >&2
  exit 1
fi

status=0
approved=()
current="$(api "$explorer/api/forecasts")"
for id in "${ids[@]}"; do
  existing_series="$(jq -r --arg id "$id" --arg env "$environment" \
    'first(.series[]? | select(.metricId == $id and .environment == $env) | .seriesId) // empty' <<<"$current")"
  if [[ -n "$existing_series" ]]; then
    echo "série déjà approuvée : $id → $existing_series"
    approved+=("$id|$existing_series")
    continue
  fi
  candidate="$(jq -c --arg id "$id" '.metrics[]? | select(.metricId == $id)' <<<"$candidates")"
  if [[ -z "$candidate" ]] || [[ "$(jq -r .eligible <<<"$candidate")" != "true" ]]; then
    echo "NON APPROUVÉE : $id — $(jq -r '(.blockers // ["pas candidate : historique non activé ou métrique non enrôlée"]) | join("; ")' <<<"${candidate:-null}")" >&2
    status=1
    continue
  fi
  # Le pas proposé par Explorer tient deux collectes par seau : plus court, la préparation refuserait la
  # série pour des trous que personne n'a choisis.
  step_ms="${FORECAST_STEP_MS:-$(jq -r .suggestedStepMillis <<<"$candidate")}"
  body="$(jq -n --argjson c "$candidate" --arg env "$environment" --arg cluster "$(jq -r .clusterId <<<"$candidates")" \
    --arg collector "$(jq -r .collectorId <<<"$candidates")" --argjson step "$step_ms" --argjson horizon "$horizon" \
    '{metricId:$c.metricId, definitionVersion:$c.definitionVersion, environment:$env, unit:$c.unit,
      clusterId:$cluster, collectorId:$collector, topics:$c.topics, groups:$c.groups,
      stepMillis:$step, horizon:$horizon, threshold:null, direction:"ABOVE", confirmed:true, seasonality:"NONE"}')"
  if answer="$(api -X POST --data "$body" "$explorer/api/forecasts/series")"; then
    series_id="$(jq -r '.seriesId' <<<"$answer")"
    echo "série approuvée : $id → $series_id (pas ${step_ms} ms)"
    approved+=("$id|$series_id")
  else
    echo "NON APPROUVÉE : $id — $answer" >&2
    status=1
  fi
done

if ! $wait_forecast || [[ $status -ne 0 ]]; then
  exit "$status"
fi

# 3. Une prévision existe quand TimesFM a répondu sur la série : pas avant 128 points d'historique.
# Toutes les séries sont suivies ensemble, et l'échec les nomme toutes, pas seulement la première.
deadline=$(( $(date +%s) + wait_timeout ))
declare -A primary_ready finished last
while :; do
  pending=0
  for item in "${approved[@]}"; do
    IFS='|' read -r id series_id <<<"$item"
    [[ -n "${finished[$id]:-}" ]] && continue
    if [[ -z "${primary_ready[$id]:-}" ]]; then
      view="$(api "$explorer/api/forecasts/$series_id" 2>/dev/null || true)"
      if jq -e '.result.strategy == "TIMESFM" and ((.result.forecast.points // []) | length > 0)' <<<"$view" >/dev/null 2>&1; then
        echo "prévision TimesFM : $id — $(jq -r '"\(.result.forecast.points | length) points, état \(.result.state), modèle \(.result.forecast.modelId)"' <<<"$view")"
        primary_ready[$id]=1
      fi
    fi
    if [[ -z "${primary_ready[$id]:-}" ]]; then
      progress="$(api "$explorer/api/forecasts/$series_id/progress" 2>&1 || true)"
      line="$(jq -r '"\(.state) \(.observedPoints // 0)/\(.requiredPoints) — \(.reason // "")"' <<<"$progress" 2>/dev/null || echo "$progress")"
    elif [[ "${shadow_enabled,,}" == "true" ]]; then
      shadow="$(api "$explorer/api/forecasts/$series_id/shadow" 2>&1 || true)"
      if jq -e '.state == "READY" and .modelId == "mistralai/Timestral-28M" and (.revision | type == "string")' <<<"$shadow" >/dev/null 2>&1; then
        echo "prévision de comparaison Timestral : $id"
        finished[$id]=1
        continue
      fi
      line="$(jq -r '"Timestral \(.state) — \(.reason // "")"' <<<"$shadow" 2>/dev/null || echo "$shadow")"
      line="${line:-en attente de Timestral}"
    else
      finished[$id]=1
      continue
    fi
    pending=$((pending + 1))
    if [[ "$line" != "${last[$id]:-}" ]]; then echo "  $id : $line"; last[$id]="$line"; fi
  done
  (( pending == 0 )) && exit 0
  if (( $(date +%s) > deadline )); then
    for item in "${approved[@]}"; do
      IFS='|' read -r id _ <<<"$item"
      [[ -z "${finished[$id]:-}" ]] && echo "ÉCHEC : prévisions attendues incomplètes pour $id après ${wait_timeout} s — ${last[$id]:-aucun état}" >&2
    done
    exit 1
  fi
  sleep 20
done
