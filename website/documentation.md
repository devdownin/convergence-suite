---
layout: page
title: Documentation
description: "Installer Convergence Suite, choisir ses modules et exécuter le scénario de gare muette."
permalink: /documentation/
---
Convergence Suite assemble Kafka, KafkaExplorer, Kex-anHarness et Autoroutes. SpectraLLM s’ajoute avec le module documentaire. Ce guide décrit l’installation locale de la suite.

## Démarrage local

Prérequis : Docker Engine 25+, Docker Compose 2.20+, Bash, curl et OpenSSL.

```sh
git clone https://github.com/devdownin/convergence-suite.git
cd convergence-suite
scripts/init-env.sh
docker compose pull
docker compose up -d
scripts/smoke.sh
```

Le script d’initialisation génère le fichier `.env` et les secrets locaux. Une clé de fournisseur de modèle peut être renseignée dans ce fichier selon le scénario utilisé. Les interfaces de base sont disponibles sur `localhost:8080` pour KafkaExplorer, `localhost:8081` pour Kex-anHarness et `localhost:8084` pour Autoroutes.

## Modules Compose

| Module | Usage |
| --- | --- |
| `docs` | Recherche documentaire et IA locale avec SpectraLLM |
| `monitoring` | Métriques et tableaux de bord Prometheus et Grafana |
| `auth` | Identité et authentification avec Keycloak |
| `actions` | Approbation humaine et action vérifiée sur Autoroutes. Requiert `auth` |
| `forecast` | Prévisions de métriques avec TimesFM |
| `e2e` | Scénario de test avec simulateur et modèle factice |

Les modules s’activent en ajoutant leurs fichiers à `COMPOSE_FILE` dans `.env`. Consultez le [README du dépôt]({{ site.project_repository }}#modules) pour les versions minimales et les ressources de chaque module.

<h2 id="scenario">Scénario de gare muette</h2>

Depuis la racine du dépôt, lancez le scénario avec les surcouches d’identité, d’action et de simulation.

```sh
export COMPOSE_FILE=compose.yaml:compose.auth.yaml:compose.actions.yaml:compose.e2e.yaml
docker compose up -d
scripts/e2e.sh
```

Le simulateur interrompt les événements d’une gare. Le modèle factice appelle l’outil MCP `etat_gare` et propose une déclaration lorsque l’état est `STALE`. Le script approuve la proposition et attend le résultat `VERIFIED`, qui confirme l’application de la déclaration puis sa relecture.

## Références

- [Démarrage, configuration du proxy et limites]({{ site.project_repository }}#d%C3%A9marrage)
- [Sécurité avant tout partage de la pile]({{ site.project_repository }}#sécurité--à-lire-avant-tout-partage)
- [Décisions d’architecture]({{ site.project_repository }}/tree/{{ site.project_branch }}/docs/adr)
- [Matrice de versions]({{ site.project_repository }}/blob/{{ site.project_branch }}/docs/versions.md)
