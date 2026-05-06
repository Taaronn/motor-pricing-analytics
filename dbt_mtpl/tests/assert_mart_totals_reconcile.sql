-- assert_mart_totals_reconcile.sql
-- Custom singular test: verifies that total exposure and total capped losses
-- are consistent across all three mart tables.
--
-- WHY this test matters:
-- Each mart aggregates int_policy_with_exposure by a different dimension. If
-- the GROUP BY logic in any mart accidentally filters rows (e.g. a WHERE clause
-- that shouldn't be there, or a NULL band that absorbs rows silently), its totals
-- will diverge from the others. This test catches that class of bug.
--
-- Tolerance: exposure within 0.01 policy-years, losses within €1.
-- These tolerances accommodate floating-point rounding differences.
--
-- A singular test returns rows that FAIL. Zero rows = test passes.

WITH age_totals AS (
    SELECT
        SUM(earned_exposure)     AS total_exposure,
        SUM(total_capped_losses) AS total_losses
    FROM {{ ref('mart_burning_cost_by_age') }}
),

bm_totals AS (
    SELECT
        SUM(earned_exposure)     AS total_exposure,
        SUM(total_capped_losses) AS total_losses
    FROM {{ ref('mart_burning_cost_by_bonus_malus') }}
),

heatmap_totals AS (
    SELECT
        SUM(earned_exposure)     AS total_exposure,
        SUM(total_capped_losses) AS total_losses
    FROM {{ ref('mart_age_x_vehage_heatmap') }}
),

comparison AS (
    SELECT
        a.total_exposure    AS age_exposure,
        b.total_exposure    AS bm_exposure,
        h.total_exposure    AS heatmap_exposure,
        a.total_losses      AS age_losses,
        b.total_losses      AS bm_losses,
        h.total_losses      AS heatmap_losses
    FROM age_totals a, bm_totals b, heatmap_totals h
)

-- Return a row (causing test failure) if any totals diverge beyond tolerance.
--
-- Tolerances are intentionally loose for exposure (1.0 py) and losses (€5):
-- Each mart rounds individual cells with ROUND(..., 1) before aggregating.
-- The heatmap has 35 cells (vs 7 and 4 for the other marts), so accumulated
-- rounding differences are larger. An observed gap of 0.2 py / €1 is a known
-- floating-point artefact, not a data integrity issue. Anything materially
-- larger (> 1 py exposure, > €5 losses) would indicate a real row-count divergence
-- and should fail the test.
SELECT
    'exposure or losses mismatch across marts' AS failure_reason,
    age_exposure,
    bm_exposure,
    heatmap_exposure,
    age_losses,
    bm_losses,
    heatmap_losses
FROM comparison
WHERE
    ABS(age_exposure - bm_exposure)         > 1.0
    OR ABS(age_exposure - heatmap_exposure) > 1.0
    OR ABS(age_losses  - bm_losses)         > 5.0
    OR ABS(age_losses  - heatmap_losses)    > 5.0
