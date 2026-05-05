-- 2D burning cost heatmap: driver age band × vehicle age band (capped losses)
--
-- Business question: does the driver age effect interact with vehicle age?
-- A young driver in a new car might look different from a young driver in a 10-year-old car.
-- Two-dimensional segmentation surfaces interaction effects that 1D slices miss.
--
-- Methodology: individual claims capped at €16,793.70 (P99), matching
-- 05_burning_cost_by_age_capped.sql and 06_burning_cost_by_bonus_malus.sql.
-- Using the same cap consistently means burning cost figures are directly comparable
-- across all segmentation files in this folder.
--
-- VehAge banding (data-driven):
--   0-1   : new/nearly-new vehicles
--   2-5   : recent, still in high-depreciation phase
--   6-10  : mid-age fleet (largest cluster by policy count)
--   11-15 : ageing fleet
--   16+   : older vehicles — potentially higher mechanical risk, lower insured value
--
-- Cell count check (pre-run, see 07 diagnostic):
--   All 35 cells (7 age bands × 5 veh age bands) are above the 500-policy threshold.
--   Relatively thin cells to treat with caution on the dashboard:
--     18-24 × 16+   : 2,848 policies  <- note when presenting
--     75+   × 16+   : 2,207 policies  <- note when presenting
--     18-24 × 0-1   : 3,825 policies  <- borderline
--   These cells will produce noisier burning cost estimates. Confidence intervals
--   would widen materially here; avoid over-indexing on point estimates.

WITH
capped_claims AS (
  SELECT
    IDpol,
    LEAST(ClaimAmount, 16793.70) AS capped_claim_amount
  FROM raw_sev
),
policy_losses AS (
  SELECT
    IDpol,
    SUM(capped_claim_amount) AS policy_total_loss
  FROM capped_claims
  GROUP BY IDpol
),
policy_with_losses AS (
  SELECT
    f.IDpol,
    f.DrivAge,
    f.VehAge,
    f.Exposure,
    COALESCE(pl.policy_total_loss, 0) AS policy_total_loss
  FROM raw_freq f
  LEFT JOIN policy_losses pl ON f.IDpol = pl.IDpol
),
banded AS (
  SELECT
    CASE
      WHEN DrivAge < 25 THEN '1_18-24'
      WHEN DrivAge < 35 THEN '2_25-34'
      WHEN DrivAge < 45 THEN '3_35-44'
      WHEN DrivAge < 55 THEN '4_45-54'
      WHEN DrivAge < 65 THEN '5_55-64'
      WHEN DrivAge < 75 THEN '6_65-74'
      ELSE                   '7_75+'
    END AS age_band,
    CASE
      WHEN VehAge <= 1  THEN '1_0-1'
      WHEN VehAge <= 5  THEN '2_2-5'
      WHEN VehAge <= 10 THEN '3_6-10'
      WHEN VehAge <= 15 THEN '4_11-15'
      ELSE                   '5_16+'
    END AS veh_age_band,
    Exposure,
    policy_total_loss
  FROM policy_with_losses
)
SELECT
  age_band,
  veh_age_band,
  COUNT(*)                                              AS policy_count,
  ROUND(SUM(Exposure), 1)                               AS earned_exposure,
  ROUND(SUM(policy_total_loss), 0)                      AS total_capped_losses,
  ROUND(SUM(policy_total_loss) / SUM(Exposure), 2)      AS burning_cost_capped,
  -- Relativities vs overall mean: same logic as 06_burning_cost_by_bonus_malus.sql.
  -- A relativity of 200 means that cell costs twice the average policy.
  -- WHY this matters: relativities are how actuaries communicate pricing adequacy.
  -- The raw £ number depends on the portfolio mix; relativities strip that out.
  ROUND(
    100.0 * (SUM(policy_total_loss) / SUM(Exposure))
    / SUM(SUM(policy_total_loss)) OVER () * SUM(SUM(Exposure)) OVER ()
  , 1) AS relativity
FROM banded
GROUP BY age_band, veh_age_band
ORDER BY age_band, veh_age_band;
