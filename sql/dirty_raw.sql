-- dirty_raw.sql
-- Synthesises dirty versions of raw_freq and raw_sev for dbt cleaning demonstration.
--
-- PURPOSE: Introduces deliberate, documented data quality issues into
-- raw_freq_dirty and raw_sev_dirty so that dbt staging models can demonstrate
-- real-world cleaning logic. The original raw_freq and raw_sev tables are
-- left untouched.
--
-- RUN: duckdb mtpl.duckdb < sql/dirty_raw.sql
-- (from project root, after running sql/load_raw.sql)
--
-- ISSUES INTRODUCED (see data_quality.md for full documentation):
--   raw_freq_dirty:
--     [1] ~50 duplicate rows (same IDpol appearing twice)
--     [2] Mixed-case Region values (lowercase and uppercase variants)
--     [3] Leading/trailing whitespace on Region values
--     [4] Trailing whitespace on VehBrand values
--     [5] Implausible DrivAge values (999 and -5)
--     [6] Implausible Exposure values (-0.5 and 999.0)
--   raw_sev_dirty:
--     [7] ~30 NULL ClaimAmount values

-- ─────────────────────────────────────────────
-- raw_freq_dirty
-- ─────────────────────────────────────────────

CREATE OR REPLACE TABLE raw_freq_dirty AS
  SELECT * FROM raw_freq;

-- [2] Lowercase Region on rows 100–299 (200 rows)
UPDATE raw_freq_dirty
SET Region = lower(Region)
WHERE IDpol IN (
  SELECT IDpol FROM raw_freq ORDER BY IDpol LIMIT 200 OFFSET 100
);

-- [2] Uppercase Region on rows 300–449 (150 rows)
UPDATE raw_freq_dirty
SET Region = upper(Region)
WHERE IDpol IN (
  SELECT IDpol FROM raw_freq ORDER BY IDpol LIMIT 150 OFFSET 300
);

-- [3] Leading and trailing whitespace on Region, rows 450–549 (100 rows)
UPDATE raw_freq_dirty
SET Region = '  ' || Region || '  '
WHERE IDpol IN (
  SELECT IDpol FROM raw_freq ORDER BY IDpol LIMIT 100 OFFSET 450
);

-- [4] Trailing whitespace on VehBrand, rows 550–649 (100 rows)
UPDATE raw_freq_dirty
SET VehBrand = VehBrand || ' '
WHERE IDpol IN (
  SELECT IDpol FROM raw_freq ORDER BY IDpol LIMIT 100 OFFSET 550
);

-- [5a] Implausible DrivAge = 999 on rows 1500–1509 (10 rows)
UPDATE raw_freq_dirty
SET DrivAge = 999
WHERE IDpol IN (
  SELECT IDpol FROM raw_freq ORDER BY IDpol LIMIT 10 OFFSET 1500
);

-- [5b] Implausible DrivAge = -5 on rows 1510–1519 (10 rows)
UPDATE raw_freq_dirty
SET DrivAge = -5
WHERE IDpol IN (
  SELECT IDpol FROM raw_freq ORDER BY IDpol LIMIT 10 OFFSET 1510
);

-- [6a] Negative Exposure = -0.5 on rows 3000–3004 (5 rows)
UPDATE raw_freq_dirty
SET Exposure = -0.5
WHERE IDpol IN (
  SELECT IDpol FROM raw_freq ORDER BY IDpol LIMIT 5 OFFSET 3000
);

-- [6b] Absurd Exposure = 999.0 on rows 3005–3009 (5 rows)
UPDATE raw_freq_dirty
SET Exposure = 999.0
WHERE IDpol IN (
  SELECT IDpol FROM raw_freq ORDER BY IDpol LIMIT 5 OFFSET 3005
);

-- [1] Insert 50 exact duplicate rows (same IDpol, same data).
-- Sourced from raw_freq at a high offset to avoid overlapping with the
-- rows modified above. The staging dedup step must eliminate these.
INSERT INTO raw_freq_dirty
  SELECT * FROM raw_freq ORDER BY IDpol LIMIT 50 OFFSET 300000;

-- ─────────────────────────────────────────────
-- raw_sev_dirty
-- ─────────────────────────────────────────────

CREATE OR REPLACE TABLE raw_sev_dirty AS
  SELECT * FROM raw_sev;

-- [7] NULL ClaimAmount on first 30 rows.
-- ClaimAmount should never be NULL in a severity table — these represent
-- claims that were opened but never valued, a common feed issue.
UPDATE raw_sev_dirty
SET ClaimAmount = NULL
WHERE IDpol IN (
  SELECT IDpol FROM raw_sev ORDER BY IDpol LIMIT 30
);

-- ─────────────────────────────────────────────
-- Verification counts
-- ─────────────────────────────────────────────

SELECT
  'raw_freq'       AS table_name, COUNT(*) AS row_count FROM raw_freq
UNION ALL
SELECT
  'raw_freq_dirty', COUNT(*) FROM raw_freq_dirty
UNION ALL
SELECT
  'raw_sev'       , COUNT(*) FROM raw_sev
UNION ALL
SELECT
  'raw_sev_dirty' , COUNT(*) FROM raw_sev_dirty
ORDER BY table_name;
