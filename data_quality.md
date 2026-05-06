# Data Quality Log

Documents all known data quality issues in the freMTPL2 dataset, including issues
present in the original source data and issues deliberately introduced into
`raw_freq_dirty` / `raw_sev_dirty` for dbt cleaning demonstration.

The dirty tables are produced by `sql/dirty_raw.sql`. dbt staging models
(`stg_freq`, `stg_sev`) apply the cleaning rules listed here.

---

## Issues in raw_freq_dirty

### [1] Duplicate rows (~50 rows)
**What it is:** 50 rows were inserted from `raw_freq` with the same `IDpol` as
existing rows, producing exact duplicates.

**Row count:** `raw_freq_dirty` has 678,063 rows vs `raw_freq`'s 678,013 — a
difference of exactly 50.

**Cleaning rule:** `ROW_NUMBER() OVER (PARTITION BY IDpol ORDER BY IDpol)` — keep
only the first occurrence per `IDpol`. Rows where `row_num > 1` are dropped.

**Why this matters in practice:** Duplicate policy records are common when source
feeds are reloaded without a truncate step, or when two systems contribute to the
same feed. If not caught, duplicate rows inflate earned exposure and artificially
deflate burning cost.

---

### [2] Mixed-case Region values (350 rows)
**What it is:** `Region` values were overwritten with `lower()` (200 rows) and
`upper()` (150 rows) variants. For example: `"Alsace"` appears alongside
`"alsace"` and `"ALSACE"` in the same table.

**Row count:** 350 rows with non-standard casing (excluding whitespace rows,
which are covered under [3]).

**Cleaning rule:** `TRIM(INITCAP(Region))` — trims whitespace, then title-cases
each word. Normalises all variants to `"Alsace"` form.

**Why this matters in practice:** Case inconsistencies cause GROUP BY to produce
spurious segments — `"alsace"` and `"Alsace"` will appear as separate regions
on a dashboard, fragmenting exposure counts and producing nonsense burning costs.

---

### [3] Leading/trailing whitespace on Region (100 rows)
**What it is:** `Region` values have two spaces prepended and appended
(e.g. `"  Alsace  "`).

**Row count:** 100 rows.

**Cleaning rule:** `TRIM(Region)` (combined with `INITCAP` from rule [2]).

**Why this matters in practice:** Whitespace padding is invisible in most BI
tools — `"Alsace"` and `"  Alsace  "` look identical on a dashboard but are
treated as separate values in SQL GROUP BY and JOIN keys.

---

### [4] Trailing whitespace on VehBrand (100 rows)
**What it is:** A trailing space appended to `VehBrand` values
(e.g. `"B12 "`).

**Row count:** 100 rows.

**Cleaning rule:** `TRIM(VehBrand)`.

**Why this matters in practice:** Same category-fragmentation risk as [3], but
on vehicle brand. Vehicle brand is used as a rating factor and joining key in
intermediate models.

---

### [5] Implausible DrivAge values (20 rows)
**What it is:** `DrivAge` overwritten with `999` (10 rows) and `-5` (10 rows).

**Row count:** 20 rows.

**Valid range:** 18 to 100 (minimum legal driving age; 100+ treated as data error).

**Cleaning rule:** `WHERE DrivAge BETWEEN 18 AND 100` — rows outside this range
are dropped in staging. A dbt singular test also asserts no out-of-range values
reach the mart layer.

**Why this matters in practice:** Out-of-range ages can be the result of
miskeyed data, unit errors (e.g. date-of-birth encoded as age incorrectly), or
system default values. A DrivAge of 999 would be bucketed into the `75+` age
band under a naive CASE statement, distorting that segment's burning cost.

---

### [6] Implausible Exposure values (12 rows total)
**What it is:** `Exposure` overwritten with `-0.5` (5 rows) and `999.0` (5 rows).
Additionally, **2 rows existed in the original `raw_freq`** with `Exposure <= 0`
— a genuine pre-existing data quality issue in the source dataset.

**Row count:** 10 injected + 2 pre-existing = 12 rows total.

**Valid range:** `0 < Exposure <= 1` (fraction of a policy year; cannot exceed 1
for a single-year study).

**Cleaning rule:** `WHERE Exposure > 0 AND Exposure <= 1` — rows outside this
range are dropped in staging.

**Why this matters in practice:** Exposure is the denominator of burning cost.
A negative or zero exposure causes division-by-zero or sign-flipped burning
costs. An exposure of 999 would wildly inflate that policy's contribution to
portfolio-level earned exposure.

> **Note:** The 2 pre-existing bad-exposure rows are a real finding in the
> freMTPL2 source data, not a synthetic issue. Their presence here demonstrates
> why staging validation is essential even on "clean" source data.

---

## Issues in raw_sev_dirty

### [7] NULL ClaimAmount values (30 rows)
**What it is:** `ClaimAmount` set to `NULL` on 30 rows.

**Row count:** 30 rows (out of 26,639 total).

**Cleaning rule:** `WHERE ClaimAmount IS NOT NULL AND ClaimAmount > 0` — NULL
and zero-valued claims are dropped in staging. A dbt `not_null` test enforces
this on the staged severity table.

**Why this matters in practice:** NULL claim amounts typically represent claims
that have been reported but not yet valued (IBNR in the reserving sense). They
should not be included in a burning cost calculation — doing so would understate
average severity and make the portfolio look cheaper than it is.

---

## Issues in original raw_sev (not introduced synthetically)

### [8] Unmatched IDpol in severity table (~195 rows)
**What it is:** ~195 rows in `raw_sev` have an `IDpol` value that does not
match any policy in `raw_freq`. These claims cannot be joined to an exposure base.

**Row count:** ~195 rows.

**Handling:** Retained in `raw_sev` totals but excluded from any model that
requires a LEFT JOIN to `raw_freq` (i.e. all intermediate and mart models).
These rows do not affect portfolio burning cost calculations since they have
no matched exposure.

**Why this matters in practice:** Unmatched severity records could indicate
policies that were cancelled mid-year and removed from the freq file, or a
referential integrity issue in the source system. In a production environment
these would be escalated to the data engineering team for investigation.

---

## Operational notes

### [O1] DuckDB single-writer constraint

DuckDB is a local single-process analytical engine. It enforces an exclusive
write lock on the `.duckdb` file: only one connection can hold a write lock at
a time. This affects the Dagster orchestration layer in two ways:

**Dagster run concurrency (`max_concurrent_runs: 1`)**
When a backfill materialises multiple partitions, Dagster's default behaviour
is to launch all partition runs concurrently. For a DuckDB backend, concurrent
runs each try to open the file for writing and all but one will fail with a
lock conflict error. The instance is configured with `max_concurrent_runs: 1`
in `dagster_home/dagster.yaml`, which serialises runs through a queue. Each
partition run completes and releases the lock before the next one starts.

**dbt thread count (`threads: 1`)**
dbt runs independent models in parallel across threads. With a DuckDB backend,
parallel model execution within a single dbt invocation also causes lock
contention. The dev target in `~/.dbt/profiles.yml` is set to `threads: 1` so
dbt executes models sequentially within each run.

**Architectural note:** Both settings are constraints of the DuckDB storage
engine, not of the pipeline design. On a Snowflake or BigQuery backend,
`max_concurrent_runs` can be removed (unlimited concurrency is correct) and
`threads` can be increased to 4–8 for parallel model execution. The pipeline
code itself is backend-agnostic; only these two config values need to change.
