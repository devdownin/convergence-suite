# Matrice de versions

Relevée le 2026-11-15 dans les dépôts sources. La suite épingle des **versions publiées**, jamais `latest` : la surface MCP d'une application (outils, paramètres, plafonds) peut changer d'une publication à l'autre.

## Versions épinglées par la suite

| Application | Image(s) | Tag épinglé | Commit du tag | Variable |
| --- | --- | --- | --- | --- |
| KafkaExplorer | `compagnonsdudev/kafkaexplorer` | `2.5.0` (2026-11-15) | tag `v2.5.0` | `EXPLORER_IMAGE_TAG` |
| Kex-anHarness | `compagnonsdudev/kex-agent-ai` | `0.13.2` (2026-11-14) | tag `v0.13.2` | `KEX_AGENT_IMAGE_TAG` |
| SpectraLLM | `compagnonsdudev/spectrallm`, `compagnonsdudev/spectrallm-frontend` | `0.2.0` (2026-11-08) | tag `v0.2.0` | `SPECTRA_IMAGE_TAG` |
| Autoroutes | `compagnonsdudev/autoroutes:{backend,simulator,mcp-anomalies,frontend}-<tag>` | `0.6.0` (2026-11-15) | tag `v0.6.0` | `AUTOROUTES_TAG` |

Images d'infrastructure :

| Composant | Image | Origine du choix |
| --- | --- | --- |
| Kafka | `apache/kafka:4.4.0` | Autoroutes ; voir ADR 0003 |
| PostgreSQL (Autoroutes et prévisions) | `postgres:17.12-alpine` | Dernier correctif publié pour PostgreSQL 17 |
| TimesFM et Timestral‑28M (module forecast) | `compagnonsdudev/kafkaexplorer-timesfm:2.5.0`, construite depuis `services/timesfm` au tag `v2.5.0` | Contrat de prévision de KafkaExplorer 2.5.0, poids des deux modèles épinglés |
| Qdrant (SpectraLLM) | `qdrant/qdrant:v1.20.1` | Moteur de SpectraLLM 0.2.0 |
| llama.cpp (SpectraLLM) | `ghcr.io/ggml-org/llama.cpp:server@sha256:89fe93c2ef53ea2d09ca9f53db8878a8f57bb6b143eb63c76a9c218fb583b392` | Image serveur CPU publiée, build b12407 |
| Reverse proxy | `caddy:2.11.9-alpine` | Suite |
| Prometheus, Alertmanager, Grafana | `prom/prometheus:v3.16.0`, `prom/alertmanager:v0.35.0`, `grafana/grafana:13.3.1` | Suite |
| Keycloak | `quay.io/keycloak/keycloak:26.8.2` | Suite |

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
| Base vectorielle SpectraLLM | Qdrant | Qdrant en `0.2.0`, publiée après `0.12.3` | Une instance existante doit transférer l’index ChromaDB vers Qdrant |
| Outils MCP SpectraLLM | 6 outils, dont `spectra_read_document` | Présent dans `0.2.0` | L’agent conserve sa liste d’outils autorisés |
| Numérotation SpectraLLM | `backend/pom.xml` en `1.1.0-SNAPSHOT`, CHANGELOG à 1.13.0 | Tags Git et images en `0.x` | Trois numérotations à réconcilier ; la suite suit les tags d'image |
| Fonctions Kex de la phase 2 | — | `client-credentials` et `harness_*` présents dès Kex `0.13.0` | MCP d'Autoroutes sous jeton dès que le module `auth` est actif |
| Fonctions de la phase 3 | Kex : `DECLARE_ANOMALY` (PR #223) ; Autoroutes : `etat_gare` (PR #58), provenance des rejets (PR #59) | Présentes dans Kex `0.13.1` et Autoroutes `0.5.3`, mais la boucle n'aboutit qu'avec Kex #225 (`governed-only`, `settle`) et Autoroutes #61 (gare muette, `structuredContent`) | Overlay `compose.actions.yaml` à utiliser avec Kex ≥ `0.13.2` et Autoroutes ≥ `0.5.4` : sous `0.13.1`, `governed-only` est ignoré et `declarer_anomalies` redevient visible du modèle |
| Prévisions (3.1) | KafkaExplorer : correctif des offsets (#565) et du taux de rejet (#567) | Inclus dans `2.5.0`, qui intègre également Timestral‑28M | TimesFM fournit les prévisions principales et Timestral évalue le même historique en parallèle |
| Fonctions Kex de l'audit d'intégration | Kex `main` : départ autonome sur instance unique (`schedule.single-instance`), rôle `METRICS` | Absentes de `0.13.2` | Le cœur déclare déjà le départ autonome : ignoré avec un avertissement tant que l'image n'est pas montée. La collecte Prometheus de l'agent attend le rôle `METRICS` |
| Tags Kex-anHarness | — | Un tag `v9.12.1` coexiste avec `v0.12.1` | Probable coquille à supprimer dans le dépôt Kex |

## Mettre à jour une version

1. Changer la variable dans `.env.example` et dans les valeurs par défaut des fichiers Compose.
2. Si la version touche KafkaExplorer ou Autoroutes, relancer `scripts/sync-upstream.sh` avec le nouveau tag : la suite embarque des fichiers de ces deux dépôts.
3. Lancer `scripts/smoke.sh` : le test vérifie les catalogues MCP, donc une surface d'outils qui change se voit tout de suite.
