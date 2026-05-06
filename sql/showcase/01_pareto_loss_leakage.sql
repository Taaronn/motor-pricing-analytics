/*
  SHOWCASE 1: Window functions — Pareto loss leakage analysis
  ============================================================

  BUSINESS QUESTION
  "What is the smallest set of (age × vehicle age) segments that explains
  80% of our total underwriting loss? Which cells should the pricing team
  focus on first?"

  WHY THIS TECHNIQUE
  The cumulative-sum window function is the right tool here because:

    1. ROW_NUMBER() OVER (ORDER BY ...) ranks all 35 cells portfolio-wide in
       a single pass — no GROUP BY or correlated subquery needed.

    2. SUM(...) OVER (ORDER BY ... ROWS BETWEEN UNBOUNDED PRECEDING AND
       CURRENT ROW) computes a running total without a self-join. The frame
       clause is important: ROWS BETWEEN ... gives a deterministic running
       total even if two cells have the same loss amount (ties handled by
       row insertion order within the frame).

    3. The 80% threshold in the final WHERE/CASE doesn't require a subquery
       because the cumulative percentage is already available as a window
       output — the logic reads linearly from top to bottom.

  THRESHOLD: 80% is the standard Pareto concentration point used in most
  insurance triage exercises. In production, parametrise as a dbt var
  ({{ var('pareto_threshold', 0.80) }}) so pricing and actuarial teams can
  run 70% or 90% cuts without touching the SQL.

  Alternative that DOESN'T work as well:
  A correlated subquery (SUM of all rows with rank <= current) would produce
  the same result but scan the table O(n²). With 35 cells that's trivial;
  with 35,000 cells in a real book it would be 1,000× slower.

  Aggregate used: SUM() OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
  Combines all three accident years — this is a portfolio view, not a single-year slice.
*/

WITH segment_totals AS (

    -- Aggregate across accident years to get portfolio-level loss by cell.
    -- The 30/35/35 year split means each year has different exposure, so we
    -- can't just take any single year as representative — sum all three.
    SELECT
        age_band,
        veh_age_band,
        SUM(total_capped_losses)              AS segment_losses,
        SUM(earned_exposure)                  AS segment_exposure,
        ROUND(SUM(total_capped_losses)
              / SUM(earned_exposure), 2)      AS burning_cost_capped
    FROM main.mart_age_x_vehage_heatmap
    GROUP BY age_band, veh_age_band

),

ranked AS (

    SELECT
        age_band,
        veh_age_band,
        segment_losses,
        segment_exposure,
        burning_cost_capped,

        -- Rank cells from highest to lowest total loss
        ROW_NUMBER() OVER (
            ORDER BY segment_losses DESC
        )                                                       AS loss_rank,

        -- Portfolio grand total (same value on every row — OVER () with no frame)
        SUM(segment_losses) OVER ()                             AS portfolio_total_losses,

        -- Running total: losses accounted for by the top-N cells
        SUM(segment_losses) OVER (
            ORDER BY segment_losses DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                                                       AS cumulative_losses

    FROM segment_totals

)

SELECT
    loss_rank,
    age_band,
    veh_age_band,
    ROUND(segment_losses, 0)                                        AS segment_losses_eur,
    ROUND(segment_losses / portfolio_total_losses * 100, 2)         AS pct_of_total,
    ROUND(cumulative_losses / portfolio_total_losses * 100, 1)      AS cumulative_pct,
    burning_cost_capped,
    CASE
        WHEN cumulative_losses <= portfolio_total_losses * 0.80
            THEN 'core (in 80%)'
        ELSE 'tail (>80%)'
    END                                                             AS pareto_group

FROM ranked
ORDER BY loss_rank
;
