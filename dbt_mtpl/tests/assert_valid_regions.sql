-- assert_valid_regions.sql
-- Singular test: fails if any row in stg_freq has a region not in the canonical list.
--
-- WHY a singular test rather than accepted_values?
-- dbt's generic accepted_values test generates an IN (...) clause by interpolating
-- the values list as SQL string literals. Any value containing a single quote
-- (such as "Provence-Alpes-Cotes-D'Azur") breaks the generated SQL.
-- A singular test lets us write raw SQL and use the standard '' escape for apostrophes.
--
-- A singular test returns rows that FAIL the assertion.
-- dbt expects zero rows returned for the test to pass.

SELECT
    idpol,
    region
FROM {{ ref('stg_freq') }}
WHERE region NOT IN (
    'Alsace',
    'Aquitaine',
    'Auvergne',
    'Basse-Normandie',
    'Bourgogne',
    'Bretagne',
    'Centre',
    'Champagne-Ardenne',
    'Corse',
    'Franche-Comte',
    'Haute-Normandie',
    'Ile-de-France',
    'Languedoc-Roussillon',
    'Limousin',
    'Midi-Pyrenees',
    'Nord-Pas-de-Calais',
    'Pays-de-la-Loire',
    'Picardie',
    'Poitou-Charentes',
    'Provence-Alpes-Cotes-D''Azur',  -- '' is the SQL standard escape for a literal apostrophe
    'Rhone-Alpes'
)
