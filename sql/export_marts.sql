/*
  export_marts.sql — Export all three mart tables to CSV
  =======================================================

  Run with DuckDB CLI from the repo root:
    duckdb mtpl.duckdb < sql/export_marts.sql

  Outputs written to data/exports/ (created automatically by COPY if absent).
  Each file is a self-contained CSV with a header row, comma-delimited.

  Row counts expected after a full three-year load:
    mart_burning_cost_by_age         → 21 rows  (7 age bands × 3 years)
    mart_burning_cost_by_bonus_malus → 12 rows  (4 BM bands × 3 years)
    mart_age_x_vehage_heatmap        → 105 rows (35 cells × 3 years)
*/

-- Ensure target directory exists (DuckDB COPY does not create directories)
-- Run: mkdir -p data/exports   before executing this script if needed.

COPY (
    SELECT *
    FROM   main.mart_burning_cost_by_age
    ORDER BY accident_year, age_band
)
TO 'data/exports/mart_burning_cost_by_age.csv'
(HEADER, DELIMITER ',');

COPY (
    SELECT *
    FROM   main.mart_burning_cost_by_bonus_malus
    ORDER BY accident_year, bm_band
)
TO 'data/exports/mart_burning_cost_by_bonus_malus.csv'
(HEADER, DELIMITER ',');

COPY (
    SELECT *
    FROM   main.mart_age_x_vehage_heatmap
    ORDER BY accident_year, age_band, veh_age_band
)
TO 'data/exports/mart_age_x_vehage_heatmap.csv'
(HEADER, DELIMITER ',');

-- Quick row-count verification (printed to stdout after export)
SELECT
    'mart_burning_cost_by_age'         AS table_name,
    COUNT(*)                           AS row_count,
    COUNT(DISTINCT accident_year)      AS years
FROM main.mart_burning_cost_by_age

UNION ALL

SELECT
    'mart_burning_cost_by_bonus_malus',
    COUNT(*),
    COUNT(DISTINCT accident_year)
FROM main.mart_burning_cost_by_bonus_malus

UNION ALL

SELECT
    'mart_age_x_vehage_heatmap',
    COUNT(*),
    COUNT(DISTINCT accident_year)
FROM main.mart_age_x_vehage_heatmap

ORDER BY table_name;