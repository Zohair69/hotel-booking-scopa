-- =====================================================================
-- Requêtes métier – Annulations de réservations hôtelières
-- Base : data/hotels.db (SQLite), créée par sql/create_load.py
-- Vue de travail : bookings (données nettoyées, règles dans
-- sql/nettoyage.sql) – 87 208 réservations, identique au nettoyage Python
-- Taux d'annulation = moyenne de is_canceled (0/1) × 100
--
-- Constructions SQL avancées utilisées :
--   - CTE (WITH) ................. R5, R6
--   - Fonction de fenêtrage ...... R5 (RANK), R6 (LAG)
--   - Sous-requête ............... R7
-- =====================================================================


-- ---------------------------------------------------------------------
-- R1. Quel est le taux d'annulation de chaque hôtel, par année ?
-- ---------------------------------------------------------------------
SELECT
    hotel,
    arrival_date_year                         AS annee,
    COUNT(*)                                  AS nb_reservations,
    SUM(is_canceled)                          AS nb_annulations,
    ROUND(100.0 * AVG(is_canceled), 1)        AS taux_annulation_pct
FROM bookings
GROUP BY hotel, arrival_date_year
ORDER BY hotel, annee;

-- Interprétation :
-- Le City Hotel annule davantage que le Resort Hotel : 30,1 % des
-- réservations contre 23,5 % sur la période, soit 6,6 points d'écart.
-- Cet écart se retrouve chaque année : le risque d'annulation est
-- structurellement plus élevé en ville, qui doit être la priorité.
-- Le taux augmente dans les deux hôtels entre 2015 et 2017 (de 21,7 %
-- à 34,1 % en ville, de 18,8 % à 28,3 % au Resort), mais la comparaison
-- est à nuancer : 2015 (juillet-décembre) et 2017 (janvier-août) sont
-- incomplètes et ne couvrent pas les mêmes saisons.
-- À confirmer par une analyse mois par mois (requête R6).


-- ---------------------------------------------------------------------
-- R2. Quels segments de marché annulent le plus, dans chaque hôtel ?
-- ---------------------------------------------------------------------
SELECT
    hotel,
    market_segment,
    COUNT(*)                                  AS nb_reservations,
    ROUND(100.0 * AVG(is_canceled), 1)        AS taux_annulation_pct
FROM bookings
GROUP BY hotel, market_segment
HAVING COUNT(*) >= 100        -- on écarte les segments trop petits pour conclure
ORDER BY hotel, taux_annulation_pct DESC;

-- Interprétation :
-- Les agences en ligne (Online TA) sont le segment le plus exposé dans
-- les deux hôtels : 36,1 % d'annulations au City Hotel et 33,8 % au
-- Resort Hotel. Comme c'est aussi le segment le plus volumineux, il
-- concentre environ 8 annulations sur 10 en ville et 7 sur 10 au Resort.
-- C'est donc le levier prioritaire : conditions d'annulation, demande
-- d'acompte ou confirmation avant l'arrivée sur ce canal.
-- Les groupes annulent nettement plus en ville (33,9 %) qu'au Resort
-- (19,3 %). Les réservations directes et entreprises sont les plus
-- fiables (12 à 17 %).
-- Limites : les segments Complementary et Aviation ont de faibles
-- volumes. La requête ne dit pas pourquoi Online TA annule autant :
-- l'hypothèse d'une annulation gratuite reste à vérifier (deposit_type).


-- ---------------------------------------------------------------------
-- R3. Le délai de réservation (lead_time) influence-t-il l'annulation ?
-- ---------------------------------------------------------------------
SELECT
    hotel,
    CASE
        WHEN lead_time <= 7   THEN '1. 0-7 jours'
        WHEN lead_time <= 30  THEN '2. 8-30 jours'
        WHEN lead_time <= 90  THEN '3. 31-90 jours'
        WHEN lead_time <= 180 THEN '4. 91-180 jours'
        WHEN lead_time <= 365 THEN '5. 181-365 jours'
        ELSE                       '6. plus de 365 jours'
    END                                       AS tranche_lead_time,
    COUNT(*)                                  AS nb_reservations,
    ROUND(100.0 * AVG(is_canceled), 1)        AS taux_annulation_pct
