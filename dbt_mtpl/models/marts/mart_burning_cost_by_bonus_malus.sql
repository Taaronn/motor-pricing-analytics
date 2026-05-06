{{
  config(
    materialized='table',
    tags=['mart', 'pricing']
  )
}}

/*
  mart_burning_cost_by_bonus_malus — burning cost segmented by BonusMalus band.

  Reads from int_policy_with_exposure (cleaned, capped losses).
  Matches the output of sql/exploration/06_burning_cost_by_bonus_malus.sql.

  Banding rationale (data-driven — see exploration diagnostic):
    BM = 50    : 56.7% of book — long-tenured safe drivers at the regulatory floor
    BM 51–70   : 22.3% — actively earning their discount
    BM 71–100  : 19.9% — new entrants or recently loaded but still discounted
    BM 101+    : <1%   — confirmed at-fault claim history; four sub-bands collapsed
                         below the ~3,000-policy statistical reliability threshold

  See sql/exploration/06_burning_cost_by_bonus_malus.sql header for full rationale.

  PARTITIONING NOTE: see mart_burning_cost_by_age.sql for explanation.
  data_vintage column added as the notional partition key.
*/

WITH base AS (

    SELECT * FROM {{ ref('int_policy_with_exposure') }}

),

banded AS (

    SELECT
        CASE
            WHEN bonus_malus = 50  THEN '1_floor (BM=50)'
            WHEN bonus_malus <= 70  THEN '2_51-70'
            WHEN bonus_malus <= 100 THEN '3_71-100'
            ELSE                        '4_101+'
        END AS bm_band,
        exposure,
        policy_loss_capped
    FROM base

),

aggregated AS (

    SELECT
        bm_band,
        COUNT(*)                                              AS policy_count,
        ROUND(SUM(exposure), 1)                               AS earned_exposure,
        ROUND(SUM(policy_loss_capped), 0)                     AS total_capped_losses,
        ROUND(SUM(policy_loss_capped) / SUM(exposure), 2)     AS burning_cost_capped,
        ROUND(
            (SUM(policy_loss_capped) / SUM(exposure))
            / SUM(SUM(policy_loss_capped)) OVER () * SUM(SUM(exposure)) OVER ()
        , 3) AS relativity
    FROM banded
    GROUP BY bm_band

)

SELECT
    bm_band,
    policy_count,
    earned_exposure,
    total_capped_losses,
    burning_cost_capped,
    relativity,
    CAST('2024-01-01' AS DATE) AS data_vintage
FROM aggregated
ORDER BY bm_band
