-- Portfolio-level burning cost
-- Burning cost = total losses / total earned exposure
-- This is the average loss per policy-year, before any expense or profit loading.

WITH 
  losses AS (
    SELECT SUM(ClaimAmount) AS total_losses 
    FROM raw_sev
  ),
  exposure AS (
    SELECT SUM(Exposure) AS total_exposure 
    FROM raw_freq
  )
SELECT 
  losses.total_losses,
  exposure.total_exposure,
  losses.total_losses / exposure.total_exposure AS burning_cost_per_year
FROM losses, exposure;
