{{
  config(materialized='view')
}}

/*
  int_policy_losses — aggregate capped claims to one row per policy.

  A policy can have multiple claims. This model collapses to policy level so
  that the next step (int_policy_with_exposure) can do a clean 1:1 LEFT JOIN
  on IDpol without fan-out. Without this step, joining raw claims to the policy
  table would multiply exposure rows for multi-claim policies.

  WHY SUM the capped amounts?
  The cap was applied per-claim in int_capped_claims. Summing here gives the
  policy-level total loss after capping — the correct numerator for burning cost
  at policy level.

  Source: int_capped_claims
*/

WITH source AS (

    SELECT * FROM {{ ref('int_capped_claims') }}

)

SELECT
    idpol,
    COUNT(*)                        AS claim_count,
    SUM(claim_amount_raw)           AS policy_loss_raw,
    SUM(claim_amount_capped)        AS policy_loss_capped

FROM source
GROUP BY idpol
