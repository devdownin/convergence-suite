## Quand l'utiliser

Une gare présente un défaut à signaler sur la carte, ou une anomalie déjà signalée doit être revue ou levée.

## Procédure

1. Lire l'état courant : `consulter_anomalies` pour la gare. Noter `maSource` et `versionAttendue`.
2. Préparer l'état **complet** de la source `maSource` : une déclaration remplace tout ce que cette
   source avait déclaré, elle n'ajoute pas. Reprendre les anomalies déjà déclarées qui restent vraies.
3. Proposer la déclaration (ou la levée) avec sa criticité, ses preuves et la `version_attendue` lue
   à l'étape 1. La proposer, ne pas l'exécuter.
4. Après exécution validée par un humain, relire l'état avec `consulter_anomalies` et vérifier que
   l'`eventId` rendu par Autoroutes correspond à l'état affiché.

## Règles

- `declarer_anomalies` et `lever_anomalies` ne sont jamais appelés directement depuis une conversation :
  ils passent par une décision approuvée dans le Control Center.
- Toujours transmettre `version_attendue` : sans elle, deux sessions du même agent peuvent s'écraser.
- Une action n'est « vérifiée » que lorsque sa trace est retrouvée ; sinon, dire qu'elle ne l'est pas.
