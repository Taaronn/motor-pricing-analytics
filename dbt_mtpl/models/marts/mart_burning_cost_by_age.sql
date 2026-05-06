{{
  config(
    materialized='table',
    tags=['mart', 'pricing']
  )
}}

/*
  mart_burning_cost_by_age — burning cost segmented by driver age band.

  Reads from int_policy_with_exposure (cleaned, capped losses).
  Matches the output of sql/exploration/05_burning_cost_by_age_capped.sql
  but uses the fully cleaned dbt pipeline rather than raw tables directly.

  Numbers will differ slightly from exploration:
    - 676,759 policies (vs 678,013 in raw) — cleaning removed bad DrivAge/Exposure
    - €59.8M raw losses (vs €60.7M) — 30 NULL claims excluded at staging

  PARTITIONING NOTE:
  In a production data warehouse (BigQuery, Snowflake, Redshift), you would
  declare a partition key in the config block, e.g.:
    partition_by = {"field": "data_vintage", "data_type": "date"}
  This physically splits the table storage by date, so a query filtered to
  a single partition reads only that slice of data — O(1/n) scan instead of full table.

  Accretive (incremental) partitioning means each pipeline run appends a new
  partition for the latest period rather than rewriting the whole table. For an
  annual motor book, each accident-year run would add one partition.
  DuckDB is a local analytical engine and doesn't support declarative partitioning,
  so we demonstrate the concept via a `data_vintage` column that would serve as
  the partition key in a cloud warehouse.
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
            ELSE                    '7_75+'
        END AS age_band,
        exposure,
        policy_loss_capped
    FROM base

),

aggregated AS (

    SELECT
        accident_year,
        age_band,
        COUNT(*)                                              AS policy_count,
        ROUND(SUM(exposure), 1)                               AS earned_exposure,
        ROUND(SUM(policy_loss_capped), 0)                     AS total_capped_losses,
        ROUND(SUM(policy_loss_capped) / SUM(exposure), 2)     AS burning_cost_capped,
        -- Relativity is computed against the full portfolio average (OVER () = all rows).
        -- With accident_year in GROUP BY, each cell is one age_band × year combination.
        -- The denominator is still the portfolio-wide BC, so relativities remain
        -- comparable across years and segments.
        ROUND(
            (SUM(policy_loss_capped) / SUM(exposure))
            / SUM(SUM(policy_loss_capped)) OVER () * SUM(SUM(exposure)) OVER ()
        , 3) AS relativity
    FROM banded
    GROUP BY accident_year, age_band

)

SELECT
    accident_year,
    age_band,
    policy_count,
    earned_exposure,
    total_capped_losses,
    burning_cost_capped,
    relativity
FROM aggregated
ORDER BY accident_year, age_band
