## Quand l'utiliser

La carte d'Autoroutes semble figée, ou une gare reste en `CATCHING_UP` ou `STALE` alors que des
événements devraient arriver.

## Procédure

1. Mesurer le retard du consommateur : `kex_consumer_lag` pour le groupe `autoroutes-supervision` sur
   le topic `toll-events`.
2. Vérifier que le flux entre bien : `kex_describe_topic` sur `toll-events` (offsets récents).
3. Lire l'état publié côté carte : `consulter_anomalies` pour la gare concernée, et `rechercher_gares`
   si la gare n'est pas identifiée.
4. Rapprocher le retard mesuré de l'état affiché et conclure.

## Règles

- Un lag absent n'est pas un lag de zéro : une mesure non remontée se dit « non mesurée ».
- Un retard qui diminue d'un relevé à l'autre n'est pas une panne : le dire avant de conclure.
- Cette procédure ne modifie ni la carte ni le consommateur.
