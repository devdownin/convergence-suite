# Convergence Suite

Assemblage de quatre applications en une suite cohérente, à partir de leurs images publiées :

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
| `e2e` | `compose.e2e.yaml` | Jeu d'essai de la boucle complète : gare muette au simulateur, modèle factice scripté, seuil de silence court. Exige `auth` et `actions`. Pour `scripts/e2e.sh`, pas pour un usage réel | négligeable |

```bash
# exemple : tout
COMPOSE_FILE=compose.yaml:compose.docs.yaml:compose.monitoring.yaml:compose.auth.yaml
```

### Tester la boucle de bout en bout

```bash
COMPOSE_FILE=compose.yaml:compose.auth.yaml:compose.actions.yaml:compose.e2e.yaml
docker compose up -d && scripts/e2e.sh
```

Le simulateur fait taire Vienne (`GL-BPV-0134`) après 2 minutes. L'agent lance des cycles. Le modèle factice (`e2e/fake-llm.py`) appelle réellement `etat_gare` et ne propose `DECLARE_ANOMALY` que si la gare y est `STALE`. Le script approuve la décision comme un opérateur, puis exige `VERIFIED` : Autoroutes a appliqué la déclaration et `etat_gare` en relit la version. Seul le jugement du modèle est simulé ; jeton Keycloak, politique, approbation, action et vérification sont les vrais. Compter environ 2 minutes après le démarrage, sans clé de fournisseur. La CI le lance à chaque PR (job `e2e`).

Pourquoi des surcouches et non des profils : un module doit aussi modifier des services du cœur (le module `docs` ajoute une connexion MCP à l'agent), ce qu'un profil Compose ne sait pas faire.

Le module `forecast` (TimesFM) arrivera en phase 3 : son service n'a pas d'image publiée.

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
compose.{docs,monitoring,auth,actions,e2e}.yaml   modules
proxy/                       Caddyfile et un fichier de sites par module
observability/prometheus.yml collecte Prometheus de la suite
upstream/                    fichiers repris des dépôts sources à un tag précis (ne pas éditer)
scripts/init-env.sh          crée .env et génère les secrets
scripts/smoke.sh             test de fumée (santé, catalogues MCP, unicité des noms d'outils)
scripts/e2e.sh               boucle complète : gare muette → décision → approbation → action → vérification
e2e/fake-llm.py              modèle factice compatible OpenAI, scripté, pour le module e2e
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
| 3 — Boucle opérationnelle | Métriques péage, prévisions, DLQ, action vérifiée | Code fusionné : 3.2 (Autoroutes #59), 3.3 (Autoroutes #58), 3.4 (Kex #223) ; publiés dans Kex `0.13.1` et Autoroutes `0.5.3`, puis complétés par Kex `0.13.2` et Autoroutes `0.5.4` ; boucle complète prouvée en CI par `scripts/e2e.sh`, après trois correctifs qu'elle a révélés (Kex #225, Autoroutes #61) ; 3.1 : `scripts/seed-forecasts.sh` écrit mais non vérifié (débit et rejets seulement ; entrées/sorties par gare à faire avec l'assistant de la console) |
| 4 — Connaissance et IA locale | Ingestion des specs et audits, DPO, fine-tuning | À venir |
| 5 — Industrialisation | MCP communs, monitoring complet, SSO, liens profonds | À venir |

Décisions : [plan de ports](docs/adr/0001-plan-de-ports.md) · [nommage des outils MCP](docs/adr/0002-nommage-outils-mcp.md) · [broker unique](docs/adr/0003-broker-kafka-unique.md) · [identité](docs/adr/0004-fournisseur-identite.md).
