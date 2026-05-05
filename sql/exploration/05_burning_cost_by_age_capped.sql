-- Burning cost by driver age band, with individual losses capped at €16,794 (P99).
-- This separates attritional pricing signal from large-loss noise.
-- Compare to the uncapped version (02_burning_cost_by_age.sql) to see the impact of capping.

WITH 
capped_claims AS (
  -- Step 1: Cap each individual claim at the P99 threshold.
  -- LEAST(a, b) returns the smaller of two values — a SQL idiom for capping.
  SELECT 
    IDpol,
    LEAST(ClaimAmount, 16793.70) AS capped_claim_amount
  FROM raw_sev
),
policy_losses AS (
  -- Step 2: Aggregate capped claims to one row per policy.
  SELECT 
    IDpol, 
    SUM(capped_claim_amount) AS policy_total_loss
  FROM capped_claims
  GROUP BY IDpol
),
policy_with_losses AS (
  -- Step 3: Left-join exposure with capped losses, COALESCE for no-claim policies.
  SELECT 
    f.IDpol,
    f.DrivAge,
    f.Exposure,
    COALESCE(pl.policy_total_loss, 0) AS policy_total_loss
  FROM raw_freq f
  LEFT JOIN policy_losses pl 
    ON f.IDpol = pl.IDpol
)
SELECT 
  CASE 
    WHEN DrivAge < 25 THEN '18-24'
    WHEN DrivAge < 35 THEN '25-34'
    WHEN DrivAge < 45 THEN '35-44'
    WHEN DrivAge < 55 THEN '45-54'
    WHEN DrivAge < 65 THEN '55-64'
    WHEN DrivAge < 75 THEN '65-74'
    ELSE '75+'
  END AS age_band,
  COUNT(*) AS policy_count,
  SUM(Exposure) AS earned_exposure,
  SUM(policy_total_loss) AS total_capped_losses,
  SUM(policy_total_loss) / SUM(Exposure) AS burning_cost_capped
FROM policy_with_losses
GROUP BY age_band
ORDER BY age_band;
