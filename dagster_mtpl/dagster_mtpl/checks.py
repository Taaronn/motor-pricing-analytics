"""
Asset checks for the MTPL pipeline.

WHY asset checks at the orchestration layer vs dbt tests?
dbt tests validate schema contracts at model build time: not_null, unique,
accepted_values. They run inside a dbt invocation and catch structural issues.

Dagster asset checks run AFTER materialisation, in Python, with access to the
full Dagster execution context. They are the right place for:
  - Runtime volume anomalies (row count drift across runs)
  - Null rate monitoring that should alert on-call, not just fail a CI step
  - Cross-asset reconciliation that spans multiple dbt models
  - Partition balance checks that require aggregating across the full dataset

With blocking=True, a failing check prevents downstream Dagster assets from
materialising — the orchestration-layer equivalent of a circuit breaker.
"""
from pathlib import Path

import duckdb
from dagster import AssetCheckResult, AssetCheckSeverity, AssetKey, asset_check

# Absolute path to the DuckDB file. Mirrors the path in ~/.dbt/profiles.yml.
DUCKDB_PATH = Path(__file__).parent.parent.parent / "mtpl.duckdb"


def _connect() -> duckdb.DuckDBPyConnection:
    """Open a read-only DuckDB connection.

    Read-only mode allows the check to run concurrently with other readers
    and avoids any risk of interfering with an in-progress dbt write.
    """
    return duckdb.connect(str(DUCKDB_PATH), read_only=True)


# ---------------------------------------------------------------------------
# Check 1: stg_freq row count drift
# ---------------------------------------------------------------------------

# Baseline established from the first clean dbt run against the full dataset.
# 676,759 is the row count of stg_freq after deduplication, DrivAge/Exposure
# cleaning, and region normalisation (see data_quality.md).
_STG_FREQ_BASELINE = 676_759
_STG_FREQ_ROW_COUNT_FLOOR = int(_STG_FREQ_BASELINE * 0.90)  # 90% = 609,083


@asset_check(
    asset=AssetKey("stg_freq"),
    blocking=True,
    description=(
        "Row count must be >= 90% of the established baseline (676,759 rows). "
        "Catches partial source loads, accidental truncation, or upstream feed "
        "failures that silently reduce policy volume. A 10% tolerance allows for "
        "legitimate data corrections without false-positive alerts."
    ),
)
def stg_freq_row_count_check() -> AssetCheckResult:
    """Detect sudden drops in stg_freq row volume.

    Failure mode caught: the source CSV is re-delivered with only a partial
    extract (e.g. one region's data missing), or a cleaning rule is accidentally
    tightened and drops a large chunk of valid rows. Both manifest as a count
    well below the established baseline.

    In production you would store the previous run's count in a monitoring table
    and compute the threshold dynamically, making the check self-calibrating as
    the book grows year-over-year.
    """
    conn = _connect()
    row_count = conn.execute("SELECT COUNT(*) FROM main.stg_freq").fetchone()[0]
    conn.close()

    passed = row_count >= _STG_FREQ_ROW_COUNT_FLOOR
    return AssetCheckResult(
        passed=passed,
        severity=AssetCheckSeverity.ERROR,
        metadata={
            "row_count": row_count,
            "baseline": _STG_FREQ_BASELINE,
            "threshold_90pct": _STG_FREQ_ROW_COUNT_FLOOR,
            "pct_of_baseline": round(row_count / _STG_FREQ_BASELINE * 100, 2),
        },
        description=(
            f"Row count {row_count:,} is "
            f"{row_count / _STG_FREQ_BASELINE * 100:.1f}% of baseline "
            f"({_STG_FREQ_BASELINE:,}). "
            f"{'PASS' if passed else 'FAIL — below 90% floor of ' + str(_STG_FREQ_ROW_COUNT_FLOOR)}"
        ),
    )


# ---------------------------------------------------------------------------
# Check 2: bonus_malus null rate on stg_freq
# ---------------------------------------------------------------------------

