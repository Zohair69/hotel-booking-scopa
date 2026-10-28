-- =====================================================================
-- Nettoyage commun – création de la vue de travail "bookings"
-- Exécuté automatiquement par sql/create_load.py
--
-- Règles appliquées (alignées sur le notebook de Zouhair,
-- 01_exploration_preparation.ipynb, résultat attendu : 87 208 réservations) :
--   1. Doublons exacts : on garde une seule ligne             (-31 994)
--   2. Réservations sans aucun client : retirées               (-166)
--   3. adr négatif ou aberrant (5 400) : retirés               (-2)
--   4. Plus de 10 adultes (blocs de chambres) : retirées       (-12)
--   5. 10 enfants ou plus, 9 bébés ou plus : retirées          (-3)
--   6. market_segment ou distribution_channel = 'Undefined'    (-5)
--
-- Pour modifier une règle : changer ce fichier, puis relancer
--   python sql/create_load.py
-- =====================================================================

DROP VIEW IF EXISTS bookings;

CREATE VIEW bookings AS
WITH numerotees AS (
    SELECT *,
           ROW_NUMBER() OVER (
               -- toutes les colonnes d'origine : deux lignes identiques
               -- sur l'ensemble de ces colonnes sont des doublons
               PARTITION BY hotel, is_canceled, lead_time,
                            arrival_date_year, arrival_date_month,
                            arrival_date_week_number, arrival_date_day_of_month,
                            stays_in_weekend_nights, stays_in_week_nights,
                            adults, children, babies, meal, country,
                            market_segment, distribution_channel,
                            is_repeated_guest, previous_cancellations,
                            previous_bookings_not_canceled,
                            reserved_room_type, assigned_room_type,
                            booking_changes, deposit_type, agent, company,
                            days_in_waiting_list, customer_type, adr,
                            required_car_parking_spaces,
                            total_of_special_requests,
                            reservation_status, reservation_status_date
               ORDER BY booking_id
           ) AS rang_doublon
    FROM bookings_raw
)
SELECT *
FROM numerotees
WHERE rang_doublon = 1                                   -- règle 1
  AND (adults + COALESCE(children, 0) + babies) > 0      -- règle 2
  AND adr >= 0 AND adr < 5400                            -- règle 3
  AND adults <= 10                                       -- règle 4
  AND COALESCE(children, 0) < 10 AND babies < 9          -- règle 5
  AND market_segment <> 'Undefined'                      -- règle 6
  AND distribution_channel <> 'Undefined';
  -- COALESCE : children est vide sur quelques lignes, on le compte comme 0
  --
  -- Différences restantes avec le CSV de Zouhair (sans effet sur le
  -- nombre de lignes) : il remplace meal 'Undefined' par 'SC', agent vide
  -- par 0, country vide par 'Unknown', et supprime la colonne company.
  -- Ici les colonnes restent brutes : en tenir compte si une requête
  -- utilise meal (traiter 'Undefined' comme 'SC') ou agent/country.
