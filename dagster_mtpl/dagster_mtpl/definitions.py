from dagster import Definitions
from dagster_dbt import DbtCliResource

from dagster_mtpl.assets import (
    MTPL_DBT_PROJECT,
    daily_partition_job,
    daily_partition_schedule,
    full_refresh_job,
    mtpl_dbt_assets,
)
from dagster_mtpl.checks import (
    cross_mart_exposure_reconciliation_check,
    partition_row_count_consistency_check,
    stg_freq_bonus_malus_null_rate_check,
    stg_freq_row_count_check,
)

defs = Definitions(
    assets=[mtpl_dbt_assets],
    asset_checks=[
        stg_freq_row_count_check,
        stg_freq_bonus_malus_null_rate_check,
        cross_mart_exposure_reconciliation_check,
        partition_row_count_consistency_check,
    ],
    jobs=[full_refresh_job, daily_partition_job],
    schedules=[daily_partition_schedule],
    resources={
        "dbt": DbtCliResource(project_dir=MTPL_DBT_PROJECT),
    },
)
