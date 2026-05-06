/*
  SHOWCASE 2: Recursive CTE — bonus-malus improvement path
  =========================================================

  BUSINESS QUESTION
  "How many consecutive claim-free years does it take for a loaded driver
  (BM 130) to reach the statutory floor (BM 50), and what is the expected
  burning cost at each stage of that journey?"

  This models a real pricing question: how long does it take a recently
  loaded policyholder to become profitable, and should we offer retention
  pricing to accelerate that journey?

  WHY THIS TECHNIQUE
  The French bonus-malus system is inherently recursive: each year's BM
  coefficient depends on the previous year's coefficient. A non-recursive
  query cannot model a path-dependent sequence of unknown length — you'd
  need either a hardcoded UNION of N steps (fragile, requires knowing N
  in advance) or an application-layer loop.

  The recursive CTE terminates naturally when the BM reaches the floor
  (50), making the number of steps data-driven: change the starting BM or
  the improvement coefficient and the path length adjusts automatically.

  The LEFT JOIN on the mart is the key observability hook: it attaches the
  current burning cost and relativity for each BM band the driver passes
  through. If a band had no data (e.g. a new product type with no history),
  the year still appears with NULL costs — the gap is visible rather than
  silently omitted, which is the actuarial safety property you want.

  BM improvement rule (simplified French CRM):
    Each claim-free year: new_BM = GREATEST(50, FLOOR(prev_BM * 0.95))
    i.e. a 5% reduction per year, floored at the statutory minimum of 50.
*/

WITH RECURSIVE bm_path AS (

    -- Seed: a loaded driver at BM 130.
    -- BM 130 is plausible after two at-fault claims from the new-driver
    -- entry level of BM 100 (each claim increases BM by ~25%).
    SELECT
        0   AS claim_free_years,
        130 AS bm_value

    UNION ALL

    -- Recursive step: apply 5% annual improvement, floor at 50.
    -- Terminates when bm_value reaches 50 (the GREATEST expression returns 50,
    -- then the WHERE clause bm_value > 50 is FALSE on the next iteration).
    SELECT
        claim_free_years + 1,
        GREATEST(50, CAST(bm_value * 0.95 AS INTEGER))
    FROM bm_path
    WHERE bm_value > 50          -- stop once the floor is reached
      AND claim_free_years < 25  -- safety guard against infinite recursion

),

bm_with_band AS (

    -- Map each BM value on the path to the mart's band labels.
    -- The same bands used in mart_burning_cost_by_bonus_malus.
    SELECT
        claim_free_years,
        bm_value,
        CASE
            WHEN bm_value =  50 THEN '1_floor (BM=50)'
            WHEN bm_value <= 70 THEN '2_51-70'
            WHEN bm_value <= 100 THEN '3_71-100'
            ELSE                     '4_101+'
        END AS bm_band
    FROM bm_path

)

SELECT
    b.claim_free_years,
    b.bm_value,
    b.bm_band,
    -- LEFT JOIN: every year on the path appears even if the mart has no
    -- matching row for that band (NULL burning_cost signals a data gap).
    m.burning_cost_capped,
    m.earned_exposure                                       AS band_exposure_py,
    m.relativity,
    -- Estimated premium saving vs the loaded entry year (claim_free_years = 0)
    ROUND(
        m.burning_cost_capped
        - FIRST_VALUE(m.burning_cost_capped) OVER (ORDER BY b.claim_free_years)
    , 2)                                                    AS bc_vs_entry_eur

FROM bm_with_band b
LEFT JOIN main.mart_burning_cost_by_bonus_malus m
    ON  b.bm_band        = m.bm_band
    AND m.accident_year  = 2019   -- anchor to most recent year's rate basis

ORDER BY b.claim_free_years
;
