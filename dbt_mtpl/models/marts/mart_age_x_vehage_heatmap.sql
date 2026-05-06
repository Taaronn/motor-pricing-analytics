{{
  config(
    materialized='table',
    tags=['mart', 'pricing']
  )
}}

/*
  mart_age_x_vehage_heatmap — 2D burning cost: driver age × vehicle age.

  Reads from int_policy_with_exposure (cleaned, capped losses).
  Matches the output of sql/exploration/07_age_x_veh_age_heatmap.sql.

  All 35 cells (7 age bands × 5 vehicle age bands) exceed the 500-policy
  reliability threshold. Two thin cells to note on dashboards:
    - 18-24 × 16+  : ~2,848 policies — treat point estimate with caution
    - 75+   × 16+  : ~2,207 policies — treat point estimate with caution

  PARTITIONING NOTE: see mart_burning_cost_by_age.sql for explanation.
  data_vintage column added as the notional partition key.
*/

WITH base AS (

    SELECT * FROM {{ ref('int_policy_with_exposure') }}

),

banded AS (

    SELECT
        accident_year,
        CASE
            WHEN driv_age < 25 THEN '1_18-24'
            WHEN driv_age < 35 THEN '2_25-34'
            WHEN driv_age < 45 THEN '3_35-44'
            WHEN driv_age < 55 THEN '4_45-54'
            WHEN driv_age < 65 THEN '5_55-64'
            WHEN driv_age < 75 THEN '6_65-74'
            ELSE                   '7_75+'
        END AS age_band,
        CASE
            WHEN veh_age <= 1  THEN '1_0-1'
            WHEN veh_age <= 5  THEN '2_2-5'
            WHEN veh_age <= 10 THEN '3_6-10'
            WHEN veh_age <= 15 THEN '4_11-15'
            ELSE                   '5_16+'
        END AS veh_age_band,
        exposure,
        policy_loss_capped
    FROM base

),

aggregated AS (

    SELECT
        accident_year,
        age_band,
        veh_age_band,
        COUNT(*)                                              AS policy_count,
        ROUND(SUM(exposure), 1)                               AS earned_exposure,
        ROUND(SUM(policy_loss_capped), 0)                     AS total_capped_losses,
        ROUND(SUM(policy_loss_capped) / SUM(exposure), 2)     AS burning_cost_capped,
        ROUND(
            (SUM(policy_loss_capped) / SUM(exposure))
            / SUM(SUM(policy_loss_capped)) OVER () * SUM(SUM(exposure)) OVER ()
        , 3) AS relativity
    FROM banded
    GROUP BY accident_year, age_band, veh_age_band

)

SELECT
    accident_year,
    age_band,
    veh_age_band,
    policy_count,
    earned_exposure,
    total_capped_losses,
    burning_cost_capped,
    relativity
FROM aggregated
ORDER BY accident_year, age_band, veh_age_band
