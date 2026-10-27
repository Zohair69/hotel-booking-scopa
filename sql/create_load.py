"""
Création et chargement de la base SQLite à partir de hotel_bookings.csv.

Usage (depuis la racine du dépôt) :
    python sql/create_load.py

Résultat : data/hotels.db avec
    - la table bookings_raw : données brutes, une ligne par réservation
    - la vue bookings       : données nettoyées (règles dans sql/nettoyage.sql),
                              celle sur laquelle on écrit toutes les requêtes
"""

import sqlite3
from pathlib import Path

import pandas as pd

CSV_PATH = Path("data/hotel_bookings.csv")
DB_PATH = Path("data/hotels.db")
NETTOYAGE_PATH = Path("sql/nettoyage.sql")

MONTHS = {
    "January": 1, "February": 2, "March": 3, "April": 4,
    "May": 5, "June": 6, "July": 7, "August": 8,
    "September": 9, "October": 10, "November": 11, "December": 12,
}

# 1. Lecture
df = pd.read_csv(CSV_PATH)  # "NULL" et "NA" sont lus comme valeurs manquantes
assert df.shape == (119390, 32), f"Dimensions inattendues : {df.shape}"

# 2. Colonnes utiles pour le SQL
df.insert(0, "booking_id", range(1, len(df) + 1))
df["arrival_month_num"] = df["arrival_date_month"].map(MONTHS)
df["arrival_date"] = pd.to_datetime(
    dict(
        year=df["arrival_date_year"],
        month=df["arrival_month_num"],
        day=df["arrival_date_day_of_month"],
    )
).dt.strftime("%Y-%m-%d")
df["total_nights"] = df["stays_in_weekend_nights"] + df["stays_in_week_nights"]

# 3. Chargement
DB_PATH.unlink(missing_ok=True)
with sqlite3.connect(DB_PATH) as conn:
    df.to_sql("bookings_raw", conn, index=False)

    # Vue de travail "bookings" = données nettoyées.
    # Les règles de nettoyage sont dans sql/nettoyage.sql :
    # pour en changer une, modifier ce fichier et relancer ce script.
    conn.executescript(NETTOYAGE_PATH.read_text(encoding="utf-8"))

    n_brut = conn.execute("SELECT COUNT(*) FROM bookings_raw").fetchone()[0]
    n_net = conn.execute("SELECT COUNT(*) FROM bookings").fetchone()[0]

print(f"Base créée : {DB_PATH}")
print(f"  Données brutes    : {n_brut} réservations")
print(f"  Après nettoyage   : {n_net} réservations ({n_brut - n_net} retirées)")
print("  -> Comparer ce dernier chiffre avec celui de Zouhair en Python.")
