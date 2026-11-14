#!/usr/bin/env bash
# Propose puis approuve les trois compétences de la suite dans Kex-anHarness (kex/skills/*.md).
#
# Approuver une compétence change le prompt de toutes les conversations suivantes : lancer ce script
# est le geste de l'administrateur qui les a relues. Idempotent : une compétence déjà présente (même
# titre) est laissée telle quelle.
#
# Usage : scripts/seed-kex.sh            (agent sur http://localhost:8081, clé lue dans .env)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
[[ -f "$root/.env" ]] && { set -a; source "$root/.env"; set +a; }
agent="${AGENT_URL:-http://localhost:${KEX_AGENT_PORT:-8081}}"
: "${KEX_AGENT_API_KEY:?KEX_AGENT_API_KEY absent : lancer scripts/init-env.sh}"

api() { curl -sS --fail-with-body --max-time 30 -H "Authorization: Bearer $KEX_AGENT_API_KEY" -H 'Content-Type: application/json' "$@"; }

existing="$(api "$agent/api/agent/skills")"

# fichier | titre | déclencheurs (JSON)
skills=(
  "triage-dlq.md|Triage des rejets de gare|[\"dlq\",\"rejet\",\"lettre morte\",\"evenements invalides\"]"
  "carte-figee.md|Carte figée ou en retard|[\"carte figee\",\"stale\",\"catching_up\",\"retard de diffusion\"]"
  "anomalie-de-gare.md|Anomalie de gare|[\"anomalie\",\"gare\",\"signaler\"]"
)

for entry in "${skills[@]}"; do
  IFS='|' read -r file title triggers <<<"$entry"
  if jq -e --arg t "$title" 'any(.[]?; .title == $t)' <<<"$existing" >/dev/null 2>&1; then
    echo "déjà présente : $title"
    continue
  fi
  body="$(jq -n --arg title "$title" --rawfile markdown "$root/kex/skills/$file" --argjson triggers "$triggers" \
    '{title:$title, markdown:$markdown, scope:"DOMAIN", triggers:$triggers,
      evidence:"Procédure de la suite Convergence (kex/skills), relue avant approbation."}')"
  id="$(api -X POST --data "$body" "$agent/api/agent/skills" | jq -r '.id')"
  api -X POST --data '{"reason":"Procédure de la suite Convergence, relue par l'"'"'administrateur."}' \
    "$agent/api/agent/skills/$id/approve" >/dev/null
  echo "approuvée : $title ($id)"
done
