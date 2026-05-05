-- Diagnostic: is the 18-24 burning cost dominated by a single large loss?
-- Show the 10 largest claims belonging to drivers under 25.
-- If we see a single multi-million-euro claim, that's our distortion.

WITH policy_losses AS (
  SELECT 
    IDpol, 
    SUM(ClaimAmount) AS policy_total_loss
  FROM raw_sev
  GROUP BY IDpol
)
SELECT 
  f.IDpol,
  f.DrivAge,
  f.Exposure,
  pl.policy_total_loss
FROM raw_freq f
INNER JOIN policy_losses pl 
  ON f.IDpol = pl.IDpol
WHERE f.DrivAge < 25
ORDER BY pl.policy_total_loss DESC
LIMIT 10;
