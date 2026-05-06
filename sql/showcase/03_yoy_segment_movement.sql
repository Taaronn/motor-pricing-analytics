/*
  SHOWCASE 3: Self-join — year-over-year burning cost movement by segment
  =======================================================================

  DATA CONTEXT — READ BEFORE INTERPRETING OUTPUT
  accident_year is a synthetic dimension derived from HASH(IDpol) % 100 for
  Dagster orchestration partitioning (see stg_freq.sql). The 2017/2018/2019
  split is a deterministic but arbitrary assignment of policies to years —
  not a real temporal cohort. Year-over-year movements observed in this
  output reflect the random variation introduced by that hash assignment,
  not genuine loss trends, reserve deterioration, or rate-action effects.

  In production with real accident-year data, this same self-join structure
  would surface meaningful pricing signals:
    - Calendar-year underwriting drift (macro loss inflation)
    - Reserve deterioration between underwriting and accident year
    - Rate-action effectiveness: did a 2018 rate increase reduce 2019 BC?
    - Segment mix shift as new business channels are added or dropped

  The query structure and the technique (self-join with year aliases) are
  the demonstration. The specific numbers are illustrative only.

  BUSINESS QUESTION
  "Which driver age segments saw the largest burning cost movement between
  accident years 2017 and 2019? Are any segments trending in a direction
  that warrants a rate change before the next renewal cycle?"

  WHY THIS TECHNIQUE
  A self-join is the correct tool when you need to compare two different
  subsets of the SAME table against each other — here, the 2017 rows versus
  the 2019 rows of mart_burning_cost_by_age.

  Alternatives that don't work as cleanly:

    - PIVOT / conditional aggregation (MAX(CASE WHEN year=2017...)):
      Works, but you lose column-level type safety and readability suffers.
      The self-join makes the 2017/2019 semantics explicit: y17.bc, y19.bc.

    - LAG() window function: requires ordering by accident_year within a
      partition, and only gives you the immediately preceding row — fine for
      consecutive years but awkward when comparing specific non-adjacent years
      or when rows may be missing (a missing year would give a wrong LAG).

    - Two separate CTEs then join: equivalent to a self-join but more verbose
      with no clarity benefit.

  The self-join's JOIN condition (ON age_band AND year filters) is the key:
  it is the relational expression of "give me matching segments from two
  different time slices". Missing segments (a band present in 2019 but not
  2017, or vice versa) are handled by the join type — INNER here because we
  want only segments with data in both years to make the comparison valid.

  THRESHOLD: ±20% is a common first-cut tolerance for rate adequacy review —
  movements inside that band are often within normal statistical noise for
  annual cohorts. In production, drive this from a dbt var or a config table
  (rate_change_appetite by segment) rather than hardcoding 0.20.

  Pricing interpretation of the output:
  bc_change_pct > 20%  → potential rate inadequacy, flag for pricing review
  bc_change_pct < -20% → potential rate redundancy, competitive opportunity
*/

SELECT
    y17.age_band,

    -- 2017 baseline
    ROUND(y17.earned_exposure, 1)                               AS exposure_2017_py,
    y17.burning_cost_capped                                     AS bc_2017,
    y17.relativity                                              AS relativity_2017,

    -- 2019 current
    ROUND(y19.earned_exposure, 1)                               AS exposure_2019_py,
    y19.burning_cost_capped                                     AS bc_2019,
    y19.relativity                                              AS relativity_2019,

    -- Movement metrics
    ROUND(y19.burning_cost_capped - y17.burning_cost_capped, 2) AS bc_change_eur,
    ROUND(
        (y19.burning_cost_capped - y17.burning_cost_capped)
        / y17.burning_cost_capped * 100
    , 1)                                                        AS bc_change_pct,

    -- Actioning flag: >20% movement in either direction warrants pricing review.
    -- Threshold is illustrative — a real pricing team would set this based on
    -- their rate change appetite and competitive position.
    CASE
        WHEN (y19.burning_cost_capped - y17.burning_cost_capped)
             / y17.burning_cost_capped >  0.20 THEN 'rate increase indicated'
        WHEN (y19.burning_cost_capped - y17.burning_cost_capped)
             / y17.burning_cost_capped < -0.20 THEN 'rate reduction opportunity'
        ELSE 'within tolerance'
    END                                                         AS pricing_action

FROM      main.mart_burning_cost_by_age y17   -- 2017 slice (left table)
JOIN      main.mart_burning_cost_by_age y19   -- 2019 slice (right table)
    ON    y17.age_band      = y19.age_band    -- match on segment
    AND   y17.accident_year = 2017
    AND   y19.accident_year = 2019

ORDER BY ABS(y19.burning_cost_capped - y17.burning_cost_capped) DESC
;
