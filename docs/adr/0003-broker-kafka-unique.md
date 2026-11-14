# ADR 0003 — Un broker Kafka unique pour la suite

- **Statut :** accepté
- **Date :** 2026-11-14

## Contexte

Chaque projet embarque son broker :

| Projet | Image | Écoute interne | Écoute hôte |
| --- | --- | --- | --- |
| KafkaExplorer, Kex-anHarness | `apache/kafka:4.3.1` | `kafka:29092` | `localhost:9092` |
| Autoroutes | `apache/kafka:4.4.0` | `kafka:9092` | `localhost:29092` |

Deux brokers séparent la donnée observée (`toll-events`, chez Autoroutes) de l'outil qui l'observe (KafkaExplorer). Les synergies S2, S4 et S5 du plan exigent que KafkaExplorer et Kex voient le topic `toll-events`.

## Décision

La suite démarre un seul broker KRaft, `apache/kafka:4.4.0`, un nœud.

- Écoute interne : `kafka:9092`, utilisée par tous les services de la suite.
- Écoute hôte : `localhost:9092` (`KAFKA_HOST_PORT`), pour les outils lancés depuis l'hôte.
- Topics créés au démarrage, comme le fait Autoroutes : `toll-events` (6 partitions) et `toll-events.rejected` (3 partitions, rétention 7 jours).
- Création automatique des topics laissée active : KafkaExplorer crée ses topics `internal.*` lui-même, et Spring Kafka crée des topics `.DLT` en cas d'échec d'ingestion.

La version 4.4.0 est retenue parce qu'elle est la plus récente des deux ; les clients Kafka 4.3 de KafkaExplorer et de Kex sont compatibles avec un broker 4.4.

## Conséquences

- KafkaExplorer voit `toll-events` et `toll-events.rejected` dès le premier démarrage ; aucune synchronisation entre clusters.
- Les jeux de démonstration de KafkaExplorer (76 topics `demo.*`) ne sont pas chargés : la suite observe le flux métier d'Autoroutes.
- Un seul volume Kafka à sauvegarder (`kafka_data`).
- Le topic `toll-events.rejected` existe déjà côté Autoroutes : la friction « quarantaine invisible » du plan est en partie levée. Reste à vérifier en phase 3 que les rejets y sont effectivement publiés, et pas seulement en PostgreSQL.
