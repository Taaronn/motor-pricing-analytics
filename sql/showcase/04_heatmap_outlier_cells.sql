/*
  SHOWCASE 4: Correlated subquery — heatmap outlier cell identification
  ======================================================================

  BUSINESS QUESTION
  "Which (age × vehicle age) cells have a burning cost more than 150% of
  their age-band's average? These are the cells where a one-dimensional
  age-only rate table is most mispriced — the vehicle age interaction
  creates risk that the flat rate doesn't capture."

  WHY THIS TECHNIQUE
  A correlated subquery is used here to compute the reference value — the
  average burning cost across all vehicle-age cells within a given age band.
  It is "correlated" because the subquery references h.age_band and
  h.accident_year from the outer query: it re-executes for each outer row,
  computing the denominator specific to that row's age band and year.

  Honest trade-off vs window function:
    AVG(burning_cost_capped) OVER (PARTITION BY age_band, accident_year)
    would compute the same denominator in a single pass (O(n) vs O(n²)).
    For 105 rows the difference is immeasurable; for millions of rows the
    correlated subquery would be materially slower.

    The correlated subquery is shown here because:
    (a) it makes the filtering logic self-contained in the WHERE clause —
        the business rule "cells > 150% of their age-band average" is
        expressed directly in SQL without a CTE wrapper;
    (b) it demonstrates the technique for contexts where window functions
        are unavailable (MySQL pre-8.0, some embedded DBs);
    (c) in an interview context it is a distinct skill from window functions
        and worth demonstrating separately.

    In production on a large dataset, replace with a CTE:
      WITH band_avgs AS (
          SELECT age_band, accident_year,
                 AVG(burning_cost_capped) AS avg_bc
          FROM   mart_age_x_vehage_heatmap
          GROUP BY age_band, accident_year
      )
      SELECT h.*, h.burning_cost_capped / b.avg_bc AS ratio ...
      FROM   mart_age_x_vehage_heatmap h
      JOIN   band_avgs b USING (age_band, accident_year)
      WHERE  h.burning_cost_capped > 1.5 * b.avg_bc

  THRESHOLD: 1.5× (150%) is chosen as a materiality floor — cells below
  that level are likely noise given typical GLM uncertainty bounds. In
  production, replace the literal with {{ var('outlier_ratio', 1.5) }} and
  let the underwriting team tune it per product line or confidence interval.

  Underwriting implication:
  Cells identified here are candidates for a vehicle-age loading factor in
  the rate table — an interaction term that a GLM would also surface if fitted
  with age × veh_age as a two-way interaction.
*/

SELECT
    h.accident_year,
    h.age_band,
    h.veh_age_band,
    h.burning_cost_capped                                   AS cell_bc,

    -- Correlated subquery: average BC for all veh_age cells in this age band and year.
    -- The WHERE clause references h.age_band and h.accident_year from the outer row.
    ROUND(
        (SELECT AVG(h2.burning_cost_capped)
         FROM   main.mart_age_x_vehage_heatmap h2
         WHERE  h2.age_band      = h.age_band
           AND  h2.accident_year = h.accident_year)
    , 2)                                                    AS age_band_avg_bc,

    -- How many times the cell's BC exceeds its band average
    ROUND(
        h.burning_cost_capped
        / (SELECT AVG(h2.burning_cost_capped)
           FROM   main.mart_age_x_vehage_heatmap h2
           WHERE  h2.age_band      = h.age_band
             AND  h2.accident_year = h.accident_year)
    , 3)                                                    AS ratio_to_band_avg,

    h.policy_count,
    ROUND(h.earned_exposure, 1)                             AS earned_exposure_py

FROM main.mart_age_x_vehage_heatmap h

-- Filter: only cells where BC exceeds 150% of the age-band average.
-- The subquery here is the same correlated pattern — DuckDB optimises
-- repeated identical correlated subqueries but clarity is the priority.
WHERE h.burning_cost_capped > 1.5 * (
    SELECT AVG(h2.burning_cost_capped)
    FROM   main.mart_age_x_vehage_heatmap h2
    WHERE  h2.age_band      = h.age_band
      AND  h2.accident_year = h.accident_year
)

ORDER BY ratio_to_band_avg DESC
;
