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

<h2 id="scenario">Rejouer le scénario de gare muette</h2>

Le scénario se lance sans clé de fournisseur IA. Prérequis : Docker Engine 25+, Docker Compose 2.20+, Bash, curl, OpenSSL et jq.

Depuis la racine du dépôt, initialisez la configuration.

```sh
scripts/init-env.sh
```

Dans le fichier `.env`, remplacez la ligne `COMPOSE_FILE` par celle-ci. Le script relit ce fichier au lancement.

```dotenv
COMPOSE_FILE=compose.yaml:compose.auth.yaml:compose.actions.yaml:compose.e2e.yaml
```

Démarrez la pile et lancez le test.

```sh
docker compose up -d
scripts/e2e.sh
```

Le simulateur cesse d’émettre pour la gare de Vienne (`GL-BPV-0134`). Le modèle factice appelle `etat_gare` et propose une déclaration lorsque l’état est `STALE`. Le script vérifie que la décision est en attente de validation, puis l’approuve comme le ferait un opérateur. Autoroutes enregistre la déclaration et l’agent relit la version de la gare pour confirmer son application.

Le test réussit quand la décision atteint l’état `VERIFIED`. Le journal se termine par « déclaration appliquée par Autoroutes et vérifiée par relecture indépendante ». Dans le [journal de démonstration]({{ site.project_repository }}/actions/runs/43702972938/job/132777968691), cette boucle a pris 118 secondes après le lancement du script. Le premier démarrage de la pile peut prendre davantage de temps selon le téléchargement des images.

Pour arrêter la pile :

```sh
docker compose down
```

[Voir les quatre étapes de la démonstration]({{ '/' | relative_url }}#demonstration) · [Lire le script de vérification]({{ site.project_repository }}/blob/{{ site.project_branch }}/scripts/e2e.sh)

## Références

- [Démarrage, configuration du proxy et limites]({{ site.project_repository }}#d%C3%A9marrage)
- [Sécurité avant tout partage de la pile]({{ site.project_repository }}#sécurité--à-lire-avant-tout-partage)
- [Décisions d’architecture]({{ site.project_repository }}/tree/{{ site.project_branch }}/docs/adr)
- [Matrice de versions]({{ site.project_repository }}/blob/{{ site.project_branch }}/docs/versions.md)
