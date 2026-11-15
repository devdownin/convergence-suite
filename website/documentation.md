---
layout: page
title: Documentation
description: "Installer Convergence Suite, choisir ses modules et essayer un scénario de bout en bout."
permalink: /documentation/
---
Convergence Suite assemble Kafka, KafkaExplorer, Kex-anHarness et Autoroutes. SpectraLLM s’ajoute avec le module documentaire. Ce guide décrit l’installation locale de la suite.

<h2 id="démarrage-local">Démarrage local</h2>

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

<details class="demo-log">
  <summary>Voir les quatre étapes dans le journal du test</summary>
  <ol class="demo-steps">
    <li class="demo-step">
      <h3>Détecter la gare muette</h3>
      <p>L’agent interroge Autoroutes. L’état <code>STALE</code> indique que la gare n’émet plus dans le délai attendu.</p>
      <pre><samp>cycle 11 : 1 anomalie(s), 1 décision(s)
ok    cycle 11 : gare GL-BPV-0134 muette détectée</samp></pre>
    </li>
    <li class="demo-step">
      <h3>Attendre l’approbation</h3>
      <p>L’agent propose une déclaration d’anomalie. La décision reste en attente de validation.</p>
      <pre><samp>ok    décision 58e78781-c095-4806-80b3-cdcb082d32b8 en attente de validation humaine</samp></pre>
    </li>
    <li class="demo-step">
      <h3>Appliquer la déclaration</h3>
      <p>Après approbation, Autoroutes renvoie l’identifiant de la gare et l’horodatage de la déclaration.</p>
      <pre><samp>"stationId": "GL-BPV-0134",
"stationName": "Vienne",
"eventTime": "2026-11-15T10:16:41.960708787Z"</samp></pre>
    </li>
    <li class="demo-step">
      <h3>Vérifier le résultat</h3>
      <p>L’agent relit la version de la gare et la compare à l’horodatage attendu. Leur concordance donne le statut <code>VERIFIED</code>.</p>
      <pre><samp>ok    déclaration appliquée par Autoroutes et vérifiée par relecture indépendante
Boucle complète en 118 s.</samp></pre>
    </li>
  </ol>
</details>

[Lire le script de vérification]({{ site.project_repository }}/blob/{{ site.project_branch }}/scripts/e2e.sh)

## Références

- [Démarrage, configuration du proxy et limites]({{ site.project_repository }}#d%C3%A9marrage)
- [Sécurité avant tout partage de la pile]({{ site.project_repository }}#sécurité--à-lire-avant-tout-partage)
- [Décisions d’architecture]({{ site.project_repository }}/tree/{{ site.project_branch }}/docs/adr)
- [Matrice de versions]({{ site.project_repository }}/blob/{{ site.project_branch }}/docs/versions.md)
