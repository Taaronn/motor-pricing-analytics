{{
  config(materialized='view')
}}

/*
  int_policy_with_exposure — the central policy-level analytical base table.

  Joins cleaned exposure (stg_freq) to capped policy losses (int_policy_losses).
  This is the model that all mart aggregations read from — one clean, tested,
  policy-level dataset with exposure and capped losses aligned.

  WHY LEFT JOIN (not INNER JOIN)?
  Most policies have no claims. An INNER JOIN would silently drop all zero-claim
  policies from the dataset, removing them from exposure totals and inflating
  burning cost. LEFT JOIN retains every policy; COALESCE gives zero-claim
  policies a loss of 0.

  Note on row count vs stg_freq:
  This model has the same row count as stg_freq (one row per policy). The ~195
  unmatched IDpols in the severity table (claims with no matching policy) are
  excluded by this join — they cannot contribute exposure and so correctly fall
  out. See data_quality.md issue [8].

  Sources: stg_freq, int_policy_losses
*/

WITH policies AS (

    SELECT * FROM {{ ref('stg_freq') }}

),

losses AS (

    SELECT * FROM {{ ref('int_policy_losses') }}

)

SELECT
    -- Policy identifiers and rating factors
    p.idpol,
    p.claim_nb,
    p.exposure,
    p.veh_power,
    p.veh_age,
    p.driv_age,
    p.bonus_malus,
    p.veh_brand,
    p.veh_gas,
    p.area,
    p.density,
    p.region,

    -- Loss metrics (zero for no-claim policies via COALESCE)
    COALESCE(l.claim_count, 0)        AS claim_count,
    COALESCE(l.policy_loss_raw, 0)    AS policy_loss_raw,
    COALESCE(l.policy_loss_capped, 0) AS policy_loss_capped,

    -- Convenience flag: did this policy have at least one claim?
    CASE WHEN l.idpol IS NOT NULL THEN 1 ELSE 0 END AS has_claim

FROM policies p
LEFT JOIN losses l
    ON p.idpol = l.idpol
