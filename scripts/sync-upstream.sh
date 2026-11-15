#!/usr/bin/env bash
# Copie dans upstream/ les fichiers de configuration que la suite reprend des dépôts sources,
# à un tag précis. Ces fichiers ne sont pas dans les images publiées :
#   - Autoroutes : règles Prometheus, configuration Alertmanager, tableaux Grafana, royaume Keycloak ;
#   - KafkaExplorer : scripts de démarrage des serveurs llama.cpp de SpectraLLM (pile spectra-hub).
#
# Usage : scripts/sync-upstream.sh            (tags par défaut ci-dessous)
#         AUTOROUTES_REF=v0.6.0 scripts/sync-upstream.sh
#
# Le résultat est versionné : la suite démarre sans accès à GitHub. Relancer ce script à chaque
# changement de version épinglée (docs/versions.md), puis relire le diff avant de committer.
set -euo pipefail

AUTOROUTES_REPO="${AUTOROUTES_REPO:-https://github.com/SteelDevAndroid/autoroutes}"
AUTOROUTES_REF="${AUTOROUTES_REF:-v0.6.0}"
EXPLORER_REPO="${EXPLORER_REPO:-https://github.com/devdownin/Kafkaexplorer}"
EXPLORER_REF="${EXPLORER_REF:-v2.5.0}"

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/upstream"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Clone superficiel d'un seul tag, puis copie des chemins demandés.
fetch() {
  local repo="$1" ref="$2" name="$3"
  shift 3
  echo "→ $name @ $ref"
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$ref" "$repo" "$work/$name"
  rm -rf "${dest:?}/$name"
  mkdir -p "$dest/$name"
  for path in "$@"; do
    mkdir -p "$dest/$name/$(dirname "$path")"
    cp -R "$work/$name/$path" "$dest/$name/$path"
  done
  printf '%s %s %s\n' "$name" "$ref" "$(git -C "$work/$name" rev-parse HEAD)" >>"$work/VERSIONS"
}

fetch "$AUTOROUTES_REPO" "$AUTOROUTES_REF" autoroutes \
  observability/prometheus/alerts.yml \
  observability/alertmanager/alertmanager.yml \
  observability/grafana/provisioning \
  observability/grafana/dashboards \
  auth/realm-supervision.json \
  LICENSE

fetch "$EXPLORER_REPO" "$EXPLORER_REF" kafkaexplorer \
  scripts/spectra-hub/llm-chat.sh \
  scripts/spectra-hub/llm-embed.sh \
  scripts/spectra-hub/fetch-models.sh \
  LICENSE

{
  echo "# Fichiers repris des dépôts sources par scripts/sync-upstream.sh. Ne pas modifier à la main."
  echo "# projet tag commit"
  cat "$work/VERSIONS"
} >"$dest/VERSIONS"

echo "upstream/ à jour :"
cat "$dest/VERSIONS"
