# Prédire les annulations de réservations hôtelières

Projet de groupe Simplon (brief SCOPA, octobre 2026), à partir du jeu de données Kaggle *Hotel Booking Demand* (un City Hotel et un Resort Hotel).

**Équipe** : Zohair (exploration, nettoyage, visualisations, règle des 100 réservations), Mouna (base SQL, requêtes métier, compléments de la modélisation), Brice (modélisation).

## La question métier

Les annulations empêchent l'hôtel de prévoir son taux d'occupation et d'organiser ses équipes. On cherche à :

1. comprendre quelles réservations annulent le plus ;
2. prédire, **au moment de la réservation**, le risque d'annulation ;
3. proposer une règle pour choisir les 100 réservations à contacter en priorité sur 1 000 réservations à venir.

## Organisation du dépôt

```
hotel-booking-scopa/
  README.md
  requirements.txt
  data/
    hotel_bookings.csv              données brutes (Kaggle)
    hotel_bookings_clean.csv        données nettoyées (créées par le notebook 01)
  sql/
    create_load.py                  crée la base SQLite data/hotels.db
    nettoyage.sql                   vue bookings = données nettoyées
    requetes_metier.sql             7 requêtes métier commentées (R1 à R7)
  notebooks/
    01_exploration_preparation.ipynb   exploration, qualité, nettoyage, visualisations
    02_modelisation.ipynb              3 modèles comparés, réglages, modèle final
    03_regle_100_reservations.ipynb    règle de priorisation des 100 réservations
  docs/
    dictionnaire_colonnes.pdf       description des colonnes (Mouna)
  livrables/
    synthese_metier.pdf             synthèse 2 pages
    presentation.pdf                support de la soutenance
```

## Comment tout relancer

1. Cloner le dépôt :
   ```
   git clone https://github.com/Zohair69/hotel-booking-scopa.git
   cd hotel-booking-scopa
   ```
2. Installer les librairies :
   ```
   pip install -r requirements.txt
   ```
3. Lancer Jupyter depuis la racine du dépôt :
   ```
   python -m notebook
   ```
4. Exécuter les notebooks **dans l'ordre** (Run > Run All Cells) :
   - `01_exploration_preparation.ipynb` : crée `data/hotel_bookings_clean.csv` ;
   - `02_modelisation.ipynb` ;
   - `03_regle_100_reservations.ipynb`.
5. Partie SQL, depuis la racine du dépôt :
   ```
   python sql/create_load.py
   ```
   Le script crée `data/hotels.db` et affiche le nombre de réservations avant et après nettoyage. Ensuite, ouvrir `data/hotels.db` avec un outil SQLite (par exemple DB Browser for SQLite) et exécuter `sql/requetes_metier.sql`.

## Nettoyage des données

- 119 390 réservations au départ, 87 208 après nettoyage.
- Suppression de 31 994 doublons exacts (aucun identifiant de réservation, et un même doublon pourrait se retrouver à la fois dans le train et dans le test).
- Valeurs manquantes : `children` remplacé par 0, `country` par « Unknown », `agent` par 0, colonne `company` supprimée.
- Lignes incohérentes supprimées : réservations sans aucune personne, 2 prix aberrants (négatif et 5 400), plus de 10 adultes, enfants ou bébés aberrants, segments et canaux « Undefined ».
- Le même nettoyage est refait en SQL (vue `bookings`) et donne aussi 87 208 réservations.

## Résultats principaux

**Constats** (notebook 01) :
- Le City Hotel annule plus que le Resort Hotel (30,09 % contre 23,46 %).
- Plus la réservation est faite tôt, plus elle est annulée.
- Les réservations Non Refund annulent à 94,7 %, mais ne représentent que 1 037 réservations.
- Le segment Online TA est celui qui annule le plus dans les deux hôtels.
- Un client qui a déjà annulé annule beaucoup plus, un client fidèle beaucoup moins.

**Requêtes SQL** (sql/requetes_metier.sql, sur la vue `bookings`) :
- R1, taux d'annulation par hôtel et par année : il augmente chaque année dans les deux hôtels (City Hotel 21,7 % en 2015, 29,2 % en 2016, 34,1 % en 2017 ; Resort Hotel 18,8 %, 21,9 %, 28,3 %). 2015 et 2017 sont des années incomplètes.
- R2, segments de marché : Online TA annule le plus dans les deux hôtels (36,1 % au City Hotel, 33,8 % au Resort Hotel).
- R3, délai de réservation : au City Hotel, le taux passe de 10,5 % (0 à 7 jours) à 44,5 % (181 à 365 jours) ; au Resort Hotel, de 6,0 % à 34,2 %.
- R4, chiffre d'affaires perdu : 35,2 % du chiffre d'affaires réservé est annulé au City Hotel, 31,0 % au Resort Hotel (estimation prix moyen x nuits).
- R5, pays (CTE + RANK) : au Resort Hotel, le Portugal arrive en tête (34,4 % sur 14 217 réservations). Résultat à prendre avec prudence, car le pays est souvent confirmé à l'arrivée du client.
- R6, évolution mois par mois (CTE + LAG) : comparaison de chaque mois avec le mois précédent et avec le même mois de l'année précédente.
- R7, historique du client (sous-requête) : les clients qui ont déjà annulé annulent à 68,7 % au City Hotel et 66,3 % au Resort Hotel, les clients fidèles à 5,1 % et 1,4 %.

**Modèles** (notebook 02, AUC sur le jeu de test) :

| Modèle | AUC avant réglage | Réglage retenu | AUC après réglage |
|---|---|---|---|
| Référence (classe majoritaire) | 0,5 | - | 0,5 |
| Régression logistique | 0,748 | C = 1 | 0,748 |
| Arbre de décision | 0,749 | max_depth = 10 | 0,766 |
| **Forêt aléatoire (retenue)** | 0,776 | max_depth = 20 | **0,796** |

La profondeur 20 de la forêt est confirmée en validation croisée sur l'entraînement (notebook 03, partie 1 bis) : AUC de 0,7902 avec 20, contre 0,7691 avec 10.

Moment de la prédiction : au moment où la réservation est enregistrée. Les colonnes connues seulement après (`reservation_status`, `reservation_status_date`, `assigned_room_type`, `booking_changes`...) ne sont pas utilisées.

**Règle des 100 réservations** (notebook 03) : on écarte les réservations Non Refund (l'hôtel garde déjà l'acompte), puis on contacte les 100 réservations avec la plus forte probabilité d'annulation.
- Sur un lot test de 1 000 réservations : 68 % des 100 réservations choisies ont été annulées, contre 29,0 % en moyenne.
- Sur tout le jeu de test (notebook 02) : les 10 % de réservations les plus risquées sont annulées à 71,6 %, contre 27,5 % en moyenne.
- Variante (notebook 02) : classer par risque x valeur du séjour permet de cibler 49,2 % du chiffre d'affaires annulé, contre 40,5 % avec la probabilité seule.

## Limites

- Le résultat de la règle varie selon le tirage : sur 5 autres tirages de 1 000 réservations, entre 54 % et 69 % des 100 réservations choisies ont été annulées.
- Le modèle classe bien les réservations par risque, mais au seuil de 0,5 il rate beaucoup d'annulations (rappel de 0,258).
- Le découpage entre entraînement et test est aléatoire, pas chronologique.
- On ne sait pas si un appel empêche vraiment l'annulation : il faudrait le tester sur le terrain.
- Les données ne couvrent que deux hôtels, de 2015 à 2017.
