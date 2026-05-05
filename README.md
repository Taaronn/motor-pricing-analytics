# Motor TPL Pricing Analysis

> **Business question:** Which segments are driving our motor book's loss ratio above target, and what rate change is indicated to bring it back in line?

**Status:** Stage 1 complete — exploratory analysis. dbt pipeline and dashboard in progress.

A data analytics project built on the French Motor Third-Party Liability (freMTPL2) dataset, demonstrating actuarial pricing analysis with SQL and DuckDB.

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

## Architecture (current)

```
data/raw/                  ← freMTPL2freq.csv, freMTPL2sev.csv (not tracked)
    │
    ▼
DuckDB (mtpl.duckdb)       ← loaded via sql/load_raw.sql; not tracked (reproduced locally)
    │
    ▼
sql/exploration/           ← 7 standalone SQL files
                              01 portfolio burning cost
                              02 burning cost by driver age (uncapped)
                              03 youth loss distribution diagnostic
                              04 loss distribution (P50–P99.9)
                              05 burning cost by driver age (capped at P99)
                              06 burning cost by BonusMalus band (capped)
                              07 burning cost heatmap: driver age × vehicle age (capped)
```

**Coming next:** dbt transformation layer (staging → intermediate → marts), Dagster orchestration, Looker Studio dashboard.

---

## Methodology notes

**Loss capping at P99 (€16,794)**
Individual claims are capped before any segment analysis. One catastrophic claim (€4.07M) distorted the uncapped youth burning cost from €940 to €286 after capping — a 70% reduction. All segment comparisons use the same P99 cap so figures are directly comparable.

**Banding decisions are data-driven, not arbitrary**
- BonusMalus bands were chosen after inspecting the empirical distribution. The 101+ band collapses four thin sub-bands (101–125, 126–150, 151–200, 200+) that each fell below the ~3,000-policy statistical reliability threshold.
- Vehicle age bands (0–1, 2–5, 6–10, 11–15, 16+) were validated with a cell-count check before finalising. All 35 age × vehicle-age cells exceed 500 policies; two thin cells (18–24 × 16+, 75+ × 16+) are flagged in the heatmap query comments.

**Known data quality issues**
~195 claims in `raw_sev` have `IDpol` values with no matching policy in `raw_freq`. Retained in portfolio totals but excluded from segment analyses requiring a LEFT JOIN to exposure.

**To investigate with underwriters**
The vehicle age effect is non-linear and interacts with driver age. In the 25–34 band, burning cost peaks at VehAge 6–10 rather than declining monotonically. This warrants underwriter input before drawing pricing conclusions.

---

## Reproduce locally

Requires DuckDB installed (`brew install duckdb` on macOS).

```bash
# 1. Clone the repo
git clone https://github.com/Taaronn/motor-pricing-analytics.git
cd motor-pricing-analytics

# 2. Download raw data (freMTPL2freq.csv, freMTPL2sev.csv)
#    Source: CASdatasets R package (Charpentier et al.)
#    Place both files in data/raw/

# 3. Load raw data into DuckDB
duckdb mtpl.duckdb < sql/load_raw.sql

# 4. Run an exploration query
duckdb mtpl.duckdb < sql/exploration/01_burning_cost.sql
```

---

## Project structure

```
01-pricing-mtpl/
├── data/
│   └── raw/              ← not tracked (download separately)
├── sql/
│   ├── load_raw.sql      ← bootstrap: loads CSVs into DuckDB
│   └── exploration/      ← 7 analytical SQL files
└── README.md
```

---

## Tools & stack

| Layer | Tool |
|---|---|
| Query & storage | DuckDB |
| Language | SQL |
| Version control | Git / GitHub |
