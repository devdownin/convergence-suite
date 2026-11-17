#!/usr/bin/env bash
# Crée .env à partir de .env.example et remplit chaque secret vide par une valeur aléatoire.
# Ne touche jamais à un .env existant, sauf pour compléter les secrets encore vides.
#
# Usage : scripts/init-env.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
env_file="$root/.env"

# Variables générées si vides. Les clés de fournisseurs LLM n'en font pas partie : elles viennent
# d'un compte, pas d'un tirage aléatoire.
secrets=(
  EXPLORER_MCP_AUTH_TOKEN
  KEX_AGENT_API_KEY
  KEX_MCP_STORAGE_KEY
  AUTOROUTES_POSTGRES_PASSWORD
  SPECTRA_API_KEY
  SPECTRA_KEX_CALLER_KEY
  GRAFANA_PASSWORD
  KEYCLOAK_ADMIN_PASSWORD
  SUPERVISION_CLIENT_SECRET
  KEYCLOAK_VIEWER_PASSWORD
  KEYCLOAK_ADMIN_USER_PASSWORD
  MCP_AGENT_CLIENT_SECRET
  KEX_SUPERVISOR_CLIENT_SECRET
  FORECAST_POSTGRES_PASSWORD
  TIMESFM_TOKEN
)

if [[ ! -f "$env_file" ]]; then
  cp "$root/.env.example" "$env_file"
  chmod 600 "$env_file"
  echo "Créé : .env"
fi

random() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

filled=0
for name in "${secrets[@]}"; do
  if grep -qE "^${name}=$" "$env_file"; then
    value="$(random)"
    # Valeur hexadécimale : aucun caractère à échapper pour sed.
    sed -i.bak "s/^${name}=\$/${name}=${value}/" "$env_file"
    filled=$((filled + 1))
  elif ! grep -qE "^${name}=" "$env_file"; then
    printf '%s=%s\n' "$name" "$(random)" >>"$env_file"
    filled=$((filled + 1))
  fi
done
rm -f "$env_file.bak"

echo "Secrets générés : $filled. Renseigner ANTHROPIC_API_KEY (ou OpenRouter) pour un agent non dégradé."
