{{
  config(materialized='view')
}}

/*
  stg_sev — staging model for the severity (claims) table
  Source: raw_sev_dirty (contains ~30 NULL ClaimAmount values)

  Cleaning steps applied (see data_quality.md for issue catalogue):
    1. NULL ClaimAmount  — DROP rows where ClaimAmount IS NULL (unvalued claims)
    2. Zero ClaimAmount  — DROP rows where ClaimAmount <= 0 (nonsensical for a loss)
    3. Column rename     — CamelCase → snake_case

  Note: IDpol is not unique here — one policy can have multiple claims.
  The unique + not_null test on IDpol therefore lives only on stg_freq.
  stg_sev only asserts not_null on idpol (every claim must link to a policy).
*/

WITH source AS (

    SELECT * FROM {{ source('raw', 'raw_sev_dirty') }}

),

cleaned AS (

    SELECT
        IDpol           AS idpol,
        ClaimAmount     AS claim_amount

    FROM source

    WHERE
        ClaimAmount IS NOT NULL   -- drop unvalued claims (see data_quality.md issue [7])
        AND ClaimAmount > 0       -- drop zero-value claims (not meaningful for severity)

)

SELECT * FROM cleaned
