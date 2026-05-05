-- load_raw.sql
-- Bootstrap script: load raw CSVs into DuckDB as source tables.
--
-- WHEN TO RUN: once, immediately after cloning the repo and placing the raw CSVs
-- in data/raw/. Run from the project root with:
--
--   duckdb mtpl.duckdb < sql/load_raw.sql
--
-- This is a temporary bootstrap step. Once the dbt project is in place (Stage 3),
-- dbt staging models take over as the authoritative source of cleaned data.
-- This script only creates the raw source tables that dbt reads from.
--
-- CREATE OR REPLACE TABLE makes the script idempotent — safe to re-run if you
-- need to reload the data from scratch without manually dropping tables first.

CREATE OR REPLACE TABLE raw_freq AS
  SELECT * FROM read_csv_auto('data/raw/freMTPL2freq.csv');

CREATE OR REPLACE TABLE raw_sev AS
  SELECT * FROM read_csv_auto('data/raw/freMTPL2sev.csv');