_BONUS_MALUS_NULL_RATE_LIMIT = 5.0  # percent


@asset_check(
    asset=AssetKey("stg_freq"),
    blocking=True,
    description=(
        "bonus_malus null rate must be <= 5%. "
        "bonus_malus is a critical rating factor — nulls here mean policies "
        "cannot be correctly priced or segmented downstream."
    ),
)
def stg_freq_bonus_malus_null_rate_check() -> AssetCheckResult:
    """Monitor null rate on the bonus_malus rating factor.

    Failure mode caught: the upstream feed starts omitting the BonusMalus
    column for a subset of policies (e.g. a new sub-product type that the
    source system doesn't populate). A dbt not_null test would catch a total
    absence, but a partial null spike (e.g. 15% of rows) could pass if the
    test wasn't perfectly scoped. This check catches the gradual degradation
    pattern.

    5% threshold: a small null rate can reflect legitimate data issues (new
    policies mid-year without a BM history). Above 5% suggests a systemic
    feed problem that warrants investigation before downstream models run.
    """
    conn = _connect()
    result = conn.execute(
        """
        SELECT
            COUNT(*) FILTER (WHERE bonus_malus IS NULL) * 100.0 / COUNT(*)
        FROM main.stg_freq
        """
    ).fetchone()
    conn.close()

    null_rate = result[0] if result[0] is not None else 0.0
    passed = null_rate <= _BONUS_MALUS_NULL_RATE_LIMIT
    return AssetCheckResult(
        passed=passed,
        severity=AssetCheckSeverity.ERROR,
        metadata={
            "null_rate_pct": round(null_rate, 4),
            "threshold_pct": _BONUS_MALUS_NULL_RATE_LIMIT,
        },
        description=(
            f"bonus_malus null rate: {null_rate:.4f}% "
            f"({'≤' if passed else '>'} {_BONUS_MALUS_NULL_RATE_LIMIT}% threshold). "
            f"{'PASS' if passed else 'FAIL'}"
        ),
    )


# ---------------------------------------------------------------------------
# Check 3: cross-mart exposure reconciliation
# ---------------------------------------------------------------------------

_EXPOSURE_TOLERANCE_PY = 1.0  # policy-years


@asset_check(
    asset=AssetKey("mart_burning_cost_by_age"),
    blocking=True,
    description=(
        "Total earned_exposure must agree between mart_burning_cost_by_age and "
        "mart_burning_cost_by_bonus_malus within 1.0 policy-year. "
        "Both marts aggregate the same base table; divergence means one mart "
        "silently dropped or duplicated rows via its GROUP BY logic."
    ),
)
def cross_mart_exposure_reconciliation_check() -> AssetCheckResult:
    """Cross-check exposure totals across the two primary mart tables.

    Failure mode caught: a WHERE clause or CASE expression in one mart
    accidentally filters out rows that the other mart includes — for example,
    a NULL bm_band that absorbs 3,000 policies silently. Both marts read from
    int_policy_with_exposure; if their exposure sums diverge, one of them has
    a structural problem.

    This is the orchestration-layer mirror of the dbt singular test
    assert_mart_totals_reconcile.sql. Having both means a failure is visible in
    two places: dbt test output AND the Dagster asset check panel. In a paged
    alerting setup, the Dagster check is what fires the on-call notification.

    Tolerance of 1.0 py accommodates ROUND(..., 1) rounding applied per row in
    each mart before aggregation (heatmap has 35 cells vs 7 for the age mart,
    so accumulated rounding can differ slightly).
    """
    conn = _connect()
    age_exposure = conn.execute(
        "SELECT SUM(earned_exposure) FROM main.mart_burning_cost_by_age"
    ).fetchone()[0]
    bm_exposure = conn.execute(
        "SELECT SUM(earned_exposure) FROM main.mart_burning_cost_by_bonus_malus"
    ).fetchone()[0]
    conn.close()

    diff = abs(age_exposure - bm_exposure)
    passed = diff <= _EXPOSURE_TOLERANCE_PY
    return AssetCheckResult(
        passed=passed,
        severity=AssetCheckSeverity.ERROR,
        metadata={
            "age_mart_exposure_py": round(age_exposure, 2),
            "bm_mart_exposure_py": round(bm_exposure, 2),
            "absolute_diff_py": round(diff, 6),
            "tolerance_py": _EXPOSURE_TOLERANCE_PY,
        },
        description=(
            f"Exposure diff: {diff:.6f} py between age mart ({age_exposure:.2f}) "
            f"and BM mart ({bm_exposure:.2f}). "
            f"Tolerance: {_EXPOSURE_TOLERANCE_PY} py. "
            f"{'PASS' if passed else 'FAIL'}"
        ),
    )