FROM bookings
GROUP BY hotel, tranche_lead_time
ORDER BY hotel, tranche_lead_time;

-- Interprétation :
-- Le risque d'annulation augmente nettement avec le délai de réservation.
-- Au City Hotel, il passe de 10,5 % pour les réservations faites moins
-- d'une semaine avant l'arrivée à 44,5 % entre 6 mois et 1 an à l'avance.
-- Au Resort Hotel, il passe de 6,0 % à 34,2 %. Le saut le plus marqué
-- intervient dès qu'on dépasse 7 jours.
-- Pour la direction : les réservations de dernière minute sont fiables.
-- Les réservations lointaines sont à sécuriser (acompte, reconfirmation
-- quelques semaines avant l'arrivée).
-- Limite : la tranche "plus de 365 jours" a très peu de réservations
-- (375 et 189). Ses taux, dont la baisse au Resort (20,1 %), ne sont
-- pas fiables.
-- Lien avec le modèle : lead_time sera probablement une variable
-- importante pour prédire l'annulation.


-- ---------------------------------------------------------------------
-- R4. Quel chiffre d'affaires est perdu à cause des annulations ?
-- ---------------------------------------------------------------------
SELECT
    hotel,
    CAST(ROUND(SUM(adr * total_nights)) AS INTEGER)                  AS ca_reserve,
    CAST(ROUND(SUM(CASE WHEN is_canceled = 1
                        THEN adr * total_nights ELSE 0 END)) AS INTEGER) AS ca_perdu,
    ROUND(100.0 * SUM(CASE WHEN is_canceled = 1
                           THEN adr * total_nights ELSE 0 END)
                / SUM(adr * total_nights), 1)                        AS part_ca_perdu_pct
FROM bookings
GROUP BY hotel;

-- Interprétation :
-- Les annulations représentent environ 11,5 M€ sur 34,4 M€ réservés,
-- soit un tiers du chiffre d'affaires. Au City Hotel, 35,2 % du CA
-- réservé est perdu, pour 30,1 % des réservations annulées. Au Resort
-- Hotel, 31,0 % du CA est perdu, pour 23,5 % des réservations.
-- Les réservations annulées valent donc plus que la moyenne (séjours
-- plus longs ou plus chers), surtout au Resort, moins touché en nombre
-- mais fortement en valeur.
-- Pour la direction : prioriser les actions selon la valeur à risque,
-- pas seulement selon le nombre de réservations.
-- Limites : estimation brute sur juillet 2015 - août 2017. Elle ne tient
-- pas compte des chambres revendues après annulation ni des acomptes
-- non remboursables conservés : la perte réelle est plus faible.


-- ---------------------------------------------------------------------
-- R5. Quels pays annulent le plus, dans chaque hôtel ?
-- (CTE + fonction de fenêtrage RANK)
-- ---------------------------------------------------------------------
WITH stats_pays AS (
    SELECT
        hotel,
        country,
        COUNT(*)                               AS nb_reservations,
        ROUND(100.0 * AVG(is_canceled), 1)     AS taux_annulation_pct
    FROM bookings
    WHERE country IS NOT NULL
    GROUP BY hotel, country
    HAVING COUNT(*) >= 500
),
classement AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY hotel
                     ORDER BY taux_annulation_pct DESC) AS rang
    FROM stats_pays
)
SELECT *
FROM classement
WHERE rang <= 5
ORDER BY hotel, rang;

-- Interprétation :
-- Au Resort Hotel, le Portugal se détache nettement : 34,4 % d'annulations
-- contre 21,5 % pour l'Espagne, 2e. Avec 14 217 réservations, il pèse
-- environ 4 réservations sur 10 et concentre près de 6 annulations sur 10.
-- Au City Hotel, le classement est plus serré : Chine (53,6 %, mais sur
-- 715 réservations seulement), Brésil (40,1 %), Italie (38,0 %), puis
-- Portugal (37,1 %), premier pays en volume.
-- Pour la direction : la clientèle domestique est le premier enjeu en
-- volume, surtout au Resort.
-- Limite importante : la nationalité est souvent confirmée au check-in.
-- Pour une réservation annulée, le pays peut rester une valeur par
-- défaut (souvent PRT), ce qui gonflerait le taux du Portugal. Résultat à
-- présenter avec prudence : country est une variable risquée pour le
-- modèle.


