import json
from pathlib import Path

from dagster import (
    AssetExecutionContext,
    AssetSelection,
    DefaultScheduleStatus,
    RunRequest,
    ScheduleEvaluationContext,
    StaticPartitionsDefinition,
    define_asset_job,
    schedule,
)
from dagster_dbt import DbtCliResource, DbtProject, dbt_assets

# ---------------------------------------------------------------------------
# dbt project
# ---------------------------------------------------------------------------

MTPL_DBT_PROJECT = DbtProject(
    project_dir=Path(__file__).parent.parent.parent / "dbt_mtpl",
    profiles_dir=Path.home() / ".dbt",
)
MTPL_DBT_PROJECT.prepare_if_dev()


# ---------------------------------------------------------------------------
# Partition definition
# ---------------------------------------------------------------------------

# The freMTPL2 dataset has no real date column. accident_year is a synthetic
# dimension derived in stg_freq from HASH(IDpol) % 100 with a 30/35/35 split.
#
# StaticPartitionsDefinition is correct here because the set of accident years
# is closed and known in advance (not time-advancing). In production with a
# live feed you would use DailyPartitionsDefinition or MonthlyPartitionsDefinition,
# which auto-generate new partition keys as time advances and integrate natively
# with schedule fire dates via context.scheduled_execution_time.
accident_year_partitions = StaticPartitionsDefinition(["2017", "2018", "2019"])


# ---------------------------------------------------------------------------
# dbt assets (partitioned)
# ---------------------------------------------------------------------------

@dbt_assets(
    manifest=MTPL_DBT_PROJECT.manifest_path,
    partitions_def=accident_year_partitions,
)
def mtpl_dbt_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    """All 8 dbt models as Dagster assets, partitioned by accident_year.

    When Dagster materialises a specific partition, context.partition_key
    holds the year string ("2017" / "2018" / "2019"). We pass it to dbt
    as a Jinja variable via --vars. The intermediate model
    int_policy_with_exposure picks up the variable and adds a WHERE clause
    so that only that year's rows flow into the mart aggregations.

    Each partition run therefore builds a self-contained yearly slice.
    Dagster tracks which partitions have been materialised independently,
    so you can re-run 2018 without touching 2017 or 2019.

    DuckDB limitation: because the marts use materialized='table', each
    partition run overwrites the DuckDB table with that year's data only.
    In a cloud warehouse (BigQuery, Snowflake) you would use
    materialized='incremental' with partition_by so each year is stored
    as a separate physical partition and prior years are never touched.
    """
    dbt_vars = {"accident_year": int(context.partition_key)}
    yield from dbt.cli(
        ["run", "--vars", json.dumps(dbt_vars)],
        context=context,
    ).stream()


# ---------------------------------------------------------------------------
# Jobs
# ---------------------------------------------------------------------------

# full_refresh_job: the "rebuild everything" button.
#
# Because the assets are partitioned, materialising all three accident years
# means running this job three times — once per partition. The right way to
# trigger that in Dagster is via Backfill: select this job in the Backfill UI,
# choose all three partition keys, and Dagster queues one run per key.
# You get per-partition run history, independent failure recovery, and
# full observability without a monolithic "everything" run.
full_refresh_job = define_asset_job(
    name="full_refresh_job",
    selection=AssetSelection.assets(mtpl_dbt_assets),
    description=(
        "Rebuild all assets for one accident_year partition. "
        "Trigger via Backfill across all three partitions (2017/2018/2019) "
        "to do a complete book rebuild. Re-run a single partition to recover "
        "a failure without touching the other years."
    ),
)

# daily_partition_job: the incremental pattern.
#
# In production this job would run nightly, processing only the newly landed
# accident-year slice. Because only one partition re-runs, pipeline cost is
# proportional to one year of data — not the entire book. This is the core
# value of accretive partitioning: each incremental run is cheap and
# idempotent (re-running produces the same result).
daily_partition_job = define_asset_job(
    name="daily_partition_job",
    selection=AssetSelection.assets(mtpl_dbt_assets),
    description=(
        "Materialise a single accident_year partition. "
        "Scheduled daily to demonstrate the incremental pattern."
    ),
)


# ---------------------------------------------------------------------------
# Schedule
# ---------------------------------------------------------------------------

@schedule(
    job=daily_partition_job,
    cron_schedule="0 6 * * *",
    # STOPPED by default: this schedule is illustrative only.
    # The freMTPL2 dataset is static — no new data lands daily, so firing
    # the schedule would just re-materialise the same partition each morning.
    # In production (with a live nightly feed) you would flip this to
    # DefaultScheduleStatus.RUNNING and use DailyPartitionsDefinition so
    # context.scheduled_execution_time drives the partition key automatically.
    default_status=DefaultScheduleStatus.STOPPED,
)
def daily_partition_schedule(context: ScheduleEvaluationContext) -> RunRequest:
    """Nightly schedule targeting the most recent accident year.

    Hardcoded to partition "2019" because StaticPartitionsDefinition has no
    built-in concept of "latest". In production you would replace this with
    DailyPartitionsDefinition and derive the partition key from the cron
    fire date:
        partition_key = context.scheduled_execution_time.strftime("%Y-%m-%d")
    """
    return RunRequest(partition_key="2019")
