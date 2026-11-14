## Quand l'utiliser

Une gare émet des événements rejetés : le topic `toll-events.rejected` grossit, ou une gare apparaît
en erreur sur la carte sans raison évidente.

## Procédure

1. Mesurer la part de rejets : `kex_dlq_diagnosis` avec le topic source `toll-events` et le topic de
   rejets `toll-events.rejected`. Relever la couverture rendue avec la mesure.
2. Lire quelques messages rejetés, en nombre borné : `kex_preview_messages` sur
   `toll-events.rejected`. Ne jamais citer un contenu au-delà de ce que l'aperçu a rendu.
3. Chercher le runbook applicable avec `spectra_search`, puis ouvrir le document retenu avec
   `spectra_read_document`. Citer son `documentId`.
4. Conclure en séparant ce qui est mesuré de ce qui est supposé.

## Règles

- Une couverture partielle prouve une présence de rejets, jamais leur absence.
- Les chiffres issus du simulateur sont étiquetés « simulés » : ne pas les présenter comme du trafic réel.
- Cette procédure n'écrit rien. Déclarer une anomalie passe par une décision soumise à validation humaine.
