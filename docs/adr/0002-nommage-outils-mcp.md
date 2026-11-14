# ADR 0002 — Nommage des outils MCP

- **Statut :** accepté ; mise en œuvre en phase 2 (tâche 2.5)
- **Date :** 2026-11-14

## Contexte

Un agent branché sur plusieurs serveurs MCP voit leurs outils dans un seul catalogue. Deux serveurs de la suite utilisent le même préfixe :

- KafkaExplorer publie 27 outils de base, plus 6 de prévision, tous préfixés `kex_` (`kex_list_topics`, `kex_describe_topic`…).
- Le serveur MCP de Kex-anHarness publie 7 outils, eux aussi préfixés `kex_` (`kex_status`, `kex_overview`, `kex_diagnose_topic`…).

Aucun nom n'est en collision exacte aujourd'hui, mais un lecteur, un modèle ou une règle de politique ne peut pas savoir d'où vient un outil `kex_*`. Les règles d'outils de Kex (`kex.agent.tools.rules`) se posent par nom simple ; un préfixe ambigu rend ces règles fragiles.

SpectraLLM (`spectra_`) et Autoroutes (noms français sans préfixe : `rechercher_gares`, `declarer_anomalies`…) sont distincts des deux autres.

## Options

1. Renommer les outils de KafkaExplorer (`explorer_*`) : 33 outils, et le préfixe `kex_` est historique pour ce projet (« Kafka EXplorer »).
2. Renommer les 7 outils du serveur Kex-anHarness (`harness_*`).
3. Ne rien renommer et compter sur le nom qualifié par connexion (`kafka-explorer__kex_list_topics`).

## Décision

Option 2. Les outils du serveur Kex-anHarness deviennent `harness_status`, `harness_overview`, `harness_alerts`, `harness_incidents`, `harness_pending_decisions`, `harness_diagnose_topic`, `harness_diagnose_process`. Les anciens noms restent servis comme alias pendant une version mineure, avec une note de migration dans le CHANGELOG de Kex.

Convention pour la suite :

| Application | Préfixe |
| --- | --- |
| KafkaExplorer | `kex_` |
| Kex-anHarness (serveur) | `harness_` |
| SpectraLLM | `spectra_` |
| Autoroutes | aucun (noms métier français), conservé |

Tout nouvel outil respecte ce préfixe. Un test de la suite (phase 2) échoue si deux catalogues exposent le même nom.

## Conséquences

- Le changement est confiné au dépôt Kex-anHarness (`McpServerCatalog`).
- Les ressources `kex://` du serveur Kex restent inchangées ; leur renommage n'apporte rien tant qu'aucun autre serveur ne publie de ressources sous ce schéma.
- Le serveur MCP de Kex-anHarness n'est pas activé dans la suite en phase 1 : rien ne casse avant la tâche 2.5.
