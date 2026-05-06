{{
  config(materialized='view')
}}

/*
  stg_freq — staging model for the policy (frequency) table
  Source: raw_freq_dirty (deliberately introduced data quality issues)

  Cleaning steps applied (see data_quality.md for issue catalogue):
    1. Deduplication  — ROW_NUMBER() OVER (PARTITION BY IDpol): keep first occurrence per policy
    2. Region casing  — TRIM + lookup against canonical region list (handles lower/upper/whitespace)
    3. VehBrand trim  — TRIM removes trailing whitespace
    4. DrivAge range  — DROP rows where DrivAge < 18 or > 100 (implausible values)
    5. Exposure range — DROP rows where Exposure <= 0 or > 1 (fraction of year; cannot exceed 1)
    6. Column rename  — CamelCase → snake_case as dbt convention

  WHY views for staging?
  Staging models are thin wrappers — they don't need to be materialised as tables
  because downstream models will filter and aggregate heavily anyway. Views keep
  the pipeline fast during development and avoid storing intermediate data.
*/

WITH source AS (

    SELECT * FROM {{ source('raw', 'raw_freq_dirty') }}

),

deduped AS (

    -- ROW_NUMBER() partitions by IDpol and numbers each occurrence.
    -- Keeping only row 1 per IDpol eliminates all exact duplicates.
    -- WHY ROW_NUMBER over DISTINCT: DISTINCT requires all columns to match;
    -- ROW_NUMBER works even if the duplicates differ on some columns.
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY IDpol ORDER BY IDpol) AS _row_num
    FROM source

),

canonical_regions AS (

    -- Hardcoded lookup: maps any case/whitespace variant to the correct title-case name.
    -- WHY a lookup rather than initcap(): French region names like "Franche-Comte" and
    -- "Provence-Alpes-Cotes-D'Azur" have non-standard capitalisation that a generic
    -- string function would mangle. An explicit list validates AND corrects simultaneously.
    SELECT * FROM (VALUES
        ('alsace',                        'Alsace'),
        ('aquitaine',                     'Aquitaine'),
        ('auvergne',                      'Auvergne'),
        ('basse-normandie',               'Basse-Normandie'),
        ('bourgogne',                     'Bourgogne'),
        ('bretagne',                      'Bretagne'),
        ('centre',                        'Centre'),
        ('champagne-ardenne',             'Champagne-Ardenne'),
        ('corse',                         'Corse'),
        ('franche-comte',                 'Franche-Comte'),
        ('haute-normandie',               'Haute-Normandie'),
        ('ile-de-france',                 'Ile-de-France'),
        ('languedoc-roussillon',          'Languedoc-Roussillon'),
        ('limousin',                      'Limousin'),
        ('midi-pyrenees',                 'Midi-Pyrenees'),
        ('nord-pas-de-calais',            'Nord-Pas-de-Calais'),
        ('pays-de-la-loire',              'Pays-de-la-Loire'),
        ('picardie',                      'Picardie'),
        ('poitou-charentes',              'Poitou-Charentes'),
        ('provence-alpes-cotes-d''azur',  'Provence-Alpes-Cotes-D''Azur'),
        ('rhone-alpes',                   'Rhone-Alpes')
    ) AS t(region_key, region_canonical)

),

cleaned AS (

    SELECT
        d.IDpol                                     AS idpol,
        d.ClaimNb                                   AS claim_nb,
        CAST(d.Exposure AS DOUBLE)                  AS exposure,
        CAST(d.VehPower AS INTEGER)                 AS veh_power,
        CAST(d.VehAge AS INTEGER)                   AS veh_age,
        CAST(d.DrivAge AS INTEGER)                  AS driv_age,
        CAST(d.BonusMalus AS INTEGER)               AS bonus_malus,
        TRIM(d.VehBrand)                            AS veh_brand,
        d.VehGas                                    AS veh_gas,
        d.Area                                      AS area,
        CAST(d.Density AS INTEGER)                  AS density,
        -- Join on lowercased, trimmed Region to match any case variant
        COALESCE(cr.region_canonical, TRIM(d.Region)) AS region

    FROM deduped d
    LEFT JOIN canonical_regions cr
        ON lower(TRIM(d.Region)) = cr.region_key

    WHERE
        d._row_num = 1                        -- drop duplicates
        AND d.DrivAge BETWEEN 18 AND 100      -- drop implausible driver ages
        AND d.Exposure > 0 AND d.Exposure <= 1  -- drop bad exposure values

)

SELECT * FROM cleaned
