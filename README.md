# Motor TPL Pricing Analysis

> **Business question:** Which segments are driving our motor book's loss ratio above target, and what rate change is indicated to bring it back in line?

**Status:** Project 1 complete. Live dashboard, full dbt + Dagster pipeline.

A pricing analysis project using the French Motor Third-Party Liability (freMTPL2) dataset. The stack goes from raw CSV → DuckDB → dbt → Dagster → Looker Studio.

---

## Dashboard

**[View the live dashboard →](https://datastudio.google.com/reporting/53a0cdc4-9106-4849-b45e-afa3ed74d13d)**

![Executive summary](docs/screenshots/dashboard_page1_executive_summary.png)

![Driver age and BonusMalus deep-dive](docs/screenshots/dashboard_page2_deep_dive.png)

![BonusMalus heatmap close-up](docs/screenshots/dashboard_heatmap_closeup.png)

> **Note on data source:** The dashboard connects to Google Sheets rather than DuckDB directly. Looker Studio needs a cloud-accessible source to generate a public link. The numbers are identical — it's a plumbing trade-off for shareability.

---

## Pipeline highlights

- **8 dbt models** across three layers: staging → intermediate → marts
- **30 dbt tests** — schema contracts, not-null checks, accepted values, and two custom singular tests
- **4 Dagster asset checks** — row count drift, null rate monitoring, cross-mart exposure reconciliation, and partition balance (all blocking, with documented failure modes)
- **4 advanced SQL showcase queries** — Pareto loss leakage, BM improvement paths, YoY segment movement, heatmap outlier detection
- **Partitioned execution** with documented DuckDB concurrency fix (read-only connections on asset checks to avoid write lock conflicts)
- **3 CSV mart exports** for the Looker Studio data source

---

## Headline findings

| KPI | Value |
|---|---|
| Portfolio capped burning cost | **€116 / policy-year** |
| Youth drivers (18–24) relativity | **2.5–3.0× average** |
| High-malus drivers (BM 101+) relativity | **4.9× average** |
| Driver age band spread | **3.8×** |
| BonusMalus band spread | **7.3×** (the stronger predictor) |

The book is running above target in two segments: young drivers and recently-penalised drivers (BonusMalus > 100). The majority cohort at BM=50 is adequately priced — the loss ratio problem is concentrated in a small tail. Year-on-year the numbers are stable, ruling out a single-year distortion.

---

## Dataset

**Source:** `freMTPL2freq` and `freMTPL2sev` from the `CASdatasets` R package (Charpentier et al.)
**Size:** 678,013 policies × 26,639 claims
**Period:** Single accident year, French private motor market
**Key variables:** Driver age, BonusMalus coefficient, vehicle age/power/brand, area/region, exposure (fraction of year)

*Raw CSVs are excluded from this repo (see `.gitignore`). Download instructions below.*

---

## Architecture

```
data/raw/                  ← freMTPL2freq.csv, freMTPL2sev.csv (not tracked)
    │
    ▼
DuckDB (mtpl.duckdb)       ← loaded via sql/load_raw.sql (not tracked)
    │
    ▼
dbt_mtpl/models/
    staging/               ← stg_freq, stg_sev
    intermediate/          ← int_capped_claims, int_policy_losses,
    │                          int_policy_with_exposure
    marts/                 ← mart_burning_cost_by_age,
                               mart_burning_cost_by_bonus_malus,
                               mart_age_x_vehage_heatmap
    │
    ▼
dagster_mtpl/              ← partitioned dbt assets + 4 asset checks
    │
    ▼
data/exports/              ← 3 CSV mart exports (tracked)
    │
    ▼
Looker Studio              ← public dashboard (via Google Sheets)
```

---

## Reproduce locally

Requires DuckDB (`brew install duckdb`) and Python 3.12+.

```bash
# 1. Clone and set up
git clone https://github.com/Taaronn/motor-pricing-analytics.git
cd motor-pricing-analytics
python -m venv venv && source venv/bin/activate
pip install dbt-duckdb dagster dagster-dbt

# 2. Download raw data (freMTPL2freq.csv, freMTPL2sev.csv)
#    Source: CASdatasets R package (Charpentier et al.)
#    Place both files in data/raw/

# 3. Load raw data into DuckDB
duckdb mtpl.duckdb < sql/load_raw.sql

# 4. Run dbt transformations and tests
cd dbt_mtpl
dbt run
dbt test

# 5. Launch the Dagster UI
cd ../dagster_mtpl
dagster dev

# 6. Export marts to CSV (for dashboard data source)
cd ..
duckdb mtpl.duckdb < sql/export_marts.sql

# 7. Run an exploration or showcase query
duckdb mtpl.duckdb < sql/exploration/01_burning_cost.sql
duckdb mtpl.duckdb < sql/showcase/01_pareto_loss_leakage.sql
```

---

## Project structure

```
01-pricing-mtpl/
├── data/
│   ├── raw/              ← not tracked (download separately)
│   └── exports/          ← 3 mart CSVs (tracked; dashboard source)
├── dbt_mtpl/             ← dbt project: 8 models, 30 tests
│   └── models/
│       ├── staging/
│       ├── intermediate/
│       └── marts/
├── dagster_mtpl/         ← Dagster: partitioned assets, 4 checks
├── docs/
│   └── screenshots/      ← dashboard screenshots
├── sql/
│   ├── load_raw.sql
│   ├── export_marts.sql
│   ├── exploration/      ← 7 analytical SQL files
│   └── showcase/         ← 4 advanced SQL queries
├── dashboard_plan.md     ← dashboard spec and data source decisions
└── README.md
```

---

## Methodology notes

**Loss capping at P99 (€16,794)**
Claims are capped before any segment analysis. One catastrophic claim (€4.07M) moved the uncapped youth burning cost from €940 to €286 after capping — a 70% reduction. All segments use the same cap so comparisons are consistent.

**How bands were chosen**
BonusMalus bands were set after inspecting the empirical distribution. The 101+ band merges four thin sub-bands (101–125, 126–150, 151–200, 200+) that each fell below ~3,000 policies individually. Vehicle age bands (0–1, 2–5, 6–10, 11–15, 16+) were validated with a cell-count check — all 35 age × vehicle-age cells exceed 500 policies. Two thin cells (18–24 × 16+, 75+ × 16+) are flagged in the query comments.

**Data quality**
~195 claims in `raw_sev` have `IDpol` values with no matching policy in `raw_freq`. Kept in portfolio totals, excluded from segment analyses that need a LEFT JOIN to exposure. See `data_quality.md` for details.

**Open question**
The vehicle age effect isn't monotonic. In the 25–34 driver age band, burning cost peaks at VehAge 6–10 rather than falling steadily. Worth discussing with underwriters before using this in a rate change.

---

## Stack

| Layer | Tool |
|---|---|
| Query & storage | DuckDB |
| Transformation | dbt-core + dbt-duckdb |
| Orchestration | Dagster |
| Dashboard | Looker Studio |
| Language | SQL, Python |
| Version control | Git / GitHub |
