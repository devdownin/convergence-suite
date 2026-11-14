#!/usr/bin/env bash
# Crée les métriques de péage dans KafkaExplorer puis approuve leurs séries pour TimesFM (tâche 3.1).
#
# NON VÉRIFIÉ DE BOUT EN BOUT : écrit contre les contrats lus dans le code de KafkaExplorer 2.4.1
# (POST /api/metrics, GET /api/forecasts/candidates, POST /api/forecasts/series), sans pile en marche.
# Premier lancement : lire la sortie, ouvrir « Metrics Forecast » dans la console.
#
# Prérequis : pile de prévision de KafkaExplorer (historique PostgreSQL + TimesFM, compose/forecasts.yml
# de KafkaExplorer) avec `runtime-approval` actif. Sans eux, l'approbation répond 409 avec sa raison.
#
# Ce que ce script mesure — et ce qu'il ne mesure pas :
#   - débit du topic toll-events (offsets produits) ;
#   - rejets rapportés aux événements (topic de rejets, rapport d'offsets).
# Les entrées/sorties par minute et par gare, et le taux d'ANOMALY_REPORT, demandent du SQL Flink sur le
# contenu des messages : ils ne sont pas devinés ici, à écrire avec l'assistant de la console.
#
# Usage : scripts/seed-forecasts.sh        (Explorer sur http://localhost:8080)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
[[ -f "$root/.env" ]] && { set -a; source "$root/.env"; set +a; }
explorer="${EXPLORER_URL:-http://localhost:${EXPLORER_PORT:-8080}}"
environment="${FORECAST_ENVIRONMENT:-local}"
rejected_topic="${REJECTED_TOPIC:-toll-events.rejected}"
step_ms="${FORECAST_STEP_MS:-60000}"
horizon="${FORECAST_HORIZON:-10}"

api() { curl -sS --fail-with-body --max-time 60 -H 'Content-Type: application/json' "$@"; }

# id | nom | description | paramètres du gabarit (JSON) | gabarit
metrics=(
  "peage-evenements-produits|Péage : événements produits|Offsets produits sur toll-events|{\"measurement\":\"PRODUCED_OFFSETS\",\"topic\":\"toll-events\"}|KAFKA_CLUSTER_COUNT"
  "peage-taux-rejets|Péage : rejets rapportés aux événements|Offsets de ${rejected_topic} rapportés à ceux de toll-events|{\"leftTopic\":\"${rejected_topic}\",\"rightTopic\":\"toll-events\",\"countBy\":\"OFFSETS\",\"operation\":\"RATIO\"}|TOPIC_COUNT_DELTA"
)

existing="$(api "$explorer/api/metrics")"
for entry in "${metrics[@]}"; do
  IFS='|' read -r id name description params template <<<"$entry"
  if jq -e --arg id "$id" 'any(.[]?; .id == $id)' <<<"$existing" >/dev/null 2>&1; then
    echo "métrique déjà présente : $id"
    continue
  fi
  body="$(jq -n --arg id "$id" --arg name "$name" --arg d "$description" --arg t "$template" --argjson p "$params" \
    '{id:$id, name:$name, type:"GAUGE", description:$d, templateType:$t, templateParams:$p}')"
  api -X POST --data "$body" "$explorer/api/metrics" >/dev/null
  echo "métrique créée : $id"
done

# L'historique doit enrôler la métrique avant qu'elle soit candidate : on laisse deux cycles de collecte.
echo "attente de l'enrôlement par l'historique (jusqu'à 3 min)…"
candidates=""
for _ in $(seq 1 18); do
  candidates="$(api "$explorer/api/forecasts/candidates")"
  jq -e 'any(.metrics[]?; (.metricId | startswith("peage-")) and .eligible)' <<<"$candidates" >/dev/null 2>&1 && break
  sleep 10
done

status=0
for entry in "${metrics[@]}"; do
  IFS='|' read -r id _ <<<"$entry"
  candidate="$(jq -c --arg id "$id" '.metrics[]? | select(.metricId == $id)' <<<"$candidates")"
  if [[ -z "$candidate" ]] || [[ "$(jq -r .eligible <<<"$candidate")" != "true" ]]; then
    echo "NON APPROUVÉE : $id — $(jq -r '(.blockers // ["pas candidate : historique non activé ou métrique non enrôlée"]) | join("; ")' <<<"${candidate:-null}")" >&2
    status=1
    continue
  fi
  body="$(jq -n --argjson c "$candidate" --arg env "$environment" --arg cluster "$(jq -r .clusterId <<<"$candidates")" \
    --arg collector "$(jq -r .collectorId <<<"$candidates")" --argjson step "$step_ms" --argjson horizon "$horizon" \
    '{metricId:$c.metricId, definitionVersion:$c.definitionVersion, environment:$env, unit:$c.unit,
      clusterId:$cluster, collectorId:$collector, topics:$c.topics, groups:$c.groups,
      stepMillis:$step, horizon:$horizon, threshold:null, direction:"ABOVE", confirmed:true, seasonality:"NONE"}')"
  if answer="$(api -X POST --data "$body" "$explorer/api/forecasts/series")"; then
    echo "série approuvée : $id → $(jq -r '.seriesId // .' <<<"$answer")"
  else
    echo "NON APPROUVÉE : $id — $answer" >&2
    status=1
  fi
done
exit "$status"
