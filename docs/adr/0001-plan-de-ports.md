# ADR 0001 — Plan de ports de la suite

- **Statut :** accepté
- **Date :** 2026-11-14

## Contexte

Les quatre applications publient leurs ports sur la boucle locale de l'hôte. Trois d'entre elles (KafkaExplorer, Kex-anHarness, SpectraLLM) partagent déjà un plan commun, documenté dans `compose/ecosystem.yml` de KafkaExplorer : 8080, 8081, 8088 et 8089. Autoroutes, lui, prend 8080 pour son interface et 8081 pour son backend. Les deux collisions empêchent de démarrer la suite.

Kex-anHarness cible KafkaExplorer par défaut sur `http://localhost:8080` (`KAFKA_EXPLORER_URL`). Déplacer KafkaExplorer ou Kex casserait les valeurs par défaut de deux projets ; déplacer Autoroutes ne coûte que deux variables de son `.env` (`FRONTEND_PORT`, `BACKEND_PORT`).

## Décision

Autoroutes se déplace. Les trois autres gardent le plan déjà partagé.

| Service | Port hôte | Variable de la suite |
| --- | ---: | --- |
| KafkaExplorer (UI, API, `/mcp`) | 8080 | `EXPLORER_PORT` |
| Kex-anHarness (Control Center, `/api/agent`) | 8081 | `KEX_AGENT_PORT` |
| Autoroutes — interface | **8084** | `AUTOROUTES_UI_PORT` |
| Autoroutes — backend et Actuator | **8085** | `AUTOROUTES_API_PORT` |
| SpectraLLM — interface | 8088 | `SPECTRA_UI_PORT` |
| SpectraLLM — API et `/mcp` | 8089 | `SPECTRA_API_PORT` |
| Autoroutes — serveur MCP des anomalies | 8090 | `AUTOROUTES_MCP_PORT` |
| Keycloak (module `auth`) | 8180 | `KEYCLOAK_PORT` |
| Grafana (module `monitoring`) | 3000 | `GRAFANA_PORT` |
| Prometheus (module `monitoring`) | 9090 | `PROMETHEUS_PORT` |
| Alertmanager (module `monitoring`) | 9093 | `ALERTMANAGER_PORT` |
| Kafka depuis l'hôte | 9092 | `KAFKA_HOST_PORT` |
| Reverse proxy TLS | 8443 | `PROXY_HTTPS_PORT` |

Tous les ports sont liés à `127.0.0.1` par défaut (`BIND_ADDR`). Les services internes (PostgreSQL, Qdrant, serveurs llama.cpp) ne sont pas publiés.

## Conséquences

- Les quatre applications démarrent ensemble sans réglage.
- Les liens et documentations d'Autoroutes qui citent `http://localhost:8080` ne valent pas dans la suite : l'interface est sur 8084, ou sur `https://carte.localhost:8443` via le proxy.
- `PUBLIC_URL`, utilisé par le royaume Keycloak d'Autoroutes pour ses URL de redirection, vaut `http://localhost:8084` dans la suite.