-- ---------------------------------------------------------------------
-- R6. Comment le taux d'annulation évolue-t-il mois par mois ?
-- (CTE + fonction de fenêtrage LAG)
-- ---------------------------------------------------------------------
WITH mensuel AS (
    SELECT
        hotel,
        SUBSTR(arrival_date, 1, 7)             AS mois,
        COUNT(*)                               AS nb_reservations,
        ROUND(100.0 * AVG(is_canceled), 1)     AS taux_annulation_pct
    FROM bookings
    GROUP BY hotel, mois
)
SELECT
    hotel,
    mois,
    nb_reservations,
    taux_annulation_pct,
    ROUND(taux_annulation_pct
          - LAG(taux_annulation_pct, 1)  OVER (PARTITION BY hotel ORDER BY mois), 1)
                                            AS variation_vs_mois_precedent,
    ROUND(taux_annulation_pct
          - LAG(taux_annulation_pct, 12) OVER (PARTITION BY hotel ORDER BY mois), 1)
                                            AS variation_vs_annee_precedente
FROM mensuel
ORDER BY hotel, mois;

-- Interprétation :
-- La hausse des annulations observée en R1 est confirmée : à partir
-- d'août 2016, chaque mois affiche un taux supérieur au même mois de
-- l'année précédente, dans les deux hôtels (+1,7 à +16,6 points au City
-- Hotel, +2,7 à +10,7 points au Resort). La comparaison au même mois
-- neutralise l'effet des saisons : la dégradation est réelle.
-- Le Resort Hotel est très saisonnier : 10 à 17 % d'annulations en
-- hiver, plus de 30 % en été (37,3 % en août 2017). Les annulations
-- frappent donc la haute saison, quand les chambres valent le plus.
-- Le City Hotel est plus stable (30 à 37 % sur 2016-2017).
-- Pour la direction : renforcer les mesures de sécurisation (acompte,
-- reconfirmation) avant l'été au Resort, toute l'année au City.
-- Limite : juillet 2015 au City Hotel (59,0 % sur 393 réservations) est
-- le premier mois du fichier, probablement incomplet. Il fausse aussi la
-- comparaison de juillet 2016 et n'est pas interprété.


-- ---------------------------------------------------------------------
-- R7. Les clients fidèles annulent-ils moins que les nouveaux ?
-- (sous-requête)
-- ---------------------------------------------------------------------
SELECT
    hotel,
    CASE
        WHEN previous_cancellations > 0          THEN '3. A déjà annulé'
        WHEN is_repeated_guest = 1
          OR previous_bookings_not_canceled > 0  THEN '2. Client fidèle'
        ELSE                                          '1. Nouveau client'
    END                                           AS profil_client,
    COUNT(*)                                      AS nb_reservations,
    ROUND(100.0 * COUNT(*) /
          (SELECT COUNT(*) FROM bookings b2
           WHERE b2.hotel = b.hotel), 1)          AS part_reservations_pct,
    ROUND(100.0 * AVG(is_canceled), 1)            AS taux_annulation_pct
FROM bookings b
GROUP BY hotel, profil_client
ORDER BY hotel, profil_client;

-- Interprétation :
-- L'historique du client est un signal très fort. Les clients qui ont
-- déjà annulé par le passé annulent de nouveau dans 2 cas sur 3 (68,7 %
-- au City Hotel, 66,3 % au Resort), soit 2 à 3 fois plus que les
-- nouveaux clients (29,8 % en ville, 24,2 % au Resort). À l'inverse,
-- les clients fidèles honorent presque
-- toujours leur réservation (5,1 % d'annulations en ville, 1,4 % au
-- Resort).
-- Pour la direction : demander systématiquement un acompte aux clients
-- ayant déjà annulé, et fidéliser les clients réguliers (programme de
-- fidélité, offres de retour).
-- Limite : ces deux profils représentent moins de 8 % des réservations.
-- Les nouveaux clients sans historique représentent 95,4 % des
-- réservations en ville et 92,4 % au Resort : c'est chez eux que se
-- concentre l'essentiel des annulations. L'historique ne suffit donc
-- pas à anticiper la majorité des cas.
