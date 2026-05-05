-- Burning cost by BonusMalus band (capped losses)
--
-- BonusMalus (CRM) is the French regulated no-claims discount/surcharge coefficient.
-- Every driver starts at 100. Claim-free years multiply by 0.95; at-fault claims by 1.25.
-- Floor is 50 (reached after ~13 clean years); cap is 350.
--
-- Methodology: individual claims capped at €16,793.70 (P99) before aggregation.
-- This matches 05_burning_cost_by_age_capped.sql — same cleaning rule applied consistently
-- across all segmentation analyses so that results are directly comparable.
--
-- Banding rationale (data-driven, not arbitrary):
--   50 (floor)  — 56.7% of book; long-tenured, never-claimed population. Pulled out
--                 separately because lumping with 51-70 hides a meaningful signal.
--   51-70       — actively earning their way down; 22.3% of book
--   71-100      — new entrants or recently loaded but still discounted; 19.9%
--   101+        — confirmed at-fault claim history; <1% but key pricing story.
--                 101-125/126-150/151+ collapsed: individually below the ~3,000-policy
--                 reliability threshold; combined ~7,794 policies, thin but defensible.

WITH
capped_claims AS (
  -- Cap each individual claim at the P99 threshold to remove catastrophic noise.
  SELECT
    IDpol,
    LEAST(ClaimAmount, 16793.70) AS capped_claim_amount
  FROM raw_sev
),
policy_losses AS (
  -- Aggregate capped claims to one row per policy.
  SELECT
    IDpol,
    SUM(capped_claim_amount) AS policy_total_loss
  FROM capped_claims
  GROUP BY IDpol
),
policy_with_losses AS (
  -- Left-join all policies to losses; COALESCE gives 0 for no-claim policies.
  SELECT
    f.IDpol,
    f.BonusMalus,
    f.Exposure,
    COALESCE(pl.policy_total_loss, 0) AS policy_total_loss
  FROM raw_freq f
  LEFT JOIN policy_losses pl ON f.IDpol = pl.IDpol
)
SELECT
  CASE
    WHEN BonusMalus = 50  THEN '1_floor (BM=50)'
    WHEN BonusMalus <= 70  THEN '2_51-70'
    WHEN BonusMalus <= 100 THEN '3_71-100'
    ELSE                        '4_101+'
  END AS bm_band,
  COUNT(*)                                              AS policy_count,
  ROUND(SUM(Exposure), 1)                               AS earned_exposure,
  ROUND(SUM(policy_total_loss), 0)                      AS total_capped_losses,
  ROUND(SUM(policy_total_loss) / SUM(Exposure), 2)      AS burning_cost_capped,
  -- Index vs book average: makes under/over-pricing visible at a glance.
  -- WHY: raw burning cost alone doesn't tell you how far each segment is from the mean.
  -- An index of 150 means that segment costs 50% more than the average policy.
  ROUND(
    100.0 * (SUM(policy_total_loss) / SUM(Exposure))
    / SUM(SUM(policy_total_loss)) OVER () * SUM(SUM(Exposure)) OVER ()
  , 1) AS burning_cost_index
FROM policy_with_losses
GROUP BY bm_band
ORDER BY bm_band;