# ---------------------------------------------------------------------------
# Check 4: per-partition row count consistency
# ---------------------------------------------------------------------------

_PARTITION_BALANCE_LIMIT = 0.50  # 50% max deviation from mean


@asset_check(
    asset=AssetKey("stg_freq"),
    blocking=True,
    description=(
        "No accident_year partition's policy count may deviate from the "
        "cross-partition average by more than 50%. "
        "Catches degenerate HASH distributions or silent zero-row partitions."
    ),
)
def partition_row_count_consistency_check() -> AssetCheckResult:
    """Verify that accident_year partitions have broadly balanced row counts.

    Failure mode caught: the HASH(IDpol) partition formula is accidentally
    changed (e.g. during a model refactor) and produces a degenerate split —
    say 95% of policies assigned to 2019 and 5% to 2017. Burning cost
    calculations would then be based on extremely thin exposure for 2017,
    making that year's figures statistically meaningless. This check fails
    before those numbers reach a dashboard.

    Also catches the silent zero-row partition: if a formula bug assigns 0
    rows to one year, that year's assets appear materialised in Dagster but
    contain no data. A 50% deviation threshold catches a year at 0 rows
    (100% deviation) or even at 25% of its expected count.

    NOTE: In a cloud warehouse with persistent incremental mart tables, this
    check would run against the mart tables directly (each partition physically
    stored separately). In DuckDB, mart tables are overwritten per run, so
    stg_freq (an unfiltered view of the full dataset) is the right target.
    """
    conn = _connect()
    rows = conn.execute(
        """
        SELECT accident_year, COUNT(*) AS cnt
        FROM main.stg_freq
        GROUP BY accident_year
        ORDER BY accident_year
        """
    ).fetchall()
    conn.close()

    counts = {str(year): cnt for year, cnt in rows}
    if not counts:
        return AssetCheckResult(
            passed=False,
            severity=AssetCheckSeverity.ERROR,
            description="No rows found in stg_freq — cannot compute partition balance.",
        )

    mean_count = sum(counts.values()) / len(counts)
    deviations = {
        year: abs(cnt - mean_count) / mean_count
        for year, cnt in counts.items()
    }
    worst_year = max(deviations, key=deviations.get)
    worst_deviation = deviations[worst_year]
    passed = worst_deviation <= _PARTITION_BALANCE_LIMIT

    return AssetCheckResult(
        passed=passed,
        severity=AssetCheckSeverity.ERROR,
        metadata={
            **{f"rows_{year}": cnt for year, cnt in counts.items()},
            "mean_rows": round(mean_count, 1),
            "worst_year": worst_year,
            "worst_deviation_pct": round(worst_deviation * 100, 2),
            "threshold_pct": _PARTITION_BALANCE_LIMIT * 100,
        },
        description=(
            f"Partition counts: {counts}. "
            f"Worst deviation: {worst_year} at {worst_deviation * 100:.1f}% from mean "
            f"({mean_count:,.0f}). "
            f"Threshold: {_PARTITION_BALANCE_LIMIT * 100:.0f}%. "
            f"{'PASS' if passed else 'FAIL'}"
        ),
    )
