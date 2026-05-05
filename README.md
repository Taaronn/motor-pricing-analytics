# Motor TPL Pricing Analysis

> **Business question:** Which segments are driving our motor book's loss ratio above target, and what rate change is indicated to bring it back in line?

A end-to-end data engineering and actuarial analytics project built on the French Motor Third-Party Liability (freMTPL2) dataset. Demonstrates the full pipeline from raw claims data through transformation, testing, orchestration, and interactive dashboarding.

---

## Headline findings

| KPI | Value |
|---|---|
| Portfolio capped burning cost | **€116 / policy-year** |
| Youth drivers (18–24) relativity | **2.5–3.0× average** |
| High-malus drivers (BM 101+) relativity | **4.9× average** |

The book is running above target primarily due to two segments: young drivers and recently-penalised drivers (BonusMalus > 100). Critically, 57% of the book sits at the BonusMalus floor (BM=50) generating just €78/year — meaning the majority cohort is adequately priced, and the loss ratio problem is concentrated in a small but poorly-rated tail.

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
DuckDB (mtpl.duckdb)       ← loaded via seed script; not tracked (reproduced locally)
    │
    ▼
sql/exploration/           ← 7 standalone SQL files — burning cost, loss distribution,
    │                         BonusMalus segmentation, age × vehicle age heatmap
    ▼
dbt_mtpl/                  ← transformation layer
    ├── staging/            ← clean, dedupe, validate raw tables
    ├── intermediate/       ← join exposure to capped losses at policy level
    └── marts/              ← pre-aggregated tables the dashboard hits directly
         ├── mart_burning_cost_by_segment
         └── mart_rate_indication
    │
    ▼
dagster_mtpl/              ← orchestration: load → dbt → quality checks → summary
    │
    ▼
data/exports/              ← CSVs exported from mart tables for Looker Studio
    │
    ▼
Looker Studio dashboard    ← [link placeholder]
```

---

## Methodology notes

**Loss capping at P99 (€16,794)**
Individual claims are capped before any segment analysis. One catastrophic claim (€4.07M) distorted the uncapped youth burning cost from €940 to €286 after capping — a 70% reduction. All comparisons across segments use the same P99 cap so figures are directly comparable.

**Banding decisions are data-driven, not arbitrary**
- BonusMalus bands were chosen after inspecting the empirical distribution. The 101+ band collapses four thin sub-bands (101–125, 126–150, 151–200, 200+) that each fell below the ~3,000-policy statistical reliability threshold.
- Vehicle age bands (0–1, 2–5, 6–10, 11–15, 16+) were validated with a cell-count check before finalising. All 35 age × vehicle-age cells exceed 500 policies; two thin cells (18–24 × 16+, 75+ × 16+) are flagged in the heatmap query.

**Known data quality issues**
~195 claims in `raw_sev` have `IDpol` values with no matching policy in `raw_freq`. These are retained in portfolio totals but excluded from segment analyses that require a LEFT JOIN to exposure. Documented in `data/data_quality.md`.

**To investigate with underwriters**
The vehicle age effect is non-linear and interacts with driver age. In the 25–34 band, burning cost peaks at VehAge 6–10 rather than declining monotonically. This may reflect a selection effect (careful drivers keeping older cars vs. active drivers trading up) and warrants underwriter input before drawing pricing conclusions.

---

## Reproduce locally

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/actuarial-mtpl-pricing.git
cd actuarial-mtpl-pricing

# 2. Download raw data (freMTPL2freq.csv, freMTPL2sev.csv)
#    Source: https://cas.uqam.ca/ → CASdatasets → freMTPL2
#    Place both files in data/raw/

# 3. Create virtual environment and install dependencies
python3.12 -m venv venv
source venv/bin/activate
pip install dbt-core dbt-duckdb dagster dagster-webserver pandas pyarrow

# 4. Load raw data into DuckDB
duckdb mtpl.duckdb < sql/load_raw.sql

# 5. Run exploration queries
duckdb mtpl.duckdb < sql/exploration/01_burning_cost.sql

# 6. Run the full dbt pipeline
cd dbt_mtpl
dbt deps
dbt run
dbt test

# 7. Launch Dagster UI
cd ../dagster_mtpl
dagster dev

# 8. View dbt docs
cd ../dbt_mtpl
dbt docs generate
dbt docs serve
```

---

## Project structure

```
01-pricing-mtpl/
├── data/
│   ├── raw/              ← not tracked (download separately)
│   └── exports/          ← mart CSVs for Looker Studio (tracked)
├── sql/
│   ├── exploration/      ← 7 analytical SQL files
│   └── showcase/         ← advanced SQL demos (window functions, recursive CTEs)
├── dbt_mtpl/             ← dbt project (staging → intermediate → marts)
├── dagster_mtpl/         ← Dagster orchestration
├── data_quality.md       ← documented data issues and cleaning decisions
├── DASHBOARD_PLAN.md     ← chart-by-chart Looker Studio build guide
└── README.md
```

---

## Dashboard

**Looker Studio:** [link to be added after export]

Built on `mart_burning_cost_by_segment` and `mart_rate_indication`. See `DASHBOARD_PLAN.md` for full chart specifications and the narrative flow.

---

## Tools & stack

| Layer | Tool |
|---|---|
| Query & storage | DuckDB |
| Transformation | dbt-core + dbt-duckdb |
| Orchestration | Dagster |
| Language | SQL, Python 3.12 |
| Dashboard | Looker Studio |
| Version control | Git / GitHub |
