-- Understand the claim severity distribution to inform a capping threshold.
-- We use percentiles (P50, P90, P95, P99, P99.5, P99.9) to see where the tail kicks in.

SELECT 
  COUNT(*) AS n_claims,
  AVG(ClaimAmount) AS mean_claim,
  MEDIAN(ClaimAmount) AS p50,
  QUANTILE_CONT(ClaimAmount, 0.90) AS p90,
  QUANTILE_CONT(ClaimAmount, 0.95) AS p95,
  QUANTILE_CONT(ClaimAmount, 0.99) AS p99,
  QUANTILE_CONT(ClaimAmount, 0.995) AS p99_5,
  QUANTILE_CONT(ClaimAmount, 0.999) AS p99_9,
  MAX(ClaimAmount) AS max_claim
FROM raw_sev;
