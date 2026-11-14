# Matrice de versions

Relevée le 2026-11-14 dans les dépôts sources. La suite épingle des **versions publiées**, jamais `latest` : la surface MCP d'une application (outils, paramètres, plafonds) peut changer d'une publication à l'autre.

## Versions épinglées par la suite

| Application | Image(s) | Tag épinglé | Commit du tag | Variable |
| --- | --- | --- | --- | --- |
| KafkaExplorer | `compagnonsdudev/kafkaexplorer` | `2.4.1` (2026-11-13) | tag `v2.4.1` | `EXPLORER_IMAGE_TAG` |
| Kex-anHarness | `compagnonsdudev/kex-agent-ai` | `0.13.2` (2026-11-14) | tag `v0.13.2` | `KEX_AGENT_IMAGE_TAG` |
| SpectraLLM | `compagnonsdudev/spectrallm`, `compagnonsdudev/spectrallm-frontend` | `0.12.3` (2026-10-19) | tag `v0.12.3` | `SPECTRA_IMAGE_TAG` |
| Autoroutes | `compagnonsdudev/autoroutes:{backend,simulator,mcp-anomalies,frontend}-<tag>` | `0.5.4` (2026-11-14) | tag `v0.5.4` | `AUTOROUTES_TAG` |

Images d'infrastructure :

| Composant | Image | Origine du choix |
| --- | --- | --- |
| Kafka | `apache/kafka:4.4.0` | Autoroutes ; voir ADR 0003 |
| PostgreSQL (Autoroutes) | `postgres:17-alpine` | Autoroutes |
| ChromaDB (SpectraLLM) | `chromadb/chroma:1.5.9` | Pile `spectra-hub` de KafkaExplorer |
| llama.cpp (SpectraLLM) | `ghcr.io/ggml-org/llama.cpp:server-b9828` | Pile `spectra-hub` de KafkaExplorer |
| Reverse proxy | `caddy:2.10-alpine` | Suite |
| Prometheus, Alertmanager, Grafana | `prom/prometheus:v3.15.1`, `prom/alertmanager:v0.34.2`, `grafana/grafana:13.3.0` | Autoroutes |
| Keycloak | `quay.io/keycloak/keycloak:26.8` | Autoroutes |

## Socles techniques (branche `main` de chaque dépôt)

| Application | JDK | Spring Boot | Spring AI | Autres |
| --- | --- | --- | --- | --- |
| KafkaExplorer | 21 | 4.1.2 | 2.0.2 | Flink 2.3.0, clients Kafka 4.3 |
| Kex-anHarness | 21 | 4.1.2 | 2.0.2 | Resilience4j 2.4.0 |
| SpectraLLM | 25 | 4.1.0 | starter MCP serveur (version gérée par le BOM) | React 19 |
| Autoroutes — backend | 25 | 4.1.1 | — | Spring Modulith 2.1.1 |
| Autoroutes — MCP | 25 | 4.1.1 | 2.0.2 | — |

Trois serveurs ou clients MCP sur quatre sont déjà sur Spring AI 2.0.2 : l'alignement par un BOM commun (friction « socles différents ») ne demande que SpectraLLM.

## Écarts entre la spécification et les versions publiées

| Sujet | Spécification (`main`) | Version épinglée | Effet pour la suite |
| --- | --- | --- | --- |
| Base vectorielle SpectraLLM | Qdrant | ChromaDB en 0.12.3 ; Qdrant n'est que sur `main` | La suite utilise ChromaDB jusqu'à la prochaine publication de SpectraLLM |
| Outils MCP SpectraLLM | 6 outils, dont `spectra_read_document` | La sonde de KafkaExplorer n'en attend que 5 en 0.12.3 | `spectra_read_document` à vérifier avant la phase 4 |
| Numérotation SpectraLLM | `backend/pom.xml` en `1.1.0-SNAPSHOT`, CHANGELOG à 1.13.0 | Tags Git et images en `0.12.x` | Trois numérotations à réconcilier ; la suite suit les tags d'image |
| Fonctions Kex de la phase 2 | — | `client-credentials` et `harness_*` présents dès Kex `0.13.0` | MCP d'Autoroutes sous jeton dès que le module `auth` est actif |
| Fonctions de la phase 3 | Kex : `DECLARE_ANOMALY` (PR #223) ; Autoroutes : `etat_gare` (PR #58), provenance des rejets (PR #59) | Présentes dans Kex `0.13.1` et Autoroutes `0.5.3`, mais la boucle n'aboutit qu'avec Kex #225 (`governed-only`, `settle`) et Autoroutes #61 (gare muette, `structuredContent`) | Overlay `compose.actions.yaml` à utiliser avec Kex ≥ `0.13.2` et Autoroutes ≥ `0.5.4` : sous `0.13.1`, `governed-only` est ignoré et `declarer_anomalies` redevient visible du modèle |
| Tags Kex-anHarness | — | Un tag `v9.12.1` coexiste avec `v0.12.1` | Probable coquille à supprimer dans le dépôt Kex |

## Mettre à jour une version

1. Changer la variable dans `.env.example` et dans les valeurs par défaut des fichiers Compose.
2. Si la version touche KafkaExplorer ou Autoroutes, relancer `scripts/sync-upstream.sh` avec le nouveau tag : la suite embarque des fichiers de ces deux dépôts.
3. Lancer `scripts/smoke.sh` : le test vérifie les catalogues MCP, donc une surface d'outils qui change se voit tout de suite.
