# ADR 0004 — Fournisseur d'identité et authentification MCP

- **Statut :** accepté
- **Date :** 2026-11-14

## Contexte

Quatre mécanismes d'authentification coexistent sur les serveurs MCP de la suite :

| Serveur MCP | Mécanisme | Source |
| --- | --- | --- |
| KafkaExplorer `/mcp` | Bearer statique `EXPLORER_MCP_AUTH_TOKEN` ; TLS exigé par défaut (426) | `McpHttpAuthFilter` |
| SpectraLLM `/mcp` | En-tête `X-API-Key` ; clés par appelant via `SPECTRA_MCP_CALLERS_JSON` | `McpRequiresApiKeyFilter` |
| Autoroutes `/mcp` | Aucun par défaut ; JWT Keycloak de 5 minutes, rôle `ANOMALY_REPORTER`, si `MCP_SECURITY_ENABLED=true` | `docs/mcp-anomalies.md` |
| Kex-anHarness (client) | Jeton statique par préfixe d'URL (`kex.mcp.bearer-tokens`), en-tête configurable | `application.yml` de la v0.12.1 |

Kex ne sait présenter qu'un jeton statique : il ne sait pas obtenir ni renouveler un jeton *client credentials*. Activer la sécurité du MCP d'Autoroutes casserait donc la connexion de l'agent au bout de 5 minutes.

Autoroutes fournit déjà un Keycloak (royaume `supervision`, client confidentiel `agent-anomalies`). Kex-anHarness accepte des jetons OIDC sur son API.

## Décision

Keycloak est le fournisseur d'identité cible de la suite, en reprenant le royaume `supervision` d'Autoroutes.

Trajectoire en trois paliers :

1. **Phase 1 (cette branche).** Un secret par connexion, injecté par le `.env` de la suite. Le MCP d'Autoroutes reste sans sécurité, mais il n'est joignable que depuis le réseau Compose et la boucle locale. Le module `auth` démarre Keycloak, sans l'imposer aux applications.
2. **Phase 2.** Kex apprend le renouvellement *client credentials* par connexion (tâche 2.2). Un client Keycloak dédié `kex-supervisor`, doté de `ANOMALY_REPORTER`, donne à l'agent une source `mcp:` distincte (tâche 2.3). Le MCP d'Autoroutes passe en `MCP_SECURITY_ENABLED=true` (`AUTOROUTES_MCP_SECURITY_ENABLED`), dès qu'une image Kex qui renouvelle les jetons est publiée : le code est dans la PR devdownin/kex-anharness#222, l'interrupteur reste éteint par défaut d'ici là.
3. **Phase 5.** OIDC sur les interfaces de Kex, proxy d'authentification devant KafkaExplorer et SpectraLLM, validation de JWT Keycloak sur le `/mcp` de KafkaExplorer (tâche 5.3).

## Conséquences

- En phase 1, la sécurité repose sur la liaison à `127.0.0.1` et sur l'isolement du réseau Compose. La suite ne doit pas être exposée sur un réseau partagé avant la phase 2.
- Activer `AUTOROUTES_SUPERVISION_PROFILE=auth` en phase 1 rend la carte authentifiée, mais casse `consulter_anomalies` côté agent : le MCP relaie le jeton de l'appelant au backend, et l'agent n'en a pas.
- Les outils d'écriture d'Autoroutes (`declarer_anomalies`, `lever_anomalies`) sont refusés à l'agent en phase 1 par une règle `kex.agent.tools.rules` ; l'exécution après approbation humaine est la tâche 3.4 (phase 3) : elle lie une décision approuvée à l'appel, avec `version_attendue`. D'ici là, la règle de refus reste la seule porte.
