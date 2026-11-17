# Configuration de l'agent par module

Chaque module de la suite monte son propre répertoire sous `/etc/kex/config/` dans le conteneur de
l'agent, qui les lit tous (`SPRING_CONFIG_ADDITIONAL_LOCATION=optional:file:/etc/kex/config/*/`),
par ordre alphabétique du point de montage : un module plus tardif complète ou remplace une clé
d'un module plus tôt, sans effacer le reste.

| Répertoire | Monté en | Par |
| --- | --- | --- |
| `core/` | `/etc/kex/config/10-core/` | `compose.yaml` |
| `actions/` | `/etc/kex/config/30-actions/` | `compose.actions.yaml` |
| `e2e/` | `/etc/kex/config/90-e2e/` | `compose.e2e.yaml` |

Pourquoi des fichiers et non plus `SPRING_APPLICATION_JSON` : une surcouche Compose remplace une
variable d'environnement en entier. Le JSON du module `actions` devait donc recopier toutes les
règles du cœur, et une règle oubliée rouvrait un outil d'écriture au modèle. Les cartes YAML, elles,
fusionnent clé par clé entre fichiers.

Limite : une **liste** n'est pas fusionnée, elle est remplacée par la dernière qui la déclare.
`kex.mcp.bearer-tokens` reste donc entier dans `compose.auth.yaml`.
