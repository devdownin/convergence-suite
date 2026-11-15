# Convergence Suite

[![Site web](https://img.shields.io/badge/Site_web-Convergence_Suite-274DCC)](https://devdownin.github.io/convergence-suite/)
[![Intégration continue](https://github.com/devdownin/convergence-suite/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/devdownin/convergence-suite/actions/workflows/ci.yml)
[![Publication GitHub Pages](https://github.com/devdownin/convergence-suite/actions/workflows/jekyll-gh-pages.yml/badge.svg?branch=main&event=push)](https://github.com/devdownin/convergence-suite/actions/workflows/jekyll-gh-pages.yml)
[![Licence GPL v3](https://img.shields.io/badge/Licence-GPL_v3-326F5C)](LICENSE)

Convergence Suite relie vos flux Kafka à votre activité métier. Explorez les événements, suivez le trafic simulé sur une carte des péages et consultez vos documents avec leurs sources. L’agent rassemble les informations utiles et soumet les actions sensibles à votre validation.

**[Découvrir les usages](https://devdownin.github.io/convergence-suite/#applications)** · **[Essayer en local](#démarrage)**

La suite assemble quatre applications à partir de leurs images publiées.

| Application | Rôle dans la suite | Dépôt |
| --- | --- | --- |
| **KafkaExplorer** | Observer : mesure et preuve sur Kafka (SQL Flink, audit, DLQ, MCP) | [devdownin/Kafkaexplorer](https://github.com/devdownin/Kafkaexplorer) |
| **Kex-anHarness** | Décider : agent pivot, supervision, gouvernance, client des trois MCP | [devdownin/Kex-anHarness](https://github.com/devdownin/Kex-anHarness) |
| **SpectraLLM** | Comprendre : mémoire documentaire, RAG cité, IA locale | [devdownin/SpectraLLM](https://github.com/devdownin/SpectraLLM) |
| **Autoroutes** | Montrer et agir : carte des péages, flux `toll-events`, MCP des anomalies | [SteelDevAndroid/autoroutes](https://github.com/SteelDevAndroid/autoroutes) |

Ce dépôt ne contient aucun code applicatif : des fichiers Compose, un reverse proxy, la configuration partagée, un test de fumée et les décisions d'architecture.

## Démarrage

Prérequis : Docker Engine 25+ et Compose v2.20+, `bash`, `curl`, `openssl`.

```bash
scripts/init-env.sh            # crée .env et génère les secrets
# facultatif : renseigner ANTHROPIC_API_KEY dans .env (sinon l'agent démarre dégradé)
docker compose pull
docker compose up -d
scripts/smoke.sh               # vérifie santé, catalogues MCP, broker unique et proxy
```

| Accès | Direct | Via le proxy TLS |
| --- | --- | --- |
| KafkaExplorer | http://localhost:8080 | https://explorer.localhost:8443 |
| Kex-anHarness (Control Center) | http://localhost:8081 | https://agent.localhost:8443 |
| Autoroutes (carte) | http://localhost:8084 | https://carte.localhost:8443 |
| SpectraLLM (module docs) | http://localhost:8088, API :8089 | https://docs.localhost:8443 |
| Grafana (module monitoring) | http://localhost:3000 | https://grafana.localhost:8443 |
| Keycloak (module auth) | http://localhost:8180 | — |

Le proxy utilise l'autorité de certification locale de Caddy. Pour que le navigateur lui fasse confiance :

```bash
docker compose cp proxy:/data/caddy/pki/authorities/local/root.crt ./convergence-ca.crt
# puis importer convergence-ca.crt dans le magasin de certificats de l'hôte
```

## Modules

Le cœur (`compose.yaml`) démarre Kafka, KafkaExplorer, Kex-anHarness, Autoroutes et le proxy. Les modules s'ajoutent par surcouche, en éditant `COMPOSE_FILE` dans `.env` :

| Module | Fichier | Ajoute | Coût |
| --- | --- | --- | --- |
| `docs` | `compose.docs.yaml` | SpectraLLM, branché sur l'agent (MCP) et sur KafkaExplorer (LLM local) | ~16 Go de RAM, 4,8 Go de modèles au premier démarrage |
| `monitoring` | `compose.monitoring.yaml` | Prometheus, Alertmanager, Grafana d'Autoroutes, étendus à KafkaExplorer et SpectraLLM | ~1 Go |
| `auth` | `compose.auth.yaml` | Keycloak, royaume `supervision` d'Autoroutes | ~1 Go |
| `actions` | `compose.actions.yaml` | Déclaration d'anomalie gouvernée : proposition du modèle, validation humaine, relecture par `etat_gare`. Exige `auth`, Kex ≥ `0.13.2` et Autoroutes ≥ `0.5.4` | négligeable |
| `forecast` | `compose.forecast.yaml` | Historique PostgreSQL, prévisions TimesFM et comparaison avec Timestral‑28M de Mistral. Exige KafkaExplorer `2.5.0` ou une version compatible. | 4 CPU, ~8 Go de RAM ; compilation du service et téléchargement des modèles au premier démarrage |
| `e2e` | `compose.e2e.yaml` | Jeu d'essai de la boucle complète : gare muette au simulateur, modèle factice scripté, seuil de silence court. Exige `auth` et `actions`. Pour `scripts/e2e.sh`, pas pour un usage réel | négligeable |

```bash
# exemple : tout
COMPOSE_FILE=compose.yaml:compose.docs.yaml:compose.monitoring.yaml:compose.auth.yaml
```

Pour une pile `docs` existante, SpectraLLM 0.2.0 ouvre un index Qdrant dans un volume dédié. Les volumes ChromaDB existants exigent un [transfert d’index](https://github.com/devdownin/SpectraLLM/blob/v0.2.0/docs/tech/qdrant-pilot.fr.md). Conserver le volume ChromaDB jusqu’à la vérification du nouvel index.

### Tester la boucle de bout en bout

Après `scripts/init-env.sh`, ajoutez les surcouches à `COMPOSE_FILE` dans `.env`. Le test requiert aussi `jq`.

```dotenv
COMPOSE_FILE=compose.yaml:compose.auth.yaml:compose.actions.yaml:compose.e2e.yaml
```

```bash
docker compose up -d && scripts/e2e.sh
```

Le simulateur fait taire Vienne (`GL-BPV-0134`) après 2 minutes. L'agent lance des cycles. Le modèle factice (`e2e/fake-llm.py`) appelle réellement `etat_gare` et ne propose `DECLARE_ANOMALY` que si la gare y est `STALE`. Le script approuve la décision comme un opérateur, puis exige `VERIFIED` : Autoroutes a appliqué la déclaration et `etat_gare` en relit la version. Seul le jugement du modèle est simulé ; jeton Keycloak, politique, approbation, action et vérification sont les vrais. Compter environ 2 minutes après le démarrage, sans clé de fournisseur. La CI le lance à chaque PR (job `e2e`).

Pourquoi des surcouches et non des profils : un module doit aussi modifier des services du cœur (le module `docs` ajoute une connexion MCP à l'agent), ce qu'un profil Compose ne sait pas faire.

### Prévoir le trafic de péage avec Timestral

#### Tester sur Docker Desktop

Depuis la racine du dépôt, ouvrez PowerShell avec Docker Desktop démarré en mode conteneurs Linux et Docker Compose 2.24.4 ou plus récent. Le test utilise les [poids Timestral‑28M de Mistral](https://huggingface.co/mistralai/Timestral-28M/blob/main/LICENSE) en local, sans clé de fournisseur IA. Le service d’inférence est limité par défaut à 4 CPU et 8 Go de RAM. Prévoyez aussi de la mémoire pour Kafka et les autres services en mode complet.

```powershell
.\scripts\test-forecast.ps1
.\scripts\test-forecast.ps1 -Mode Complet
.\scripts\test-forecast.ps1 -Arreter
```

| Commande | Résultat attendu |
| --- | --- |
| Sans option | Le mode **Rapide** démarre le service d’inférence. TimesFM et Timestral renvoient chacun dix points valides pour la même série synthétique. |
| `-Mode Complet` | KafkaExplorer mesure le débit des événements, le débit des rejets et le taux de rejet à partir du trafic simulé. Pour chacune, le test attend la prévision principale de TimesFM et le résultat de comparaison de Timestral. |
| `-Arreter` | Les conteneurs de test s’arrêtent. L’historique, les autres données de test et les poids sont conservés dans les volumes pour le prochain essai. |

Au premier démarrage, Compose construit le service et télécharge les poids. En mode complet, comptez ensuite environ **11 minutes de collecte** pour atteindre 128 points au pas de 5 s, puis le délai de calcul. Ouvrez l’URL `/metrics` affichée par le lanceur. Dans le panneau **Metrics Forecast**, sélectionnez une série pour consulter la prévision et la comparaison Timestral. Docker choisit un port libre sur `127.0.0.1`, qui peut changer après un arrêt.

Le lanceur utilise un projet Compose propre au dossier de travail et stocke ses secrets dans `.forecast-test.env`, ignoré par Git. Votre `.env` habituel reste intact. Le [workflow Prévisions](https://github.com/devdownin/convergence-suite/actions/workflows/forecast.yml) exécute les deux modes.

#### Dépanner le test

| Symptôme | Vérification |
| --- | --- |
| Docker est introuvable ou les conteneurs Linux sont indisponibles | Démarrez Docker Desktop et vérifiez que `docker info --format '{{.OSType}}'` renvoie `linux`. |
| Compose refuse la surcouche de test | Exécutez `docker compose version` et vérifiez que la version est au moins 2.24.4. |
| Le démarrage bloque pendant le premier essai | Consultez les lignes `forecast-model-prefetch` et `timesfm` affichées en cas d’échec. Elles aident à distinguer le téléchargement des poids du chargement du modèle. |
| Une série du mode complet attend encore | Suivez le nombre de points observés et le motif affiché par série. Une fois l’historique suffisant, le script affiche séparément le résultat de TimesFM et celui de Timestral. |

#### Activer le module dans la pile habituelle

Exécutez `scripts/init-env.sh` depuis Bash pour créer `.env` ou compléter les secrets. Dans `.env`, activez le module avec `COMPOSE_FILE=compose.yaml:compose.forecast.yaml`. Sous Windows, utilisez le séparateur documenté dans [`.env.example`](.env.example). Si votre `.env` épingle déjà des tags, reportez les versions actuelles depuis ce même fichier.

Les [poids Timestral‑28M](https://huggingface.co/mistralai/Timestral-28M/blob/main/LICENSE) sont distribués sous licence Modified MIT. Pour utiliser TimesFM seul, renseigner dans `.env` les trois réglages de désactivation de Timestral indiqués dans `.env.example`.

```bash
docker compose pull --ignore-buildable
docker compose up -d --build
scripts/seed-forecasts.sh --wait
```

Le script crée et approuve les trois séries. Le délai de collecte dépend du pas affiché à l’approbation. À 30 s par point, il faut un peu plus d’une heure pour atteindre les 128 points.

## Sécurité — à lire avant tout partage

Les serveurs MCP communiquent en clair sur le réseau Compose et tous les ports sont liés à `127.0.0.1`. Sans le module `auth`, le MCP d'Autoroutes n'exige aucun jeton ; avec lui, il exige un jeton Keycloak portant `ANOMALY_REPORTER`, que l'agent obtient et renouvelle seul. **Ne pas exposer cette pile sur un réseau partagé sans le module `auth`** ([ADR 0004](docs/adr/0004-fournisseur-identite.md)).

L'agent ne peut pas écrire sur la carte : `declarer_anomalies` et `lever_anomalies` lui sont refusés par règle, jusqu'à l'exécution après approbation humaine (tâche 3.4, phase 3).

Les chiffres d'Autoroutes viennent de son simulateur : ce sont des **données simulées**.

## Limites connues

- Avec le module `docs`, l'interface web de SpectraLLM répond 401 sur ses appels d'API : elle n'envoie pas la clé que son serveur MCP exige. Utiliser l'API ou l'agent.
- La règle d'alerte mémoire d'Autoroutes additionne le tas de toutes les JVM collectées (voir `observability/prometheus.yml`).
- Kex-anHarness n'est pas collecté par Prometheus : son endpoint de métriques exige le bearer de l'API.
- Le module `auth` exige Kex `0.13.0` ou plus (`0.13.2` pour l'overlay `actions`) : une image plus ancienne ne renouvelle pas son jeton et reçoit 401 (`AUTOROUTES_MCP_SECURITY_ENABLED=false` pour y revenir).

## Contenu du dépôt

```
compose.yaml                 cœur de la suite
compose.{docs,monitoring,auth,actions,forecast,e2e}.yaml   modules
proxy/                       Caddyfile et un fichier de sites par module
observability/prometheus.yml collecte Prometheus de la suite
upstream/                    fichiers repris des dépôts sources à un tag précis (ne pas éditer)
scripts/init-env.sh          crée .env et génère les secrets
scripts/smoke.sh             test de fumée (santé, catalogues MCP, unicité des noms d'outils)
scripts/e2e.sh               boucle complète : gare muette → décision → approbation → action → vérification
e2e/fake-llm.py              modèle factice compatible OpenAI, scripté, pour le module e2e
compose.forecast-test.yaml   surcouche isolée du lanceur de test
scripts/test-forecast.ps1    tests rapide et complet sous PowerShell
scripts/seed-forecasts.sh    métriques de péage, approbation des séries, attente des prévisions TimesFM et Timestral
scripts/seed-kex.sh          propose puis approuve les trois compétences de kex/skills
scripts/build-realm.py       génère auth/realm-supervision.json (royaume Autoroutes + client kex-supervisor)
kex/skills/                  procédures de l'agent : triage DLQ, carte figée, anomalie de gare
auth/                        royaume Keycloak généré
scripts/sync-upstream.sh     met à jour upstream/
docs/adr/                    décisions d'architecture
docs/versions.md             matrice de versions
docs/verifications-phase-0.md  points vérifiés dans le code des quatre dépôts
```

## Avancement du plan

| Phase | Contenu | État |
| --- | --- | --- |
| 0 — Cadrage | ADR, matrice de versions, six points vérifiés | Livrée |
| 1 — Assemblage | Compose à modules, broker unique, proxy TLS, test de fumée en CI | Livrée, à valider en CI |
| 2 — Agent unifié et gouvernance | Jetons renouvelés et `harness_*` (code Kex, PR #222), client `kex-supervisor`, caller SpectraLLM, processus et compétences | Livrée ; MCP d'Autoroutes sous jeton avec le module `auth` (Kex `0.13.0`) |
| 3 — Boucle opérationnelle | Métriques péage, prévisions, DLQ, action vérifiée | Code fusionné : 3.2 (Autoroutes #59), 3.3 (Autoroutes #58), 3.4 (Kex #223) ; publiés dans Kex `0.13.1` et Autoroutes `0.5.3`, puis complétés par Kex `0.13.2` et Autoroutes `0.5.4` ; boucle complète prouvée en CI par `scripts/e2e.sh`, après trois correctifs qu'elle a révélés (Kex #225, Autoroutes #61) ; 3.1 : le workflow `Prévisions` vérifie TimesFM et Timestral sur les trois séries de péage avec le lanceur PowerShell |
| 4 — Connaissance et IA locale | Ingestion des specs et audits, DPO, fine-tuning | À venir |
| 5 — Industrialisation | MCP communs, monitoring complet, SSO, liens profonds | À venir |

Décisions : [plan de ports](docs/adr/0001-plan-de-ports.md) · [nommage des outils MCP](docs/adr/0002-nommage-outils-mcp.md) · [broker unique](docs/adr/0003-broker-kafka-unique.md) · [identité](docs/adr/0004-fournisseur-identite.md).
