# Vérifications de la phase 0

Le plan Convergence listait six points que les spécifications ne permettaient pas de trancher (tâche 0.3). Chacun a été vérifié dans le code des dépôts le 2026-11-14.

| # | Question | Réponse | Preuve | Effet sur le plan |
| --- | --- | --- | --- | --- |
| 1 | Kex sait-il renouveler un jeton *client credentials* pour une connexion MCP ? | **Non.** Seuls des jetons statiques par préfixe d'URL, avec en-tête configurable | `kex.mcp.bearer-tokens` dans `application.yml` (v0.12.1) ; aucune occurrence de `client_credentials` dans `src/main` | Tâche 2.2 confirmée, 3 j maintenus |
| 2 | Que contiennent les fichiers Compose d'assemblage existants ? | **Une pile à trois existe déjà** : `compose/ecosystem.yml` de KafkaExplorer assemble KafkaExplorer, SpectraLLM et Kex à partir d'images publiées. Kex fournit `compose/autoroutes.yml` et `compose/spectrallm.yml` | Dépôts KafkaExplorer et Kex-anHarness | Tâche 1.1 allégée : la suite reprend ces fichiers et ajoute Autoroutes |
| 3 | SpectraLLM expose-t-il une inférence compatible OpenAI et des métriques Prometheus ? | **Prometheus : oui** (`/actuator/prometheus`, sans clé). **API OpenAI : non** côté SpectraLLM ; les serveurs llama.cpp internes parlent le protocole OpenAI mais sans authentification | `management.endpoints.web.exposure.include` ; `LlamaCppChatClient` est un client, pas un contrôleur | KafkaExplorer utilise déjà SpectraLLM comme LLM (`CLAUDE_PROVIDER=SPECTRA`) : synergie S7 réalisée pour lui. Pour Kex, voir le point 4 |
| 4 | Un modèle local tient-il le *tool calling* de Kex ? | **Pas sur CPU**, selon les auteurs : un 7B quantifié sur CPU suffit au Process Mining, pas à une boucle d'outils | Commentaire d'en-tête de `compose/ecosystem.yml` (KafkaExplorer) | Kex garde un modèle hébergé. L'essai d'un modèle local pour Kex passe en phase 4, sur GPU uniquement |
| 5 | Le canal entrant de Kex accepte-t-il un webhook Alertmanager ? | **Non, pas directement.** Le canal entrant attend une signature HMAC avec horodatage, qu'Alertmanager ne sait pas produire | `InboundSignature`, `InboundApprovalController` | Tâche 5.2 : ajouter un petit relais qui signe les notifications d'Alertmanager (+1 j) |
| 6 | Le dépôt Autoroutes, sous une autre organisation GitHub, peut-il recevoir les modifications ? | **À confirmer par son propriétaire.** Ses images sont publiées sous le même espace Docker Hub (`compagnonsdudev`) que les trois autres | `compose.hub.yaml`, `docs/docker.md` | Les phases 0 et 1 n'exigent aucune modification d'Autoroutes |

## Autres constats

- **Topic de rejets déjà créé.** Autoroutes crée `toll-events.rejected` (3 partitions, 7 jours) au démarrage. La moitié de la tâche 3.2 existe ; reste à vérifier que les rejets y sont publiés.
- **Deux noms pour la même variable.** Kex écrit `EXPLORER_MCP_REQUIRETLS`, KafkaExplorer `EXPLORER_MCP_REQUIRE_TLS`. La liaison souple de Spring Boot accepte les deux : aucun correctif nécessaire, mais la suite utilise la forme de KafkaExplorer.
- **TLS derrière un proxy.** KafkaExplorer refuse en 426 toute requête MCP non TLS et ne lit pas `X-Forwarded-Proto` par défaut. Derrière le proxy de la suite, il faudrait `SERVER_FORWARD_HEADERS_STRATEGY=framework` ; mais l'agent appelle KafkaExplorer en direct sur le réseau Compose. La suite garde donc `EXPLORER_MCP_REQUIRE_TLS=false`, réseau interne seulement (voir ADR 0004).
- **Outils d'écriture d'Autoroutes.** Kex n'applique aucune règle par défaut à `declarer_anomalies` et `lever_anomalies`. La suite les refuse explicitement en phase 1.
- **Interface SpectraLLM et clé d'API.** Le serveur MCP de SpectraLLM exige `SPECTRA_API_KEY`, mais l'interface web de SpectraLLM n'envoie pas cette clé : avec le module `docs`, l'interface répond 401 sur ses appels d'API. Limite connue, déjà documentée par KafkaExplorer ; à traiter dans SpectraLLM.
- **TimesFM sans image publiée.** Le service de prévision se construit depuis les sources de KafkaExplorer (`services/timesfm`). Le module `forecast` est reporté en phase 3, avec la tâche 3.1.

## Effort recalé

| Phase | Plan initial | Après vérification | Raison |
| --- | ---: | ---: | --- |
| 1 | 8 j | 6 j | Assemblage à trois déjà disponible |
| 5 | 15 j | 16 j | Relais de signature pour Alertmanager |
| **Total** | **60 j** | **59 j** | |
