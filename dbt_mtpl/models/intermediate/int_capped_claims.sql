{{
  config(materialized='view')
}}

/*
  int_capped_claims — apply the P99 severity cap to each individual claim.

  The cap threshold (€16,793.70) is the 99th percentile of ClaimAmount in the
  raw severity table, established in sql/exploration/04_loss_distribution.sql.

  WHY cap at the individual claim level, not at the policy level?
  A policy with two legitimate mid-size claims should not be penalised for the
  sum exceeding the cap. Capping per-claim preserves attritional signal while
  neutralising the effect of a single catastrophic loss. Doing it here — in an
  intermediate model — means every downstream model inherits the same rule
  automatically. One place to change the threshold, one place to audit it.

  Source: stg_sev (already cleaned: no NULLs, no zero-value claims)
*/

WITH source AS (

    SELECT * FROM {{ ref('stg_sev') }}

)

SELECT
    idpol,
    claim_amount                                            AS claim_amount_raw,
    LEAST(claim_amount, 16793.70)                          AS claim_amount_capped

FROM source
