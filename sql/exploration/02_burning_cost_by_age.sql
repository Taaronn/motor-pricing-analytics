-- Burning cost by driver age band
-- Group drivers into 10-year age bands and compute frequency, severity, and burning cost for each.
-- Hypothesis: young drivers and very old drivers have higher burning costs than middle-aged drivers (the classic "U-shape").

WITH policy_losses AS (
  -- Aggregate claim amounts to one row per policy (policies can have multiple claims)
  SELECT 
    IDpol, 
    SUM(ClaimAmount) AS policy_total_loss
  FROM raw_sev
  GROUP BY IDpol
),
policy_with_losses AS (
  -- LEFT JOIN: keep all policies, attach losses where they exist
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
  SUM(policy_total_loss) AS total_losses,
  SUM(policy_total_loss) / SUM(Exposure) AS burning_cost
FROM policy_with_losses
GROUP BY age_band
ORDER BY age_band;